import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:kanban/organizer/domain/notification_models.dart';
import 'package:kanban/organizer/platform/local_notification_scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/platform/flutter_notification_scheduler.dart';
import 'package:timezone/data/latest_all.dart' as data;
import 'package:timezone/timezone.dart' as tz;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final identifier in ['Europe/Ljubljana', 'US/Eastern']) {
    test(
      'native timezone alias $identifier resolves without UTC fallback',
      () async {
        data.initializeTimeZones();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('flutter_timezone'),
              (call) async => {'identifier': identifier},
            );
        addTearDown(
          () => TestDefaultBinaryMessengerBinding
              .instance
              .defaultBinaryMessenger
              .setMockMethodCallHandler(
                const MethodChannel('flutter_timezone'),
                null,
              ),
        );
        final result = await FlutterNotificationScheduler().refreshTimezone();
        expect(result, identifier);
        expect(tz.local.name, identifier);
        expect(
          tz.TZDateTime(tz.local, 2026, 10, 4).timeZoneOffset,
          identifier == 'Europe/Ljubljana'
              ? const Duration(hours: 2)
              : const Duration(hours: -4),
        );
      },
    );
  }
  for (final platform in [
    TargetPlatform.iOS,
    TargetPlatform.macOS,
    TargetPlatform.android,
  ]) {
    test(
      '$platform native scheduling groups shared Darwin threads exactly like published APNs and preserves local/Android groups',
      () async {
        debugDefaultTargetPlatformOverride = platform;
        switch (platform) {
          case TargetPlatform.iOS:
            IOSFlutterLocalNotificationsPlugin.registerWith();
          case TargetPlatform.macOS:
            MacOSFlutterLocalNotificationsPlugin.registerWith();
          default:
            AndroidFlutterLocalNotificationsPlugin.registerWith();
        }
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        data.initializeTimeZones();
        tz.setLocalLocation(tz.UTC);
        const channel = MethodChannel(
          'dexterous.com/flutter/local_notifications',
        );
        final captured = <Map<dynamic, dynamic>>[];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              if (call.method == 'zonedSchedule') {
                captured.add(call.arguments as Map);
              }
              if (call.method == 'initialize') return true;
              return null;
            });
        addTearDown(
          () => TestDefaultBinaryMessengerBinding
              .instance
              .defaultBinaryMessenger
              .setMockMethodCallHandler(channel, null),
        );
        final scheduler = FlutterNotificationScheduler();
        await scheduler.initialize((_) {});
        const server = '11111111-1111-4111-a111-111111111111';
        const account = '22222222-2222-4222-a222-222222222222';
        // SHA256 golden from the published PHP hash('sha256', serverId:accountId).
        const apnsThread =
            'f484a0bc7118fb544b9279a77ea41bd09fdeb30c06c353d5d8c51925dfb32846';
        final targets = [
          NotificationTarget(
            serverUrl: 'https://synthetic.invalid',
            serverId: server,
            accountId: account,
            scopeId: 'scope-a',
            records: const [],
          ),
          NotificationTarget(
            serverUrl: 'https://synthetic.invalid',
            serverId: server,
            accountId: account,
            scopeId: 'scope-b',
            records: const [],
          ),
          NotificationTarget(
            serverUrl: 'https://synthetic.invalid',
            serverId: server,
            accountId: 'another-account',
            scopeId: 'scope-a',
            records: const [],
          ),
          NotificationTarget(
            serverUrl: 'https://synthetic.invalid',
            serverId: 'another-server',
            accountId: account,
            scopeId: 'scope-a',
            records: const [],
          ),
          NotificationTarget(localSpaceId: 'local-home', records: const []),
        ];
        for (var index = 0; index < targets.length; index++) {
          await scheduler.schedule(
            index + 1,
            LocalNotificationRequest(
              plan: ReminderPlan(
                stableKey: 'test-$index',
                scheduledAt: DateTime.now().toUtc().add(
                  const Duration(days: 1),
                ),
                target: targets[index],
                reason: 'task_due',
              ),
              title: 'Task',
              body: 'Due',
            ),
            'routing-$index',
          );
        }
        expect(captured, hasLength(5));
        final specifics = captured
            .map((row) => row['platformSpecifics'] as Map)
            .toList();
        if (platform == TargetPlatform.android) {
          expect(specifics[0]['groupKey'], 'jivie.$server.$account');
          expect(specifics[1]['groupKey'], 'jivie.$server.$account');
          expect(specifics[4]['groupKey'], 'jivie.local.local-home');
        } else {
          expect(specifics[0]['threadIdentifier'], apnsThread);
          expect(specifics[1]['threadIdentifier'], apnsThread);
          expect(specifics[2]['threadIdentifier'], isNot(apnsThread));
          expect(specifics[3]['threadIdentifier'], isNot(apnsThread));
          expect(specifics[4]['threadIdentifier'], 'jivie.local.local-home');
        }
        expect(captured.map((row) => row['payload']), [
          'routing-0',
          'routing-1',
          'routing-2',
          'routing-3',
          'routing-4',
        ]);
      },
    );
  }
}
