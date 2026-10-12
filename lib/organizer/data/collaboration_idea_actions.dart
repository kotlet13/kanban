part of 'collaboration_repository.dart';

extension CollaborationIdeaActions on CollaborationRepository {
  Future<void> saveIdea(
    String scopeId,
    IdeaBoard board, {
    bool isNew = false,
  }) => _edit(
    scopeId,
    (partition) => _put(
      partition,
      scopeId,
      SharedRecordType.idea,
      board.id,
      board.toJson(),
      expectedLocalRevision: isNew ? null : board.revision,
    ),
  );
  Future<void> deleteIdea(String scopeId, IdeaBoard board) => _edit(
    scopeId,
    (p) => _put(
      p,
      scopeId,
      SharedRecordType.idea,
      board.id,
      null,
      deleted: true,
      expectedLocalRevision: board.revision,
    ),
  );
  Future<void> _uploadIdeaAssets(
    DeviceSession session,
    int epoch,
    String scopeId,
    IdeaBoard board,
  ) async {
    final workspace = 'shared:${session.profile.partition}:$scopeId';
    for (final asset in board.assets) {
      final params = <String, Object?>{
        'scopeId': scopeId,
        'boardId': board.id,
        ...asset.toJson(),
      };
      final start = await _callSession(
        session,
        epoch,
        'ideas.asset.begin',
        params,
      );
      _checkIdeaAssetReply(asset, start);
      if (start['complete'] == true) continue;
      final rows = await database.rows(
        'SELECT bytes FROM idea_assets WHERE workspace=? AND sha256=?',
        [workspace, asset.sha256],
      );
      if (rows.isEmpty) {
        throw const CollaborationException('idea_asset_missing');
      }
      final bytes = Uint8List.fromList(rows.single['bytes'] as List<int>);
      await verifyIdeaAsset(asset, bytes);
      _checkEpoch(epoch);
      final offset = start['offset'];
      if (offset is! int || offset < 0 || offset > bytes.length) {
        throw const CollaborationException('invalid_response');
      }
      for (var i = offset; i < bytes.length; i += 262144) {
        final end = (i + 262144).clamp(0, bytes.length);
        final reply = await _callSession(session, epoch, 'ideas.asset.chunk', {
          'scopeId': scopeId,
          'boardId': board.id,
          'sha256': asset.sha256,
          'offset': i,
          'data': base64Encode(bytes.sublist(i, end)),
        });
        _checkIdeaAssetReply(asset, reply);
        if (reply['offset'] != end) {
          throw const CollaborationException('invalid_response');
        }
      }
      final complete = await _callSession(
        session,
        epoch,
        'ideas.asset.complete',
        {'scopeId': scopeId, 'boardId': board.id, 'sha256': asset.sha256},
      );
      _checkIdeaAssetReply(asset, complete);
      if (complete['complete'] != true || complete['offset'] != asset.size) {
        throw const CollaborationException('invalid_response');
      }
    }
  }

  Future<void> downloadIdeaAssets(String scopeId, IdeaBoard board) async {
    final session = _requireSession(),
        epoch = _epoch,
        workspace = 'shared:${_requireSession().profile.partition}:$scopeId';
    await _writableReadIdea(session.profile.partition, scopeId, board.id);
    for (final asset in board.assets) {
      if ((await database.rows(
        'SELECT sha256 FROM idea_assets WHERE workspace=? AND sha256=?',
        [workspace, asset.sha256],
      )).isNotEmpty) {
        continue;
      }
      final bytes = <int>[];
      while (bytes.length < asset.size) {
        final offset = bytes.length;
        final reply = await _callSession(session, epoch, 'ideas.asset.get', {
          'scopeId': scopeId,
          'boardId': board.id,
          'sha256': asset.sha256,
          'offset': offset,
          'limit': 262144,
        });
        _checkIdeaAssetReply(asset, reply);
        if (reply['sha256'] != asset.sha256 ||
            reply['size'] != asset.size ||
            reply['offset'] != offset) {
          throw const CollaborationException('invalid_response');
        }
        final chunk = base64Decode(reply['data'] as String);
        if (chunk.isEmpty ||
            chunk.length > 262144 ||
            bytes.length + chunk.length > asset.size) {
          throw const CollaborationException('invalid_response');
        }
        bytes.addAll(chunk);
      }
      final data = Uint8List.fromList(bytes);
      await verifyIdeaAsset(asset, data);
      _checkEpoch(epoch);
      await _writableReadIdea(session.profile.partition, scopeId, board.id);
      await database.execute(
        'INSERT INTO idea_assets(workspace,sha256,metadata,bytes) VALUES(?,?,?,?) ON CONFLICT(workspace,sha256) DO NOTHING',
        [workspace, asset.sha256, jsonEncode(asset.toJson()), data],
      );
      await database.touchPersonal();
    }
  }

  Future<bool> _rebaseIdeaConflict(
    String partition,
    String scopeId,
    Map<String, dynamic> op,
    Map<String, dynamic> canonical,
    int epoch,
  ) async {
    final request = CollaborationRepository._map(op['request']);
    if (request['type'] != 'idea' ||
        request['deleted'] == true ||
        canonical['deleted'] == true) {
      return false;
    }
    final bases = await database.rows(
      'SELECT value FROM local_meta WHERE name=?',
      ['idea_op_base:$partition:${op['op_id']}'],
    );
    if (bases.isEmpty) return false;
    try {
      final current = await _record(
        partition,
        scopeId,
        op['record_id'] as String,
      );
      if (current['deleted'] == 1) return false;
      final base = IdeaBoard.fromJson(
        CollaborationRepository._map(bases.single['value']),
      );
      final local = IdeaBoard.fromJson(
        CollaborationRepository._map(current['payload']),
      );
      final remote = IdeaBoard.fromJson(
        Map<String, dynamic>.from(canonical['payload'] as Map),
      );
      final merged = mergeIdeaBoards(base, local, remote);
      await database.transaction(() async {
        _checkEpoch(epoch);
        await _validLease(partition);
        await _writable(partition, scopeId);
        final latest = await _record(partition, scopeId, local.id);
        if (latest['local_revision'] != current['local_revision']) {
          throw const CollaborationException('stale_edit');
        }
        final queued = await database.rows(
          'SELECT op_id,scope_id,request,wire_version FROM outbox WHERE partition=? AND scope_id=? AND record_id=?',
          [partition, scopeId, local.id],
        );
        // Original immutable operations are retained verbatim in the encrypted
        // archive. The merged successor has a fresh operation identity.
        for (final old in queued) {
          final basis = await database.rows(
            'SELECT value FROM local_meta WHERE name=?',
            ['idea_op_base:$partition:${old['op_id']}'],
          );
          final archived = {
            ...old,
            if (basis.isNotEmpty) 'base': basis.single['value'],
          };
          await database.execute(
            'INSERT INTO local_meta(name,value) VALUES(?,?) ON CONFLICT(name) DO NOTHING',
            [
              'idea_rebased_op:$partition:${old['op_id']}',
              jsonEncode(archived),
            ],
          );
        }
        await database.execute(
          'DELETE FROM outbox WHERE partition=? AND scope_id=? AND record_id=?',
          [partition, scopeId, local.id],
        );
        await database.execute(
          'UPDATE records SET server_revision=?,remote=? WHERE partition=? AND scope_id=? AND id=?',
          [
            canonical['revision'],
            jsonEncode(canonical),
            partition,
            scopeId,
            local.id,
          ],
        );
        await _put(
          partition,
          scopeId,
          SharedRecordType.idea,
          local.id,
          merged.toJson(),
          expectedLocalRevision: current['local_revision'] as int,
        );
        final next = (await database.rows(
          'SELECT op_id FROM outbox WHERE partition=? AND scope_id=? AND record_id=? ORDER BY sequence DESC LIMIT 1',
          [partition, scopeId, local.id],
        )).single;
        await database.execute('UPDATE local_meta SET value=? WHERE name=?', [
          jsonEncode(remote.toJson()),
          'idea_op_base:$partition:${next['op_id']}',
        ]);
      });
      return true;
    } on IdeaMergeConflict {
      return false;
    }
  }

  void _checkIdeaAssetReply(IdeaAsset asset, Map<String, dynamic> reply) {
    if (reply['sha256'] != asset.sha256 ||
        reply['mime'] != asset.mime ||
        reply['size'] != asset.size ||
        reply['width'] != asset.width ||
        reply['height'] != asset.height) {
      throw const CollaborationException('invalid_response');
    }
  }

  Future<void> _writableReadIdea(
    String partition,
    String scopeId,
    String boardId,
  ) async {
    final scope = state.scopes
        .where((s) => s.id == scopeId && !s.revoked)
        .firstOrNull;
    if (scope == null || !state.localAccessAllowed) {
      throw const CollaborationException('permission_revoked');
    }
    final row = await _record(partition, scopeId, boardId);
    if (row['type'] != 'idea') {
      throw const CollaborationException('record_missing');
    }
  }
}

class SharedIdeaStorage extends IdeaStorage {
  SharedIdeaStorage(this.repository, this.partition, this.scopeId)
    : super(repository.database);
  final CollaborationRepository repository;
  final String partition, scopeId;
  @override
  String get workspaceKey => 'shared:$partition:$scopeId';
  @override
  int get identityGeneration => repository._epoch;
  @override
  Stream<void> get changes => Stream<void>.multi((controller) {
    final shared = repository.changes.listen((_) => controller.add(null));
    final personal = database.personalChanges.stream.listen(
      (_) => controller.add(null),
    );
    controller.onCancel = () async {
      await shared.cancel();
      await personal.cancel();
    };
  });
  SharedScope _identity() {
    if (repository._session?.profile.partition != partition ||
        !repository.state.localAccessAllowed) {
      throw const CollaborationException('session_changed');
    }
    final scope = repository.state.scopes
        .where((s) => s.id == scopeId)
        .firstOrNull;
    if (scope == null || scope.revoked) {
      throw const CollaborationException('permission_revoked');
    }
    return scope;
  }

  @override
  void checkAccess() {
    _identity();
  }

  @override
  Future<void> checkWritable() async {
    _identity();
    await repository._writable(partition, scopeId);
  }

  @override
  Future<void> validateEditorBase(IdeaBoard base) async {
    _identity();
  }

  @override
  Future<void> checkDurableAccess() async {
    _identity();
    final epoch = repository._epoch;
    final rows = await database.rows(
      'SELECT data FROM scopes WHERE partition=? AND id=?',
      [partition, scopeId],
    );
    repository._checkEpoch(epoch);
    _identity();
    if (rows.isEmpty ||
        SharedScope.fromJson(
          CollaborationRepository._map(rows.single['data']),
        ).revoked) {
      throw const CollaborationException('permission_revoked');
    }
  }

  @override
  Future<IdeaSnapshot> read() async {
    await checkDurableAccess();
    final scope = _identity(), epoch = repository._epoch;
    final data = await repository._scopeData(partition, scopeId);
    final revision =
        (await database.rows(
              "SELECT COALESCE(SUM(local_revision),0) AS revision FROM records WHERE partition=? AND scope_id=? AND type='idea'",
              [partition, scopeId],
            )).single['revision']
            as int;
    repository._checkEpoch(epoch);
    _identity();
    return IdeaSnapshot(
      revision: revision,
      workspaceKey: workspaceKey,
      canEdit: scope.canEdit,
      sharedScopeId: scopeId,
      boards: data.ideas,
    );
  }

  @override
  Future<void> write(
    IdeaSnapshot snapshot, {
    required int expectedRevision,
    bool allSpaces = false,
    String? expectedWorkspaceKey,
    int? expectedIdentityGeneration,
  }) async {
    _identity();
    if (allSpaces ||
        (expectedWorkspaceKey != null &&
            expectedWorkspaceKey != workspaceKey) ||
        (expectedIdentityGeneration != null &&
            expectedIdentityGeneration != identityGeneration)) {
      throw const OrganizerConflictException('Idea workspace changed');
    }
    snapshot.validate();
    await repository._edit(scopeId, (p) async {
      _identity();
      final previous = await read();
      if (previous.revision != expectedRevision) {
        throw const OrganizerConflictException('Idea changed; reload');
      }
      final old = {for (final b in previous.boards) b.id: b},
          next = {for (final b in snapshot.boards) b.id: b};
      for (final b in previous.boards.where((b) => !next.containsKey(b.id))) {
        await repository._put(
          p,
          scopeId,
          SharedRecordType.idea,
          b.id,
          null,
          deleted: true,
          expectedLocalRevision: b.revision,
        );
      }
      for (final b in snapshot.boards) {
        if (old[b.id] != null &&
            jsonEncode(old[b.id]!.toJson()) == jsonEncode(b.toJson())) {
          continue;
        }
        await repository._put(
          p,
          scopeId,
          SharedRecordType.idea,
          b.id,
          b.toJson(),
          expectedLocalRevision: old[b.id]?.revision,
        );
      }
    });
  }

  @override
  Future<void> ensureAssets(IdeaBoard board) async {
    _identity();
    await repository.downloadIdeaAssets(scopeId, board);
  }
}
