import 'dart:convert';
import '../domain/collaboration_models.dart';
import '../domain/organizer_models.dart';
import '../domain/garden_models.dart';
import '../domain/local_space_models.dart';
import '../domain/linked_payment_models.dart';
import '../domain/shared_payload_validation.dart';
import '../domain/shared_finance_validation.dart';
import '../domain/shared_dates.dart';
import 'sqlite_organizer_storage.dart';
import 'organizer_storage.dart';

const backupTables = <String, List<String>>{
  'scopes': [
    'partition',
    'id',
    'data',
    'cursor',
    'blocked',
    'finance_cursor',
    'finance_access_revision',
    'finance_policy',
    'finance_blocked',
    'finance_complete',
  ],
  'records': [
    'partition',
    'scope_id',
    'id',
    'type',
    'local_revision',
    'server_revision',
    'payload',
    'deleted',
    'remote',
  ],
  'outbox': [
    'sequence',
    'op_id',
    'partition',
    'scope_id',
    'record_id',
    'request',
    'state',
    'wire_version',
  ],
  'conflicts': [
    'id',
    'partition',
    'scope_id',
    'record_id',
    'type',
    'reason',
    'remote',
  ],
  'finance_records': [
    'partition',
    'scope_id',
    'id',
    'type',
    'local_revision',
    'server_revision',
    'payload',
    'deleted',
    'remote',
  ],
  'finance_outbox': [
    'wire_version',
    'sequence',
    'op_id',
    'partition',
    'scope_id',
    'record_id',
    'request',
    'state',
  ],
  'finance_conflicts': [
    'id',
    'partition',
    'scope_id',
    'record_id',
    'type',
    'reason',
    'remote',
  ],
  'members': ['partition', 'scope_id', 'account_id', 'data'],
  'inbox': ['partition', 'id', 'data', 'remote'],
  'inbox_state': ['partition', 'cursor', 'visibility_revision'],
  'commands': [
    'sequence',
    'id',
    'partition',
    'operation',
    'params',
    'entity_key',
    'state',
  ],
  'notification_preferences': ['partition', 'scope_id', 'data'],
  'scheduled_reminders': ['partition', 'id', 'scope_id', 'data', 'remote'],
};

Map<String, dynamic> backupMap(Object? value) => value as Map<String, dynamic>;
List<Map<String, dynamic>> backupRows(Map<String, dynamic> doc, String table) {
  final rows = (backupMap(doc['tables'])[table] as List)
      .cast<Map<String, dynamic>>();
  if (table == 'finance_outbox' && (doc['version'] as int) < 3) {
    // Add envelope metadata only; the immutable request remains byte-for-byte.
    for (final row in rows) {
      row.putIfAbsent('wire_version', () => 1);
    }
  }
  return rows;
}

OrganizerSnapshot backupPersonal(Map<String, dynamic> doc) =>
    OrganizerBackupCodec.decode(doc['personal'] as String);

GardenSnapshot? backupGardens(Map<String, dynamic> doc) => doc['version'] == 1
    ? null
    : GardenSnapshot.fromJson(backupMap(doc['gardens']));

/// Reject unsupported fields and invalid parent links before any restore write.
void validateBackupDocument(Map<String, dynamic> doc) {
  try {
    if (doc.keys.toSet().difference({
          'format',
          'version',
          'databaseVersion',
          'id',
          'createdAt',
          'source',
          'privateData',
          'personal',
          'tables',
          'uiPreferences',
          'completeness',
          'exclusions',
          if (doc['version'] != 1) 'gardens',
          if ((doc['version'] as int) >= 3) ...[
            'operationPairs',
            'financeInboxReads',
          ],
          if (doc['version'] == 4) ...[
            'localSpaces',
            'gardenSpaceLinks',
            'linkedPayments',
          ],
        }).isNotEmpty ||
        doc.length !=
            (doc['version'] == 1
                ? 12
                : doc['version'] == 2
                ? 13
                : doc['version'] == 3
                ? 15
                : doc.containsKey('linkedPayments')
                ? 18
                : 17) ||
        doc['format'] != 'vsakdan-portable-data' ||
        !const [1, 2, 3, 4].contains(doc['version']) ||
        (doc['version'] == 4
            ? !const [7, 8].contains(doc['databaseVersion'])
            : doc['databaseVersion'] !=
                  (doc['version'] == 1
                      ? 4
                      : doc['version'] == 2
                      ? 5
                      : doc['version'] == 3
                      ? 6
                      : 7)) ||
        !isSharedUuid(doc['id'] as String)) {
      throw const FormatException();
    }
    DateTime.parse(doc['createdAt'] as String);
    backupPersonal(doc).validate();
    // Portable documents have one canonical garden section; embedded JSON
    // garden extensions are rejected to avoid ambiguous duplicate restores.
    if (OrganizerBackupCodec.decodeDocument(
          doc['personal'] as String,
        ).gardens !=
        null) {
      throw const FormatException();
    }
    backupGardens(doc)?.validate();
    if (doc['version'] == 4) {
      validateBackupLocalSpaces(doc);
      if (doc['linkedPayments'] != null) {
        validateLinkedPaymentsBackup(backupMap(doc['linkedPayments']));
      }
    }
    final source = doc['source'] == null ? null : backupMap(doc['source']);
    if (source != null &&
        (source.keys.toSet().difference({
              'partition',
              'serverId',
              'accountId',
              'serverUrl',
              'username',
              'displayName',
              if (doc['version'] == 4) 'deviceId',
            }).isNotEmpty ||
            !isSharedUuid(source['serverId'] as String) ||
            !isSharedUuid(source['accountId'] as String))) {
      throw const FormatException();
    }
    final tables = backupMap(doc['tables']);
    if (tables.keys.toSet().difference(backupTables.keys.toSet()).isNotEmpty ||
        tables.length != backupTables.length) {
      throw const FormatException();
    }
    final scopeMap = <String, SharedScope>{};
    for (final table in backupTables.keys) {
      for (final row in backupRows(doc, table)) {
        if (row.keys
                .toSet()
                .difference(backupTables[table]!.toSet())
                .isNotEmpty ||
            row.length != backupTables[table]!.length ||
            source == null ||
            row['partition'] != source['partition']) {
          throw const FormatException();
        }
        if (table == 'scopes') {
          final scope = SharedScope.fromJson(
            backupMap(jsonDecode(row['data'] as String)),
          );
          if (scope.id != row['id'] ||
              scope.revoked ||
              scopeMap.containsKey(scope.id)) {
            throw const FormatException();
          }
          scopeMap[scope.id] = scope;
        }
      }
    }
    final ids = <String, Set<String>>{'records': {}, 'finance_records': {}};
    for (final table in ['records', 'finance_records']) {
      for (final row in backupRows(doc, table)) {
        final scope = scopeMap[row['scope_id']];
        if (scope == null ||
            !isSharedUuid(row['id'] as String) ||
            (row['local_revision'] as int) < 0 ||
            (row['server_revision'] as int) < 0 ||
            !const [0, 1].contains(row['deleted'])) {
          throw const FormatException();
        }
        if (table == 'records') {
          SharedRecordType.values.byName(row['type'] as String);
        } else {
          SharedFinanceRecordType.values.byName(row['type'] as String);
        }
        if ((row['deleted'] == 1) != (row['payload'] == null)) {
          throw const FormatException();
        }
        final key = '${row['scope_id']}:${row['id']}';
        if (!(ids[table] ??= <String>{}).add(key)) {
          throw const FormatException();
        }
        if (row['payload'] != null) {
          final payload = backupMap(jsonDecode(row['payload'] as String));
          if (table == 'records') {
            validateSharedPayload(
              SharedRecordType.values.byName(row['type'] as String),
              payload,
              contractVersion: sharedPayloadContractVersion(
                row['type'] as String,
                payload,
              ),
              personal: scope.kind == SharedScopeKind.personal,
            );
          } else {
            final type = SharedFinanceRecordType.values.byName(
              row['type'] as String,
            );
            if (const [
                      SharedFinanceRecordType.personalFinanceEntry,
                      SharedFinanceRecordType.personalFinanceAccount,
                    ].contains(type) !=
                    (scope.kind == SharedScopeKind.personal) &&
                type != SharedFinanceRecordType.financeRecurrenceRule) {
              throw const FormatException();
            }
            validateSharedFinancePayload(
              type,
              payload,
              contractVersion: backupFinanceContractVersion(type.name, payload),
            );
          }
        }
      }
    }
    for (final table in ['outbox', 'finance_outbox']) {
      final opIds = <String>{};
      var lastSequence = 0;
      final recordTypes = {
        for (final r in backupRows(
          doc,
          table == 'outbox' ? 'records' : 'finance_records',
        ))
          '${r['scope_id']}:${r['id']}': r['type'],
      };
      for (final row in backupRows(doc, table)) {
        final request = backupMap(jsonDecode(row['request'] as String));
        if (!isSharedUuid(row['op_id'] as String) ||
            !opIds.add(row['op_id'] as String) ||
            request['opId'] != row['op_id'] ||
            request['recordId'] != row['record_id'] ||
            !ids[table == 'outbox' ? 'records' : 'finance_records']!.contains(
              '${row['scope_id']}:${row['record_id']}',
            ) ||
            !const ['pending', 'blocked', 'conflict'].contains(row['state']) ||
            request.keys.toSet().difference({
              'opId',
              'recordId',
              'type',
              'expectedRevision',
              'deleted',
              'payload',
            }).isNotEmpty ||
            (request['expectedRevision'] as int) < 0 ||
            request['deleted'] is! bool) {
          throw const FormatException();
        }
        if ((row['sequence'] as int) <= lastSequence ||
            request['type'] !=
                recordTypes['${row['scope_id']}:${row['record_id']}'] ||
            (request['deleted'] == true) != (request['payload'] == null) ||
            (table == 'outbox' &&
                !const [1, 2, 3, 4].contains(row['wire_version']))) {
          throw const FormatException();
        }
        lastSequence = row['sequence'] as int;
        final scope = scopeMap[row['scope_id']]!;
        if (request['payload'] != null) {
          if (table == 'outbox') {
            validateSharedPayload(
              SharedRecordType.values.byName(request['type'] as String),
              backupMap(request['payload']),
              contractVersion: row['wire_version'] as int,
              personal: scope.kind == SharedScopeKind.personal,
            );
          } else {
            validateSharedFinancePayload(
              SharedFinanceRecordType.values.byName(request['type'] as String),
              backupMap(request['payload']),
              contractVersion: row['wire_version'] as int? ?? 1,
            );
          }
        }
      }
    }
    final private = backupMap(doc['privateData']);
    if (private.keys.toSet().difference({
          'binding',
          'maps',
          'reminders',
        }).isNotEmpty ||
        private.length != 3) {
      throw const FormatException();
    }
    final binding = private['binding'];
    if (binding != null &&
        (binding is! Map ||
            source == null ||
            binding['partition'] != source['partition'] ||
            binding['id'] != 'private:${source['partition']}' ||
            scopeMap[binding['scope_id']]?.kind != SharedScopeKind.personal)) {
      throw const FormatException();
    }
    final originalIds = <String>{}, remoteIds = <String>{};
    for (final value in private['maps'] as List) {
      final m = backupMap(value);
      if (binding == null ||
          m['workspace'] != binding['id'] ||
          !const [
            'project',
            'task',
            'event',
            'shoppingList',
            'shoppingItem',
            'personalFinanceEntry',
            'personalFinanceAccount',
            'financeRecurrenceRule',
            'householdPerson',
          ].contains(m['type']) ||
          m.keys.toSet().difference({
            'workspace',
            'id',
            'remote_id',
            'type',
          }).isNotEmpty ||
          !isSharedUuid(m['remote_id'] as String) ||
          !originalIds.add(m['id'] as String) ||
          !remoteIds.add(m['remote_id'] as String) ||
          (m['id'] as String).isEmpty ||
          (m['id'] as String).length > 200) {
        throw const FormatException();
      }
    }
    for (final value in private['maps'] as List) {
      final m = backupMap(value);
      if (!backupRows(
        doc,
        const [
              'personalFinanceEntry',
              'personalFinanceAccount',
              'financeRecurrenceRule',
            ].contains(m['type'])
            ? 'finance_records'
            : 'records',
      ).any(
        (r) =>
            r['scope_id'] == binding['scope_id'] &&
            r['id'] == m['remote_id'] &&
            r['type'] == m['type'],
      )) {
        throw const FormatException();
      }
    }
    for (final r in private['reminders'] as List) {
      LocalReminder.fromJson(
        backupMap(jsonDecode(backupMap(r)['payload'] as String)),
      );
    }
    for (final table in [
      'records',
      'finance_records',
      'conflicts',
      'finance_conflicts',
    ]) {
      for (final row in backupRows(doc, table)) {
        if (row['remote'] == null) continue;
        final remote = backupMap(jsonDecode(row['remote'] as String));
        final id = table.endsWith('conflicts') ? row['record_id'] : row['id'];
        if (remote.keys.toSet().difference({
              'id',
              'type',
              'revision',
              'deleted',
              'payload',
              'sequence',
              'updatedAt',
              'createdByAccountId',
              'updatedByAccountId',
              if (table.startsWith('finance')) 'contractVersion',
            }).isNotEmpty ||
            (remote.containsKey('contractVersion') &&
                !const [1, 2].contains(remote['contractVersion'])) ||
            remote['id'] != id ||
            remote['type'] != row['type'] ||
            (remote['revision'] as int) < 1 ||
            (remote['sequence'] as int) < 1 ||
            remote['deleted'] is! bool ||
            (remote['deleted'] == true) != (remote['payload'] == null)) {
          throw const FormatException();
        }
        readSharedDate(remote, 'updatedAt');
        if (remote['payload'] != null) {
          final p = backupMap(remote['payload']);
          if (table.startsWith('finance')) {
            validateSharedFinancePayload(
              SharedFinanceRecordType.values.byName(row['type'] as String),
              p,
              contractVersion:
                  remote['contractVersion'] as int? ??
                  backupFinanceContractVersion(row['type'] as String, p),
            );
          } else {
            validateSharedPayload(
              SharedRecordType.values.byName(row['type'] as String),
              p,
              contractVersion: sharedPayloadContractVersion(
                row['type'] as String,
                p,
              ),
              personal:
                  scopeMap[row['scope_id']]!.kind == SharedScopeKind.personal,
            );
          }
        }
      }
    }
    validateBackupLinks(doc);
    validateBackupOperationPairs(doc);
    validateBackupFinanceInboxReads(doc);
    for (final row in backupRows(doc, 'commands')) {
      final operation = row['operation'] as String,
          params = backupMap(jsonDecode(row['params'] as String));
      validateBackupCommand(operation, params, scopeMap.keys.toSet());
    }
    for (final row in backupRows(doc, 'notification_preferences')) {
      final prefs = backupMap(jsonDecode(row['data'] as String));
      for (final value in prefs.values) {
        SharedNotificationSettings.fromJson(backupMap(value));
      }
    }
    validateBackupUiPreferences(backupMap(doc['uiPreferences']));
    if (doc['completeness'] is! List || doc['exclusions'] is! List) {
      throw const FormatException();
    }
    // A copied personal snapshot is strict including every cross-reference.
    snapshotRows(backupPersonal(doc));
  } on Object {
    throw const CollaborationException('backup_unsupported');
  }
}

void validateBackupUiPreferences(Map<String, dynamic> prefs) {
  if (prefs.keys.toSet().difference({
        'app_locale_code',
        'app_theme_mode',
        'organizer_getting_started_seen_v1',
      }).isNotEmpty ||
      (prefs['app_locale_code'] != null &&
          !const ['sl', 'en'].contains(prefs['app_locale_code'])) ||
      (prefs.containsKey('app_theme_mode') &&
          !const [
            'system',
            'light',
            'dark',
          ].contains(prefs['app_theme_mode'])) ||
      (prefs.containsKey('organizer_getting_started_seen_v1') &&
          prefs['organizer_getting_started_seen_v1'] is! bool)) {
    throw const CollaborationException('backup_unsupported');
  }
}

void validateBackupCommand(
  String operation,
  Map<String, dynamic> p,
  Set<String> scopes,
) {
  final keys = switch (operation) {
    'inbox.read' => {'id', 'read', 'expectedRevision', 'requestId'},
    'inbox.preferences.set' => {'scopeId', 'category', 'settings', 'requestId'},
    'reminders.put' => {
      'id',
      'scopeId',
      'targetType',
      'targetId',
      'remindAt',
      'expectedRevision',
      'requestId',
    },
    'reminders.cancel' => {'id', 'scopeId', 'expectedRevision', 'requestId'},
    _ => throw const FormatException('Unsupported recovery command'),
  };
  if (p.keys.toSet().difference(keys).isNotEmpty ||
      p.length != keys.length ||
      !isSharedUuid(p['requestId'] as String)) {
    throw const FormatException();
  }
  if (p.containsKey('scopeId') && !scopes.contains(p['scopeId'])) {
    throw const FormatException();
  }
  if (p.containsKey('expectedRevision') && (p['expectedRevision'] as int) < 0) {
    throw const FormatException();
  }
  if (operation == 'inbox.read') {
    if (p['id'] is! int || (p['id'] as int) < 1 || p['read'] is! bool) {
      throw const FormatException();
    }
  } else if (operation == 'inbox.preferences.set') {
    if (!const [
      'tasks',
      'events',
      'shopping',
      'finance',
      'reminders',
      'membership',
    ].contains(p['category'])) {
      throw const FormatException();
    }
    final settings = backupMap(p['settings']);
    if (settings.keys.toSet().difference({
          'inApp',
          'sound',
          'email',
          'push',
        }).isNotEmpty ||
        settings.values.any((v) => v is! bool)) {
      throw const FormatException();
    }
    SharedNotificationSettings.fromJson(settings);
  } else {
    if (!isSharedUuid(p['id'] as String)) throw const FormatException();
    if (operation == 'reminders.put') {
      if (!const ['task', 'event', 'financeEntry'].contains(p['targetType']) ||
          !isSharedUuid(p['targetId'] as String)) {
        throw const FormatException();
      }
      readSharedDate(p, 'remindAt');
    }
  }
}

void validateBackupLinks(Map<String, dynamic> doc) {
  final generic = {
    for (final r in backupRows(doc, 'records'))
      '${r['scope_id']}:${r['id']}': r,
  };
  final finance = {
    for (final r in backupRows(doc, 'finance_records'))
      '${r['scope_id']}:${r['id']}': r,
  };
  for (final r in [...generic.values, ...finance.values]) {
    if (r['payload'] == null) continue;
    final p = backupMap(jsonDecode(r['payload'] as String));
    for (final field in ['projectId', 'listId']) {
      if (p[field] != null &&
          generic['${r['scope_id']}:${p[field]}']?['type'] !=
              (field == 'projectId' ? 'project' : 'shoppingList')) {
        throw const FormatException('Invalid parent');
      }
    }
    for (final field in ['accountId', 'fromAccountId', 'toAccountId']) {
      if (p[field] != null) {
        final account = finance['${r['scope_id']}:${p[field]}'];
        if (account?['type'] != 'financeAccount' ||
            account?['payload'] == null ||
            backupMap(jsonDecode(account!['payload'] as String))['currency'] !=
                p['currency']) {
          throw const FormatException('Invalid financial account');
        }
      }
    }
  }
  for (final table in ['conflicts', 'finance_conflicts']) {
    final records = table == 'conflicts' ? generic : finance;
    for (final c in backupRows(doc, table)) {
      if (!isSharedUuid(c['id'] as String) ||
          records['${c['scope_id']}:${c['record_id']}']?['type'] != c['type']) {
        throw const FormatException('Invalid conflict');
      }
    }
  }
}

int backupFinanceContractVersion(String type, Map<String, dynamic> p) =>
    const ['personalFinanceAccount', 'financeRecurrenceRule'].contains(type) ||
        p.containsKey('plannedAt') ||
        p.containsKey('openingBalanceAt')
    ? 2
    : 1;

void validateBackupOperationPairs(Map<String, dynamic> doc) {
  if ((doc['version'] as int) < 3) return;
  if (doc['operationPairs'] is! List) {
    throw const FormatException('Missing operation pairs');
  }
  final generic = {
    for (final row in backupRows(doc, 'outbox')) row['op_id']: row,
  };
  final finance = {
    for (final row in backupRows(doc, 'finance_outbox')) row['op_id']: row,
  };
  final seenGeneric = <String>{}, seenFinance = <String>{};
  for (final raw in doc['operationPairs'] as List) {
    final pair = backupMap(raw),
        g = generic[pair['genericOpId']],
        f = finance[pair['financeOpId']];
    if (pair.length != 2 ||
        !isSharedUuid(pair['genericOpId']) ||
        !isSharedUuid(pair['financeOpId']) ||
        !seenGeneric.add(pair['genericOpId'] as String) ||
        !seenFinance.add(pair['financeOpId'] as String) ||
        g == null ||
        f == null ||
        g['partition'] != f['partition'] ||
        g['scope_id'] != f['scope_id']) {
      throw const FormatException('Invalid operation pair');
    }
    final gp = backupMap(jsonDecode(g['request'] as String)),
        fp = backupMap(jsonDecode(f['request'] as String));
    if (gp['type'] != 'task' ||
        !const ['financeEntry', 'personalFinanceEntry'].contains(fp['type'])) {
      throw const FormatException('Invalid paired types');
    }
    final taskId = gp['recordId'];
    if (fp['payload'] != null && (fp['payload'] as Map)['taskId'] == taskId) {
      continue;
    }
    // Detaching preserves the finance record; prove its original task link.
    final history = finance.values
        .where(
          (r) =>
              r['scope_id'] == f['scope_id'] &&
              r['record_id'] == f['record_id'],
        )
        .map((r) => backupMap(jsonDecode(r['request'] as String)));
    final canonical = backupRows(doc, 'finance_records')
        .where(
          (r) => r['scope_id'] == f['scope_id'] && r['id'] == f['record_id'],
        )
        .firstOrNull?['remote'];
    if (!history.any(
          (r) =>
              r['payload'] != null && (r['payload'] as Map)['taskId'] == taskId,
        ) &&
        !(canonical != null &&
            (backupMap(jsonDecode(canonical as String))['payload']
                    as Map?)?['taskId'] ==
                taskId)) {
      throw const FormatException('Unproven cost detach');
    }
  }
}

void validateBackupFinanceInboxReads(Map<String, dynamic> doc) {
  if ((doc['version'] as int) < 3) return;
  if (doc['financeInboxReads'] is! List ||
      (doc['financeInboxReads'] as List).length > 50000) {
    throw const FormatException('Invalid finance inbox receipts');
  }
  final source = doc['source'] as Map?;
  final seen = <String>{};
  for (final raw in doc['financeInboxReads'] as List) {
    final receipt = backupMap(raw), name = receipt['name'];
    if (receipt.length != 2 ||
        !receipt.containsKey('value') ||
        name is! String ||
        name.length > 4096 ||
        !seen.add(name) ||
        (!name.startsWith('finance_inbox_read:personal:local:') &&
            !(source != null &&
                name.startsWith(
                  'finance_inbox_read:${source['partition']}:',
                )))) {
      throw const FormatException('Invalid finance inbox receipt source');
    }
    readSharedDate(receipt, 'value');
  }
}

void validateBackupLocalSpaces(Map<String, dynamic> doc) {
  final spaces = doc['localSpaces'];
  if (spaces is! List || spaces.length > 1000) {
    throw const FormatException('Invalid local spaces');
  }
  final ids = <String>{}, households = <String>{};
  for (final raw in spaces) {
    final item = backupMap(raw);
    if (item.length != 2 ||
        !item.containsKey('space') ||
        !item.containsKey('snapshot')) {
      throw const FormatException('Invalid local space document');
    }
    final space = LocalSpace.fromJson(backupMap(item['space']));
    if (!ids.add(space.id)) {
      throw const FormatException('Duplicate local space');
    }
    if (space.kind == LocalSpaceKind.household) households.add(space.id);
    final snapshot = OrganizerBackupCodec.decode(item['snapshot'] as String);
    snapshot.validate();
  }
  final gardenIds = backupGardens(doc)!.gardens.map((g) => g.id).toSet();
  final seen = <String>{};
  for (final raw in doc['gardenSpaceLinks'] as List) {
    final link = backupMap(raw);
    if (link.length != 2 ||
        !gardenIds.contains(link['garden_id']) ||
        !households.contains(link['space_id']) ||
        !seen.add(link['garden_id'] as String)) {
      throw const FormatException('Invalid garden household');
    }
  }
}
