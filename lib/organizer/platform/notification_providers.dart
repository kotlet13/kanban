import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/notification_models.dart';
import 'flutter_notification_scheduler.dart';
import 'local_notification_adapter.dart';
import 'local_notification_scheduler.dart';

final localNotificationSchedulerProvider = Provider<LocalNotificationScheduler>(
  (ref) => FlutterNotificationScheduler(),
);

final localNotificationAdapterProvider =
    FutureProvider<LocalNotificationAdapter>((ref) async {
      final adapter = LocalNotificationAdapter(
        scheduler: ref.read(localNotificationSchedulerProvider),
        preferences: await SharedPreferences.getInstance(),
      );
      var alive = true;
      ref.onDispose(() {
        alive = false;
        adapter.dispose();
      });
      final launch = await adapter.initialize((target) {
        if (alive) {
          ref.read(notificationLaunchTargetProvider.notifier).state = target;
        }
      });
      if (alive && launch != null) {
        ref.read(notificationLaunchTargetProvider.notifier).state = launch;
      }
      return adapter;
    });
final notificationLaunchTargetProvider = StateProvider<NotificationTarget?>(
  (ref) => null,
);
final localNotificationDeviceStatusProvider =
    StateProvider<AsyncValue<LocalNotificationStatus>>(
      (ref) => const AsyncData(
        LocalNotificationStatus(
          permission: LocalNotificationPermission.unknown,
        ),
      ),
    );

class LocalReminderSettings {
  const LocalReminderSettings({this.enabled = false, this.sound = false});
  final bool enabled, sound;
}

final localReminderSettingsProvider =
    AsyncNotifierProvider<
      LocalReminderSettingsController,
      LocalReminderSettings
    >(LocalReminderSettingsController.new);

class LocalReminderSettingsController
    extends AsyncNotifier<LocalReminderSettings> {
  static const _enabled = 'organizer_local_reminders_enabled_v1';
  static const _sound = 'organizer_local_reminders_sound_v1';
  @override
  Future<LocalReminderSettings> build() async {
    final prefs = await SharedPreferences.getInstance();
    return LocalReminderSettings(
      enabled: prefs.getBool(_enabled) ?? false,
      sound: prefs.getBool(_sound) ?? false,
    );
  }

  Future<void> save({required bool enabled, required bool sound}) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setBool(_enabled, enabled) ||
        !await prefs.setBool(_sound, sound)) {
      throw StateError('Reminder preferences could not be saved');
    }
    state = AsyncData(LocalReminderSettings(enabled: enabled, sound: sound));
  }
}
