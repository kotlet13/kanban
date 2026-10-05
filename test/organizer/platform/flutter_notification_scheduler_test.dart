import 'package:flutter/services.dart';
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
}
