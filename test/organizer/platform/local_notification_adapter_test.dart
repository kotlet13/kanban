import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kanban/organizer/domain/notification_models.dart';
import 'package:kanban/organizer/platform/local_notification_adapter.dart';
import 'package:kanban/organizer/platform/local_notification_scheduler.dart';

class FakeScheduler implements LocalNotificationScheduler {
  @override
  bool supported = true;
  @override
  bool inexact = false;
  LocalNotificationPermission permission = LocalNotificationPermission.granted;
  final pending = <int>{};
  final scheduled = <int, LocalNotificationRequest>{};
  final canceled = <int>[];
  final payloads = <int, String>{};
  int scheduleCalls = 0, timezoneCalls = 0, permissionRequests = 0;
  bool failTimezone = false;
  String timezone = 'Europe/Ljubljana';
  String? launchPayload;
  void Function(String)? onOpen;
  Completer<void>? scheduleGate;
  @override
  Future<String?> initialize(void Function(String) callback) async {
    onOpen = callback;
    return launchPayload;
  }

  @override
  Future<LocalNotificationPermission> permissionStatus() async =>
      supported ? permission : LocalNotificationPermission.unsupported;
  @override
  Future<LocalNotificationPermission> requestPermission() async {
    permissionRequests++;
    return permission;
  }

  @override
  Future<String> refreshTimezone() async {
    timezoneCalls++;
    if (failTimezone) throw StateError('Timezone unavailable');
    return timezone;
  }

  @override
  Future<Set<int>> pendingIds() async => {...pending};
  @override
  Future<void> cancel(int id) async {
    canceled.add(id);
    pending.remove(id);
    scheduled.remove(id);
  }

  @override
  Future<void> schedule(
    int id,
    LocalNotificationRequest request,
    String payload,
  ) async {
    scheduleCalls++;
    if (scheduleGate != null) await scheduleGate!.future;
    pending.add(id);
    scheduled[id] = request;
    payloads[id] = payload;
  }
}

LocalNotificationRequest request(int index, DateTime at) =>
    LocalNotificationRequest(
      plan: ReminderPlan(
        stableKey: 'task:$index',
        scheduledAt: at,
        reason: 'task.due',
        target: NotificationTarget(
          records: [
            NotificationRecordTarget(type: 'task', recordId: 'task-$index'),
          ],
        ),
      ),
      title: 'Vsakdan',
      body: 'Odpri aplikacijo za svoj opomnik.',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime.utc(2026, 10, 4, 10);
  late SharedPreferences prefs;
  late FakeScheduler scheduler;
  late LocalNotificationAdapter adapter;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    scheduler = FakeScheduler();
    adapter = LocalNotificationAdapter(
      scheduler: scheduler,
      preferences: prefs,
      now: () => now,
    );
    await adapter.initialize((target) {});
  });

  test(
    'moving future reminder into past cancels pending and delivered IDs',
    () async {
      await adapter.initialize((_) {});
      await adapter.reconcile([
        request(1, now.add(const Duration(minutes: 5))),
      ]);
      final id = scheduler.pending.single;
      await adapter.reconcile([
        request(1, now.subtract(const Duration(minutes: 1))),
      ]);
      expect(scheduler.pending, isEmpty);
      expect(scheduler.canceled, contains(id));
      expect(scheduler.scheduleCalls, 1);
      await adapter.reconcile([
        request(2, now.add(const Duration(minutes: 5))),
      ]);
      final deliveredId = scheduler.pending.single;
      scheduler.pending.clear();
      await adapter.reconcile([
        request(2, now.subtract(const Duration(minutes: 1))),
      ]);
      expect(scheduler.canceled, contains(deliveredId));
      expect(scheduler.scheduleCalls, 2);
    },
  );

  test(
    'nearest 60 survive adapter restart with same persistent IDs; unchanged plans avoid plugin churn',
    () async {
      final plans = [
        for (var i = 100; i > 0; i--) request(i, now.add(Duration(minutes: i))),
      ];
      final status = await adapter.reconcile(plans);
      expect(status.scheduledCount, 60);
      expect(status.deferredCount, 40);
      expect(scheduler.scheduled.values.map((r) => r.plan.stableKey).toSet(), {
        for (var i = 1; i <= 60; i++) 'task:$i',
      });
      final ids = {...scheduler.payloads};
      final restarted = LocalNotificationAdapter(
        scheduler: scheduler,
        preferences: prefs,
        now: () => now,
      );
      await restarted.initialize((target) {});
      await restarted.reconcile(plans);
      expect(scheduler.payloads, ids);
      expect(scheduler.scheduleCalls, 60);
      expect(scheduler.permissionRequests, 0);
    },
  );

  test(
    'timezone change reconciles scheduled dates; completion removes stale IDs',
    () async {
      final plans = [
        request(1, now.add(const Duration(hours: 1))),
        request(2, now.add(const Duration(hours: 2))),
      ];
      await adapter.reconcile(plans);
      scheduler.timezone = 'America/New_York';
      await adapter.reconcile(plans);
      expect(scheduler.scheduleCalls, 4);
      final removed = scheduler.scheduled.entries
          .firstWhere((e) => e.value.plan.stableKey == 'task:1')
          .key;
      await adapter.reconcile([plans.last]);
      expect(scheduler.canceled, contains(removed));
      expect(scheduler.scheduled.values.single.plan.stableKey, 'task:2');
    },
  );

  test(
    'logout cancelAll cancels before failing timezone lookup and needs no timezone',
    () async {
      await adapter.reconcile([request(1, now.add(const Duration(hours: 1)))]);
      scheduler.failTimezone = true;
      await adapter.cancelAll();
      expect(scheduler.pending, isEmpty);
      expect(scheduler.scheduled, isEmpty);
      expect(scheduler.timezoneCalls, 1);
    },
  );

  test(
    'revoked target cancels before timezone failure on remaining target',
    () async {
      final one = request(1, now.add(const Duration(hours: 1))),
          two = request(2, now.add(const Duration(hours: 2)));
      await adapter.reconcile([one, two]);
      scheduler.failTimezone = true;
      final removed = scheduler.scheduled.entries
          .firstWhere((e) => e.value.plan.stableKey == 'task:1')
          .key;
      await expectLater(adapter.reconcile([two]), throwsStateError);
      expect(scheduler.canceled, contains(removed));
      expect(scheduler.scheduled.values.single.plan.stableKey, 'task:2');
    },
  );

  test(
    'nominally past inexact pending alarm survives resume but is never newly scheduled',
    () async {
      final one = request(1, now.add(const Duration(minutes: 1)));
      await adapter.reconcile([one]);
      final later = LocalNotificationAdapter(
        scheduler: scheduler,
        preferences: prefs,
        now: () => now.add(const Duration(minutes: 2)),
      );
      await later.initialize((target) {});
      await later.reconcile([one]);
      expect(scheduler.pending.length, 1);
      expect(scheduler.scheduleCalls, 1);
      scheduler.pending.clear();
      await later.reconcile([one]);
      expect(scheduler.scheduleCalls, 1);
      expect(scheduler.canceled, isEmpty);
      await later.cancelAll();
      expect(scheduler.canceled.length, 1);
      await later.reconcile([request(2, now)]);
      expect(scheduler.scheduleCalls, 1);
    },
  );

  test(
    'late schedule is cancelled when identity requests are replaced',
    () async {
      scheduler.scheduleGate = Completer<void>();
      final first = adapter.reconcile([
        request(1, now.add(const Duration(hours: 1))),
      ]);
      while (scheduler.scheduleCalls == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      final logout = adapter.cancelAll();
      scheduler.scheduleGate!.complete();
      await first;
      await logout;
      expect(scheduler.pending, isEmpty);
      expect(scheduler.canceled, isNotEmpty);
    },
  );

  test(
    'launch and foreground taps contain exact references only, invalid payload ignored',
    () async {
      final target = request(1, now).plan.target;
      scheduler.launchPayload = jsonEncode(target.toJson());
      final opened = <NotificationTarget>[];
      final fresh = LocalNotificationAdapter(
        scheduler: scheduler,
        preferences: prefs,
        now: () => now,
      );
      final launch = await fresh.initialize(opened.add);
      expect(launch!.records.single.recordId, 'task-1');
      scheduler.onOpen!(jsonEncode(target.toJson()));
      expect(opened.single.records.single.recordId, 'task-1');
      scheduler.onOpen!('{"token":"secret","records":[]}');
      expect(opened.length, 1);
      await fresh.reconcile([request(2, now.add(const Duration(hours: 1)))]);
      final payload = jsonDecode(scheduler.payloads.values.last) as Map;
      expect(payload.keys.toSet(), {
        'serverUrl',
        'serverId',
        'accountId',
        'scopeId',
        'records',
        'inboxIds',
      });
      expect(payload.toString(), isNot(contains('Odpri aplikacijo')));
    },
  );

  test(
    'unsupported platform does not schedule or query timezone; denied permission cancels',
    () async {
      scheduler.supported = false;
      final status = await adapter.reconcile([
        request(1, now.add(const Duration(hours: 1))),
      ]);
      expect(status.permission, LocalNotificationPermission.unsupported);
      expect(scheduler.timezoneCalls, 0);
      expect(scheduler.scheduleCalls, 0);
      scheduler.supported = true;
      await adapter.reconcile([request(1, now.add(const Duration(hours: 1)))]);
      scheduler.permission = LocalNotificationPermission.denied;
      await adapter.reconcile([request(1, now.add(const Duration(hours: 1)))]);
      expect(scheduler.pending, isEmpty);
    },
  );
}
