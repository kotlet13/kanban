import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../domain/local_notification_preferences.dart';
import '../domain/notification_models.dart';
import '../platform/notification_providers.dart';

export '../domain/local_notification_preferences.dart';

final localNotificationPreferencesProvider =
    AsyncNotifierProvider<
      LocalNotificationPreferencesController,
      LocalNotificationPreferences
    >(LocalNotificationPreferencesController.new);

class LocalNotificationPreferencesController
    extends AsyncNotifier<LocalNotificationPreferences> {
  static const storageKey = 'organizer_local_notification_preferences_v2';
  Future<void> _tail = Future.value();
  @override
  Future<LocalNotificationPreferences> build() async {
    final legacy = await ref.watch(localReminderSettingsProvider.future);
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(storageKey);
    if (raw != null) {
      return LocalNotificationPreferences.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    }
    // Reading the page never overwrites existing opt-ins or sound choices.
    return LocalNotificationPreferences(
      defaults: SharedNotificationSettings(
        push: legacy.enabled,
        sound: legacy.sound,
      ),
    );
  }

  Future<void> change(
    String channel,
    bool enabled, {
    String? workspace,
    String? project,
    bool Function()? stillCurrent,
    Set<String>? resetWorkspaces,
  }) {
    final result = _tail.then((_) async {
      final current = await future;
      if (stillCurrent?.call() == false) {
        throw StateError('Notification account changed');
      }
      final next = current.change(
        channel,
        enabled,
        workspace: workspace,
        project: project,
        resetWorkspaces: resetWorkspaces,
      );
      final prefs = await SharedPreferences.getInstance();
      if (stillCurrent?.call() == false) {
        throw StateError('Notification account changed');
      }
      if (!await prefs.setString(storageKey, jsonEncode(next.toJson()))) {
        throw StateError('Notification preferences could not be saved');
      }
      state = AsyncData(next);
    });
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }
}
