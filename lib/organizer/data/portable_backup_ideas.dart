part of 'portable_backup_repository.dart';

extension PortableBackupIdeas on PortableBackupRepository {
  Future<Map<String, dynamic>> _exportIdeas(
    Map<String, dynamic> tables,
    List<String> completeness,
  ) async {
    final ideas = await IdeaStorage(database).readAll();
    final links = await database.rows(
      'SELECT idea_id,space_id FROM idea_space_links ORDER BY idea_id',
    );
    final ownership = {for (final r in links) r['idea_id']: r['space_id']};
    final allowed = {
      for (final r in await database.rows('SELECT id FROM local_spaces'))
        r['id'] as String,
    };
    final source = database.personalProfile?.partition;
    for (final row in tables['scopes'] as List) {
      allowed.add('shared:$source:${(row as Map)['id']}');
    }
    final drafts = (await database.rows(
      'SELECT workspace,id,payload,base FROM idea_drafts ORDER BY workspace,id',
    )).where((r) => allowed.contains(r['workspace'])).toList();
    final required = <String, IdeaAsset>{};
    void board(IdeaBoard b, String workspace) {
      for (final a in b.assets) {
        required['$workspace:${a.sha256}'] = a;
      }
    }

    for (final b in ideas.boards) {
      board(b, ownership[b.id] as String? ?? 'local');
    }
    for (final r in tables['records'] as List) {
      final row = r as Map;
      if (row['type'] == 'idea' && row['payload'] != null) {
        board(
          IdeaBoard.fromJson(backupMap(jsonDecode(row['payload'] as String))),
          'shared:$source:${row['scope_id']}',
        );
      }
    }
    for (final d in drafts) {
      board(
        IdeaBoard.fromJson(backupMap(jsonDecode(d['payload'] as String))),
        d['workspace'] as String,
      );
      if (d['base'] != null) {
        board(
          IdeaBoard.fromJson(backupMap(jsonDecode(d['base'] as String))),
          d['workspace'] as String,
        );
      }
    }
    for (final raw in tables['outbox'] as List) {
      final row = raw as Map,
          request = backupMap(jsonDecode(raw['request'] as String));
      final workspace = 'shared:$source:${row['scope_id']}';
      if (request['type'] == 'idea' && request['payload'] != null) {
        board(IdeaBoard.fromJson(backupMap(request['payload'])), workspace);
      }
      final bases = await database.rows(
        'SELECT value FROM local_meta WHERE name=?',
        ['idea_op_base:$source:${row['op_id']}'],
      );
      if (bases.isNotEmpty) {
        board(
          IdeaBoard.fromJson(
            backupMap(jsonDecode(bases.single['value'] as String)),
          ),
          workspace,
        );
      }
    }
    for (final raw in tables['conflicts'] as List) {
      final row = raw as Map;
      if (row['type'] == 'idea' && row['remote'] != null) {
        final remote = backupMap(jsonDecode(row['remote'] as String));
        if (remote['payload'] != null) {
          board(
            IdeaBoard.fromJson(backupMap(remote['payload'])),
            'shared:$source:${row['scope_id']}',
          );
        }
      }
    }
    final history =
        (await database.rows(
          "SELECT name,value FROM local_meta WHERE name LIKE 'idea_op_base:%' OR name LIKE ? OR name=?",
          ['idea_rebased_op:$source:%', 'idea_import_archive:$source'],
        )).where((r) {
          if (r['name'] == 'idea_import_archive:$source') {
            final archived = backupMap(jsonDecode(r['value'] as String));
            return archived['partition'] == source &&
                allowed.contains('shared:$source:${archived['scopeId']}');
          }
          if ((r['name'] as String).startsWith('idea_rebased_op:')) {
            final old = backupMap(jsonDecode(r['value'] as String));
            return (r['name'] as String).startsWith(
                  'idea_rebased_op:$source:',
                ) &&
                allowed.contains('shared:$source:${old['scope_id']}');
          }
          return (tables['outbox'] as List).any(
            (op) => r['name'] == 'idea_op_base:$source:${(op as Map)['op_id']}',
          );
        }).toList();
    for (final row in history) {
      if (row['name'] == 'idea_import_archive:$source') {
        final archived = backupMap(jsonDecode(row['value'] as String)),
            workspace =
                'shared:$source:${backupMap(jsonDecode(row['value'] as String))['scopeId']}';
        for (final raw in archived['boards'] as List) {
          board(IdeaBoard.fromJson(backupMap(raw)), workspace);
        }
        for (final raw in archived['drafts'] as List) {
          final draft = backupMap(raw);
          board(
            IdeaBoard.fromJson(
              backupMap(jsonDecode(draft['payload'] as String)),
            ),
            workspace,
          );
          if (draft['base'] != null) {
            board(
              IdeaBoard.fromJson(
                backupMap(jsonDecode(draft['base'] as String)),
              ),
              workspace,
            );
          }
        }
      }

      if ((row['name'] as String).startsWith('idea_rebased_op:')) {
        final old = backupMap(jsonDecode(row['value'] as String));
        final request = backupMap(jsonDecode(old['request'] as String));
        final archivedWorkspace = 'shared:$source:${old['scope_id']}';
        if (old['base'] != null && allowed.contains(archivedWorkspace)) {
          board(
            IdeaBoard.fromJson(backupMap(jsonDecode(old['base'] as String))),
            archivedWorkspace,
          );
        }
        if (request['payload'] != null) {
          final workspace =
              'shared:$source:${request['scopeId'] ?? old['scope_id']}';
          if (allowed.contains(workspace)) {
            board(IdeaBoard.fromJson(backupMap(request['payload'])), workspace);
          }
        }
      }
    }
    final assets = <Map<String, dynamic>>[];
    for (final row in await database.rows(
      'SELECT workspace,sha256,metadata,bytes FROM idea_assets ORDER BY workspace,sha256',
    )) {
      if (!allowed.contains(row['workspace'])) continue;
      final key = '${row['workspace']}:${row['sha256']}';
      if (!required.containsKey(key)) continue;
      final asset = IdeaAsset.fromJson(
            backupMap(jsonDecode(row['metadata'] as String)),
          ),
          bytes = Uint8List.fromList(row['bytes'] as List<int>);
      await verifyIdeaAsset(asset, bytes);
      assets.add({
        'workspace': row['workspace'],
        'sha256': row['sha256'],
        'metadata': row['metadata'],
        'data': base64Encode(bytes),
      });
      required.remove(key);
    }
    for (final key in required.keys) {
      completeness.add('idea_asset_missing:$key');
    }
    return {
      'ideas': ideas.toJson(),
      'ideaSpaceLinks': links,
      'ideaAssets': assets,
      'ideaDrafts': drafts,
      'ideaOperationHistory': history,
    };
  }

  Future<void> _verifyIdeaArchive(Map<String, dynamic> doc) async {
    if (doc['version'] != 5) return;
    for (final raw in doc['ideaAssets'] as List) {
      final row = backupMap(raw);
      await verifyIdeaAsset(
        IdeaAsset.fromJson(backupMap(jsonDecode(row['metadata'] as String))),
        Uint8List.fromList(base64Decode(row['data'] as String)),
      );
    }
  }

  Future<void> _restoreIdeas(
    Map<String, dynamic> doc,
    BackupRestoreMode mode,
  ) async {
    final storage = IdeaStorage(database),
        current = await IdeaStorage(database).readAll(),
        imported = backupIdeas(doc)!;
    final ids = current.boards.map((b) => b.id).toSet();
    if (mode != BackupRestoreMode.replace &&
        imported.boards.any((b) => ids.contains(b.id))) {
      throw const CollaborationException('backup_conflict');
    }
    await storage.write(
      IdeaSnapshot(
        boards: mode == BackupRestoreMode.replace
            ? imported.boards
            : [...current.boards, ...imported.boards],
      ),
      expectedRevision: current.revision,
      allSpaces: true,
    );
    for (final raw in doc['ideaSpaceLinks'] as List) {
      final row = backupMap(raw);
      await database.execute(
        'INSERT INTO idea_space_links(idea_id,space_id) VALUES(?,?) ON CONFLICT(idea_id) DO UPDATE SET space_id=excluded.space_id',
        [row['idea_id'], row['space_id']],
      );
    }
    // Per-account assets remain quarantined under their original partition until
    // an explicit authorized resume or standalone conversion is requested.
    for (final raw in doc['ideaAssets'] as List) {
      final row = backupMap(raw);
      if (await _deletedIdeaWorkspace(row['workspace'] as String)) continue;
      await database.execute(
        'INSERT INTO idea_assets(workspace,sha256,metadata,bytes) VALUES(?,?,?,?) ON CONFLICT(workspace,sha256) DO UPDATE SET metadata=excluded.metadata,bytes=excluded.bytes',
        [
          row['workspace'],
          row['sha256'],
          row['metadata'],
          Uint8List.fromList(base64Decode(row['data'] as String)),
        ],
      );
    }
    for (final raw in doc['ideaOperationHistory'] as List) {
      final row = backupMap(raw);
      final source = doc['source'] == null
          ? null
          : backupMap(doc['source'])['partition'];
      if (source != null &&
          (await database.rows('SELECT value FROM local_meta WHERE name=?', [
            'deleted_account:$source',
          ])).isNotEmpty) {
        continue;
      }
      await database.execute(
        'INSERT INTO local_meta(name,value) VALUES(?,?) ON CONFLICT(name) DO NOTHING',
        [row['name'], row['value']],
      );
    }
    for (final raw in doc['ideaDrafts'] as List) {
      final row = backupMap(raw);
      if (await _deletedIdeaWorkspace(row['workspace'] as String)) continue;
      await database.execute(
        'INSERT INTO idea_drafts(workspace,id,payload,base) VALUES(?,?,?,?) ON CONFLICT(workspace,id) DO UPDATE SET payload=excluded.payload,base=excluded.base',
        [row['workspace'], row['id'], row['payload'], row['base']],
      );
    }
  }

  Future<bool> _deletedIdeaWorkspace(String workspace) async {
    if (!workspace.startsWith('shared:')) return false;
    for (final row in await database.rows(
      "SELECT name FROM local_meta WHERE name LIKE 'deleted_account:%'",
    )) {
      if (workspace.startsWith(
        'shared:${(row['name'] as String).substring('deleted_account:'.length)}:',
      )) {
        return true;
      }
    }
    return false;
  }
}
