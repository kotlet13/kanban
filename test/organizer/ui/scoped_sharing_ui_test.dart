import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';
import 'package:kanban/organizer/presentation/shared/space_settings_page.dart';
import 'package:kanban/organizer/presentation/shared/sharing_invitation_details.dart';

import 'onboarding_ui_test.dart' show pumpPanel;
import 'sharing_ui_fixture.dart';
import 'sharing_ui_test.dart' show enterSharing, tapSharing;

const parentId = sharingScopeId;
const childId = 'project-child';
const rootScope = SharedScope(
  id: parentId,
  name: 'Celotna organizacija',
  kind: SharedScopeKind.organization,
  role: SharedRole.member,
  accessPolicyVersion: 3,
);
const childScope = SharedScope(
  id: childId,
  name: 'Samo prenova',
  kind: SharedScopeKind.project,
  parentScopeId: parentId,
  parentScopeKind: SharedScopeKind.organization,
  role: SharedRole.member,
  accessPolicyVersion: 3,
  accessSource: 'spaceMembership',
);

class ScopedController extends SharingUiController {
  ScopedController({
    SharedScope parent = rootScope,
    String selected = parentId,
    bool supported = true,
    this.dualSource = false,
  }) : super(
         initial: CollaborationState(
           session: sharingSession(),
           selectedSpaceId: selected,
           emailInvitationsSupported: true,
           scopedInvitationsSupported: supported,
           spaceProjectMembershipSupported: supported,
           scopes: [parent, childScope],
         ),
       );
  final bool dualSource;
  @override
  Future<List<SharedMember>> members(String scopeId) async => [
    const SharedMember(
      userId: 1,
      accountId: 'owner',
      username: 'owner',
      displayName: 'Lastnik',
      role: SharedRole.owner,
      active: true,
    ),
    SharedMember(
      userId: 2,
      accountId: 'inherited',
      username: 'inherited',
      displayName: 'Član prostora',
      role: SharedRole.member,
      active: true,
      accessSource: dualSource ? 'direct' : 'spaceMembership',
      membershipScopeId: dualSource ? childId : parentId,
      accessSources: dualSource
          ? ['direct', 'spaceMembership']
          : ['spaceMembership'],
    ),
  ];
}

SpaceSettingsPage settings(String id) => SpaceSettingsPage(
  selectedScopeId: id,
  onScopeSelected: (_) {},
  onConnect: () {},
);

void main() {
  for (final width in [320.0, 1280.0]) {
    testWidgets('member selects whole space or project separately at $width', (
      tester,
    ) async {
      final controller = ScopedController();
      final semantics = tester.ensureSemantics();
      await pumpPanel(
        tester,
        controller,
        settings(parentId),
        width: width,
        textScale: width == 320 ? 1.4 : 1,
      );
      expect(
        find.byKey(const ValueKey('organization-access-review')),
        findsNothing,
      );
      await tester.ensureVisible(find.text('Povabi osebo'));
      await tester.tap(find.text('Povabi osebo'));
      await tester.pumpAndSettle();
      tester.view.viewInsets = FakeViewPadding(bottom: width == 320 ? 280 : 0);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel(RegExp('Obseg povabila')), findsWidgets);
      expect(
        find.textContaining('obstoječih in prihodnjih projektov'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.byKey(const ValueKey('sharing-scope')));
      await tester.tap(find.byKey(const ValueKey('sharing-scope')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Samo projekt · Samo prenova').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('ne dodeli članstva'), findsOneWidget);
      expect(find.textContaining('ustvarja, ureja in briše'), findsOneWidget);
      await enterSharing(tester, 'recipient', 'recipient@example.test');
      await tapSharing(tester, 'sharing-submit');
      expect(controller.emailInviteTargets, [
        (childId, 'project', SharedRole.member),
      ]);
      semantics.dispose();
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'inherited project members show source without a removal action',
    (tester) async {
      final controller = ScopedController(selected: childId);
      await pumpPanel(tester, controller, settings(childId), width: 390);
      expect(
        find.textContaining('Dostop iz članstva v celotnem prostoru'),
        findsOneWidget,
      );
      expect(find.byTooltip('Odstrani člana'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('dual-source project removal affects only direct membership', (
    tester,
  ) async {
    final controller = ScopedController(selected: childId, dualSource: true);
    await pumpPanel(tester, controller, settings(childId), width: 390);
    expect(
      find.textContaining(
        'Dostop iz članstva v celotnem prostoru · Članstvo v projektu',
      ),
      findsOneWidget,
    );
    final remove = find.byTooltip('Odstrani neposredno članstvo v projektu');
    await tester.ensureVisible(remove);
    await tester.tap(remove);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Dostop iz članstva v celotnem prostoru ostane'),
      findsOneWidget,
    );
    await tester.tap(
      find.widgetWithText(
        FilledButton,
        'Odstrani neposredno članstvo v projektu',
      ),
    );
    await tester.pumpAndSettle();
    expect(controller.calls, contains('remove:2'));
    expect(tester.takeException(), isNull);
  });
  testWidgets('old policy cannot send an invitation promising full space', (
    tester,
  ) async {
    const old = SharedScope(
      id: parentId,
      name: 'Stara organizacija',
      kind: SharedScopeKind.organization,
      role: SharedRole.member,
      accessPolicyVersion: 2,
    );
    final controller = ScopedController(parent: old);
    await pumpPanel(tester, controller, settings(parentId));
    expect(find.textContaining('starejša pravila dostopa'), findsOneWidget);
    expect(find.text('Povabi osebo'), findsNothing);
  });
  testWidgets(
    'scoped acceptance explains project only and member administration',
    (tester) async {
      await pumpPanel(
        tester,
        ScopedController(),
        SharingInvitationDetails(
          invitation: SharedInvitationPreview(
            scopeName: 'Samo prenova',
            scopeId: childId,
            kind: SharedScopeKind.project,
            recipientUsername: '',
            role: SharedRole.member,
            expiresAt: DateTime.utc(2099),
            registrationAllowed: true,
            contractVersion: 3,
            accessScope: 'project',
          ),
        ),
      );
      expect(find.text('Samo projekt'), findsOneWidget);
      expect(find.textContaining('ne dodeli članstva'), findsOneWidget);
      expect(
        find.textContaining('nastavitve, povabila in člane'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
