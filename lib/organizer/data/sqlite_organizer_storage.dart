import 'dart:async';
import 'dart:convert';
import '../domain/garden_models.dart';
import 'garden_storage.dart';
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
    implements
        OrganizerStorage,
        ObservableOrganizerStorage,
        OrganizerOwnershipStorage,
        PersonalJsonBackupStorage {
  SqliteOrganizerStorage(this.database, {this.legacyFactory});
  final CollaborationDatabase database;
  final Future<OrganizerStorage> Function()? legacyFactory;
  static const localWorkspace = 'local';
  @override
  Future<Set<String>> deviceLocalRecordIds() async =>
      (await localSnapshot()).recordIds;
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
        if (remote != null) {
          json['createdByAccountId'] = remote['createdByAccountId'];
          json['updatedByAccountId'] = remote['updatedByAccountId'];
        }
        for (final field in [
          'projectId',
          'listId',
          'taskId',
          'ledgerAccountId',
          'recurrenceRuleId',
          'payerPersonId',
          'recipientPersonId',
          'createdByPersonId',
          'assigneePersonId',
        ]) {
          if (json[field] != null) {
            json[field] = reverse[json[field]] ?? json[field];
          }
        }
        if (json['subjectPersonIds'] is List) {
          json['subjectPersonIds'] = (json['subjectPersonIds'] as List)
              .map((id) => reverse[id] ?? id)
              .toList();
        }
        final type = record['type'] == 'personalFinanceEntry'
            ? 'financeEntry'
            : record['type'] == 'personalFinanceAccount'
            ? 'financeAccount'
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
      // A record inherits the location of its existing local parents. Compute
      // the closure before allocating private identities or ordering writes.
      if (binding != null) {
        var count = -1;
        while (count != localIds.length) {
          count = localIds.length;
          for (final row in next.values) {
            final json = row.json;
            final refs = [
              json['projectId'],
              json['listId'],
              json['taskId'],
              json['ledgerAccountId'],
              json['recurrenceRuleId'],
              json['assigneePersonId'],
              json['payerPersonId'],
              json['recipientPersonId'],
              ...(json['subjectPersonIds'] as List? ?? []),
            ];
            if (!localIds.contains(row.id) && refs.any(localIds.contains)) {
              if (old.containsKey(row.id)) {
                throw const FormatException(
                  'Private records cannot reference device-local parents',
                );
              }
              localIds.add(row.id);
            }
          }
        }
      }
      for (final row in next.values.where((r) => localIds.contains(r.id))) {
        final json = row.json;
        final refs = [
          json['projectId'],
          json['listId'],
          json['taskId'],
          json['ledgerAccountId'],
          json['recurrenceRuleId'],
          json['assigneePersonId'],
          json['payerPersonId'],
          json['recipientPersonId'],
          ...(json['subjectPersonIds'] as List? ?? []),
        ];
        if (refs.any(
          (ref) =>
              ref != null && next.containsKey(ref) && !localIds.contains(ref),
        )) {
          throw const FormatException(
            'Device-local records cannot reference private parents',
          );
        }
      }
      final changedIds = {...old.keys, ...next.keys}.toList()
        ..sort((a, b) {
          int rank(String id) {
            final before = old[id], after = next[id];
            final deletingParent =
                after == null &&
                const ['project', 'shoppingList'].contains(before?.type);
            final removingPhase =
                before?.type == 'project' &&
                after?.type == 'project' &&
                (before!.json['phases'] as List? ?? []).any(
                  (phase) => !(after!.json['phases'] as List? ?? []).any(
                    (nextPhase) =>
                        (phase as Map)['id'] == (nextPhase as Map)['id'],
                  ),
                );
            if (deletingParent || removingPhase) return 3;
            if ((after?.type ?? before?.type) == 'financeRecurrenceRule') {
              return 1;
            }
            return const [
                  'task',
                  'event',
                  'shoppingItem',
                  'financeEntry',
                ].contains(after?.type ?? before?.type)
                ? 2
                : 0;
          }

          final order = rank(a).compareTo(rank(b));
          return order == 0 ? a.compareTo(b) : order;
        });
      if (binding != null) {
        for (final row in next.values.where(
          (r) => !localIds.contains(r.id) && r.type != 'reminder',
        )) {
          await database.execute(
            'INSERT INTO personal_record_map(workspace,id,remote_id,type) VALUES(?,?,?,?) ON CONFLICT(workspace,id) DO NOTHING',
            [
              binding['id'],
              row.id,
              isSharedUuid(row.id) ? row.id : newSharedId(),
              row.type == 'financeEntry'
                  ? 'personalFinanceEntry'
                  : row.type == 'financeAccount'
                  ? 'personalFinanceAccount'
                  : row.type,
            ],
          );
        }
      }
      final actuallyChanged = <String>{};
      for (final id in changedIds) {
        final a = old[id], b = next[id];
        if (a != null &&
            b != null &&
            jsonEncode(a.json) == jsonEncode(b.json)) {
          continue;
        }
        actuallyChanged.add(id);

        if (binding == null ||
            localIds.contains(id) ||
            (b?.type ?? a?.type) == 'reminder') {
          final workspace = (binding != null && !localIds.contains(id))
              ? binding['id'] as String
              : localWorkspace;
          if (b == null) {
            if (a != null && a.type != 'reminder') {
              await savePersonalRevisionFloor(
                database,
                workspace,
                id,
                (a.json['revision'] as int? ?? 0) + 1,
              );
            }
            await database.execute(
              'DELETE FROM personal_records WHERE workspace=? AND id=?',
              [workspace, id],
            );
          } else {
            await commitPersonalRow(database, workspace, b);
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
      if (binding != null) {
        for (final taskId in actuallyChanged.where(
          (id) =>
              (next[id]?.type ?? old[id]?.type) == 'task' &&
              !localIds.contains(id),
        )) {
          final linked =
              next.values
                  .where(
                    (r) =>
                        r.type == 'financeEntry' && r.json['taskId'] == taskId,
                  )
                  .firstOrNull ??
              old.values
                  .where(
                    (r) =>
                        r.type == 'financeEntry' && r.json['taskId'] == taskId,
                  )
                  .firstOrNull;
          if (linked == null || !actuallyChanged.contains(linked.id)) continue;
          await pairPrivateTaskCostOperations(
            database,
            binding,
            taskId,
            linked.id,
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
  Future<String> exportPersonalJsonBackup() => database.transaction(
    () async => OrganizerBackupCodec.encode(
      await read(),
      gardens: await GardenStorage(database).read(),
    ),
  );

  @override
  Future<void> importPersonalJsonBackup(String json) async {
    final document = OrganizerBackupCodec.decodeDocument(json);
    await database.transaction(() async {
      final current = await read();
      final merged = mergePersonalSnapshots(
        current,
        document.personal,
        revision: current.revision + 1,
      ).copyWith(workspaceKey: current.workspaceKey);
      final gardenStorage = GardenStorage(database),
          gardens = await gardenStorage.read();
      final candidateGardens = document.gardens == null
          ? null
          : mergeGardenSnapshots(gardens, document.gardens!);
      // Personal work follows the existing explicit JSON-import path. Gardens
      // always remain device-local, including with a private binding enabled.
      await write(merged);
      if (candidateGardens != null) {
        await gardenStorage.write(
          candidateGardens,
          expectedRevision: gardens.revision,
        );
      }
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
  for (final r in s.people)
    (id: r.id, type: 'householdPerson', json: r.toJson()),
  for (final r in s.financeAccounts)
    (id: r.id, type: 'financeAccount', json: r.toJson()),
  for (final r in s.financeRecurrenceRules)
    (id: r.id, type: 'financeRecurrenceRule', json: r.toJson()),
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
    'householdPerson': 'people',
    'financeAccount': 'financeAccounts',
    'financeRecurrenceRule': 'financeRecurrenceRules',
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
    people: [...a.people, ...b.people],
    financeAccounts: [...a.financeAccounts, ...b.financeAccounts],
    financeRecurrenceRules: [
      ...a.financeRecurrenceRules,
      ...b.financeRecurrenceRules,
    ],
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
  final type = privateRecordType(localType);
  final financial = const [
        'personalFinanceEntry',
        'personalFinanceAccount',
        'financeRecurrenceRule',
      ].contains(type),
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
  final old = await db.rows(
    'SELECT * FROM $table WHERE partition=? AND scope_id=? AND id=?',
    [p, scope, id],
  );
  final wireVersion = privateRecordWireVersion(
    localType,
    source ??
        (old.firstOrNull?['payload'] == null
            ? <String, Object?>{}
            : jsonDecode(old.first['payload'] as String)
                  as Map<String, Object?>),
  );
  Map<String, Object?>? payload;
  if (source != null) {
    payload = Map.of(source)
      ..remove('id')
      ..remove('revision')
      ..remove('createdByAccountId')
      ..remove('updatedByAccountId');
    for (final field in [
      'projectId',
      'listId',
      'taskId',
      'ledgerAccountId',
      'recurrenceRuleId',
      'payerPersonId',
      'recipientPersonId',
      'createdByPersonId',
      'assigneePersonId',
    ]) {
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
    if (payload['subjectPersonIds'] is List) {
      payload['subjectPersonIds'] = await Future.wait(
        (payload['subjectPersonIds'] as List).map((id) async {
          final refs = await db.rows(
            'SELECT remote_id FROM personal_record_map WHERE workspace=? AND id=?',
            [w, id],
          );
          if (refs.isEmpty) {
            throw const FormatException('Missing private person mapping');
          }
          return refs.single['remote_id'];
        }),
      );
    }
    if (type == 'event') {
      payload['startAt'] = payload.remove('startsAt');
      payload['endAt'] = payload.remove('endsAt');
      payload['assigneeAccountIds'] = [];
    }

    payload = privatePayloadForVersion(payload, localType, wireVersion);
    if (financial) {
      validateSharedFinancePayload(
        SharedFinanceRecordType.values.byName(type),
        Map<String, dynamic>.from(payload),
        contractVersion: wireVersion,
      );
    } else {
      validateSharedPayload(
        SharedRecordType.values.byName(type),
        Map<String, dynamic>.from(payload),
        contractVersion: wireVersion,
        personal: true,
      );
    }
  }
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
    'INSERT INTO $outbox(op_id,partition,scope_id,record_id,request,wire_version) VALUES(?,?,?,?,?,?)',
    [request['opId'], p, scope, id, jsonEncode(request), wireVersion],
  );
}

/// Redirect an equivalent newly materialized monthly occurrence to the server's
/// existing identity. Different user values remain a conflict, never overwrite.
Future<bool> reconcilePrivateFinanceDuplicate(
  CollaborationDatabase db,
  String partition,
  String scope,
  String originalRemoteId,
  Map<String, dynamic> canonical,
) => db.transaction(() async {
  if (db.personalProfile?.partition != partition ||
      canonical['type'] != 'personalFinanceEntry' ||
      canonical['deleted'] != false ||
      canonical['id'] == originalRemoteId ||
      !isSharedUuid(canonical['id']) ||
      canonical['payload'] is! Map<String, dynamic>) {
    return false;
  }
  final bindings = await db.rows(
    'SELECT id FROM personal_workspaces WHERE partition=? AND scope_id=? AND enabled=1 AND paused=0',
    [partition, scope],
  );
  if (bindings.length != 1) return false;
  final access = await db.rows(
    'SELECT finance_policy,finance_blocked,blocked FROM scopes WHERE partition=? AND id=?',
    [partition, scope],
  );
  if (access.isEmpty ||
      access.single['blocked'] == 1 ||
      access.single['finance_blocked'] == 1 ||
      access.single['finance_policy'] == null ||
      !SharedFinancePolicy.fromJson(
        jsonDecode(access.single['finance_policy'] as String)
            as Map<String, dynamic>,
      ).canWrite) {
    return false;
  }
  final rows = await db.rows(
    'SELECT * FROM finance_records WHERE partition=? AND scope_id=? AND id=?',
    [partition, scope, originalRemoteId],
  );
  if (rows.length != 1 ||
      rows.single['server_revision'] != 0 ||
      rows.single['payload'] == null) {
    return false;
  }
  final local =
      jsonDecode(rows.single['payload'] as String) as Map<String, dynamic>;
  final remote = canonical['payload'] as Map<String, dynamic>;
  if (local['recurrenceRuleId'] == null ||
      local['recurrenceRuleId'] != remote['recurrenceRuleId'] ||
      local['occurrenceKey'] != remote['occurrenceKey'] ||
      local['currency'] != remote['currency']) {
    return false;
  }
  Object? comparable(Object? value) {
    if (value is Map) {
      return {
        for (final key in value.keys.map((k) => k.toString()).toList()..sort())
          if (!const ['createdAt', 'updatedAt'].contains(key))
            key: comparable(value[key]),
      };
    }
    if (value is List) return value.map(comparable).toList();
    if (value is String && RegExp(r'^\d{4}-\d\d-\d\dT').hasMatch(value)) {
      return DateTime.tryParse(value)?.toUtc().toIso8601String() ?? value;
    }
    return value;
  }

  if (jsonEncode(comparable(local)) != jsonEncode(comparable(remote))) {
    return false;
  }
  final workspace = bindings.single['id'];
  final map = await db.rows(
    'SELECT * FROM personal_record_map WHERE workspace=? AND remote_id=?',
    [workspace, originalRemoteId],
  );
  final occupied = await db.rows(
    'SELECT id FROM personal_record_map WHERE workspace=? AND remote_id=?',
    [workspace, canonical['id']],
  );
  final pending = await db.rows(
    'SELECT op_id FROM finance_outbox WHERE partition=? AND scope_id=? AND record_id=?',
    [partition, scope, originalRemoteId],
  );
  if (map.length != 1 || occupied.isNotEmpty || pending.length != 1) {
    return false;
  }
  await db.execute(
    'UPDATE personal_record_map SET remote_id=? WHERE workspace=? AND id=?',
    [canonical['id'], workspace, map.single['id']],
  );
  await db.execute(
    'UPDATE finance_records SET deleted=1,payload=NULL WHERE partition=? AND scope_id=? AND id=?',
    [partition, scope, originalRemoteId],
  );
  return true;
});

const privateReferenceFields = [
  'projectId',
  'listId',
  'taskId',
  'ledgerAccountId',
  'recurrenceRuleId',
  'payerPersonId',
  'recipientPersonId',
  'createdByPersonId',
  'assigneePersonId',
];
String privateRecordType(String localType) => switch (localType) {
  'financeEntry' => 'personalFinanceEntry',
  'financeAccount' => 'personalFinanceAccount',
  _ => localType,
};
bool privateFinancialType(String localType) => const [
  'financeEntry',
  'financeAccount',
  'financeRecurrenceRule',
  'personalFinanceEntry',
  'personalFinanceAccount',
].contains(localType);
int privateRecordWireVersion(String type, Map<String, Object?> source) {
  if (type == 'householdPerson') return 3;
  if (const [
    'financeAccount',
    'personalFinanceAccount',
    'financeRecurrenceRule',
  ].contains(type)) {
    return 2;
  }
  if (const ['financeEntry', 'personalFinanceEntry'].contains(type)) {
    return (source['status'] != null && source['status'] != 'posted') ||
            const [
              'plannedAt',
              'paidAt',
              'taskId',
              'ledgerAccountId',
              'payerPersonId',
              'recipientPersonId',
              'createdByPersonId',
              'recurrenceRuleId',
              'occurrenceKey',
            ].any((k) => source[k] != null)
        ? 2
        : 1;
  }
  if (source['availabilityMinutes'] != null ||
      source['availabilityPeriod'] != null) {
    return 3;
  }
  if (type == 'project' && (source['phases'] as List? ?? []).isNotEmpty) {
    return 3;
  }
  if (type == 'task' &&
      (source['phaseId'] != null ||
          source['estimateMinutes'] != null ||
          source['assigneePersonId'] != null ||
          (source['subjectPersonIds'] as List? ?? []).isNotEmpty ||
          ((source['timer'] as Map?)?['elapsedSeconds'] ?? 0) != 0 ||
          (source['timer'] as Map?)?['runningSince'] != null)) {
    return 3;
  }
  return 2;
}

/// Empty new defaults have the exact semantics of the old wire contract. Real
/// planning or financial metadata requires its newer contract, never stripped.
Map<String, Object?> privatePayloadForVersion(
  Map<String, Object?> payload,
  String type,
  int version,
) {
  if (privateRecordWireVersion(type, payload) > version) {
    throw const CollaborationException('client_upgrade_required');
  }
  final result = Map<String, Object?>.from(payload);
  if (!privateFinancialType(type) && version < 3) {
    for (final key in [
      'availabilityMinutes',
      'availabilityPeriod',
      if (type == 'project') 'phases',
      if (type == 'task') ...[
        'phaseId',
        'estimateMinutes',
        'timer',
        'assigneePersonId',
        'subjectPersonIds',
      ],
    ]) {
      result.remove(key);
    }
  }
  if (privateFinancialType(type) && version < 2) {
    for (final key in [
      'status',
      'plannedAt',
      'paidAt',
      'taskId',
      'ledgerAccountId',
      'payerPersonId',
      'recipientPersonId',
      'createdByPersonId',
      'recurrenceRuleId',
      'occurrenceKey',
    ]) {
      result.remove(key);
    }
  }
  return result;
}

Future<void> pairPrivateTaskCostOperations(
  CollaborationDatabase db,
  Map<String, dynamic> binding,
  String taskId,
  String financeId,
) async {
  final p = binding['partition'] as String,
      scope = binding['scope_id'] as String,
      workspace = binding['id'] as String;
  final refs = await db.rows(
    'SELECT id,remote_id FROM personal_record_map WHERE workspace=? AND id IN (?,?)',
    [workspace, taskId, financeId],
  );
  final mapped = {for (final r in refs) r['id']: r['remote_id']};
  final generic = await db.rows(
    "SELECT op_id FROM outbox WHERE partition=? AND scope_id=? AND record_id=? AND state='pending' ORDER BY sequence DESC LIMIT 1",
    [p, scope, mapped[taskId]],
  );
  final finance = await db.rows(
    "SELECT op_id FROM finance_outbox WHERE partition=? AND scope_id=? AND record_id=? AND state='pending' ORDER BY sequence DESC LIMIT 1",
    [p, scope, mapped[financeId]],
  );
  if (generic.isNotEmpty && finance.isNotEmpty) {
    await db.execute(
      'INSERT INTO local_meta(name,value) VALUES(?,?) ON CONFLICT(name) DO UPDATE SET value=excluded.value',
      ['task_cost_pair:$p:${generic.single['op_id']}', finance.single['op_id']],
    );
  }
}

String _personalRevisionKey(String workspace, String id) =>
    'personal_record_revision:${Uri.encodeComponent(workspace)}:${Uri.encodeComponent(id)}';
Future<int?> personalRevisionFloor(
  CollaborationDatabase db,
  String workspace,
  String id,
) async {
  final rows = await db.rows('SELECT value FROM local_meta WHERE name=?', [
    _personalRevisionKey(workspace, id),
  ]);
  if (rows.isEmpty) return null;
  final value = int.tryParse(rows.single['value'] as String);
  if (value == null || value < 0 || value >= 9007199254740991) {
    throw const FormatException('Invalid personal revision floor');
  }
  return value;
}

Future<void> savePersonalRevisionFloor(
  CollaborationDatabase db,
  String workspace,
  String id,
  int revision,
) async {
  final floor = await personalRevisionFloor(db, workspace, id);
  final value = floor != null && floor > revision ? floor : revision;
  if (value < 0 || value >= 9007199254740991) {
    throw const FormatException('Invalid personal revision floor');
  }
  await db.execute(
    'INSERT INTO local_meta(name,value) VALUES(?,?) ON CONFLICT(name) DO UPDATE SET value=excluded.value',
    [_personalRevisionKey(workspace, id), value.toString()],
  );
}

Future<void> commitPersonalRow(
  CollaborationDatabase db,
  String workspace,
  PersonalRow row,
) async {
  final json = Map<String, Object?>.of(row.json);
  if (row.type != 'reminder') {
    final floor = await personalRevisionFloor(db, workspace, row.id);
    final revision = json['revision'] as int? ?? 0;
    json['revision'] = floor != null && revision <= floor
        ? floor + 1
        : revision;
    await savePersonalRevisionFloor(
      db,
      workspace,
      row.id,
      json['revision'] as int,
    );
  }
  await db.execute(
    'INSERT INTO personal_records(workspace,id,type,payload) VALUES(?,?,?,?) ON CONFLICT(workspace,id) DO UPDATE SET payload=excluded.payload',
    [workspace, row.id, row.type, jsonEncode(json)],
  );
}
