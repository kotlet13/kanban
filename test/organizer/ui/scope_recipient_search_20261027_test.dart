import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/presentation/shared/sharing_members.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';

import 'onboarding_ui_test.dart' show pumpPanel;
import 'sharing_ui_fixture.dart';
import 'sharing_ui_test.dart' show enterSharing, tapSharing;

const scope = SharedScope(
  id: sharingScopeId,
  name: 'Captured household',
  kind: SharedScopeKind.household,
  role: SharedRole.owner,
  accessPolicyVersion: 3,
);
const recipient = InvitationRecipient(
  accountId: '00000000-0000-4000-a000-000000000999',
  username: 'selected_person',
  displayName: 'Selected Person',
);

class Sender extends SharingUiController {
  Sender()
    : super(
        initial: CollaborationState(
          session: sharingSession(),
          selectedSpaceId: sharingScopeId,
          scopedInvitationsSupported: true,
          usernameInvitationsSupported: true,
          recipientSearchSupported: true,
          scopes: [scope],
        ),
      );
  final requests = <String>[];
  String? sentUsername, sentAccount;
  @override
  Future<List<SharedMember>> members(String scopeId) async => [];
  @override
  Future<List<SharedInvitation>> invitations(String scopeId) async => [];
  @override
  Future<List<InvitationRecipient>> searchInvitationRecipients({
    required String scopeId,
    required String query,
  }) async {
    expect(scopeId, sharingScopeId);
    requests.add(query);
    return [recipient];
  }

  @override
  Future<SharedInvitation> createRecipientInvitation({
    required String scopeId,
    required String recipient,
    String? recipientAccountId,
    SharedRole role = SharedRole.member,
    String language = 'sl',
    String? requestId,
    String? accessScope,
  }) async {
    expect(scopeId, sharingScopeId);
    expect(accessScope, 'space');
    expect(requestId, isNotEmpty);
    sentUsername = recipient;
    sentAccount = recipientAccountId;
    return SharedInvitation(
      id: 'search-invite',
      scopeId: scopeId,
      recipientUsername: recipient,
      role: role,
      contractVersion: 3,
      accessScope: 'space',
      expiresAt: DateTime.utc(2099),
    );
  }
}

void main() {
  testWidgets(
    'invitation form searches public names selects exact account and submits through ordinary consent flow',
    (tester) async {
      final sender = Sender();
      await pumpPanel(
        tester,
        sender,
        SharingMembersPage(scope: scope, session: sharingSession()),
        width: 390,
      );
      await tester.ensureVisible(find.text('Povabi osebo'));
      await tester.tap(find.text('Povabi osebo'));
      await tester.pumpAndSettle();
      await enterSharing(tester, 'recipient', 'Selected');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(sender.requests, ['Selected']);
      await tester.ensureVisible(find.text('Selected Person'));
      await tester.tap(find.text('Selected Person'));
      await tester.pumpAndSettle();
      expect(find.text('selected_person'), findsOneWidget);
      await tapSharing(tester, 'sharing-submit');
      expect(sender.sentUsername, 'selected_person');
      expect(sender.sentAccount, recipient.accountId);
      expect(
        find.text('Povabilo čaka v prejemnikovem računu.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
