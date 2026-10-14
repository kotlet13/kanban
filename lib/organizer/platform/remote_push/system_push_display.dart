import 'dart:convert';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../domain/remote_push_models.dart';

class SystemPushMessage {
  const SystemPushMessage(
    this.reference,
    this.title,
    this.body,
    this.language,
    this.sound,
  );
  final RemotePushReference reference;
  final String title, body, language;
  final bool sound;

  static Map<String, Object?> referenceData(Map<String, Object?> data) => {
    for (final key in ['type', 'serverId', 'accountId', 'notificationId'])
      key: data[key],
  };

  static SystemPushMessage? tryParse(Map<String, Object?> data) {
    final reference = RemotePushReference.tryParse(referenceData(data));
    if (reference == null ||
        data['displayVersion'] != '2' ||
        data['title'] is! String ||
        (data['title'] as String).isEmpty ||
        (data['title'] as String).length > 512 ||
        data['body'] is! String ||
        (data['body'] as String).length > 512 ||
        !const ['sl', 'en'].contains(data['language']) ||
        !const ['0', '1'].contains(data['sound'])) {
      return null;
    }
    return SystemPushMessage(
      reference,
      data['title'] as String,
      data['body'] as String,
      data['language'] as String,
      data['sound'] == '1',
    );
  }

  String get groupKey => 'jivie.${reference.serverId}.${reference.accountId}';
  int get id =>
      stableSystemNotificationId('$groupKey:${reference.notificationId}');
  int get summaryId => stableSystemNotificationId('$groupKey:summary');
  String payload({bool summary = false}) => jsonEncode({
    'type': 'familyhub.system.v2',
    'reference': reference.toData(),
    'summary': summary,
  });
}

int stableSystemNotificationId(String key) {
  var hash = 2166136261;
  for (final byte in utf8.encode(key)) {
    hash = ((hash ^ byte) * 16777619) & 0xffffffff;
  }
  // Keep a separate range from the small IDs assigned to local reminders.
  return 0x40000000 | (hash & 0x3fffffff);
}

class SystemPushGroup {
  SystemPushGroup(SystemPushMessage message, List<ActiveNotification> active)
    : lines = [
        for (final item in active)
          if (item.groupKey == message.groupKey &&
              item.id != message.summaryId &&
              item.id != message.id)
            item.title ?? 'Jivie',
        message.title,
      ];
  final List<String> lines;
  int get count => lines.length;
  String label(String language) => language == 'sl'
      ? 'Nova obvestila ($count)'
      : 'New notifications ($count)';
}

/// Android's background isolate renders negotiated data messages without opening
/// user databases, authenticating, syncing or navigating.
Future<void> displaySystemPush(
  Map<String, Object?> data, {
  FlutterLocalNotificationsPlugin? plugin,
}) async {
  final message = SystemPushMessage.tryParse(data);
  if (message == null) return;
  final notifications = plugin ?? FlutterLocalNotificationsPlugin();
  await notifications.initialize(
    settings: const InitializationSettings(
      android: AndroidInitializationSettings('ic_notification'),
    ),
  );
  final group = SystemPushGroup(
    message,
    await notifications.getActiveNotifications(),
  );
  final channel = message.sound
      ? 'familyhub_push_sound_v1'
      : 'familyhub_push_silent_v1';
  await notifications.show(
    id: message.id,
    title: message.title,
    body: message.body,
    payload: message.payload(),
    notificationDetails: NotificationDetails(
      android: AndroidNotificationDetails(
        channel,
        'Jivie',
        groupKey: message.groupKey,
        groupAlertBehavior: GroupAlertBehavior.children,
        playSound: message.sound,
        enableVibration: message.sound,
        styleInformation: BigTextStyleInformation(message.body),
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
      ),
    ),
  );
  if (group.count == 1) {
    await notifications.cancel(id: message.summaryId);
  } else {
    await notifications.show(
      id: message.summaryId,
      title: 'Jivie',
      body: group.label(message.language),
      payload: message.payload(summary: true),
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          channel,
          'Jivie',
          groupKey: message.groupKey,
          setAsGroupSummary: true,
          groupAlertBehavior: GroupAlertBehavior.children,
          playSound: false,
          enableVibration: false,
          onlyAlertOnce: true,
          number: group.count,
          styleInformation: InboxStyleInformation(
            group.lines.reversed.take(7).toList(),
            contentTitle: group.label(message.language),
          ),
        ),
      ),
    );
  }
}
