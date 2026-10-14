import 'notification_models.dart';
import 'organizer_models.dart';

/// Device-owned preferences. A workspace key includes the private account
/// partition when applicable; project IDs are never matched across workspaces.
class LocalNotificationPreferences {
  LocalNotificationPreferences({
    required this.defaults,
    Map<String, Map<String, bool>> overrides = const {},
  }) : overrides = Map.unmodifiable({
         for (final e in overrides.entries)
           e.key: Map<String, bool>.unmodifiable(e.value),
       });
  final SharedNotificationSettings defaults;
  final Map<String, Map<String, bool>> overrides;
  static String key(String workspace, [String? project]) =>
      '${workspace.length}:$workspace:${project ?? ''}';
  SharedNotificationSettings resolve(String workspace, [String? project]) {
    var value = defaults;
    for (final id in [
      key(workspace),
      if (project != null) key(workspace, project),
    ]) {
      for (final e in (overrides[id] ?? const <String, bool>{}).entries) {
        value = value.withChannel(e.key, e.value);
      }
    }
    return value;
  }

  LocalNotificationPreferences change(
    String channel,
    bool enabled, {
    String? workspace,
    String? project,
    Set<String>? resetWorkspaces,
  }) {
    if (!const ['inApp', 'sound', 'push'].contains(channel)) {
      throw ArgumentError.value(channel);
    }
    final next = {
      for (final e in overrides.entries) e.key: {...e.value},
    };
    if (workspace == null) {
      // A bulk change resets just this property, including project exceptions.
      for (final entry in next.entries) {
        if (resetWorkspaces == null ||
            resetWorkspaces.any(
              (workspace) => entry.key.startsWith(key(workspace)),
            )) {
          entry.value.remove(channel);
        }
      }
      next.removeWhere((_, value) => value.isEmpty);
      return LocalNotificationPreferences(
        defaults: defaults.withChannel(channel, enabled),
        overrides: next,
      );
    }
    final id = key(workspace, project);
    next[id] = {...?next[id], channel: enabled};
    return LocalNotificationPreferences(defaults: defaults, overrides: next);
  }

  Map<String, Object?> toJson() => {
    'defaults': defaults.toJson(),
    'overrides': overrides,
  };
  factory LocalNotificationPreferences.fromJson(Map<String, dynamic> value) {
    final rows = Map<String, dynamic>.from(value['overrides'] as Map);
    return LocalNotificationPreferences(
      defaults: SharedNotificationSettings.fromJson(
        Map<String, dynamic>.from(value['defaults'] as Map),
      ),
      overrides: {
        for (final e in rows.entries)
          e.key: Map<String, bool>.from(e.value as Map),
      },
    );
  }
}

String? notificationProject(
  NotificationTarget target,
  OrganizerSnapshot? snapshot,
) {
  if (snapshot == null || target.records.length != 1) return null;
  final record = target.records.single;
  return switch (record.type) {
    'task' =>
      snapshot.tasks
          .where((t) => t.id == record.recordId)
          .firstOrNull
          ?.projectId,
    'event' =>
      snapshot.events
          .where((e) => e.id == record.recordId)
          .firstOrNull
          ?.projectId,
    'financeEntry' =>
      snapshot.financeEntries
          .where((e) => e.id == record.recordId)
          .firstOrNull
          ?.projectId,
    _ => null,
  };
}

String sharedDeviceNotificationWorkspace(String partition, String scope) =>
    'shared:${LocalNotificationPreferences.key(partition, scope)}';
