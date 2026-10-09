part of 'collaboration_repository.dart';

/// Remote permission changes require a live identity and an explicit reviewed action.
extension CollaborationOrganizationAccess on CollaborationRepository {
  Future<bool> organizationAccessAvailable() async {
    final session = _requireSession(), epoch = _epoch;
    final rows = await database.rows(
      'SELECT value FROM local_meta WHERE name=?',
      ['capabilities:${session.profile.partition}'],
    );
    _checkEpoch(epoch);
    if (rows.isEmpty) return false;
    final features = CollaborationRepository._map(
      rows.first['value'],
    )['features'];
    return features is Map &&
        features['organizationLeadership'] == true &&
        features['accessMigrationPreview'] == true;
  }

  Future<OrganizationAccessPreview> previewOrganizationAccess(
    String scopeId,
  ) async {
    final session = _requireSession(), epoch = _epoch;
    await _organizationOwner(session, epoch, scopeId);
    final reply = await _callSession(
      session,
      epoch,
      'scopes.accessMigrationPreview',
      {'scopeId': scopeId},
    );
    _checkEpoch(epoch);
    final preview = OrganizationAccessPreview.fromJson(reply);
    if (preview.scopeId != scopeId) {
      throw const CollaborationException('invalid_response');
    }
    return preview;
  }

  Future<SharedScope> applyOrganizationAccess(
    String scopeId,
    String previewHash, {
    String? requestId,
  }) async {
    final reply = await _organizationMutation(
      scopeId,
      'scopes.accessMigrationApply',
      {'scopeId': scopeId, 'previewHash': previewHash},
      requestId: requestId,
    );
    return SharedScope.fromJson(reply['scope'] as Map<String, dynamic>);
  }

  Future<void> setOrganizationLeader(
    String scopeId,
    String accountId,
    bool enabled, {
    String? requestId,
  }) async {
    await _organizationMutation(scopeId, 'scopes.setLeader', {
      'scopeId': scopeId,
      'accountId': accountId,
      'enabled': enabled,
    }, requestId: requestId);
  }

  Future<SharedScope> updateScopeMetadata(
    String scopeId,
    String name,
    String? address, {
    required int expectedRevision,
    String? requestId,
  }) async {
    validateSharedText(name, 200);
    if (address != null) validateSharedText(address, 2000, empty: true);
    final reply =
        await _organizationMutation(scopeId, 'scopes.updateMetadata', {
          'scopeId': scopeId,
          'name': name,
          'address': address,
          'expectedRevision': expectedRevision,
        }, requestId: requestId);
    return SharedScope.fromJson(reply['scope'] as Map<String, dynamic>);
  }

  Future<void> _scopeMetadataOwner(
    DeviceSession session,
    int epoch,
    String scopeId,
  ) async {
    final rows = await database.rows(
      'SELECT data FROM scopes WHERE partition=? AND id=?',
      [session.profile.partition, scopeId],
    );
    _checkEpoch(epoch);
    if (rows.isEmpty) throw const CollaborationException('permission_revoked');
    final scope = SharedScope.fromJson(
      CollaborationRepository._map(rows.first['data']),
    );
    if (!const {
          SharedScopeKind.household,
          SharedScopeKind.organization,
        }.contains(scope.kind) ||
        !scope.canManage) {
      throw const CollaborationException('permission_revoked');
    }
    final caps = await database.rows(
      'SELECT value FROM local_meta WHERE name=?',
      ['capabilities:${session.profile.partition}'],
    );
    _checkEpoch(epoch);
    final features = caps.isEmpty
        ? null
        : CollaborationRepository._map(caps.first['value'])['features'];
    if (features is! Map || features['scopeMetadata'] != true) {
      throw const CollaborationException('client_upgrade_required');
    }
  }

  Future<void> resumeOrganizationAccessChange(String scopeId) async {
    final session = _requireSession(), epoch = _epoch;
    final rows = await database.rows(
      'SELECT value FROM local_meta WHERE name=?',
      ['organization_access_pending:${session.profile.partition}:$scopeId'],
    );
    _checkEpoch(epoch);
    if (rows.isEmpty) return;
    final saved = CollaborationRepository._map(rows.first['value']);
    final params = Map<String, Object?>.from(saved['params'] as Map);
    final operation = saved['operation'] as String;
    final request = params.remove('requestId') as String;
    await _organizationMutation(scopeId, operation, params, requestId: request);
  }

  Future<void> _organizationOwner(
    DeviceSession session,
    int epoch,
    String scopeId,
  ) async {
    if (!isSharedUuid(scopeId)) {
      throw const CollaborationException('validation_error');
    }
    final rows = await database.rows(
      'SELECT data FROM scopes WHERE partition=? AND id=?',
      [session.profile.partition, scopeId],
    );
    _checkEpoch(epoch);
    if (rows.isEmpty) throw const CollaborationException('permission_revoked');
    final scope = SharedScope.fromJson(
      CollaborationRepository._map(rows.first['data']),
    );
    if (scope.kind != SharedScopeKind.organization || !scope.canManage) {
      throw const CollaborationException('permission_revoked');
    }
    if (!await organizationAccessAvailable()) {
      throw const CollaborationException('client_upgrade_required');
    }
    _checkEpoch(epoch);
  }

  Future<Map<String, dynamic>> _organizationMutation(
    String scopeId,
    String operation,
    Map<String, Object?> desired, {
    String? requestId,
  }) async {
    final session = _requireSession(), epoch = _epoch;
    if (operation == 'scopes.updateMetadata') {
      await _scopeMetadataOwner(session, epoch, scopeId);
    } else {
      await _organizationOwner(session, epoch, scopeId);
    }
    final key =
        'organization_access_pending:${session.profile.partition}:$scopeId';
    late Map<String, Object?> params;
    await database.transaction(() async {
      _checkEpoch(epoch);
      final rows = await database.rows(
        'SELECT value FROM local_meta WHERE name=?',
        [key],
      );
      if (rows.isNotEmpty) {
        final saved = CollaborationRepository._map(rows.first['value']);
        final old = Map<String, Object?>.from(saved['params'] as Map);
        final originalRequest = old.remove('requestId');
        if (saved['operation'] != operation ||
            jsonEncode(old) != jsonEncode(desired) ||
            (requestId != null && originalRequest != requestId)) {
          throw const CollaborationException('organization_access_pending');
        }
        params = {...old, 'requestId': originalRequest};
      } else {
        params = {...desired, 'requestId': requestId ?? newSharedId()};
        await database.execute(
          'INSERT INTO local_meta(name,value) VALUES(?,?)',
          [
            key,
            jsonEncode({'operation': operation, 'params': params}),
          ],
        );
      }
      _checkEpoch(epoch);
    });
    late Map<String, dynamic> reply;
    try {
      reply = await _callSession(session, epoch, operation, params);
    } on CollaborationException catch (error) {
      if (!const {
        'network',
        'session_changed',
        'auth_required',
        'device_revoked',
        'invalid_response',
      }.contains(error.code)) {
        await database.transaction(() async {
          _checkEpoch(epoch);
          await database.execute('DELETE FROM local_meta WHERE name=?', [key]);
        });
      }
      rethrow;
    }
    _checkEpoch(epoch);
    if (operation == 'scopes.accessMigrationApply' ||
        operation == 'scopes.updateMetadata') {
      final scope = SharedScope.fromJson(
        reply['scope'] as Map<String, dynamic>,
      );
      if (scope.id != scopeId ||
          (operation == 'scopes.accessMigrationApply' &&
              (scope.kind != SharedScopeKind.organization ||
                  scope.accessPolicyVersion != 2))) {
        throw const CollaborationException('invalid_response');
      }
      await database.transaction(() async {
        _checkEpoch(epoch);
        await _upsertScope(session.profile.partition, scope);
        await database.execute('DELETE FROM local_meta WHERE name=?', [key]);
        await _invalidateMemberDirectory(session.profile.partition, scopeId);
      });
    } else {
      final members = (reply['members'] as List)
          .map((r) => SharedMember.fromJson(r as Map<String, dynamic>))
          .toList();
      await database.transaction(() async {
        _checkEpoch(epoch);
        await database.execute(
          'DELETE FROM members WHERE partition=? AND scope_id=?',
          [session.profile.partition, scopeId],
        );
        for (final member in members) {
          await database.execute(
            'INSERT INTO members(partition,scope_id,account_id,data) VALUES(?,?,?,?)',
            [
              session.profile.partition,
              scopeId,
              member.accountId,
              jsonEncode(member.toJson()),
            ],
          );
        }
        await database.execute('DELETE FROM local_meta WHERE name=?', [key]);
        await _invalidateMemberDirectory(session.profile.partition, scopeId);
      });
    }
    await refreshLocal();
    await syncNow();
    _checkEpoch(epoch);
    return reply;
  }
}
