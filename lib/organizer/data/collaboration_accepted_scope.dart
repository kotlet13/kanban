part of 'collaboration_repository.dart';

extension CollaborationAcceptedScopeActions on CollaborationRepository {
  /// Prepare just the verified accepted target. This is a scoped read, not a
  /// completed account synchronization or acknowledgement of account.changes.
  Future<void> prepareAcceptedScope(String scopeId) async {
    var session = _requireSession();
    final epoch = _epoch;
    final partition = session.profile.partition;
    final router = cryptoRouter;
    if (!isSharedUuid(scopeId) || router is! CryptoAcceptedScopeReader) {
      throw const CollaborationException('crypto_reconciliation_required');
    }
    await _renewDeviceSessionIfNeeded(session, epoch);
    session = _currentDeviceSession(session, epoch);
    Future<void> checkCurrent() async {
      final current = _currentDeviceSession(session, epoch);
      if (!current.profile.expiresAt.isAfter(clock())) {
        throw const CollaborationException('auth_required');
      }
      final invalidKey =
          'invalid_session:$partition:${session.profile.deviceId}';
      final markers = await database.rows(
        'SELECT name,value FROM local_meta WHERE name IN (?,?,?)',
        [
          invalidKey,
          'deleted_account:$partition',
          'deletion_pending:$partition',
        ],
      );
      _currentDeviceSession(session, epoch);
      if (markers.isNotEmpty) {
        final invalid = markers
            .where((row) => row['name'] == invalidKey)
            .firstOrNull;
        throw CollaborationException(
          invalid == null ? 'deletion_pending' : invalid['value'] as String,
        );
      }
      if ((await database.rows(
        "SELECT 1 FROM crypto_restore_fences WHERE partition=? AND state<>'verified'",
        [partition],
      )).isNotEmpty) {
        throw const CollaborationException('crypto_reconciliation_required');
      }
      _currentDeviceSession(session, epoch);
    }

    await checkCurrent();
    Future<List<Map<String, Object?>>> local() => database.rows(
      "SELECT data,blocked,cursor,finance_cursor,finance_access_revision,finance_complete,(SELECT value FROM local_meta WHERE name='scope_reconciliation:'||scopes.partition||':'||scopes.id) AS reconciliation FROM scopes WHERE partition=? AND id=?",
      [partition, scopeId],
    );
    final before = await local();
    _checkEpoch(epoch);
    final previous = before.isEmpty
        ? null
        : SharedScope.fromJson(
            CollaborationRepository._map(before.single['data']),
          );
    if (previous?.deleted == true ||
        (before.isNotEmpty &&
            before.single['blocked'] == 1 &&
            previous?.revoked != true &&
            previous?.role != SharedRole.viewer)) {
      throw const CollaborationException('crypto_reconciliation_required');
    }
    final cursorKeys = [
      for (final domain in const ['content', 'finance'])
        'crypto_projection_cursor_v1:$partition:$scopeId:$domain',
    ];
    final priorCursors = await database.rows(
      'SELECT name FROM local_meta WHERE name IN (?,?) ORDER BY name',
      cursorKeys,
    );
    _checkEpoch(epoch);
    CryptoProjectionCursorOrigin? origin;
    var cursor = before.isEmpty ? 0 : before.single['cursor'] as int;
    final read = await withAccountWorkJob(
      transport,
      AccountWorkKind.invitation,
      () async {
        if (priorCursors.length != cursorKeys.length) {
          if (router is! CryptoProjectionCursorTransition) {
            throw const CollaborationException(
              'crypto_reconciliation_required',
            );
          }
          origin = await (router as CryptoProjectionCursorTransition)
              .verifyProjectionCursorOrigin(session: session, scopeId: scopeId);
          _checkEpoch(epoch);
          if (origin == null) {
            throw const CollaborationException(
              'crypto_reconciliation_required',
            );
          }
          if (origin == CryptoProjectionCursorOrigin.legacyMigration &&
              !priorCursors.any((row) => row['name'] == cursorKeys.first)) {
            cursor = 0;
          }
        }
        return (router as CryptoAcceptedScopeReader).prepareAcceptedScope(
          session: session,
          scopeId: scopeId,
          cursor: cursor,
        );
      },
    );
    _checkEpoch(epoch);
    final scope = SharedScope.fromJson(read.scope);
    if (scope.id != scopeId ||
        !scope.canRead ||
        scope.blocked ||
        scope.deleted ||
        scope.metadataRevision <= 0 ||
        read.cursor < cursor ||
        (previous != null && scope.sequence < previous.sequence)) {
      throw const CollaborationException('crypto_reconciliation_required');
    }
    final canonical = [
      for (final record in read.records)
        _canonical(record, personal: scope.kind == SharedScopeKind.personal),
    ];
    await database.transaction(() async {
      await checkCurrent();
      if (jsonEncode(before) != jsonEncode(await local()) ||
          jsonEncode(priorCursors) !=
              jsonEncode(
                await database.rows(
                  'SELECT name FROM local_meta WHERE name IN (?,?) ORDER BY name',
                  cursorKeys,
                ),
              ) ||
          !await read.isCurrent()) {
        throw const CollaborationException('crypto_reconciliation_required');
      }
      // Share an existing lease only inside this atomic commit. If no run owns
      // it, claim and release it in the same transaction; never release another
      // in-flight coordinator's lease or start a second account sync.
      final priorLease = await database.rows(
        'SELECT owner,expires_at FROM sync_leases WHERE partition=?',
        [partition],
      );
      final retainedLease =
          priorLease.isNotEmpty &&
          priorLease.single['owner'] == _leaseOwner &&
          (priorLease.single['expires_at'] as int) >
              clock().millisecondsSinceEpoch;
      if (!await _claimLease(partition)) {
        throw const CollaborationException('sync_lease_lost');
      }
      await _validLease(partition);
      if (previous?.revoked == true) {
        await database.execute(
          'UPDATE scopes SET blocked=? WHERE partition=? AND id=?',
          [scope.role == SharedRole.viewer ? 1 : 0, partition, scopeId],
        );
      }
      await _upsertScope(partition, scope);
      for (final key in cursorKeys) {
        if (priorCursors.any((row) => row['name'] == key)) continue;
        if (origin == CryptoProjectionCursorOrigin.legacyMigration &&
            key == cursorKeys.last) {
          await database.execute(
            'UPDATE scopes SET finance_cursor=0,finance_access_revision=0,finance_complete=0 WHERE partition=? AND id=?',
            [partition, scopeId],
          );
        }
        await database.execute(
          'INSERT INTO local_meta(name,value) VALUES(?,?) ON CONFLICT(name) DO NOTHING',
          [key, origin!.name],
        );
      }
      for (final record in canonical) {
        // Existing merge rules preserve dirty local candidates and immutable
        // outbox entries, including local deletions and task-cost partners.
        await _applyRemote(partition, scopeId, record);
      }
      await database.execute(
        'UPDATE scopes SET cursor=? WHERE partition=? AND id=?',
        [read.cursor, partition, scopeId],
      );
      await database.execute('DELETE FROM local_meta WHERE name=?', [
        'scope_reconciliation:$partition:$scopeId',
      ]);
      _checkEpoch(epoch);
      if (!await read.isCurrent()) {
        throw const CollaborationException('crypto_reconciliation_required');
      }
      await checkCurrent();
      if (!retainedLease) {
        await database.execute(
          'DELETE FROM sync_leases WHERE partition=? AND owner=?',
          [partition, _leaseOwner],
        );
      }
    });
    await refreshLocal(scopeIds: {scopeId});
    _checkEpoch(epoch);
  }
}
