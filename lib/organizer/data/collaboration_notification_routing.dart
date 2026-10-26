part of 'collaboration_repository.dart';

/// Account-bound notification navigation with current server authorization.
extension CollaborationNotificationRouting on CollaborationRepository {
  /// Refresh display-only acceptance notices after proven admission. A complete
  /// bounded host snapshot may hide stale notices; it never establishes a
  /// membership change, grants keys or alters the ordinary inbox sync cursor.
  Future<void> refreshInvitationApprovalInbox({
    required bool Function() isCurrent,
  }) async {
    final session = _session, epoch = _epoch;
    if (session == null || _sessionInvalidReason != null || !isCurrent()) {
      return;
    }
    final captured = {
      for (final item in state.inbox)
        if (item.invitationAcceptance != null)
          item.id: item.invitationAcceptance!,
    };
    if (captured.isEmpty) return;
    final entries = <SharedInboxEntry>[];
    int? before;
    for (var pageNumber = 0; pageNumber < 5; pageNumber++) {
      _checkEpoch(epoch);
      if (!isCurrent()) return;
      final reply = await _callSession(session, epoch, 'inbox.list', {
        'limit': 100,
        if (before != null) 'beforeId': before,
      });
      _checkEpoch(epoch);
      if (!isCurrent()) return;
      final page = (reply['items'] as List)
          .map(
            (v) =>
                SharedInboxEntry.fromJson(Map<String, dynamic>.from(v as Map)),
          )
          .toList();
      var previous = before;
      for (final item in page) {
        if (item.id < 1 || previous != null && item.id >= previous) {
          throw const CollaborationException('invalid_response');
        }
        previous = item.id;
      }
      if (page.length > 100) {
        throw const CollaborationException('invalid_response');
      }
      entries.addAll(page);
      if (readBool(reply, 'hasMore')) {
        final next = reply['nextBeforeId'];
        if (next is! int ||
            next < 1 ||
            before != null && next >= before ||
            page.any((item) => item.id < next)) {
          throw const CollaborationException('invalid_response');
        }
        before = next;
        continue;
      }
      await database.transaction(() async {
        _checkEpoch(epoch);
        if (!isCurrent()) return;
        for (final entry in entries.where(
          (e) => e.invitationAcceptance != null,
        )) {
          _checkEpoch(epoch);
          if (!isCurrent()) return;
          await _applyInbox(session.profile.partition, entry);
        }
        for (final id in captured.keys) {
          if (entries.any((e) => e.id == id)) continue;
          // Preserve the orchestration of an immutable read already in flight.
          // The existing notification_missing reconciliation retires it safely.
          final queued = await database.rows(
            "SELECT 1 FROM commands WHERE partition=? AND entity_key=? AND state='pending'",
            [session.profile.partition, 'inbox:$id'],
          );
          if (queued.isNotEmpty) continue;
          final current = await database.rows(
            'SELECT data FROM inbox WHERE partition=? AND id=?',
            [session.profile.partition, id],
          );
          if (current.length == 1 &&
              captured[id]!.same(
                SharedInboxEntry.fromJson(
                  CollaborationRepository._map(current.single['data']),
                ).invitationAcceptance,
              )) {
            _checkEpoch(epoch);
            if (!isCurrent()) return;
            await database.execute(
              'DELETE FROM inbox WHERE partition=? AND id=?',
              [session.profile.partition, id],
            );
          }
        }
      });
      _checkEpoch(epoch);
      if (isCurrent()) await refreshLocal();
      return;
    }
    // A partial snapshot cannot show that an older exact notice disappeared.
  }

  /// Known local content follows the account coordinator's change hints. A
  /// hint never admits an unknown record, notification or financial target.
  /// Older servers retain the established targeted verification path.
  Future<bool> _knownTargetUsesCoordinator(
    DeviceSession session,
    int epoch,
    NotificationTarget target,
  ) async {
    if (target.inboxIds.isNotEmpty ||
        target.invitationAcceptance != null ||
        target.records.isEmpty ||
        target.records.any(
          (r) => r.type == 'membership' || isFinancialRecordType(r.type),
        )) {
      return false;
    }
    final p = session.profile.partition;
    final caps = await database.rows(
      'SELECT value FROM local_meta WHERE name=?',
      ['capabilities:$p'],
    );
    _checkEpoch(epoch);
    if (caps.isEmpty ||
        !(CollaborationRepository._map(
                      caps.single['value'],
                    )['accountChangeVersions']
                    as List? ??
                const [])
            .contains(1)) {
      return false;
    }
    for (final ref in target.records) {
      final rows = await database.rows(
        'SELECT type,deleted FROM records WHERE partition=? AND scope_id=? AND id=?',
        [p, target.scopeId, ref.recordId],
      );
      _checkEpoch(epoch);
      if (rows.length != 1 ||
          rows.single['type'] != ref.type ||
          rows.single['deleted'] != 0) {
        return false;
      }
    }
    return true;
  }

  /// Revalidate an already visible task through the normal change coordinator.
  /// Unknown/older-server paths retain the bounded single-scope fallback below.
  /// The task preview itself does not grant new access or prepare finance;
  /// ordinary queued account work remains owned by the existing coordinator.
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
      visibleTaskMetadata: operation == 'scopes.list'
          ? CryptoVisibleTaskMetadataTarget(scopeId, recordId)
          : null,
    ).timeout(const Duration(seconds: 5) - elapsed.elapsed);
    try {
      if (await _knownTargetUsesCoordinator(session, epoch, target)) {
        await syncNow();
        _checkEpoch(epoch);
        if (!accessible() || !await storedAccess()) {
          return result(NotificationOpenStatus.permissionDenied);
        }
        return result(
          state.dataForScope(scopeId).tasks.any((t) => t.id == recordId)
              ? NotificationOpenStatus.available
              : NotificationOpenStatus.deleted,
        );
      }
      final listed = await call('scopes.list', {});
      _checkEpoch(epoch);
      if ((listed['pendingCryptoScopeIds'] as List? ?? const []).contains(
        scopeId,
      )) {
        return result(NotificationOpenStatus.requiresConnection);
      }
      if (elapsed.elapsed >= const Duration(seconds: 5)) {
        return result(NotificationOpenStatus.offline);
      }
      if (!accessible()) return result(NotificationOpenStatus.permissionDenied);
      final wire = (listed['scopes'] as List)
          .cast<Map>()
          .where((s) => s['id'] == scopeId)
          .firstOrNull;
      if (wire == null) {
        await _blockScope(session.profile.partition, scopeId, epoch);
        await refreshLocal(scopeIds: {scopeId});
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
      await refreshLocal(scopeIds: {scopeId});
      if (!accessible()) return result(NotificationOpenStatus.permissionDenied);
      final rows = await database.rows(
        'SELECT cursor FROM scopes WHERE partition=? AND id=?',
        [session.profile.partition, scopeId],
      );
      final pulled = await call(
        _recordContractVersion >= 6
            ? 'sync6.pull'
            : _recordContractVersion >= 5
            ? 'sync5.pull'
            : _recordContractVersion >= 4
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
      await refreshLocal(scopeIds: {scopeId});
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
      if (error.code == 'permission_revoked' || error.code == 'scope_deleted') {
        await _blockScope(session.profile.partition, scopeId, epoch);
        await refreshLocal(scopeIds: {scopeId});
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
    if (scope == null ||
        scope.revoked ||
        scope.blocked ||
        scope.archived ||
        (target.invitationAcceptance != null && !scope.canManage)) {
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
    final contextTargets = <NotificationRecordTarget>[];
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
            if (_recordContractVersion >= 5)
              'recordContractVersion': _recordContractVersion,
          });
          final wire = reply['target'] as Map<String, dynamic>;
          if (wire['scopeId'] != target.scopeId ||
              !target.records.any(
                (r) => r.type == wire['type'] && r.recordId == wire['id'],
              )) {
            throw const CollaborationException('invalid_notification_target');
          }
          if (target.invitationAcceptance != null) {
            final item = SharedInboxEntry.fromJson(
              Map<String, dynamic>.from(reply['item'] as Map),
            );
            if (item.id != id ||
                !target.invitationAcceptance!.same(item.invitationAcceptance)) {
              throw const CollaborationException('invalid_notification_target');
            }
          }
          if (wire['type'] != 'membership' &&
              (reply['record'] == null ||
                  (reply['record'] as Map)['deleted'] == true)) {
            missing = true;
          }
          if (wire['type'] == 'shoppingItem' &&
              reply['contextRecord'] != null) {
            final parent = _canonical(
              reply['contextRecord'],
              personal: scope.kind == SharedScopeKind.personal,
            );
            if (parent['type'] != 'shoppingList' || parent['deleted'] == true) {
              throw const CollaborationException('invalid_notification_target');
            }
            await database.transaction(() async {
              _checkEpoch(epoch);
              await _applyRemote(session.profile.partition, scope.id, parent);
            });
            final id = parent['id'] as String;
            if (!contextTargets.any((record) => record.recordId == id)) {
              contextTargets.add(
                NotificationRecordTarget(type: 'shoppingList', recordId: id),
              );
            }
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
        if (!await _knownTargetUsesCoordinator(session, epoch, target)) {
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
    if (offline && target.invitationAcceptance != null) {
      return NotificationOpenResult(
        status: NotificationOpenStatus.requiresConnection,
        target: target,
      );
    }
    if (_sessionInvalidReason != null ||
        !state.scopes.any(
          (s) =>
              s.id == scope.id &&
              s.canRead &&
              !s.blocked &&
              !s.deleted &&
              !s.archived,
        )) {
      return NotificationOpenResult(
        status: NotificationOpenStatus.permissionDenied,
        target: target,
      );
    }
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
      status: missing && contextTargets.isEmpty
          ? NotificationOpenStatus.deleted
          : offline
          ? NotificationOpenStatus.offline
          : NotificationOpenStatus.available,
      target: contextTargets.isEmpty
          ? target
          : NotificationTarget(
              serverUrl: target.serverUrl,
              serverId: target.serverId,
              accountId: target.accountId,
              scopeId: target.scopeId,
              localSpaceId: target.localSpaceId,
              inboxIds: target.inboxIds,
              records: [
                ...target.records,
                for (final record in contextTargets)
                  if (!target.records.any(
                    (existing) =>
                        existing.type == record.type &&
                        existing.recordId == record.recordId,
                  ))
                    record,
              ],
            ),
    );
  }
}
