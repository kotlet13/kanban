part of 'collaboration_repository.dart';

/// Financial writes use a distinct local store, queue and module authorization.
extension CollaborationFinanceActions on CollaborationRepository {
  DateTime _financeUpdatedAt(DateTime previous) {
    final now = clock().toUtc();
    return now.isBefore(previous) ? previous : now;
  }

  Future<SharedFinancePolicy> _cachedFinancePolicy(
    String partition,
    String scopeId,
  ) async {
    final rows = await database.rows(
      'SELECT finance_policy FROM scopes WHERE partition=? AND id=?',
      [partition, scopeId],
    );
    return rows.isEmpty || rows.first['finance_policy'] == null
        ? const SharedFinancePolicy()
        : SharedFinancePolicy.fromJson(
            CollaborationRepository._map(rows.first['finance_policy']),
          );
  }

  Future<int> _financeAccessGeneration(String partition, String scopeId) async {
    final rows = await database.rows(
      'SELECT value FROM local_meta WHERE name=?',
      ['finance_access_generation:$partition:$scopeId'],
    );
    return rows.isEmpty ? 0 : int.parse(rows.first['value'] as String);
  }

  Future<SharedFinancePolicy> _fetchFinancePolicy(
    DeviceSession session,
    int epoch,
    String scopeId, {
    bool syncLease = false,
  }) async {
    final partition = session.profile.partition;
    final generation = await _financeAccessGeneration(partition, scopeId);
    _checkEpoch(epoch);
    final router = cryptoRouter;
    var policyOnly = false;
    late final SharedFinancePolicy policy;
    try {
      Future<Map<String, dynamic>> read() => _callSession(
        session,
        epoch,
        '$_financeNamespace.policy',
        {'scopeId': scopeId},
      );
      Map<String, dynamic> reply;
      if (syncLease && router is CryptoFinancePolicyReadContext) {
        final result = await (router as CryptoFinancePolicyReadContext)
            .withFinancePolicyOnly(read);
        policyOnly = result.policyOnly;
        reply = result.value;
      } else {
        reply = await read();
      }
      policy = SharedFinancePolicy.fromJson(reply);
    } on CollaborationApiException catch (error) {
      if (syncLease &&
          error.code != 'finance_forbidden' &&
          error.code != 'permission_revoked') {
        _captureSyncFailure(
          error,
          epoch: epoch,
          stage: SyncFailureStage.financePolicy,
          scopeId: scopeId,
        );
      }
      if (error.code == 'finance_forbidden' ||
          error.code == 'permission_revoked') {
        // Every policy fetch, including dependency preflight, must invalidate
        // cached reads when the server gives a definitive financial denial.
        await database.transaction(() async {
          _checkEpoch(epoch);
          if (syncLease) await _validLease(partition);
          _checkEpoch(epoch);
          await _storeFinancePolicy(
            partition,
            scopeId,
            const SharedFinancePolicy(),
          );
        });
        await refreshLocal();
        _checkEpoch(epoch);
      }
      rethrow;
    }
    return database.transaction(() async {
      _checkEpoch(epoch);
      if (syncLease) await _validLease(partition);
      _checkEpoch(epoch);
      if (generation != await _financeAccessGeneration(partition, scopeId)) {
        if (policyOnly) {
          // A concurrent permission change must not turn a previously cached
          // canWrite into the result of this fresh background authorization.
          throw const CryptoAuthorityPending(
            'finance_policy_changed_during_read',
          );
        }
      } else {
        var stored = policy;
        if (policyOnly && policy.canRead) {
          final previous = await _cachedFinancePolicy(partition, scopeId);
          final sameAuthorization =
              previous.enabled == policy.enabled &&
              previous.grant == policy.grant &&
              previous.revision == policy.revision &&
              previous.requiredContractVersion ==
                  policy.requiredContractVersion &&
              previous.managedByOrganizationPolicy ==
                  policy.managedByOrganizationPolicy &&
              previous.readAccessFromMembership ==
                  policy.readAccessFromMembership &&
              previous.linkedPaymentsRequired == policy.linkedPaymentsRequired;
          if (sameAuthorization) {
            // Retain only the OLD verified aggregate. The ordinary finance
            // pull still has to establish fresh coverage before sync succeeds.
            stored = SharedFinancePolicy.fromJson({
              ...policy.toJson(),
              'organizationFinanceComplete':
                  previous.organizationFinanceComplete,
              'organizationFinanceScopeIds':
                  previous.organizationFinanceScopeIds,
              'organizationFinanceSequences':
                  previous.organizationFinanceSequences,
            });
          }
        }
        await _storeFinancePolicy(partition, scopeId, stored);
      }
      _checkEpoch(epoch);
      return _cachedFinancePolicy(partition, scopeId);
    });
  }

  Future<void> _storeFinancePolicy(
    String partition,
    String scopeId,
    SharedFinancePolicy policy,
  ) async {
    final old = await _cachedFinancePolicy(partition, scopeId);
    if (policy.enabled && policy.revision < old.revision) return;
    final deniedWithoutRevision = !policy.canRead && policy.revision == 0;
    if (deniedWithoutRevision && old.revision > 0) {
      policy = SharedFinancePolicy(
        enabled: policy.enabled,
        grant: policy.grant,
        revision: old.revision,
        managedByOrganizationPolicy: policy.managedByOrganizationPolicy,
        readAccessFromMembership: policy.readAccessFromMembership,
        linkedPaymentsRequired: policy.linkedPaymentsRequired,
        requiredContractVersion: old.requiredContractVersion,
        organizationFinanceComplete: false,
        organizationFinanceScopeIds: const [],
        organizationFinanceSequences: const {},
      );
    }
    if (deniedWithoutRevision ||
        old.requiredContractVersion != policy.requiredContractVersion ||
        jsonEncode(old.organizationFinanceSequences) !=
            jsonEncode(policy.organizationFinanceSequences) ||
        old.organizationFinanceComplete != policy.organizationFinanceComplete ||
        jsonEncode(old.organizationFinanceScopeIds) !=
            jsonEncode(policy.organizationFinanceScopeIds) ||
        old.enabled != policy.enabled ||
        old.grant != policy.grant ||
        old.linkedPaymentsRequired != policy.linkedPaymentsRequired ||
        old.revision != policy.revision) {
      final generation = await _financeAccessGeneration(partition, scopeId);
      await database.execute(
        'INSERT INTO local_meta(name,value) VALUES(?,?) ON CONFLICT(name) DO UPDATE SET value=excluded.value',
        ['finance_access_generation:$partition:$scopeId', '${generation + 1}'],
      );
    }
    // Explicit denials preserve the monotonic revision floor.
    await database.execute(
      'UPDATE scopes SET finance_policy=? WHERE partition=? AND id=?',
      [jsonEncode(policy.toJson()), partition, scopeId],
    );
    if (!policy.canRead) {
      await _hideFinance(partition, scopeId);
    } else {
      if (!policy.canWrite && old.canWrite) {
        await _blockFinanceWrites(partition, scopeId);
      }
      if (old.canRead && old.revision != policy.revision) {
        // Access epochs may change because another member's rights changed.
        // Rebuild the authorized projection, retaining our own pending intent.
        await _resetFinanceProjection(partition, scopeId);
      }
    }
  }

  Future<void> _blockFinanceWrites(String p, String scope) async {
    await database.execute(
      "UPDATE finance_outbox SET state='blocked' WHERE partition=? AND scope_id=? AND state='pending'",
      [p, scope],
    );
    await database.execute(
      'UPDATE scopes SET finance_blocked=1 WHERE partition=? AND id=?',
      [p, scope],
    );
  }

  Future<void> _hideFinance(String partition, String scopeId) async {
    await _clearFinanceAccountChoices(partition, scopeId);
    // Retain only explicitly unsent candidates, never expose them without a grant.
    await database.execute(
      "UPDATE finance_outbox SET state='blocked' WHERE partition=? AND scope_id=? AND state='pending'",
      [partition, scopeId],
    );
    await database.execute(
      'DELETE FROM finance_records WHERE partition=? AND scope_id=? AND id NOT IN(SELECT record_id FROM finance_outbox WHERE partition=? AND scope_id=?)',
      [partition, scopeId, partition, scopeId],
    );
    await database.execute(
      'UPDATE finance_records SET remote=NULL WHERE partition=? AND scope_id=?',
      [partition, scopeId],
    );
    await database.execute(
      'UPDATE finance_conflicts SET remote=NULL WHERE partition=? AND scope_id=?',
      [partition, scopeId],
    );
    await database.execute(
      'UPDATE scopes SET finance_cursor=0,finance_access_revision=0,finance_complete=0,finance_blocked=1 WHERE partition=? AND id=?',
      [partition, scopeId],
    );
    await database.execute(
      r"UPDATE commands SET state='blocked' WHERE partition=? AND (json_extract(params,'$.scopeId')=? AND json_extract(params,'$.targetType')='financeEntry' OR json_extract(params,'$.id') IN(SELECT id FROM scheduled_reminders WHERE partition=? AND scope_id=? AND json_extract(data,'$.targetType')='financeEntry'))",
      [partition, scopeId, partition, scopeId],
    );
    await database.execute(
      r"DELETE FROM local_meta WHERE (name LIKE ? OR name LIKE ?) AND json_extract(value,'$.scopeId')=? AND json_extract(value,'$.category')='finance'",
      ['push_reference:$partition:%', 'push_group:$partition:%', scopeId],
    );
    await database.execute(
      r"DELETE FROM inbox WHERE partition=? AND json_extract(data,'$.scopeId')=? AND json_extract(data,'$.category')='finance'",
      [partition, scopeId],
    );
  }

  Future<void> _financeWritable(String partition, String scopeId) async {
    await _requireScopeReconciled(partition, scopeId);
    final sharing = await database.rows(
      r"SELECT 1 FROM local_meta WHERE name=? OR (name LIKE ? AND json_extract(value,'$.projectId')=?)",
      [
        'project_sharing_pending:$partition:$scopeId',
        'project_sharing_pending:$partition:%',
        scopeId,
      ],
    );
    if (sharing.isNotEmpty) {
      throw const CollaborationException('project_sharing_pending_changes');
    }
    if (!_financeSupported) {
      throw const CollaborationException('feature_disabled');
    }
    final rows = await database.rows(
      'SELECT data,finance_blocked FROM scopes WHERE partition=? AND id=?',
      [partition, scopeId],
    );
    if (rows.isEmpty ||
        SharedScope.fromJson(
          CollaborationRepository._map(rows.first['data']),
        ).revoked) {
      throw const CollaborationException('permission_revoked');
    }
    if (SharedScope.fromJson(
      CollaborationRepository._map(rows.first['data']),
    ).archived) {
      throw const CollaborationException('scope_archived');
    }
    final policy = await _cachedFinancePolicy(partition, scopeId);
    if (policy.requiredContractVersion > _financeContractVersion) {
      throw const CollaborationException('unsupported_version');
    }
    if (!policy.canWrite) {
      throw const CollaborationException('finance_forbidden');
    }
    final pending = await database.rows(
      "SELECT op_id FROM finance_outbox WHERE partition=? AND scope_id=? AND state='blocked' LIMIT 1",
      [partition, scopeId],
    );
    if (rows.first['finance_blocked'] == 1 && pending.isNotEmpty) {
      throw const CollaborationException('changes_blocked');
    }
  }

  Future<void> _editFinance(
    String scopeId,
    Future<void> Function(String) action,
  ) async {
    final session = _requireSession(), epoch = _epoch;
    await requireVerifiedEmailForConnectedEntry();
    _checkEpoch(epoch);
    await database.transaction(() async {
      _checkEpoch(epoch);
      await _financeWritable(session.profile.partition, scopeId);
      await action(session.profile.partition);
    });
    await refreshLocal();
  }

  Future<void> _putFinance(
    String partition,
    String scopeId,
    SharedFinanceRecordType type,
    String id,
    Map<String, Object?>? payload, {
    bool deleted = false,
    int? expectedLocalRevision,
  }) async {
    if (!isSharedUuid(id)) {
      throw const CollaborationException('validation_error');
    }
    final linked = (await database.rows(
      "SELECT event_id FROM linked_payment_events WHERE space_key=? AND json_extract(data,'\$.sourceEntryId')=?",
      ['remote:$partition:$scopeId', id],
    )).isNotEmpty;
    final rows = await database.rows(
      'SELECT * FROM finance_records WHERE partition=? AND scope_id=? AND id=?',
      [partition, scopeId, id],
    );
    final old = rows.isEmpty ? null : rows.first;
    await _requireRecordAuthor(
      partition,
      scopeId,
      type.name,
      id,
      old: old,
      payload: payload == null ? null : Map<String, dynamic>.from(payload),
      deleted: deleted,
      domain: 'finance',
    );

    if (old != null && (old['type'] != type.name || old['deleted'] == 1)) {
      throw const CollaborationException('record_deleted');
    }
    if (deleted && old == null) {
      throw const CollaborationException('record_missing');
    }
    if (expectedLocalRevision != null &&
        (old == null || old['local_revision'] != expectedLocalRevision)) {
      throw const CollaborationException('stale_edit');
    }
    final previous = old?['payload'] == null
        ? null
        : CollaborationRepository._map(old!['payload']);
    if (linked) {
      if (deleted ||
          payload == null ||
          previous == null ||
          !paymentFinancialFactsMatch(previous, payload)) {
        throw const CollaborationException('linked_payment_source_locked');
      }
    }
    if (_financeContractVersion < 3 &&
        (previous?['accountScopeId'] != null ||
            previous?['projectId'] != null)) {
      throw const CollaborationException('unsupported_version');
    }
    if (payload != null) {
      validateSharedFinancePayload(
        type,
        Map<String, dynamic>.from(payload),
        contractVersion: _financeContractVersion,
      );
      if (previous != null) {
        if (readSharedDate(previous, 'createdAt') !=
            readSharedDate(Map<String, dynamic>.from(payload), 'createdAt')) {
          throw const CollaborationException('validation_error');
        }
        payload['createdAt'] = previous['createdAt'];
      }
      if (_financeContractVersion == 1 &&
          type == SharedFinanceRecordType.financeAccount &&
          previous != null &&
          (previous['currency'] != payload['currency'] ||
              previous['openingBalanceMinor'] !=
                  payload['openingBalanceMinor'])) {
        throw const CollaborationException('finance_account_immutable');
      }
      final accountIds = switch (type) {
        SharedFinanceRecordType.financeAccount => <String>[],
        SharedFinanceRecordType.personalFinanceEntry ||
        SharedFinanceRecordType.personalFinanceAccount ||
        SharedFinanceRecordType.financeRecurrenceRule => <String>[],
        SharedFinanceRecordType.financeEntry => [
          payload['accountId'] as String,
        ],
        SharedFinanceRecordType.financeTransfer => [
          payload['fromAccountId'] as String,
          payload['toAccountId'] as String,
        ],
      };
      final accountScopeId = payload['accountScopeId'];
      if (accountScopeId != null) {
        final sourceScope = await _financeStoredScope(partition, scopeId);
        if (!_organizationFinanceSupported ||
            sourceScope?.kind != SharedScopeKind.project ||
            sourceScope?.parentSpaceId != accountScopeId) {
          throw const CollaborationException('finance_account_missing');
        }
        final choices = await _cachedFinanceAccountChoices(partition, scopeId);
        final choiceMatches = choices.any(
          (a) =>
              a.scopeId == accountScopeId &&
              a.id == payload['accountId'] &&
              a.currency == payload['currency'] &&
              (!a.archived ||
                  previous?['accountScopeId'] == accountScopeId &&
                      previous?['accountId'] == a.id),
        );
        if (!choiceMatches) {
          final parent = await _financeStoredScope(
            partition,
            accountScopeId as String,
          );
          final policy = await _cachedFinancePolicy(partition, accountScopeId);
          final accounts = await database.rows(
            "SELECT payload FROM finance_records WHERE partition=? AND scope_id=? AND id=? AND type='financeAccount' AND deleted=0",
            [partition, accountScopeId, payload['accountId']],
          );
          final account = accounts.isEmpty
              ? null
              : CollaborationRepository._map(accounts.single['payload']);
          if (parent == null ||
              parent.revoked ||
              parent.deleted ||
              !parent.canRead ||
              !policy.canRead ||
              account?['currency'] != payload['currency'] ||
              account?['archived'] == true &&
                  (previous?['accountScopeId'] != accountScopeId ||
                      previous?['accountId'] != payload['accountId'])) {
            throw const CollaborationException('finance_account_missing');
          }
        }
      }
      if (accountScopeId != null && payload['recurrenceRuleId'] != null) {
        throw const CollaborationException('validation_error');
      }
      final projectId = payload['projectId'];
      if (type == SharedFinanceRecordType.financeEntry && projectId != null) {
        final sourceScope = await _financeStoredScope(partition, scopeId);
        final project = await database.rows(
          "SELECT id FROM records WHERE partition=? AND scope_id=? AND id=? AND type='project' AND deleted=0",
          [partition, scopeId, projectId],
        );
        if (sourceScope?.kind == SharedScopeKind.project || project.isEmpty) {
          throw const CollaborationException('parent_missing');
        }
      }
      for (final accountId
          in accountScopeId == null ? accountIds : <String>[]) {
        final account = await database.rows(
          "SELECT payload FROM finance_records WHERE partition=? AND scope_id=? AND id=? AND type='financeAccount' AND deleted=0",
          [partition, scopeId, accountId],
        );
        if (account.isEmpty ||
            CollaborationRepository._map(
                  account.first['payload'],
                )['currency'] !=
                payload['currency']) {
          throw const CollaborationException('finance_account_missing');
        }
      }
      for (final field in [
        'ownerAccountId',
        'payerAccountId',
        'recipientAccountId',
      ]) {
        final person = payload[field];
        if (person == null || previous?[field] == person) continue;
        final member = await database.rows(
          'SELECT data FROM members WHERE partition=? AND scope_id=? AND account_id=?',
          [partition, scopeId, person],
        );
        if (member.isEmpty ||
            !SharedMember.fromJson(
              CollaborationRepository._map(member.first['data']),
            ).active) {
          throw const CollaborationException('person_not_member');
        }
      }
    }
    if (deleted && type == SharedFinanceRecordType.financeAccount) {
      final refs = await database.rows(
        r"SELECT id FROM finance_records WHERE partition=? AND scope_id=? AND deleted=0 AND (json_extract(payload,'$.accountId')=? OR json_extract(payload,'$.fromAccountId')=? OR json_extract(payload,'$.toAccountId')=?) LIMIT 1",
        [partition, scopeId, id, id, id],
      );
      if (refs.isNotEmpty) {
        throw const CollaborationException('finance_live_references');
      }
    }
    final queue = await database.rows(
      'SELECT state FROM finance_outbox WHERE partition=? AND scope_id=? AND record_id=?',
      [partition, scopeId, id],
    );
    if (queue.any((r) => r['state'] != 'pending')) {
      throw const CollaborationException('changes_blocked');
    }
    await _reconcileLocalReminders(
      partition,
      scopeId,
      type.name,
      id,
      previous,
      payload == null ? null : Map<String, dynamic>.from(payload),
      deleted,
    );
    final request = {
      'opId': newSharedId(),
      'recordId': id,
      'type': type.name,
      'expectedRevision':
          ((old?['server_revision'] as int?) ?? 0) + queue.length,
      'deleted': deleted,
      'payload': payload,
    };
    await database.execute(
      'INSERT INTO finance_records(partition,scope_id,id,type,local_revision,server_revision,payload,deleted) VALUES(?,?,?,?,?,?,?,?) ON CONFLICT(partition,scope_id,id) DO UPDATE SET local_revision=excluded.local_revision,payload=excluded.payload,deleted=excluded.deleted',
      [
        partition,
        scopeId,
        id,
        type.name,
        ((old?['local_revision'] as int?) ?? 0) + 1,
        (old?['server_revision'] as int?) ?? 0,
        payload == null ? null : jsonEncode(payload),
        deleted ? 1 : 0,
      ],
    );
    await database.execute(
      'INSERT INTO finance_outbox(op_id,partition,scope_id,record_id,request,wire_version) VALUES(?,?,?,?,?,?)',
      [
        request['opId'],
        partition,
        scopeId,
        id,
        jsonEncode(request),
        _financeContractVersion,
      ],
    );
  }

  Future<void> enableFinance(String scopeId, bool enabled) async {
    final session = _requireSession(), epoch = _epoch;
    await _callSession(session, epoch, 'finance.enable', {
      'scopeId': scopeId,
      'enabled': enabled,
      'requestId': newSharedId(),
    });
    await refreshFinancePolicy(scopeId);
    await syncNow();
  }

  Future<Map<String, SharedFinanceGrant>> financeGrants(String scopeId) async {
    final reply = await _call('finance.grants', {'scopeId': scopeId});
    return Map.unmodifiable({
      for (final item in reply['grants'] as List)
        (item as Map)['accountId'] as String: SharedFinanceGrant.values.byName(
          item['grant'] as String,
        ),
    });
  }

  Future<void> grantFinance({
    required String scopeId,
    required String accountId,
    required SharedFinanceGrant grant,
  }) async {
    final session = _requireSession(), epoch = _epoch;
    await _callSession(session, epoch, 'finance.grant', {
      'scopeId': scopeId,
      'accountId': accountId,
      'grant': grant.name,
      'requestId': newSharedId(),
    });
    await refreshFinancePolicy(scopeId);
    await syncNow();
  }

  Future<SharedFinancePolicy> refreshFinancePolicy(String scopeId) async {
    final session = _requireSession(), epoch = _epoch;
    await _fetchFinancePolicy(session, epoch, scopeId);
    await refreshLocal();
    _checkEpoch(epoch);
    return _cachedFinancePolicy(session.profile.partition, scopeId);
  }

  Future<List<SharedFinanceAuditEntry>> financeAudit({
    required String scopeId,
    required String recordId,
    int? beforeRevision,
    int limit = 50,
  }) async {
    final session = _requireSession(), epoch = _epoch;
    final policy = await refreshFinancePolicy(scopeId);
    _checkEpoch(epoch);
    if (!policy.canRead) {
      throw const CollaborationException('finance_forbidden');
    }
    final reply =
        await _callSession(session, epoch, '$_financeNamespace.audit', {
          'scopeId': scopeId,
          'recordId': recordId,
          if (beforeRevision != null) 'beforeRevision': beforeRevision,
          'limit': limit,
        });
    final current = await _cachedFinancePolicy(
      session.profile.partition,
      scopeId,
    );
    _checkEpoch(epoch);
    if (!current.canRead || current.revision != policy.revision) {
      throw const CollaborationException('finance_forbidden');
    }
    return List.unmodifiable(
      (reply['entries'] as List).map(
        (r) => SharedFinanceAuditEntry.fromJson(r as Map<String, dynamic>),
      ),
    );
  }

  Future<String> createFinanceAccount({
    required String scopeId,
    required String name,
    required String currency,
    int openingBalanceMinor = 0,
    String? ownerAccountId,
  }) async {
    final id = newSharedId(), now = clock().toUtc();
    final record = SharedFinanceAccount(
      id: id,
      createdAt: now,
      updatedAt: now,
      name: name,
      currency: currency,
      openingBalanceMinor: openingBalanceMinor,
      ownerAccountId: ownerAccountId,
    );
    await _editFinance(scopeId, (p) async {
      final scope = await _financeStoredScope(p, scopeId);
      if (_organizationFinanceSupported &&
          scope?.kind == SharedScopeKind.project &&
          scope?.parentSpaceId != null) {
        throw const CollaborationException('finance_account_parent_required');
      }
      await _putFinance(
        p,
        scopeId,
        SharedFinanceRecordType.financeAccount,
        id,
        record.toPayload(contractVersion: _financeContractVersion),
      );
    });
    return id;
  }

  Future<void> updateFinanceAccount(
    String scopeId,
    SharedFinanceAccount draft,
  ) => _editFinance(
    scopeId,
    (p) => _putFinance(
      p,
      scopeId,
      SharedFinanceRecordType.financeAccount,
      draft.id,
      draft
          .copyWith(updatedAt: _financeUpdatedAt(draft.updatedAt))
          .toPayload(contractVersion: _financeContractVersion),
      expectedLocalRevision: draft.revision,
    ),
  );
  Future<void> deleteFinanceAccount(String scopeId, String id) => _editFinance(
    scopeId,
    (p) => _putFinance(
      p,
      scopeId,
      SharedFinanceRecordType.financeAccount,
      id,
      null,
      deleted: true,
    ),
  );

  Future<String> createFinanceEntry({
    required String scopeId,
    required String accountId,
    String? accountScopeId,
    String? projectId,
    required FinanceEntryKind kind,
    SharedFinanceStatus status = SharedFinanceStatus.posted,
    required int amountMinor,
    required String currency,
    required String title,
    String notes = '',
    String category = '',
    String? payerAccountId,
    String? recipientAccountId,
    required DateTime occurredAt,
  }) async {
    final id = newSharedId(), now = clock().toUtc();
    final record = SharedFinanceEntry(
      id: id,
      createdAt: now,
      updatedAt: now,
      accountId: accountId,
      accountScopeId: accountScopeId,
      projectId: projectId,
      kind: kind,
      status: status,
      amountMinor: amountMinor,
      currency: currency,
      title: title,
      notes: notes,
      category: category,
      payerAccountId: payerAccountId,
      recipientAccountId: recipientAccountId,
      occurredAt: occurredAt,
    );
    await _editFinance(
      scopeId,
      (p) => _putFinance(
        p,
        scopeId,
        SharedFinanceRecordType.financeEntry,
        id,
        record.toPayload(contractVersion: _financeContractVersion),
      ),
    );
    return id;
  }

  Future<void> updateFinanceEntry(String scopeId, SharedFinanceEntry draft) =>
      _editFinance(
        scopeId,
        (p) => _putFinance(
          p,
          scopeId,
          SharedFinanceRecordType.financeEntry,
          draft.id,
          draft
              .copyWith(updatedAt: _financeUpdatedAt(draft.updatedAt))
              .toPayload(contractVersion: _financeContractVersion),
          expectedLocalRevision: draft.revision,
        ),
      );
  Future<void> deleteFinanceEntry(String scopeId, String id) => _editFinance(
    scopeId,
    (p) => _putFinance(
      p,
      scopeId,
      SharedFinanceRecordType.financeEntry,
      id,
      null,
      deleted: true,
    ),
  );

  Future<String> createFinanceTransfer({
    required String scopeId,
    required String fromAccountId,
    required String toAccountId,
    required int amountMinor,
    required String currency,
    SharedFinanceStatus status = SharedFinanceStatus.posted,
    required String title,
    String notes = '',
    required DateTime occurredAt,
  }) async {
    final id = newSharedId(), now = clock().toUtc();
    final record = SharedFinanceTransfer(
      id: id,
      createdAt: now,
      updatedAt: now,
      fromAccountId: fromAccountId,
      toAccountId: toAccountId,
      amountMinor: amountMinor,
      currency: currency,
      status: status,
      title: title,
      notes: notes,
      occurredAt: occurredAt,
    );
    await _editFinance(
      scopeId,
      (p) => _putFinance(
        p,
        scopeId,
        SharedFinanceRecordType.financeTransfer,
        id,
        record.toPayload(contractVersion: _financeContractVersion),
      ),
    );
    return id;
  }

  Future<void> updateFinanceTransfer(
    String scopeId,
    SharedFinanceTransfer draft,
  ) => _editFinance(
    scopeId,
    (p) => _putFinance(
      p,
      scopeId,
      SharedFinanceRecordType.financeTransfer,
      draft.id,
      draft
          .copyWith(updatedAt: _financeUpdatedAt(draft.updatedAt))
          .toPayload(contractVersion: _financeContractVersion),
      expectedLocalRevision: draft.revision,
    ),
  );
  Future<void> deleteFinanceTransfer(String scopeId, String id) => _editFinance(
    scopeId,
    (p) => _putFinance(
      p,
      scopeId,
      SharedFinanceRecordType.financeTransfer,
      id,
      null,
      deleted: true,
    ),
  );
}

extension CollaborationFinancePlanningActions on CollaborationRepository {
  void _requireFinancePlanning() {
    if (_financeContractVersion < 2) {
      throw const CollaborationException('unsupported_version');
    }
  }

  Future<void> saveFinancePlanForScope({
    required String scopeId,
    required List<LocalFinanceAccount> accounts,
    required List<FinanceRecurrenceRule> rules,
  }) async {
    _requireFinancePlanning();
    await _editFinance(scopeId, (p) async {
      for (final account in accounts) {
        account.validate();
        await _putFinance(
          p,
          scopeId,
          SharedFinanceRecordType.financeAccount,
          account.id,
          SharedFinanceAccount(
            id: account.id,
            name: account.name,
            currency: account.currency,
            openingBalanceMinor: account.openingBalanceMinor,
            openingBalanceAt: account.openingBalanceAt,
            archived: account.archived,
            createdAt: account.createdAt,
            updatedAt: account.updatedAt,
          ).toPayload(contractVersion: _financeContractVersion),
        );
      }
      for (final rule in rules) {
        rule.validate();
        if (rule.ledgerAccountId == null) {
          throw const CollaborationException('finance_account_missing');
        }
        final payload = Map<String, Object?>.of(rule.toJson())
          ..remove('id')
          ..remove('revision');
        await _putFinance(
          p,
          scopeId,
          SharedFinanceRecordType.financeRecurrenceRule,
          rule.id,
          payload,
        );
      }
      await _materializeSharedFinance(p, scopeId);
    });
  }

  Future<void> updateFinanceRecurrenceRule(
    String scopeId,
    FinanceRecurrenceRule rule,
  ) async {
    _requireFinancePlanning();
    rule.validate();
    final previous = state
        .dataForScope(scopeId)
        .financeRecurrenceRules
        .where((r) => r.id == rule.id)
        .firstOrNull;
    if (previous != null &&
        (previous.currency != rule.currency || previous.kind != rule.kind)) {
      throw const CollaborationException('rule_currency_immutable');
    }
    await _editFinance(scopeId, (p) async {
      final payload =
          Map<String, Object?>.of(
              rule
                  .copyWith(updatedAt: _financeUpdatedAt(rule.updatedAt))
                  .toJson(),
            )
            ..remove('id')
            ..remove('revision');
      await _putFinance(
        p,
        scopeId,
        SharedFinanceRecordType.financeRecurrenceRule,
        rule.id,
        payload,
        expectedLocalRevision: rule.revision,
      );
      final data = await _scopeData(p, scopeId), now = clock();
      for (final e in data.financeEntries.where(
        (e) =>
            e.recurrenceRuleId == rule.id &&
            e.status == SharedFinanceStatus.planned &&
            e.plannedAt != null &&
            !e.plannedAt!.isBefore(now),
      )) {
        final month = e.plannedAt!.toLocal();
        if (!rule.includesMonth(month.year, month.month)) {
          await _putFinance(
            p,
            scopeId,
            SharedFinanceRecordType.financeEntry,
            e.id,
            null,
            deleted: true,
            expectedLocalRevision: e.revision,
          );
        } else {
          final updated = e.copyWith(
            title: rule.title,
            kind: rule.entryKind,
            amountMinor: rule.estimatedAmountMinor,
            currency: rule.currency,
            accountId: rule.ledgerAccountId,
            ledgerAccountId: rule.ledgerAccountId,
            plannedAt: rule.dateForMonth(month.year, month.month).toUtc(),
            updatedAt: _financeUpdatedAt(e.updatedAt),
          );
          await _putFinance(
            p,
            scopeId,
            SharedFinanceRecordType.financeEntry,
            e.id,
            updated.toPayload(contractVersion: _financeContractVersion),
            expectedLocalRevision: e.revision,
          );
        }
      }
      await _materializeSharedFinance(p, scopeId);
    });
  }

  Future<void> materializeFinanceOccurrencesForScope(String scopeId) async {
    _requireFinancePlanning();
    await _editFinance(scopeId, (p) => _materializeSharedFinance(p, scopeId));
  }

  Future<void> _materializeSharedFinance(String p, String scopeId) async {
    final data = await _scopeData(p, scopeId), now = clock().toLocal();
    final actor = _requireSession().profile.accountId;
    final scopes = await database.rows(
      'SELECT data FROM scopes WHERE partition=? AND id=?',
      [p, scopeId],
    );
    final scope = SharedScope.fromJson(
      CollaborationRepository._map(scopes.single['data']),
    );
    final owner = scope.isOwner || scope.verifiedParentOwner;
    final seen = {
      for (final e in data.financeEntries)
        if (e.recurrenceRuleId != null)
          '${e.recurrenceRuleId}:${e.occurrenceKey}',
    };
    for (final rule in data.financeRecurrenceRules.where((r) => r.active)) {
      if (scope.recordPolicyVersion == 1 &&
          !owner &&
          data.recordCreators['finance:${rule.id}'] != actor)
        continue;
      if (data.financeAccounts.any(
        (a) => a.id == rule.ledgerAccountId && a.archived,
      )) {
        continue;
      }
      if (rule.ledgerAccountId == null) {
        throw const CollaborationException('finance_account_missing');
      }
      for (var offset = 0; offset < 12; offset++) {
        final month = DateTime(now.year, now.month + offset);
        if (!rule.includesMonth(month.year, month.month)) continue;
        final key = rule.keyForMonth(month.year, month.month);
        if (!seen.add('${rule.id}:$key')) continue;
        final date = rule.dateForMonth(month.year, month.month).toUtc();
        final record = SharedFinanceEntry(
          id: newSharedId(),
          createdAt: clock().toUtc(),
          updatedAt: clock().toUtc(),
          accountId: rule.ledgerAccountId!,
          kind: rule.entryKind,
          status: SharedFinanceStatus.planned,
          amountMinor: rule.estimatedAmountMinor,
          currency: rule.currency,
          title: rule.title,
          occurredAt: date,
          plannedAt: date,
          ledgerAccountId: rule.ledgerAccountId,
          recurrenceRuleId: rule.id,
          occurrenceKey: key,
        );
        await _putFinance(
          p,
          scopeId,
          SharedFinanceRecordType.financeEntry,
          record.id,
          record.toPayload(contractVersion: _financeContractVersion),
        );
      }
    }
  }

  Future<void> confirmFinanceOccurrenceForScope(
    String scopeId,
    SharedFinanceEntry entry, {
    required int amountMinor,
    required DateTime paidAt,
  }) async {
    _requireFinancePlanning();
    final current = state
        .dataForScope(scopeId)
        .financeEntries
        .where((e) => e.id == entry.id)
        .firstOrNull;
    if (current?.status == SharedFinanceStatus.posted &&
        current?.amountMinor == amountMinor &&
        current?.paidAt == paidAt.toUtc()) {
      return;
    }
    if (entry.status != SharedFinanceStatus.planned) {
      throw const CollaborationException('stale_edit');
    }
    await updateFinanceEntry(
      scopeId,
      entry.copyWith(
        status: SharedFinanceStatus.posted,
        amountMinor: amountMinor,
        paidAt: paidAt.toUtc(),
        occurredAt: paidAt.toUtc(),
      ),
    );
  }
}
