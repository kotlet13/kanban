part of 'local_spaces_repository.dart';

/// Device-owned graph deletion shares one SQLite transaction with its preview
/// recheck. Linked server scopes require the server lifecycle API instead.
extension LocalSpaceLifecycle on LocalSpacesRepository {
  Future<Map<String, dynamic>> _spaceDeletionGraph(String id) async {
    final rows = await database.rows(
      'SELECT data FROM local_spaces WHERE id=?',
      [id],
    );
    if (rows.isEmpty || id == 'local') {
      throw const OrganizerConflictException(
        'Default personal space cannot be deleted',
      );
    }
    final space = LocalSpace.fromJson(
      jsonDecode(rows.single['data'] as String) as Map<String, dynamic>,
    );
    if (space.binding != null) {
      throw const OrganizerConflictException('Use the linked space lifecycle');
    }
    if ((await database.rows("SELECT name FROM local_meta WHERE name LIKE ?", [
      'space_publication_create:%:$id',
    ])).isNotEmpty) {
      throw const CollaborationException('local_space_publication_pending');
    }
    final workspace = await database.rows(
      'SELECT * FROM personal_workspaces WHERE id=?',
      [id],
    );
    if (workspace.any(
      (row) => row['partition'] != null || row['scope_id'] != null,
    )) {
      throw const OrganizerConflictException('Use the linked space lifecycle');
    }
    final records = await database.rows(
      'SELECT * FROM personal_records WHERE workspace=? ORDER BY id',
      [id],
    );
    final gardens = await database.rows(
      'SELECT g.id,g.payload FROM device_gardens g JOIN garden_space_links l ON l.garden_id=g.id WHERE l.space_id=? ORDER BY g.id',
      [id],
    );
    final ideas = await database.rows(
      'SELECT i.id,i.payload FROM device_ideas i JOIN idea_space_links l ON l.idea_id=i.id WHERE l.space_id=? ORDER BY i.id',
      [id],
    );
    final drafts = await database.rows(
      'SELECT * FROM idea_drafts WHERE workspace=? ORDER BY id',
      [id],
    );
    final assets = await database.rows(
      'SELECT workspace,sha256,metadata,length(bytes) size FROM idea_assets WHERE workspace=? ORDER BY sha256',
      [id],
    );
    final maps = await database.rows(
      'SELECT * FROM personal_record_map WHERE workspace=? ORDER BY id',
      [id],
    );
    final payments = <Map<String, Object?>>[];
    var blocked = false;
    bool references(Object? value) {
      if (value is List) {
        return value.any(references);
      }
      if (value is! Map) {
        return false;
      }
      if (value['id'] == id &&
              value.containsKey('partition') &&
              value['partition'] == null ||
          value['organizationAccountScopeId'] == id ||
          value['sourceScopeId'] == id && value['sourcePartition'] == null) {
        return true;
      }
      return value.values.any(references);
    }

    bool outside(Object? value) {
      if (value is List) {
        return value.any(outside);
      }
      if (value is! Map) {
        return false;
      }
      if (value['sourceScopeId'] is String &&
              (value['sourceScopeId'] != id ||
                  value['sourcePartition'] != null) ||
          value['organizationAccountScopeId'] is String &&
              value['organizationAccountScopeId'] != id) {
        return true;
      }
      return value.values.any(outside);
    }

    for (final table in [
      'linked_payment_cash',
      'linked_payment_events',
      'linked_payment_projections',
      'linked_payment_intents',
    ]) {
      for (final row in await database.rows(
        'SELECT * FROM $table ORDER BY data',
      )) {
        final owns = row['space_key'] == 'local:$id';
        final decoded = jsonDecode(row['data'] as String);
        final ref = references(decoded);
        if (owns || ref) {
          payments.add({'table': table, ...row});
          // Cross-space financial facts remain in their original ledgers. A
          // pending delivery can involve several stores and is blocked too.
          if (!owns || table == 'linked_payment_intents' || outside(decoded)) {
            blocked = true;
          }
        }
      }
    }
    final counts = {
      'spaces': 1,
      'projects': 0,
      'tasks': 0,
      'events': 0,
      'ideas': ideas.length,
      'photos': assets.length,
      'finance': 0,
      'other': gardens.length,
      'gardens': gardens.length,
      'drafts': drafts.length,
    };
    for (final row in records) {
      final key =
          {
            'project': 'projects',
            'task': 'tasks',
            'event': 'events',
            'financeEntry': 'finance',
            'financeAccount': 'finance',
            'financeTransfer': 'finance',
            'financeRecurrenceRule': 'finance',
          }[row['type']] ??
          'other';
      counts[key] = counts[key]! + 1;
    }
    final preview = <String, dynamic>{
      'scopeId': id,
      'name': space.name,
      'scopeNames': [space.name],
      'counts': counts,
      'canDelete': !blocked,
      'blockers': blocked
          ? [
              {'code': 'cross_scope_payment_dependency'},
            ]
          : [],
    };
    final digest = await Sha256().hash(
      utf8.encode(
        jsonEncode([
          rows,
          workspace,
          records,
          gardens,
          ideas,
          drafts,
          assets,
          maps,
          payments,
        ]),
      ),
    );
    preview['previewHash'] = digest.bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    return {'preview': preview, 'gardens': gardens, 'ideas': ideas};
  }

  Future<Map<String, dynamic>> previewSpaceDeletion(String id) =>
      database.transaction(
        () async =>
            (await _spaceDeletionGraph(id))['preview'] as Map<String, dynamic>,
      );

  Future<void> deleteSpace(Map<String, dynamic> preview) async {
    final id = preview['scopeId'] as String,
        identity = database.personalIdentityGeneration;
    var selected = false;
    await database.transaction(() async {
      final graph = await _spaceDeletionGraph(id);
      final current = graph['preview'] as Map<String, dynamic>;
      if (identity != database.personalIdentityGeneration) {
        throw const CollaborationException('session_changed');
      }
      if (preview['previewHash'] != current['previewHash']) {
        throw const CollaborationException('scope_deletion_preview_changed');
      }
      if (current['canDelete'] != true) {
        throw const CollaborationException('scope_deletion_blocked');
      }
      for (final pair in [('gardens', 'garden'), ('ideas', 'idea')]) {
        for (final row in graph[pair.$1] as List<Map<String, dynamic>>) {
          final payload = jsonDecode(row['payload'] as String) as Map;
          await database.execute(
            "INSERT INTO local_meta(name,value) VALUES(?,?) ON CONFLICT(name) DO UPDATE SET value=CAST(MAX(CAST(value AS INTEGER),CAST(excluded.value AS INTEGER)) AS TEXT)",
            [
              '${pair.$2}_record_revision:${row['id']}',
              '${(payload['revision'] as int? ?? 0) + 1}',
            ],
          );
          if (pair.$2 == 'idea') {
            await database.execute(
              "INSERT INTO local_meta(name,value) VALUES(?,?) ON CONFLICT(name) DO UPDATE SET value=CAST(MAX(CAST(value AS INTEGER),CAST(excluded.value AS INTEGER)) AS TEXT)",
              [
                'idea_deleted_revision:${row['id']}',
                '${(payload['revision'] as int? ?? 0) + 1}',
              ],
            );
          }
          await database.execute('DELETE FROM device_${pair.$1} WHERE id=?', [
            row['id'],
          ]);
        }
        await database.execute(
          "INSERT INTO local_meta(name,value) VALUES(?,'1') ON CONFLICT(name) DO UPDATE SET value=CAST(value AS INTEGER)+1",
          ['${pair.$2}_generation'],
        );
      }
      await database.execute(
        'DELETE FROM garden_space_links WHERE space_id=?',
        [id],
      );
      await database.execute('DELETE FROM idea_space_links WHERE space_id=?', [
        id,
      ]);
      await database.execute('DELETE FROM idea_drafts WHERE workspace=?', [id]);
      await database.execute('DELETE FROM idea_assets WHERE workspace=?', [id]);
      await database.execute('DELETE FROM personal_records WHERE workspace=?', [
        id,
      ]);
      await database.execute(
        'DELETE FROM personal_record_map WHERE workspace=?',
        [id],
      );
      await database.execute('DELETE FROM personal_workspaces WHERE id=?', [
        id,
      ]);
      for (final table in [
        'linked_payment_cash',
        'linked_payment_events',
        'linked_payment_projections',
      ]) {
        await database.execute('DELETE FROM $table WHERE space_key=?', [
          'local:$id',
        ]);
      }
      await database.execute('DELETE FROM local_meta WHERE name IN (?,?)', [
        'local_notification_preferences:$id',
        'local_scope_sound:$id',
      ]);
      await database.execute('DELETE FROM local_spaces WHERE id=?', [id]);
      selected = database.selectedLocalWorkspaceId == id;
      if (selected) {
        await database.execute(
          "INSERT INTO local_meta(name,value) VALUES('selected_local_space','local') ON CONFLICT(name) DO UPDATE SET value='local'",
        );
      }
      await database.touchPersonal();
    });
    if (selected) database.activateLocalWorkspace('local');
    database.personalChanged();
  }

  Future<void> archiveSpace(String id, {required bool archived}) async {
    await database.transaction(() async {
      final rows = await database.rows(
        'SELECT data FROM local_spaces WHERE id=?',
        [id],
      );
      if (rows.isEmpty || id == 'local') {
        throw const OrganizerConflictException(
          'Default personal space cannot be archived',
        );
      }
      final space = LocalSpace.fromJson(
        jsonDecode(rows.single['data'] as String) as Map<String, dynamic>,
      );
      if (space.binding != null) {
        throw const OrganizerConflictException(
          'Use the linked space lifecycle',
        );
      }
      if ((await database.rows(
        "SELECT name FROM local_meta WHERE name LIKE ?",
        ['space_publication_create:%:$id'],
      )).isNotEmpty) {
        throw const CollaborationException('local_space_publication_pending');
      }
      await database.execute('UPDATE local_spaces SET data=? WHERE id=?', [
        jsonEncode({...space.toJson(), 'archived': archived}),
        id,
      ]);
      await database.execute(
        'UPDATE personal_workspaces SET revision=revision+1 WHERE id=?',
        [id],
      );
      for (final kind in ['idea', 'garden']) {
        await database.execute(
          "INSERT INTO local_meta(name,value) VALUES(?,'1') ON CONFLICT(name) DO UPDATE SET value=CAST(value AS INTEGER)+1",
          ['${kind}_generation'],
        );
      }
      await database.touchPersonal();
    });
    database.personalChanged();
  }
}
