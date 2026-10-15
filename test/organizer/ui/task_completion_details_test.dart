import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kanban/l10n/app_localizations.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'package:kanban/organizer/presentation/inbox/visible_task_target_view.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';
import 'package:kanban/organizer/state/local_spaces_provider.dart';
import 'package:kanban/organizer/state/organizer_provider.dart';
import 'sharing_ui_fixture.dart';
import 'organizer_ui_test.dart' show MemoryOrganizerStorage;

class Catalog extends LocalSpacesController {
  @override
  Future<LocalSpacesState> build() async => LocalSpacesState(
    spaces: const [
      LocalSpace(id: 'local', name: 'Personal', kind: LocalSpaceKind.personal),
    ],
  );
}

CollaborationState taskState({
  bool completed = false,
  SharedRole role = SharedRole.member,
  bool secondAccount = false,
  bool archivedParent = false,
}) => CollaborationState(
  session: sharingSession(second: secondAccount),
  scopes: [sharingScope(role: role)],
  data: {
    sharingScopeId: SharedScopeData(
      projects: [
        sharingData().projects.single.copyWith(archived: archivedParent),
      ],
      tasks: [sharingData().tasks.single.copyWith(isCompleted: completed)],
    ),
  },
);

class TaskController extends SharingUiController {
  TaskController({
    bool completed = false,
    SharedRole role = SharedRole.member,
    bool archivedParent = false,
  }) : super(
         initial: taskState(
           completed: completed,
           role: role,
           archivedParent: archivedParent,
         ),
       );
  final completions = <(String, String, bool)>[];
  final saves = <(String, LocalTask)>[];
  @override
  Future<NotificationOpenResult> refreshVisibleTaskTarget(
    NotificationTarget target,
  ) async => NotificationOpenResult(
    status: NotificationOpenStatus.offline,
    target: target,
  );
  void saved(LocalTask task) {
    final current = state.requireValue;
    replace(
      CollaborationState(
        session: current.session,
        scopes: current.scopes,
        data: {
          sharingScopeId: SharedScopeData(
            projects: current.dataForScope(sharingScopeId).projects,
            tasks: [task],
          ),
        },
      ),
    );
  }

  @override
  Future<void> setTaskCompleted(String scopeId, String id, bool value) async {
    completions.add((scopeId, id, value));
    saved(
      state.requireValue
          .dataForScope(scopeId)
          .tasks
          .single
          .copyWith(isCompleted: value),
    );
  }

  @override
  Future<void> updateTask(String scopeId, LocalTask task) async {
    saves.add((scopeId, task));
    saved(task);
  }
}

NotificationTarget target() => NotificationTarget(
  serverUrl: sharingSession().serverUrl,
  serverId: sharingSession().serverId,
  accountId: sharingSession().accountId,
  scopeId: sharingScopeId,
  records: const [NotificationRecordTarget(type: 'task', recordId: 'task')],
);
Future<void> host(
  WidgetTester tester,
  TaskController controller, {
  MemoryOrganizerStorage? storage,
  bool personal = false,
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(390, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        collaborationProvider.overrideWith(() => controller),
        localSpacesProvider.overrideWith(Catalog.new),
        organizerStorageProvider.overrideWithValue(
          () async => storage ?? MemoryOrganizerStorage(),
        ),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) {
              ref.watch(organizerProvider);
              ref.watch(collaborationProvider);
              return TextButton(
                onPressed: () => showVisibleTaskTarget(
                  context,
                  ref,
                  personal
                      ? NotificationTarget(
                          records: const [
                            NotificationRecordTarget(
                              type: 'task',
                              recordId: 'local-task',
                            ),
                          ],
                        )
                      : target(),
                ),
                child: const Text('Open task'),
              );
            },
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> open(WidgetTester tester) async {
  await tester.tap(find.text('Open task'));
  await tester.pumpAndSettle();
}

Future<void> edit(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Edit task'));
  await tester.tap(find.text('Edit task'));
  await tester.pumpAndSettle();
}

Future<void> toggle(WidgetTester tester) async {
  final field = find.byKey(const ValueKey('organizer-task-completed'));
  await tester.ensureVisible(field);
  await tester.tap(field);
  await tester.pumpAndSettle();
}

Future<void> save(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('organizer-save')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'shared offline detail completes/reopens exact scoped task; editor Cancel does not save the draft',
    (tester) async {
      final controller = TaskController();
      await host(tester, controller);
      await open(tester);
      final field = find.byKey(const ValueKey('task-detail-completed-task'));
      await tester.tap(field);
      await tester.pumpAndSettle();
      expect(controller.completions, [(sharingScopeId, 'task', true)]);
      expect(tester.widget<CheckboxListTile>(field).value, true);
      await tester.tap(field);
      await tester.pumpAndSettle();
      expect(controller.completions.last, (sharingScopeId, 'task', false));
      await edit(tester);
      await toggle(tester);
      expect(controller.saves, isEmpty);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(controller.saves, isEmpty);
      expect(
        controller.state.requireValue
            .dataForScope(sharingScopeId)
            .tasks
            .single
            .isCompleted,
        false,
      );
      await edit(tester);
      await toggle(tester);
      await save(tester);
      expect(controller.saves.single.$1, sharingScopeId);
      expect(controller.saves.single.$2.id, 'task');
      expect(controller.saves.single.$2.isCompleted, true);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'completed editor retains status on title edit and explicitly reopens on Save',
    (tester) async {
      final controller = TaskController(completed: true);
      await host(tester, controller);
      await open(tester);
      await edit(tester);
      expect(
        tester
            .widget<CheckboxListTile>(
              find.byKey(const ValueKey('organizer-task-completed')),
            )
            .value,
        true,
      );
      await tester.enterText(
        find.byKey(const ValueKey('organizer-title-field')),
        'Renamed completed task',
      );
      await save(tester);
      expect(controller.saves.single.$2.isCompleted, true);
      expect(controller.saves.single.$2.title, 'Renamed completed task');
      await edit(tester);
      await toggle(tester);
      await save(tester);
      expect(controller.saves.last.$2.isCompleted, false);
      expect(tester.takeException(), isNull);
    },
  );
  for (final archived in [false, true]) {
    testWidgets(
      'readonly viewer/archived-parent=$archived task cannot complete or open an editor',
      (tester) async {
        final controller = TaskController(
          role: archived ? SharedRole.member : SharedRole.viewer,
          archivedParent: archived,
        );
        await host(tester, controller);
        await open(tester);
        final field = find.byKey(const ValueKey('task-detail-completed-task'));
        expect(tester.widget<CheckboxListTile>(field).onChanged, isNull);
        expect(find.text('Edit task'), findsNothing);
        await tester.tap(field);
        await tester.pumpAndSettle();
        expect(controller.completions, isEmpty);
        expect(controller.saves, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'account change closes modified editor without saving completion',
    (tester) async {
      final controller = TaskController();
      await host(tester, controller);
      await open(tester);
      await edit(tester);
      await toggle(tester);
      controller.replace(taskState(secondAccount: true));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('organizer-save')), findsNothing);
      expect(controller.completions, isEmpty);
      expect(controller.saves, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'local linked-cost editor saves completion and detail reopens without changing expense',
    (tester) async {
      final now = DateTime.now().toUtc();
      final storage = MemoryOrganizerStorage()
        ..snapshot = OrganizerSnapshot(
          tasks: [
            LocalTask(
              id: 'local-task',
              projectId: null,
              dueAt: null,
              title: 'Local task',
              notes: '',
              isCompleted: false,
              createdAt: now,
              updatedAt: now,
            ),
          ],
          financeEntries: [
            FinanceEntry(
              id: 'cost',
              projectId: null,
              taskId: 'local-task',
              title: 'Cost',
              notes: '',
              status: FinanceEntryStatus.planned,
              kind: FinanceEntryKind.expense,
              amountMinor: 700,
              currency: 'EUR',
              occurredAt: now,
              createdAt: now,
              updatedAt: now,
            ),
          ],
        );
      await host(tester, TaskController(), storage: storage, personal: true);
      await open(tester);
      await edit(tester);
      await toggle(tester);
      await save(tester);
      expect(storage.snapshot.tasks.single.isCompleted, true);
      expect(storage.snapshot.financeEntries.single.amountMinor, 700);
      expect(storage.snapshot.financeEntries.single.taskId, 'local-task');
      await tester.tap(
        find.byKey(const ValueKey('task-detail-completed-local-task')),
      );
      await tester.pumpAndSettle();
      expect(storage.snapshot.tasks.single.isCompleted, false);
      expect(tester.takeException(), isNull);
    },
  );
}
