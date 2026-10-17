import 'dart:convert';
import '../domain/collaboration_models.dart';
import '../domain/organizer_models.dart';
import '../domain/garden_models.dart';
import '../domain/idea_models.dart';
import '../domain/spreadsheet_models.dart';
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
          if ((doc['version'] as int) >= 4) ...[
            'localSpaces',
            'gardenSpaceLinks',
            'linkedPayments',
          ],
          if ((doc['version'] as int) >= 6) 'localTaskReminderPreferences',
          if ((doc['version'] as int) >= 7) 'tableDrafts',
          if ((doc['version'] as int) >= 5) ...[
            'ideas',
            'ideaSpaceLinks',
            'ideaAssets',
            'ideaDrafts',
            'ideaOperationHistory',
          ],
        }).isNotEmpty ||
        doc.length !=
            (doc['version'] == 1
                ? 12
                : doc['version'] == 2
                ? 13
                : doc['version'] == 3
                ? 15
                : (doc['version'] as int) >= 7
                ? 25
                : doc['version'] == 6
                ? 24
                : (doc['version'] as int) >= 5
                ? 23
                : doc.containsKey('linkedPayments')
                ? 18
                : 17) ||
        doc['format'] != 'vsakdan-portable-data' ||
        !const [1, 2, 3, 4, 5, 6, 7, 8].contains(doc['version']) ||
        ((doc['version'] as int) >= 4
            ? !((doc['version'] as int) >= 6
                      ? const [10]
                      : doc['version'] == 5
                      ? const [9]
                      : const [7, 8])
                  .contains(doc['databaseVersion'])
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
    if ((doc['version'] as int) >= 5) validateBackupIdeas(doc);
    if ((doc['version'] as int) >= 6) {
      final rows = doc['localTaskReminderPreferences'];
      if (rows is! List || rows.length > 50000) {
        throw const FormatException('Invalid reminder preferences');
      }
      final names = <String>{};
      for (final raw in rows) {
        final row = backupMap(raw);
        ideaKeys(row, {'name', 'value'});
        final name = row['name'];
        if (name is! String ||
            !RegExp(
              r'^local_task_deadline_reminder:(personal|local:[^\u0000]{1,200}):task:[^\u0000]{1,200}:due$',
            ).hasMatch(name) ||
            !names.add(name)) {
          throw const FormatException('Invalid reminder preference identity');
        }
        final value = backupMap(jsonDecode(row['value'] as String));
        ideaKeys(value, {
          'createdAt',
          'offsetMinutes',
          'enabled',
          'lastRemindAt',
        });
        if (value['enabled'] is! bool ||
            value['offsetMinutes'] is! int ||
            !const [0, 60, 1440].contains(value['offsetMinutes'])) {
          throw const FormatException('Invalid reminder preference');
        }
        readSharedDate(value, 'createdAt');
        readSharedDate(value, 'lastRemindAt');
      }
    }

    if ((doc['version'] as int) >= 4) {
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
              if ((doc['version'] as int) >= 4) 'deviceId',
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
          if (row['type'] == 'idea' && (doc['version'] as int) < 5) {
            throw const FormatException(
              'Idea records require image-capable backup content5',
            );
          }
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
            if ((doc['version'] as int) < 8 &&
                backupFinanceContractVersion(type.name, payload) >= 3) {
              throw const FormatException('Finance links require backup 8');
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
            (table == 'finance_outbox' &&
                !((doc['version'] as int) >= 8 ? const [1, 2, 3] : const [1, 2])
                    .contains(row['wire_version'] ?? 1)) ||
            (table == 'outbox' &&
                !((doc['version'] as int) >= 5
                        ? ((doc['version'] as int) >= 6
                              ? const [1, 2, 3, 4, 5, 6]
                              : const [1, 2, 3, 4, 5])
                        : const [1, 2, 3, 4])
                    .contains(row['wire_version']))) {
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
          ![
            'project',
            'task',
            'event',
            'shoppingList',
            'shoppingItem',
            'personalFinanceEntry',
            'personalFinanceAccount',
            'financeRecurrenceRule',
            'householdPerson',
            if ((doc['version'] as int) >= 5) 'idea',
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
                !((doc['version'] as int) >= 8 ? const [1, 2, 3] : const [1, 2])
                    .contains(remote['contractVersion'])) ||
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
    if ((doc['version'] as int) >= 7) validateBackupTableDrafts(doc);
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
    if (!sharedNotificationCategories.contains(p['category'])) {
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
  final scopes = {
    for (final row in backupRows(doc, 'scopes'))
      row['id']: SharedScope.fromJson(
        backupMap(jsonDecode(row['data'] as String)),
      ),
  };
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
        final external =
            r['type'] == 'financeEntry' &&
            field == 'accountId' &&
            p['accountScopeId'] != null;
        final accountScope = external ? p['accountScopeId'] : r['scope_id'];
        if (external &&
            ((doc['version'] as int) < 8 ||
                scopes[r['scope_id']]?.kind != SharedScopeKind.project ||
                scopes[r['scope_id']]?.parentSpaceId != accountScope)) {
          throw const FormatException('Invalid parent account scope');
        }
        final account = finance['$accountScope:${p[field]}'];
        // A project-only backup must not contain the parent's private ledger.
        // Keep its validated reference quarantined; recovery fetches fresh rights
        // and sanitized choices instead of restoring a grant or inventing money.
        if (external && account == null) continue;
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
    type == 'financeEntry' &&
        (p.containsKey('accountScopeId') || p.containsKey('projectId'))
    ? 3
    : const [
            'personalFinanceAccount',
            'financeRecurrenceRule',
          ].contains(type) ||
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

IdeaSnapshot? backupIdeas(Map<String, dynamic> doc) =>
    (doc['version'] as int) >= 5
    ? IdeaSnapshot.fromJson(backupMap(doc['ideas']))
    : null;
void validateBackupIdeas(Map<String, dynamic> doc) {
  final ideas = backupIdeas(doc)!;
  ideas.validate();
  if ((doc['version'] as int) < 6 && ideas.boards.any((b) => b.version >= 2)) {
    throw const FormatException('Extended ideas require content6');
  }
  final spaces = {
    for (final r in doc['localSpaces'] as List) (r as Map)['space']['id'],
  };
  final source = doc['source'] == null
      ? null
      : backupMap(doc['source'])['partition'];
  final allowedWorkspaces = <String>{
    ...spaces.cast<String>(),
    for (final r in backupRows(doc, 'scopes')) 'shared:$source:${r['id']}',
  };
  final ids = ideas.boards.map((b) => b.id).toSet(), linked = <String>{};
  for (final r in doc['ideaSpaceLinks'] as List) {
    final v = backupMap(r);
    ideaKeys(v, {'idea_id', 'space_id'});
    if (!ids.contains(v['idea_id']) ||
        !spaces.contains(v['space_id']) ||
        !linked.add(v['idea_id'] as String)) {
      throw const FormatException('Invalid idea space link');
    }
  }
  final required = <String, IdeaAsset>{};
  void require(IdeaBoard b, String workspace) {
    for (final a in b.assets) {
      required['$workspace:${a.sha256}'] = a;
    }
  }

  final ownership = {
    for (final r in doc['ideaSpaceLinks'] as List)
      (r as Map)['idea_id']: r['space_id'],
  };
  for (final b in ideas.boards) {
    require(b, ownership[b.id] as String? ?? 'local');
  }
  for (final raw in backupRows(doc, 'records')) {
    if (raw['type'] == 'idea' && raw['payload'] != null) {
      require(
        IdeaBoard.fromJson(backupMap(jsonDecode(raw['payload'] as String))),
        'shared:$source:${raw['scope_id']}',
      );
    }
  }
  for (final raw in doc['ideaDrafts'] as List) {
    final r = backupMap(raw);
    require(
      IdeaBoard.fromJson(backupMap(jsonDecode(r['payload'] as String))),
      r['workspace'] as String,
    );
    if (r['base'] != null) {
      require(
        IdeaBoard.fromJson(backupMap(jsonDecode(r['base'] as String))),
        r['workspace'] as String,
      );
    }
  }
  final keys = <String>{};
  for (final r in doc['ideaAssets'] as List) {
    final v = backupMap(r);
    ideaKeys(v, {'workspace', 'sha256', 'metadata', 'data'});
    if (!allowedWorkspaces.contains(v['workspace'])) {
      throw const FormatException('Invalid idea image workspace');
    }
    final asset = IdeaAsset.fromJson(
      backupMap(jsonDecode(v['metadata'] as String)),
    );
    final expected = required['${v['workspace']}:${asset.sha256}'];
    if (expected != null &&
        jsonEncode(expected.toJson()) != jsonEncode(asset.toJson())) {
      throw const FormatException('Idea image metadata mismatch');
    }
    if (v['sha256'] != asset.sha256 ||
        base64Decode(v['data'] as String).length != asset.size ||
        !keys.add('${v['workspace']}:${asset.sha256}')) {
      throw const FormatException('Invalid idea image archive');
    }
  }
  for (final key in required.keys) {
    if (!keys.contains(key) &&
        !(doc['completeness'] as List).contains('idea_asset_missing:$key')) {
      throw const FormatException('Missing idea image must be declared');
    }
  }
  for (final r in doc['ideaOperationHistory'] as List) {
    final row = backupMap(r);
    ideaKeys(row, {'name', 'value'});
    final name = row['name'] as String;
    if (name == 'idea_import_archive:$source') {
      final archived = backupMap(jsonDecode(row['value'] as String));
      ideaKeys(archived, {'partition', 'scopeId', 'boards', 'drafts'});
      if (archived['partition'] != source ||
          !allowedWorkspaces.contains(
            'shared:$source:${archived['scopeId']}',
          )) {
        throw const FormatException('Invalid idea import archive source');
      }
      ideaId(archived['scopeId'] as String);
      final originalIds = <String>{};
      for (final raw in archived['boards'] as List) {
        final b = IdeaBoard.fromJson(backupMap(raw));
        if (!originalIds.add(b.id)) {
          throw const FormatException('Duplicate archived idea');
        }
      }
      for (final raw in archived['drafts'] as List) {
        final d = backupMap(raw);
        ideaKeys(d, {'workspace', 'id', 'payload', 'base'});
        if (d['workspace'] != 'local') {
          throw const FormatException('Invalid original idea draft workspace');
        }
        final b = IdeaBoard.fromJson(
          backupMap(jsonDecode(d['payload'] as String)),
        );
        if (b.id != d['id']) {
          throw const FormatException('Invalid original idea draft identity');
        }
        if (d['base'] != null) {
          IdeaBoard.fromJson(backupMap(jsonDecode(d['base'] as String)));
        }
      }
    } else if (name.startsWith('idea_op_base:$source:')) {
      final opId = name.substring('idea_op_base:$source:'.length);
      ideaId(opId);
      IdeaBoard.fromJson(backupMap(jsonDecode(row['value'] as String)));
    } else if (name.startsWith('idea_rebased_op:$source:')) {
      final old = backupMap(jsonDecode(row['value'] as String));
      ideaKeys(old, {
        'op_id',
        'scope_id',
        'request',
        'wire_version',
        if (old.containsKey('base')) 'base',
      });
      if (name != 'idea_rebased_op:$source:${old['op_id']}' ||
          !const [5, 6].contains(old['wire_version']) ||
          !allowedWorkspaces.contains('shared:$source:${old['scope_id']}')) {
        throw const FormatException('Invalid idea operation source');
      }
      final request = backupMap(jsonDecode(old['request'] as String));
      ideaKeys(request, {
        'opId',
        'recordId',
        'type',
        'expectedRevision',
        'deleted',
        'payload',
      });
      ideaId(request['opId'] as String);
      ideaId(request['recordId'] as String);
      if (request['opId'] != old['op_id'] ||
          request['type'] != 'idea' ||
          request['expectedRevision'] is! int ||
          (request['expectedRevision'] as int) < 0 ||
          request['deleted'] is! bool ||
          (request['deleted'] == true) != (request['payload'] == null)) {
        throw const FormatException('Invalid idea operation envelope');
      }
      if (request['payload'] != null) {
        final b = IdeaBoard.fromJson(backupMap(request['payload']));
        if (b.id != request['recordId']) {
          throw const FormatException('Invalid idea operation identity');
        }
      }
      if (old['base'] != null) {
        IdeaBoard.fromJson(backupMap(jsonDecode(old['base'] as String)));
      }
    } else {
      throw const FormatException('Invalid idea operation history');
    }
  }
  for (final r in doc['ideaDrafts'] as List) {
    final v = backupMap(r);
    ideaKeys(v, {'workspace', 'id', 'payload', 'base'});
    if (!allowedWorkspaces.contains(v['workspace'])) {
      throw const FormatException('Invalid idea draft workspace');
    }
    final b = IdeaBoard.fromJson(backupMap(jsonDecode(v['payload'] as String)));
    if (b.id != v['id']) throw const FormatException('Invalid idea draft');
    if (v['base'] != null) {
      IdeaBoard.fromJson(backupMap(jsonDecode(v['base'] as String)));
    }
  }
}

/// New table drafts never enter ordinary record sync or confer server access.
/// Older backups contain no spreadsheet section and remain valid unchanged.
List<Map<String, dynamic>> backupTableDrafts(Map<String, dynamic> doc) =>
    (doc['version'] as int) >= 7
    ? (doc['tableDrafts'] as List).cast<Map<String, dynamic>>()
    : const [];

void validateBackupTableDrafts(Map<String, dynamic> doc) {
  final raw = doc['tableDrafts'];
  if (raw is! List || raw.length > 10000) {
    throw const FormatException('Invalid spreadsheet drafts');
  }
  final source = doc['source'] as Map?;
  final scopes = {for (final row in backupRows(doc, 'scopes')) row['id']};
  final ids = <String>{};
  for (final row in backupTableDrafts(doc)) {
    ideaKeys(row, {'partition', 'scopeId', 'tableId', 'draft'});
    if (source == null ||
        row['partition'] != source['partition'] ||
        !scopes.contains(row['scopeId']) ||
        !isSharedUuid(row['scopeId'] as String) ||
        !isSharedUuid(row['tableId'] as String) ||
        !ids.add('${row['scopeId']}:${row['tableId']}')) {
      throw const FormatException('Invalid spreadsheet draft identity');
    }
    final draft = backupMap(row['draft']);
    validateBackupTableDraft(draft);
    if (draft['tableId'] != row['tableId']) {
      throw const FormatException('Spreadsheet draft target mismatch');
    }
  }
}

void validateBackupTableDraft(Map<String, dynamic> draft) {
  ideaKeys(draft, {'tableId', 'baseRevision', 'title', 'cells', 'updatedAt'});
  final parsed = SpreadsheetDraft.fromJson(draft);
  // Preserve a not-yet-saved title even if its UTF-8 form exceeds the server's
  // current title limit. Recovery does not publish it or bypass save validation.
  if (!isSharedUuid(parsed.tableId) ||
      parsed.baseRevision < 0 ||
      parsed.updatedAt < 0 ||
      utf8.encode(parsed.title).length > 800 ||
      parsed.cells.length > 10000 ||
      utf8.encode(jsonEncode(parsed.cells)).length > 524288) {
    throw const FormatException('Invalid spreadsheet draft');
  }
  for (final cell in parsed.cells.entries) {
    final address = SpreadsheetAddress.parse(cell.key);
    if (address == null ||
        address.label != cell.key ||
        utf8.encode(cell.value).length > 4096) {
      throw const FormatException('Invalid spreadsheet draft cell');
    }
  }
}

/// Order-independent comparison preserves an existing different local draft.
String backupTableDraftCanonical(Map<String, dynamic> draft) {
  validateBackupTableDraft(draft);
  final parsed = SpreadsheetDraft.fromJson(draft);
  final keys = parsed.cells.keys.toList()..sort();
  return jsonEncode({
    ...parsed.toJson(),
    'cells': {for (final key in keys) key: parsed.cells[key]},
  });
}
