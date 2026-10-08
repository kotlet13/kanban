part of 'collaboration_repository.dart';

extension CollaborationTaskCostRecovery on CollaborationRepository {
  Future<void> saveTaskWithCost(
    String scopeId,
    LocalTask task, {
    bool isNew = false,
    TaskCostDraft? cost,
    bool removeCost = false,
    int? expectedFinanceRevision,
  }) async {
    if (_recordContractVersion < 3 || _financeContractVersion < 2) {
      throw const CollaborationException('client_upgrade_required');
    }
    final session = _requireSession(),
        epoch = _epoch,
        p = session.profile.partition;
    await database.transaction(() async {
      _checkEpoch(epoch);
      await _writable(p, scopeId);
      if (cost != null || removeCost) await _financeWritable(p, scopeId);
      final existing = await database.rows(
        r"SELECT * FROM finance_records WHERE partition=? AND scope_id=? AND type='financeEntry' AND deleted=0 AND json_extract(payload,'$.taskId')=?",
        [p, scopeId, task.id],
      );
      final old = existing.firstOrNull;
      if ((cost != null || removeCost) &&
          (old?['local_revision'] as int?) != expectedFinanceRevision) {
        throw const CollaborationException('stale_edit');
      }
      final previous = old == null
          ? null
          : SharedFinanceEntry.fromJson({
              ...CollaborationRepository._map(old['payload']),
              'id': old['id'],
              'revision': old['local_revision'],
            });
      final now = _now;
      final saved = task.copyWith(
        title: task.title.trim(),
        updatedAt: isNew ? task.createdAt : now,
      );
      await _put(
        p,
        scopeId,
        SharedRecordType.task,
        task.id,
        _payload(saved.toJson()),
        expectedLocalRevision: isNew ? null : task.revision,
      );
      SharedFinanceEntry? entry;
      if (removeCost && previous != null) {
        entry = previous.copyWith(taskId: null, updatedAt: now);
      } else if (cost != null) {
        final ledger =
            cost.ledgerAccountId ??
            previous?.ledgerAccountId ??
            previous?.accountId;
        if (ledger == null) {
          throw const CollaborationException('finance_account_missing');
        }
        final paidAt =
            previous?.paidAt ??
            (previous?.status == SharedFinanceStatus.posted
                ? previous?.occurredAt
                : null) ??
            (cost.paid ? (cost.paidAt ?? now).toUtc() : null);
        entry = SharedFinanceEntry(
          id: previous?.id ?? newSharedId(),
          revision: previous?.revision ?? 0,
          accountId: ledger,
          ledgerAccountId: ledger,
          kind: FinanceEntryKind.expense,
          status: paidAt == null
              ? SharedFinanceStatus.planned
              : SharedFinanceStatus.posted,
          amountMinor: cost.amountMinor,
          currency: cost.currency,
          title: saved.title,
          notes: previous?.notes ?? '',
          category: previous?.category ?? '',
          payerAccountId: previous?.payerAccountId,
          recipientAccountId: previous?.recipientAccountId,
          payerPersonId: cost.payerPersonId,
          recipientPersonId: cost.recipientPersonId,
          createdByPersonId: cost.createdByPersonId,
          taskId: task.id,
          plannedAt: saved.dueAt,
          paidAt: paidAt,
          occurredAt: paidAt ?? saved.dueAt ?? now,
          createdAt: previous?.createdAt ?? now,
          updatedAt: now,
        );
      }
      if (entry != null) {
        await _putFinance(
          p,
          scopeId,
          SharedFinanceRecordType.financeEntry,
          entry.id,
          entry.toPayload(contractVersion: 2),
          expectedLocalRevision: previous?.revision,
        );
        final generic = (await database.rows(
          'SELECT op_id FROM outbox WHERE partition=? AND scope_id=? AND record_id=? ORDER BY sequence DESC LIMIT 1',
          [p, scopeId, task.id],
        )).single;
        final financial = (await database.rows(
          'SELECT op_id FROM finance_outbox WHERE partition=? AND scope_id=? AND record_id=? ORDER BY sequence DESC LIMIT 1',
          [p, scopeId, entry.id],
        )).single;
        await database.execute(
          'INSERT INTO local_meta(name,value) VALUES(?,?)',
          ['task_cost_pair:$p:${generic['op_id']}', financial['op_id']],
        );
      }
      _checkEpoch(epoch);
    });
    await refreshLocal();
  }

  /// A finance review must explicitly approve keeping both conflicting drafts.
  /// Choosing the server version discards both halves of the local compound edit.
  Future<bool> _resolvePairedTaskCostConflict({
    required String conflictId,
    required bool keepLocal,
    bool financialReview = false,
  }) async {
    final session = _requireSession(),
        epoch = _epoch,
        p = session.profile.partition;
    final pairKey = 'task_cost_pair:$p:$conflictId';
    final pairs = await database.rows(
      'SELECT value FROM local_meta WHERE name=?',
      [pairKey],
    );
    if (pairs.isEmpty) return false;
    if (keepLocal && !financialReview) {
      throw const CollaborationException('requires_finance_resolution');
    }
    final financeOps = await database.rows(
      'SELECT * FROM finance_outbox WHERE partition=? AND op_id=?',
      [p, pairs.single['value']],
    );
    if (financeOps.isEmpty) {
      throw const CollaborationException('conflict_missing');
    }
    final financeOp = financeOps.single,
        scope = financeOp['scope_id'] as String;
    if (keepLocal) {
      await syncNow();
      _checkEpoch(epoch);
      if (_lastError != null) throw _lastError!;
      if (!(await refreshFinancePolicy(scope)).canWrite) {
        throw const CollaborationException('finance_forbidden');
      }
    }
    await database.transaction(() async {
      _checkEpoch(epoch);
      final conflicts = await database.rows(
        'SELECT * FROM conflicts WHERE partition=? AND id=?',
        [p, conflictId],
      );
      if (conflicts.isEmpty) {
        throw const CollaborationException('conflict_missing');
      }
      final taskId = conflicts.single['record_id'] as String;
      final task = (await database.rows(
        'SELECT * FROM records WHERE partition=? AND scope_id=? AND id=?',
        [p, scope, taskId],
      )).single;
      final financeId = financeOp['record_id'] as String;
      final financial = (await database.rows(
        'SELECT * FROM finance_records WHERE partition=? AND scope_id=? AND id=?',
        [p, scope, financeId],
      )).single;
      final remoteTask = task['remote'] == null
          ? null
          : _canonical(
              CollaborationRepository._map(task['remote']),
              personal: await _isPersonalScope(p, scope),
            );
      final remoteFinance = financial['remote'] == null
          ? null
          : _financeCanonical(
              CollaborationRepository._map(financial['remote']),
            );
      if (keepLocal) {
        await _writable(p, scope);
        if (!(await _cachedFinancePolicy(p, scope)).canWrite) {
          throw const CollaborationException('finance_forbidden');
        }
        if (remoteTask?['deleted'] == true ||
            remoteFinance?['deleted'] == true) {
          throw const CollaborationException('record_deleted');
        }
      }
      final queued = await database.rows(
        'SELECT op_id FROM outbox WHERE partition=? AND scope_id=? AND record_id=?',
        [p, scope, taskId],
      );
      for (final row in queued) {
        await database.execute('DELETE FROM local_meta WHERE name=?', [
          'task_cost_pair:$p:${row['op_id']}',
        ]);
      }
      await database.execute(
        'DELETE FROM outbox WHERE partition=? AND scope_id=? AND record_id=?',
        [p, scope, taskId],
      );
      await database.execute(
        'DELETE FROM finance_outbox WHERE partition=? AND scope_id=? AND record_id=?',
        [p, scope, financeId],
      );
      await database.execute(
        'DELETE FROM conflicts WHERE partition=? AND scope_id=? AND record_id=?',
        [p, scope, taskId],
      );
      await database.execute(
        'DELETE FROM finance_conflicts WHERE partition=? AND scope_id=? AND record_id=?',
        [p, scope, financeId],
      );
      if (keepLocal) {
        final taskPayload = task['payload'] == null
            ? null
            : CollaborationRepository._map(task['payload']);
        if (taskPayload != null) addRichPlanningDefaults(taskPayload, 'task');
        final financePayload = financial['payload'] == null
            ? null
            : CollaborationRepository._map(financial['payload']);
        if (financePayload != null) {
          financePayload['taskId'] = task['deleted'] == 1 ? null : taskId;
          financePayload['plannedAt'] = taskPayload?['dueAt'];
        }
        final taskRequest = {
          'opId': newSharedId(),
          'recordId': taskId,
          'type': 'task',
          'expectedRevision': remoteTask?['revision'] ?? 0,
          'deleted': task['deleted'] == 1,
          'payload': taskPayload,
        };
        final financeRequest = {
          'opId': newSharedId(),
          'recordId': financeId,
          'type': financial['type'],
          'expectedRevision': remoteFinance?['revision'] ?? 0,
          'deleted': financial['deleted'] == 1,
          'payload': financePayload,
        };
        await database.execute(
          'INSERT INTO outbox(op_id,partition,scope_id,record_id,request,wire_version) VALUES(?,?,?,?,?,3)',
          [taskRequest['opId'], p, scope, taskId, jsonEncode(taskRequest)],
        );
        await database.execute(
          'INSERT INTO finance_outbox(op_id,partition,scope_id,record_id,request,wire_version) VALUES(?,?,?,?,?,2)',
          [
            financeRequest['opId'],
            p,
            scope,
            financeId,
            jsonEncode(financeRequest),
          ],
        );
        await database.execute(
          'INSERT INTO local_meta(name,value) VALUES(?,?)',
          ['task_cost_pair:$p:${taskRequest['opId']}', financeRequest['opId']],
        );
      } else {
        await database.execute(
          'UPDATE records SET payload=?,deleted=?,local_revision=local_revision+1 WHERE partition=? AND scope_id=? AND id=?',
          [
            remoteTask?['payload'] == null
                ? null
                : jsonEncode(remoteTask!['payload']),
            remoteTask == null || remoteTask['deleted'] == true ? 1 : 0,
            p,
            scope,
            taskId,
          ],
        );
        await database.execute(
          'UPDATE finance_records SET payload=?,deleted=?,local_revision=local_revision+1 WHERE partition=? AND scope_id=? AND id=?',
          [
            remoteFinance?['payload'] == null
                ? null
                : jsonEncode(remoteFinance!['payload']),
            remoteFinance == null || remoteFinance['deleted'] == true ? 1 : 0,
            p,
            scope,
            financeId,
          ],
        );
      }
      if (await _activePrivateScope(p, scope)) await database.touchPersonal();
    });
    await refreshLocal();
    return true;
  }
}
