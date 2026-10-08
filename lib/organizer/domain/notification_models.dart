import 'shared_dates.dart';
import 'organizer_models.dart';
import 'collaboration_models.dart' show AccountSession;

enum InboxAudience { personal, scope }

enum NotificationOpenStatus {
  available,
  offline,
  deleted,
  requiresConnection,
  permissionDenied,
  wrongAccount,
}

class NotificationRecordTarget {
  const NotificationRecordTarget({required this.type, required this.recordId});
  final String type, recordId;
  Map<String, Object?> toJson() => {'type': type, 'recordId': recordId};
  factory NotificationRecordTarget.fromJson(Map<String, dynamic> j) =>
      NotificationRecordTarget(
        type: readString(j, 'type'),
        recordId: readString(j, 'recordId'),
      );
}

/// Contains routing references only, never credentials or financial snapshots.
class NotificationTarget {
  NotificationTarget({
    this.serverUrl,
    this.serverId,
    this.accountId,
    this.scopeId,
    required Iterable<NotificationRecordTarget> records,
    Iterable<int> inboxIds = const [],
  }) : records = List.unmodifiable(records),
       inboxIds = List.unmodifiable(inboxIds);
  final String? serverUrl, serverId, accountId, scopeId;
  final List<NotificationRecordTarget> records;
  final List<int> inboxIds;
  bool get isPersonal =>
      serverUrl == null &&
      serverId == null &&
      accountId == null &&
      scopeId == null;
  bool matches(AccountSession session) =>
      serverUrl == session.serverUrl &&
      serverId == session.serverId &&
      accountId == session.accountId;
  Map<String, Object?> toJson() => {
    'serverUrl': serverUrl,
    'serverId': serverId,
    'accountId': accountId,
    'scopeId': scopeId,
    'records': records.map((r) => r.toJson()).toList(),
    'inboxIds': inboxIds,
  };
  factory NotificationTarget.fromJson(Map<String, dynamic> j) =>
      NotificationTarget(
        serverUrl: readNullableString(j, 'serverUrl'),
        serverId: readNullableString(j, 'serverId'),
        accountId: readNullableString(j, 'accountId'),
        scopeId: readNullableString(j, 'scopeId'),
        records: (j['records'] as List).map(
          (r) => NotificationRecordTarget.fromJson(r as Map<String, dynamic>),
        ),
        inboxIds: (j['inboxIds'] as List? ?? const []).cast<int>(),
      );
}

class ReminderPlan {
  const ReminderPlan({
    required this.stableKey,
    required this.scheduledAt,
    required this.target,
    required this.reason,
  });
  final String stableKey, reason;
  final DateTime scheduledAt;
  final NotificationTarget target;
}

class NotificationOpenResult {
  const NotificationOpenResult({required this.status, required this.target});
  final NotificationOpenStatus status;
  final NotificationTarget target;
}

class SharedInboxEntry {
  const SharedInboxEntry({
    required this.id,
    this.revision = 0,
    this.sequence = 0,
    this.targetRevision = 0,
    required this.scopeId,
    required this.kind,
    required this.category,
    required this.audience,
    required this.targetType,
    required this.targetId,
    required this.groupKey,
    required this.createdAt,
    this.readAt,
    this.actorAccountId,
  });
  final int id;
  final int revision, sequence, targetRevision;
  final String scopeId, kind, category, targetType, targetId, groupKey;
  final InboxAudience audience;
  final DateTime createdAt;
  final DateTime? readAt;
  final String? actorAccountId;
  bool get isRead => readAt != null;
  SharedInboxEntry withReadAt(DateTime? value) => SharedInboxEntry(
    id: id,
    revision: revision,
    sequence: sequence,
    targetRevision: targetRevision,
    scopeId: scopeId,
    kind: kind,
    category: category,
    audience: audience,
    targetType: targetType,
    targetId: targetId,
    groupKey: groupKey,
    createdAt: createdAt,
    actorAccountId: actorAccountId,
    readAt: value,
  );
  Map<String, Object?> toJson() => {
    'id': id,
    'revision': revision,
    'sequence': sequence,
    'targetRevision': targetRevision,
    'scopeId': scopeId,
    'kind': kind,
    'category': category,
    'audience': audience.name,
    'targetType': targetType,
    'targetId': targetId,
    'groupKey': groupKey,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'readAt': readAt?.toUtc().toIso8601String(),
    'actorAccountId': actorAccountId,
  };
  factory SharedInboxEntry.fromJson(Map<String, dynamic> j) => SharedInboxEntry(
    id: readInt(j, 'id'),
    revision: j['revision'] is int ? readInt(j, 'revision') : 0,
    sequence: j['sequence'] is int ? readInt(j, 'sequence') : 0,
    targetRevision: j['targetRevision'] is int
        ? readInt(j, 'targetRevision')
        : 0,
    scopeId: readString(j, 'scopeId'),
    kind: readString(j, 'kind'),
    category: readString(j, 'category'),
    audience: InboxAudience.values.byName(readString(j, 'audience')),
    targetType: readString(j, 'targetType'),
    targetId: readString(j, 'targetId'),
    groupKey: readString(j, 'groupKey'),
    createdAt: readSharedDate(j, 'createdAt'),
    readAt: readNullableSharedDate(j, 'readAt'),
    actorAccountId: readNullableString(j, 'actorAccountId'),
  );
}

class SharedInboxGroup {
  SharedInboxGroup(Iterable<SharedInboxEntry> values)
    : entries = List.unmodifiable(values);
  final List<SharedInboxEntry> entries;
  List<int> get ids => List.unmodifiable(entries.map((e) => e.id));
  bool get isRead => entries.every((e) => e.isRead);
  NotificationTarget targetFor(AccountSession session) => NotificationTarget(
    serverUrl: session.serverUrl,
    serverId: session.serverId,
    accountId: session.accountId,
    scopeId: entries.first.scopeId,
    records: {
      for (final e in entries)
        '${e.targetType}:${e.targetId}': NotificationRecordTarget(
          type: e.targetType,
          recordId: e.targetId,
        ),
    }.values,
    inboxIds: ids,
  );
}

/// Captures immutable event IDs; reading a group never reads later additions.
List<SharedInboxGroup> groupSharedInbox(
  Iterable<SharedInboxEntry> values, {
  Duration window = const Duration(minutes: 5),
}) {
  final sorted = values.toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  final groups = <List<SharedInboxEntry>>[];
  for (final e in sorted) {
    final match = groups
        .where(
          (g) =>
              g.first.scopeId == e.scopeId &&
              g.first.audience == e.audience &&
              g.first.kind == e.kind &&
              g.first.groupKey == e.groupKey &&
              g.first.createdAt.difference(e.createdAt) <= window,
        )
        .firstOrNull;
    if (match == null) {
      groups.add([e]);
    } else {
      match.add(e);
    }
  }
  return List.unmodifiable(groups.map(SharedInboxGroup.new));
}

class SharedNotificationSettings {
  const SharedNotificationSettings({
    this.inApp = true,
    this.sound = false,
    this.push = false,
    this.email = false,
  });
  final bool inApp, sound, push, email;
  Map<String, Object?> toJson() => {
    'inApp': inApp,
    'sound': sound,
    'push': push,
    'email': email,
  };
  factory SharedNotificationSettings.fromJson(Map<String, dynamic> j) =>
      SharedNotificationSettings(
        inApp: readBool(j, 'inApp'),
        sound: readBool(j, 'sound'),
        push: readBool(j, 'push'),
        email: readBool(j, 'email'),
      );
}

class SharedNotificationPreferences {
  SharedNotificationPreferences({
    required this.scopeId,
    Map<String, SharedNotificationSettings> categories = const {},
  }) : categories = Map.unmodifiable(categories);
  final String scopeId;
  final Map<String, SharedNotificationSettings> categories;
  SharedNotificationSettings forCategory(String category) =>
      categories[category] ?? const SharedNotificationSettings();
}

class SharedScheduledReminder {
  const SharedScheduledReminder({
    required this.id,
    required this.scopeId,
    required this.targetType,
    required this.targetId,
    required this.remindAt,
    required this.revision,
    required this.state,
    this.syncState = 'synced',
    this.syncError,
  });
  final String id, scopeId, targetType, targetId, state;

  /// Local command status, independent of the server delivery state.
  final String syncState;
  final String? syncError;
  final DateTime remindAt;
  final int revision;
  factory SharedScheduledReminder.fromJson(Map<String, dynamic> j) =>
      SharedScheduledReminder(
        id: readString(j, 'id'),
        scopeId: readString(j, 'scopeId'),
        targetType: readString(j, 'targetType'),
        targetId: readString(j, 'targetId'),
        remindAt: readSharedDate(j, 'remindAt'),
        revision: readInt(j, 'revision'),
        state: readString(j, 'state'),
        syncState: j['syncState'] as String? ?? 'synced',
        syncError: j['syncError'] as String?,
      );
  Map<String, Object?> toJson() => {
    'id': id,
    'scopeId': scopeId,
    'targetType': targetType,
    'targetId': targetId,
    'remindAt': remindAt.toUtc().toIso8601String(),
    'revision': revision,
    'state': state,
    'syncState': syncState,
    if (syncError != null) 'syncError': syncError,
  };
}
