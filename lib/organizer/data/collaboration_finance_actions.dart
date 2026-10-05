part of 'collaboration_repository.dart';

/// Financial writes use a distinct local store, queue and module authorization.
extension CollaborationFinanceActions on CollaborationRepository {
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
    final policy = SharedFinancePolicy.fromJson(
      await _callSession(session, epoch, 'finance.policy', {
        'scopeId': scopeId,
      }),
    );
    return database.transaction(() async {
      _checkEpoch(epoch);
      if (syncLease) await _validLease(partition);
      _checkEpoch(epoch);
      if (generation == await _financeAccessGeneration(partition, scopeId)) {
        await _storeFinancePolicy(partition, scopeId, policy);
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
      );
    }
    if (deniedWithoutRevision ||
        old.enabled != policy.enabled ||
        old.grant != policy.grant ||
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
    if (!(await _cachedFinancePolicy(partition, scopeId)).canWrite) {
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
    final rows = await database.rows(
      'SELECT * FROM finance_records WHERE partition=? AND scope_id=? AND id=?',
      [partition, scopeId, id],
    );
    final old = rows.isEmpty ? null : rows.first;
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
    if (payload != null) {
      validateSharedFinancePayload(type, Map<String, dynamic>.from(payload));
      if (previous != null) {
        if (readSharedDate(previous, 'createdAt') !=
            readSharedDate(Map<String, dynamic>.from(payload), 'createdAt')) {
          throw const CollaborationException('validation_error');
        }
        payload['createdAt'] = previous['createdAt'];
      }
      if (type == SharedFinanceRecordType.financeAccount &&
          previous != null &&
          (previous['currency'] != payload['currency'] ||
              previous['openingBalanceMinor'] !=
                  payload['openingBalanceMinor'])) {
        throw const CollaborationException('finance_account_immutable');
      }
      final accountIds = switch (type) {
        SharedFinanceRecordType.financeAccount => <String>[],
        SharedFinanceRecordType.personalFinanceEntry => <String>[],
        SharedFinanceRecordType.financeEntry => [
          payload['accountId'] as String,
        ],
        SharedFinanceRecordType.financeTransfer => [
          payload['fromAccountId'] as String,
          payload['toAccountId'] as String,
        ],
      };
      for (final accountId in accountIds) {
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
      'INSERT INTO finance_outbox(op_id,partition,scope_id,record_id,request) VALUES(?,?,?,?,?)',
      [request['opId'], partition, scopeId, id, jsonEncode(request)],
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
    final reply = await _callSession(session, epoch, 'finance.audit', {
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
    await _editFinance(
      scopeId,
      (p) => _putFinance(
        p,
        scopeId,
        SharedFinanceRecordType.financeAccount,
        id,
        record.toPayload(),
      ),
    );
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
      draft.copyWith(updatedAt: clock().toUtc()).toPayload(),
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
        record.toPayload(),
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
          draft.copyWith(updatedAt: clock().toUtc()).toPayload(),
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
        record.toPayload(),
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
      draft.copyWith(updatedAt: clock().toUtc()).toPayload(),
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
