part of 'collaboration_repository.dart';

/// Leased idempotent delivery, incremental pulls, conflicts and recovery export.
extension CollaborationSyncActions on CollaborationRepository {
  Future<bool> _claimLease(String partition) => database.transaction(() async {
    final now = clock().millisecondsSinceEpoch;
    final leases = await database.rows(
      'SELECT * FROM sync_leases WHERE partition=?',
      [partition],
    );
    if (leases.isNotEmpty &&
        leases.first['owner'] != _leaseOwner &&
        (leases.first['expires_at'] as int) > now) {
      return false;
    }
    await database.execute(
      'INSERT INTO sync_leases(partition,owner,expires_at) VALUES(?,?,?) ON CONFLICT(partition) DO UPDATE SET owner=excluded.owner,expires_at=excluded.expires_at',
      [partition, _leaseOwner, now + 60000],
    );
    return true;
  });
  Future<void> _validLease(String partition) async {
    final lease = await database.rows(
      'SELECT owner,expires_at FROM sync_leases WHERE partition=?',
      [partition],
    );
    if (lease.isEmpty ||
        lease.first['owner'] != _leaseOwner ||
        (lease.first['expires_at'] as int) <= clock().millisecondsSinceEpoch) {
      throw const CollaborationException('sync_lease_lost');
    }
  }

  Future<void> _renewLease(String partition) => database.transaction(() async {
    await _validLease(partition);
    await database.execute(
      'UPDATE sync_leases SET expires_at=? WHERE partition=? AND owner=?',
      [clock().millisecondsSinceEpoch + 60000, partition, _leaseOwner],
    );
  });

  Future<void> _prepareCryptoProjectionCursors(
    DeviceSession session,
    int epoch,
    List<SharedScope> scopes,
  ) async {
    final router = cryptoRouter;
    if (router is! CryptoProjectionCursorTransition) return;
    final transition = router as CryptoProjectionCursorTransition;
    final partition = session.profile.partition;
    for (final scope in scopes) {
      // Ordinary cursors and crypto_received.sequence have separate namespaces.
      // Keep records and immutable pending work while replaying the verified
      // encrypted projection once. The two domain checkpoints commit together.
      final keys = [
        for (final domain in const ['content', 'finance'])
          'crypto_projection_cursor_v1:$partition:${scope.id}:$domain',
      ];
      final prior = await database.rows(
        'SELECT name FROM local_meta WHERE name IN (?,?)',
        keys,
      );
      _checkEpoch(epoch);
      if (prior.length == keys.length) continue;
      final origin = await transition.verifyProjectionCursorOrigin(
        session: session,
        scopeId: scope.id,
      );
      _checkEpoch(epoch);
      if (origin == null) continue;
      await database.transaction(() async {
        _checkEpoch(epoch);
        await _validLease(partition);
        for (var index = 0; index < keys.length; index++) {
          final exists = await database.rows(
            'SELECT 1 FROM local_meta WHERE name=?',
            [keys[index]],
          );
          if (exists.isNotEmpty) continue;
          if (origin == CryptoProjectionCursorOrigin.legacyMigration) {
            await database.execute(
              index == 0
                  ? 'UPDATE scopes SET cursor=0 WHERE partition=? AND id=?'
                  : 'UPDATE scopes SET finance_cursor=0,finance_access_revision=0,finance_complete=0 WHERE partition=? AND id=?',
              [partition, scope.id],
            );
          }
          await database.execute(
            'INSERT INTO local_meta(name,value) VALUES(?,?)',
            [keys[index], origin.name],
          );
        }
        _checkEpoch(epoch);
      });
    }
  }

  Future<void> syncNow({bool resumePayments = true, bool manual = false}) {
    final session = _session, epoch = _epoch;
    if (session == null) {
      return _syncNow(resumePayments: resumePayments, manual: manual);
    }
    return CryptoCapabilityDiscovery.withSync(
      () => _syncNow(resumePayments: resumePayments, manual: manual),
      transport: transport,
      session: session,
      isCurrent: () =>
          !_closed &&
          _epoch == epoch &&
          identical(_session, session) &&
          _sessionInvalidReason == null,
    );
  }

  Future<void> _syncNow({
    required bool resumePayments,
    required bool manual,
  }) async {
    if (_syncing ||
        _session == null ||
        _closed ||
        (resumePayments &&
            (_fullSyncEpoch == _epoch || _fullAttemptEpoch == _epoch)) ||
        (!manual &&
            _automaticSyncRetryIdentity == backgroundSyncIdentity &&
            _automaticSyncRetryAt != null &&
            clock().toUtc().isBefore(_automaticSyncRetryAt!))) {
      return;
    }
    final completionIdentity = backgroundSyncIdentity!;
    final completionSequence = resumePayments ? ++_syncCompletionSequence : 0;
    if (resumePayments) {
      _syncStarts.add(
        CollaborationSyncStart(completionSequence, completionIdentity),
      );
    }
    _lastSyncAttemptAt = clock().toUtc();
    if (_sessionInvalidReason != null) {
      _lastError = CollaborationException(_sessionInvalidReason!);
      await refreshLocal();
      if (resumePayments && completionIdentity == backgroundSyncIdentity) {
        final work = await syncWork();
        if (!_closed &&
            completionIdentity == backgroundSyncIdentity &&
            completionSequence > (lastSyncCompletion?.sequence ?? 0)) {
          lastSyncCompletion = CollaborationSyncCompletion(
            sequence: completionSequence,
            identity: completionIdentity,
            at: clock().toUtc(),
            work: work,
            error: _lastError,
          );
          _syncCompletions.add(lastSyncCompletion!);
        }
      }
      return;
    }
    final session = _requireSession(),
        epoch = _epoch,
        partition = _session!.profile.partition;
    _syncing = true;
    _syncEpoch = epoch;
    if (resumePayments) {
      _fullSyncEpoch = epoch;
      _fullAttemptEpoch = epoch;
    }
    final done = _syncDone = Completer<void>();
    var leaseClaimed = false, completed = false;
    final previousFullSuccess = _lastSuccessfulSyncAt;
    try {
      _lastError = null;
      try {
        leaseClaimed = await _claimLease(partition);
        if (!leaseClaimed) return;
        _checkEpoch(epoch);
        await refreshLocal();
        await _negotiate(session, epoch);
        // Authentication preflight belongs to the sync transaction: a failed or
        // lost renewal must stop this attempt instead of being mistaken for a
        // terms endpoint outage and immediately retried by the next API read.
        await _renewDeviceSessionIfNeeded(session, epoch);
        if (_moderationSupported) {
          try {
            await _refreshModerationStatus(session, epoch);
          } on CollaborationException catch (error) {
            _checkEpoch(epoch);
            if (_sessionInvalidReason != null) rethrow;
            // Terms service failure defers shared uploads, while personal sync and
            // authorized downloads continue independently.
            _moderationAccepted = null;
            _moderationVerifiedEpoch = null;
            _sharedContentPolicy = null;
            _lastError = error;
          }
        }
        await _retryRemotePushCleanups(epoch);
        await _syncRemotePushRegistration(session, epoch);
        final reply = await _callSession(session, epoch, 'scopes.list', {
          if (_privateSyncSupported) 'includePersonal': true,
          if (_scopeAccessChangesSupported) 'includeAccessChanges': true,
          if (_organizationsSupported) 'includeOrganizations': true,
          if (_projectArchivingSupported) 'includeArchived': true,
        });
        final revokedIds = _scopeAccessChangesSupported
            ? (reply['revokedScopeIds'] as List).cast<String>().toSet()
            : <String>{};
        final deletedIds = _scopeDeletionSupported
            ? (reply['deletedScopeIds'] as List? ?? const [])
                  .cast<String>()
                  .toSet()
            : <String>{};
        revokedIds.addAll(deletedIds);
        if (revokedIds.any((id) => !isSharedUuid(id))) {
          throw const CollaborationException('invalid_response');
        }
        final scopes = (reply['scopes'] as List)
            .map((r) => SharedScope.fromJson(r as Map<String, dynamic>))
            .toList();
        final cryptoPendingIds =
            (reply['pendingCryptoScopeIds'] as List? ?? const [])
                .cast<String>()
                .toSet();
        if (cryptoPendingIds.any((id) => !isSharedUuid(id))) {
          throw const CollaborationException('invalid_response');
        }
        await _reconcileTerminalTaskConflicts(session, epoch);
        await database.transaction(() async {
          _checkEpoch(epoch);
          await _validLease(partition);
          final old = await database.rows(
            'SELECT data FROM scopes WHERE partition=?',
            [partition],
          );
          for (final row in old) {
            final scope = SharedScope.fromJson(
              CollaborationRepository._map(row['data']),
            );
            if (revokedIds.contains(scope.id) &&
                !scopes.any((r) => r.id == scope.id)) {
              await _upsertScope(
                partition,
                SharedScope.fromJson({
                  ...scope.toJson(),
                  'revoked': true,
                  'deleted': deletedIds.contains(scope.id) || scope.deleted,
                }),
              );
              await database.execute('DELETE FROM local_meta WHERE name=?', [
                'scope_reconciliation:$partition:${scope.id}',
              ]);
            } else if (!scopes.any((r) => r.id == scope.id) && !scope.revoked) {
              // A missing row is not proof of revoked membership: a restored or
              // incomplete server must not silently lock the only local copy.
              await database.execute(
                'INSERT INTO local_meta(name,value) VALUES(?,?) ON CONFLICT(name) DO UPDATE SET value=excluded.value',
                ['scope_reconciliation:$partition:${scope.id}', 'missing'],
              );
            }
          }
          for (final scope in scopes) {
            await _upsertScope(partition, scope);
            if (!cryptoPendingIds.contains(scope.id)) {
              await database.execute('DELETE FROM local_meta WHERE name=?', [
                'scope_reconciliation:$partition:${scope.id}',
              ]);
            }
          }
          for (final id in cryptoPendingIds) {
            await database.execute(
              'INSERT INTO local_meta(name,value) VALUES(?,?) ON CONFLICT(name) DO UPDATE SET value=excluded.value',
              ['scope_reconciliation:$partition:$id', 'crypto_pending'],
            );
          }
        });
        // Pending discovery preserves the local view/immutable queues while
        // independent scopes continue. It is not authenticated revocation.
        scopes.removeWhere((scope) => cryptoPendingIds.contains(scope.id));
        if (_recordContractVersion >= 2) {
          for (final scope in scopes) {
            if (!await _privateScopeAllowed(partition, scope)) continue;
            await _renewLease(partition);
            try {
              await _loadMembers(session, epoch, scope.id, syncLease: true);
            } on CryptoAuthorityPending {
              _checkEpoch(epoch);
              // One scope awaiting keys/identity must not starve independent scopes.
              // Cached labels remain display-only and grant no upload authority.
              _lastError ??= const CollaborationException(
                'crypto_reconciliation_required',
              );
            } on CollaborationApiException catch (error) {
              if (!const {
                'crypto_scope_head_missing',
                'crypto_migration_required',
                'crypto_device_keys_pending',
              }.contains(error.code)) {
                rethrow;
              }
              _checkEpoch(epoch);
              _lastError ??= const CollaborationException(
                'crypto_reconciliation_required',
              );
            }
          }
        }
        await _prepareCryptoProjectionCursors(session, epoch, scopes);
        if (_financeSupported) {
          await _pushFinanceDependencies(session, epoch, scopes);
        }
        // Push first, retaining dirty candidates when subsequent pulls arrive.
        while (true) {
          _checkEpoch(epoch);
          await _renewLease(partition);
          final pending = await database.rows(
            r"SELECT o.* FROM outbox o LEFT JOIN personal_workspaces w ON w.partition=o.partition AND w.scope_id=o.scope_id WHERE o.partition=? AND o.state='pending' AND NOT EXISTS(SELECT 1 FROM local_meta m WHERE m.name='scope_reconciliation:'||o.partition||':'||o.scope_id) AND (?=1 OR EXISTS(SELECT 1 FROM scopes m WHERE m.partition=o.partition AND m.id=o.scope_id AND json_extract(m.data,'$.kind')='personal')) AND EXISTS(SELECT 1 FROM scopes s WHERE s.partition=o.partition AND s.id=o.scope_id AND COALESCE(json_extract(s.data,'$.archived'),0)=0) AND (w.id IS NULL OR (w.enabled=1 AND w.paused=0)) AND NOT(json_extract(o.request,'$.type')='project' AND json_extract(o.request,'$.deleted')=1 AND EXISTS(SELECT 1 FROM finance_records f JOIN finance_outbox q ON q.partition=f.partition AND q.scope_id=f.scope_id AND q.record_id=f.id WHERE f.partition=o.partition AND f.scope_id=o.scope_id AND (json_extract(f.remote,'$.payload.projectId')=o.record_id OR json_extract(q.request,'$.payload.projectId')=o.record_id))) ORDER BY o.sequence LIMIT 1",
            [partition, _sharedUploadsAllowed ? 1 : 0],
          );
          if (pending.isEmpty) break;
          final op = pending.first, scopeId = op['scope_id'] as String;
          final pairKey = 'task_cost_pair:$partition:${op['op_id']}';
          final pairs = await database.rows(
            'SELECT value FROM local_meta WHERE name=?',
            [pairKey],
          );
          Map<String, dynamic>? financeOp;
          int? financeGeneration;
          if (pairs.isNotEmpty) {
            final partner = await database.rows(
              'SELECT * FROM finance_outbox WHERE partition=? AND scope_id=? AND op_id=?',
              [partition, scopeId, pairs.single['value']],
            );
            if (partner.isEmpty) {
              throw const CollaborationException('invalid_response');
            }
            financeOp = partner.single;
            if (financeOp['state'] != 'pending') {
              await database.execute(
                "UPDATE outbox SET state='blocked' WHERE partition=? AND op_id=?",
                [partition, op['op_id']],
              );
              continue;
            }
            financeGeneration = await _financeAccessGeneration(
              partition,
              scopeId,
            );
          }
          final financePair = financeOp;
          try {
            if ((op['wire_version'] as int) > _recordContractVersion) {
              throw const CollaborationException('client_upgrade_required');
            }
            if (financePair != null &&
                (_recordContractVersion < 3 ||
                    _financeContractVersion < 2 ||
                    (financePair['wire_version'] as int? ?? 1) >
                        _financeContractVersion)) {
              throw const CollaborationException('unsupported_version');
            }
            if (financePair != null) {
              await _pushFinancePredecessors(
                session,
                epoch,
                scopeId,
                financePair['record_id'] as String,
                financePair['sequence'] as int,
              );
              financeGeneration = await _financeAccessGeneration(
                partition,
                scopeId,
              );
            }
            final ideaRequest = CollaborationRepository._map(op['request']);
            if (ideaRequest['type'] == 'idea' &&
                ideaRequest['payload'] != null &&
                ideaRequest['deleted'] != true) {
              await _uploadIdeaAssets(
                session,
                epoch,
                scopeId,
                IdeaBoard.fromJson(
                  Map<String, dynamic>.from(ideaRequest['payload'] as Map),
                ),
              );
            }
            final applied = await _callSession(
              session,
              epoch,
              financePair != null
                  ? (_recordContractVersion >= 6
                        ? 'sync6.pushTaskWithCost'
                        : _recordContractVersion >= 5
                        ? 'sync5.pushTaskWithCost'
                        : _recordContractVersion >= 4
                        ? 'sync4.pushTaskWithCost'
                        : 'sync3.pushTaskWithCost')
                  : (_recordContractVersion >= 6
                        ? 'sync6.push'
                        : _recordContractVersion >= 5
                        ? 'sync5.push'
                        : _recordContractVersion >= 4
                        ? 'sync4.push'
                        : _recordContractVersion >= 3
                        ? 'sync3.push'
                        : (op['wire_version'] == 2
                              ? 'sync2.push'
                              : 'sync.push')),
              {
                'scopeId': scopeId,
                if (_recordContractVersion >= 3)
                  'operationContractVersion': op['wire_version'],
                'operation': CollaborationRepository._map(op['request']),
                if (financePair != null)
                  'financeOperation': CollaborationRepository._map(
                    financePair['request'],
                  ),
                if (financePair != null)
                  'financeOperationContractVersion':
                      financePair['wire_version'] ?? 2,
              },
            );
            final canonical = _canonical(
              applied['record'],
              personal: await _isPersonalScope(partition, scopeId),
            );
            if (applied['status'] != 'applied' ||
                canonical['id'] != op['record_id']) {
              throw const CollaborationException('invalid_response');
            }
            final financeCanonical = financePair == null
                ? null
                : _financeCanonical(
                    (applied['finance'] as Map<String, dynamic>)['record'],
                  );
            if (financeCanonical != null &&
                financeCanonical['id'] != financePair!['record_id']) {
              throw const CollaborationException('invalid_response');
            }
            await database.transaction(() async {
              _checkEpoch(epoch);
              await _validLease(partition);
              _checkEpoch(epoch);
              await database.execute(
                'DELETE FROM outbox WHERE op_id=? AND partition=?',
                [op['op_id'], partition],
              );
              await database.execute('DELETE FROM local_meta WHERE name=?', [
                'idea_op_base:$partition:${op['op_id']}',
              ]);
              if (financePair != null) {
                if (financeGeneration !=
                        await _financeAccessGeneration(partition, scopeId) ||
                    !(await _cachedFinancePolicy(
                      partition,
                      scopeId,
                    )).canWrite) {
                  throw const CollaborationException('finance_forbidden');
                }
                await database.execute(
                  'DELETE FROM finance_outbox WHERE partition=? AND op_id=?',
                  [partition, financePair['op_id']],
                );
                await database.execute('DELETE FROM local_meta WHERE name=?', [
                  pairKey,
                ]);
                await _applyFinanceRemote(
                  partition,
                  scopeId,
                  financeCanonical!,
                );
              }
              await _applyRemote(partition, scopeId, canonical);
              if (applied['scope'] is Map<String, dynamic>) {
                final updatedScope = SharedScope.fromJson(
                  applied['scope'] as Map<String, dynamic>,
                );
                if (updatedScope.id != scopeId) {
                  throw const CollaborationException('invalid_response');
                }
                await _upsertScope(partition, updatedScope);
              }
            });
          } on CollaborationApiException catch (error) {
            _checkEpoch(epoch);
            if ((financePair != null &&
                    !const {
                      'policy_acceptance_required',
                      'moderation_upgrade_required',
                      'finance_forbidden',
                      'permission_revoked',
                      'auth_required',
                      'device_revoked',
                      'rate_limited',
                      'feature_disabled',
                    }.contains(error.code)) ||
                error.code == 'conflict' ||
                const {
                  'parent_missing',
                  'live_children',
                  'validation_error',
                  'invalid_payload',
                  'created_at_immutable',
                  'record_deleted',
                  'client_upgrade_required',
                  'assignee_not_member',
                  'invalid_date_range',
                  'person_missing',
                  'person_archived',
                  'project_archived',
                  'task_cost_change_requires_finance',
                }.contains(error.code)) {
              final canonical = error.details['serverRecord'] == null
                  ? null
                  : _canonical(
                      error.details['serverRecord'],
                      personal: await _isPersonalScope(partition, scopeId),
                    );
              if (error.code == 'conflict' &&
                  canonical != null &&
                  await _rebaseIdeaConflict(
                    partition,
                    scopeId,
                    op,
                    canonical,
                    epoch,
                  )) {
                continue;
              }
              await database.transaction(() async {
                _checkEpoch(epoch);
                await _validLease(partition);
                _checkEpoch(epoch);
                if (financePair != null) {
                  await database.execute(
                    "UPDATE finance_outbox SET state='conflict' WHERE partition=? AND scope_id=? AND record_id=?",
                    [partition, scopeId, financePair['record_id']],
                  );
                  final financial = error.details['financeRecord'];
                  await database.execute(
                    'INSERT OR REPLACE INTO finance_conflicts(id,partition,scope_id,record_id,type,reason,remote) VALUES(?,?,?,?,?,?,?)',
                    [
                      financePair['op_id'],
                      partition,
                      scopeId,
                      financePair['record_id'],
                      CollaborationRepository._map(
                        financePair['request'],
                      )['type'],
                      error.code,
                      financial == null
                          ? null
                          : jsonEncode(_financeCanonical(financial)),
                    ],
                  );
                }
                await _persistRecordConflict(
                  partition,
                  scopeId,
                  op,
                  canonical?['deleted'] == true ? 'record_deleted' : error.code,
                  canonical,
                );
              });
            } else if (financePair != null &&
                error.code == 'finance_forbidden') {
              await database.transaction(() async {
                _checkEpoch(epoch);
                await _storeFinancePolicy(
                  partition,
                  scopeId,
                  const SharedFinancePolicy(),
                );
                await database.execute(
                  "UPDATE finance_outbox SET state='blocked' WHERE partition=? AND op_id=?",
                  [partition, financePair['op_id']],
                );
                await database.execute(
                  "UPDATE outbox SET state='blocked' WHERE partition=? AND op_id=?",
                  [partition, op['op_id']],
                );
              });
            } else if ((error.code == 'permission_revoked' ||
                error.code == 'scope_deleted')) {
              await _blockScope(partition, scopeId, epoch);
            } else {
              rethrow;
            }
          }
        }
        for (final scope in scopes) {
          if (!await _privateScopeAllowed(partition, scope)) continue;
          var more = true;
          while (more) {
            _checkEpoch(epoch);
            await _renewLease(partition);
            final rows = await database.rows(
              'SELECT cursor FROM scopes WHERE partition=? AND id=?',
              [partition, scope.id],
            );
            final cursor = rows.first['cursor'] as int;
            try {
              final pulled = await _callSession(
                session,
                epoch,
                _recordContractVersion >= 6
                    ? 'sync6.pull'
                    : _recordContractVersion >= 5
                    ? 'sync5.pull'
                    : _recordContractVersion >= 4
                    ? 'sync4.pull'
                    : _recordContractVersion >= 3
                    ? 'sync3.pull'
                    : (_recordContractVersion >= 2
                          ? 'sync2.pull'
                          : 'sync.pull'),
                {'scopeId': scope.id, 'cursor': cursor, 'limit': 100},
              );
              final next = readInt(pulled, 'cursor');
              more = pulled['hasMore'] == true;
              if (next < cursor || (more && next == cursor)) {
                throw const CollaborationException('invalid_response');
              }
              final canonical = (pulled['records'] as List)
                  .map(
                    (r) => _canonical(
                      r,
                      personal: scope.kind == SharedScopeKind.personal,
                    ),
                  )
                  .toList();
              await database.transaction(() async {
                _checkEpoch(epoch);
                await _validLease(partition);
                _checkEpoch(epoch);
                for (final record in canonical) {
                  await _applyRemote(partition, scope.id, record);
                }
                await database.execute(
                  'UPDATE scopes SET cursor=? WHERE partition=? AND id=?',
                  [next, partition, scope.id],
                );
              });
            } on CryptoAuthorityPending {
              _checkEpoch(epoch);
              _lastError ??= const CollaborationException(
                'crypto_reconciliation_required',
              );
              more = false;
            } on CollaborationApiException catch (error) {
              if (const {
                'crypto_scope_head_missing',
                'crypto_migration_required',
                'crypto_device_keys_pending',
              }.contains(error.code)) {
                _checkEpoch(epoch);
                _lastError ??= const CollaborationException(
                  'crypto_reconciliation_required',
                );
                more = false;
              } else if ((error.code == 'permission_revoked' ||
                  error.code == 'scope_deleted')) {
                await _blockScope(partition, scope.id, epoch);
                more = false;
              } else {
                rethrow;
              }
            }
          }
        }
        if (_recordContractVersion >= 5) {
          for (final scope in scopes) {
            if (!await _privateScopeAllowed(partition, scope)) continue;
            for (final row in await database.rows(
              "SELECT payload FROM records WHERE partition=? AND scope_id=? AND type='idea' AND deleted=0",
              [partition, scope.id],
            )) {
              await downloadIdeaAssets(
                scope.id,
                IdeaBoard.fromJson(
                  CollaborationRepository._map(row['payload']),
                ),
              );
            }
            for (final row in await database.rows(
              "SELECT remote FROM conflicts WHERE partition=? AND scope_id=? AND type='idea' AND remote IS NOT NULL",
              [partition, scope.id],
            )) {
              final canonical = CollaborationRepository._map(row['remote']);
              if (canonical['deleted'] == true ||
                  canonical['payload'] == null) {
                continue;
              }
              await downloadIdeaAssets(
                scope.id,
                IdeaBoard.fromJson(
                  Map<String, dynamic>.from(canonical['payload'] as Map),
                ),
              );
            }
          }
        }
        if (_financeSupported) await _syncFinance(session, epoch, scopes);
        if (_inboxSupported) {
          await _syncInbox(session, epoch);
          await _syncCommands(session, epoch);
          await _syncInbox(session, epoch);
          await _syncNotificationConfiguration(session, epoch, scopes);
        }
        _checkEpoch(epoch);
        if (!_sharedUploadsAllowed &&
            (await database.rows(
              "SELECT 1 FROM outbox o JOIN scopes s ON s.partition=o.partition AND s.id=o.scope_id WHERE o.partition=? AND json_extract(s.data,'\$.kind')!='personal' UNION ALL SELECT 1 FROM finance_outbox o JOIN scopes s ON s.partition=o.partition AND s.id=o.scope_id WHERE o.partition=? AND json_extract(s.data,'\$.kind')!='personal' UNION ALL SELECT 1 FROM commands c JOIN scopes s ON s.partition=c.partition AND s.id=json_extract(c.params,'\$.scopeId') WHERE c.partition=? AND c.operation='reminders.put' AND json_extract(s.data,'\$.kind')!='personal' UNION ALL SELECT 1 FROM linked_payment_intents i JOIN scopes s ON s.partition=json_extract(i.data,'\$.partition') AND s.id=json_extract(i.data,'\$.source.space.id') WHERE s.partition=? AND i.state='pending' AND json_extract(i.data,'\$.operation')!='finance3.paymentProject' AND json_extract(s.data,'\$.kind')!='personal' LIMIT 1",
              [partition, partition, partition, partition],
            )).isNotEmpty) {
          _lastError ??= CollaborationException(
            _moderationSupported
                ? 'policy_acceptance_required'
                : 'moderation_upgrade_required',
          );
        }
        completed = true;
      } on CryptoAuthorityPending {
        if (epoch == _epoch) {
          _lastError = const CollaborationException(
            'crypto_reconciliation_required',
          );
        }
      } on CollaborationException catch (error) {
        if (epoch == _epoch) _lastError = error;
      } catch (_) {
        if (epoch == _epoch) {
          _lastError = const CollaborationException('invalid_response');
        }
      } finally {
        try {
          if (leaseClaimed) {
            await database.execute(
              'DELETE FROM sync_leases WHERE partition=? AND owner=?',
              [session.profile.partition, _leaseOwner],
            );
          }
        } catch (error) {
          completed = false;
          if (epoch == _epoch) {
            _lastError = error is CollaborationException
                ? error
                : const CollaborationException('invalid_response');
          }
          rethrow;
        } finally {
          _syncing = false;
          _syncEpoch = null;
          if (resumePayments &&
              (!completed || epoch != _epoch) &&
              _fullSyncEpoch == epoch) {
            _fullSyncEpoch = null;
          }
          try {
            await refreshLocal();
          } catch (_) {
            if (resumePayments && _fullSyncEpoch == epoch) {
              _fullSyncEpoch = null;
            }
            rethrow;
          } finally {
            done.complete();
          }
        }
      }
      if (resumePayments && epoch == _epoch && _lastError == null) {
        try {
          await LinkedPaymentsRepository(
            database,
            collaboration: this,
          ).resumePending();
        } on CollaborationException catch (error) {
          if (epoch == _epoch) _lastError = error;
        } catch (_) {
          if (epoch == _epoch) {
            _lastError = const CollaborationException('invalid_response');
          }
        }
      }
      if (resumePayments && epoch == _epoch && !_closed) {
        final previousSuccess = _lastSuccessfulSyncAt;
        if (completed && _lastError == null) {
          _lastSuccessfulSyncAt = clock().toUtc();
        }
        if (_fullSyncEpoch == epoch) _fullSyncEpoch = null;
        try {
          await refreshLocal();
        } catch (error) {
          if (epoch == _epoch) {
            _lastSuccessfulSyncAt = previousSuccess;
            _lastError = error is CollaborationException
                ? error
                : const CollaborationException('invalid_response');
          }
          rethrow;
        }
      }
    } catch (error) {
      completed = false;
      if (epoch == _epoch) {
        _lastError = error is CollaborationException
            ? error
            : const CollaborationException('invalid_response');
      }
      rethrow;
    } finally {
      try {
        if (resumePayments && leaseClaimed && epoch == _epoch && !_closed) {
          CollaborationSyncWork work;
          try {
            work = await syncWork();
          } catch (error) {
            completed = false;
            work = const CollaborationSyncWork(
              'bookkeeping_failed',
              unresolved: true,
            );
            if (epoch == _epoch) {
              _lastSuccessfulSyncAt = previousFullSuccess;
              _lastError = error is CollaborationException
                  ? error
                  : const CollaborationException('invalid_response');
              try {
                await refreshLocal();
              } catch (_) {
                // The completion still reports failure if local storage cannot
                // render its status; it must never advertise drained success.
              }
            }
          }
          final error = completed
              ? _lastError
              : (_lastError ??
                    const CollaborationException('invalid_response'));
          final at = clock().toUtc();
          final retry =
              error is CollaborationApiException && error.code == 'rate_limited'
              ? error.details['retryAfter']
              : null;
          if (retry is int && retry >= 1 && retry <= 86400) {
            final minimum = at.add(Duration(seconds: retry));
            if (_automaticSyncRetryIdentity != completionIdentity ||
                _automaticSyncRetryAt == null ||
                minimum.isAfter(_automaticSyncRetryAt!)) {
              _automaticSyncRetryAt = minimum;
              _automaticSyncRetryIdentity = completionIdentity;
            }
          }
          if (epoch == _epoch &&
              !_closed &&
              completionSequence > (lastSyncCompletion?.sequence ?? 0)) {
            lastSyncCompletion = CollaborationSyncCompletion(
              sequence: completionSequence,
              identity: completionIdentity,
              at: at,
              work: work,
              error: error,
              retryAt: _automaticSyncRetryIdentity == completionIdentity
                  ? _automaticSyncRetryAt
                  : null,
            );
            _syncCompletions.add(lastSyncCompletion!);
          }
        }
      } finally {
        if (resumePayments && _fullAttemptEpoch == epoch) {
          _fullAttemptEpoch = null;
        }
      }
    }
  }

  Future<void> _reconcileTerminalTaskConflicts(
    DeviceSession session,
    int epoch,
  ) async {
    final router = cryptoRouter;
    if (router is! CryptoTerminalTaskConflicts) return;
    final partition = session.profile.partition;
    final candidates = await database.rows(
      "SELECT o.* FROM outbox o WHERE o.partition=? AND o.state='pending' "
      "AND json_extract(o.request,'\$.type')='task' AND o.wire_version=6 "
      "AND NOT EXISTS(SELECT 1 FROM local_meta m WHERE m.name='task_cost_pair:'||o.partition||':'||o.op_id) "
      'ORDER BY o.sequence LIMIT 32',
      [partition],
    );
    for (final row in candidates) {
      _checkEpoch(epoch);
      await _validLease(partition);
      final operation = CollaborationRepository._map(row['request']);
      if (operation['opId'] != row['op_id'] ||
          (operation['recordId'] ?? operation['id']) != row['record_id']) {
        throw const FormatException('crypto_task_conflict_binding');
      }
      if (!await (router as CryptoTerminalTaskConflicts)
          .hasTerminalTaskConflict(
            session: session,
            scopeId: row['scope_id'] as String,
            operation: operation,
          )) {
        continue;
      }
      await database.transaction(() async {
        _checkEpoch(epoch);
        await _validLease(partition);
        final current = await database.rows(
          'SELECT state,request,scope_id,record_id,sequence,wire_version FROM outbox WHERE partition=? AND op_id=?',
          [partition, row['op_id']],
        );
        if (current.length != 1 ||
            current.single['state'] != 'pending' ||
            current.single['request'] != row['request'] ||
            current.single['scope_id'] != row['scope_id'] ||
            current.single['record_id'] != row['record_id'] ||
            current.single['sequence'] != row['sequence'] ||
            current.single['wire_version'] != row['wire_version'] ||
            (await database.rows('SELECT 1 FROM local_meta WHERE name=?', [
              'task_cost_pair:$partition:${row['op_id']}',
            ])).isNotEmpty) {
          return;
        }
        _checkEpoch(epoch);
        await _persistRecordConflict(
          partition,
          row['scope_id'] as String,
          row,
          'conflict',
          null,
          exactOperation: true,
        );
      });
    }
  }

  /// Caller owns the epoch/lease-checked transaction and retains original bytes.
  Future<void> _persistRecordConflict(
    String partition,
    String scopeId,
    Map<String, dynamic> operation,
    String reason,
    Map<String, dynamic>? canonical, {
    bool exactOperation = false,
  }) async {
    await database.execute(
      "UPDATE outbox SET state='conflict' WHERE partition=? AND scope_id=? AND record_id=?"
      '${exactOperation ? ' AND op_id=?' : ''}',
      [
        partition,
        scopeId,
        operation['record_id'],
        if (exactOperation) operation['op_id'],
      ],
    );
    await database.execute(
      'INSERT OR REPLACE INTO conflicts(id,partition,scope_id,record_id,type,reason,remote) VALUES(?,?,?,?,?,?,?)',
      [
        operation['op_id'],
        partition,
        scopeId,
        operation['record_id'],
        CollaborationRepository._map(operation['request'])['type'],
        reason,
        canonical == null ? null : jsonEncode(canonical),
      ],
    );
  }

  Map<String, dynamic> _canonical(Object? value, {bool personal = false}) {
    if (value is! Map<String, dynamic> ||
        !isSharedUuid(value['id']) ||
        value['revision'] is! int ||
        (value['revision'] as int) < 1 ||
        value['deleted'] is! bool ||
        value['type'] is! String) {
      throw const CollaborationException('invalid_response');
    }
    final type = SharedRecordType.values.byName(value['type'] as String);
    if (value['deleted'] == true) {
      if (value['payload'] != null) {
        throw const CollaborationException('invalid_response');
      }
    } else {
      if (value['payload'] is! Map<String, dynamic>) {
        throw const CollaborationException('invalid_response');
      }
      validateSharedPayload(
        type,
        value['payload'] as Map<String, dynamic>,
        personal: personal,
      );
      final json = {
        ...normalizeSharedPayloadDates(
          value['payload'] as Map<String, dynamic>,
        ),
        'id': value['id'],
        'revision': value['revision'],
      };
      switch (type) {
        case SharedRecordType.idea:
          if ((value['payload'] as Map)['id'] != value['id']) {
            throw const CollaborationException('invalid_response');
          }
          IdeaBoard.fromJson(json);
        case SharedRecordType.garden:
          if ((value['payload'] as Map)['id'] != value['id']) {
            throw const CollaborationException('invalid_response');
          }
          Garden.fromJson(json);
        case SharedRecordType.householdPerson:
          HouseholdPerson.fromJson(json);
        case SharedRecordType.event:
          SharedEvent.fromJson(json);
        case SharedRecordType.project:
          LocalProject.fromJson(json);
        case SharedRecordType.task:
          LocalTask.fromJson(json);
        case SharedRecordType.shoppingList:
          LocalShoppingList.fromJson(json);
        case SharedRecordType.shoppingItem:
          LocalShoppingItem.fromJson(json);
      }
    }
    return value;
  }

  Future<void> _applyRemote(
    String partition,
    String scope,
    Map<String, dynamic> canonical,
  ) async {
    final id = canonical['id'];
    final old = await database.rows(
      'SELECT * FROM records WHERE partition=? AND scope_id=? AND id=?',
      [partition, scope, id],
    );
    await database.execute(
      r"UPDATE conflicts SET remote=? WHERE partition=? AND scope_id=? AND record_id=? AND (remote IS NULL OR json_extract(remote,'$.revision') <= ?)",
      [jsonEncode(canonical), partition, scope, id, canonical['revision']],
    );
    if (old.isNotEmpty && old.first['type'] != canonical['type']) {
      throw const CollaborationException('invalid_response');
    }
    final queued = await database.rows(
      'SELECT op_id FROM outbox WHERE partition=? AND scope_id=? AND record_id=?',
      [partition, scope, id],
    );
    final preserve = queued.isNotEmpty;
    if (old.isNotEmpty &&
        (old.first['server_revision'] as int) >=
            (canonical['revision'] as int)) {
      if (preserve || old.first['remote'] == null) return;
      // A lost ACK may be replayed after a newer canonical was pulled while
      // blocked. Once the last draft is acknowledged, materialize that newest
      // canonical rather than leaving an old candidate behind a passed cursor.
      canonical = _canonical(
        CollaborationRepository._map(old.first['remote']),
        personal: await _isPersonalScope(partition, scope),
      );
      final payload = canonical['payload'] == null
          ? null
          : jsonEncode(canonical['payload']);
      if (old.first['payload'] == payload &&
          old.first['deleted'] == (canonical['deleted'] == true ? 1 : 0)) {
        return;
      }
    }
    await _reconcileLocalReminders(
      partition,
      scope,
      canonical['type'] as String,
      id as String,
      old.isEmpty || old.first['payload'] == null
          ? null
          : CollaborationRepository._map(old.first['payload']),
      canonical['payload'] as Map<String, dynamic>?,
      canonical['deleted'] == true,
    );
    await database.execute(
      'INSERT INTO records(partition,scope_id,id,type,local_revision,server_revision,payload,deleted,remote) VALUES(?,?,?,?,?,?,?,?,?) ON CONFLICT(partition,scope_id,id) DO UPDATE SET local_revision=excluded.local_revision,server_revision=excluded.server_revision,payload=excluded.payload,deleted=excluded.deleted,remote=excluded.remote',
      [
        partition,
        scope,
        id,
        canonical['type'],
        preserve
            ? old.first['local_revision']
            : ((old.isEmpty ? 0 : old.first['local_revision'] as int) + 1),
        canonical['revision'],
        preserve
            ? old.first['payload']
            : (canonical['payload'] == null
                  ? null
                  : jsonEncode(canonical['payload'])),
        preserve
            ? old.first['deleted']
            : (canonical['deleted'] == true ? 1 : 0),
        jsonEncode(canonical),
      ],
    );
    if (await _activePrivateScope(partition, scope)) {
      await database.touchPersonal();
    }
  }

  Future<void> _blockScope(String partition, String scopeId, int epoch) =>
      database.transaction(() async {
        _checkEpoch(epoch);
        final rows = await database.rows(
          'SELECT data FROM scopes WHERE partition=? AND id=?',
          [partition, scopeId],
        );
        if (rows.isNotEmpty) {
          final scope = SharedScope.fromJson(
            CollaborationRepository._map(rows.first['data']),
          );
          await _upsertScope(
            partition,
            SharedScope.fromJson({...scope.toJson(), 'revoked': true}),
          );
        }
      });
  Future<void> resumeBlockedChanges(String scopeId) async {
    final profile = _requireSession().profile, epoch = _epoch;
    final reply = await _call('scopes.list', {});
    final scope = (reply['scopes'] as List)
        .map((r) => SharedScope.fromJson(r as Map<String, dynamic>))
        .where((r) => r.id == scopeId)
        .firstOrNull;
    if (scope == null || scope.role == SharedRole.viewer) {
      throw const CollaborationException('permission_revoked');
    }
    await database.transaction(() async {
      _checkEpoch(epoch);
      await database.execute(
        'UPDATE scopes SET data=?,blocked=0 WHERE partition=? AND id=?',
        [jsonEncode(scope.toJson()), profile.partition, scopeId],
      );
      await database.execute(
        "UPDATE outbox SET state='pending' WHERE partition=? AND scope_id=? AND state='blocked'",
        [profile.partition, scopeId],
      );
    });
    await refreshLocal();
    await syncNow();
  }

  Future<void> resolveConflict({
    required String conflictId,
    required bool keepLocal,
  }) async {
    if (await _resolvePairedTaskCostConflict(
      conflictId: conflictId,
      keepLocal: keepLocal,
    )) {
      return;
    }
    final profile = _requireSession().profile, epoch = _epoch;
    if (keepLocal) {
      await syncNow();
      _checkEpoch(epoch);
      if (_lastError != null) throw _lastError!;
    }
    await database.transaction(() async {
      _checkEpoch(epoch);
      final rows = await database.rows(
        'SELECT * FROM conflicts WHERE partition=? AND id=?',
        [profile.partition, conflictId],
      );
      if (rows.isEmpty) throw const CollaborationException('conflict_missing');
      final conflict = rows.first,
          scope = conflict['scope_id'] as String,
          id = conflict['record_id'] as String;
      await _writable(profile.partition, scope);
      final records = await database.rows(
        'SELECT * FROM records WHERE partition=? AND scope_id=? AND id=?',
        [profile.partition, scope, id],
      );
      final candidate = records.first,
          remoteValue = records.first['remote'] ?? conflict['remote'],
          remote = remoteValue == null
              ? null
              : _canonical(
                  CollaborationRepository._map(remoteValue),
                  personal: await _isPersonalScope(profile.partition, scope),
                );
      if (keepLocal && remote?['deleted'] == true) {
        throw const CollaborationException('record_deleted');
      }
      if (keepLocal &&
          const {
            'parent_missing',
            'live_children',
          }.contains(conflict['reason'])) {
        throw const CollaborationException('requires_remote_resolution');
      }
      await database.execute(
        'DELETE FROM outbox WHERE partition=? AND scope_id=? AND record_id=?',
        [profile.partition, scope, id],
      );
      await database.execute(
        'DELETE FROM conflicts WHERE partition=? AND scope_id=? AND record_id=?',
        [profile.partition, scope, id],
      );
      final revision = (remote?['revision'] as int?) ?? 0;
      await database.execute(
        'UPDATE records SET server_revision=?,local_revision=local_revision+1,remote=? WHERE partition=? AND scope_id=? AND id=?',
        [
          revision,
          remote == null ? null : jsonEncode(remote),
          profile.partition,
          scope,
          id,
        ],
      );
      if (keepLocal) {
        final candidatePayload = candidate['payload'] == null
            ? null
            : CollaborationRepository._map(candidate['payload']);
        if (candidatePayload != null && remote?['payload'] is Map) {
          // Legacy drafts do not know later planning/person fields. Preserve the
          // latest canonical values for missing keys before upgrading the body.
          for (final entry
              in (remote!['payload'] as Map<String, dynamic>).entries) {
            candidatePayload.putIfAbsent(entry.key, () => entry.value);
          }
        }
        if (candidatePayload != null && _recordContractVersion >= 2) {
          if (candidate['type'] == 'task' || candidate['type'] == 'project') {
            candidatePayload.putIfAbsent('startAt', () => null);
            candidatePayload.putIfAbsent('endAt', () => null);
          }
          if (_recordContractVersion >= 3) {
            addRichPlanningDefaults(
              candidatePayload,
              candidate['type'] as String,
            );
          }
          if (candidate['type'] == 'task') {
            candidatePayload.putIfAbsent(
              'assigneeAccountIds',
              () => <String>[],
            );
          }
        }
        final request = {
          'opId': newSharedId(),
          'recordId': id,
          'type': candidate['type'],
          'expectedRevision': revision,
          'deleted': candidate['deleted'] == 1,
          'payload': candidatePayload,
        };
        await database.execute(
          'INSERT INTO outbox(op_id,partition,scope_id,record_id,request,wire_version) VALUES(?,?,?,?,?,?)',
          [
            request['opId'],
            profile.partition,
            scope,
            id,
            jsonEncode(request),
            _recordContractVersion,
          ],
        );
      } else {
        await database.execute(
          'UPDATE records SET payload=?,deleted=? WHERE partition=? AND scope_id=? AND id=?',
          [
            remote?['payload'] == null ? null : jsonEncode(remote!['payload']),
            remote == null || remote['deleted'] == true ? 1 : 0,
            profile.partition,
            scope,
            id,
          ],
        );
      }
    });
    await refreshLocal();
  }

  /// Recovery export contains no password, OTP, device token or remote base snapshot.
  Future<String> exportUnsentWork() async {
    final session = _requireSession(), epoch = _epoch;
    final partition = session.profile.partition;
    final profiles = await database.rows(
      'SELECT profile FROM accounts WHERE partition=?',
      [partition],
    );
    final ops = await database.rows(
      'SELECT scope_id,record_id,state,request FROM outbox WHERE partition=? ORDER BY sequence',
      [partition],
    );
    final conflicts = await database.rows(
      'SELECT scope_id,record_id,type,reason FROM conflicts WHERE partition=?',
      [partition],
    );
    final commands = await database.rows(
      'SELECT operation,params,state FROM commands WHERE partition=? ORDER BY sequence',
      [partition],
    );
    // This explicit recovery contains only this device's immutable candidates.
    // It intentionally survives loss of read rights; no canonical/base rows or
    // authorization objects enter the document and nothing is resumed here.
    final financial = await database.rows(
      'SELECT scope_id,record_id,state,request FROM finance_outbox WHERE partition=? ORDER BY sequence',
      [partition],
    );
    final ownIdeaDrafts = <Map<String, dynamic>>[];
    final media = <String, Map<String, dynamic>>{};
    Future<void> collectMedia(IdeaBoard board, String workspace) async {
      for (final asset in board.assets) {
        final key = '$workspace:${asset.sha256}';
        if (media.containsKey(key)) continue;
        final rows = await database.rows(
          'SELECT bytes FROM idea_assets WHERE workspace=? AND sha256=?',
          [workspace, asset.sha256],
        );
        if (rows.isEmpty) {
          throw const CollaborationException('idea_asset_missing');
        }
        final bytes = Uint8List.fromList(rows.single['bytes'] as List<int>);
        await verifyIdeaAsset(asset, bytes);
        media[key] = {
          'workspace': workspace,
          'metadata': asset.toJson(),
          'bytes': base64Encode(bytes),
        };
      }
    }

    for (final row in ops) {
      final operation = CollaborationRepository._map(row['request']);
      if (operation['type'] == 'idea' && operation['payload'] != null) {
        await collectMedia(
          IdeaBoard.fromJson(
            CollaborationRepository._map(operation['payload']),
          ),
          'shared:$partition:${row['scope_id']}',
        );
      }
    }
    for (final row in await database.rows(
      'SELECT workspace,id,payload,base FROM idea_drafts WHERE workspace LIKE ? ORDER BY workspace,id',
      ['shared:$partition:%'],
    )) {
      // An unchanged preview of somebody else's downloaded board is not work.
      if (row['payload'] == row['base']) continue;
      final board = IdeaBoard.fromJson(
        CollaborationRepository._map(row['payload']),
      );
      await collectMedia(board, row['workspace'] as String);
      ownIdeaDrafts.add({
        'workspace': row['workspace'],
        'id': row['id'],
        'payload': board.toJson(),
      });
    }
    _checkEpoch(epoch);
    return jsonEncode({
      'format': 'vsakdan-unsent-work',
      'schemaVersion': ownIdeaDrafts.isNotEmpty || media.isNotEmpty ? 2 : 1,
      'account': CollaborationRepository._map(profiles.first['profile']),
      'operations': ops
          .map(
            (r) => {
              'scopeId': r['scope_id'],
              'recordId': r['record_id'],
              'state': r['state'],
              'operation': CollaborationRepository._map(r['request']),
            },
          )
          .toList(),
      'conflicts': conflicts,
      'commands': commands
          .map(
            (r) => {
              'operation': r['operation'],
              'params': CollaborationRepository._map(r['params']),
              'state': r['state'],
            },
          )
          .toList(),
      'financeOperations': financial
          .map(
            (r) => {
              'scopeId': r['scope_id'],
              'recordId': r['record_id'],
              'state': r['state'],
              'operation': CollaborationRepository._map(r['request']),
            },
          )
          .toList(),
      if (ownIdeaDrafts.isNotEmpty || media.isNotEmpty) ...{
        'ideaDrafts': ownIdeaDrafts,
        'ideaAssets': media.values.toList(),
      },
    });
  }
}
