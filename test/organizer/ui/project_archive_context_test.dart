import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/l10n/app_localizations.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'package:kanban/organizer/presentation/collection_actions.dart';
import 'package:kanban/organizer/presentation/organizer_actions.dart';
import 'package:kanban/organizer/presentation/organizer_editors.dart';
import 'package:kanban/organizer/presentation/projects_page.dart';
import 'package:kanban/organizer/presentation/organizer_widgets.dart';
import 'package:kanban/organizer/presentation/shared/collaboration_actions.dart';
import 'package:kanban/organizer/presentation/shared/project_sharing_settings.dart';
import 'package:kanban/organizer/presentation/shared/sharing_members.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';
import 'package:kanban/organizer/state/local_spaces_provider.dart';
import 'package:kanban/organizer/state/organizer_provider.dart';

import 'sharing_ui_fixture.dart';

LocalProject project(
  String id, {
  bool archived = false,
  ProjectArea area = ProjectArea.personal,
}) => LocalProject(
  id: id,
  title: '$id project',
  description: 'Preserved notes',
  archived: archived,
  area: area,
  createdAt: sharingTestNow,
  updatedAt: sharingTestNow,
);

class _Catalog extends LocalSpacesController {
  _Catalog(this.kind);
  final LocalSpaceKind kind;
  @override
  Future<LocalSpacesState> build() async => LocalSpacesState(
    selectedSpaceId: kind == LocalSpaceKind.personal ? 'local' : 'local-org',
    spaces: [
      LocalSpace(
        id: kind == LocalSpaceKind.personal ? 'local' : 'local-org',
        kind: kind,
        name: 'Project organization',
      ),
    ],
  );
}

class _Personal extends OrganizerController {
  _Personal(this.initial);
  final OrganizerSnapshot initial;
  LocalProject? saved;
  @override
  Future<OrganizerSnapshot> build() async => initial;
  @override
  Future<void> updateProject(LocalProject value) async => saved = value;
}

class _ProjectActions implements OrganizerCollectionActions {
  _ProjectActions(this.snapshot);
  final ValueNotifier<OrganizerSnapshot> snapshot;
  final edits = <String>[], deletes = <String>[], archives = <(String, bool)>[];
  @override
  Future<void> project([
    LocalProject? value,
    ProjectArea area = ProjectArea.personal,
  ]) async {
    if (value != null) edits.add(value.id);
  }

  @override
  Future<void> archiveProject(
    LocalProject value, {
    bool archived = true,
  }) async {
    archives.add((value.id, archived));
    snapshot.value = snapshot.value.copyWith(
      projects: [
        for (final p in snapshot.value.projects)
          p.id == value.id ? p.copyWith(archived: archived) : p,
      ],
    );
  }

  @override
  Future<void> deleteProject(LocalProject value) async => deletes.add(value.id);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> host(
  WidgetTester tester,
  Widget child, {
  List<Override> overrides = const [],
  double width = 390,
  double scale = 1,
}) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(
          platform: width >= 900
              ? TargetPlatform.macOS
              : TargetPlatform.android,
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> chooseMenu(WidgetTester tester, String id, String action) async {
  final menu = find.byKey(ValueKey('project-menu-$id'));
  await tester.ensureVisible(menu);
  await tester.tap(menu);
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(PopupMenuItem<String>, action));
  await tester.pumpAndSettle();
}

void main() {
  for (final kind in [LocalSpaceKind.organization, LocalSpaceKind.personal]) {
    testWidgets(
      'local ${kind.name} project editor exposes appropriate area and preserves hidden value',
      (tester) async {
        final p = project('local', area: ProjectArea.home);
        final personal = _Personal(
          OrganizerSnapshot(
            projects: [p],
            workspaceKey: kind == LocalSpaceKind.personal
                ? 'local'
                : 'local-org',
          ),
        );
        await host(
          tester,
          Consumer(
            builder: (context, ref, _) {
              final snapshot = ref.watch(organizerProvider).valueOrNull;
              final catalog = ref.watch(localSpacesProvider).valueOrNull;
              if (snapshot == null || catalog == null) return const SizedBox();
              return TextButton(
                onPressed: () =>
                    OrganizerActions(context, ref, snapshot).project(p),
                child: const Text('Open project'),
              );
            },
          ),
          overrides: [
            organizerProvider.overrideWith(() => personal),
            localSpacesProvider.overrideWith(() => _Catalog(kind)),
            collaborationProvider.overrideWith(() => SharingUiController()),
          ],
          width: 320,
          scale: 2,
        );
        await tester.tap(find.text('Open project'));
        await tester.pumpAndSettle();
        expect(
          find.byType(DropdownButtonFormField<ProjectArea>),
          kind == LocalSpaceKind.personal ? findsOneWidget : findsNothing,
        );
        expect(find.text('Project organization'), findsOneWidget);
        await tester.enterText(
          find.byKey(const ValueKey('organizer-title-field')),
          'Renamed project',
        );
        await tester.tap(find.byKey(const ValueKey('organizer-save')));
        await tester.pumpAndSettle();
        expect(personal.saved?.id, p.id);
        expect(personal.saved?.area, ProjectArea.home);
        expect(personal.saved?.description, 'Preserved notes');
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'project editor review cancellation retains draft and confirmed deletion closes once',
    (tester) async {
      var accepted = false, reviews = 0, shares = 0;
      await host(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showOrganizerEditor(
              context,
              heading: 'Edit project',
              kind: OrganizerEditorKind.project,
              draft: OrganizerDraft(title: 'Original'),
              projectAreaEnabled: false,
              projectContext: 'Shared organization',
              onShare: () async {
                shares++;
              },
              onSave: (_) async {},
              onDeleteWithReview: () async {
                reviews++;
                return accepted;
              },
            ),
            child: const Text('Open project'),
          ),
        ),
      );
      await tester.tap(find.text('Open project'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('organizer-title-field')),
        'Unsaved draft',
      );
      await tester.tap(find.byKey(const ValueKey('project-editor-sharing')));
      await tester.pumpAndSettle();
      expect(shares, 1);
      await tester.tap(find.byTooltip('Delete'));
      await tester.pumpAndSettle();
      expect(reviews, 1);
      expect(find.text('Unsaved draft'), findsOneWidget);
      accepted = true;
      await tester.tap(find.byTooltip('Delete'));
      await tester.pumpAndSettle();
      expect(reviews, 2);
      expect(find.byKey(const ValueKey('organizer-save')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final childScope in [false, true]) {
    testWidgets(
      'shared editor routes ${childScope ? 'root to own members' : 'inline project to exact sharing review'}',
      (tester) async {
        final p = project('target');
        final scope = SharedScope(
          id: childScope ? 'child-scope' : sharingScopeId,
          name: childScope ? 'Project scope context' : 'Household context',
          kind: childScope
              ? SharedScopeKind.project
              : SharedScopeKind.household,
          role: SharedRole.owner,
          accessPolicyVersion: 3,
          projectRootId: childScope ? p.id : null,
        );
        final data = SharedScopeData(
          projects: [p, if (!childScope) project('unrelated')],
        );
        final shared = SharingUiController(
          initial: CollaborationState(
            session: sharingSession(),
            selectedSpaceId: scope.id,
            scopes: [scope],
            data: {scope.id: data},
            spaceProjectMembershipSupported: true,
            scopedInvitationsSupported: true,
            emailInvitationsSupported: true,
          ),
        );
        await host(
          tester,
          Consumer(
            builder: (context, ref, _) {
              if (ref.watch(collaborationProvider).valueOrNull == null) {
                return const SizedBox();
              }
              return TextButton(
                onPressed: () =>
                    CollaborationActions(context, ref, scope, data).project(p),
                child: const Text('Open project'),
              );
            },
          ),
          overrides: [
            ...await sharingUiInfrastructureOverrides(tester, shared),
            collaborationProvider.overrideWith(() => shared),
          ],
        );
        await tester.tap(find.text('Open project'));
        await tester.pumpAndSettle();
        expect(find.byType(DropdownButtonFormField<ProjectArea>), findsNothing);
        expect(find.text(scope.name), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('project-editor-sharing')));
        await tester.pumpAndSettle();
        if (childScope) {
          expect(
            tester
                .widget<SharingMembersPage>(find.byType(SharingMembersPage))
                .scope
                .id,
            scope.id,
          );
          expect(shared.memberLoads, 1);
        } else {
          expect(
            find.byType(SharingMembersPage),
            findsNothing,
            reason:
                'An inline project must never offer whole-household invitations',
          );
          expect(find.byType(ProjectSharingSettings), findsOneWidget);
          expect(
            find.byKey(const ValueKey('project-sharing-review-target')),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('project-sharing-review-unrelated')),
            findsNothing,
          );
          expect(shared.memberLoads, 0);
        }
        expect(shared.emailInviteTargets, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final width in [390.0, 1280.0]) {
    testWidgets(
      'project archive collapses, restore and menus act on exact ID at $width',
      (tester) async {
        final snapshot = ValueNotifier(
          OrganizerSnapshot(
            projects: [project('active'), project('old', archived: true)],
          ),
        );
        addTearDown(snapshot.dispose);
        final actions = _ProjectActions(snapshot);
        await host(
          tester,
          ValueListenableBuilder<OrganizerSnapshot>(
            valueListenable: snapshot,
            builder: (_, value, _) => OrganizerProjectsPage(
              snapshot: value,
              actions: actions,
              onSelection: (_) {},
              scopeLabel: 'Organization',
            ),
          ),
          width: width,
        );
        expect(
          find.byKey(const ValueKey('projects-category-home')),
          findsNothing,
        );
        expect(find.text('active project'), findsOneWidget);
        expect(find.text('old project'), findsNothing);
        await chooseMenu(tester, 'active', 'Edit project');
        expect(actions.edits, ['active']);
        await chooseMenu(tester, 'active', 'Archive');
        expect(actions.archives, [('active', true)]);
        expect(find.text('active project'), findsNothing);
        await tester.tap(find.byKey(const ValueKey('projects-archived')));
        await tester.pumpAndSettle();
        expect(find.text('active project'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('project-menu-active')));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<PopupMenuItem<String>>(
                find.widgetWithText(PopupMenuItem<String>, 'Edit project'),
              )
              .enabled,
          isFalse,
        );
        await tester.tap(find.widgetWithText(PopupMenuItem<String>, 'Restore'));
        await tester.pumpAndSettle();
        expect(actions.archives, [('active', true), ('active', false)]);
        await chooseMenu(tester, 'active', 'Delete');
        expect(actions.deletes, ['active']);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'home archive applies the same category filter as active projects',
    (tester) async {
      final snapshot = ValueNotifier(
        OrganizerSnapshot(
          projects: [
            project('home', archived: true, area: ProjectArea.home),
            project('personal', archived: true),
          ],
        ),
      );
      addTearDown(snapshot.dispose);
      await host(
        tester,
        OrganizerProjectsPage(
          snapshot: snapshot.value,
          actions: _ProjectActions(snapshot),
          home: true,
          onSelection: (_) {},
        ),
      );
      await tester.tap(find.byKey(const ValueKey('projects-archived')));
      await tester.pumpAndSettle();
      expect(find.text('home project'), findsOneWidget);
      expect(find.text('personal project'), findsNothing);
    },
  );
  testWidgets(
    'archived project detail remains readable and removes edit/completion actions',
    (tester) async {
      final p = project('closed', archived: true);
      final task = LocalTask(
        id: 'closed-task',
        projectId: p.id,
        title: 'Historical task',
        notes: '',
        dueAt: null,
        isCompleted: false,
        createdAt: sharingTestNow,
        updatedAt: sharingTestNow,
      );
      final snapshot = ValueNotifier(
        OrganizerSnapshot(projects: [p], tasks: [task]),
      );
      addTearDown(snapshot.dispose);
      await host(
        tester,
        OrganizerProjectsPage(
          snapshot: snapshot.value,
          actions: _ProjectActions(snapshot),
          selectedId: p.id,
          onSelection: (_) {},
        ),
      );
      expect(find.text(p.title), findsWidgets);
      expect(find.text('Historical task'), findsOneWidget);
      expect(find.byTooltip('Edit project'), findsNothing);
      expect(find.byTooltip('Add task'), findsNothing);
      final row = tester.widget<OrganizerTaskRow>(
        find.byType(OrganizerTaskRow),
      );
      expect(row.onEdit, isNull);
      expect(row.onCompleted, isNull);
      expect(tester.takeException(), isNull);
    },
  );
}
