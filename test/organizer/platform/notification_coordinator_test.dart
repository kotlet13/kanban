import 'package:kanban/organizer/data/local_vault_preferences.dart';
import '../support/local_vault_test_overrides.dart';
import 'package:kanban/organizer/state/notification_local_spaces_provider.dart';
import 'package:kanban/organizer/state/local_notification_preferences_provider.dart';
import 'dart:async';
import 'package:drift/native.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/state/local_database_provider.dart';
import 'package:kanban/organizer/state/local_spaces_provider.dart';
import 'package:kanban/organizer/state/reminder_snooze_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kanban/l10n/app_localizations.dart';
import 'package:kanban/organizer/state/organizer_provider.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';
import 'package:kanban/organizer/platform/notification_coordinator.dart';
import 'package:kanban/organizer/platform/notification_providers.dart';
import 'package:kanban/organizer/platform/local_notification_adapter.dart';
import 'package:kanban/organizer/presentation/planning/device_reminder_settings.dart';
import '../ui/organizer_ui_test.dart' as personal;
import '../ui/sharing_ui_fixture.dart';
import 'local_notification_adapter_test.dart' as fake;
import 'all_local_notifications_test.dart' show Catalog, localSnapshot;

class BrokenOrganizer extends OrganizerController {
  @override
  Future<OrganizerSnapshot> build() async =>
      throw StateError('personal SQLite read failed');
}

class DelayedShared extends SharingUiController {
  DelayedShared(this.gate) : super(initial: CollaborationState());
  final Completer<void> gate;
  @override
  Future<CollaborationState> build() async {
    await gate.future;
    return initial;
  }
}

class FailedShared extends SharingUiController {
  FailedShared() : super(initial: CollaborationState());
  @override
  Future<CollaborationState> build() async =>
      throw StateError('synthetic collaboration unavailable');
  void fail() => state = AsyncError(
    StateError('synthetic collaboration unavailable'),
    StackTrace.current,
  );
}

Widget host(
  List<Override> overrides,
  Widget child, {
  bool useDerivedNotificationCatalog = false,
}) {
  final database = CollaborationDatabase(NativeDatabase.memory());
  addTearDown(database.close);
  return ProviderScope(
    overrides: [
      localVaultTestPreferencesOverride(),
      localDatabaseProvider.overrideWith((ref) async => database),
      if (!useDerivedNotificationCatalog)
        notificationLocalSnapshotsProvider.overrideWith(
          (ref) async => [await ref.watch(organizerProvider.future)],
        ),
      ...overrides,
    ],
    child: MaterialApp(
      locale: const Locale('sl'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: LocalNotificationCoordinator(child: Scaffold(body: child)),
    ),
  );
}

void main() {
  testWidgets(
    'nullable collaboration error preserves empty then personal reminders',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'organizer_local_reminders_enabled_v1': true,
      });
      final due = DateTime.now().add(const Duration(hours: 1));
      final scheduler = fake.FakeScheduler();
      final controller = FailedShared();
      final snapshots = <String, OrganizerSnapshot>{};
      final catalog = Catalog(snapshots);
      await tester.pumpWidget(
        host(
          [
            localSpacesProvider.overrideWith(() => catalog),
            collaborationProvider.overrideWith(() => controller),
            localNotificationSchedulerProvider.overrideWithValue(scheduler),
          ],
          const Text('ready'),
          useDerivedNotificationCatalog: true,
        ),
      );
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.text('ready')),
      );
      expect(container.read(collaborationProvider).hasError, isTrue);
      expect(container.read(collaborationProvider).valueOrNull, isNull);
      expect(
        container.read(notificationLocalSnapshotsProvider).requireValue,
        isEmpty,
      );
      expect(
        container.read(localNotificationPreferencesProvider).hasValue,
        isTrue,
      );
      expect(scheduler.pending, isEmpty);
      snapshots['local'] = localSnapshot('local', 'Only local', due);
      catalog.choose('local');
      await tester.pumpAndSettle();
      expect(scheduler.pending, hasLength(1));
      expect(scheduler.scheduled.values.single.plan.target.isPersonal, isTrue);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'nullable collaboration async recovery retains local and removes stale shared reminders',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'organizer_local_reminders_enabled_v1': true,
      });
      final due = DateTime.now().add(const Duration(hours: 1));
      final scheduler = fake.FakeScheduler();
      final controller = FailedShared();
      await tester.pumpWidget(
        host(
          [
            localSpacesProvider.overrideWith(
              () =>
                  Catalog({'local': localSnapshot('local', 'Only local', due)}),
            ),
            collaborationProvider.overrideWith(() => controller),
            localNotificationSchedulerProvider.overrideWithValue(scheduler),
          ],
          const Text('ready'),
          useDerivedNotificationCatalog: true,
        ),
      );
      await tester.pumpAndSettle();
      expect(scheduler.pending, hasLength(1));
      expect(scheduler.scheduled.values.single.plan.target.isPersonal, isTrue);
      controller.replace(
        CollaborationState(
          session: sharingSession(),
          scopes: [sharingScope()],
          data: {
            sharingScopeId: SharedScopeData(
              tasks: [sharingData().tasks.first.copyWith(dueAt: due)],
            ),
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(scheduler.pending, hasLength(2));
      expect(
        scheduler.scheduled.values
            .where((r) => !r.plan.target.isPersonal)
            .single
            .plan
            .target
            .matches(sharingSession()),
        isTrue,
      );
      // AsyncError retains previous AsyncData in Riverpod. Explicit session
      // removal represents logout; an ensuing error must keep only local data.
      controller.replace(CollaborationState());
      await tester.pumpAndSettle();
      controller.fail();
      await tester.pumpAndSettle();
      expect(scheduler.pending, hasLength(1));
      expect(scheduler.scheduled.values.single.plan.target.isPersonal, isTrue);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'nullable collaboration rejects absent foreign and partial shared plan authority',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'organizer_local_reminders_enabled_v1': true,
      });
      final due = DateTime.now().add(const Duration(hours: 1));
      final scheduler = fake.FakeScheduler();
      final controller = FailedShared();
      final session = sharingSession();
      NotificationTarget target({
        String? serverUrl,
        String? serverId,
        String? accountId,
        bool missingScope = false,
      }) => NotificationTarget(
        serverUrl: serverUrl ?? session.serverUrl,
        serverId: serverId ?? session.serverId,
        accountId: accountId ?? session.accountId,
        scopeId: missingScope ? null : sharingScopeId,
        records: const [
          NotificationRecordTarget(type: 'task', recordId: 'authority-task'),
        ],
      );
      final targets = [
        NotificationTarget(
          records: const [
            NotificationRecordTarget(
              type: 'task',
              recordId: 'local-authority-task',
            ),
          ],
        ),
        target(),
        target(accountId: sharingSession(second: true).accountId),
        target(serverUrl: 'https://other.example.test'),
        target(serverId: 'other-server'),
        target(missingScope: true),
      ];
      await tester.pumpWidget(
        host(
          [
            localSpacesProvider.overrideWith(
              () =>
                  Catalog({'local': localSnapshot('local', 'Only local', due)}),
            ),
            collaborationProvider.overrideWith(() => controller),
            effectiveReminderPlansProvider.overrideWith(
              (ref) async => [
                for (var i = 0; i < targets.length; i++)
                  ReminderPlan(
                    stableKey: 'authority-$i',
                    scheduledAt: due,
                    target: targets[i],
                    reason: 'task',
                  ),
              ],
            ),
            localNotificationSchedulerProvider.overrideWithValue(scheduler),
          ],
          const Text('ready'),
          useDerivedNotificationCatalog: true,
        ),
      );
      await tester.pumpAndSettle();
      expect(scheduler.scheduled.values.map((r) => r.plan.stableKey), [
        'authority-0',
      ]);
      controller.replace(
        CollaborationState(session: session, scopes: [sharingScope()]),
      );
      await tester.pumpAndSettle();
      expect(
        scheduler.scheduled.values.map((r) => r.plan.stableKey),
        unorderedEquals(['authority-0', 'authority-1']),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'shared sound follows the scope preference without a second device sound switch',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'organizer_local_reminders_enabled_v1': true,
        'organizer_local_reminders_sound_v1': false,
      });
      final due = DateTime.now().add(const Duration(hours: 1));
      final scheduler = fake.FakeScheduler();
      final controller = SharingUiController(
        initial: CollaborationState(
          session: sharingSession(),
          scopes: [sharingScope()],
          data: {
            sharingScopeId: SharedScopeData(
              tasks: [sharingData().tasks.first.copyWith(dueAt: due)],
            ),
          },
          notificationPreferences: {
            sharingScopeId: SharedNotificationPreferences(
              scopeId: sharingScopeId,
              categories: const {
                'reminders': SharedNotificationSettings(sound: true),
              },
            ),
          },
        ),
      );
      await tester.pumpWidget(
        host([
          organizerStorageProvider.overrideWithValue(
            () async => personal.MemoryOrganizerStorage(),
          ),
          collaborationProvider.overrideWith(() => controller),
          localNotificationSchedulerProvider.overrideWithValue(scheduler),
        ], const Text('ready')),
      );
      await tester.pumpAndSettle();
      expect(scheduler.scheduled, isNotEmpty);
      expect(scheduler.scheduled.values.every((r) => r.sound), isTrue);
      final container = ProviderScope.containerOf(
        tester.element(find.text('ready')),
      );
      await container
          .read(localNotificationPreferencesProvider.notifier)
          .change('push', false);
      await tester.pumpAndSettle();
      expect(scheduler.pending, isEmpty);
      await container
          .read(localNotificationPreferencesProvider.notifier)
          .change(
            'push',
            true,
            workspace: sharedDeviceNotificationWorkspace(
              sharingSession().partition,
              sharingScopeId,
            ),
          );
      await tester.pumpAndSettle();
      expect(scheduler.pending, isNotEmpty);

      final c = ProviderScope.containerOf(tester.element(find.text('ready')));
      expect(
        (await c.read(
          localNotificationPreferencesProvider.future,
        )).defaults.sound,
        isFalse,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'shared initialization loading retains existing scheduled alarms until identity resolves',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'organizer_local_reminders_enabled_v1': true,
      });
      final scheduler = fake.FakeScheduler(),
          prefs = await SharedPreferences.getInstance();
      final adapter = LocalNotificationAdapter(
        scheduler: scheduler,
        preferences: TestLocalVaultPreferences(prefs),
      );
      await adapter.initialize((_) {});
      await adapter.reconcile([
        fake.request(1, DateTime.now().add(const Duration(hours: 1))),
      ]);
      final gate = Completer<void>();
      await tester.pumpWidget(
        host([
          organizerStorageProvider.overrideWithValue(
            () async => personal.MemoryOrganizerStorage(),
          ),
          collaborationProvider.overrideWith(() => DelayedShared(gate)),
          localNotificationAdapterProvider.overrideWith((ref) async => adapter),
        ], const Text('ready')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(scheduler.pending, hasLength(1));
      expect(scheduler.canceled, isEmpty);
      gate.complete();
      await tester.pumpAndSettle();
      expect(scheduler.pending, isEmpty);
    },
  );
  testWidgets(
    'settings opt-in keeps provider tap callback after settings widget is removed',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final scheduler = fake.FakeScheduler();
      await tester.pumpWidget(
        host(
          [
            organizerStorageProvider.overrideWithValue(
              () async => personal.MemoryOrganizerStorage(),
            ),
            collaborationProvider.overrideWith(
              () => SharingUiController(initial: CollaborationState()),
            ),
            localNotificationSchedulerProvider.overrideWithValue(scheduler),
          ],
          Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) =>
                      const Scaffold(body: DeviceReminderSettings()),
                ),
              ),
              child: const Text('settings'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('settings'));
      await tester.pumpAndSettle();
      final switchFinder = find.byType(SwitchListTile).first;
      await tester.tap(switchFinder);
      await tester.pumpAndSettle();
      expect(scheduler.permissionRequests, 1);
      Navigator.of(tester.element(find.byType(DeviceReminderSettings))).pop();
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.text('settings')),
      );
      scheduler.onOpen!('{"records":[{"type":"task","recordId":"exact"}]}');
      await tester.pump();
      expect(
        container
            .read(notificationLaunchTargetProvider)
            ?.records
            .single
            .recordId,
        'exact',
      );
    },
  );
  testWidgets(
    'delayed adapter completion after account switch schedules only current identity',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'organizer_local_reminders_enabled_v1': true,
      });
      final scheduler = fake.FakeScheduler(),
          gate = Completer<LocalNotificationAdapter>();
      final a = sharingSession(),
          b = sharingSession(second: true),
          date = DateTime.now().add(const Duration(hours: 1));
      CollaborationState value(AccountSession session) => CollaborationState(
        session: session,
        scopes: [sharingScope()],
        data: {
          sharingScopeId: SharedScopeData(
            tasks: [sharingData().tasks.first.copyWith(dueAt: date)],
          ),
        },
      );
      final controller = SharingUiController(initial: value(a));
      await tester.pumpWidget(
        host([
          organizerStorageProvider.overrideWithValue(
            () async => personal.MemoryOrganizerStorage(),
          ),
          collaborationProvider.overrideWith(() => controller),
          localNotificationAdapterProvider.overrideWith((ref) => gate.future),
        ], const Text('ready')),
      );
      await tester.pump();
      controller.replace(value(b));
      await tester.pump();
      final adapter = LocalNotificationAdapter(
        scheduler: scheduler,
        preferences: TestLocalVaultPreferences(
          await SharedPreferences.getInstance(),
        ),
      );
      await adapter.initialize((_) {});
      gate.complete(adapter);
      await tester.pumpAndSettle();
      expect(scheduler.scheduled.values, hasLength(1));
      expect(
        scheduler.scheduled.values.single.plan.target.accountId,
        b.accountId,
      );
    },
  );
  testWidgets(
    'snooze storage failure cancels old alarms after logout and reports the error',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'organizer_local_reminders_enabled_v1': true,
      });
      final scheduler = fake.FakeScheduler();
      final adapter = LocalNotificationAdapter(
        scheduler: scheduler,
        preferences: TestLocalVaultPreferences(
          await SharedPreferences.getInstance(),
        ),
      );
      await adapter.initialize((_) {});
      await adapter.reconcile([
        fake.request(1, DateTime.now().add(const Duration(hours: 1))),
      ]);
      expect(scheduler.pending, hasLength(1));
      final controller = SharingUiController();
      final gate = Completer<List<ReminderPlan>>();
      await tester.pumpWidget(
        host([
          organizerStorageProvider.overrideWithValue(
            () async => personal.MemoryOrganizerStorage(),
          ),
          collaborationProvider.overrideWith(() => controller),
          localNotificationAdapterProvider.overrideWith((ref) async => adapter),
          effectiveReminderPlansProvider.overrideWith((ref) => gate.future),
        ], const Text('ready')),
      );
      await tester.pump();
      controller.replace(CollaborationState());
      await tester.pump();
      gate.completeError(StateError('injected snooze read failure'));
      await tester.pumpAndSettle();
      expect(scheduler.pending, isEmpty);
      expect(scheduler.canceled, isNotEmpty);
      final container = ProviderScope.containerOf(
        tester.element(find.text('ready')),
      );
      expect(
        container.read(localNotificationDeviceStatusProvider).error,
        isA<StateError>(),
      );
      expect(scheduler.scheduleCalls, 1);
    },
  );
  testWidgets(
    'personal SQLite load error cancels existing alarms instead of returning early',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'organizer_local_reminders_enabled_v1': true,
      });
      final scheduler = fake.FakeScheduler();
      final adapter = LocalNotificationAdapter(
        scheduler: scheduler,
        preferences: TestLocalVaultPreferences(
          await SharedPreferences.getInstance(),
        ),
      );
      await adapter.initialize((_) {});
      await adapter.reconcile([
        fake.request(1, DateTime.now().add(const Duration(hours: 1))),
      ]);
      await tester.pumpWidget(
        host([
          organizerProvider.overrideWith(BrokenOrganizer.new),
          collaborationProvider.overrideWith(
            () => SharingUiController(initial: CollaborationState()),
          ),
          localNotificationAdapterProvider.overrideWith((ref) async => adapter),
        ], const Text('ready')),
      );
      await tester.pumpAndSettle();
      expect(scheduler.pending, isEmpty);
      final container = ProviderScope.containerOf(
        tester.element(find.text('ready')),
      );
      expect(
        container.read(localNotificationDeviceStatusProvider).error,
        isA<StateError>(),
      );
      expect(scheduler.scheduleCalls, 1);
    },
  );
  for (final value in ['absent', 'missingSound', 'savedFalse', 'savedTrue']) {
    testWidgets(
      'shared emitted sound defaults on for $value while stored choices remain exact',
      (tester) async {
        SharedPreferences.setMockInitialValues({
          'organizer_local_reminders_enabled_v1': true,
          'organizer_local_reminders_sound_v1': false,
        });
        final scheduler = fake.FakeScheduler();
        final categories = switch (value) {
          'missingSound' => {
            'reminders': SharedNotificationSettings.fromJson({'push': true}),
          },
          'savedFalse' => {
            'reminders': const SharedNotificationSettings(sound: false),
          },
          'savedTrue' => {
            'reminders': const SharedNotificationSettings(sound: true),
          },
          _ => <String, SharedNotificationSettings>{},
        };
        final controller = SharingUiController(
          initial: CollaborationState(
            session: sharingSession(),
            scopes: [sharingScope()],
            data: {
              sharingScopeId: SharedScopeData(
                tasks: [
                  sharingData().tasks.first.copyWith(
                    dueAt: DateTime.now().add(const Duration(hours: 1)),
                  ),
                ],
              ),
            },
            notificationPreferences: value == 'absent'
                ? {}
                : {
                    sharingScopeId: SharedNotificationPreferences(
                      scopeId: sharingScopeId,
                      categories: categories,
                    ),
                  },
          ),
        );
        await tester.pumpWidget(
          host([
            organizerStorageProvider.overrideWithValue(
              () async => personal.MemoryOrganizerStorage(),
            ),
            collaborationProvider.overrideWith(() => controller),
            localNotificationSchedulerProvider.overrideWithValue(scheduler),
          ], const Text('ready')),
        );
        await tester.pumpAndSettle();
        expect(scheduler.scheduled, isNotEmpty);
        expect(
          scheduler.scheduled.values.every(
            (r) => r.sound == (value != 'savedFalse'),
          ),
          isTrue,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final sound in [null, false, true]) {
    testWidgets(
      'device reminder emits absent/saved legacy sound $sound without rewriting settings',
      (tester) async {
        SharedPreferences.setMockInitialValues({
          'organizer_local_reminders_enabled_v1': true,
          if (sound != null) 'organizer_local_reminders_sound_v1': sound,
        });
        final scheduler = fake.FakeScheduler();
        final storage = personal.MemoryOrganizerStorage()
          ..snapshot = localSnapshot(
            'local',
            'Task',
            DateTime.now().add(const Duration(hours: 1)),
          );
        await tester.pumpWidget(
          host([
            organizerStorageProvider.overrideWithValue(() async => storage),
            collaborationProvider.overrideWith(
              () => SharingUiController(initial: CollaborationState()),
            ),
            localNotificationSchedulerProvider.overrideWithValue(scheduler),
          ], const Text('ready')),
        );
        await tester.pumpAndSettle();
        expect(scheduler.scheduled, isNotEmpty);
        expect(
          scheduler.scheduled.values.every((r) => r.sound == (sound ?? true)),
          isTrue,
        );
        expect(
          (await SharedPreferences.getInstance()).getBool(
            'organizer_local_reminders_sound_v1',
          ),
          sound,
        );
        expect(
          (await SharedPreferences.getInstance()).getString(
            LocalNotificationPreferencesController.storageKey,
          ),
          isNull,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
