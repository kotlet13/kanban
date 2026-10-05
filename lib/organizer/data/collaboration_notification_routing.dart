part of 'collaboration_repository.dart';

/// Account-bound notification navigation with current server authorization.
extension CollaborationNotificationRouting on CollaborationRepository {
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
