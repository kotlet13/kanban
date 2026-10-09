part of 'collaboration_repository.dart';

/// Resume original immutable operations only under their source account and
/// freshly checked ACL. Canonical backup rows never become server authority.
extension CollaborationBackupActions on CollaborationRepository {
  Future<void> resumePortableBackup(Map<String, dynamic> doc) async {
    validateBackupDocument(doc);
    final session = _requireSession(),
        epoch = _epoch,
        p = session.profile.partition;
    if ((await database.rows('SELECT value FROM local_meta WHERE name=?', [
      'deleted_account:$p',
    ])).isNotEmpty) {
      throw const CollaborationException('account_deleted');
    }
    final source = doc['source'];
    if (source is! Map ||
        source['partition'] != p ||
        source['serverId'] != session.profile.serverId ||
        source['accountId'] != session.profile.accountId) {
      throw const CollaborationException('backup_wrong_account');
    }
    await _negotiate(session, epoch);
    await syncNow();
    _checkEpoch(epoch);
    if (_lastError != null) throw _lastError!;
    final restoredPrivate = backupMap(doc['privateData']);
    final policies = <String, SharedFinancePolicy>{},
        generations = <String, int>{};
    final writableScopeIds = {
      for (final row in [
        ...backupRows(doc, 'outbox'),
        ...backupRows(doc, 'finance_outbox'),
      ])
        row['scope_id'],
      for (final row in backupRows(
        doc,
        'commands',
      ).where((r) => (r['operation'] as String).startsWith('reminders.')))
        backupMap(jsonDecode(row['params'] as String))['scopeId'],
    };
    final scopeIds = backupRows(
      doc,
      'scopes',
    ).map((r) => r['id'] as String).toSet();
    for (final scope in scopeIds) {
      final rows = await database.rows(
        'SELECT data FROM scopes WHERE partition=? AND id=?',
        [p, scope],
      );
      if (rows.isEmpty ||
          SharedScope.fromJson(
            CollaborationRepository._map(rows.single['data']),
          ).revoked) {
        throw const CollaborationException('permission_revoked');
      }
      if (backupRows(
        doc,
        'finance_outbox',
      ).any((r) => r['scope_id'] == scope)) {
        policies[scope] = await _fetchFinancePolicy(session, epoch, scope);
        if (!policies[scope]!.canWrite) {
          throw const CollaborationException('finance_forbidden');
        }
        generations[scope] = await _financeAccessGeneration(p, scope);
      }
    }
    if (restoredPrivate['binding'] != null &&
        !(await _privateSyncState(session.profile)).enabled) {
      await _attachPrivateRecovery(
        backupMap(restoredPrivate['binding']),
        restoredPrivate['maps'] as List,
      );
      _checkEpoch(epoch);
    }
    if (_syncing) await _syncDone?.future;
    _checkEpoch(epoch);
    _syncing = true;
    final done = _syncDone = Completer<void>();
    var leased = false;
    try {
      leased = await _claimLease(p);
      if (!leased) throw const CollaborationException('sync_busy');
      await database.transaction(() async {
        _checkEpoch(epoch);
        await _validLease(p);
        for (final scope in scopeIds) {
          final rows = await database.rows(
            'SELECT data,blocked FROM scopes WHERE partition=? AND id=?',
            [p, scope],
          );
          if (rows.isEmpty ||
              (writableScopeIds.contains(scope) &&
                  rows.single['blocked'] == 1) ||
              (writableScopeIds.contains(scope) &&
                  !SharedScope.fromJson(
                    CollaborationRepository._map(rows.single['data']),
                  ).canEdit)) {
            throw const CollaborationException('permission_revoked');
          }
          if (generations.containsKey(scope) &&
              (generations[scope] != await _financeAccessGeneration(p, scope) ||
                  !(await _cachedFinancePolicy(p, scope)).canWrite)) {
            throw const CollaborationException('finance_forbidden');
          }
        }
        for (final queueTable in ['outbox', 'finance_outbox']) {
          final recordTable = queueTable == 'outbox'
              ? 'records'
              : 'finance_records';
          for (final op in backupRows(doc, queueTable)) {
            final duplicate = await database.rows(
              'SELECT request FROM $queueTable WHERE op_id=?',
              [op['op_id']],
            );
            if (duplicate.isNotEmpty) {
              if (duplicate.single['request'] != op['request']) {
                throw const CollaborationException('backup_conflict');
              }
              continue;
            }
            final scope = op['scope_id'] as String,
                recordId = op['record_id'] as String;
            final ownPending = await database.rows(
              'SELECT request FROM $queueTable WHERE partition=? AND scope_id=? AND record_id=?',
              [p, scope, recordId],
            );
            final originalOps = backupRows(doc, queueTable)
                .where(
                  (r) => r['scope_id'] == scope && r['record_id'] == recordId,
                )
                .map((r) => r['request'])
                .toSet();
            if (ownPending.any((r) => !originalOps.contains(r['request']))) {
              throw const CollaborationException('backup_conflict');
            }
            final candidate = backupRows(
              doc,
              recordTable,
            ).singleWhere((r) => r['scope_id'] == scope && r['id'] == recordId);
            final current = await database.rows(
              'SELECT * FROM $recordTable WHERE partition=? AND scope_id=? AND id=?',
              [p, scope, recordId],
            );
            if (current.isNotEmpty &&
                current.single['type'] != candidate['type']) {
              throw const CollaborationException('backup_conflict');
            }
            // Base is the newest authorized local canonical, never imported ACL or cursor.
            final remote = current.firstOrNull?['remote'];
            final serverRevision = current.firstOrNull?['server_revision'] ?? 0;
            await database.execute(
              'INSERT INTO $recordTable(partition,scope_id,id,type,local_revision,server_revision,payload,deleted,remote) VALUES(?,?,?,?,?,?,?,?,?) ON CONFLICT(partition,scope_id,id) DO UPDATE SET payload=excluded.payload,deleted=excluded.deleted,local_revision=excluded.local_revision',
              [
                p,
                scope,
                recordId,
                candidate['type'],
                (current.firstOrNull?['local_revision'] as int? ?? 0) + 1,
                serverRevision,
                candidate['payload'],
                candidate['deleted'],
                remote,
              ],
            );
            if (queueTable == 'outbox') {
              await database.execute(
                'INSERT INTO outbox(op_id,partition,scope_id,record_id,request,state,wire_version) VALUES(?,?,?,?,?,?,?)',
                [
                  op['op_id'],
                  p,
                  scope,
                  recordId,
                  op['request'],
                  op['state'],
                  op['wire_version'],
                ],
              );
            } else {
              await database.execute(
                'INSERT INTO finance_outbox(op_id,partition,scope_id,record_id,request,state,wire_version) VALUES(?,?,?,?,?,?,?)',
                [
                  op['op_id'],
                  p,
                  scope,
                  recordId,
                  op['request'],
                  op['state'],
                  op['wire_version'] ?? 1,
                ],
              );
            }
          }
        }
        for (final pair in (doc['operationPairs'] as List? ?? const [])) {
          final opPair = Map<String, dynamic>.from(pair as Map);
          await database.execute(
            'INSERT INTO local_meta(name,value) VALUES(?,?) ON CONFLICT(name) DO UPDATE SET value=excluded.value',
            [
              'task_cost_pair:$p:${opPair['genericOpId']}',
              opPair['financeOpId'],
            ],
          );
        }
        for (final raw in (doc['financeInboxReads'] as List? ?? const [])) {
          final receipt = backupMap(raw), name = receipt['name'] as String;
          final prefix = 'finance_inbox_read:$p:';
          if (!name.startsWith(prefix)) continue;
          final scope = name.substring(prefix.length).split(':').first;
          if (!isSharedUuid(scope) ||
              !(await _cachedFinancePolicy(p, scope)).canRead) {
            continue;
          }
          final projection = await database.rows(
            'SELECT finance_complete FROM scopes WHERE partition=? AND id=?',
            [p, scope],
          );
          if (projection.isEmpty ||
              projection.single['finance_complete'] != 1) {
            continue;
          }
          _checkEpoch(epoch);
          await database.execute(
            'INSERT INTO local_meta(name,value) VALUES(?,?) ON CONFLICT(name) DO UPDATE SET value=excluded.value',
            [name, receipt['value']],
          );
        }
        for (final pair in [
          ('conflicts', 'records'),
          ('finance_conflicts', 'finance_records'),
        ]) {
          for (final c in backupRows(doc, pair.$1)) {
            final exists = await database.rows(
              'SELECT id FROM ${pair.$2} WHERE partition=? AND scope_id=? AND id=?',
              [p, c['scope_id'], c['record_id']],
            );
            if (exists.isEmpty) continue;
            await database.execute(
              'INSERT INTO ${pair.$1}(id,partition,scope_id,record_id,type,reason,remote) VALUES(?,?,?,?,?,?,?) ON CONFLICT(id) DO NOTHING',
              [
                c['id'],
                p,
                c['scope_id'],
                c['record_id'],
                c['type'],
                c['reason'],
                (await database.rows(
                  'SELECT remote FROM ${pair.$2} WHERE partition=? AND scope_id=? AND id=?',
                  [p, c['scope_id'], c['record_id']],
                )).single['remote'],
              ],
            );
          }
        }
        if (restoredPrivate['binding'] != null) {
          final w = 'private:$p';
          await database.execute(
            'UPDATE personal_workspaces SET enabled=1,paused=0 WHERE id=?',
            [w],
          );
          for (final value in restoredPrivate['maps'] as List) {
            final m = backupMap(value);
            final old = await database.rows(
              'SELECT remote_id,type FROM personal_record_map WHERE workspace=? AND id=?',
              [w, m['id']],
            );
            if (old.isNotEmpty &&
                (old.single['remote_id'] != m['remote_id'] ||
                    old.single['type'] != m['type'])) {
              throw const CollaborationException('backup_conflict');
            }
            await database.execute(
              'INSERT INTO personal_record_map(workspace,id,remote_id,type) VALUES(?,?,?,?) ON CONFLICT(workspace,id) DO NOTHING',
              [w, m['id'], m['remote_id'], m['type']],
            );
          }
          for (final value in restoredPrivate['reminders'] as List) {
            final r = backupMap(value);
            await database.execute(
              "INSERT INTO personal_records(workspace,id,type,payload) VALUES(?,?,'reminder',?) ON CONFLICT(workspace,id) DO NOTHING",
              [w, r['id'], r['payload']],
            );
          }
        }
        // Read/reminder commands preserve request IDs and CAS, never include credentials.
        for (final command in backupRows(doc, 'commands')) {
          final old = await database.rows(
            'SELECT params FROM commands WHERE id=?',
            [command['id']],
          );
          if (old.isNotEmpty) {
            if (old.single['params'] != command['params']) {
              throw const CollaborationException('backup_conflict');
            }
            continue;
          }
          await database.execute(
            'INSERT INTO commands(id,partition,operation,params,entity_key,state) VALUES(?,?,?,?,?,?)',
            [
              command['id'],
              p,
              command['operation'],
              command['params'],
              command['entity_key'],
              command['state'],
            ],
          );
        }
        await database.touchPersonal();
        _checkEpoch(epoch);
      });
    } finally {
      if (leased) {
        await database.execute(
          'DELETE FROM sync_leases WHERE partition=? AND owner=?',
          [p, _leaseOwner],
        );
      }
      _syncing = false;
      done.complete();
    }
    await refreshLocal();
    await syncNow();
  }
}

extension CollaborationPrivateRecoveryAttachment on CollaborationRepository {
  Future<void> _attachPrivateRecovery(
    Map<String, dynamic> original,
    List maps,
  ) async {
    final session = _requireSession(),
        epoch = _epoch,
        p = session.profile.partition;
    if (_syncing) await _syncDone?.future;
    _checkEpoch(epoch);
    _syncing = true;
    final done = _syncDone = Completer<void>();
    var leased = false;
    try {
      leased = await _claimLease(p);
      if (!leased) throw const CollaborationException('sync_busy');
      final result = await _callSession(session, epoch, 'personal.ensure', {});
      final scope = SharedScope.fromJson(backupMap(result['scope']));
      if (scope.kind != SharedScopeKind.personal ||
          scope.id != original['scope_id'] ||
          scope.role != SharedRole.owner) {
        throw const CollaborationException('backup_wrong_account');
      }
      await database.transaction(() async {
        _checkEpoch(epoch);
        await _validLease(p);
        await _upsertScope(p, scope);
        await database.execute(
          'INSERT INTO personal_workspaces(id,partition,scope_id,enabled) VALUES(?,?,?,0) ON CONFLICT(id) DO NOTHING',
          ['private:$p', p, scope.id],
        );
        for (final value in maps) {
          final m = backupMap(value);
          await database.execute(
            'INSERT INTO personal_record_map(workspace,id,remote_id,type) VALUES(?,?,?,?) ON CONFLICT(workspace,id) DO NOTHING',
            ['private:$p', m['id'], m['remote_id'], m['type']],
          );
        }
      });
      var more = true;
      while (more) {
        await _renewLease(p);
        final cursor = (await database.rows(
          'SELECT cursor FROM scopes WHERE partition=? AND id=?',
          [p, scope.id],
        )).single['cursor'];
        final page = await _callSession(
          session,
          epoch,
          _recordContractVersion >= 4
              ? 'sync4.pull'
              : _recordContractVersion >= 3
              ? 'sync3.pull'
              : 'sync2.pull',
          {'scopeId': scope.id, 'cursor': cursor, 'limit': 100},
        );
        final next = readInt(page, 'cursor');
        more = readBool(page, 'hasMore');
        if (next < (cursor as int) || (more && next == cursor)) {
          throw const CollaborationException('invalid_response');
        }
        await database.transaction(() async {
          _checkEpoch(epoch);
          await _validLease(p);
          for (final row in page['records'] as List) {
            await _applyRemote(p, scope.id, _canonical(row, personal: true));
          }
          await database.execute(
            'UPDATE scopes SET cursor=? WHERE partition=? AND id=?',
            [next, p, scope.id],
          );
        });
      }
      final policy = await _fetchFinancePolicy(
        session,
        epoch,
        scope.id,
        syncLease: true,
      );
      if (!policy.canRead) {
        throw const CollaborationException('finance_forbidden');
      }
      await _pullFinanceScope(session, epoch, scope.id);
      await database.transaction(() async {
        _checkEpoch(epoch);
        await _validLease(p);
        // Remain staged until the caller validates every scope and commits the recovery.
        await database.touchPersonal();
      });
    } finally {
      if (leased) {
        await database.execute(
          'DELETE FROM sync_leases WHERE partition=? AND owner=?',
          [p, _leaseOwner],
        );
      }
      _syncing = false;
      done.complete();
    }
    database.personalChanged();
    await refreshLocal();
  }
}
