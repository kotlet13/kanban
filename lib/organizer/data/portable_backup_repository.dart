import 'dart:convert';
import 'dart:typed_data';
import '../domain/collaboration_models.dart';
import '../domain/organizer_models.dart';
import 'collaboration_database.dart';
import 'collaboration_repository.dart';
import 'organizer_storage.dart';
import 'portable_backup_crypto.dart';
import 'portable_backup_document.dart';
import 'sqlite_organizer_storage.dart';

abstract interface class BackupUiPreferencesStore {
  Future<Map<String, Object?>> read();
  Future<void> restore(Map<String, Object?> values);
}

class MemoryBackupUiPreferencesStore implements BackupUiPreferencesStore {
  Map<String, Object?> values = {};
  @override
  Future<Map<String, Object?>> read() async => Map.of(values);
  @override
  Future<void> restore(Map<String, Object?> values) async {
    this.values = Map.of(values);
  }
}

/// SQL restore commits data and its encrypted recovery package together. Remote
/// candidates stay quarantined until an explicit authenticated, authorized resume.
class PortableBackupRepository {
  PortableBackupRepository(
    this.database,
    this.storage,
    this.uiPreferences, {
    this.collaboration,
    PortableBackupCrypto? crypto,
  }) : crypto = crypto ?? PortableBackupCrypto();
  final CollaborationDatabase database;
  final SqliteOrganizerStorage storage;
  final BackupUiPreferencesStore uiPreferences;
  final CollaborationRepository? Function()? collaboration;
  final PortableBackupCrypto crypto;
  final _prepared = <String, String>{};
  static const exclusions = [
    'bearer tokens',
    'passwords and verification codes',
    'FCM tokens and opt-in',
    'OS permissions and scheduled delivery IDs',
    'server attachments and complete server database',
    'other signed-out accounts',
  ];
  Future<String> _rightsStamp() async {
    final profile = database.personalProfile;
    final parts = <Object?>[
      database.personalIdentityGeneration,
      profile?.partition,
    ];
    if (profile != null) {
      for (final row in await database.rows(
        'SELECT id,data,blocked,finance_policy,finance_blocked FROM scopes WHERE partition=? ORDER BY id',
        [profile.partition],
      )) {
        final scope = SharedScope.fromJson(
          backupMap(jsonDecode(row['data'] as String)),
        );
        final policy = row['finance_policy'] == null
            ? const SharedFinancePolicy()
            : SharedFinancePolicy.fromJson(
                backupMap(jsonDecode(row['finance_policy'] as String)),
              );
        parts.add([
          scope.id,
          scope.role.name,
          scope.revoked,
          row['blocked'],
          policy.canRead ? policy.toJson() : null,
          row['finance_blocked'],
        ]);
        if (policy.canRead) {
          parts.add(
            await database.rows('SELECT value FROM local_meta WHERE name=?', [
              'finance_access_generation:${profile.partition}:${scope.id}',
            ]),
          );
        }
      }
    }
    return jsonEncode(parts);
  }

  Future<void> validatePreparedExport(String backupId) async {
    if (_prepared[backupId] == null ||
        _prepared[backupId] != await _rightsStamp()) {
      throw const CollaborationException('backup_stale');
    }
  }

  Future<Uint8List> exportEncryptedBackup(String password) async {
    await storage.initialize();
    final preferences = await uiPreferences.read();
    validateBackupUiPreferences(Map<String, dynamic>.from(preferences));
    late String stamp;
    final doc = await database.transaction(() async {
      stamp = await _rightsStamp();
      final profile = database.personalProfile;
      final tables = <String, dynamic>{
        for (final table in backupTables.keys) table: <Map<String, dynamic>>[],
      };
      final completeness = <String>[];
      if (profile != null) {
        final scopeRows = await database.rows(
          'SELECT * FROM scopes WHERE partition=?',
          [profile.partition],
        );
        final allowed = <String>{}, financial = <String>{};
        for (final row in scopeRows) {
          final scope = SharedScope.fromJson(
            backupMap(jsonDecode(row['data'] as String)),
          );
          if (scope.revoked || row['blocked'] == 1) continue;
          allowed.add(scope.id);
          final policy = row['finance_policy'] == null
              ? const SharedFinancePolicy()
              : SharedFinancePolicy.fromJson(
                  backupMap(jsonDecode(row['finance_policy'] as String)),
                );
          if (policy.canRead && row['finance_blocked'] != 1) {
            financial.add(scope.id);
          }
          if (row['finance_complete'] != 1 || row['cursor'] == 0) {
            completeness.add(scope.id);
          }
          // Cached policy is descriptive only; importing never grants access.
          (tables['scopes'] as List).add({
            for (final col in backupTables['scopes']!) col: row[col],
          });
        }
        for (final table in backupTables.keys.where((t) => t != 'scopes')) {
          for (final row in await database.rows(
            'SELECT * FROM $table WHERE partition=?',
            [profile.partition],
          )) {
            final scopeId = row['scope_id'];
            if (scopeId != null &&
                scopeId != '' &&
                !allowed.contains(scopeId)) {
              continue;
            }
            if (table.startsWith('finance_') && !financial.contains(scopeId)) {
              continue;
            }
            if (const ['inbox', 'scheduled_reminders'].contains(table)) {
              final data = backupMap(jsonDecode(row['data'] as String));
              final scope = data['scopeId'];
              if (scope != null && !allowed.contains(scope)) continue;
              if ((data['category'] == 'finance' ||
                      (data['targetType'] as String? ?? '').contains(
                        'Finance',
                      ) ||
                      (data['targetType'] as String? ?? '').startsWith(
                        'finance',
                      )) &&
                  !financial.contains(scope)) {
                continue;
              }
            }
            if (table == 'commands') {
              final params = backupMap(jsonDecode(row['params'] as String));
              if (params['scopeId'] != null &&
                  !allowed.contains(params['scopeId'])) {
                continue;
              }
              if (params['targetType'] is String &&
                  (params['targetType'] as String).contains('Finance') &&
                  !financial.contains(params['scopeId'])) {
                continue;
              }
            }
            (tables[table] as List).add({
              for (final col in backupTables[table]!) col: row[col],
            });
          }
        }
      }
      final local = await storage.localSnapshot();
      final revision = (await storage.read()).revision;
      final binding = await storage.activeBinding();
      final privateData = <String, dynamic>{
        'binding': binding == null
            ? null
            : {
                'id': binding['id'],
                'partition': binding['partition'],
                'scope_id': binding['scope_id'],
                'paused': binding['paused'],
              },
        'maps': binding == null
            ? []
            : await database.rows(
                'SELECT * FROM personal_record_map WHERE workspace=?',
                [binding['id']],
              ),
        'reminders': binding == null
            ? []
            : await database.rows(
                "SELECT * FROM personal_records WHERE workspace=? AND type='reminder'",
                [binding['id']],
              ),
      };
      return <String, dynamic>{
        'format': 'vsakdan-portable-data',
        'version': 1,
        'databaseVersion': 4,
        'id': newSharedId(),
        'createdAt': DateTime.now().toUtc().toIso8601String(),
        'source': profile == null
            ? null
            : {
                'partition': profile.partition,
                'serverId': profile.serverId,
                'accountId': profile.accountId,
                'serverUrl': profile.serverUrl,
                'username': profile.username,
                'displayName': profile.displayName,
              },
        'privateData': privateData,
        'personal': OrganizerBackupCodec.encode(
          local.copyWith(revision: revision),
        ),
        'tables': tables,
        'uiPreferences': preferences,
        'completeness': completeness,
        'exclusions': exclusions,
      };
    });
    validateBackupDocument(doc);
    final bytes = await crypto.encrypt(doc, password);
    if (stamp != await _rightsStamp()) {
      throw const CollaborationException('backup_stale');
    }
    _prepared[doc['id'] as String] = stamp;
    return bytes;
  }

  Future<Map<String, dynamic>> _decode(List<int> bytes, String password) async {
    final doc = await crypto.decrypt(bytes, password);
    validateBackupDocument(doc);
    return doc;
  }

  BackupPreview _preview(Map<String, dynamic> doc) {
    final local = backupPersonal(doc),
        source = doc['source'] == null ? null : backupMap(doc['source']);
    final scopes = backupRows(doc, 'scopes');
    return BackupPreview(
      backupId: doc['id'] as String,
      createdAt: DateTime.parse(doc['createdAt'] as String),
      personalRevision: local.revision,
      personalCounts: personalCounts(local),
      scopeCount: scopes.length,
      pendingCount:
          backupRows(doc, 'outbox').length +
          backupRows(doc, 'finance_outbox').length +
          backupRows(doc, 'commands').length,
      hasRemoteRecovery: scopes.isNotEmpty,
      sourceAccount: source?['displayName'] as String?,
      sourceServer: source?['serverUrl'] as String?,
      incompleteScopes: (doc['completeness'] as List).cast<String>(),
      exclusions: (doc['exclusions'] as List).cast<String>(),
    );
  }

  Future<BackupPreview> inspectEncryptedBackup(
    List<int> bytes,
    String password,
  ) async => _preview(await _decode(bytes, password));
  Future<BackupRestoreResult> restoreEncryptedBackup(
    List<int> bytes,
    String password, {
    required BackupRestoreMode mode,
    required int expectedPersonalRevision,
  }) async {
    final stamp = await _rightsStamp(),
        doc = await _decode(bytes, password),
        imported = backupPersonal(doc);
    final id = doc['id'] as String;
    await database.transaction(() async {
      if (stamp != await _rightsStamp() ||
          (await storage.read()).revision != expectedPersonalRevision) {
        throw const CollaborationException('backup_stale');
      }
      final current = await storage.localSnapshot();
      OrganizerSnapshot candidate;
      try {
        candidate = mode == BackupRestoreMode.replace
            ? imported
            : mergePersonalSnapshots(
                current,
                imported,
                revision: current.revision,
              );
      } on Object {
        throw const CollaborationException('backup_conflict');
      }
      final active = await storage.activeBinding();
      if (active != null) {
        mergePersonalSnapshots(
          candidate,
          await storage.privateSnapshot(active),
          revision: candidate.revision,
        );
      }
      // Restore anonymous data directly. The active B profile must never enqueue A.
      await database.execute(
        "DELETE FROM personal_records WHERE workspace='local'",
      );
      for (final row in snapshotRows(candidate)) {
        await database.execute(
          'INSERT INTO personal_records(workspace,id,type,payload) VALUES(?,?,?,?)',
          ['local', row.id, row.type, jsonEncode(row.json)],
        );
      }
      await database.execute(
        'INSERT INTO restored_backups(id,created_at,source_partition,data) VALUES(?,?,?,?) ON CONFLICT(id) DO UPDATE SET data=excluded.data',
        [
          id,
          doc['createdAt'],
          doc['source'] == null ? null : backupMap(doc['source'])['partition'],
          jsonEncode({
            'preview': _previewJson(_preview(doc)),
            'encrypted': base64Encode(bytes),
          }),
        ],
      );
      await database.execute(
        "INSERT INTO local_meta(name,value) VALUES('backup_ui_preferences_pending',?) ON CONFLICT(name) DO UPDATE SET value=excluded.value",
        [jsonEncode(doc['uiPreferences'])],
      );
      await database.touchPersonal();
    });
    database.personalChanged();
    await applyPendingUiPreferences();
    return BackupRestoreResult(
      backupId: id,
      personalRecordCount: imported.recordIds.length,
      hasRemoteRecovery: backupRows(doc, 'scopes').isNotEmpty,
    );
  }

  Future<void> applyPendingUiPreferences() async {
    final rows = await database.rows(
      "SELECT value FROM local_meta WHERE name='backup_ui_preferences_pending'",
    );
    if (rows.isEmpty) return;
    final text = rows.single['value'] as String;
    await uiPreferences.restore(backupMap(jsonDecode(text)));
    await database.execute(
      "DELETE FROM local_meta WHERE name='backup_ui_preferences_pending' AND value=?",
      [text],
    );
  }

  Map<String, dynamic> _previewJson(BackupPreview p) => {
    'backupId': p.backupId,
    'createdAt': p.createdAt.toIso8601String(),
    'personalRevision': p.personalRevision,
    'personalCounts': p.personalCounts,
    'scopeCount': p.scopeCount,
    'pendingCount': p.pendingCount,
    'hasRemoteRecovery': p.hasRemoteRecovery,
    'sourceAccount': p.sourceAccount,
    'sourceServer': p.sourceServer,
    'incompleteScopes': p.incompleteScopes,
    'exclusions': p.exclusions,
  };
  Future<List<BackupPreview>> listRestoredBackups() async {
    final rows = await database.rows(
      'SELECT data FROM restored_backups ORDER BY created_at DESC',
    );
    return rows.map((r) {
      final p = backupMap(
        backupMap(jsonDecode(r['data'] as String))['preview'],
      );
      return BackupPreview(
        backupId: p['backupId'] as String,
        createdAt: DateTime.parse(p['createdAt'] as String),
        personalRevision: p['personalRevision'] as int,
        personalCounts: Map<String, int>.from(p['personalCounts'] as Map),
        scopeCount: p['scopeCount'] as int,
        pendingCount: p['pendingCount'] as int,
        hasRemoteRecovery: p['hasRemoteRecovery'] as bool,
        sourceAccount: p['sourceAccount'] as String?,
        sourceServer: p['sourceServer'] as String?,
        incompleteScopes: (p['incompleteScopes'] as List).cast<String>(),
        exclusions: (p['exclusions'] as List).cast<String>(),
      );
    }).toList();
  }

  Future<Map<String, dynamic>> _restored(String id, String password) async {
    final rows = await database.rows(
      'SELECT data FROM restored_backups WHERE id=?',
      [id],
    );
    if (rows.isEmpty) throw const CollaborationException('backup_missing');
    return _decode(
      base64Decode(
        backupMap(jsonDecode(rows.single['data'] as String))['encrypted']
            as String,
      ),
      password,
    );
  }

  Future<bool> _knownFinanceDenied(String partition, String scope) async {
    final rows = await database.rows(
      'SELECT data,finance_policy,finance_blocked FROM scopes WHERE partition=? AND id=?',
      [partition, scope],
    );
    if (rows.isEmpty) return true;
    final row = rows.single;
    return row['finance_blocked'] == 1 ||
        SharedScope.fromJson(
          backupMap(jsonDecode(row['data'] as String)),
        ).revoked ||
        row['finance_policy'] == null ||
        !SharedFinancePolicy.fromJson(
          backupMap(jsonDecode(row['finance_policy'] as String)),
        ).canRead;
  }

  Future<BackupRecoveryReview> reviewRestoredWork(
    String id,
    String password,
  ) async {
    final stamp = await _rightsStamp();
    final doc = await _restored(id, password),
        source = doc['source'] == null ? null : backupMap(doc['source']);
    final scopes = {
      for (final s in backupRows(doc, 'scopes'))
        s['id']: SharedScope.fromJson(
          backupMap(jsonDecode(s['data'] as String)),
        ),
    };
    final items = <BackupRecoveryItem>[];
    for (final table in ['records', 'finance_records']) {
      for (final row in backupRows(doc, table)) {
        if (table == 'finance_records' &&
            (database.personalProfile?.partition != row['partition'] ||
                await _knownFinanceDenied(
                  row['partition'] as String,
                  row['scope_id'] as String,
                ))) {
          continue;
        }
        final payload = row['payload'] == null
            ? <String, dynamic>{}
            : backupMap(jsonDecode(row['payload'] as String));
        final queue =
            backupRows(doc, table == 'records' ? 'outbox' : 'finance_outbox')
                .where(
                  (q) =>
                      q['record_id'] == row['id'] &&
                      q['scope_id'] == row['scope_id'],
                )
                .toList();
        items.add(
          BackupRecoveryItem(
            scopeId: row['scope_id'] as String,
            scopeName: scopes[row['scope_id']]!.name,
            recordId: row['id'] as String,
            recordType: row['type'] as String,
            title: (payload['title'] ?? payload['name'] ?? '') as String,
            state: queue.isEmpty ? 'cached' : queue.last['state'] as String,
            isFinancial: table == 'finance_records',
          ),
        );
      }
    }
    if (stamp != await _rightsStamp()) {
      throw const CollaborationException('backup_stale');
    }
    return BackupRecoveryReview(
      backupId: id,
      canResume: database.personalProfile?.partition == source?['partition'],
      sourceAccount: source?['displayName'] as String?,
      sourceServer: source?['serverUrl'] as String?,
      items: items,
    );
  }

  Future<void> resumeRestoredWork(String id, {required String password}) async {
    final repo = collaboration?.call();
    if (repo == null) throw const CollaborationException('auth_required');
    final stamp = await _rightsStamp(), doc = await _restored(id, password);
    if (stamp != await _rightsStamp()) {
      throw const CollaborationException('backup_stale');
    }
    await repo.resumePortableBackup(doc);
    database.personalChanged();
  }
}
