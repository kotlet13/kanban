part of 'collaboration_repository.dart';

/// Separate authorized financial change stream; ordinary record sync never sees it.
extension CollaborationFinanceSync on CollaborationRepository {
  Map<String, dynamic> _financeCanonical(Object? value) {
    if (value is! Map<String, dynamic> ||
        !isSharedUuid(value['id']) ||
        value['revision'] is! int ||
        (value['revision'] as int) < 1 ||
        value['deleted'] is! bool ||
        value['type'] is! String) {
      throw const CollaborationException('invalid_response');
    }
    final type = SharedFinanceRecordType.values.byName(value['type'] as String);
    if (value['deleted'] == true) {
      if (value['payload'] != null) {
        throw const CollaborationException('invalid_response');
      }
    } else {
      if (value['payload'] is! Map<String, dynamic>) {
        throw const CollaborationException('invalid_response');
      }
      validateSharedFinancePayload(
        type,
        value['payload'] as Map<String, dynamic>,
        contractVersion: value['contractVersion'] as int? ?? 1,
      );
    }
    return value;
  }

  Future<void> _applyFinanceRemote(
    String p,
    String scope,
    Map<String, dynamic> canonical,
  ) async {
    final id = canonical['id'];
    final old = await database.rows(
      'SELECT * FROM finance_records WHERE partition=? AND scope_id=? AND id=?',
      [p, scope, id],
    );
    if (old.isNotEmpty && old.first['type'] != canonical['type']) {
      throw const CollaborationException('invalid_response');
    }
    await database.execute(
      r"UPDATE finance_conflicts SET remote=? WHERE partition=? AND scope_id=? AND record_id=? AND (remote IS NULL OR json_extract(remote,'$.revision')<=?)",
      [jsonEncode(canonical), p, scope, id, canonical['revision']],
    );
    final queued = await database.rows(
      'SELECT op_id FROM finance_outbox WHERE partition=? AND scope_id=? AND record_id=?',
      [p, scope, id],
    );
    final dirty = queued.isNotEmpty;
    if (old.isNotEmpty &&
        (old.first['server_revision'] as int) >=
            (canonical['revision'] as int)) {
      if (dirty || old.first['remote'] == null) return;
      canonical = _financeCanonical(
        CollaborationRepository._map(old.first['remote']),
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
      p,
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
      'INSERT INTO finance_records(partition,scope_id,id,type,local_revision,server_revision,payload,deleted,remote) VALUES(?,?,?,?,?,?,?,?,?) ON CONFLICT(partition,scope_id,id) DO UPDATE SET local_revision=excluded.local_revision,server_revision=excluded.server_revision,payload=excluded.payload,deleted=excluded.deleted,remote=excluded.remote',
      [
        p,
        scope,
        id,
        canonical['type'],
        dirty
            ? old.first['local_revision']
            : ((old.isEmpty ? 0 : old.first['local_revision'] as int) + 1),
        canonical['revision'],
        dirty
            ? old.first['payload']
            : canonical['payload'] == null
            ? null
            : jsonEncode(canonical['payload']),
        dirty
            ? old.first['deleted']
            : canonical['deleted'] == true
            ? 1
            : 0,
        jsonEncode(canonical),
      ],
    );
    if (await _activePrivateScope(p, scope)) await database.touchPersonal();
  }

  Future<void> _resetFinanceProjection(String p, String scope) async {
    await _clearFinanceAccountChoices(p, scope);
    await database.execute(
      'DELETE FROM finance_records WHERE partition=? AND scope_id=? AND id NOT IN(SELECT record_id FROM finance_outbox WHERE partition=? AND scope_id=?)',
      [p, scope, p, scope],
    );
    await database.execute(
      'UPDATE scopes SET finance_cursor=0,finance_access_revision=0,finance_complete=0 WHERE partition=? AND id=?',
      [p, scope],
    );
  }

  Future<void> _syncFinance(
    DeviceSession session,
    int epoch,
    List<SharedScope> scopes, {
    required List<SharedScope> availableScopes,
    CollaborationAccountChanges? changes,
  }) async {
    final p = session.profile.partition;
    final dependencies = <SharedScope>[];
    final selected = scopes.map((s) => s.id).toSet();
    for (final parent in scopes.where(
      (s) =>
          (s.kind == SharedScopeKind.organization ||
              s.kind == SharedScopeKind.household) &&
          s.canRead &&
          !s.deleted &&
          !s.revoked,
    )) {
      final policy = await _cachedFinancePolicy(p, parent.id);
      _checkEpoch(epoch);
      if (!policy.canRead) continue;
      for (final child in availableScopes) {
        if (child.kind != SharedScopeKind.project ||
            child.parentSpaceId != parent.id ||
            !child.canRead ||
            child.deleted ||
            child.revoked ||
            selected.contains(child.id)) {
          continue;
        }
        final dependency = await _financeDependencyReadState(
          p,
          child.id,
          policy.organizationFinanceSequences[child.id],
        );
        if (dependency.needsRead) {
          selected.add(child.id);
          dependencies.add(child);
          changes?.include(child.id, 'finance');
        }
        _checkEpoch(epoch);
      }
    }
    if (dependencies.isNotEmpty) {
      // The dependency is still read through its normal fresh policy, crypto
      // cursor transition and finance/payment verifiers. Cached flags select
      // work only; they never certify the missing child as complete.
      await _prepareCryptoProjectionCursors(session, epoch, dependencies);
      scopes.addAll(dependencies);
    }
    // Child settlement/materialization precedes the parent's coverage read.
    // Keep selected projects in order and include archived historical sources.
    final ordered = [
      ...scopes.where((s) => s.kind == SharedScopeKind.project),
      ...scopes.where((s) => s.kind != SharedScopeKind.project),
    ];
    final capabilities = await database.rows(
      'SELECT value FROM local_meta WHERE name=?',
      ['capabilities:$p'],
    );
    _checkEpoch(epoch);
    final linkedPaymentsSupported =
        capabilities.isNotEmpty &&
        (CollaborationRepository._map(capabilities.single['value'])['features']
                as Map?)?['linkedPayments'] ==
            true;
    for (final scope in ordered) {
      if (!await _privateScopeAllowed(p, scope)) continue;
      await _renewLease(p);
      Future<void> syncScope() => _syncFinanceScope(
        session,
        epoch,
        scope,
        linkedPaymentsSupported: linkedPaymentsSupported,
      );
      final router = cryptoRouter;
      if (router is CryptoFinanceReadContext) {
        await (router as CryptoFinanceReadContext).withFinanceRead(
          session: session,
          read: syncScope,
        );
      } else {
        await syncScope();
      }
      _checkEpoch(epoch);
    }
  }

  Future<({bool needsRead, String signature})> _financeDependencyReadState(
    String partition,
    String scope,
    int? requiredSequence,
  ) async {
    final rows = await database.rows(
      'SELECT finance_policy,finance_complete,finance_cursor,finance_access_revision,finance_blocked FROM scopes WHERE partition=? AND id=?',
      [partition, scope],
    );
    if (rows.length != 1) return (needsRead: false, signature: '');
    final row = rows.single;
    final policy = await _cachedFinancePolicy(partition, scope);
    // A definitive denial is not a missing snapshot and must remain hidden.
    // An unknown policy still gets the ordinary fresh authorization query.
    if (row['finance_policy'] != null && !policy.canRead) {
      return (needsRead: false, signature: '');
    }
    final incomplete =
        row['finance_complete'] != 1 ||
        requiredSequence != null &&
            (row['finance_cursor'] as int) < requiredSequence;
    final generation = await _financeAccessGeneration(partition, scope);
    Map<String, dynamic>? proof;
    if (policy.linkedPaymentsRequired) {
      final space = PaymentSpaceRef(scope, partition: partition);
      final proofs = await database.rows(
        'SELECT value FROM local_meta WHERE name=?',
        ['linked_payment_complete:${space.key}'],
      );
      if (proofs.isNotEmpty) {
        proof = CollaborationRepository._map(proofs.single['value']);
      }
    }
    return (
      needsRead:
          incomplete ||
          policy.linkedPaymentsRequired &&
              (proof == null ||
                  row['finance_blocked'] != 0 ||
                  proof['generation'] != generation ||
                  proof['accessRevision'] != row['finance_access_revision']),
      signature: jsonEncode([
        row,
        requiredSequence,
        generation,
        // Only snapshot bindings can change debt. Refresh bookkeeping such as
        // a checked-at timestamp must not schedule another identical read.
        if (proof != null)
          for (final key in const [
            'generation',
            'scopeSequence',
            'accessRevision',
          ])
            proof[key],
      ]),
    );
  }

  /// Automatic local debt selects the existing coordinator once per stable
  /// prerequisite state; an explicit manual demand may retry that same debt.
  /// A cached false aggregate gets one verified recheck even when its local
  /// children are already ready. Local flags select work, never certify coverage.
  Future<bool> _includeIncompleteParentFinanceRecovery(
    DeviceSession session,
    int epoch,
    CollaborationAccountChanges changes, {
    required bool manual,
  }) async {
    if (!_financeSupported || !_organizationFinanceSupported) return false;
    if (_parentFinanceRecoveryEpoch != epoch) {
      _parentFinanceRecoveryEpoch = epoch;
      _parentFinanceRecoveryAttempts.clear();
    }
    var included = false;
    final p = session.profile.partition;
    for (final parent in state.scopes) {
      if (!const {
            SharedScopeKind.organization,
            SharedScopeKind.household,
          }.contains(parent.kind) ||
          !parent.canRead ||
          parent.deleted ||
          parent.revoked ||
          _parentFinanceRecoveryAttempts.length >= 64 &&
              !_parentFinanceRecoveryAttempts.containsKey(parent.id)) {
        continue;
      }
      final policy = await _cachedFinancePolicy(p, parent.id);
      _checkEpoch(epoch);
      if (!policy.canRead) continue;
      final prerequisites = <String>[], readyChildren = <String>[];
      for (final child in state.scopes) {
        if (child.kind != SharedScopeKind.project ||
            child.parentSpaceId != parent.id ||
            !child.canRead ||
            child.deleted ||
            child.revoked) {
          continue;
        }
        final dependency = await _financeDependencyReadState(
          p,
          child.id,
          policy.organizationFinanceSequences[child.id],
        );
        _checkEpoch(epoch);
        if (dependency.needsRead) {
          prerequisites.add('${child.id}:${dependency.signature}');
        } else if (dependency.signature.isNotEmpty) {
          readyChildren.add('${child.id}:${dependency.signature}');
        }
      }
      prerequisites.sort();
      late final String signature;
      if (prerequisites.isEmpty) {
        if (policy.organizationFinanceComplete) continue;
        final parentRead = await _financeDependencyReadState(
          p,
          parent.id,
          null,
        );
        _checkEpoch(epoch);
        if (parentRead.signature.isEmpty) continue;
        readyChildren.sort();
        signature = jsonEncode([
          'coverage',
          parentRead.signature,
          readyChildren,
        ]);
      } else {
        signature = jsonEncode([
          policy.revision,
          policy.grant.name,
          prerequisites,
        ]);
      }
      if (!manual && _parentFinanceRecoveryAttempts[parent.id] == signature) {
        continue;
      }
      // Record before work, including a failed/unfinished read, so unchanged
      // 30-second probes do not retry the same prerequisite/coverage state.
      _parentFinanceRecoveryAttempts[parent.id] = signature;
      changes.include(parent.id, 'finance');
      included = true;
    }
    return included;
  }

  Future<void> _syncFinanceScope(
    DeviceSession session,
    int epoch,
    SharedScope scope, {
    required bool linkedPaymentsSupported,
  }) async {
    final p = session.profile.partition;
    Future<void> reviewed() => database.transaction(() async {
      _checkEpoch(epoch);
      await _validLease(p);
      _checkEpoch(epoch);
      await database.execute('DELETE FROM local_meta WHERE name=?', [
        'finance_access_review:$p:${scope.id}',
      ]);
    });

    var failureStage = SyncFailureStage.financePolicy;
    try {
      final policy = await _fetchFinancePolicy(
        session,
        epoch,
        scope.id,
        syncLease: true,
      );
      if (!policy.canRead) {
        await reviewed();
        return;
      }
      failureStage = SyncFailureStage.financeUpload;
      if (policy.canWrite) await _pushFinanceScope(session, epoch, scope.id);
      failureStage = SyncFailureStage.financeDownload;
      await _pullFinanceScope(session, epoch, scope.id);
      failureStage = SyncFailureStage.financePolicy;
      if (_organizationFinanceSupported &&
          scope.kind == SharedScopeKind.project) {
        try {
          await _fetchFinanceAccountChoices(
            session,
            epoch,
            scope.id,
            syncLease: true,
          );
        } on CryptoAuthorityPending catch (error) {
          // The selector is optional when this project-only member cannot
          // discover the parent needed to issue a new endorsed selection.
          // Existing target manifests were still tried; no empty selection
          // or refreshed completeness is inferred from this condition.
          if (error.reason != 'crypto_account_choices_parent_unavailable') {
            rethrow;
          }
          _checkEpoch(epoch);
        }
      }
      // A first personal payment needs a verified empty sidecar snapshot too.
      // `required` only becomes true once a linked financial fact exists.
      if (policy.linkedPaymentsRequired ||
          linkedPaymentsSupported &&
              policy.canWrite &&
              (scope.kind == SharedScopeKind.organization ||
                  scope.organizationId != null)) {
        failureStage = SyncFailureStage.linkedPayments;
        await _fetchLinkedPayments(
          PaymentSpaceRef(scope.id, partition: p),
          syncLease: true,
        );
        _checkEpoch(epoch);
      }
      await reviewed();
    } on CryptoAuthorityPending catch (error) {
      _checkEpoch(epoch);
      _captureSyncFailure(
        error,
        epoch: epoch,
        stage: failureStage,
        scopeId: scope.id,
      );
      _lastError ??= const CollaborationException(
        'crypto_reconciliation_required',
      );
    } on CollaborationApiException catch (e) {
      if (e.code != 'finance_forbidden' && e.code != 'permission_revoked') {
        _captureSyncFailure(
          e,
          epoch: epoch,
          stage: failureStage,
          scopeId: scope.id,
        );
      }
      if (const {
        'crypto_scope_head_missing',
        'crypto_migration_required',
        'crypto_device_keys_pending',
      }.contains(e.code)) {
        _checkEpoch(epoch);
        _lastError ??= const CollaborationException(
          'crypto_reconciliation_required',
        );
        return;
      }
      if (e.code != 'finance_forbidden' && e.code != 'permission_revoked') {
        rethrow;
      }
      await database.transaction(() async {
        _checkEpoch(epoch);
        await _validLease(p);
        _checkEpoch(epoch);
        await _storeFinancePolicy(p, scope.id, const SharedFinancePolicy());
        await reviewed();
      });
    } catch (error) {
      _captureSyncFailure(
        error,
        epoch: epoch,
        stage: failureStage,
        scopeId: scope.id,
      );
      rethrow;
    }
  }

  Future<void> _pushFinanceDependencies(
    DeviceSession session,
    int epoch,
    List<SharedScope> scopes,
  ) async {
    for (final scope in scopes) {
      if (!await _privateScopeAllowed(session.profile.partition, scope)) {
        continue;
      }
      // Full policy/aggregate verification is needed only when this preflight
      // can actually send a dependency. The ordinary finance pass still checks
      // current policy, and task-cost delivery checks its predecessors again.
      final dependencies = await database.rows(
        "SELECT 1 FROM finance_outbox f WHERE f.partition=? AND f.scope_id=? AND f.state='pending' AND json_extract(f.request,'\$.type') IN ('financeAccount','personalFinanceAccount','financeRecurrenceRule') AND NOT EXISTS(SELECT 1 FROM local_meta m WHERE m.name LIKE ? AND m.value=f.op_id) LIMIT 1",
        [
          session.profile.partition,
          scope.id,
          'task_cost_pair:${session.profile.partition}:%',
        ],
      );
      _checkEpoch(epoch);
      if (dependencies.isEmpty) continue;
      try {
        final policy = await _fetchFinancePolicy(
          session,
          epoch,
          scope.id,
          syncLease: true,
        );
        if (policy.canWrite) {
          await _pushFinanceScope(
            session,
            epoch,
            scope.id,
            dependenciesOnly: true,
          );
        }
      } on CryptoAuthorityPending catch (error) {
        _checkEpoch(epoch);
        _captureSyncFailure(
          error,
          epoch: epoch,
          stage: SyncFailureStage.financeUpload,
          scopeId: scope.id,
        );
        _lastError ??= const CollaborationException(
          'crypto_reconciliation_required',
        );
      } on CollaborationApiException catch (error) {
        _captureSyncFailure(
          error,
          epoch: epoch,
          stage: SyncFailureStage.financeUpload,
          scopeId: scope.id,
        );
        if (!const {
          'crypto_scope_head_missing',
          'crypto_migration_required',
          'crypto_device_keys_pending',
        }.contains(error.code))
          rethrow;
        _checkEpoch(epoch);
        _lastError ??= const CollaborationException(
          'crypto_reconciliation_required',
        );
      }
    }
  }

  Future<void> _pushFinancePredecessors(
    DeviceSession session,
    int epoch,
    String scope,
    String financeRecordId,
    int beforeSequence,
  ) async {
    final p = session.profile.partition;
    final policy = await _fetchFinancePolicy(
      session,
      epoch,
      scope,
      syncLease: true,
    );
    if (!policy.canWrite) {
      throw const CollaborationException('finance_forbidden');
    }
    await _pushFinanceScope(
      session,
      epoch,
      scope,
      recordId: financeRecordId,
      beforeSequence: beforeSequence,
    );
    final pending = await database.rows(
      'SELECT op_id FROM finance_outbox WHERE partition=? AND scope_id=? AND record_id=? AND sequence<? LIMIT 1',
      [p, scope, financeRecordId, beforeSequence],
    );
    if (pending.isNotEmpty) {
      throw const CollaborationException('changes_blocked');
    }
  }

  Future<void> _pushFinanceScope(
    DeviceSession session,
    int epoch,
    String scope, {
    bool dependenciesOnly = false,
    String? recordId,
    int? beforeSequence,
  }) async {
    if (!_sharedUploadsAllowed &&
        !await _isPersonalScope(session.profile.partition, scope)) {
      return;
    }
    final p = session.profile.partition;
    while (true) {
      await _renewLease(p);
      final rows = await database.rows(
        "SELECT f.* FROM finance_outbox f WHERE partition=? AND scope_id=? AND state='pending' AND NOT EXISTS(SELECT 1 FROM local_meta m WHERE m.name LIKE ? AND m.value=f.op_id) ${dependenciesOnly ? "AND json_extract(f.request,'\$.type') IN ('financeAccount','personalFinanceAccount','financeRecurrenceRule')" : ''} ${recordId == null ? '' : 'AND f.record_id=?'} ${beforeSequence == null ? '' : 'AND f.sequence<?'} ORDER BY sequence LIMIT 1",
        [
          p,
          scope,
          'task_cost_pair:$p:%',
          if (recordId != null) recordId,
          if (beforeSequence != null) beforeSequence,
        ],
      );
      if (rows.isEmpty) return;
      final op = rows.first;
      try {
        final wireVersion = op['wire_version'] as int? ?? 1;
        if (wireVersion > _financeContractVersion) {
          throw const CollaborationException('unsupported_version');
        }
        final reply =
            await _callSession(session, epoch, '$_financeNamespace.push', {
              'scopeId': scope,
              'operation': CollaborationRepository._map(op['request']),
              if (_financeContractVersion >= 2)
                'operationContractVersion': wireVersion,
            });
        final canonical = _financeCanonical(reply['record']);
        if (reply['status'] != 'applied' ||
            canonical['id'] != op['record_id']) {
          throw const CollaborationException('invalid_response');
        }
        await database.transaction(() async {
          _checkEpoch(epoch);
          await _validLease(p);
          _checkEpoch(epoch);
          await database.execute(
            'DELETE FROM finance_outbox WHERE partition=? AND op_id=?',
            [p, op['op_id']],
          );
          await _applyFinanceRemote(p, scope, canonical);
        });
      } on CollaborationApiException catch (e) {
        if (e.code == 'finance_forbidden' || e.code == 'scope_archived') {
          _captureSyncFailure(
            e,
            epoch: epoch,
            stage: SyncFailureStage.financeUpload,
            scopeId: scope,
          );
          await _fetchFinancePolicy(session, epoch, scope, syncLease: true);
          await database.transaction(() async {
            _checkEpoch(epoch);
            await _validLease(p);
            _checkEpoch(epoch);
            await _blockFinanceWrites(p, scope);
          });
          return;
        }
        if (!const [
          'conflict',
          'parent_missing',
          'live_children',
          'currency_mismatch',
          'person_not_member',
          'finance_account_missing',
          'finance_account_parent_required',
          'assignee_not_member',
          'validation_error',
          'unsupported_currency',
          'opening_balance_immutable',
          'created_at_immutable',
          'same_transfer_account',
          'duplicate_finance_reference',
          'task_cost_date_mismatch',
        ].contains(e.code)) {
          rethrow;
        }
        if (e.code == 'duplicate_finance_reference' &&
            e.details['existingRecord'] != null) {
          final existing = _financeCanonical(e.details['existingRecord']);
          await database.transaction(() async {
            _checkEpoch(epoch);
            await _validLease(p);
            _checkEpoch(epoch);
            final reconciled = await reconcilePrivateFinanceDuplicate(
              database,
              p,
              scope,
              op['record_id'] as String,
              existing,
            );
            if (reconciled) {
              await database.execute(
                'DELETE FROM finance_outbox WHERE partition=? AND op_id=?',
                [p, op['op_id']],
              );
            } else {
              _captureSyncFailure(
                e,
                epoch: epoch,
                stage: SyncFailureStage.financeUpload,
                scopeId: scope,
              );
              await database.execute(
                "UPDATE finance_outbox SET state='conflict' WHERE partition=? AND scope_id=? AND record_id=?",
                [p, scope, op['record_id']],
              );
              await database.execute(
                'INSERT OR REPLACE INTO finance_conflicts(id,partition,scope_id,record_id,type,reason,remote) VALUES(?,?,?,?,?,?,NULL)',
                [
                  op['op_id'],
                  p,
                  scope,
                  op['record_id'],
                  CollaborationRepository._map(op['request'])['type'],
                  'duplicate_finance_reference',
                ],
              );
            }
            await _applyFinanceRemote(p, scope, existing);
          });
          continue;
        }
        final canonical = e.details['serverRecord'] == null
            ? null
            : _financeCanonical(e.details['serverRecord']);
        if (e.code != 'conflict') {
          _captureSyncFailure(
            e,
            epoch: epoch,
            stage: SyncFailureStage.financeUpload,
            scopeId: scope,
          );
        }
        await database.transaction(() async {
          _checkEpoch(epoch);
          await _validLease(p);
          _checkEpoch(epoch);
          await database.execute(
            "UPDATE finance_outbox SET state='conflict' WHERE partition=? AND scope_id=? AND record_id=?",
            [p, scope, op['record_id']],
          );
          await database.execute(
            'INSERT OR REPLACE INTO finance_conflicts(id,partition,scope_id,record_id,type,reason,remote) VALUES(?,?,?,?,?,?,?)',
            [
              op['op_id'],
              p,
              scope,
              op['record_id'],
              CollaborationRepository._map(op['request'])['type'],
              canonical?['deleted'] == true ? 'record_deleted' : e.code,
              canonical == null ? null : jsonEncode(canonical),
            ],
          );
        });
      }
    }
  }

  Future<void> _pullFinanceScope(
    DeviceSession session,
    int epoch,
    String scope,
  ) async {
    final p = session.profile.partition;
    for (var attempt = 0; attempt < 2; attempt++) {
      final rows = await database.rows(
        'SELECT finance_cursor,finance_access_revision FROM scopes WHERE partition=? AND id=?',
        [p, scope],
      );
      var cursor = rows.first['finance_cursor'] as int,
          access = rows.first['finance_access_revision'] as int;
      try {
        var more = true;
        while (more) {
          await _renewLease(p);
          final reply =
              await _callSession(session, epoch, '$_financeNamespace.pull', {
                'scopeId': scope,
                'cursor': cursor,
                if (cursor > 0 || access > 0) 'accessRevision': access,
                'limit': 100,
              });
          final next = readInt(reply, 'cursor'),
              revision = readInt(reply, 'accessRevision');
          more = readBool(reply, 'hasMore');
          if (next < cursor ||
              (more && next == cursor) ||
              cursor > 0 && revision != access) {
            throw const CollaborationException('invalid_response');
          }
          cursor = next;
          access = revision;
          final canonical = (reply['records'] as List)
              .map(_financeCanonical)
              .toList();
          await database.transaction(() async {
            _checkEpoch(epoch);
            await _validLease(p);
            _checkEpoch(epoch);
            for (final record in canonical) {
              await _applyFinanceRemote(p, scope, record);
            }
            if (_organizationFinanceSupported) {
              final policy = await _cachedFinancePolicy(p, scope);
              await _storeFinancePolicy(
                p,
                scope,
                SharedFinancePolicy.fromJson({
                  ...policy.toJson(),
                  'organizationFinanceComplete':
                      reply['organizationFinanceComplete'] == true,
                  'organizationFinanceScopeIds':
                      reply['organizationFinanceScopeIds'] ?? <String>[],
                  'organizationFinanceSequences':
                      reply['organizationFinanceSequences'] ?? <String, int>{},
                }),
              );
            }
            await database.execute(
              'UPDATE scopes SET finance_cursor=?,finance_access_revision=?,finance_complete=? WHERE partition=? AND id=?',
              [
                cursor,
                access,
                more || reply['cryptoProjectionComplete'] == false ? 0 : 1,
                p,
                scope,
              ],
            );
          });
        }
        return;
      } on CollaborationApiException catch (e) {
        if (e.code != 'finance_access_changed') {
          if (e.code != 'finance_forbidden' && e.code != 'permission_revoked') {
            _captureSyncFailure(
              e,
              epoch: epoch,
              stage: SyncFailureStage.financeDownload,
              scopeId: scope,
            );
          }
          rethrow;
        }
        await database.transaction(() async {
          _checkEpoch(epoch);
          await _validLease(p);
          _checkEpoch(epoch);
          await _resetFinanceProjection(p, scope);
        });
        await refreshLocal();
        final policy = await _fetchFinancePolicy(
          session,
          epoch,
          scope,
          syncLease: true,
        );
        if (!policy.canRead) return;
      }
    }
    throw const CollaborationException('finance_access_changed');
  }

  Future<void> resumeBlockedFinanceChanges(String scopeId) async {
    final session = _requireSession(), epoch = _epoch;
    final policy = await refreshFinancePolicy(scopeId);
    _checkEpoch(epoch);
    if (!policy.canWrite) {
      throw const CollaborationException('finance_forbidden');
    }
    await database.transaction(() async {
      _checkEpoch(epoch);
      await database.execute(
        'UPDATE scopes SET finance_blocked=0 WHERE partition=? AND id=?',
        [session.profile.partition, scopeId],
      );
      await database.execute(
        "UPDATE finance_outbox SET state='pending' WHERE partition=? AND scope_id=? AND state='blocked'",
        [session.profile.partition, scopeId],
      );
    });
    final prefix = 'task_cost_pair:${session.profile.partition}:';
    await database.transaction(() async {
      _checkEpoch(epoch);
      await database.execute(
        "UPDATE outbox SET state='pending' WHERE partition=? AND scope_id=? AND state='blocked' AND op_id IN (SELECT substr(name,?) FROM local_meta WHERE name LIKE ? AND value IN(SELECT op_id FROM finance_outbox WHERE partition=? AND scope_id=? AND state='pending'))",
        [
          session.profile.partition,
          scopeId,
          prefix.length + 1,
          '$prefix%',
          session.profile.partition,
          scopeId,
        ],
      );
    });
    await syncNow();
  }

  Future<void> resolveFinanceConflict({
    required String conflictId,
    required bool keepLocal,
  }) async {
    final session = _requireSession(),
        epoch = _epoch,
        p = session.profile.partition;
    final prefix = 'task_cost_pair:$p:';
    final pairs = await database.rows(
      'SELECT m.name,o.scope_id FROM local_meta m JOIN finance_outbox o ON o.op_id=m.value AND o.partition=? WHERE substr(m.name,1,?)=? AND m.value=?',
      [p, prefix.length, prefix, conflictId],
    );
    _checkEpoch(epoch);
    if (pairs.isNotEmpty) {
      final scope = pairs.single['scope_id'] as String;
      final visibility = await database.rows(
        'SELECT data,blocked,finance_blocked,finance_complete FROM scopes WHERE partition=? AND id=?',
        [p, scope],
      );
      final policy = await _cachedFinancePolicy(p, scope);
      _checkEpoch(epoch);
      if (!policy.canRead ||
          visibility.isEmpty ||
          visibility.single['finance_complete'] != 1 ||
          SharedScope.fromJson(
            CollaborationRepository._map(visibility.single['data']),
          ).revoked) {
        throw const CollaborationException('finance_forbidden');
      }
      final genericId = (pairs.single['name'] as String).substring(
        prefix.length,
      );
      if (await _resolvePairedTaskCostConflict(
        conflictId: genericId,
        keepLocal: keepLocal,
        financialReview: true,
      )) {
        return;
      }
      throw const CollaborationException('conflict_missing');
    }
    await database.transaction(() async {
      _checkEpoch(epoch);
      final rows = await database.rows(
        'SELECT * FROM finance_conflicts WHERE partition=? AND id=?',
        [p, conflictId],
      );
      if (rows.isEmpty) throw const CollaborationException('conflict_missing');
      final conflict = rows.first,
          scope = conflict['scope_id'] as String,
          id = conflict['record_id'] as String;
      await _financeWritable(p, scope);
      final candidate = (await database.rows(
        'SELECT * FROM finance_records WHERE partition=? AND scope_id=? AND id=?',
        [p, scope, id],
      )).first;
      var remote = conflict['remote'] == null
          ? null
          : _financeCanonical(CollaborationRepository._map(conflict['remote']));
      final freshest = candidate['remote'] == null
          ? null
          : _financeCanonical(
              CollaborationRepository._map(candidate['remote']),
            );
      if (freshest != null &&
          (remote == null ||
              (freshest['revision'] as int) >= (remote['revision'] as int))) {
        remote = freshest;
      }
      final versions = await database.rows(
        'SELECT wire_version FROM finance_outbox WHERE partition=? AND scope_id=? AND record_id=? ORDER BY sequence DESC LIMIT 1',
        [p, scope, id],
      );
      final candidateVersion = versions.isEmpty
          ? 1
          : (versions.first['wire_version'] as int? ?? 1);
      final resolveVersion = _financeContractVersion;
      if (resolveVersion < (remote?['contractVersion'] as int? ?? 1)) {
        throw const CollaborationException('unsupported_version');
      }
      Map<String, dynamic>? resolvedPayload = candidate['payload'] == null
          ? null
          : CollaborationRepository._map(candidate['payload']);
      if (keepLocal && resolvedPayload != null) {
        if (candidateVersion < 3 &&
            remote?['payload'] is Map &&
            ((remote!['payload'] as Map)['accountScopeId'] != null ||
                (remote['payload'] as Map)['projectId'] != null)) {
          throw const CollaborationException('requires_remote_resolution');
        }
        if (candidateVersion == 1 &&
            (remote?['contractVersion'] as int? ?? 1) >= 2 &&
            remote?['payload'] is Map) {
          final fresh = Map<String, dynamic>.from(remote!['payload'] as Map);
          resolvedPayload = {...fresh, ...resolvedPayload};
          if (fresh['paidAt'] != null) {
            resolvedPayload['occurredAt'] = fresh['occurredAt'];
          }
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
            'openingBalanceAt',
            'archived',
          ]) {
            if (fresh.containsKey(key)) resolvedPayload[key] = fresh[key];
          }
        }
        resolvedPayload = financePayloadForContract(
          SharedFinanceRecordType.values.byName(candidate['type'] as String),
          resolvedPayload,
          resolveVersion,
        );
        validateSharedFinancePayload(
          SharedFinanceRecordType.values.byName(candidate['type'] as String),
          resolvedPayload,
          contractVersion: resolveVersion,
        );
      }
      if (keepLocal && remote?['deleted'] == true) {
        throw const CollaborationException('record_deleted');
      }
      if (keepLocal && conflict['reason'] != 'conflict') {
        throw const CollaborationException('requires_remote_resolution');
      }
      await database.execute(
        'DELETE FROM finance_outbox WHERE partition=? AND scope_id=? AND record_id=?',
        [p, scope, id],
      );
      await database.execute(
        'DELETE FROM finance_conflicts WHERE partition=? AND scope_id=? AND record_id=?',
        [p, scope, id],
      );
      final revision = remote?['revision'] ?? 0;
      await database.execute(
        'UPDATE finance_records SET server_revision=?,local_revision=local_revision+1,remote=? WHERE partition=? AND scope_id=? AND id=?',
        [revision, remote == null ? null : jsonEncode(remote), p, scope, id],
      );
      if (keepLocal) {
        final request = {
          'opId': newSharedId(),
          'recordId': id,
          'type': candidate['type'],
          'expectedRevision': revision,
          'deleted': candidate['deleted'] == 1,
          'payload': resolvedPayload,
        };
        await database.execute(
          'INSERT INTO finance_outbox(op_id,partition,scope_id,record_id,request,wire_version) VALUES(?,?,?,?,?,?)',
          [request['opId'], p, scope, id, jsonEncode(request), resolveVersion],
        );
        await database.execute(
          'UPDATE finance_records SET payload=? WHERE partition=? AND scope_id=? AND id=?',
          [
            resolvedPayload == null ? null : jsonEncode(resolvedPayload),
            p,
            scope,
            id,
          ],
        );
      } else {
        await database.execute(
          'UPDATE finance_records SET payload=?,deleted=? WHERE partition=? AND scope_id=? AND id=?',
          [
            remote?['payload'] == null ? null : jsonEncode(remote!['payload']),
            remote == null || remote['deleted'] == true ? 1 : 0,
            p,
            scope,
            id,
          ],
        );
      }
    });
    await refreshLocal();
  }
}
