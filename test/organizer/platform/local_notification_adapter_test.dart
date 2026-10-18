import 'package:kanban/organizer/data/local_vault_preferences.dart';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kanban/organizer/domain/notification_models.dart';
import 'package:kanban/organizer/platform/local_notification_adapter.dart';
import 'package:kanban/organizer/platform/remote_push/system_push_display.dart';
import 'package:kanban/organizer/platform/local_notification_scheduler.dart';

class FakeScheduler implements LocalNotificationScheduler {
  @override
  bool supported = true;
  @override
  bool inexact = false;
  LocalNotificationPermission permission = LocalNotificationPermission.granted;
  final pending = <int>{};
  final presented = <int>{};
  int privacyClears = 0;
  bool failAfterPrivacyClear = false;
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
  Future<void> clearPresentedAndPending() async {
    privacyClears++;
    canceled.addAll(pending.toList()..sort());
    pending.clear();
    presented.clear();
    scheduled.clear();
    if (failAfterPrivacyClear) {
      failAfterPrivacyClear = false;
      throw StateError('interrupted after OS cleanup');
    }
  }

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
      preferences: TestLocalVaultPreferences(prefs),
      now: () => now,
    );
    await adapter.initialize((target) {});
  });

  test(
    'legacy pending presentation is cancelled once then rebuilt from intact reminder requests',
    () async {
      final pending = FakeScheduler()..pending.addAll([41, 42]);
      await prefs.setString(
        'organizer_notification_ids_v1',
        jsonEncode({
          'ids': {'task:1': 41},
          'fingerprints': {'task:1': 'legacy source title'},
          'nextId': 43,
        }),
      );
      final fresh = LocalNotificationAdapter(
        scheduler: pending,
        preferences: TestLocalVaultPreferences(prefs),
        now: () => now,
      );
      final original = request(1, now.add(const Duration(hours: 1)));
      await fresh.initialize((_) {});
      expect(pending.canceled, [41, 42]);
      expect(pending.pending, isEmpty);
      await fresh.reconcile([original]);
      expect(pending.scheduled.values.single.plan.stableKey, 'task:1');
      expect(original.plan.scheduledAt, now.add(const Duration(hours: 1)));
      final reopened = LocalNotificationAdapter(
        scheduler: pending,
        preferences: TestLocalVaultPreferences(prefs),
        now: () => now,
      );
      await reopened.initialize((_) {});
      expect(pending.canceled, [41, 42]);
      expect(
        (jsonDecode(prefs.getString('organizer_notification_ids_v1')!)
            as Map)['presentationVersion'],
        3,
      );
    },
  );
  test(
    'delivered cleanup retries safely and preserves launch and consumed state',
    () async {
      final past = request(1, now.subtract(const Duration(hours: 1)));
      final future = request(2, now.add(const Duration(hours: 1)));
      final seeded = LocalNotificationAdapter(
        scheduler: scheduler,
        preferences: TestLocalVaultPreferences(prefs),
        now: () => now.subtract(const Duration(hours: 2)),
      );
      await seeded.initialize((_) {});
      await seeded.reconcile([past, future]);
      final saved =
          jsonDecode(prefs.getString('organizer_notification_ids_v1')!) as Map;
      saved['presentationVersion'] = 2;
      await prefs.setString('organizer_notification_ids_v1', jsonEncode(saved));
      final os = FakeScheduler()
        ..presented.addAll([99, saved['ids']['task:1'] as int])
        ..pending.add(saved['ids']['task:2'] as int)
        ..launchPayload = jsonEncode(future.plan.target.toJson())
        ..failAfterPrivacyClear = true;
      final recovering = LocalNotificationAdapter(
        scheduler: os,
        preferences: TestLocalVaultPreferences(prefs),
        now: () => now,
      );
      await expectLater(recovering.initialize((_) {}), throwsStateError);
      expect(os.presented, isEmpty);
      expect(os.pending, isEmpty);
      expect(
        (jsonDecode(prefs.getString('organizer_notification_ids_v1')!)
            as Map)['presentationVersion'],
        2,
      );
      final launch = await recovering.initialize((_) {});
      expect(launch?.toJson(), future.plan.target.toJson());
      await recovering.reconcile([past, future]);
      expect(os.privacyClears, 2);
      expect(os.scheduled.values.map((r) => r.plan.stableKey), ['task:2']);
      final reopened = LocalNotificationAdapter(
        scheduler: os,
        preferences: TestLocalVaultPreferences(prefs),
        now: () => now,
      );
      await reopened.initialize((_) {});
      expect(os.privacyClears, 2);
      expect(os.scheduled.values.map((r) => r.plan.stableKey), ['task:2']);
    },
  );

  test(
    'group summary cold launch routes to remote center once, never local target',
    () async {
      final message = SystemPushMessage.tryParse({
        'type': 'familyhub.inbox.v1',
        'serverId': '11111111-1111-4111-a111-111111111111',
        'accountId': '22222222-2222-4222-a222-222222222222',
        'notificationId': '12',
        'displayVersion': '2',
        'title': 'Nakupi',
        'body': 'Dodano korenje',
        'language': 'sl',
        'sound': '0',
      })!;
      final cold = FakeScheduler()
        ..launchPayload = message.payload(summary: true);
      final fresh = LocalNotificationAdapter(
        scheduler: cold,
        preferences: TestLocalVaultPreferences(prefs),
      );
      var localOpens = 0, remoteOpens = 0;
      final result = await fresh.initialize(
        (_) => localOpens++,
        onRemoteOpen: (ref, summary) {
          remoteOpens++;
          expect(summary, true);
          expect(ref.notificationId, 12);
        },
      );
      expect(result, isNull);
      expect(remoteOpens, 1);
      expect(localOpens, 0);
      await fresh.initialize(
        (_) => localOpens++,
        onRemoteOpen: (ref, summary) => remoteOpens++,
      );
      expect(remoteOpens, 1);
      cold.onOpen!(message.payload());
      expect(remoteOpens, 2);
      expect(localOpens, 0);
      cold.onOpen!(
        jsonEncode({
          'type': 'familyhub.system.v2',
          'summary': true,
          'reference': {'type': 'familyhub.inbox.v1'},
        }),
      );
      expect(remoteOpens, 2);
      fresh.dispose();
      cold.onOpen!(message.payload());
      expect(remoteOpens, 2);
    },
  );

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
        preferences: TestLocalVaultPreferences(prefs),
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
        preferences: TestLocalVaultPreferences(prefs),
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
        preferences: TestLocalVaultPreferences(prefs),
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
  test(
    'Darwin shared thread migration replaces future pending once with same ID, keeps local/past/delivered untouched',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      LocalNotificationRequest shared(int index, DateTime time) =>
          LocalNotificationRequest(
            plan: ReminderPlan(
              stableKey: 'shared-$index',
              scheduledAt: time,
              reason: 'task_due',
              target: NotificationTarget(
                serverUrl: 'https://synthetic.invalid',
                serverId: 'server',
                accountId: 'account',
                scopeId: 'scope',
                records: [
                  NotificationRecordTarget(
                    type: 'task',
                    recordId: 'shared-task-$index',
                  ),
                ],
              ),
            ),
            title: 'Shared task',
            body: 'Due',
          );
      final sharedFuture = shared(1, now.add(const Duration(hours: 1)));
      final pastPending = shared(2, now.subtract(const Duration(minutes: 1)));
      final pastDelivered = shared(3, now.subtract(const Duration(minutes: 2)));
      final localFuture = request(4, now.add(const Duration(hours: 2)));
      final requests = [sharedFuture, pastPending, pastDelivered, localFuture];
      final legacy = LocalNotificationAdapter(
        scheduler: scheduler,
        preferences: TestLocalVaultPreferences(prefs),
        now: () => now.subtract(const Duration(days: 1)),
      );
      await legacy.initialize((_) {});
      await legacy.reconcile(requests);
      final oldIds = {
        for (final entry in scheduler.scheduled.entries)
          entry.value.plan.stableKey: entry.key,
      };
      final oldPayloads = {...scheduler.payloads};
      scheduler.pending.remove(oldIds[pastDelivered.plan.stableKey]);
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await adapter.reconcile(requests);
      expect(scheduler.canceled, [oldIds[sharedFuture.plan.stableKey]]);
      expect(scheduler.scheduleCalls, 5);
      expect(
        scheduler.scheduled.entries
            .singleWhere(
              (e) => e.value.plan.stableKey == sharedFuture.plan.stableKey,
            )
            .key,
        oldIds[sharedFuture.plan.stableKey],
      );
      expect(scheduler.payloads, oldPayloads);
      await adapter.reconcile(requests);
      expect(scheduler.scheduleCalls, 5);
      expect(scheduler.canceled, [oldIds[sharedFuture.plan.stableKey]]);
      final later = LocalNotificationAdapter(
        scheduler: scheduler,
        preferences: TestLocalVaultPreferences(prefs),
        now: () => now.add(const Duration(hours: 3)),
      );
      await later.initialize((_) {});
      await later.reconcile(requests);
      expect(scheduler.scheduleCalls, 5);
      expect(scheduler.canceled, [oldIds[sharedFuture.plan.stableKey]]);
    },
  );
}
