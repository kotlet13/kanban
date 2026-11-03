import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/l10n/app_localizations.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'package:kanban/organizer/presentation/shared/local_space_lifecycle_menu.dart';
import 'package:kanban/organizer/presentation/shared/local_space_settings.dart';
import 'package:kanban/organizer/presentation/shared/scope_lifecycle_menu.dart';
import 'package:kanban/organizer/presentation/shared/sharing_members.dart';
import 'package:kanban/organizer/presentation/shared/sharing_workspace.dart';
import 'package:kanban/organizer/presentation/shared/space_settings_page.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';
import 'package:kanban/organizer/state/local_spaces_provider.dart';
import 'package:kanban/organizer/state/organizer_provider.dart';

import 'sharing_ui_fixture.dart';

SharedScope _scope({
  SharedRole role = SharedRole.owner,
  bool archived = false,
  SharedScopeKind kind = SharedScopeKind.household,
}) => SharedScope.fromJson({
  ...sharingScope(role: role).toJson(),
  'name': 'Selected household',
  'kind': kind.name,
  'archived': archived,
  'accessPolicyVersion': 3,
});

class _Shared extends SharingUiController {
  _Shared(
    SharedScope scope, {
    bool supported = true,
    List<SharedScope>? children,
  }) : super(
         initial: CollaborationState(
           session: sharingSession(),
           selectedSpaceId: scope.id,
           scopes: [scope, ...?children],
           data: {scope.id: sharingData()},
           scopeDeletionSupported: supported,
           scopeArchivingSupported: supported,
           organizationsSupported: true,
           spaceProjectMembershipSupported: true,
         ),
       );
  final archives = <(String, bool)>[];
  final deletes = <Map<String, dynamic>>[];
  int previews = 0;
  bool canDelete = true;
  Completer<Map<String, dynamic>>? heldPreview;
  Map<String, dynamic> get preview => {
    'scopeId': initial.scopes.first.id,
    'name': initial.scopes.first.name,
    'scopeNames': [initial.scopes.first.name],
    'counts': {
      'projects': 1,
      'tasks': 2,
      'events': 3,
      'ideas': 4,
      'photos': 5,
      'finance': 6,
      'other': 0,
    },
    'canDelete': canDelete,
    'previewHash': 'a' * 64,
  };
  @override
  Future<Map<String, dynamic>> previewScopeDeletion(
    String scopeId, {
    String? projectId,
  }) async {
    previews++;
    return heldPreview == null ? preview : heldPreview!.future;
  }

  @override
  Future<void> deleteScopeContents(
    Map<String, dynamic> preview, {
    String? projectId,
  }) async => deletes.add(preview);

  @override
  Future<void> archiveProjectScope(
    String scopeId, {
    required bool archived,
    String? requestId,
  }) async => archives.add((scopeId, archived));
}

class _Local extends LocalSpacesController {
  _Local(this.spaces);
  final List<LocalSpace> spaces;
  final archives = <(String, bool)>[];
  final deletes = <Map<String, dynamic>>[];
  int previews = 0;
  @override
  Future<LocalSpacesState> build() async => LocalSpacesState(
    spaces: spaces,
    selectedSpaceId: spaces.firstOrNull?.id ?? 'local',
  );
  @override
  Future<void> archiveSpace(String id, {required bool archived}) async =>
      archives.add((id, archived));
  @override
  Future<Map<String, dynamic>> previewSpaceDeletion(String id) async {
    previews++;
    return {
      'spaceId': id,
      'name': spaces.first.name,
      'counts': {
        'projects': 1,
        'tasks': 2,
        'events': 0,
        'ideas': 0,
        'photos': 0,
        'finance': 0,
        'other': 0,
        'gardens': 1,
        'drafts': 2,
      },
      'canDelete': true,
      'previewHash': 'b' * 64,
    };
  }

  @override
  Future<void> deleteSpace(Map<String, dynamic> preview) async =>
      deletes.add(preview);
}

class _Organizer extends OrganizerController {
  _Organizer(this.workspaceKey);
  final String workspaceKey;
  @override
  Future<OrganizerSnapshot> build() async =>
      OrganizerSnapshot(workspaceKey: workspaceKey);
}

Future<void> _mount(
  WidgetTester tester,
  _Shared shared,
  Widget child, {
  _Local? local,
  double width = 390,
  String language = 'sl',
}) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final catalog = local ?? _Local([]);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...await sharingUiInfrastructureOverrides(tester, shared),
        collaborationProvider.overrideWith(() => shared),
        localSpacesProvider.overrideWith(() => catalog),
        organizerProvider.overrideWith(
          () => _Organizer(catalog.spaces.firstOrNull?.id ?? 'local'),
        ),
      ],
      child: MaterialApp(
        locale: Locale(language),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: Padding(padding: const EdgeInsets.all(16), child: child),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _archive(SharedScope scope) =>
    find.byKey(ValueKey('space-settings-${scope.id}-archive'));
Finder _delete(SharedScope scope) =>
    find.byKey(ValueKey('space-settings-${scope.id}-delete'));
Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  for (final scenario in [(320.0, 'sl'), (390.0, 'en')]) {
    testWidgets('space settings end with explicit actions ${scenario.$2}', (
      tester,
    ) async {
      final scope = _scope(), shared = _Shared(_scope());
      await _mount(
        tester,
        shared,
        SpaceSettingsPage(
          selectedScopeId: scope.id,
          onScopeSelected: (_) {},
          onConnect: () {},
        ),
        width: scenario.$1,
        language: scenario.$2,
      );
      expect(find.byType(ScopeLifecycleMenu), findsNothing);
      expect(_archive(scope), findsOneWidget);
      expect(_delete(scope), findsOneWidget);
      final settingsColumn = tester.widget<Column>(
        find
            .descendant(
              of: find.byType(SpaceSettingsPage),
              matching: find.byType(Column),
            )
            .first,
      );
      expect(settingsColumn.children.last, isA<ScopeLifecycleActions>());
      expect(
        tester.getTopLeft(_archive(scope)).dy,
        greaterThan(tester.getTopLeft(find.byType(SharingMembersPage)).dy),
      );
      expect(shared.previews, 0);
      await _tap(tester, _archive(scope));
      expect(shared.archives, [(scope.id, true)]);
      expect(shared.deletes, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('settings delete keeps counted preview cancel and confirmation', (
    tester,
  ) async {
    final scope = _scope(), shared = _Shared(_scope());
    await _mount(tester, shared, ScopeLifecycleActions(scope: scope));
    await _tap(tester, _delete(scope));
    expect(find.textContaining('Opravila: 2'), findsOneWidget);
    expect(find.textContaining('Fotografije: 5'), findsOneWidget);
    expect(shared.previews, 1);
    expect(shared.deletes, isEmpty);
    await _tap(tester, find.text('Prekliči'));
    expect(shared.deletes, isEmpty);
    await _tap(tester, _delete(scope));
    await _tap(tester, find.byKey(const ValueKey('scope-delete-confirm')));
    expect(shared.previews, 2);
    expect(shared.deletes, [shared.preview]);
  });

  testWidgets('settings delete preserves financial blocker', (tester) async {
    final scope = _scope(), shared = _Shared(_scope())..canDelete = false;
    await _mount(tester, shared, ScopeLifecycleActions(scope: scope));
    await _tap(tester, _delete(scope));
    expect(
      tester
          .widget<TextButton>(
            find.byKey(const ValueKey('scope-delete-confirm')),
          )
          .onPressed,
      isNull,
    );
    expect(shared.deletes, isEmpty);
    expect(find.textContaining('Izbris je zadržan'), findsOneWidget);
  });

  testWidgets('settings preview cannot follow an account change', (
    tester,
  ) async {
    final scope = _scope(), shared = _Shared(_scope());
    shared.heldPreview = Completer();
    await _mount(tester, shared, ScopeLifecycleActions(scope: scope));
    await tester.tap(_delete(scope));
    await tester.pump();
    expect(shared.previews, 1);
    shared.switchAccount();
    shared.heldPreview!.complete(shared.preview);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(shared.deletes, isEmpty);
    expect(_delete(scope), findsNothing);
  });

  for (final role in [SharedRole.member, SharedRole.viewer]) {
    testWidgets('explicit settings actions retain $role rights', (
      tester,
    ) async {
      final scope = _scope(role: role), shared = _Shared(_scope(role: role));
      await _mount(tester, shared, ScopeLifecycleActions(scope: scope));
      expect(
        _archive(scope),
        role == SharedRole.member ? findsOneWidget : findsNothing,
      );
      expect(_delete(scope), findsNothing);
      expect(shared.previews, 0);
    });
  }

  testWidgets('unsupported lifecycle actions remain unavailable', (
    tester,
  ) async {
    final scope = _scope();
    await _mount(
      tester,
      _Shared(scope, supported: false),
      ScopeLifecycleActions(scope: scope),
    );
    expect(_archive(scope), findsNothing);
    expect(_delete(scope), findsNothing);
  });

  testWidgets('archived shared space has an explicit restore action', (
    tester,
  ) async {
    final scope = _scope(archived: true),
        shared = _Shared(_scope(archived: true));
    await _mount(tester, shared, ScopeLifecycleActions(scope: scope));
    expect(find.text('Ponovno aktiviraj prostor'), findsOneWidget);
    await _tap(tester, _archive(scope));
    expect(shared.archives, [(scope.id, false)]);
  });

  testWidgets('local settings end with archive and counted delete actions', (
    tester,
  ) async {
    const space = LocalSpace(
      id: 'local-household',
      kind: LocalSpaceKind.household,
      name: 'Local household',
    );
    final local = _Local([space]);
    await _mount(
      tester,
      _Shared(_scope()),
      LocalSpaceSettings(space: space, onConnect: () {}),
      local: local,
      width: 320,
    );
    // The real shell already owns the selected organizer snapshot before this
    // settings panel opens; initialize that provider in the isolated fixture.
    final container = ProviderScope.containerOf(
      tester.element(find.byType(LocalSpaceSettings)),
    );
    await container.read(organizerProvider.future);
    await tester.pumpAndSettle();
    expect(find.byType(PopupMenuButton<String>), findsNothing);
    final column = tester.widget<Column>(
      find
          .descendant(
            of: find.byType(LocalSpaceSettings),
            matching: find.byType(Column),
          )
          .first,
    );
    expect(column.children.last, isA<LocalSpaceLifecycleActions>());
    await _tap(
      tester,
      find.byKey(
        const ValueKey('local-space-settings-local-household-archive'),
      ),
    );
    expect(local.archives, [(space.id, true)]);
    await _tap(
      tester,
      find.byKey(const ValueKey('local-space-settings-local-household-delete')),
    );
    expect(local.previews, 1);
    expect(local.deletes, isEmpty);
    expect(find.textContaining('Opravila: 2'), findsOneWidget);
    await _tap(
      tester,
      find.byKey(const ValueKey('local-space-delete-confirm')),
    );
    expect(local.deletes.single['spaceId'], space.id);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'default and linked local spaces expose no local lifecycle action',
    (tester) async {
      const defaultSpace = LocalSpace(
        id: 'local',
        kind: LocalSpaceKind.personal,
        name: 'Personal',
      );
      const linked = LocalSpace(
        id: 'linked',
        kind: LocalSpaceKind.household,
        name: 'Linked household',
        binding: LocalSpaceBinding(
          partition: 'synthetic',
          scopeId: sharingScopeId,
        ),
      );
      await _mount(
        tester,
        _Shared(_scope()),
        const Column(
          children: [
            LocalSpaceLifecycleActions(space: defaultSpace),
            LocalSpaceLifecycleActions(space: linked),
          ],
        ),
        local: _Local([defaultSpace, linked]),
      );
      expect(find.byType(OutlinedButton), findsNothing);
      expect(find.byType(TextButton), findsNothing);
    },
  );

  for (final view in [
    SharingView.tasks,
    SharingView.finances,
    SharingView.shopping,
  ]) {
    testWidgets('$view heading keeps sync without full-space lifecycle menu', (
      tester,
    ) async {
      final scope = _scope(), shared = _Shared(_scope());
      await _mount(
        tester,
        shared,
        SharingWorkspace(
          view: view,
          selectedScopeId: scope.id,
          onScopeSelected: (_) {},
          onConnect: () {},
          showScopePicker: false,
        ),
      );
      expect(find.byKey(ValueKey('scope-lifecycle-${scope.id}')), findsNothing);
      expect(
        find.byKey(ValueKey('sharing-status-${scope.id}-$view')),
        findsOneWidget,
      );
      expect(shared.archives, isEmpty);
      expect(shared.deletes, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'organization heading loses its menu but project row keeps context',
    (tester) async {
      final organization = _scope(kind: SharedScopeKind.organization);
      final project = SharedScope(
        id: 'child-project',
        name: 'Child project',
        kind: SharedScopeKind.project,
        role: SharedRole.owner,
        parentScopeId: organization.id,
      );
      final shared = _Shared(organization, children: [project]);
      await _mount(
        tester,
        shared,
        SharingWorkspace(
          view: SharingView.projects,
          selectedScopeId: organization.id,
          onScopeSelected: (_) {},
          onConnect: () {},
          showScopePicker: false,
        ),
      );
      expect(
        find.byKey(ValueKey('scope-lifecycle-${organization.id}')),
        findsNothing,
      );
      final projectMenu = find.byKey(ValueKey('scope-lifecycle-${project.id}'));
      expect(projectMenu, findsOneWidget);
      await _tap(tester, projectMenu);
      await _tap(tester, find.text('Arhiviraj'));
      expect(shared.archives, [(project.id, true)]);
      expect(tester.takeException(), isNull);
    },
  );
}
