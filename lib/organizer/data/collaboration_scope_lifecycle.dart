part of 'collaboration_repository.dart';

/// Explicit server-confirmed graph deletion; uncertain delivery keeps its exact
/// request ID and approved preview. Offline drafts remain available for export.
extension CollaborationScopeLifecycle on CollaborationRepository {
  String _scopeDeletionKey(
    String partition,
    String scopeId,
    String? projectId,
  ) => 'scope_deletion_pending:$partition:$scopeId:${projectId ?? "scope"}';

  Future<Map<String, dynamic>> previewScopeDeletion(
    String scopeId, {
    String? projectId,
  }) async {
    if (!_scopeDeletionSupported) {
      throw const CollaborationException('client_upgrade_required');
    }
    final session = _requireSession(), epoch = _epoch;
    final pending = await database.rows(
      'SELECT value FROM local_meta WHERE name=?',
      [_scopeDeletionKey(session.profile.partition, scopeId, projectId)],
    );
    _checkEpoch(epoch);
    if (pending.isNotEmpty) {
      return Map<String, dynamic>.from(
        CollaborationRepository._map(pending.single['value'])['preview'] as Map,
      );
    }
    final preview = await _callSession(
      session,
      epoch,
      'scopes.deletionPreview',
      {'scopeId': scopeId, if (projectId != null) 'projectId': projectId},
    );
    if (preview['scopeId'] != scopeId ||
        preview['previewHash'] is! String ||
        preview['name'] is! String ||
        preview['counts'] is! Map ||
        (preview['counts'] as Map).values.any((v) => v is! int || v < 0) ||
        preview['canDelete'] is! bool) {
      throw const CollaborationException('invalid_response');
    }
    return preview;
  }

  Future<void> deleteScopeContents(
    Map<String, dynamic> preview, {
    String? projectId,
  }) async {
    if (!_scopeDeletionSupported) {
      throw const CollaborationException('client_upgrade_required');
    }
    if (preview['canDelete'] != true) {
      throw const CollaborationException('scope_deletion_blocked');
    }
    final session = _requireSession(), epoch = _epoch;
    final sid = preview['scopeId'] as String;
    final key = _scopeDeletionKey(session.profile.partition, sid, projectId);
    late Map<String, dynamic> request;
    await database.transaction(() async {
      _checkEpoch(epoch);
      final saved = await database.rows(
        'SELECT value FROM local_meta WHERE name=?',
        [key],
      );
      if (saved.isNotEmpty) {
        final pending = CollaborationRepository._map(saved.single['value']);
        request = Map<String, dynamic>.from(pending['request'] as Map);
        if (request['previewHash'] != preview['previewHash']) {
          throw const CollaborationException('scope_deletion_preview_changed');
        }
      } else {
        request = {
          'scopeId': sid,
          if (projectId != null) 'projectId': projectId,
          'previewHash': preview['previewHash'],
          'requestId': newSharedId(),
        };
        await database.execute(
          'INSERT INTO local_meta(name,value) VALUES(?,?)',
          [
            key,
            jsonEncode({'preview': preview, 'request': request}),
          ],
        );
      }
    });
    Map<String, dynamic> reply;
    try {
      reply = await _callSession(session, epoch, 'scopes.delete', request);
    } on CollaborationApiException catch (error) {
      // A definitive rejection did not commit. An interrupted/network request
      // stays durable and must retry with its original body, never a new UUID.
      if (const {
        'scope_deletion_preview_changed',
        'scope_deletion_blocked',
        'permission_revoked',
        'validation_error',
      }.contains(error.code)) {
        _checkEpoch(epoch);
        await database.execute('DELETE FROM local_meta WHERE name=?', [key]);
      }
      rethrow;
    }
    final deletedIds = (reply['deletedScopeIds'] as List)
        .cast<String>()
        .toSet();
    if (reply['deleted'] != true ||
        reply['scopeId'] != sid ||
        deletedIds.any((id) => !isSharedUuid(id))) {
      throw const CollaborationException('invalid_response');
    }
    await database.transaction(() async {
      _checkEpoch(epoch);
      for (final scopeId in deletedIds) {
        final rows = await database.rows(
          'SELECT data FROM scopes WHERE partition=? AND id=?',
          [session.profile.partition, scopeId],
        );
        if (rows.isNotEmpty) {
          await _upsertScope(
            session.profile.partition,
            SharedScope.fromJson({
              ...CollaborationRepository._map(rows.single['data']),
              'deleted': true,
              'revoked': true,
            }),
          );
        }
      }
      for (final pair in [('records', false), ('financeRecords', true)]) {
        for (final value in reply[pair.$1] as List) {
          final row = Map<String, dynamic>.from(value as Map);
          final scopeId = row['scopeId'] as String;
          if (scopeId != sid && !deletedIds.contains(scopeId)) {
            throw const CollaborationException('invalid_response');
          }
          if (deletedIds.contains(scopeId)) continue;
          final table = pair.$2 ? 'finance_records' : 'records';
          final outbox = pair.$2 ? 'finance_outbox' : 'outbox';
          await database.execute(
            "UPDATE $outbox SET state='blocked' WHERE partition=? AND scope_id=? AND record_id=? AND state='pending'",
            [session.profile.partition, scopeId, row['id']],
          );
          // Keep immutable unsent requests for export. Remove the live candidate
          // so a stale local draft cannot appear as a surviving project child.
          await database.execute(
            'UPDATE $table SET deleted=1,payload=NULL,server_revision=?,remote=? WHERE partition=? AND scope_id=? AND id=?',
            [
              row['revision'],
              jsonEncode(row),
              session.profile.partition,
              scopeId,
              row['id'],
            ],
          );
          await database.execute(
            r"DELETE FROM scheduled_reminders WHERE partition=? AND scope_id=? AND json_extract(data,'$.targetId')=?",
            [session.profile.partition, scopeId, row['id']],
          );
        }
      }
      await database.execute('DELETE FROM local_meta WHERE name=?', [key]);
    });
    await refreshLocal();
    await syncNow();
  }
}
