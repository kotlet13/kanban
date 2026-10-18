import '../support/synthetic_content_route_guard.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/data/idea_repository.dart';
import 'package:kanban/organizer/data/idea_storage.dart';
import 'package:kanban/organizer/data/unsent_work_recovery.dart';
import 'package:kanban/organizer/data/portable_backup_repository.dart';
import 'package:kanban/organizer/data/portable_backup_crypto.dart';
import 'package:kanban/organizer/data/sqlite_organizer_storage.dart';
import 'package:kanban/organizer/domain/idea_models.dart';
import 'collaboration_repository_test.dart'
    show FakeServer, FakeTransport, MemorySessionStore;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  test(
    'revoke/restart exports only own unsent task/finance/Idea and referenced photo; file review never sends',
    () async {
      final dir = await Directory.systemTemp.createTemp('own-unsent-recovery-');
      final file = File('${dir.path}/database.sqlite');
      final server = FakeServer(),
          transport = FakeTransport(server),
          sessions = MemorySessionStore();
      var db = CollaborationDatabase(NativeDatabase(file));
      var repo = CollaborationRepository(
        db,
        transport,
        sessions,
        ownsDatabase: false,
        contentRouteGuard: const SyntheticContentRouteGuard(),
      );
      await repo.initialize();
      await repo.login(
        serverUrl: 'https://synthetic.invalid',
        username: 'alice',
        password: 'synthetic',
      );
      final sid = await repo.createScope('Shared scope');
      await repo.createTask(scopeId: sid, title: 'Foreign cached title');
      await repo.syncNow();
      final sourceCount = server.records[sid]!.length;
      transport.offline = true;
      await repo.createTask(scopeId: sid, title: 'Own unsent task');
      final partition = repo.state.session!.partition,
          workspace = 'shared:${repo.state.session!.partition}:$sid';
      final ideas = IdeaRepository(IdeaStorage(db));
      await ideas.initialize();
      final asset = await ideas.importImage(
        Uint8List.fromList(img.encodePng(img.Image(width: 2, height: 3))),
      );
      final imageBytes = await ideas.readAsset(asset);
      await db.execute(
        'INSERT INTO idea_assets(workspace,sha256,metadata,bytes) VALUES(?,?,?,?)',
        [workspace, asset.sha256, jsonEncode(asset.toJson()), imageBytes!],
      );
      final board = IdeaBoard(
        id: newSharedId(),
        title: 'Own unsaved Idea',
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
        elements: [
          IdeaElement(
            id: newSharedId(),
            kind: IdeaElementKind.image,
            x: 0,
            y: 0,
            width: 200,
            height: 300,
            asset: asset,
          ),
        ],
      );
      final base = board.copyWith(title: 'Foreign downloaded base');
      await db.execute(
        'INSERT INTO idea_drafts(workspace,id,payload,base) VALUES(?,?,?,?)',
        [
          workspace,
          board.id,
          jsonEncode(board.toJson()),
          jsonEncode(base.toJson()),
        ],
      );
      await ideas.close();
      server.confirmRevocation(sid, 'alice');
      transport.offline = false;
      await repo.syncNow();
      final op = {
        'opId': newSharedId(),
        'scopeId': sid,
        'recordId': newSharedId(),
        'type': 'financeEntry',
        'baseRevision': 0,
        'payload': {'title': 'Own unsent expense', 'amountMinor': 100},
        'deleted': false,
      };
      await db.execute(
        'INSERT INTO finance_outbox(op_id,partition,scope_id,record_id,request,state,wire_version) VALUES(?,?,?,?,?,?,?)',
        [
          op['opId'],
          partition,
          sid,
          op['recordId'],
          jsonEncode(op),
          'blocked',
          1,
        ],
      );
      expect(repo.state.dataForScope(sid).tasks, isEmpty);
      final json = await repo.exportUnsentWork();
      expect(json, isNot(contains('Foreign cached title')));
      expect(json, isNot(contains('Foreign downloaded base')));
      expect(json, isNot(contains('finance_policy')));
      final doc = jsonDecode(json) as Map;
      expect(doc['schemaVersion'], 2);
      expect((doc['financeOperations'] as List).single['operation'], op);
      final backup = PortableBackupRepository(
        db,
        SqliteOrganizerStorage(db),
        MemoryBackupUiPreferencesStore(),
        collaboration: () => repo,
      );
      final authorizedCopy = await PortableBackupCrypto().decrypt(
        await backup.exportEncryptedBackup('synthetic recovery password'),
        'synthetic recovery password',
      );
      expect((authorizedCopy['tables'] as Map)['records'], isEmpty);
      expect((authorizedCopy['tables'] as Map)['finance_outbox'], isEmpty);
      expect(authorizedCopy['ideaDrafts'], isEmpty);
      expect(
        jsonEncode(authorizedCopy),
        isNot(contains('Foreign downloaded base')),
      );
      await File('${dir.path}/recovery.json').writeAsString(json);
      await repo.close();
      await db.close();
      db = CollaborationDatabase(NativeDatabase(file));
      repo = CollaborationRepository(
        db,
        transport,
        sessions,
        ownsDatabase: false,
        contentRouteGuard: const SyntheticContentRouteGuard(),
      );
      await repo.initialize();
      final reopened = await UnsentWorkRecovery.decode(
        await File('${dir.path}/recovery.json').readAsString(),
      );
      expect(
        reopened.candidates.map((c) => c.title),
        containsAll([
          'Own unsent task',
          'Own unsent expense',
          'Own unsaved Idea',
        ]),
      );
      expect(reopened.assets.values.single, imageBytes);
      expect(server.records[sid]!.length, sourceCount);
      expect(repo.state.dataForScope(sid).tasks, isEmpty);
      final corrupt = jsonDecode(json) as Map<String, dynamic>;
      (corrupt['ideaAssets'] as List).single['bytes'] = base64Encode([1, 2, 3]);
      await expectLater(
        UnsentWorkRecovery.decode(jsonEncode(corrupt)),
        throwsA(anything),
      );
      await repo.close();
      await db.close();
      await dir.delete(recursive: true);
    },
  );
}
