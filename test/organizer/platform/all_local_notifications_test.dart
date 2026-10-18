import '../support/local_vault_test_overrides.dart';
import 'package:kanban/organizer/state/local_notification_preferences_provider.dart';
import 'package:kanban/organizer/state/inbox_projection_provider.dart';
import 'package:kanban/organizer/state/reminder_snooze_provider.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kanban/l10n/app_localizations.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'package:kanban/organizer/domain/organizer_projections.dart';
import 'package:kanban/organizer/domain/inbox_projection.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/organizer_repository.dart';
import 'package:kanban/organizer/data/sqlite_organizer_storage.dart';
import 'package:kanban/organizer/data/local_spaces_repository.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';
import 'package:kanban/organizer/state/local_database_provider.dart';
import 'package:kanban/organizer/state/local_spaces_provider.dart';
import 'package:kanban/organizer/state/organizer_provider.dart';
import 'package:kanban/organizer/platform/notification_coordinator.dart';
import 'package:kanban/organizer/platform/notification_providers.dart';
import 'package:kanban/organizer/presentation/inbox/visible_task_target_view.dart';
import '../ui/sharing_ui_fixture.dart';
import 'local_notification_adapter_test.dart' as fake;

OrganizerSnapshot localSnapshot(String workspace, String title, DateTime due) =>
    OrganizerSnapshot(
      workspaceKey: workspace,
      tasks: [
        LocalTask(
          id: 'same-task',
          title: title,
          notes: '',
          projectId: null,
          dueAt: due,
          isCompleted: false,
          createdAt: due.subtract(const Duration(days: 1)),
          updatedAt: due.subtract(const Duration(days: 1)),
        ),
      ],
      reminders: [
        LocalReminder(
          id: 'same-reminder',
          taskId: 'same-task',
          dueAt: due,
          createdAt: due.subtract(const Duration(days: 1)),
          isRead: false,
        ),
      ],
    );

class Catalog extends LocalSpacesController {
  Catalog(this.snapshots);
  final Map<String, OrganizerSnapshot> snapshots;
  @override
  Future<LocalSpacesState> build() async => LocalSpacesState(
    spaces: [
      const LocalSpace(id: 'local', name: '', kind: LocalSpaceKind.personal),
      const LocalSpace(
        id: 'house-a',
        name: 'QA dom A',
        kind: LocalSpaceKind.household,
      ),
      const LocalSpace(
        id: 'house-b',
        name: 'QA dom B',
        kind: LocalSpaceKind.household,
      ),
    ],
    snapshots: snapshots,
  );
  void choose(String id) => state = AsyncData(
    LocalSpacesState(
      spaces: state.requireValue.spaces,
      selectedSpaceId: id,
      snapshots: snapshots,
    ),
  );
}

class Selected extends OrganizerController {
  Selected(this.first);
  final OrganizerSnapshot first;
  @override
  Future<OrganizerSnapshot> build() async => first;
  void choose(OrganizerSnapshot snapshot) => state = AsyncData(snapshot);
}

void main() {
  testWidgets(
    'project sound and delivery exceptions reschedule only their own local alarm',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'organizer_local_reminders_enabled_v1': true,
        'organizer_local_reminders_sound_v1': false,
      });
      final due = DateTime.now().add(const Duration(hours: 1));
      final a = localSnapshot('house-a', 'A', due);
      final b = localSnapshot('house-b', 'B', due);
      final snapshots = {
        'house-a': a.copyWith(
          tasks: [a.tasks.single.copyWith(projectId: 'p1')],
        ),
        'house-b': b,
      };
      final scheduler = fake.FakeScheduler();
      final db = CollaborationDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localVaultTestPreferencesOverride(),
            localDatabaseProvider.overrideWith((ref) async => db),
            localSpacesProvider.overrideWith(() => Catalog(snapshots)),
            organizerProvider.overrideWith(
              () => Selected(snapshots['house-a']!),
            ),
            collaborationProvider.overrideWith(
              () => SharingUiController(initial: CollaborationState()),
            ),
            localNotificationSchedulerProvider.overrideWithValue(scheduler),
          ],
          child: MaterialApp(
            locale: const Locale('sl'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const LocalNotificationCoordinator(
              child: Scaffold(body: Text('ready')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(scheduler.pending, hasLength(2));
      final c = ProviderScope.containerOf(tester.element(find.text('ready')));
      await c
          .read(localNotificationPreferencesProvider.notifier)
          .change('sound', true, workspace: 'house-a', project: 'p1');
      await tester.pumpAndSettle();
      expect(
        scheduler.scheduled.values
            .singleWhere((r) => r.plan.target.localWorkspaceId == 'house-a')
            .sound,
        isTrue,
      );
      expect(
        scheduler.scheduled.values
            .singleWhere((r) => r.plan.target.localWorkspaceId == 'house-b')
            .sound,
        isFalse,
      );
      await c
          .read(localNotificationPreferencesProvider.notifier)
          .change('push', false, workspace: 'house-a', project: 'p1');
      await tester.pumpAndSettle();
      expect(
        scheduler.scheduled.values.single.plan.target.localWorkspaceId,
        'house-b',
      );
      expect(scheduler.canceled.toSet(), hasLength(1));
      await c
          .read(localNotificationPreferencesProvider.notifier)
          .change('push', true);
      await tester.pumpAndSettle();
      expect(scheduler.pending, hasLength(2));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'per-project in-app optout updates the inbox and unread badge together',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final due = DateTime.now().subtract(const Duration(hours: 1));
      final original = localSnapshot('house-a', 'A', due);
      final snap = original.copyWith(
        tasks: [original.tasks.single.copyWith(projectId: 'p1')],
      );
      final db = CollaborationDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localVaultTestPreferencesOverride(),
            localDatabaseProvider.overrideWith((ref) async => db),
            localSpacesProvider.overrideWith(() => Catalog({'house-a': snap})),
            organizerProvider.overrideWith(() => Selected(snap)),
            collaborationProvider.overrideWith(
              () => SharingUiController(initial: CollaborationState()),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) {
                  ref.watch(effectiveReminderPlansProvider);
                  return Text(
                    '${ref.watch(organizerInboxProjectionProvider).local.length}:${ref.watch(organizerInboxHasUnreadProvider)}',
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('1:true'), findsOneWidget);
      final c = ProviderScope.containerOf(tester.element(find.text('1:true')));
      await c
          .read(localNotificationPreferencesProvider.notifier)
          .change('inApp', false, workspace: 'house-a', project: 'p1');
      await tester.pumpAndSettle();
      expect(find.text('0:false'), findsOneWidget);
      expect(snap.reminders.single.isRead, isFalse);
      expect(snap.tasks.single.isCompleted, isFalse);
      await c
          .read(localNotificationPreferencesProvider.notifier)
          .change('inApp', true);
      await tester.pumpAndSettle();
      expect(find.text('1:true'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'all local tasks keep unique alarms and inbox sources with legacy default keys',
    () {
      final due = DateTime.utc(2026, 10, 9);
      final snapshots = [
        localSnapshot('local', 'QA osebno', due),
        localSnapshot('house-a', 'QA dom A', due),
        localSnapshot('house-b', 'QA dom B', due),
      ];
      final plans = desiredReminderPlans(
        personal: snapshots.last,
        shared: CollaborationState(),
        localSnapshots: snapshots,
      );
      expect(plans.map((p) => p.stableKey).toSet(), {
        'personal:task:same-task:due',
        'local:house-a:task:same-task:due',
        'local:house-b:task:same-task:due',
      });
      expect(plans.map((p) => p.target.localWorkspaceId), [
        'local',
        'house-a',
        'house-b',
      ]);
      expect(plans.first.target.toJson().containsKey('localSpaceId'), isFalse);
      final inbox = projectOrganizerInbox(
        personal: snapshots.last,
        shared: CollaborationState(),
        localSnapshots: snapshots,
        effectivePlans: plans,
        now: due.add(const Duration(hours: 1)),
      );
      expect(inbox.local.map((r) => r.task!.title), [
        'QA osebno',
        'QA dom A',
        'QA dom B',
      ]);
      expect(inbox.hasUnread({}), isTrue);
    },
  );
  testWidgets(
    'switching local editor retains every other local alarm without cancellations',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'organizer_local_reminders_enabled_v1': true,
      });
      final due = DateTime.now().add(const Duration(hours: 1));
      final snapshots = {
        for (final id in ['local', 'house-a', 'house-b'])
          id: localSnapshot(id, 'QA $id', due),
      };
      final catalog = Catalog(snapshots),
          selected = Selected(snapshots['local']!);
      final scheduler = fake.FakeScheduler(),
          database = CollaborationDatabase(NativeDatabase.memory());
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        await database.close();
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localVaultTestPreferencesOverride(),
            localDatabaseProvider.overrideWith((ref) async => database),
            localSpacesProvider.overrideWith(() => catalog),
            organizerProvider.overrideWith(() => selected),
            collaborationProvider.overrideWith(
              () => SharingUiController(initial: CollaborationState()),
            ),
            localNotificationSchedulerProvider.overrideWithValue(scheduler),
          ],
          child: MaterialApp(
            locale: const Locale('sl'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: LocalNotificationCoordinator(
              child: Scaffold(
                body: Consumer(
                  builder: (context, ref, _) => Text(
                    ref.watch(organizerProvider).valueOrNull?.workspaceKey ??
                        'QA',
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(scheduler.pending, hasLength(3));
      final keys = scheduler.scheduled.values
          .map((r) => r.plan.stableKey)
          .toSet();
      catalog.choose('house-a');
      selected.choose(snapshots['house-a']!);
      await tester.pumpAndSettle();
      catalog.choose('house-b');
      selected.choose(snapshots['house-b']!);
      await tester.pumpAndSettle();
      expect(scheduler.pending, hasLength(3));
      expect(
        scheduler.scheduled.values.map((r) => r.plan.stableKey).toSet(),
        keys,
      );
      expect(scheduler.canceled, isEmpty);
    },
  );
  testWidgets(
    'named local tap and old default tap resolve identical IDs in their exact spaces',
    (tester) async {
      final database = CollaborationDatabase(NativeDatabase.memory());
      late String householdId;
      await tester.runAsync(() async {
        final personal = OrganizerRepository(
          SqliteOrganizerStorage(database),
          idGenerator: () => 'same-task',
        );
        await personal.initialize();
        await personal.createTask(title: 'QA pravo osebno opravilo');
        final household = await LocalSpacesRepository(
          database,
        ).createSpace(kind: LocalSpaceKind.household, name: 'QA pravi dom');
        householdId = household.id;
        final shared = OrganizerRepository(
          SqliteOrganizerStorage(database, workspaceId: householdId),
          idGenerator: () => 'same-task',
        );
        await shared.initialize();
        await shared.createTask(title: 'QA pravo gospodinjsko opravilo');
        await personal.close();
        await shared.close();
      });
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(database.close);
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localVaultTestPreferencesOverride(),
            localDatabaseProvider.overrideWith((ref) async => database),
            organizerStorageProvider.overrideWithValue(
              () async => SqliteOrganizerStorage(database),
            ),
            collaborationProvider.overrideWith(
              () => SharingUiController(initial: CollaborationState()),
            ),
          ],
          child: MaterialApp(
            locale: const Locale('sl'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) => Column(
                  children: [
                    TextButton(
                      onPressed: () => showVisibleTaskTarget(
                        context,
                        ref,
                        NotificationTarget(
                          localSpaceId: householdId,
                          records: const [
                            NotificationRecordTarget(
                              type: 'task',
                              recordId: 'same-task',
                            ),
                          ],
                        ),
                      ),
                      child: const Text('Named'),
                    ),
                    TextButton(
                      onPressed: () => showVisibleTaskTarget(
                        context,
                        ref,
                        NotificationTarget(
                          records: const [
                            NotificationRecordTarget(
                              type: 'task',
                              recordId: 'same-task',
                            ),
                          ],
                        ),
                      ),
                      child: const Text('Old default'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Named'));
      await tester.pumpAndSettle();
      expect(find.text('QA pravo gospodinjsko opravilo'), findsOneWidget);
      expect(find.text('QA pravo osebno opravilo'), findsNothing);
      await tester.tap(find.text('Zapri'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Old default'));
      await tester.pumpAndSettle();
      expect(find.text('QA pravo osebno opravilo'), findsOneWidget);
      expect(find.text('QA pravo gospodinjsko opravilo'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
