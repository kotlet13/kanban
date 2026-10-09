import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';
import 'package:kanban/organizer/presentation/shared/space_settings_page.dart';
import 'package:kanban/organizer/presentation/shared/sharing_workspace.dart';
import 'onboarding_ui_test.dart' show pumpPanel;
import 'sharing_ui_fixture.dart';

const orgScope = SharedScope(
  id: sharingScopeId,
  name: 'QA organizacija',
  kind: SharedScopeKind.organization,
  role: SharedRole.owner,
  accessPolicyVersion: 1,
);

class AccessController extends SharingUiController {
  AccessController({
    SharedRole role = SharedRole.owner,
    int policy = 1,
    bool expired = false,
  }) : super(
         initial: CollaborationState(
           session: expired
               ? AccountSession.fromJson({
                   ...sharingSession().toJson(),
                   'expiresAt': DateTime.utc(2020).toIso8601String(),
                 })
               : sharingSession(),
           selectedSpaceId: sharingScopeId,
           scopes: [
             SharedScope.fromJson({
               ...orgScope.toJson(),
               'role': role.name,
               'accessPolicyVersion': policy,
             }),
           ],
         ),
       );
  int applied = 0;
  final leadership = <bool>[];
  @override
  Future<OrganizationAccessPreview> previewOrganizationAccess(
    String id,
  ) async => OrganizationAccessPreview(
    scopeId: id,
    fromVersion: 1,
    toVersion: 2,
    previewHash: 'a' * 64,
    projects: [
      OrganizationAccessProject(
        scopeId: 'project',
        name: 'QA projekt',
        financeWasEnabled: true,
        additionalReaders: [
          const OrganizationAccessReader(
            accountId: 'extra',
            displayName: 'QA član z dodatnim vpogledom',
            accessSource: 'projectMembership',
          ),
        ],
      ),
    ],
  );
  @override
  Future<SharedScope> applyOrganizationAccess(
    String id,
    String hash, {
    String? requestId,
  }) async {
    applied++;
    return orgScope;
  }

  @override
  Future<List<SharedMember>> members(String id) async => [
    const SharedMember(
      userId: 1,
      accountId: 'owner',
      username: 'owner',
      displayName: 'QA lastnik',
      role: SharedRole.owner,
      active: true,
      organizationLeader: true,
    ),
    const SharedMember(
      userId: 2,
      accountId: 'member',
      username: 'member',
      displayName: 'QA član',
      role: SharedRole.member,
      active: true,
    ),
  ];
  @override
  Future<void> setOrganizationLeader(
    String id,
    String accountId,
    bool enabled, {
    String? requestId,
  }) async {
    leadership.add(enabled);
  }
}

void main() {
  testWidgets(
    'organization owner reviews additional finance readers before applying',
    (tester) async {
      final controller = AccessController();
      await pumpPanel(
        tester,
        controller,
        SpaceSettingsPage(
          selectedScopeId: sharingScopeId,
          onScopeSelected: (_) {},
          onConnect: () {},
        ),
        width: 390,
      );
      await tester.tap(
        find.byKey(const ValueKey('organization-access-review')),
      );
      await tester.pumpAndSettle();
      expect(controller.applied, 0);
      expect(find.text('QA član z dodatnim vpogledom'), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const ValueKey('organization-access-confirm')),
      );
      await tester.tap(
        find.byKey(const ValueKey('organization-access-confirm')),
      );
      await tester.pumpAndSettle();
      expect(controller.applied, 1);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'account switch closes reviewed access preview and cannot apply',
    (tester) async {
      final controller = AccessController();
      await pumpPanel(
        tester,
        controller,
        SpaceSettingsPage(
          selectedScopeId: sharingScopeId,
          onScopeSelected: (_) {},
          onConnect: () {},
        ),
      );
      await tester.tap(
        find.byKey(const ValueKey('organization-access-review')),
      );
      await tester.pumpAndSettle();
      controller.switchAccount();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('organization-access-confirm')),
        findsNothing,
      );
      expect(controller.applied, 0);
    },
  );
  for (final role in [SharedRole.member, SharedRole.viewer]) {
    testWidgets(
      'organization $role cannot migrate rights or grant leadership',
      (tester) async {
        await pumpPanel(
          tester,
          AccessController(role: role, policy: 2),
          SpaceSettingsPage(
            selectedScopeId: sharingScopeId,
            onScopeSelected: (_) {},
            onConnect: () {},
          ),
        );
        expect(
          find.byKey(const ValueKey('organization-access-review')),
          findsNothing,
        );
        expect(find.byIcon(Icons.manage_accounts_outlined), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'only owner grants a reviewed leadership role and cannot remove owner',
    (tester) async {
      final controller = AccessController(policy: 2);
      await pumpPanel(
        tester,
        controller,
        SpaceSettingsPage(
          selectedScopeId: sharingScopeId,
          onScopeSelected: (_) {},
          onConnect: () {},
        ),
      );
      expect(
        find.byKey(const ValueKey('organization-leader-owner')),
        findsNothing,
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('organization-leader-member')),
      );
      await tester.tap(
        find.byKey(const ValueKey('organization-leader-member')),
      );
      await tester.pumpAndSettle();
      expect(controller.leadership, isEmpty);
      await tester.tap(
        find.widgetWithText(FilledButton, 'Dodeli vodstveno vlogo'),
      );
      await tester.pumpAndSettle();
      expect(controller.leadership, [true]);
    },
  );
  testWidgets(
    'expired session keeps downloaded shopping editable under known ACL',
    (tester) async {
      final session = AccountSession.fromJson({
        ...sharingSession().toJson(),
        'expiresAt': DateTime.utc(2020).toIso8601String(),
      });
      final controller = SharingUiController(
        initial: CollaborationState(
          session: session,
          sessionInvalid: true,
          localAccessAllowed: true,
          selectedSpaceId: sharingScopeId,
          scopes: [sharingScope()],
          data: {sharingScopeId: sharingData()},
        ),
      );
      await pumpPanel(
        tester,
        controller,
        SharingWorkspace(
          view: SharingView.shopping,
          selectedScopeId: sharingScopeId,
          onScopeSelected: (_) {},
          onConnect: () {},
        ),
      );
      expect(find.text('Mleko za skupno gospodinjstvo'), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const ValueKey('shopping-item-field')),
      );
      await tester.enterText(
        find.byKey(const ValueKey('shopping-item-field')),
        'QA lokalni dodatek',
      );
      await tester.tap(find.byTooltip('Dodaj izdelek'));
      await tester.pumpAndSettle();
      expect(controller.calls, contains('item:QA lokalni dodatek'));
      expect(find.text('QA lokalni dodatek'), findsOneWidget);
    },
  );
  testWidgets('confirmed device revocation hides cached space contents', (
    tester,
  ) async {
    final controller = SharingUiController(
      initial: CollaborationState(
        session: sharingSession(),
        localAccessAllowed: false,
        selectedSpaceId: sharingScopeId,
        scopes: [sharingScope()],
        data: {sharingScopeId: sharingData()},
      ),
    );
    await pumpPanel(
      tester,
      controller,
      SharingWorkspace(
        view: SharingView.shopping,
        selectedScopeId: sharingScopeId,
        onScopeSelected: (_) {},
        onConnect: () {},
      ),
    );
    expect(find.text('Mleko za skupno gospodinjstvo'), findsNothing);
    expect(find.byKey(const ValueKey('shopping-item-field')), findsNothing);
  });
}
