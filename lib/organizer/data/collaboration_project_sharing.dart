part of 'collaboration_repository.dart';

extension CollaborationProjectSharing on CollaborationRepository {
  Future<void> _projectSharingParent(
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
      CollaborationRepository._map(rows.single['data']),
    );
    if (scope.kind != SharedScopeKind.household ||
        !scope.canManage ||
        scope.accessPolicyVersion != 3) {
      throw const CollaborationException('space_access_upgrade_required');
    }
    if (!_spaceProjectMembershipSupported) {
      throw const CollaborationException('client_upgrade_required');
    }
  }

  Future<void> _projectSharingClean(String partition, String scopeId) async {
    // Do not rewrite queued operations, including operations not yet delivered
    // whose request IDs and immutable wire hashes must retain their meaning.
    for (final table in [
      'outbox',
      'finance_outbox',
      'conflicts',
      'finance_conflicts',
    ]) {
      final rows = await database.rows(
        'SELECT 1 FROM $table WHERE partition=? AND scope_id=? LIMIT 1',
        [partition, scopeId],
      );
      if (rows.isNotEmpty) {
        throw const CollaborationException('project_sharing_pending_changes');
      }
    }
    final payments = await database.rows(
      r"SELECT 1 FROM linked_payment_intents WHERE state NOT IN ('complete','local_only') AND (json_extract(data,'$.sourceSpaceKey')=? OR json_extract(data,'$.householdSpaceKey')=?) LIMIT 1",
      ['remote:$partition:$scopeId', 'remote:$partition:$scopeId'],
    );
    if (payments.isNotEmpty) {
      throw const CollaborationException('project_sharing_pending_changes');
    }
    final commands = await database.rows(
      r"SELECT 1 FROM commands WHERE partition=? AND json_extract(params,'$.scopeId')=? LIMIT 1",
      [partition, scopeId],
    );
    if (commands.isNotEmpty) {
      throw const CollaborationException('project_sharing_pending_changes');
    }
  }

  Future<ProjectSharingPreview> previewProjectSharing(
    String scopeId,
    String projectId,
  ) async {
    final session = _requireSession(), epoch = _epoch;
    await _projectSharingParent(session, epoch, scopeId);
    await _projectSharingClean(session.profile.partition, scopeId);
    final reply = await _callSession(
      session,
      epoch,
      'scopes.projectSharingPreview',
      {'scopeId': scopeId, 'projectId': projectId},
    );
    _checkEpoch(epoch);
    final preview = ProjectSharingPreview.fromJson(reply);
    if (preview.scopeId != scopeId || preview.projectId != projectId) {
      throw const CollaborationException('invalid_response');
    }
    return preview;
  }

  Future<SharedScope?> resumeProjectSharing(String scopeId) async {
    final session = _requireSession(), epoch = _epoch;
    final saved = await database.rows(
      'SELECT value FROM local_meta WHERE name=?',
      ['project_sharing_pending:${session.profile.partition}:$scopeId'],
    );
    _checkEpoch(epoch);
    if (saved.isEmpty) return null;
    final params = CollaborationRepository._map(saved.single['value']);
    return applyProjectSharing(
      ProjectSharingPreview(
        scopeId: scopeId,
        projectId: params['projectId'] as String,
        projectName: '',
        canApply: true,
        previewHash: params['previewHash'] as String,
      ),
      requestId: params['requestId'] as String,
    );
  }

  Future<SharedScope> applyProjectSharing(
    ProjectSharingPreview preview, {
    String? requestId,
  }) async {
    if (!preview.canApply) {
      throw const CollaborationException('project_sharing_blocked');
    }
    final session = _requireSession(),
        epoch = _epoch,
        partition = _session!.profile.partition;
    await _projectSharingParent(session, epoch, preview.scopeId);
    final key = 'project_sharing_pending:$partition:${preview.scopeId}';
    late Map<String, Object?> params;
    await database.transaction(() async {
      _checkEpoch(epoch);
      await _projectSharingClean(partition, preview.scopeId);
      final saved = await database.rows(
        'SELECT value FROM local_meta WHERE name=?',
        [key],
      );
      if (saved.isNotEmpty) {
        params = Map<String, Object?>.from(
          CollaborationRepository._map(saved.single['value']),
        );
        if (params['projectId'] != preview.projectId ||
            params['previewHash'] != preview.previewHash ||
            (requestId != null && params['requestId'] != requestId)) {
          throw const CollaborationException('project_sharing_pending_changes');
        }
      } else {
        params = {
          'scopeId': preview.scopeId,
          'projectId': preview.projectId,
          'previewHash': preview.previewHash,
          'requestId': requestId ?? newSharedId(),
        };
        await database.execute(
          'INSERT INTO local_meta(name,value) VALUES(?,?)',
          [key, jsonEncode(params)],
        );
      }
    });
    // Publish durable recovery immediately, including malformed replies and
    // local reconciliation errors that occur after the server committed.
    _checkEpoch(epoch);
    await refreshLocal();
    late Map<String, dynamic> reply;
    try {
      reply = await _callSession(
        session,
        epoch,
        'scopes.projectSharingApply',
        params,
      );
    } on CollaborationException catch (error) {
      if (error is CollaborationApiException &&
          !{
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
      if (epoch == _epoch) await refreshLocal();
      rethrow;
    }
    _checkEpoch(epoch);
    final scope = SharedScope.fromJson(reply['scope'] as Map<String, dynamic>);
    if (scope.id != preview.projectId ||
        scope.parentSpaceId != preview.scopeId ||
        scope.kind != SharedScopeKind.project) {
      throw const CollaborationException('invalid_response');
    }
    await database.transaction(() async {
      _checkEpoch(epoch);
      await _projectSharingClean(partition, preview.scopeId);
      await _projectSharingClean(partition, scope.id);
      await _upsertScope(partition, scope);
      for (final table in ['records', 'finance_records']) {
        final ids =
            (reply[table == 'records'
                        ? 'movedRecordIds'
                        : 'movedFinanceRecordIds']
                    as List)
                .cast<String>();
        for (final id in ids) {
          final rows = await database.rows(
            'SELECT * FROM $table WHERE partition=? AND scope_id=? AND id=?',
            [partition, preview.scopeId, id],
          );
          if (rows.isNotEmpty) {
            final existing = await database.rows(
              'SELECT * FROM $table WHERE partition=? AND scope_id=? AND id=?',
              [partition, scope.id, id],
            );
            if (existing.isNotEmpty &&
                (existing.single['type'] != rows.single['type'] ||
                    (existing.single['server_revision'] ==
                            rows.single['server_revision'] &&
                        existing.single['payload'] !=
                            rows.single['payload']))) {
              throw const CollaborationException('invalid_response');
            }
            final row = {...rows.single, 'scope_id': scope.id};
            final columns = row.keys.join(',');
            await database.execute(
              'INSERT OR IGNORE INTO $table($columns) VALUES(${List.filled(row.length, '?').join(',')})',
              row.values.toList(),
            );
          }
          await database.execute(
            'DELETE FROM $table WHERE partition=? AND scope_id=? AND id=?',
            [partition, preview.scopeId, id],
          );
        }
      }
      if (reply['projectRoot'] != null) {
        await _applyRemote(
          partition,
          scope.id,
          _canonical(reply['projectRoot']),
        );
      }
      for (final id in (reply['movedReminderIds'] as List).cast<String>()) {
        final rows = await database.rows(
          'SELECT data FROM scheduled_reminders WHERE partition=? AND id=?',
          [partition, id],
        );
        if (rows.isEmpty) continue;
        final data = {
          ...CollaborationRepository._map(rows.single['data']),
          'scopeId': scope.id,
        };
        await database.execute(
          'UPDATE scheduled_reminders SET scope_id=?,data=? WHERE partition=? AND id=?',
          [scope.id, jsonEncode(data), partition, id],
        );
      }
      await database.execute('DELETE FROM local_meta WHERE name=?', [key]);
      await database.execute(
        'UPDATE scopes SET cursor=0,finance_cursor=0,finance_complete=0 WHERE partition=? AND id=?',
        [partition, scope.id],
      );
    });
    await refreshLocal();
    await syncNow();
    _checkEpoch(epoch);
    return scope;
  }
}
