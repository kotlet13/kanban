import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kanban/l10n/app_localizations.dart';
import 'package:kanban/organizer/state/organizer_provider.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';
import 'package:kanban/organizer/platform/notification_coordinator.dart';
import 'package:kanban/organizer/platform/notification_providers.dart';
import 'package:kanban/organizer/platform/local_notification_adapter.dart';
import 'package:kanban/organizer/presentation/planning/device_reminder_settings.dart';
import '../ui/organizer_ui_test.dart' as personal;
import '../ui/sharing_ui_fixture.dart';
import 'local_notification_adapter_test.dart' as fake;

class DelayedShared extends SharingUiController {
  DelayedShared(this.gate) : super(initial: CollaborationState());
  final Completer<void> gate;
  @override
  Future<CollaborationState> build() async {
    await gate.future;
    return initial;
  }
}

Widget host(List<Override> overrides, Widget child) => ProviderScope(
  overrides: overrides,
  child: MaterialApp(
    locale: const Locale('sl'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: LocalNotificationCoordinator(child: Scaffold(body: child)),
  ),
);
void main() {
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
        preferences: prefs,
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
        data: {sharingScopeId: sharingData()},
        scheduledReminders: [
          SharedScheduledReminder(
            id: 'reminder',
            scopeId: sharingScopeId,
            targetType: 'task',
            targetId: 'task',
            remindAt: date,
            revision: 1,
            state: 'pending',
          ),
        ],
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
        preferences: await SharedPreferences.getInstance(),
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
}
