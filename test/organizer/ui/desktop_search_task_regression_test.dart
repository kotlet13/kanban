import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/l10n/app_localizations.dart';
import 'package:kanban/organizer/domain/all_spaces_projection.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'package:kanban/organizer/presentation/all_spaces/all_spaces_area.dart';
import 'package:kanban/organizer/presentation/all_spaces/all_spaces_rows.dart';
import 'package:kanban/organizer/presentation/desktop/desktop_search.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';
import 'package:kanban/organizer/state/idea_provider.dart';
import 'package:kanban/organizer/state/local_spaces_provider.dart';
import 'package:kanban/organizer/state/organizer_provider.dart';

final _now = DateTime.utc(2026, 10, 23, 12);

LocalTask _task(String id, String title, {bool completed = false}) => LocalTask(
  id: id,
  title: title,
  notes: '',
  projectId: null,
  dueAt: null,
  isCompleted: completed,
  createdAt: _now,
  updatedAt: _now,
);

LocalProject _project(String id, {bool archived = false}) => LocalProject(
  id: id,
  title: 'Project',
  description: '',
  archived: archived,
  createdAt: _now,
  updatedAt: _now,
);

AccountSession _session(String account) => AccountSession(
  serverUrl: 'https://search.example.test',
  serverId: 'synthetic-search-server',
  accountId: account,
  userId: 1,
  username: account,
  displayName: account,
  deviceId: 'synthetic-search-device',
  expiresAt: DateTime.utc(2099),
);

class _Organizer extends OrganizerController {
  _Organizer(this.initial);
  final OrganizerSnapshot initial;

  @override
  Future<OrganizerSnapshot> build() async => initial;

  void startWorkspaceTransition() {
    state = const AsyncLoading<OrganizerSnapshot>().copyWithPrevious(state);
  }
}

class _Sharing extends CollaborationController {
  _Sharing(this.initial);
  final CollaborationState initial;

  @override
  Future<CollaborationState> build() async => initial;

  void replace(CollaborationState next) => state = AsyncData(next);
}

class _LocalSpaces extends LocalSpacesController {
  _LocalSpaces(this.initial);
  final LocalSpacesState initial;

  @override
  Future<LocalSpacesState> build() async => initial;
}

Future<void> _pumpSearch(
  WidgetTester tester, {
  required _Organizer organizer,
  required _Sharing sharing,
  LocalSpacesState? localSpaces,
}) async {
  tester.view.physicalSize = const Size(1100, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        organizerProvider.overrideWith(() => organizer),
        collaborationProvider.overrideWith(() => sharing),
        localSpacesProvider.overrideWith(
          () => _LocalSpaces(localSpaces ?? LocalSpacesState()),
        ),
        ideaAllSpacesProvider.overrideWith((ref) async => []),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: OrganizerDesktopSearch()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _search(WidgetTester tester, String query) async {
  await tester.enterText(
    find.byKey(const ValueKey('desktop-search-input')),
    query,
  );
  await tester.pumpAndSettle();
}

Finder _result(String sourceKey, String id) =>
    find.byKey(ValueKey('desktop-search-$sourceKey:task:$id'));

void main() {
  testWidgets('search includes standalone open and completed undated tasks', (
    tester,
  ) async {
    await _pumpSearch(
      tester,
      organizer: _Organizer(
        OrganizerSnapshot(
          tasks: [
            _task('open', 'UX26 open standalone'),
            _task('done', 'UX26 completed standalone', completed: true),
            _task('notes', 'Different title').copyWith(notes: 'UX26 note'),
          ],
        ),
      ),
      sharing: _Sharing(CollaborationState()),
    );
    await _search(tester, '  ux26  ');
    expect(_result('local', 'open'), findsOneWidget);
    expect(_result('local', 'done'), findsOneWidget);
    expect(_result('local', 'notes'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('search deduplicates linked tasks and retains distinct origins', (
    tester,
  ) async {
    final session = _session('first');
    const scope = SharedScope(
      id: 'shared',
      name: 'Shared',
      kind: SharedScopeKind.household,
      role: SharedRole.owner,
    );
    await _pumpSearch(
      tester,
      organizer: _Organizer(
        OrganizerSnapshot(
          tasks: [
            _task('same', 'Needle linked').copyWith(
              projectId: 'project',
              assigneePersonId: 'person',
              dueAt: _now,
            ),
          ],
          projects: [_project('project')],
          people: [
            HouseholdPerson(
              id: 'person',
              name: 'Person',
              createdAt: _now,
              updatedAt: _now,
            ),
          ],
        ),
      ),
      sharing: _Sharing(
        CollaborationState(
          session: session,
          selectedSpaceId: scope.id,
          scopes: const [scope],
          data: {
            scope.id: SharedScopeData(
              tasks: [_task('same', 'Needle shared standalone')],
            ),
          },
        ),
      ),
      localSpaces: LocalSpacesState(
        spaces: const [
          LocalSpace(
            id: 'other-local',
            name: 'Needle other origin',
            kind: LocalSpaceKind.household,
          ),
        ],
        snapshots: {
          'other-local': OrganizerSnapshot(
            workspaceKey: 'other-local',
            tasks: [_task('same', 'Other standalone')],
          ),
        },
      ),
    );
    await _search(tester, 'needle');
    expect(_result('local', 'same'), findsOneWidget);
    expect(_result('other-local', 'same'), findsOneWidget);
    expect(_result('${session.partition}:shared', 'same'), findsOneWidget);
    expect(find.byType(ListTile), findsNWidgets(3));
    expect(tester.takeException(), isNull);
  });

  testWidgets('open task search preserves scope and visibility boundaries', (
    tester,
  ) async {
    final session = _session('first');
    const scopes = [
      SharedScope(
        id: 'active',
        name: 'Active',
        kind: SharedScopeKind.household,
        role: SharedRole.owner,
      ),
      SharedScope(
        id: 'revoked',
        name: 'Revoked',
        kind: SharedScopeKind.household,
        role: SharedRole.owner,
        revoked: true,
      ),
      SharedScope(
        id: 'blocked',
        name: 'Blocked',
        kind: SharedScopeKind.household,
        role: SharedRole.owner,
        blocked: true,
      ),
      SharedScope(
        id: 'archived',
        name: 'Archived',
        kind: SharedScopeKind.household,
        role: SharedRole.owner,
        archived: true,
      ),
    ];
    final sharing = _Sharing(
      CollaborationState(
        session: session,
        scopes: scopes,
        data: {
          for (final scope in scopes)
            scope.id: SharedScopeData(
              tasks: [_task('same', 'Boundary ${scope.id}')],
            ),
        },
      ),
    );
    final organizer = _Organizer(
      OrganizerSnapshot(
        tasks: [
          _task('visible', 'Boundary local visible'),
          _task(
            'hidden',
            'Boundary archived project',
          ).copyWith(projectId: 'hidden-project'),
        ],
        projects: [_project('hidden-project', archived: true)],
      ),
    );
    await _pumpSearch(tester, organizer: organizer, sharing: sharing);
    await _search(tester, 'boundary');
    expect(_result('local', 'visible'), findsOneWidget);
    expect(_result('local', 'hidden'), findsNothing);
    expect(_result('${session.partition}:active', 'same'), findsOneWidget);
    for (final id in ['revoked', 'blocked', 'archived']) {
      expect(_result('${session.partition}:$id', 'same'), findsNothing);
    }
    sharing.replace(CollaborationState(session: _session('second')));
    await tester.pumpAndSettle();
    expect(_result('${session.partition}:active', 'same'), findsNothing);
    expect(_result('local', 'visible'), findsOneWidget);
    organizer.startWorkspaceTransition();
    await tester.pump();
    expect(_result('local', 'visible'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('ordinary Tasks completion selector retains exact state filtering', () {
    final snapshot = projectAllSpaces(
      personal: OrganizerSnapshot(
        tasks: [
          _task('open', 'Open'),
          _task('done', 'Completed', completed: true),
        ],
      ),
      shared: CollaborationState(),
    );
    expect(
      allSpacesRows(
        snapshot,
        AllSpacesArea.tasks,
        now: _now,
      ).map((row) => row.id),
      ['open'],
    );
    expect(
      allSpacesRows(
        snapshot,
        AllSpacesArea.tasks,
        now: _now,
        showCompleted: true,
      ).map((row) => row.id),
      ['done'],
    );
  });
}
