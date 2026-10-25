part of 'collaboration_repository.dart';

extension CollaborationRecordMerge on CollaborationRepository {
  /// Uses only verified canonical projections and retained local bases. Unknown
  /// signed outcomes are never replaced; an unstaged intent or exact definitive
  /// rejection is required before a fresh successor can be created.
  Future<bool> _mergeRecordConflict(
    DeviceSession session,
    int epoch,
    String scopeId,
    Map<String, dynamic> operation,
    Map<String, dynamic> canonical,
  ) async {
    final p = session.profile.partition;
    final request = CollaborationRepository._map(operation['request']);
    final typeName = request['type'];
    if (!const {
          'task',
          'project',
          'event',
          'shoppingList',
          'shoppingItem',
          'householdPerson',
        }.contains(typeName) ||
        request['deleted'] == true ||
        canonical['deleted'] == true ||
        canonical['id'] != operation['record_id'] ||
        canonical['type'] != typeName) {
      return false;
    }
    final id = operation['record_id'] as String;
    final bases = await database.rows(
      'SELECT value FROM local_meta WHERE name=?',
      ['record_op_base:$p:${operation['op_id']}'],
    );
    if (bases.length != 1) return false;
    final saved = CollaborationRepository._map(bases.single['value']);
    if (saved['scopeId'] != scopeId ||
        saved['expectedRevision'] != request['expectedRevision'] ||
        saved['canonical'] is! Map) {
      return false;
    }
    final base = _canonical(
      Map<String, dynamic>.from(saved['canonical'] as Map),
      personal: await _isPersonalScope(p, scopeId),
    );
    final queuedPredecessors = saved['queuedPredecessors'];
    if (saved['serverRevision'] != base['revision'] ||
        queuedPredecessors is! int ||
        queuedPredecessors < 0 ||
        request['expectedRevision'] !=
            (base['revision'] as int) + queuedPredecessors) {
      return false;
    }
    if (base['id'] != id ||
        base['type'] != typeName ||
        base['deleted'] == true ||
        (canonical['revision'] as int) <= (base['revision'] as int)) {
      return false;
    }
    final current = await _record(p, scopeId, id);
    final queued = await database.rows(
      'SELECT * FROM outbox WHERE partition=? AND scope_id=? AND record_id=? ORDER BY sequence',
      [p, scopeId, id],
    );
    if (queued.isEmpty || queued.length > 32 || current['deleted'] == 1) {
      return false;
    }
    var attempts = 0;
    var expected = CollaborationRepository._map(
      queued.first['request'],
    )['expectedRevision'];
    if (expected is! int) return false;
    for (final row in queued) {
      if (!const {'pending', 'conflict'}.contains(row['state'])) return false;
      final original = CollaborationRepository._map(row['request']);
      if (original['expectedRevision'] != expected++ ||
          original['type'] != typeName ||
          original['deleted'] == true) {
        return false;
      }
      if ((await database.rows('SELECT 1 FROM local_meta WHERE name=?', [
        'task_cost_pair:$p:${row['op_id']}',
      ])).isNotEmpty) {
        return false;
      }
      final basis = await database.rows(
        'SELECT value FROM local_meta WHERE name=?',
        ['record_op_base:$p:${row['op_id']}'],
      );
      if (basis.length != 1 ||
          jsonEncode(
                CollaborationRepository._map(
                  basis.single['value'],
                )['canonical'],
              ) !=
              jsonEncode(base)) {
        return false;
      }
      final business = await database.rows(
        'SELECT request_id FROM crypto_business_requests WHERE partition=? AND operation_id=?',
        [p, row['op_id']],
      );
      if (business.isNotEmpty) {
        final router = cryptoRouter;
        bool rejected = false;
        if (router is CryptoTerminalRecordConflicts) {
          rejected = await (router as CryptoTerminalRecordConflicts)
              .hasTerminalRecordConflict(
                session: session,
                scopeId: scopeId,
                operation: original,
              );
        } else if (typeName == 'task' &&
            router is CryptoTerminalTaskConflicts) {
          rejected = await (router as CryptoTerminalTaskConflicts)
              .hasTerminalTaskConflict(
                session: session,
                scopeId: scopeId,
                operation: original,
              );
        }
        if (!rejected) return false;
      }
      final lineage = await database.rows(
        'SELECT value FROM local_meta WHERE name=?',
        ['record_merge_lineage:$p:${row['op_id']}'],
      );
      if (lineage.isNotEmpty) {
        final prior = CollaborationRepository._map(lineage.single['value']);
        if (prior['revision'] == canonical['revision']) return false;
        final count = prior['attempts'];
        if (count is! int || count >= 3) return false;
        if (count > attempts) attempts = count;
      }
    }
    Map<String, dynamic> merged;
    try {
      merged = mergeSharedRecordPayloads(
        type: SharedRecordType.values.byName(typeName as String),
        base: Map<String, dynamic>.from(base['payload'] as Map),
        local: CollaborationRepository._map(current['payload']),
        remote: Map<String, dynamic>.from(canonical['payload'] as Map),
      );
    } on SharedRecordMergeConflict {
      return false;
    }
    final alreadyShared = equivalentSharedRecordPayloads(
      merged,
      Map<String, dynamic>.from(canonical['payload'] as Map),
    );
    if (merged.containsKey('updatedAt')) {
      merged['updatedAt'] = _now.toIso8601String();
    }
    try {
      await database.transaction(() async {
        _checkEpoch(epoch);
        await _validLease(p);
        final remotePayload = Map<String, dynamic>.from(
          canonical['payload'] as Map,
        );
        final onlyCheck =
            typeName == 'shoppingItem' &&
            SharedRecordPermissions.onlyShoppingCheck(remotePayload, merged);
        await _writable(p, scopeId, allowShoppingCheck: onlyCheck);
        final latest = await _record(p, scopeId, id);
        final exact = await database.rows(
          'SELECT * FROM outbox WHERE partition=? AND scope_id=? AND record_id=? ORDER BY sequence',
          [p, scopeId, id],
        );
        if (latest['local_revision'] != current['local_revision'] ||
            latest['payload'] != current['payload'] ||
            jsonEncode(exact) != jsonEncode(queued)) {
          throw const CollaborationException('stale_edit');
        }
        for (final row in queued) {
          final basis = await database.rows(
            'SELECT value FROM local_meta WHERE name=?',
            ['record_op_base:$p:${row['op_id']}'],
          );
          await database.execute(
            'INSERT INTO local_meta(name,value) VALUES(?,?) ON CONFLICT(name) DO NOTHING',
            [
              'record_rebased_op:$p:${row['op_id']}',
              jsonEncode({...row, 'base': basis.single['value']}),
            ],
          );
        }
        await database.execute(
          'DELETE FROM outbox WHERE partition=? AND scope_id=? AND record_id=?',
          [p, scopeId, id],
        );
        await database.execute(
          'DELETE FROM conflicts WHERE partition=? AND scope_id=? AND record_id=?',
          [p, scopeId, id],
        );
        await database.execute(
          'UPDATE records SET server_revision=?,remote=? WHERE partition=? AND scope_id=? AND id=?',
          [canonical['revision'], jsonEncode(canonical), p, scopeId, id],
        );
        if (alreadyShared) {
          await _applyRemote(p, scopeId, canonical);
        } else {
          await _put(
            p,
            scopeId,
            SharedRecordType.values.byName(typeName),
            id,
            merged,
            expectedLocalRevision: current['local_revision'] as int,
          );
          final next = (await database.rows(
            'SELECT op_id FROM outbox WHERE partition=? AND scope_id=? AND record_id=? ORDER BY sequence DESC LIMIT 1',
            [p, scopeId, id],
          )).single;
          await database.execute(
            'INSERT INTO local_meta(name,value) VALUES(?,?)',
            [
              'record_merge_lineage:$p:${next['op_id']}',
              jsonEncode({
                'attempts': attempts + 1,
                'revision': canonical['revision'],
              }),
            ],
          );
        }
        await database.execute(
          'INSERT INTO local_meta(name,value) VALUES(?,?) ON CONFLICT(name) DO UPDATE SET value=excluded.value',
          [
            'record_auto_merge_notice:$p:$scopeId:$id',
            jsonEncode({
              'scopeId': scopeId,
              'recordId': id,
              'type': typeName,
              'at': _now.toIso8601String(),
            }),
          ],
        );
      });
      if (!alreadyShared) _coordinatorDemand = true;
      return true;
    } on CollaborationException catch (error) {
      // A rejected merge leaves both drafts and the exact queue intact. One
      // stale/ineligible record does not prevent independent records syncing.
      if (const {
        'stale_edit',
        'permission_revoked',
        'changes_blocked',
        'parent_missing',
        'record_deleted',
        'record_missing',
        'person_missing',
        'person_archived',
        'project_archived',
        'validation_error',
        'live_children',
        'record_author_required',
        'record_reassign_forbidden',
        'record_permission_denied',
        'record_edit_forbidden',
        'record_delete_forbidden',
        'record_assignment_forbidden',
        'project_sharing_pending_changes',
      }.contains(error.code)) {
        return false;
      }
      rethrow;
    }
  }

  Future<void> _archiveConflictOperations(
    DeviceSession session,
    String scope,
    String id,
  ) async {
    final p = session.profile.partition;
    final queued = await database.rows(
      'SELECT * FROM outbox WHERE partition=? AND scope_id=? AND record_id=? ORDER BY sequence',
      [p, scope, id],
    );
    for (final row in queued) {
      final original = CollaborationRepository._map(row['request']);
      final staged = await database.rows(
        'SELECT request_id FROM crypto_business_requests WHERE partition=? AND operation_id=?',
        [p, row['op_id']],
      );
      if (staged.isNotEmpty) {
        final router = cryptoRouter;
        final definitive = router is CryptoTerminalRecordConflicts
            ? await (router as CryptoTerminalRecordConflicts)
                  .hasTerminalRecordConflict(
                    session: session,
                    scopeId: scope,
                    operation: original,
                  )
            : original['type'] == 'task' &&
                  router is CryptoTerminalTaskConflicts &&
                  await (router as CryptoTerminalTaskConflicts)
                      .hasTerminalTaskConflict(
                        session: session,
                        scopeId: scope,
                        operation: original,
                      );
        if (!definitive) {
          throw const CollaborationException(
            'crypto_conflict_receipt_required',
          );
        }
      }
      final bases = await database.rows(
        'SELECT value FROM local_meta WHERE name=?',
        ['record_op_base:$p:${row['op_id']}'],
      );
      await database.execute(
        'INSERT INTO local_meta(name,value) VALUES(?,?) ON CONFLICT(name) DO NOTHING',
        [
          'record_resolved_op:$p:${row['op_id']}',
          jsonEncode({
            ...row,
            if (bases.isNotEmpty) 'base': bases.single['value'],
          }),
        ],
      );
    }
  }

  Future<void> _mergeVerifiedRecordConflicts(
    DeviceSession session,
    int epoch,
  ) async {
    final p = session.profile.partition;
    final conflicts = await database.rows(
      "SELECT o.* FROM outbox o JOIN conflicts c ON c.partition=o.partition AND c.id=o.op_id "
      "WHERE o.partition=? AND o.state='conflict' AND c.reason='conflict' ORDER BY o.sequence LIMIT 32",
      [p],
    );
    final visited = <String>{};
    for (final operation in conflicts) {
      _checkEpoch(epoch);
      await _renewLease(p);
      final scope = operation['scope_id'] as String,
          id = operation['record_id'] as String;
      if (!visited.add('$scope:$id')) continue;
      final rows = await database.rows(
        'SELECT remote FROM records WHERE partition=? AND scope_id=? AND id=?',
        [p, scope, id],
      );
      if (rows.singleOrNull?['remote'] == null) continue;
      final canonical = _canonical(
        CollaborationRepository._map(rows.single['remote']),
        personal: await _isPersonalScope(p, scope),
      );
      await _mergeRecordConflict(session, epoch, scope, operation, canonical);
    }
  }
}
