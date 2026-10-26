part of 'collaboration_repository.dart';

/// Counts describe verified access, never a claim that content has synchronized.
class CollaborationAccessReview {
  const CollaborationAccessReview({
    required this.available,
    required this.restored,
    required this.revoked,
    required this.unresolved,
  });
  final int available, restored, revoked, unresolved;
}

extension CollaborationAccessReviewActions on CollaborationRepository {
  /// Manual demand joins the same coordinator and any in-flight startup review.
  Future<CollaborationAccessReview> checkAllAccess() {
    final existing = _accessReviewManual;
    if (existing != null) return existing;
    final epoch = _epoch;
    _requireSession();
    final done = Completer<CollaborationAccessReview>();
    _accessReviewManual = done.future;
    () async {
      try {
        final running = _accessReviewRunning;
        if (running != null) {
          final result = await running;
          _checkEpoch(epoch);
          done.complete(result);
        } else {
          _accessReviewEpoch = -1;
          await syncNow(manual: true);
          _checkEpoch(epoch);
          if (_accessReviewEpoch != epoch || _lastAccessReview == null) {
            throw const CollaborationException(
              'crypto_reconciliation_required',
            );
          }
          done.complete(_lastAccessReview!);
        }
      } catch (error, stack) {
        done.completeError(error, stack);
      } finally {
        _accessReviewManual = null;
      }
    }();
    return done.future;
  }

  Future<CollaborationAccessReview> _reviewAllAccess(
    DeviceSession session,
    int epoch,
  ) async {
    final partition = session.profile.partition;
    final done = Completer<CollaborationAccessReview>();
    _accessReviewRunning = done.future;
    // An automatic review has no external waiter; consume its error as well as
    // propagating it to the coordinator. Manual callers can still await it.
    unawaited(
      done.future.then<void>((_) {}, onError: (Object _, StackTrace __) {}),
    );
    var leased = false;
    try {
      authorityReuse.invalidate();
      leased = await _claimLease(partition);
      if (!leased) throw const CollaborationException('sync_lease_lost');
      _checkEpoch(epoch);
      await _negotiate(session, epoch);
      await _renewDeviceSessionIfNeeded(session, epoch);
      Future<Map<String, dynamic>> read() =>
          _callSession(session, epoch, 'scopes.list', {
            if (_privateSyncSupported) 'includePersonal': true,
            if (_scopeAccessChangesSupported) 'includeAccessChanges': true,
            if (_organizationsSupported) 'includeOrganizations': true,
            if (_projectArchivingSupported) 'includeArchived': true,
          });
      final router = cryptoRouter;
      final reply = router is CryptoVerifiedReadGroupContext
          ? await (router as CryptoVerifiedReadGroupContext).withVerifiedReads(
              session: session,
              read: read,
            )
          : await read();
      _checkEpoch(epoch);
      Set<String> ids(String key) {
        final raw = reply[key] ?? const <String>[];
        if (raw is! List || raw.any((v) => v is! String || !isSharedUuid(v))) {
          throw const CollaborationException('invalid_response');
        }
        return raw.cast<String>().toSet();
      }

      final pending = ids('pendingCryptoScopeIds');
      final revoked = ids('revokedScopeIds');
      final deleted = ids('deletedScopeIds');
      final denied = {...revoked, ...deleted};
      final raw = reply['scopes'];
      if (raw is! List) {
        throw const CollaborationException('invalid_response');
      }
      final scopes = raw
          .map((r) => SharedScope.fromJson(Map<String, dynamic>.from(r as Map)))
          .toList();
      final returned = scopes.map((s) => s.id).toSet();
      if (returned.length != scopes.length ||
          scopes.any((s) => !isSharedUuid(s.id) || denied.contains(s.id)) ||
          pending.any(denied.contains)) {
        throw const CollaborationException('invalid_response');
      }
      // Parents before children for local application. Missing parents are valid
      // for project-only invitations; a cyclic response is never applied.
      final ordered = <SharedScope>[];
      final todo = [...scopes];
      while (todo.isNotEmpty) {
        final ready = todo
            .where((s) => !todo.any((p) => p.id == s.parentSpaceId))
            .toList();
        if (ready.isEmpty) {
          throw const CollaborationException('invalid_response');
        }
        ordered.addAll(ready);
        todo.removeWhere(ready.contains);
      }
      var available = 0, restored = 0, revokedCount = 0;
      final unresolved = {...pending};
      await database.transaction(() async {
        _checkEpoch(epoch);
        await _validLease(partition);
        final oldRows = await database.rows(
          'SELECT id,data FROM scopes WHERE partition=?',
          [partition],
        );
        final old = {
          for (final row in oldRows)
            row['id'] as String: SharedScope.fromJson(
              CollaborationRepository._map(row['data']),
            ),
        };
        for (final entry in old.entries) {
          if (denied.contains(entry.key)) {
            await _upsertScope(
              partition,
              SharedScope.fromJson({
                ...entry.value.toJson(),
                'revoked': true,
                'deleted': deleted.contains(entry.key) || entry.value.deleted,
              }),
            );
            revokedCount++;
            await database.execute('DELETE FROM local_meta WHERE name=?', [
              'scope_reconciliation:$partition:${entry.key}',
            ]);
          } else if (!returned.contains(entry.key)) {
            // Omission, offline failure and pending proofs are not revocation.
            unresolved.add(entry.key);
            await database.execute(
              'INSERT INTO local_meta(name,value) VALUES(?,?) ON CONFLICT(name) DO UPDATE SET value=excluded.value',
              ['scope_reconciliation:$partition:${entry.key}', 'missing'],
            );
          }
        }
        for (final scope in ordered) {
          final previous = old[scope.id];
          if (pending.contains(scope.id) ||
              scope.revoked ||
              scope.deleted ||
              !scope.canRead ||
              (previous != null && previous.sequence > scope.sequence)) {
            unresolved.add(scope.id);
            await database.execute(
              'INSERT INTO local_meta(name,value) VALUES(?,?) ON CONFLICT(name) DO UPDATE SET value=excluded.value',
              ['scope_reconciliation:$partition:${scope.id}', 'crypto_pending'],
            );
            continue;
          }
          if (previous?.revoked == true) {
            // Only clear the old access block after the normal verified router
            // has supplied current authority. Do not rewrite queued requests,
            // drafts, receipts or independently blocked operations.
            await database.execute(
              'UPDATE scopes SET blocked=? WHERE partition=? AND id=?',
              [
                scope.role == SharedRole.viewer || scope.blocked ? 1 : 0,
                partition,
                scope.id,
              ],
            );
            restored++;
          }
          await _upsertScope(partition, scope);
          await database.execute('DELETE FROM local_meta WHERE name=?', [
            'scope_reconciliation:$partition:${scope.id}',
          ]);
          available++;
        }
        _checkEpoch(epoch);
      });
      _sharingRefresh = _sharingRefresh.next(
        all: true,
        invitationChange: false,
        affectedScopes: const {},
      );
      _sharingRefreshEpoch = epoch;
      await refreshLocal();
      _checkEpoch(epoch);
      final result = CollaborationAccessReview(
        available: available,
        restored: restored,
        revoked: revokedCount,
        unresolved: unresolved.length,
      );
      // Publish completion only after releasing our lease successfully.
      leased = false;
      await database.execute(
        'DELETE FROM sync_leases WHERE partition=? AND owner=?',
        [partition, _leaseOwner],
      );
      _checkEpoch(epoch);
      _lastAccessReview = result;
      _accessReviewEpoch = epoch;
      done.complete(result);
      return result;
    } catch (error, stack) {
      done.completeError(error, stack);
      rethrow;
    } finally {
      try {
        if (leased) {
          await database.execute(
            'DELETE FROM sync_leases WHERE partition=? AND owner=?',
            [partition, _leaseOwner],
          );
        }
      } finally {
        _accessReviewRunning = null;
      }
    }
  }
}
