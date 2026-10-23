import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'package:kanban/organizer/presentation/collection_actions.dart';
import 'package:kanban/organizer/presentation/organizer_editors.dart';
import 'package:kanban/organizer/presentation/projects_page.dart';
import 'package:kanban/organizer/presentation/shared/content_actions_menu.dart';
import 'package:kanban/organizer/presentation/shared/sharing_members.dart';
import 'package:kanban/organizer/presentation/shared/sharing_workspace.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';

import 'onboarding_ui_test.dart' show pumpPanel;
import 'sharing_ui_fixture.dart';

const _rootId = '00000000-0000-4000-a000-000000000001';
LocalProject _project(String id) => LocalProject(
  id: id,
  title: '$id title',
  description: '',
  createdAt: sharingTestNow,
  updatedAt: sharingTestNow,
);

class _Controller extends SharingUiController {
  _Controller({
    bool dedicated = true,
    bool rootReady = true,
    bool extraProject = false,
    SharedRole role = SharedRole.owner,
  }) : super(
         initial: CollaborationState(
           session: sharingSession(),
           selectedSpaceId: sharingScopeId,
           scopes: [
             SharedScope(
               id: sharingScopeId,
               name: 'Selected project scope',
               kind: dedicated
                   ? SharedScopeKind.project
                   : SharedScopeKind.household,
               role: role,
               projectRootId: rootReady ? _rootId : null,
             ),
           ],
           data: {
             sharingScopeId: SharedScopeData(
               projects: [
                 if (extraProject) _project('unrelated'),
                 _project(_rootId),
               ],
             ),
           },
           scopeArchivingSupported: true,
           projectArchivingSupported: true,
           scopeDeletionSupported: true,
         ),
       );
  final loadedScopes = <String>[];
  @override
  Future<List<SharedMember>> members(String scopeId) async {
    loadedScopes.add(scopeId);
    return [];
  }
}

Widget _shared({String? selected, ValueChanged<String?>? onSelection}) =>
    SharingWorkspace(
      view: SharingView.projects,
      selectedScopeId: sharingScopeId,
      selectedProjectId: selected,
      onProjectSelected: onSelection ?? (_) {},
      onScopeSelected: (_) {},
      showScopePicker: false,
      onConnect: () {},
    );

Finder get _menu => find.byKey(
  const ValueKey('content-actions-record-$sharingScopeId-$_rootId'),
);
Future<List<String>> _menuLabels(WidgetTester tester) async {
  await tester.tap(_menu);
  await tester.pumpAndSettle();
  return tester
      .widgetList<Text>(
        find.descendant(
          of: find.byType(PopupMenuItem<String>),
          matching: find.byType(Text),
        ),
      )
      .map((text) => text.data!)
      .toList();
}

class _LocalActions implements OrganizerCollectionActions {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final width in [390.0, 1280.0]) {
    testWidgets('dedicated scope opens canonical details once at $width', (
      tester,
    ) async {
      await pumpPanel(
        tester,
        _Controller(),
        _shared(),
        width: width,
        language: 'en',
      );
      expect(find.text('$_rootId title'), findsOneWidget);
      expect(find.text('Sharing and members'), findsOneWidget);
      expect(find.text('Projects'), findsNothing);
      expect(
        find.byKey(const ValueKey('desktop-project-$_rootId')),
        findsNothing,
      );
      expect(find.byIcon(Icons.arrow_back), findsNothing);
      expect(find.byType(SharedContentActionsMenu), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'ambiguous project scope keeps list and allows explicit sibling navigation',
    (tester) async {
      String? selected;
      await pumpPanel(
        tester,
        _Controller(extraProject: true),
        StatefulBuilder(
          builder: (context, setState) => _shared(
            selected: selected,
            onSelection: (id) => setState(() => selected = id),
          ),
        ),
        width: 1280,
        language: 'en',
      );
      expect(find.text('unrelated title'), findsOneWidget);
      expect(find.text('$_rootId title'), findsOneWidget);
      expect(find.text('Sharing and members'), findsNothing);
      await tester.tap(find.text('$_rootId title'));
      await tester.pumpAndSettle();
      expect(find.text('$_rootId title'), findsNWidgets(2));
      expect(find.text('Sharing and members'), findsOneWidget);
      await tester.tap(find.text('unrelated title'));
      await tester.pumpAndSettle();
      expect(find.text('unrelated title'), findsNWidgets(2));
      expect(find.text('$_rootId title'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'unready canonical root keeps list without choosing unrelated first project',
    (tester) async {
      await pumpPanel(
        tester,
        _Controller(rootReady: false, extraProject: true),
        _shared(),
        width: 1280,
        language: 'en',
      );
      expect(find.text('unrelated title'), findsOneWidget);
      expect(find.text('$_rootId title'), findsOneWidget);
      expect(
        find.widgetWithText(OutlinedButton, 'Sharing and members'),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'shared card and detail use same actions and one detail members button',
    (tester) async {
      final controller = _Controller(dedicated: false);
      await pumpPanel(tester, controller, _shared(), language: 'en');
      final cardLabels = await _menuLabels(tester);
      expect(cardLabels, contains('Sharing and members'));
      await tester.tapAt(const Offset(1, 1));
      await tester.pumpAndSettle();
      await pumpPanel(
        tester,
        controller,
        _shared(selected: _rootId),
        language: 'en',
      );
      final detailLabels = await _menuLabels(tester);
      expect(
        cardLabels.where((label) => label != 'Sharing and members'),
        detailLabels,
      );
      expect(detailLabels, isNot(contains('Sharing and members')));
      expect(find.text('Sharing and members'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'open shared card menu cannot navigate membership after account change',
    (tester) async {
      final controller = _Controller(dedicated: false);
      await pumpPanel(tester, controller, _shared(), language: 'en');
      await _menuLabels(tester);
      controller.replace(
        CollaborationState(
          session: sharingSession(second: true),
          selectedSpaceId: controller.initial.selectedSpaceId,
          scopes: controller.initial.scopes,
          data: controller.initial.data,
        ),
      );
      await tester.pump();
      final action = find.text('Sharing and members');
      if (action.evaluate().isNotEmpty) {
        await tester.tap(action);
        await tester.pumpAndSettle();
      }
      expect(controller.loadedScopes, isEmpty);
      expect(find.byType(SharingMembersPage), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'viewer shared card offers report and membership without management',
    (tester) async {
      await pumpPanel(
        tester,
        _Controller(dedicated: false, role: SharedRole.viewer),
        _shared(),
        language: 'en',
      );
      final labels = await _menuLabels(tester);
      expect(labels, containsAll(['Sharing and members', 'Report content']));
      expect(labels, isNot(contains('Edit project')));
      expect(labels, isNot(contains('Archive')));
      expect(labels, isNot(contains('Delete')));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'local detail has same lifecycle menu as card and explicit copy button',
    (tester) async {
      final project = _project('local-project');
      Widget local(String? selected) => OrganizerProjectsPage(
        snapshot: OrganizerSnapshot(projects: [project]),
        actions: _LocalActions(),
        selectedId: selected,
        onSelection: (_) {},
        onShare: (_) {},
      );
      final controller = SharingUiController();
      await pumpPanel(tester, controller, local(null), language: 'en');
      final menu = find.byKey(const ValueKey('project-menu-local-project'));
      await tester.tap(menu);
      await tester.pumpAndSettle();
      for (final label in ['Edit project', 'Archive', 'Delete']) {
        expect(find.text(label), findsOneWidget);
      }
      await tester.tapAt(const Offset(1, 1));
      await tester.pumpAndSettle();
      await pumpPanel(tester, controller, local(project.id), language: 'en');
      expect(find.text('Create a shared copy'), findsOneWidget);
      await tester.tap(menu);
      await tester.pumpAndSettle();
      for (final label in ['Edit project', 'Archive', 'Delete']) {
        expect(find.text(label), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'project editor can distinguish local copy from connected membership',
    (tester) async {
      await pumpPanel(
        tester,
        SharingUiController(),
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showOrganizerEditor(
              context,
              heading: 'Edit local project',
              kind: OrganizerEditorKind.project,
              draft: OrganizerDraft(title: 'Local project'),
              onSave: (_) async {},
              onShare: () async {},
              shareActionLabel: 'Create a shared copy',
            ),
            child: const Text('Edit local project'),
          ),
        ),
        language: 'en',
      );
      await tester.tap(find.text('Edit local project'));
      await tester.pumpAndSettle();
      expect(find.text('Create a shared copy'), findsOneWidget);
      expect(find.text('Members'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'dedicated canonical root ignores prior project category selection',
    (tester) async {
      var dedicated = false;
      final root = _project('category-root');
      final home = _project('category-home').copyWith(area: ProjectArea.home);
      await pumpPanel(
        tester,
        SharingUiController(),
        StatefulBuilder(
          builder: (context, setState) => Column(
            children: [
              TextButton(
                onPressed: () => setState(() => dedicated = true),
                child: const Text('Open dedicated scope'),
              ),
              OrganizerProjectsPage(
                key: const ValueKey('category-transition'),
                snapshot: OrganizerSnapshot(
                  projects: dedicated ? [root] : [root, home],
                ),
                actions: _LocalActions(),
                selectedId: dedicated ? root.id : null,
                detailOnly: dedicated,
                onSelection: (_) {},
              ),
            ],
          ),
        ),
        language: 'en',
      );
      await tester.tap(find.byKey(const ValueKey('projects-category-home')));
      await tester.pumpAndSettle();
      expect(find.text('category-root title'), findsNothing);
      await tester.tap(find.text('Open dedicated scope'));
      await tester.pumpAndSettle();
      expect(find.text('category-root title'), findsOneWidget);
      expect(find.text('No projects yet'), findsNothing);
      expect(
        find.byKey(const ValueKey('projects-category-home')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
