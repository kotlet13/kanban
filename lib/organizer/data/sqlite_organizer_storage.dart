import 'dart:async';
import 'dart:convert';
import '../domain/organizer_models.dart';
import '../domain/shared_payload_validation.dart';
import '../domain/shared_finance_validation.dart';
import '../domain/collaboration_models.dart';
import 'collaboration_database.dart';
import 'collaboration_repository.dart' show newSharedId;
import 'organizer_storage.dart';
import 'organizer_repository.dart' show OrganizerConflictException;

/// Per-record canonical storage. Opening and anonymous use need no credentials.
/// Hive is read once and retained intact; the marker and every row commit together.
class SqliteOrganizerStorage
    implements OrganizerStorage, ObservableOrganizerStorage {
  SqliteOrganizerStorage(this.database, {this.legacyFactory});
  final CollaborationDatabase database;
  final Future<OrganizerStorage> Function()? legacyFactory;
  static const localWorkspace = 'local';
  @override
  Stream<void> get changes => database.personalChanges.stream;
  static final _migrations = Expando<Future<void>>();
  Future<void> initialize() {
    final pending = _migrations[database];
    if (pending != null) return pending;
    final opening = _initialize().whenComplete(
      () => _migrations[database] = null,
    );
    _migrations[database] = opening;
    return opening;
  }

  Future<void> _initialize() async {
    if ((await database.rows('SELECT id FROM personal_workspaces WHERE id=?', [
      localWorkspace,
    ])).isNotEmpty) {
      return;
    }
    OrganizerSnapshot source = OrganizerSnapshot();
    if (legacyFactory != null) {
      final legacy = await legacyFactory!();
      try {
        source = await legacy.read();
      } finally {
        await legacy.close();
      }
    }
    source.validate();
    await database.transaction(() async {
      // Another connection may have imported while the Hive read was in progress.
      if ((await database.rows(
        'SELECT id FROM personal_workspaces WHERE id=?',
        [localWorkspace],
      )).isNotEmpty) {
        return;
      }
      await database.execute(
        'INSERT INTO personal_workspaces(id,revision,migration_snapshot) VALUES(?,?,?)',
        [localWorkspace, source.revision, OrganizerBackupCodec.encode(source)],
      );
      await database.execute(
        "INSERT OR IGNORE INTO local_meta(name,value) VALUES('organizer_generation',?)",
        [source.revision.toString()],
      );
      for (final row in snapshotRows(source)) {
        await database.execute(
          'INSERT INTO personal_records(workspace,id,type,payload) VALUES(?,?,?,?)',
          [localWorkspace, row.id, row.type, jsonEncode(row.json)],
        );
      }
    });
  }

  Future<Map<String, dynamic>?> activeBinding() async {
    final profile = database.personalProfile;
    if (profile == null) return null;
    final rows = await database.rows(
      'SELECT * FROM personal_workspaces WHERE id=? AND partition=? AND enabled=1',
      ['private:${profile.partition}', profile.partition],
    );
    return rows.firstOrNull;
  }

  Future<OrganizerSnapshot> localSnapshot() async {
    final revision = await database.rows(
      'SELECT revision FROM personal_workspaces WHERE id=?',
      [localWorkspace],
    );
    return snapshotFromRows(
      await database.rows('SELECT * FROM personal_records WHERE workspace=?', [
        localWorkspace,
      ]),
      revision: revision.firstOrNull?['revision'] as int? ?? 0,
    );
  }

  @override
  Future<OrganizerSnapshot> read() async {
    final identity = database.personalIdentityGeneration;
    final result = await database.transaction(() async {
      final generation = await database.rows(
        "SELECT value FROM local_meta WHERE name='organizer_generation'",
      );
      final revision = generation.isEmpty
          ? 0
          : int.parse(generation.single['value'] as String);
      final local = await localSnapshot(), binding = await activeBinding();
      if (binding == null) {
        return local.copyWith(revision: revision, workspaceKey: 'local');
      }
      OrganizerSnapshot private;
      try {
        private = await privateSnapshot(binding);
      } on PrivateAccessUnavailable {
        return local.copyWith(revision: revision, workspaceKey: 'local');
      }
      return mergePersonalSnapshots(
        local,
        private,
        revision: revision,
      ).copyWith(workspaceKey: binding['id'] as String);
    });
    if (identity != database.personalIdentityGeneration) {
      throw const OrganizerConflictException(
        'Personal identity changed; reload',
      );
    }
    return result;
  }

  Future<OrganizerSnapshot> privateSnapshot(
    Map<String, dynamic> binding,
  ) async {
    final p = binding['partition'] as String,
        scope = binding['scope_id'] as String,
        w = binding['id'] as String;
    final maps = await database.rows(
      'SELECT * FROM personal_record_map WHERE workspace=?',
      [w],
    );
    final reverse = {
      for (final m in maps) m['remote_id'] as String: m['id'] as String,
    };
    final rows = <Map<String, dynamic>>[];
    var revision = binding['revision'] as int;
    final acl = await database.rows(
      'SELECT data,blocked,finance_policy,finance_blocked,finance_complete FROM scopes WHERE partition=? AND id=?',
      [p, scope],
    );
    if (acl.isEmpty ||
        acl.single['blocked'] == 1 ||
        (jsonDecode(acl.single['data'] as String) as Map)['revoked'] == true) {
      throw const PrivateAccessUnavailable();
    }
    final policy = acl.single['finance_policy'] == null
        ? const SharedFinancePolicy()
        : SharedFinancePolicy.fromJson(
            jsonDecode(acl.single['finance_policy'] as String)
                as Map<String, dynamic>,
          );
    for (final table in [
      'records',
      if (policy.canRead &&
          acl.single['finance_blocked'] != 1 &&
          acl.single['finance_complete'] == 1)
        'finance_records',
    ]) {
      final records = await database.rows(
        table == 'finance_records'
            ? "SELECT r.*,EXISTS(SELECT 1 FROM finance_outbox o WHERE o.partition=r.partition AND o.scope_id=r.scope_id AND o.record_id=r.id AND o.state!='pending') AS rejected FROM finance_records r WHERE partition=? AND scope_id=?"
            : 'SELECT * FROM records WHERE partition=? AND scope_id=?',
        [p, scope],
      );
      for (final record in records) {
        revision += record['local_revision'] as int;
        final remote = record['remote'] == null
            ? null
            : jsonDecode(record['remote'] as String) as Map<String, dynamic>;
        final rejected = record['rejected'] == 1;
        if (rejected && (remote == null || remote['deleted'] == true)) continue;
        if (!rejected &&
            (record['deleted'] == 1 || record['payload'] == null)) {
          continue;
        }
        final json = rejected
            ? Map<String, dynamic>.from(remote!['payload'] as Map)
            : jsonDecode(record['payload'] as String) as Map<String, dynamic>;
        json['id'] = reverse[record['id']] ?? record['id'];
        json['revision'] = record['local_revision'];
        for (final field in ['projectId', 'listId']) {
          if (json[field] != null) {
            json[field] = reverse[json[field]] ?? json[field];
          }
        }
        final type = record['type'] == 'personalFinanceEntry'
            ? 'financeEntry'
            : record['type'] as String;
        if (type == 'event') {
          json['startsAt'] = json.remove('startAt');
          json['endsAt'] = json.remove('endAt');
          json.remove('assigneeAccountIds');
        }
        rows.add({'type': type, 'payload': jsonEncode(json)});
      }
    }
    rows.addAll(
      await database.rows(
        "SELECT * FROM personal_records WHERE workspace=? AND type='reminder'",
        [w],
      ),
    );
    // Local reminder history cannot outlive its task or unchanged due date.
    final tasks = {
      for (final row in rows.where((r) => r['type'] == 'task'))
        (jsonDecode(row['payload'] as String) as Map)['id']: LocalTask.fromJson(
          jsonDecode(row['payload'] as String) as Map<String, dynamic>,
        ),
    };
    rows.removeWhere((r) {
      if (r['type'] != 'reminder') return false;
      final reminder = LocalReminder.fromJson(
            jsonDecode(r['payload'] as String) as Map<String, dynamic>,
          ),
          task = tasks[reminder.taskId];
      return task == null || task.isCompleted || task.dueAt != reminder.dueAt;
    });
    return snapshotFromRows(rows, revision: revision);
  }

  @override
  Future<void> write(OrganizerSnapshot snapshot) async {
    snapshot.validate();
    await database.transaction(() async {
      final binding = await activeBinding(),
          local = await localSnapshot(),
          previous = await read();
      if (snapshot.revision != previous.revision + 1 ||
          snapshot.workspaceKey != previous.workspaceKey) {
        throw const OrganizerConflictException(
          'Personal workspace changed; reload before writing',
        );
      }
      final identity = database.personalIdentityGeneration;
      final old = {for (final r in snapshotRows(previous)) r.id: r},
          next = {for (final r in snapshotRows(snapshot)) r.id: r};
      final localIds = local.recordIds;
      final changedIds = {...old.keys, ...next.keys}.toList()
        ..sort((a, b) {
          int rank(String id) =>
              next[id] == null &&
                  const ['project', 'shoppingList'].contains(old[id]?.type)
              ? 2
              : const [
                  'task',
                  'event',
                  'shoppingItem',
                  'financeEntry',
                ].contains(next[id]?.type ?? old[id]?.type)
              ? 1
              : 0;
          return rank(a).compareTo(rank(b));
        });
      for (final id in changedIds) {
        final a = old[id], b = next[id];
        if (a != null &&
            b != null &&
            jsonEncode(a.json) == jsonEncode(b.json)) {
          continue;
        }
        final refs = b?.json;
        if (refs != null &&
            [refs['projectId'], refs['listId']].any(localIds.contains)) {
          localIds.add(id);
        }
        if (binding == null ||
            localIds.contains(id) ||
            (b?.type ?? a?.type) == 'reminder') {
          final workspace = (binding != null && !localIds.contains(id))
              ? binding['id'] as String
              : localWorkspace;
          if (b == null) {
            await database.execute(
              'DELETE FROM personal_records WHERE workspace=? AND id=?',
              [workspace, id],
            );
          } else {
            await database.execute(
              'INSERT INTO personal_records(workspace,id,type,payload) VALUES(?,?,?,?) ON CONFLICT(workspace,id) DO UPDATE SET payload=excluded.payload',
              [workspace, id, b.type, jsonEncode(b.json)],
            );
          }
        } else {
          await queuePrivateRecord(
            database,
            binding,
            id,
            b?.type ?? a!.type,
            b?.json,
          );
        }
      }
      if (identity != database.personalIdentityGeneration) {
        throw const OrganizerConflictException(
          'Personal identity changed; reload',
        );
      }
      await database.touchPersonal();
    });
    database.personalChanged();
  }

  @override
  Future<void> close() async {}
}

class PrivateAccessUnavailable implements Exception {
  const PrivateAccessUnavailable();
}

typedef PersonalRow = ({String id, String type, Map<String, Object?> json});
List<PersonalRow> snapshotRows(OrganizerSnapshot s) => [
  for (final r in s.projects) (id: r.id, type: 'project', json: r.toJson()),
  for (final r in s.tasks) (id: r.id, type: 'task', json: r.toJson()),
  for (final r in s.shoppingLists)
    (id: r.id, type: 'shoppingList', json: r.toJson()),
  for (final r in s.shoppingItems)
    (id: r.id, type: 'shoppingItem', json: r.toJson()),
  for (final r in s.events) (id: r.id, type: 'event', json: r.toJson()),
  for (final r in s.financeEntries)
    (id: r.id, type: 'financeEntry', json: r.toJson()),
  for (final r in s.reminders) (id: r.id, type: 'reminder', json: r.toJson()),
];
OrganizerSnapshot snapshotFromRows(
  List<Map<String, dynamic>> rows, {
  required int revision,
}) {
  final groups = <String, List<Object?>>{};
  const keys = {
    'project': 'projects',
    'task': 'tasks',
    'shoppingList': 'shoppingLists',
    'shoppingItem': 'shoppingItems',
    'event': 'events',
    'financeEntry': 'financeEntries',
    'reminder': 'reminders',
  };
  for (final r in rows) {
    final key = keys[r['type']];
    if (key == null) throw const FormatException('Unknown personal record');
    (groups[key] ??= []).add(jsonDecode(r['payload'] as String));
  }
  return OrganizerSnapshot.fromJson({
    'revision': revision,
    for (final key in keys.values) key: groups[key] ?? [],
  });
}

OrganizerSnapshot mergePersonalSnapshots(
  OrganizerSnapshot a,
  OrganizerSnapshot b, {
  required int revision,
}) {
  if (a.recordIds.intersection(b.recordIds).isNotEmpty) {
    throw const OrganizerConflictException('Personal record ID collision');
  }
  return OrganizerSnapshot(
    revision: revision,
    projects: [...a.projects, ...b.projects],
    tasks: [...a.tasks, ...b.tasks],
    shoppingLists: [...a.shoppingLists, ...b.shoppingLists],
    shoppingItems: [...a.shoppingItems, ...b.shoppingItems],
    events: [...a.events, ...b.events],
    financeEntries: [...a.financeEntries, ...b.financeEntries],
    reminders: [...a.reminders, ...b.reminders],
  )..validate();
}

Future<void> queuePrivateRecord(
  CollaborationDatabase db,
  Map<String, dynamic> binding,
  String localId,
  String localType,
  Map<String, Object?>? source,
) async {
  final p = binding['partition'] as String,
      scope = binding['scope_id'] as String,
      w = binding['id'] as String;
  final type = localType == 'financeEntry' ? 'personalFinanceEntry' : localType;
  final financial = type == 'personalFinanceEntry',
      table = financial ? 'finance_records' : 'records',
      outbox = financial ? 'finance_outbox' : 'outbox';
  var maps = await db.rows(
    'SELECT remote_id FROM personal_record_map WHERE workspace=? AND id=?',
    [w, localId],
  );
  if (maps.isEmpty) {
    await db.execute(
      'INSERT INTO personal_record_map(workspace,id,remote_id,type) VALUES(?,?,?,?)',
      [w, localId, isSharedUuid(localId) ? localId : newSharedId(), type],
    );
    maps = await db.rows(
      'SELECT remote_id FROM personal_record_map WHERE workspace=? AND id=?',
      [w, localId],
    );
  }
  final id = maps.single['remote_id'] as String;
  final acl = await db.rows(
    'SELECT data,blocked,finance_blocked,finance_policy FROM scopes WHERE partition=? AND id=?',
    [p, scope],
  );
  if (acl.isEmpty ||
      acl.single['blocked'] == 1 ||
      (jsonDecode(acl.single['data'] as String) as Map)['revoked'] == true) {
    throw const CollaborationException('permission_revoked');
  }
  if (financial &&
      (acl.single['finance_blocked'] == 1 ||
          acl.single['finance_policy'] == null ||
          !SharedFinancePolicy.fromJson(
            jsonDecode(acl.single['finance_policy'] as String)
                as Map<String, dynamic>,
          ).canWrite)) {
    throw const CollaborationException('finance_forbidden');
  }
  final conflicts = await db.rows(
    "SELECT op_id FROM $outbox WHERE partition=? AND scope_id=? AND record_id=? AND state<>'pending'",
    [p, scope, id],
  );
  if (conflicts.isNotEmpty) {
    throw const CollaborationException('changes_blocked');
  }
  Map<String, Object?>? payload;
  if (source != null) {
    payload = Map.of(source)
      ..remove('id')
      ..remove('revision')
      ..remove('createdByAccountId')
      ..remove('updatedByAccountId');
    for (final field in ['projectId', 'listId']) {
      if (payload[field] != null) {
        final refs = await db.rows(
          'SELECT remote_id FROM personal_record_map WHERE workspace=? AND id=?',
          [w, payload[field]],
        );
        if (refs.isEmpty) {
          throw const FormatException('Missing private parent mapping');
        }
        payload[field] = refs.single['remote_id'];
      }
    }
    if (type == 'event') {
      payload['startAt'] = payload.remove('startsAt');
      payload['endAt'] = payload.remove('endsAt');
      payload['assigneeAccountIds'] = [];
    }

    if (financial) {
      validateSharedFinancePayload(
        SharedFinanceRecordType.personalFinanceEntry,
        Map<String, dynamic>.from(payload),
      );
    } else {
      validateSharedPayload(
        SharedRecordType.values.byName(type),
        Map<String, dynamic>.from(payload),
        contractVersion: 2,
        personal: true,
      );
    }
  }
  final old = await db.rows(
    'SELECT * FROM $table WHERE partition=? AND scope_id=? AND id=?',
    [p, scope, id],
  );
  if (old.isNotEmpty && old.first['type'] != type) {
    throw const CollaborationException('validation_error');
  }
  if (old.isNotEmpty &&
      source != null &&
      old.first['payload'] != null &&
      DateTime.parse(
            (jsonDecode(old.first['payload'] as String) as Map)['createdAt']
                as String,
          ) !=
          DateTime.parse(source['createdAt'] as String)) {
    throw const CollaborationException('created_at_immutable');
  }
  if (old.isNotEmpty && old.first['deleted'] == 1 && source != null) {
    throw const OrganizerConflictException(
      'Private tombstone requires a new ID',
    );
  }
  final pending = await db.rows(
    "SELECT * FROM $outbox WHERE partition=? AND scope_id=? AND record_id=? ORDER BY sequence DESC LIMIT 1",
    [p, scope, id],
  );
  final expected = pending.isNotEmpty
      ? ((jsonDecode(pending.first['request'] as String)
                    as Map)['expectedRevision']
                as int) +
            1
      : old.firstOrNull?['server_revision'] as int? ?? 0;
  final request = {
    'opId': newSharedId(),
    'recordId': id,
    'type': type,
    'expectedRevision': expected,
    'deleted': source == null,
    'payload': payload,
  };
  await db.execute(
    'INSERT INTO $table(partition,scope_id,id,type,local_revision,server_revision,payload,deleted,remote) VALUES(?,?,?,?,?,?,?,?,?) ON CONFLICT(partition,scope_id,id) DO UPDATE SET local_revision=excluded.local_revision,payload=excluded.payload,deleted=excluded.deleted',
    [
      p,
      scope,
      id,
      type,
      (old.firstOrNull?['local_revision'] as int? ?? 0) + 1,
      old.firstOrNull?['server_revision'] ?? 0,
      payload == null ? null : jsonEncode(payload),
      source == null ? 1 : 0,
      old.firstOrNull?['remote'],
    ],
  );
  await db.execute(
    'INSERT INTO $outbox(op_id,partition,scope_id,record_id,request${financial ? '' : ',wire_version'}) VALUES(?,?,?,?,?${financial ? '' : ',?'})',
    [request['opId'], p, scope, id, jsonEncode(request), if (!financial) 2],
  );
}
