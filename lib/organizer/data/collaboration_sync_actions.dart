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

  Future<void> syncNow({bool resumePayments = true}) async {
    if (_syncing ||
        _session == null ||
        _closed ||
        (resumePayments && _fullSyncEpoch == _epoch)) {
      return;
    }
    _lastSyncAttemptAt = clock().toUtc();
    if (_sessionInvalidReason != null) {
      _lastError = CollaborationException(_sessionInvalidReason!);
      await refreshLocal();
      return;
    }
    final session = _requireSession(),
        epoch = _epoch,
        partition = _session!.profile.partition;
    _syncing = true;
    _syncEpoch = epoch;
    if (resumePayments) _fullSyncEpoch = epoch;
    final done = _syncDone = Completer<void>();
    var leaseClaimed = false, completed = false;
    _lastError = null;
    try {
      leaseClaimed = await _claimLease(partition);
      if (!leaseClaimed) return;
      _checkEpoch(epoch);
      await refreshLocal();
      await _negotiate(session, epoch);
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
      if (revokedIds.any((id) => !isSharedUuid(id))) {
        throw const CollaborationException('invalid_response');
      }
      final scopes = (reply['scopes'] as List)
          .map((r) => SharedScope.fromJson(r as Map<String, dynamic>))
          .toList();
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
              SharedScope.fromJson({...scope.toJson(), 'revoked': true}),
            );
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
          await database.execute('DELETE FROM local_meta WHERE name=?', [
            'scope_reconciliation:$partition:${scope.id}',
          ]);
        }
      });
      if (_recordContractVersion >= 2) {
        for (final scope in scopes) {
          if (!await _privateScopeAllowed(partition, scope)) continue;
          await _renewLease(partition);
          await _loadMembers(session, epoch, scope.id, syncLease: true);
        }
      }
      if (_financeSupported) {
        await _pushFinanceDependencies(session, epoch, scopes);
      }
      // Push first, retaining dirty candidates when subsequent pulls arrive.
      while (true) {
        _checkEpoch(epoch);
        await _renewLease(partition);
        final pending = await database.rows(
          r"SELECT o.* FROM outbox o LEFT JOIN personal_workspaces w ON w.partition=o.partition AND w.scope_id=o.scope_id WHERE o.partition=? AND o.state='pending' AND NOT EXISTS(SELECT 1 FROM local_meta m WHERE m.name='scope_reconciliation:'||o.partition||':'||o.scope_id) AND EXISTS(SELECT 1 FROM scopes s WHERE s.partition=o.partition AND s.id=o.scope_id AND COALESCE(json_extract(s.data,'$.archived'),0)=0) AND (w.id IS NULL OR (w.enabled=1 AND w.paused=0)) AND NOT(json_extract(o.request,'$.type')='project' AND json_extract(o.request,'$.deleted')=1 AND EXISTS(SELECT 1 FROM finance_records f JOIN finance_outbox q ON q.partition=f.partition AND q.scope_id=f.scope_id AND q.record_id=f.id WHERE f.partition=o.partition AND f.scope_id=o.scope_id AND (json_extract(f.remote,'$.payload.projectId')=o.record_id OR json_extract(q.request,'$.payload.projectId')=o.record_id))) ORDER BY o.sequence LIMIT 1",
          [partition],
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
              (_recordContractVersion < 3 || _financeContractVersion < 2)) {
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
          final applied = await _callSession(
            session,
            epoch,
            financePair != null
                ? (_recordContractVersion >= 4
                      ? 'sync4.pushTaskWithCost'
                      : 'sync3.pushTaskWithCost')
                : (_recordContractVersion >= 4
                      ? 'sync4.push'
                      : _recordContractVersion >= 3
                      ? 'sync3.push'
                      : (op['wire_version'] == 2 ? 'sync2.push' : 'sync.push')),
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
            if (financePair != null) {
              if (financeGeneration !=
                      await _financeAccessGeneration(partition, scopeId) ||
                  !(await _cachedFinancePolicy(partition, scopeId)).canWrite) {
                throw const CollaborationException('finance_forbidden');
              }
              await database.execute(
                'DELETE FROM finance_outbox WHERE partition=? AND op_id=?',
                [partition, financePair['op_id']],
              );
              await database.execute('DELETE FROM local_meta WHERE name=?', [
                pairKey,
              ]);
              await _applyFinanceRemote(partition, scopeId, financeCanonical!);
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
                'task_cost_change_requires_finance',
              }.contains(error.code)) {
            final canonical = error.details['serverRecord'] == null
                ? null
                : _canonical(
                    error.details['serverRecord'],
                    personal: await _isPersonalScope(partition, scopeId),
                  );
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
              await database.execute(
                "UPDATE outbox SET state='conflict' WHERE partition=? AND scope_id=? AND record_id=?",
                [partition, scopeId, op['record_id']],
              );
              await database.execute(
                'INSERT OR REPLACE INTO conflicts(id,partition,scope_id,record_id,type,reason,remote) VALUES(?,?,?,?,?,?,?)',
                [
                  op['op_id'],
                  partition,
                  scopeId,
                  op['record_id'],
                  CollaborationRepository._map(op['request'])['type'],
                  canonical?['deleted'] == true ? 'record_deleted' : error.code,
                  canonical == null ? null : jsonEncode(canonical),
                ],
              );
            });
          } else if (financePair != null && error.code == 'finance_forbidden') {
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
          } else if (error.code == 'permission_revoked') {
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
              _recordContractVersion >= 4
                  ? 'sync4.pull'
                  : _recordContractVersion >= 3
                  ? 'sync3.pull'
                  : (_recordContractVersion >= 2 ? 'sync2.pull' : 'sync.pull'),
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
          } on CollaborationApiException catch (error) {
            if (error.code == 'permission_revoked') {
              await _blockScope(partition, scope.id, epoch);
              more = false;
            } else {
              rethrow;
            }
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
      completed = true;
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
          if (resumePayments && _fullSyncEpoch == epoch) _fullSyncEpoch = null;
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
            SharedScope(
              id: scope.id,
              name: scope.name,
              kind: scope.kind,
              role: scope.role,
              revoked: true,
            ),
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
    final financial = <Map<String, dynamic>>[];
    final authorizedFinancialEpochs = <String, int>{};
    final queue = await database.rows(
      'SELECT scope_id,record_id,state,request FROM finance_outbox WHERE partition=? ORDER BY sequence',
      [partition],
    );
    final financeReminderRows = await database.rows(
      r"SELECT id,scope_id FROM scheduled_reminders WHERE partition=? AND json_extract(data,'$.targetType')='financeEntry'",
      [partition],
    );
    final financeReminderScopes = {
      for (final row in financeReminderRows)
        row['id'] as String: row['scope_id'] as String,
    };
    String? financialCommandScope(Map<String, dynamic> command) {
      final params = CollaborationRepository._map(command['params']);
      if (params['targetType'] == 'financeEntry') {
        return params['scopeId'] as String?;
      }
      return params['id'] is String
          ? financeReminderScopes[params['id']]
          : null;
    }

    final scopes = {
      ...queue.map((r) => r['scope_id'] as String),
      ...commands.map(financialCommandScope).whereType<String>(),
    };
    for (final scope in scopes) {
      var policy = await _cachedFinancePolicy(partition, scope);
      try {
        policy = await refreshFinancePolicy(scope);
      } on CollaborationException catch (e) {
        if (e.code == 'permission_revoked' || e.code == 'finance_forbidden') {
          policy = const SharedFinancePolicy();
          await database.transaction(() async {
            _checkEpoch(epoch);
            await _storeFinancePolicy(partition, scope, policy);
          });
          await refreshLocal();
        } else if (e.code != 'network' &&
            e.code != 'auth_required' &&
            e.code != 'device_revoked') {
          rethrow;
        }
      }
      _checkEpoch(epoch);
      final live = state.scopes.any((s) => s.id == scope && !s.revoked);
      if (live && policy.canRead) {
        authorizedFinancialEpochs[scope] = policy.revision;
        financial.addAll(
          queue
              .where((r) => r['scope_id'] == scope)
              .map(
                (r) => {
                  'scopeId': r['scope_id'],
                  'recordId': r['record_id'],
                  'state': r['state'],
                  'operation': CollaborationRepository._map(r['request']),
                },
              ),
        );
      }
    }
    // One final SQL snapshot prevents an earlier scope's drafts leaking after
    // its rights changed while another scope's network check was suspended.
    final policyRows = await database.rows(
      'SELECT id,data,finance_policy FROM scopes WHERE partition=?',
      [partition],
    );
    final exportableFinance = <String>{};
    for (final row in policyRows) {
      if (row['finance_policy'] == null) continue;
      final policy = SharedFinancePolicy.fromJson(
        CollaborationRepository._map(row['finance_policy']),
      );
      final scope = SharedScope.fromJson(
        CollaborationRepository._map(row['data']),
      );
      if (!scope.revoked &&
          policy.canRead &&
          authorizedFinancialEpochs[scope.id] == policy.revision) {
        exportableFinance.add(scope.id);
      }
    }
    financial.removeWhere(
      (entry) => !exportableFinance.contains(entry['scopeId']),
    );
    _checkEpoch(epoch);
    return jsonEncode({
      'format': 'vsakdan-unsent-work',
      'schemaVersion': 1,
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
          .where((command) {
            final scope = financialCommandScope(command);
            return scope == null || exportableFinance.contains(scope);
          })
          .map(
            (r) => {
              'operation': r['operation'],
              'params': CollaborationRepository._map(r['params']),
              'state': r['state'],
            },
          )
          .toList(),
      'financeOperations': financial,
    });
  }
}
