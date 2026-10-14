part of 'collaboration_repository.dart';

extension CollaborationPrivateActions on CollaborationRepository {
  Future<List<IdeaBoard>> _privateIdeaCandidates() async {
    return _localPublicationIdeas('local');
  }

  Future<PrivateSyncState> _privateSyncState(AccountSession profile) async {
    final rows = await database.rows(
      'SELECT * FROM personal_workspaces WHERE id=? AND enabled=1',
      ['private:${profile.partition}'],
    );
    final binding = rows.firstOrNull;
    final pending = await database.rows(
      'SELECT COUNT(*) AS n FROM outbox WHERE partition=? AND scope_id=?',
      [profile.partition, binding?['scope_id']],
    );
    final finance = await database.rows(
      'SELECT COUNT(*) AS n FROM finance_outbox WHERE partition=? AND scope_id=?',
      [profile.partition, binding?['scope_id']],
    );
    final localIdeas = await _privateIdeaCandidates();
    final localDrafts = await _localPublicationIdeaDrafts('local');
    return PrivateSyncState(
      available: _privateSyncSupported,
      enabled: binding != null,
      paused: binding?['paused'] == 1,
      partition: profile.partition,
      scopeId: binding?['scope_id'] as String?,
      localPendingCount:
          ((await database.rows(
                "SELECT COUNT(*) AS n FROM personal_records WHERE workspace='local' AND type!='reminder'",
              )).single['n']
              as int) +
          localIdeas.length +
          localDrafts
              .where((d) => !localIdeas.any((b) => b.id == d['id']))
              .length,
      pendingCount: (pending.single['n'] as int) + (finance.single['n'] as int),
    );
  }

  Future<bool> _activePrivateScope(
    String p,
    String scope,
  ) async => (await database.rows(
    'SELECT id FROM personal_workspaces WHERE partition=? AND scope_id=? AND enabled=1',
    [p, scope],
  )).isNotEmpty;
  Future<bool> _isPersonalScope(String p, String scope) async {
    final rows = await database.rows(
      'SELECT data FROM scopes WHERE partition=? AND id=?',
      [p, scope],
    );
    return rows.isNotEmpty &&
        CollaborationRepository._map(rows.single['data'])['kind'] == 'personal';
  }

  Future<bool> _privateScopeAllowed(String p, SharedScope scope) async {
    if (scope.kind != SharedScopeKind.personal) return true;
    final rows = await database.rows(
      'SELECT paused FROM personal_workspaces WHERE partition=? AND scope_id=? AND enabled=1',
      [p, scope.id],
    );
    return rows.isNotEmpty && rows.single['paused'] == 0;
  }

  Future<OrganizerSnapshot> _defaultPersonalPublicationSnapshot(
    SqliteOrganizerStorage storage,
  ) async {
    final generation = await database.rows(
      "SELECT value FROM local_meta WHERE name='organizer_generation'",
    );
    return (await storage.localSnapshot()).copyWith(
      revision: generation.isEmpty
          ? 0
          : int.parse(generation.single['value'] as String),
      workspaceKey: 'local',
    );
  }

  Future<PrivateSyncPreview> previewPrivateSync() async {
    final profile = _requireSession().profile;
    final storage = SqliteOrganizerStorage(
      database,
      legacyFactory: HiveOrganizerStorage.open,
    );
    await storage.initialize();
    final snapshot = await _defaultPersonalPublicationSnapshot(storage);
    final local = await storage.localSnapshot();
    final localIdeas = await _privateIdeaCandidates();
    final localDrafts = await _localPublicationIdeaDrafts('local');
    final issues = <String>[];
    final fakeBinding = {
      'id': 'preview',
      'partition': profile.partition,
      'scope_id': newSharedId(),
    };
    final map = {
      for (final r in snapshotRows(local).where((r) => r.type != 'reminder'))
        r.id: isSharedUuid(r.id) ? r.id : newSharedId(),
    };
    for (final r in snapshotRows(local).where((r) => r.type != 'reminder')) {
      try {
        final payload = privateWirePayload(r.json, r.type, map);
        final wireVersion = privateRecordWireVersion(r.type, r.json);
        if (privateFinancialType(r.type)) {
          if (wireVersion > _financeContractVersion) {
            issues.add('finance_upgrade_required');
          }
          validateSharedFinancePayload(
            SharedFinanceRecordType.values.byName(privateRecordType(r.type)),
            Map<String, dynamic>.from(payload),
            contractVersion: wireVersion,
          );
        } else {
          if (wireVersion > _recordContractVersion) {
            issues.add('planning_upgrade_required');
          }
          validateSharedPayload(
            SharedRecordType.values.byName(r.type),
            Map<String, dynamic>.from(payload),
            contractVersion: wireVersion,
            personal: true,
          );
        }
        if (r.type == 'task' &&
            ((payload['assigneeAccountIds'] as List).any(
              (id) => id != profile.accountId,
            ))) {
          issues.add('assignee_not_member');
        }
      } on Object {
        issues.add('private_record_invalid:${r.type}');
      }
    }
    final state = await _privateSyncState(profile);
    final candidates = [
      ...localIdeas,
      for (final draft in localDrafts)
        IdeaBoard.fromJson(CollaborationRepository._map(draft['payload'])),
      for (final draft in localDrafts.where((d) => d['base'] != null))
        IdeaBoard.fromJson(CollaborationRepository._map(draft['base'])),
    ];
    final caps = await database.rows(
      'SELECT value FROM local_meta WHERE name=?',
      ['capabilities:${profile.partition}'],
    );
    final features = caps.isEmpty
        ? const <String, dynamic>{}
        : CollaborationRepository._map(caps.single['value'])['features'] as Map;
    if (candidates.isNotEmpty &&
        (_recordContractVersion < (candidates.any((b) => b.version >= 2) ? 6 : 5) ||
            features['ideas'] != true ||
            candidates.any((b) => b.assets.isNotEmpty) &&
                features['ideaAssets'] != true)) {
      issues.add('ideas_upgrade_required');
    }
    for (final board in candidates) {
      try {
        board.validate();
        if (board.projectId != null &&
            !local.projects.any((p) => p.id == board.projectId)) {
          issues.add('idea_project_missing');
        }
        for (final asset in board.assets) {
          final rows = await database.rows(
            'SELECT bytes FROM idea_assets WHERE workspace=? AND sha256=?',
            ['local', asset.sha256],
          );
          if (rows.isEmpty) {
            issues.add('idea_asset_missing');
            continue;
          }
          await verifyIdeaAsset(
            asset,
            Uint8List.fromList(rows.single['bytes'] as List<int>),
          );
        }
      } on FormatException {
        issues.add('private_record_invalid:idea');
      }
    }
    final existing = await database.rows(
      'SELECT COUNT(*) AS n FROM records WHERE partition=? AND scope_id=? AND deleted=0',
      [profile.partition, state.scopeId ?? fakeBinding['scope_id']],
    );
    return PrivateSyncPreview(
      revision: snapshot.revision,
      recordCounts: {
        ...personalCounts(local),
        if (localIdeas.isNotEmpty) 'ideas': localIdeas.length,
        if (localDrafts.isNotEmpty) 'ideaDrafts': localDrafts.length,
      },
      existingRemoteCount: existing.single['n'] as int,
      issues: issues,
    );
  }

  Future<void> enablePrivateSync({required int expectedRevision}) async {
    final session = _requireSession(),
        epoch = _epoch,
        p = session.profile.partition;
    await _negotiate(session, epoch);
    final preview = await previewPrivateSync();
    if (preview.issues.any((issue) => issue.endsWith('upgrade_required'))) {
      throw const CollaborationException('client_upgrade_required');
    }
    if (!preview.canEnable) {
      throw const CollaborationException('validation_error');
    }
    if (!_privateSyncSupported) {
      throw const CollaborationException('private_sync_unavailable');
    }
    if (_syncing) await _syncDone?.future;
    _checkEpoch(epoch);
    _syncing = true;
    _syncEpoch = epoch;
    final done = _syncDone = Completer<void>();
    var leased = false;
    try {
      leased = await _claimLease(p);
      if (!leased) throw const CollaborationException('sync_busy');
      final storage = SqliteOrganizerStorage(
        database,
        legacyFactory: HiveOrganizerStorage.open,
      );
      await storage.initialize();
      final source = await _defaultPersonalPublicationSnapshot(storage);
      if (source.revision != expectedRevision) {
        throw const OrganizerConflictException(
          'Personal workspace changed; review again',
        );
      }
      final reply = await _callSession(session, epoch, 'personal.ensure', {});
      final scope = SharedScope.fromJson(
        reply['scope'] as Map<String, dynamic>,
      );
      if (scope.kind != SharedScopeKind.personal ||
          scope.role != SharedRole.owner) {
        throw const CollaborationException('invalid_response');
      }
      await database.transaction(() async {
        _checkEpoch(epoch);
        await _validLease(p);
        await _upsertScope(p, scope);
        await database.execute(
          'INSERT INTO personal_workspaces(id,partition,scope_id,enabled) VALUES(?,?,?,0) ON CONFLICT(id) DO NOTHING',
          ['private:$p', p, scope.id],
        );
      });
      // Reconcile the singleton before transferring any local candidate. IDs that
      // already exist with different contents are explicit collisions, not updates.
      var more = true;
      while (more) {
        await _renewLease(p);
        final cursor = (await database.rows(
          'SELECT cursor FROM scopes WHERE partition=? AND id=?',
          [p, scope.id],
        )).single['cursor'];
        final pulled = await _callSession(
          session,
          epoch,
          _recordContractVersion >= 6
              ? 'sync6.pull'
              : _recordContractVersion >= 5
              ? 'sync5.pull'
              : _recordContractVersion >= 4
              ? 'sync4.pull'
              : _recordContractVersion >= 3
              ? 'sync3.pull'
              : 'sync2.pull',
          {'scopeId': scope.id, 'cursor': cursor, 'limit': 100},
        );
        more = readBool(pulled, 'hasMore');
        final next = readInt(pulled, 'cursor');
        if (next < (cursor as int) || (more && next == cursor)) {
          throw const CollaborationException('invalid_response');
        }
        await database.transaction(() async {
          _checkEpoch(epoch);
          await _validLease(p);
          for (final record in pulled['records'] as List) {
            await _applyRemote(p, scope.id, _canonical(record, personal: true));
          }
          await database.execute(
            'UPDATE scopes SET cursor=? WHERE partition=? AND id=?',
            [next, p, scope.id],
          );
        });
      }
      final policy = await _fetchFinancePolicy(
        session,
        epoch,
        scope.id,
        syncLease: true,
      );
      if (!policy.canWrite) {
        throw const CollaborationException('finance_forbidden');
      }
      await _pullFinanceScope(session, epoch, scope.id);
      await database.transaction(() async {
        _checkEpoch(epoch);
        await _validLease(p);
        final current = await _defaultPersonalPublicationSnapshot(storage);
        if (current.revision != expectedRevision ||
            current.workspaceKey != source.workspaceKey) {
          throw const OrganizerConflictException(
            'Personal workspace changed; review again',
          );
        }
        final local = await storage.localSnapshot(), w = 'private:$p';
        final binding = {'id': w, 'partition': p, 'scope_id': scope.id};
        final rows = snapshotRows(local);
        for (final row in rows.where((r) => r.type != 'reminder')) {
          await database.execute(
            'INSERT INTO personal_record_map(workspace,id,remote_id,type) VALUES(?,?,?,?) ON CONFLICT(workspace,id) DO NOTHING',
            [
              w,
              row.id,
              isSharedUuid(row.id) ? row.id : newSharedId(),
              privateRecordType(row.type),
            ],
          );
        }
        for (final row in rows) {
          if (row.type == 'reminder') {
            await database.execute(
              'INSERT INTO personal_records(workspace,id,type,payload) VALUES(?,?,?,?) ON CONFLICT(workspace,id) DO UPDATE SET payload=excluded.payload',
              [w, row.id, row.type, jsonEncode(row.json)],
            );
            continue;
          }
          final remote = (await database.rows(
            'SELECT remote_id FROM personal_record_map WHERE workspace=? AND id=?',
            [w, row.id],
          )).single['remote_id'];
          final table = privateFinancialType(row.type)
              ? 'finance_records'
              : 'records';
          final existing = await database.rows(
            'SELECT * FROM $table WHERE partition=? AND scope_id=? AND id=?',
            [p, scope.id, remote],
          );
          if (existing.isNotEmpty) {
            final mapRows = await database.rows(
              'SELECT id,remote_id FROM personal_record_map WHERE workspace=?',
              [w],
            );
            final payload = privateWirePayload(row.json, row.type, {
              for (final m in mapRows)
                m['id'] as String: m['remote_id'] as String,
            });
            if (existing.single['deleted'] == 1 ||
                jsonEncode(
                      normalizeSharedPayloadDates(
                        Map<String, dynamic>.from(
                          privatePayloadForVersion(
                            CollaborationRepository._map(
                              existing.single['payload'],
                            ),
                            row.type,
                            privateRecordWireVersion(row.type, row.json),
                          ),
                        ),
                      ),
                    ) !=
                    jsonEncode(
                      normalizeSharedPayloadDates(
                        Map<String, dynamic>.from(payload),
                      ),
                    )) {
              throw const OrganizerConflictException(
                'Private record ID collision',
              );
            }
          } else {
            await queuePrivateRecord(
              database,
              binding,
              row.id,
              row.type,
              row.json,
            );
          }
        }
        for (final cost in rows.where(
          (r) => r.type == 'financeEntry' && r.json['taskId'] != null,
        )) {
          await pairPrivateTaskCostOperations(
            database,
            binding,
            cost.json['taskId'] as String,
            cost.id,
          );
        }
        // Ideas have their own editable asset/draft store. Import only the
        // explicitly reviewed anonymous candidates, preserving their originals.
        final importedIdeas = await _privateIdeaCandidates();
        final importedDrafts = await _localPublicationIdeaDrafts('local');
        for (final board in importedIdeas) {
          final remoteId = isSharedUuid(board.id) ? board.id : newSharedId();
          final projects = board.projectId == null
              ? const <Map<String, dynamic>>[]
              : await database.rows(
                  'SELECT remote_id FROM personal_record_map WHERE workspace=? AND id=?',
                  [w, board.projectId],
                );
          if (board.projectId != null && projects.isEmpty) {
            throw const OrganizerConflictException(
              'Missing private idea project',
            );
          }
          final imported = board.copyWith(
            id: remoteId,
            projectId: projects.firstOrNull?['remote_id'] as String?,
            clearProjectId: board.projectId == null,
          );
          final existing = await database.rows(
            'SELECT id FROM records WHERE partition=? AND scope_id=? AND id=?',
            [p, scope.id, remoteId],
          );
          if (existing.isNotEmpty) {
            throw const OrganizerConflictException('Private idea ID collision');
          }
          await _copyPublicationIdeaAssets('local', p, scope.id, imported);
          await _put(
            p,
            scope.id,
            SharedRecordType.idea,
            imported.id,
            imported.toJson(),
          );
          await database.execute(
            'INSERT INTO personal_record_map(workspace,id,remote_id,type) VALUES(?,?,?,?)',
            [w, board.id, remoteId, 'idea'],
          );
        }
        for (final draft in importedDrafts) {
          final original = IdeaBoard.fromJson(
            CollaborationRepository._map(draft['payload']),
          );
          var maps = await database.rows(
            'SELECT remote_id FROM personal_record_map WHERE workspace=? AND id=?',
            [w, original.id],
          );
          if (maps.isEmpty) {
            await database.execute(
              'INSERT INTO personal_record_map(workspace,id,remote_id,type) VALUES(?,?,?,?)',
              [w, original.id, original.id, 'idea'],
            );
            maps = [
              {'remote_id': original.id},
            ];
          }
          Future<IdeaBoard> mapped(IdeaBoard value) async {
            final project = value.projectId == null
                ? const <Map<String, dynamic>>[]
                : await database.rows(
                    'SELECT remote_id FROM personal_record_map WHERE workspace=? AND id=?',
                    [w, value.projectId],
                  );
            if (value.projectId != null && project.isEmpty) {
              throw const OrganizerConflictException(
                'Missing private draft project',
              );
            }
            return value.copyWith(
              id: maps.single['remote_id'] as String,
              projectId: project.firstOrNull?['remote_id'] as String?,
              clearProjectId: value.projectId == null,
            );
          }

          final board = await mapped(original);
          final base = draft['base'] == null
              ? null
              : await mapped(
                  IdeaBoard.fromJson(
                    CollaborationRepository._map(draft['base']),
                  ),
                );
          await _copyPublicationIdeaAssets('local', p, scope.id, board);
          if (base != null) {
            await _copyPublicationIdeaAssets('local', p, scope.id, base);
          }
          await database.execute(
            'INSERT INTO idea_drafts(workspace,id,payload,base) VALUES(?,?,?,?) ON CONFLICT(workspace,id) DO NOTHING',
            [
              'shared:$p:${scope.id}',
              board.id,
              jsonEncode(board.toJson()),
              base == null ? null : jsonEncode(base.toJson()),
            ],
          );
        }
        if (importedIdeas.isNotEmpty || importedDrafts.isNotEmpty) {
          final name = 'idea_import_archive:$p';
          final prior = await database.rows(
            'SELECT value FROM local_meta WHERE name=?',
            [name],
          );
          final journal = prior.isEmpty
              ? <String, dynamic>{
                  'partition': p,
                  'scopeId': scope.id,
                  'boards': <Object?>[],
                  'drafts': <Object?>[],
                }
              : CollaborationRepository._map(prior.single['value']);
          if (journal['partition'] != p || journal['scopeId'] != scope.id) {
            throw const OrganizerConflictException(
              'Private idea archive identity changed',
            );
          }
          (journal['boards'] as List).addAll(
            importedIdeas.map((b) => b.toJson()),
          );
          (journal['drafts'] as List).addAll(importedDrafts);
          await database.execute(
            'INSERT INTO local_meta(name,value) VALUES(?,?) ON CONFLICT(name) DO UPDATE SET value=excluded.value',
            [name, jsonEncode(journal)],
          );
          for (final board in importedIdeas) {
            await database.execute('DELETE FROM device_ideas WHERE id=?', [
              board.id,
            ]);
          }
          for (final draft in importedDrafts) {
            await database.execute(
              'DELETE FROM idea_drafts WHERE workspace=? AND id=?',
              ['local', draft['id']],
            );
          }
          // Imported sources are archived under this account, so they cannot
          // resurface as anonymous editable content after logout or deletion.
          final preserved = <String>{};
          for (final board in await _localPublicationIdeas('local')) {
            preserved.addAll(board.assets.map((a) => a.sha256));
          }
          for (final draft in await _localPublicationIdeaDrafts('local')) {
            preserved.addAll(
              IdeaBoard.fromJson(
                CollaborationRepository._map(draft['payload']),
              ).assets.map((a) => a.sha256),
            );
            if (draft['base'] != null) {
              preserved.addAll(
                IdeaBoard.fromJson(
                  CollaborationRepository._map(draft['base']),
                ).assets.map((a) => a.sha256),
              );
            }
          }
          final migrated = [
            ...importedIdeas,
            for (final draft in importedDrafts)
              IdeaBoard.fromJson(
                CollaborationRepository._map(draft['payload']),
              ),
            for (final draft in importedDrafts.where((d) => d['base'] != null))
              IdeaBoard.fromJson(CollaborationRepository._map(draft['base'])),
          ];
          for (final hash
              in migrated
                  .expand((b) => b.assets)
                  .map((a) => a.sha256)
                  .toSet()
                  .difference(preserved)) {
            await database.execute(
              'DELETE FROM idea_assets WHERE workspace=? AND sha256=?',
              ['local', hash],
            );
          }
        }
        await database.execute(
          'UPDATE personal_workspaces SET enabled=1,paused=0,migration_snapshot=? WHERE id=?',
          [OrganizerBackupCodec.encode(local), w],
        );
        await database.execute(
          'DELETE FROM personal_records WHERE workspace=?',
          [SqliteOrganizerStorage.localWorkspace],
        );
        await database.touchPersonal();
      });
      database.personalChanged();
    } finally {
      if (leased) {
        await database.execute(
          'DELETE FROM sync_leases WHERE partition=? AND owner=?',
          [p, _leaseOwner],
        );
      }
      _syncing = false;
      _syncEpoch = null;
      done.complete();
      await refreshLocal();
    }
    await syncNow();
  }

  Future<void> pausePrivateSync() async {
    final p = _requireSession().profile.partition;
    await database.execute(
      'UPDATE personal_workspaces SET paused=1 WHERE id=?',
      ['private:$p'],
    );
    await refreshLocal();
  }

  Future<void> resumePrivateSync() async {
    final p = _requireSession().profile.partition;
    await database.execute(
      'UPDATE personal_workspaces SET paused=0 WHERE id=?',
      ['private:$p'],
    );
    await refreshLocal();
    await syncNow();
  }
}

Map<String, int> personalCounts(OrganizerSnapshot s) => {
  'people': s.people.length,
  'financeAccounts': s.financeAccounts.length,
  'financeRecurrenceRules': s.financeRecurrenceRules.length,
  'projects': s.projects.length,
  'tasks': s.tasks.length,
  'shoppingLists': s.shoppingLists.length,
  'shoppingItems': s.shoppingItems.length,
  'events': s.events.length,
  'financeEntries': s.financeEntries.length,
  'reminders': s.reminders.length,
};
Map<String, Object?> privateWirePayload(
  Map<String, Object?> source,
  String type,
  Map<String, String> ids,
) {
  final p = Map<String, Object?>.of(source)
    ..remove('id')
    ..remove('revision')
    ..remove('createdByAccountId')
    ..remove('updatedByAccountId');
  for (final field in privateReferenceFields) {
    if (p[field] != null) p[field] = ids[p[field]] ?? p[field];
  }
  if (type == 'event') {
    p['startAt'] = p.remove('startsAt');
    p['endAt'] = p.remove('endsAt');
    p['assigneeAccountIds'] = [];
  }
  if (p['subjectPersonIds'] is List) {
    p['subjectPersonIds'] = (p['subjectPersonIds'] as List)
        .map((id) => ids[id] ?? id)
        .toList();
  }
  return privatePayloadForVersion(p, type, privateRecordWireVersion(type, p));
}
