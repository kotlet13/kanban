import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/presentation/shared/sharing_workspace.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';

import 'onboarding_ui_test.dart' show pumpPanel;
import 'sharing_ui_fixture.dart';

class ProjectMenuController extends SharingUiController {
  ProjectMenuController({
    SharedRole role = SharedRole.owner,
    bool inline = false,
  }) : super(
         initial: CollaborationState(
           session: sharingSession(),
           selectedSpaceId: sharingScopeId,
           scopes: [
             SharedScope(
               id: sharingScopeId,
               name: 'Spletna stran',
               kind: inline
                   ? SharedScopeKind.household
                   : SharedScopeKind.project,
               projectRootId: inline ? null : 'project',
               role: role,
             ),
           ],
           data: {
             sharingScopeId: SharedScopeData(projects: sharingData().projects),
           },
           scopeArchivingSupported: true,
           projectArchivingSupported: true,
           scopeDeletionSupported: true,
         ),
       );
  final archived = <(String, bool)>[];
  final previews = <(String, String?)>[];
  @override
  Future<void> archiveProjectScope(
    String scopeId, {
    required bool archived,
    String? requestId,
  }) async {
    this.archived.add((scopeId, archived));
  }

  @override
  Future<Map<String, dynamic>> previewScopeDeletion(
    String scopeId, {
    String? projectId,
  }) async {
    previews.add((scopeId, projectId));
    return {
      'scopeId': scopeId,
      'name': 'Spletna stran',
      'scopeNames': ['Spletna stran'],
      'counts': {
        'projects': 1,
        'tasks': 0,
        'events': 0,
        'ideas': 0,
        'photos': 0,
        'finance': 0,
        'other': 0,
      },
      'canDelete': true,
      'previewHash': 'a' * 64,
    };
  }
}

final menu = find.byKey(
  const ValueKey('content-actions-record-$sharingScopeId-project'),
);
Future<void> host(
  WidgetTester tester,
  ProjectMenuController controller,
  double width,
) => pumpPanel(
  tester,
  controller,
  SharingWorkspace(
    view: SharingView.projects,
    selectedScopeId: sharingScopeId,
    selectedProjectId: 'project',
    onProjectSelected: (_) {},
    onScopeSelected: (_) {},
    showScopePicker: false,
    onConnect: () {},
  ),
  width: width,
);
Future<void> openMenu(WidgetTester tester) async {
  await tester.tap(menu);
  await tester.pumpAndSettle();
}

void main() {
  for (final width in [320.0, 390.0, 1280.0]) {
    testWidgets('open project merges editing report and lifecycle at $width', (
      tester,
    ) async {
      final controller = ProjectMenuController();
      await host(tester, controller, width);
      expect(menu, findsOneWidget);
      expect(
        find.byKey(const ValueKey('scope-lifecycle-$sharingScopeId')),
        findsNothing,
      );
      if (width < 760) expect(find.byIcon(Icons.more_horiz), findsOneWidget);
      await openMenu(tester);
      for (final label in [
        'Uredi projekt',
        'Arhiviraj',
        'Izbriši',
        'Prijavi vsebino',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      await tester.tap(find.text('Arhiviraj'));
      await tester.pumpAndSettle();
      expect(controller.archived, [(sharingScopeId, true)]);
      await openMenu(tester);
      await tester.tap(find.text('Izbriši'));
      await tester.pumpAndSettle();
      expect(controller.previews, [(sharingScopeId, null)]);
      expect(
        find.byKey(const ValueKey('scope-delete-confirm')),
        findsOneWidget,
      );
      await tester.tap(find.text('Prekliči'));
      await tester.pumpAndSettle();
      await openMenu(tester);
      await tester.tap(find.text('Uredi projekt'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('project-editor-sharing')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('reader keeps one report menu without management actions', (
    tester,
  ) async {
    await host(tester, ProjectMenuController(role: SharedRole.viewer), 390);
    expect(find.byIcon(Icons.more_horiz), findsOneWidget);
    await openMenu(tester);
    expect(find.text('Prijavi vsebino'), findsOneWidget);
    for (final label in ['Uredi projekt', 'Arhiviraj', 'Izbriši']) {
      expect(find.text(label), findsNothing);
    }
  });
  testWidgets(
    'inline project deletion targets the project and never its parent space',
    (tester) async {
      final controller = ProjectMenuController(inline: true);
      await host(tester, controller, 390);
      expect(find.byIcon(Icons.more_horiz), findsOneWidget);
      await openMenu(tester);
      await tester.tap(find.text('Izbriši'));
      await tester.pumpAndSettle();
      expect(controller.previews, [(sharingScopeId, 'project')]);
      expect(tester.takeException(), isNull);
    },
  );
}
