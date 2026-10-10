import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';
import 'package:kanban/organizer/presentation/shared/space_settings_page.dart';
import 'package:kanban/organizer/presentation/shared/sharing_workspace.dart';

import 'onboarding_ui_test.dart' show pumpPanel;
import 'sharing_ui_fixture.dart';

const home = SharedScope(
  id: sharingScopeId,
  name: 'Naš dom',
  kind: SharedScopeKind.household,
  role: SharedRole.member,
  accessPolicyVersion: 3,
);
const child = SharedScope(
  id: 'project',
  name: 'Skupni vrt',
  kind: SharedScopeKind.project,
  role: SharedRole.member,
  accessPolicyVersion: 3,
  parentScopeId: sharingScopeId,
  parentScopeKind: SharedScopeKind.household,
  projectRootId: 'project',
);

class ProjectSharingController extends SharingUiController {
  ProjectSharingController({
    this.allowed = true,
    this.lost = false,
    bool pending = false,
  }) : super(
         initial: CollaborationState(
           session: sharingSession(),
           selectedSpaceId: sharingScopeId,
           scopes: [home],
           data: {sharingScopeId: sharingData()},
           spaceProjectMembershipSupported: true,
           scopedInvitationsSupported: true,
           emailInvitationsSupported: true,
           projectSharingPendingScopeIds: pending ? {sharingScopeId} : {},
         ),
       );
  final bool allowed, lost;
  int applications = 0, resumptions = 0;
  @override
  Future<ProjectSharingPreview> previewProjectSharing(
    String scopeId,
    String projectId,
  ) async => ProjectSharingPreview(
    scopeId: scopeId,
    projectId: projectId,
    projectName: 'Skupni vrt',
    canApply: allowed,
    previewHash: 'a' * 64,
    movedRecordIds: ['project', 'task'],
    movedFinanceRecordIds: ['cost'],
    movedReminderIds: ['reminder'],
    financeAccounts: [
      {
        'id': 'qa-account',
        'name': 'Projektni račun',
        'currency': 'EUR',
        'openingBalanceMinor': 1200,
        'openingBalanceAt': '2026-01-01T00:00:00Z',
      },
    ],
    householdPeople: [
      {
        'id': 'qa-person',
        'name': 'Vrtni sodelavec',
        'notes': 'Opomba projekta',
      },
    ],
  );
  @override
  Future<SharedScope> applyProjectSharing(
    ProjectSharingPreview preview, {
    String? requestId,
  }) async {
    applications++;
    if (lost) throw const CollaborationException('network');
    return child;
  }

  @override
  Future<SharedScope?> resumeProjectSharing(String id) async {
    resumptions++;
    return child;
  }
}

void main() {
  for (final width in [320.0, 1280.0]) {
    testWidgets('household project sharing is reviewed before apply $width', (
      tester,
    ) async {
      final controller = ProjectSharingController();
      String? selected;
      await pumpPanel(
        tester,
        controller,
        SpaceSettingsPage(
          selectedScopeId: sharingScopeId,
          onScopeSelected: (id) => selected = id,
          onConnect: () {},
        ),
        width: width,
      );
      final review = find.byKey(
        const ValueKey('project-sharing-review-project'),
      );
      await tester.ensureVisible(review);
      await tester.tap(review);
      await tester.pumpAndSettle();
      expect(controller.applications, 0);
      expect(find.text('Projektni račun'), findsOneWidget);
      expect(find.textContaining('Začetno stanje: 12.00 EUR'), findsOneWidget);
      expect(find.text('Vrtni sodelavec'), findsOneWidget);
      expect(
        find.text('Zapisi: 2 · finančni zapisi: 1 · opomniki: 1'),
        findsOneWidget,
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('project-sharing-confirm')),
      );
      await tester.tap(find.byKey(const ValueKey('project-sharing-confirm')));
      await tester.pumpAndSettle();
      expect(controller.applications, 1);
      expect(selected, 'project');
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'cross project dependencies cannot be replaced by household invitation',
    (tester) async {
      final controller = ProjectSharingController(allowed: false);
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
      final review = find.byKey(
        const ValueKey('project-sharing-review-project'),
      );
      await tester.ensureVisible(review);
      await tester.tap(review);
      await tester.pumpAndSettle();
      expect(find.textContaining('vsebino zunaj projekta'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('project-sharing-confirm')),
        findsNothing,
      );
      expect(controller.applications, 0);
      expect(controller.emailInviteTargets, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'uncertain project sharing can be recovered after reopening settings',
    (tester) async {
      final controller = ProjectSharingController(pending: true);
      String? selected;
      await pumpPanel(
        tester,
        controller,
        SpaceSettingsPage(
          selectedScopeId: sharingScopeId,
          onScopeSelected: (id) => selected = id,
          onConnect: () {},
        ),
      );
      final resume = find.byKey(const ValueKey('project-sharing-resume'));
      await tester.ensureVisible(resume);
      await tester.tap(resume);
      await tester.pumpAndSettle();
      expect(controller.resumptions, 1);
      expect(selected, 'project');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('household parent shows child projects and their tasks', (
    tester,
  ) async {
    final controller = SharingUiController(
      initial: CollaborationState(
        session: sharingSession(),
        selectedSpaceId: sharingScopeId,
        scopes: [home, child],
        data: {'project': sharingData()},
        spaceProjectMembershipSupported: true,
      ),
    );
    await pumpPanel(
      tester,
      controller,
      SharingWorkspace(
        view: SharingView.projects,
        selectedScopeId: sharingScopeId,
        onScopeSelected: (_) {},
        onConnect: () {},
      ),
    );
    expect(
      find.byKey(const ValueKey('organization-project-project')),
      findsOneWidget,
    );
    await pumpPanel(
      tester,
      controller,
      SharingWorkspace(
        view: SharingView.tasks,
        selectedScopeId: sharingScopeId,
        onScopeSelected: (_) {},
        onConnect: () {},
      ),
    );
    expect(find.text('Pripravi zemljo'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
