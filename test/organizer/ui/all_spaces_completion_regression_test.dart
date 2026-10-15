import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/l10n/app_localizations.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'package:kanban/organizer/presentation/all_spaces/all_spaces_page.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';
import 'package:kanban/organizer/state/local_spaces_provider.dart';
import 'package:kanban/organizer/state/organizer_provider.dart';

import 'all_spaces_task_completion_test.dart'
    show CompletingController, taskCheckbox;
import 'all_spaces_ui_test.dart' show now, pumpAll, task;
import 'personal_workspace_ui_test.dart' show WorkspaceController;
import 'sharing_ui_fixture.dart';

class _ExactLocalCompletionController extends LocalSpacesController {
  _ExactLocalCompletionController(this.initial);
  final LocalSpacesState initial;
  final writes = <(String, String, bool, String)>[];

  @override
  Future<LocalSpacesState> build() async => initial;

  @override
  Future<void> setTaskCompleted(
    String localSpaceId,
    String id,
    bool value, {
    required String expectedWorkspaceKey,
    bool Function()? stillVisible,
  }) async {
    expect(stillVisible?.call(), isTrue);
    writes.add((localSpaceId, id, value, expectedWorkspaceKey));
    final current = state.requireValue;
    final source = current.snapshots[localSpaceId]!;
    expect(source.workspaceKey, expectedWorkspaceKey);
    state = AsyncData(
      LocalSpacesState(
        spaces: current.spaces,
        selectedSpaceId: current.selectedSpaceId,
        snapshots: {
          ...current.snapshots,
          localSpaceId: source.copyWith(
            tasks: source.tasks.map(
              (t) => t.id == id ? t.copyWith(isCompleted: value) : t,
            ),
          ),
        },
      ),
    );
  }
}

void main() {
  testWidgets('completion remains busy when aggregate rows reorder', (
    tester,
  ) async {
    final shared = CompletingController()..gate = Completer<void>();
    addTearDown(() {
      if (!shared.gate!.isCompleted) shared.gate!.complete();
    });
    await pumpAll(tester, area: AllSpacesArea.tasks, shared: shared);
    await tester.tap(taskCheckbox('QA skupno opravilo'));
    await tester.pump();
    expect(shared.completions, [(sharingScopeId, 'same-task', true)]);

    final current = shared.state.requireValue;
    final source = current.dataForScope(sharingScopeId);
    shared.replace(
      CollaborationState(
        session: current.session,
        selectedSpaceId: current.selectedSpaceId,
        allSpacesSelected: current.allSpacesSelected,
        scopes: current.scopes,
        data: {
          ...current.data,
          sharingScopeId: SharedScopeData(
            projects: source.projects,
            tasks: [
              task(
                'earlier-task',
                'AA inserted while saving',
              ).copyWith(dueAt: DateTime(2020)),
              ...source.tasks,
            ],
          ),
        },
      ),
    );
    await tester.pump();
    expect(
      tester.getTopLeft(find.text('AA inserted while saving')).dy,
      lessThan(tester.getTopLeft(find.text('QA skupno opravilo')).dy),
    );
    expect(
      tester.widget<Checkbox>(taskCheckbox('QA skupno opravilo')).onChanged,
      isNull,
    );
    await tester.tap(taskCheckbox('QA skupno opravilo'));
    await tester.pump();
    expect(shared.completions, [(sharingScopeId, 'same-task', true)]);
    expect(shared.opened, isEmpty);

    shared.gate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('QA skupno opravilo'), findsNothing);
    expect(find.text('AA inserted while saving'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('private Personal completes through its nonselected source', (
    tester,
  ) async {
    final session = sharingSession();
    final privateKey = 'private:${session.partition}';
    final selected = WorkspaceController(
      OrganizerSnapshot(
        workspaceKey: 'other-local',
        tasks: [task('same-task', 'Opravilo izbranega prostora')],
      ),
    );
    final local = _ExactLocalCompletionController(
      LocalSpacesState(
        selectedSpaceId: 'other-local',
        spaces: const [
          LocalSpace(id: 'local', kind: LocalSpaceKind.personal, name: ''),
          LocalSpace(
            id: 'other-local',
            kind: LocalSpaceKind.household,
            name: 'Drug lokalni prostor',
          ),
        ],
        snapshots: {
          'local': OrganizerSnapshot(
            workspaceKey: privateKey,
            tasks: [task('same-task', 'Zasebno opravilo')],
          ),
          'other-local': selected.snapshot,
        },
      ),
    );
    final shared = CompletingController(
      initial: CollaborationState(
        session: session,
        allSpacesSelected: true,
        privateSync: const PrivateSyncState(scopeId: 'private'),
        privateRecordIds: const {'remote-task': 'same-task'},
        scopes: const [
          SharedScope(
            id: 'private',
            name: 'Zasebno',
            kind: SharedScopeKind.personal,
            role: SharedRole.owner,
          ),
        ],
      ),
    );
    tester.view.physicalSize = const Size(390, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          organizerProvider.overrideWith(() => selected),
          localSpacesProvider.overrideWith(() => local),
          collaborationProvider.overrideWith(() => shared),
          organizerClockProvider.overrideWithValue(() => now),
        ],
        child: MaterialApp(
          locale: const Locale('sl'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: AllSpacesPage(
                area: AllSpacesArea.tasks,
                onSource: (_, _, _) async {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<Checkbox>(taskCheckbox('Zasebno opravilo')).onChanged,
      isNotNull,
    );
    await tester.tap(taskCheckbox('Zasebno opravilo'));
    await tester.pumpAndSettle();
    expect(local.writes, [('local', 'same-task', true, privateKey)]);
    expect(local.state.requireValue.selectedSpaceId, 'other-local');
    expect(
      local.state.requireValue.snapshots['local']!.tasks.single.isCompleted,
      isTrue,
    );
    expect(selected.state.requireValue.tasks.single.isCompleted, isFalse);
    expect(find.text('Zasebno opravilo'), findsNothing);
    expect(find.text('Opravilo izbranega prostora'), findsOneWidget);
    expect(shared.completions, isEmpty);
    expect(shared.opened, isEmpty);
    expect(shared.state.requireValue.allSpacesSelected, isTrue);
    expect(tester.takeException(), isNull);
  });
}
