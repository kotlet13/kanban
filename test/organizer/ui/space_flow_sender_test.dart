import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/presentation/shared/sharing_members.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';
import 'onboarding_ui_test.dart' show pumpPanel;
import 'sharing_ui_fixture.dart';
import 'sharing_ui_test.dart' show enterSharing, tapSharing;

const _scope = SharedScope(
  id: sharingScopeId,
  name: 'Captured home',
  kind: SharedScopeKind.household,
  role: SharedRole.owner,
  accessPolicyVersion: 3,
);

class _Sender extends SharingUiController {
  _Sender()
    : super(
        initial: CollaborationState(
          session: sharingSession(),
          selectedSpaceId: sharingScopeId,
          scopedInvitationsSupported: true,
          usernameInvitationsSupported: true,
          invitationResendSupported: true,
          scopes: [_scope],
        ),
      );
  String? recipient, invitationRequest;
  int sends = 0, resends = 0;
  bool fail = false;
  final resendIds = <String>[];
  final resendLanguages = <String>[];
  SharedInvitation invitation() => SharedInvitation(
    id: 'old-invite',
    scopeId: sharingScopeId,
    recipientUsername: 'bob',
    role: SharedRole.member,
    contractVersion: 3,
    accessScope: 'space',
    expiresAt: DateTime.utc(2099),
  );
  @override
  Future<List<SharedMember>> members(String scopeId) async => [];
  @override
  Future<List<SharedInvitation>> invitations(String scopeId) async => [
    invitation(),
  ];
  @override
  Future<SharedInvitation> createRecipientInvitation({
    required String scopeId,
    required String recipient,
    SharedRole role = SharedRole.member,
    String language = 'sl',
    String? accessScope,
    String? requestId,
  }) async {
    expect(scopeId, sharingScopeId);
    expect(accessScope, 'space');
    sends++;
    this.recipient = recipient;
    invitationRequest = requestId;
    return invitation();
  }

  @override
  Future<SharedInvitation> resendInvitation({
    required String scopeId,
    required String invitationId,
    required String requestId,
    String language = 'sl',
  }) async {
    resends++;
    resendIds.add(requestId);
    resendLanguages.add(language);
    expect(invitationId, 'old-invite');
    if (fail) throw const CollaborationException('network');
    return invitation();
  }
}

void main() {
  for (final width in [320.0, 1280.0]) {
    testWidgets(
      'direct username form is scoped, concise, and works without SMTP at $width',
      (tester) async {
        final sender = _Sender();
        await pumpPanel(
          tester,
          sender,
          SharingMembersPage(scope: _scope, session: sharingSession()),
          width: width,
          textScale: width == 320 ? 1.4 : 1,
        );
        await tester.ensureVisible(find.text('Povabi osebo'));
        await tester.tap(find.text('Povabi osebo'));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('sharing-scope')), findsNothing);
        expect(find.byType(TextFormField), findsOneWidget);
        expect(
          find.textContaining('sedanji in prihodnji projekti'),
          findsOneWidget,
        );
        expect(
          find.textContaining('vabi in odstranjuje člane'),
          findsOneWidget,
        );
        expect(
          find.textContaining('briše vsebino ter finance'),
          findsOneWidget,
        );
        await enterSharing(tester, 'recipient', 'bob');
        await tapSharing(tester, 'sharing-submit');
        expect(sender.sends, 1);
        expect(sender.recipient, 'bob');
        expect(
          find.text('Povabilo čaka v prejemnikovem računu.'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'resend confirms old-link replacement and retry keeps atomic request',
    (tester) async {
      final sender = _Sender()..fail = true;
      await pumpPanel(
        tester,
        sender,
        SharingMembersPage(scope: _scope, session: sharingSession()),
        width: 390,
      );
      Future<void> resend({bool english = false}) async {
        await tester.ensureVisible(
          find.byKey(const ValueKey('sharing-resend-invitation-old-invite')),
        );
        await tester.tap(
          find.byKey(const ValueKey('sharing-resend-invitation-old-invite')),
        );
        await tester.pumpAndSettle();
        expect(
          find.textContaining(
            english
                ? 'The previous link will stop working'
                : 'Prejšnja povezava bo prenehala veljati',
          ),
          findsOneWidget,
        );
        await tester.tap(
          find.widgetWithText(
            FilledButton,
            english ? 'Send again' : 'Pošlji znova',
          ),
        );
        await tester.pumpAndSettle();
      }

      await resend();
      expect(sender.resends, 1);
      sender.fail = false;
      await resend();
      expect(sender.resendIds, hasLength(2));
      expect(sender.resendIds.first, sender.resendIds.last);
      expect(sender.resendLanguages, ['sl', 'sl']);
      expect(tester.takeException(), isNull);
    },
  );
}
