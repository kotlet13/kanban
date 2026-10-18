import 'dart:convert';
import 'dart:ui' show Locale;
import '../../l10n/app_localizations.dart';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'local_notification_scheduler.dart';

class FlutterNotificationScheduler implements LocalNotificationScheduler {
  FlutterNotificationScheduler({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();
  final FlutterLocalNotificationsPlugin _plugin;
  @override
  bool get supported =>
      !kIsWeb &&
      {
        TargetPlatform.android,
        TargetPlatform.iOS,
        TargetPlatform.macOS,
      }.contains(defaultTargetPlatform);
  @override
  bool get inexact =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  Future<String?> initialize(void Function(String payload) onOpen) async {
    if (!supported) return null;
    tz_data.initializeTimeZones();
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_notification'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
        macOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (response) {
        if (response.payload != null) onOpen(response.payload!);
      },
    );
    final launch = await _plugin.getNotificationAppLaunchDetails();
    return launch?.didNotificationLaunchApp == true
        ? launch?.notificationResponse?.payload
        : null;
  }

  @override
  Future<LocalNotificationPermission> permissionStatus() async {
    if (!supported) return LocalNotificationPermission.unsupported;
    final bool? enabled = switch (defaultTargetPlatform) {
      TargetPlatform.android =>
        await _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.areNotificationsEnabled(),
      TargetPlatform.iOS =>
        (await _plugin
                .resolvePlatformSpecificImplementation<
                  IOSFlutterLocalNotificationsPlugin
                >()
                ?.checkPermissions())
            ?.isAlertEnabled,
      TargetPlatform.macOS =>
        (await _plugin
                .resolvePlatformSpecificImplementation<
                  MacOSFlutterLocalNotificationsPlugin
                >()
                ?.checkPermissions())
            ?.isAlertEnabled,
      _ => null,
    };
    return enabled == null
        ? LocalNotificationPermission.unknown
        : enabled
        ? LocalNotificationPermission.granted
        : LocalNotificationPermission.denied;
  }

  @override
  Future<LocalNotificationPermission> requestPermission() async {
    if (!supported) return LocalNotificationPermission.unsupported;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        await _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.requestNotificationsPermission();
      case TargetPlatform.iOS:
        await _plugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >()
            ?.requestPermissions(alert: true, badge: true, sound: true);
      case TargetPlatform.macOS:
        await _plugin
            .resolvePlatformSpecificImplementation<
              MacOSFlutterLocalNotificationsPlugin
            >()
            ?.requestPermissions(alert: true, badge: true, sound: true);
      default:
        break;
    }
    return permissionStatus();
  }

  @override
  Future<String> refreshTimezone() async {
    final info = await FlutterTimezone.getLocalTimezone();
    // Failure is surfaced; UTC fallback would shift user-selected wall times.
    tz.setLocalLocation(tz.getLocation(info.identifier));
    return info.identifier;
  }

  @override
  Future<Set<int>> pendingIds() async =>
      (await _plugin.pendingNotificationRequests())
          .map((request) => request.id)
          .toSet();
  @override
  Future<void> clearPresentedAndPending() async {
    if (supported) await _plugin.cancelAll();
  }

  @override
  Future<void> cancel(int id) => _plugin.cancel(id: id);
  @override
  Future<void> schedule(
    int id,
    LocalNotificationRequest request,
    String payload,
  ) async {
    final target = request.plan.target;
    final localGroup = 'jivie.local.${target.localWorkspaceId}';
    final accountGroup = 'jivie.${target.serverId}.${target.accountId}';
    // Match the published FamilyHub APNs thread-id exactly. Android retains
    // its existing readable group key, and device-only spaces stay separate.
    final darwinThread = target.isPersonal
        ? localGroup
        : (await Sha256().hash(
            utf8.encode('${target.serverId}:${target.accountId}'),
          )).bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    final generic = lookupAppLocalizations(
      Locale(request.languageCode == 'en' ? 'en' : 'sl'),
    ).notificationPrivateReminder;
    await _plugin.zonedSchedule(
      id: id,
      title: 'Jivie',
      body: generic,
      scheduledDate: tz.TZDateTime.from(
        request.plan.scheduledAt.toUtc(),
        tz.local,
      ),
      payload: payload,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          request.sound ? 'reminders_sound_v1' : 'reminders_quiet_v1',
          'Jivie',
          groupKey: target.isPersonal ? localGroup : accountGroup,
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          playSound: request.sound,
          enableVibration: request.sound,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentSound: request.sound,
          presentBadge: false,
          threadIdentifier: darwinThread,
        ),
        macOS: DarwinNotificationDetails(
          presentAlert: true,
          presentSound: request.sound,
          presentBadge: false,
          threadIdentifier: darwinThread,
        ),
      ),
    );
  }
}
