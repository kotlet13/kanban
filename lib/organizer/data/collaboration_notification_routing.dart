part of 'collaboration_repository.dart';

/// Account-bound notification navigation with current server authorization.
extension CollaborationNotificationRouting on CollaborationRepository {
  /// Revalidate a task that is already in the active local projection. This
  /// cannot grant access to a new target or read any financial record. The
  /// single scope pull is bounded to one page; the normal sync owns its cursor.
  Future<NotificationOpenResult> refreshVisibleTaskTarget(
    NotificationTarget target,
  ) {
    if (target.isPersonal ||
        target.records.length != 1 ||
        target.records.single.type != 'task' ||
        target.inboxIds.isNotEmpty) {
      throw const CollaborationException('invalid_notification_target');
    }
    if (_session == null || !target.matches(_session!.profile)) {
      return Future.value(
        NotificationOpenResult(
          status: NotificationOpenStatus.wrongAccount,
          target: target,
        ),
      );
    }
    final key = '$_epoch:${target.scopeId}:${target.records.single.recordId}';
    return _visibleTaskRefreshes.putIfAbsent(key, () {
      return _refreshVisibleTaskTarget(target).whenComplete(() {
        _visibleTaskRefreshes.remove(key);
      });
    });
  }

  Future<NotificationOpenResult> _refreshVisibleTaskTarget(
    NotificationTarget target,
  ) async {
    final session = _session, epoch = _epoch;
    NotificationOpenResult result(NotificationOpenStatus status) =>
        NotificationOpenResult(status: status, target: target);
    if (session == null || !target.matches(session.profile)) {
      return result(NotificationOpenStatus.wrongAccount);
    }
    final scopeId = target.scopeId!, recordId = target.records.single.recordId;
    bool accessible() =>
        _sessionInvalidReason == null &&
        state.scopes.any(
          (s) => s.id == scopeId && !s.revoked && !s.blocked && !s.archived,
        );
    Future<bool> storedAccess() async {
      final rows = await database.rows(
        'SELECT data,blocked FROM scopes WHERE partition=? AND id=?',
        [session.profile.partition, scopeId],
      );
      if (rows.isEmpty || rows.single['blocked'] == 1) return false;
      final stored = SharedScope.fromJson(
        CollaborationRepository._map(rows.single['data']),
      );
      return !stored.revoked && !stored.archived;
    }

    if (!accessible()) return result(NotificationOpenStatus.permissionDenied);
    if (!state.dataForScope(scopeId).tasks.any((t) => t.id == recordId)) {
      return result(NotificationOpenStatus.requiresConnection);
    }
    final elapsed = Stopwatch()..start();
    Future<Map<String, dynamic>> call(
      String operation,
      Map<String, Object?> params,
    ) => _callSession(
      session,
      epoch,
      operation,
      params,
    ).timeout(const Duration(seconds: 5) - elapsed.elapsed);
    try {
      final listed = await call('scopes.list', {});
      _checkEpoch(epoch);
      if (!accessible()) return result(NotificationOpenStatus.permissionDenied);
      final wire = (listed['scopes'] as List)
          .cast<Map>()
          .where((s) => s['id'] == scopeId)
          .firstOrNull;
      if (wire == null) {
        await _blockScope(session.profile.partition, scopeId, epoch);
        await refreshLocal();
        return result(NotificationOpenStatus.permissionDenied);
      }
      final scope = SharedScope.fromJson(Map<String, dynamic>.from(wire));
      await database.transaction(() async {
        _checkEpoch(epoch);
        if (!accessible() || !await storedAccess()) {
          throw const CollaborationException('permission_revoked');
        }
        await _upsertScope(session.profile.partition, scope);
      });
      await refreshLocal();
      if (!accessible()) return result(NotificationOpenStatus.permissionDenied);
      final rows = await database.rows(
        'SELECT cursor FROM scopes WHERE partition=? AND id=?',
        [session.profile.partition, scopeId],
      );
      final pulled = await call(
        _recordContractVersion >= 4
            ? 'sync4.pull'
            : _recordContractVersion >= 3
            ? 'sync3.pull'
            : (_recordContractVersion >= 2 ? 'sync2.pull' : 'sync.pull'),
        {'scopeId': scopeId, 'cursor': rows.single['cursor'], 'limit': 100},
      );
      final records = (pulled['records'] as List)
          .map(
            (r) =>
                _canonical(r, personal: scope.kind == SharedScopeKind.personal),
          )
          .toList();
      await database.transaction(() async {
        _checkEpoch(epoch);
        if (!accessible() || !await storedAccess()) {
          throw const CollaborationException('permission_revoked');
        }
        for (final record in records) {
          await _applyRemote(session.profile.partition, scopeId, record);
        }
      });
      await refreshLocal();
      _checkEpoch(epoch);
      if (!accessible()) return result(NotificationOpenStatus.permissionDenied);
      return result(
        state.dataForScope(scopeId).tasks.any((t) => t.id == recordId)
            ? NotificationOpenStatus.available
            : NotificationOpenStatus.deleted,
      );
    } on TimeoutException {
      _checkEpoch(epoch);
      return result(NotificationOpenStatus.offline);
    } on CollaborationException catch (error) {
      _checkEpoch(epoch);
      if (error.code == 'network') {
        return result(NotificationOpenStatus.offline);
      }
      if (error.code == 'permission_revoked') {
        await _blockScope(session.profile.partition, scopeId, epoch);
        await refreshLocal();
        return result(NotificationOpenStatus.permissionDenied);
      }
      rethrow;
    }
  }

  Future<NotificationOpenResult> openNotificationTarget(
    NotificationTarget target,
  ) async {
    final session = _session, epoch = _epoch;
    if (session == null || !target.matches(session.profile)) {
      return NotificationOpenResult(
        status: NotificationOpenStatus.wrongAccount,
        target: target,
      );
    }
    final scope = state.scopes.where((s) => s.id == target.scopeId).firstOrNull;
    if (scope == null || scope.revoked) {
      return NotificationOpenResult(
        status: NotificationOpenStatus.permissionDenied,
        target: target,
      );
    }
    final financial = target.records.any((r) => isFinancialRecordType(r.type));
    if (financial && !state.financePolicyForScope(scope.id).canRead) {
      return NotificationOpenResult(
        status: NotificationOpenStatus.permissionDenied,
        target: target,
      );
    }
    var offline = false, missing = false;
    try {
      if (financial) {
        final policy = await _fetchFinancePolicy(session, epoch, scope.id);
        await refreshLocal();
        if (!policy.canRead) {
          return NotificationOpenResult(
            status: NotificationOpenStatus.permissionDenied,
            target: target,
          );
        }
      }
      if (target.inboxIds.isNotEmpty) {
        for (final id in target.inboxIds) {
          final reply = await _callSession(session, epoch, 'inbox.open', {
            'id': id,
          });
          final wire = reply['target'] as Map<String, dynamic>;
          if (wire['scopeId'] != target.scopeId ||
              !target.records.any(
                (r) => r.type == wire['type'] && r.recordId == wire['id'],
              )) {
            throw const CollaborationException('invalid_notification_target');
          }
          if (wire['type'] != 'membership' &&
              (reply['record'] == null ||
                  (reply['record'] as Map)['deleted'] == true)) {
            missing = true;
          }
          if (reply['record'] != null) {
            await database.transaction(() async {
              _checkEpoch(epoch);
              if (isFinancialRecordType((wire['type'] as String))) {
                await _applyFinanceRemote(
                  session.profile.partition,
                  scope.id,
                  _financeCanonical(reply['record']),
                );
              } else {
                await _applyRemote(
                  session.profile.partition,
                  scope.id,
                  _canonical(
                    reply['record'],
                    personal: scope.kind == SharedScopeKind.personal,
                  ),
                );
              }
            });
          }
        }
        if (financial) await syncNow();
        await refreshLocal();
      } else {
        await _negotiate(session, epoch);
        final reply = await _callSession(session, epoch, 'scopes.list', {
          if (_privateSyncSupported) 'includePersonal': true,
        });
        if (!(reply['scopes'] as List).any(
          (r) => (r as Map)['id'] == scope.id,
        )) {
          await _blockScope(session.profile.partition, scope.id, epoch);
          await refreshLocal();
          return NotificationOpenResult(
            status: NotificationOpenStatus.permissionDenied,
            target: target,
          );
        }
        await syncNow();
      }
    } on CollaborationException catch (e) {
      if (e.code == 'network') {
        offline = true;
      } else if (e.code == 'permission_revoked' ||
          e.code == 'finance_forbidden') {
        if (e.code == 'permission_revoked') {
          await _blockScope(session.profile.partition, scope.id, epoch);
        } else {
          await database.transaction(() async {
            _checkEpoch(epoch);
            await _storeFinancePolicy(
              session.profile.partition,
              scope.id,
              const SharedFinancePolicy(),
            );
          });
        }
        await refreshLocal();
        return NotificationOpenResult(
          status: NotificationOpenStatus.permissionDenied,
          target: target,
        );
      } else {
        rethrow;
      }
    }
    _checkEpoch(epoch);
    if (financial && !state.financePolicyForScope(scope.id).canRead) {
      return NotificationOpenResult(
        status: NotificationOpenStatus.permissionDenied,
        target: target,
      );
    }
    for (final ref in target.records) {
      if (ref.type == 'membership') continue;
      final table = isFinancialRecordType(ref.type)
          ? 'finance_records'
          : 'records';
      final rows = await database.rows(
        'SELECT type,deleted FROM $table WHERE partition=? AND scope_id=? AND id=?',
        [session.profile.partition, scope.id, ref.recordId],
      );
      if (rows.isEmpty) {
        return NotificationOpenResult(
          status: NotificationOpenStatus.requiresConnection,
          target: target,
        );
      }
      if (rows.first['type'] != ref.type) {
        throw const CollaborationException('invalid_notification_target');
      }
      if (rows.first['deleted'] == 1) missing = true;
    }
    return NotificationOpenResult(
      status: missing
          ? NotificationOpenStatus.deleted
          : offline
          ? NotificationOpenStatus.offline
          : NotificationOpenStatus.available,
      target: target,
    );
  }
}
