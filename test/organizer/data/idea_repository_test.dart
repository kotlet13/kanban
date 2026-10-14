import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/account_deletion_store.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'account_deletion_repository_test.dart' show DeletionServer;
import 'package:kanban/organizer/data/idea_repository.dart';
import 'package:kanban/organizer/data/idea_storage.dart';
import 'package:kanban/organizer/data/organizer_repository.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'collaboration_repository_test.dart' show FakeServer, MemorySessionStore;
import 'private_sync_test_support.dart';
import 'package:kanban/organizer/data/portable_backup_crypto.dart';
import 'package:kanban/organizer/data/portable_backup_repository.dart';
import 'package:kanban/organizer/data/sqlite_organizer_storage.dart';
import 'package:kanban/organizer/domain/idea_models.dart';

const id = '11111111-1111-4111-8111-111111111111';
const e1 = '22222222-2222-4222-8222-222222222222';
const e2 = '33333333-3333-4333-8333-333333333333';
final now = DateTime.utc(2026, 10, 12);
IdeaElement note(String id, {String text = 'text'}) => IdeaElement(
  id: id,
  kind: IdeaElementKind.sticky,
  x: 20,
  y: 20,
  width: 200,
  height: 100,
  text: text,
);
IdeaBoard board() => IdeaBoard(
  id: id,
  title: 'Sketch',
  elements: [note(e1), note(e2)],
  createdAt: now,
  updatedAt: now,
);

class IdeaPrivateSeedTransport extends PersonalTransport {
  IdeaPrivateSeedTransport(super.server);
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
    if (operation == 'ideas.asset.begin') {
      throw const CollaborationException('network');
    }
    final result = await super.call(
      serverUrl: serverUrl,
      operation: operation == 'sync5.pull' ? 'sync2.pull' : operation,
      params: params,
      token: token,
      allowLocalHttp: allowLocalHttp,
    );
    if (operation == 'capabilities') {
      return {
        ...result,
        'recordContractVersions': [1, 2, 3, 4, 5],
        'features': {
          ...result['features'] as Map<String, dynamic>,
          'accountDeletion': true,
          'ideas': true,
          'ideaAssets': true,
        },
      };
    }
    return result;
  }
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  test(
    'element merge preserves distinct edits and deletion versus edit conflicts',
    () {
      final base = board(),
          local = board().copyWith(
            elements: [
              note(e1, text: 'left'),
              note(e2),
            ],
          ),
          remote = board().copyWith(
            elements: [
              note(e1),
              note(e2, text: 'right'),
            ],
          );
      final result = mergeIdeaBoards(base, local, remote);
      expect(result.elements.map((e) => e.text), ['left', 'right']);
      expect(
        () => mergeIdeaBoards(
          base,
          local,
          board().copyWith(
            elements: [
              note(e1, text: 'other'),
              note(e2),
            ],
          ),
        ),
        throwsA(isA<IdeaMergeConflict>()),
      );
      expect(
        () => mergeIdeaBoards(base, base.copyWith(elements: [note(e2)]), local),
        throwsA(isA<IdeaMergeConflict>()),
      );
    },
  );
  test(
    'real SQLite restart preserves board, draft, normalized private image bytes',
    () async {
      final dir = await Directory.systemTemp.createTemp('idea-sqlite-');
      final file = File('${dir.path}/ideas.sqlite');
      var db = CollaborationDatabase(NativeDatabase(file));
      var repo = IdeaRepository(IdeaStorage(db));
      await repo.initialize();
      final asset = await repo.importImage(
        Uint8List.fromList(img.encodePng(img.Image(width: 8, height: 6))),
      );
      final image = IdeaElement(
        id: e1,
        kind: IdeaElementKind.image,
        x: 1,
        y: 1,
        width: 80,
        height: 60,
        asset: asset,
      );
      final candidate = board().copyWith(elements: [image]);
      await repo.saveDraft(candidate, base: board());
      await repo.saveBoard(candidate, isNew: true);
      final bytes = await repo.readAsset(asset);
      await repo.close();
      await db.close();
      db = CollaborationDatabase(NativeDatabase(file));
      repo = IdeaRepository(IdeaStorage(db));
      await repo.initialize();
      expect(
        repo.snapshot.boards.single.elements.single.asset!.sha256,
        asset.sha256,
      );
      expect(await repo.readAsset(asset), bytes);
      expect(
        (await repo.readDraft(id))!.elements.single.kind,
        IdeaElementKind.image,
      );
      expect((await repo.readDraftBase(id))!.elements.length, 2);
      await repo.close();
      await db.close();
      await dir.delete(recursive: true);
    },
  );
  test('workspace switch rejects late editor writes', () async {
    final db = CollaborationDatabase(NativeDatabase.memory());
    final repo = IdeaRepository(IdeaStorage(db));
    await repo.initialize();
    final snapshot = repo.snapshot;
    repo.storage.database.activateLocalWorkspace('other');
    await expectLater(
      repo.saveBoard(
        board(),
        isNew: true,
        expectedWorkspaceKey: snapshot.workspaceKey,
      ),
      throwsA(isA<OrganizerConflictException>()),
    );
    await repo.close();
    await db.close();
  });
  test(
    'portable encrypted content6 restores actual image and draft into fresh SQLite',
    () async {
      final db = CollaborationDatabase(NativeDatabase.memory());
      final local = SqliteOrganizerStorage(db);
      await local.initialize();
      final repo = IdeaRepository(IdeaStorage(db));
      await repo.initialize();
      final asset = await repo.importImage(
        Uint8List.fromList(img.encodePng(img.Image(width: 4, height: 3))),
      );
      final candidate = board().copyWith(
        elements: [
          IdeaElement(
            id: e1,
            kind: IdeaElementKind.image,
            x: 0,
            y: 0,
            width: 40,
            height: 30,
            asset: asset,
          ),
        ],
      );
      await repo.saveBoard(candidate, isNew: true);
      await repo.saveDraft(candidate.copyWith(title: 'Draft'), base: candidate);
      final backup = PortableBackupRepository(
        db,
        local,
        MemoryBackupUiPreferencesStore(),
      );
      const password = 'long enough secret password';
      final encrypted = await backup.exportEncryptedBackup(password);
      final document = await PortableBackupCrypto().decrypt(
        encrypted,
        password,
      );
      expect(document['version'], 6);
      expect((document['ideaAssets'] as List).single['data'], isNotEmpty);
      final fresh = CollaborationDatabase(NativeDatabase.memory());
      final target = SqliteOrganizerStorage(fresh);
      await target.initialize();
      final restore = PortableBackupRepository(
        fresh,
        target,
        MemoryBackupUiPreferencesStore(),
      );
      await restore.restoreEncryptedBackup(
        encrypted,
        password,
        mode: BackupRestoreMode.replace,
        expectedPersonalRevision: (await target.read()).revision,
      );
      final reopened = IdeaRepository(IdeaStorage(fresh));
      await reopened.initialize();
      expect(await reopened.readAsset(asset), await repo.readAsset(asset));
      expect((await reopened.readDraft(id))!.title, 'Draft');
      await reopened.close();
      await fresh.close();
      await repo.close();
      await db.close();
    },
  );
  test(
    'normalized images remove PNG text and reject hash/dimension tampering',
    () async {
      final db = CollaborationDatabase(NativeDatabase.memory());
      final repo = IdeaRepository(IdeaStorage(db));
      await repo.initialize();
      final image = img.Image(
        width: 5,
        height: 7,
        textData: {'private': 'GPS coordinate'},
      );
      final asset = await repo.importImage(
        Uint8List.fromList(img.encodePng(image)),
      );
      final bytes = (await repo.readAsset(asset))!;
      expect(img.decodePng(bytes)!.textData, isNull);
      final wrong = IdeaAsset(
        sha256: asset.sha256,
        mime: asset.mime,
        size: asset.size,
        width: 6,
        height: 7,
      );
      await expectLater(
        verifyIdeaAsset(wrong, bytes),
        throwsA(isA<FormatException>()),
      );
      final corrupted = Uint8List.fromList(bytes)..[bytes.length - 1] ^= 1;
      await expectLater(
        verifyIdeaAsset(asset, corrupted),
        throwsA(isA<FormatException>()),
      );
      await repo.close();
      await db.close();
    },
  );
  test(
    'schema8 migration retains old rows and adds private idea tables',
    () async {
      final dir = await Directory.systemTemp.createTemp('idea-migration-');
      final file = File('${dir.path}/old.sqlite');
      var db = CollaborationDatabase(NativeDatabase(file));
      await db.execute(
        "INSERT INTO local_meta(name,value) VALUES('existing','preserved')",
      );
      for (final table in [
        'device_ideas',
        'idea_space_links',
        'idea_assets',
        'idea_drafts',
      ]) {
        await db.execute('DROP TABLE $table');
      }
      await db.execute('PRAGMA user_version=8');
      await db.close();
      db = CollaborationDatabase(NativeDatabase(file));
      expect(
        (await db.rows(
          "SELECT value FROM local_meta WHERE name='existing'",
        )).single['value'],
        'preserved',
      );
      expect(await db.rows('SELECT * FROM idea_assets'), isEmpty);
      await db.close();
      await dir.delete(recursive: true);
    },
  );
  test(
    'local project deletion atomically removes idea draft and unreferenced image bytes',
    () async {
      final db = CollaborationDatabase(NativeDatabase.memory());
      final local = SqliteOrganizerStorage(db),
          ideas = IdeaRepository(IdeaStorage(db));
      await local.initialize();
      final organizer = OrganizerRepository(local);
      await organizer.initialize();
      await ideas.initialize();
      await organizer.createProject(title: 'Plan');
      final project = organizer.snapshot.projects.single.id;
      final asset = await ideas.importImage(
        Uint8List.fromList(img.encodePng(img.Image(width: 3, height: 2))),
      );
      final original = board().copyWith(
        projectId: project,
        elements: [
          IdeaElement(
            id: e1,
            kind: IdeaElementKind.image,
            x: 0,
            y: 0,
            width: 30,
            height: 20,
            asset: asset,
          ),
        ],
      );
      await ideas.saveBoard(original, isNew: true);
      await ideas.saveDraft(original, base: original);
      await organizer.reload();
      await organizer.deleteProject(project);
      await ideas.reload();
      expect(ideas.snapshot.boards, isEmpty);
      expect(await ideas.readDraft(id), isNull);
      expect(await ideas.readAsset(asset), isNull);
      expect((await db.rows('SELECT value FROM local_meta WHERE name=?', ['idea_deleted_revision:$id'])).single['value'], isNotNull);
      await organizer.close();
      await ideas.close();
      await db.close();
    },
  );
  test(
    'private project deletion queues idea tombstone before parent and keeps old operation immutable',
    () async {
      final transport = PersonalTransport(FakeServer());
      final db = CollaborationDatabase(NativeDatabase.memory());
      final storage = SqliteOrganizerStorage(db);
      await storage.initialize();
      final organizer = OrganizerRepository(storage);
      await organizer.initialize();
      final shared = CollaborationRepository(
        db,
        transport,
        MemorySessionStore(),
        ownsDatabase: false,
      );
      await shared.initialize();
      await shared.login(
        serverUrl: 'https://test.invalid',
        username: 'alice',
        password: 'test',
      );
      await shared.enablePrivateSync(
        expectedRevision: (await shared.previewPrivateSync()).revision,
      );
      await organizer.reload();
      transport.offline = true;
      await organizer.createProject(title: 'Private plan');
      final project = organizer.snapshot.projects.single.id;
      final binding = (await storage.activeBinding())!;
      await queuePrivateRecord(
        db,
        binding,
        id,
        'idea',
        board().copyWith(projectId: project).toJson(),
      );
      final prior = await db.rows(
        "SELECT request FROM outbox WHERE json_extract(request,'\$.type')='idea'",
      );
      final immutable = prior.single['request'];
      await organizer.deleteProject(project);
      final queued = await db.rows(
        'SELECT request,wire_version FROM outbox ORDER BY sequence',
      );
      expect(queued.where((r) => r['request'] == immutable).length, 1);
      final idea = queued
          .map((r) => jsonDecode(r['request'] as String) as Map)
          .where((r) => r['type'] == 'idea')
          .last;
      expect(idea['deleted'], true);
      expect(idea['payload'], isNull);
      expect(
        (jsonDecode(queued.last['request'] as String) as Map)['deleted'],
        true,
      );
      expect(queued.where((r) => r['wire_version'] == 5).length, 2);
      await organizer.close();
      await shared.close();
      await db.close();
    },
  );
  test(
    'two SQLite repositories merge separate element edits and retain conflicting durable draft',
    () async {
      final db = CollaborationDatabase(NativeDatabase.memory());
      final a = IdeaRepository(IdeaStorage(db)),
          b = IdeaRepository(IdeaStorage(db));
      await a.initialize();
      await a.saveBoard(board(), isNew: true);
      await b.initialize();
      final base = b.snapshot.boards.single;
      await a.updateBoard(
        base.copyWith(
          elements: [
            note(e1, text: 'Left'),
            note(e2),
          ],
        ),
        base: base,
      );
      await b.updateBoard(
        base.copyWith(
          elements: [
            note(e1),
            note(e2, text: 'Right'),
          ],
        ),
        base: base,
      );
      await a.reload();
      expect(a.snapshot.boards.single.elements.map((e) => e.text), [
        'Left',
        'Right',
      ]);
      final later = a.snapshot.boards.single;
      await a.updateBoard(
        later.copyWith(
          elements: [
            note(e1, text: 'First'),
            note(e2, text: 'Right'),
          ],
        ),
        base: later,
      );
      final conflict = later.copyWith(
        elements: [
          note(e1, text: 'Second'),
          note(e2, text: 'Right'),
        ],
      );
      await b.saveDraft(conflict, base: later);
      await expectLater(
        b.updateBoard(conflict, base: later),
        throwsA(isA<IdeaMergeConflict>()),
      );
      expect((await b.readDraft(id))!.elements.first.text, 'Second');
      expect(
        (await IdeaStorage(db).read()).boards.single.elements.first.text,
        'First',
      );
      await a.close();
      await b.close();
      await db.close();
    },
  );
  test(
    'Unicode escaped wire budget rejects oversized previews below raw byte limit',
    () {
      final text = List.filled(10000, '🌊').join();
      List<IdeaElement> elements(int count) => List.generate(
        count,
        (i) => note(
          'aaaaaaaa-aaaa-4aaa-8aaa-${i.toString().padLeft(12, '0')}',
          text: text,
        ),
      );
      final allowed = board().copyWith(elements: elements(8));
      allowed.validate();
      final oversized = board().copyWith(elements: elements(10));
      expect(
        utf8.encode(jsonEncode(oversized.toJson())).length,
        lessThan(786432),
      );
      expect(ideaEscapedJsonBytes(oversized.toJson()), greaterThan(1048576));
      expect(oversized.validate, throwsA(isA<FormatException>()));
    },
  );
  test(
    'delete and restore retain a revision barrier against a captured old merge base',
    () async {
      final db = CollaborationDatabase(NativeDatabase.memory());
      final storage = IdeaStorage(db), repo = IdeaRepository(IdeaStorage(db));
      await repo.initialize();
      await repo.saveBoard(board(), isNew: true);
      final stale = repo.snapshot.boards.single;
      await repo.deleteBoard(stale);
      final empty = await storage.readAll();
      await storage.write(
        IdeaSnapshot(boards: [stale]),
        expectedRevision: empty.revision,
        allSpaces: true,
      );
      await repo.reload();
      await expectLater(
        repo.updateBoard(stale.copyWith(title: 'Old editor'), base: stale),
        throwsA(isA<OrganizerConflictException>()),
      );
      final fresh = repo.snapshot.boards.single;
      await repo.updateBoard(
        fresh.copyWith(title: 'Current editor'),
        base: fresh,
      );
      expect(repo.snapshot.boards.single.title, 'Current editor');
      await repo.close();
      await db.close();
    },
  );
  test(
    'publication binding closes an old local writer while retaining source photo reads and archive restores',
    () async {
      final db = CollaborationDatabase(NativeDatabase.memory());
      await db.execute('INSERT INTO local_spaces(id,data) VALUES(?,?)', [
        e2,
        jsonEncode({
          'id': e2,
          'kind': 'household',
          'name': 'Household',
          'address': '',
        }),
      ]);
      db.activateLocalWorkspace(e2);
      final storage = IdeaStorage(db), repo = IdeaRepository(IdeaStorage(db));
      await repo.initialize();
      final asset = await repo.importImage(
        Uint8List.fromList(img.encodePng(img.Image(width: 2, height: 3))),
      );
      await repo.saveBoard(board(), isNew: true);
      final before = (await repo.readAsset(asset))!;
      await db.execute('UPDATE local_spaces SET data=? WHERE id=?', [
        jsonEncode({
          'id': e2,
          'kind': 'household',
          'name': 'Household',
          'address': '',
          'binding': {'partition': 'synthetic-account', 'scopeId': id},
        }),
        e2,
      ]);
      expect(await repo.readAsset(asset), before);
      await expectLater(
        repo.updateBoard(
          repo.snapshot.boards.single.copyWith(title: 'Late writer'),
        ),
        throwsA(isA<OrganizerConflictException>()),
      );
      await expectLater(
        repo.saveDraft(board()),
        throwsA(isA<OrganizerConflictException>()),
      );
      await expectLater(
        repo.importImage(before),
        throwsA(isA<OrganizerConflictException>()),
      );
      final all = await storage.readAll();
      await storage.write(all, expectedRevision: all.revision, allSpaces: true);
      expect((await storage.readAll()).boards.single.title, 'Sketch');
      await repo.close();
      await db.close();
    },
  );
  test(
    'private import archives original bytes and drafts without resurrecting anonymous content after logout or confirmed account deletion',
    () async {
      final db = CollaborationDatabase(NativeDatabase.memory());
      final local = SqliteOrganizerStorage(db);
      await local.initialize();
      final ideas = IdeaRepository(IdeaStorage(db));
      await ideas.initialize();
      final asset = await ideas.importImage(
        Uint8List.fromList(img.encodePng(img.Image(width: 3, height: 4))),
      );
      final candidate = board().copyWith(
        elements: [
          IdeaElement(
            id: e1,
            kind: IdeaElementKind.image,
            x: 0,
            y: 0,
            width: 30,
            height: 40,
            asset: asset,
          ),
        ],
      );
      await ideas.saveBoard(candidate, isNew: true);
      await ideas.saveDraft(
        candidate.copyWith(title: 'Private draft'),
        base: candidate,
      );
      final transport = IdeaPrivateSeedTransport(DeletionServer()),
          sessions = MemorySessionStore();
      final shared = CollaborationRepository(
        db,
        transport,
        sessions,
        ownsDatabase: false,
        deletionStore: MemoryAccountDeletionStore(),
      );
      await shared.initialize();
      await shared.login(
        serverUrl: 'https://test.invalid',
        username: 'alice',
        password: 'test',
      );
      final partition = shared.state.session!.partition;
      await shared.enablePrivateSync(
        expectedRevision: (await shared.previewPrivateSync()).revision,
      );
      expect((await IdeaStorage(db).readAll()).boards, isEmpty);
      expect(await ideas.listDrafts(), isEmpty);
      final privateWorkspace =
          'shared:$partition:${shared.state.privateSync.scopeId}';
      expect(
        await db.rows('SELECT sha256 FROM idea_assets WHERE workspace=?', [
          privateWorkspace,
        ]),
        hasLength(1),
      );
      expect(
        await db.rows('SELECT id FROM idea_drafts WHERE workspace=?', [
          privateWorkspace,
        ]),
        hasLength(1),
      );
      expect(
        await db.rows('SELECT value FROM local_meta WHERE name=?', [
          'idea_import_archive:$partition',
        ]),
        hasLength(1),
      );
      final backup = PortableBackupRepository(
        db,
        local,
        MemoryBackupUiPreferencesStore(),
        collaboration: () => shared,
      );
      const password = 'private archive test password';
      final encrypted = await backup.exportEncryptedBackup(password);
      final doc = await PortableBackupCrypto().decrypt(encrypted, password);
      expect(
        (doc['ideaOperationHistory'] as List).any(
          (r) => r['name'] == 'idea_import_archive:$partition',
        ),
        true,
      );
      expect((doc['ideaAssets'] as List).single['workspace'], privateWorkspace);
      await shared.signOut();
      expect((await IdeaStorage(db).readAll()).boards, isEmpty);
      expect(await ideas.listDrafts(), isEmpty);
      await shared.login(
        serverUrl: 'https://test.invalid',
        username: 'alice',
        password: 'test',
      );
      final preview = await shared.previewAccountDeletion();
      await shared.confirmAccountDeletion(
        previewHash: preview['previewHash'] as String,
        password: 'step-up',
        review: preview,
      );
      expect((await IdeaStorage(db).readAll()).boards, isEmpty);
      expect(await db.rows('SELECT * FROM idea_assets'), isEmpty);
      expect(await db.rows('SELECT * FROM idea_drafts'), isEmpty);
      expect(
        await db.rows('SELECT value FROM local_meta WHERE name=?', [
          'idea_import_archive:$partition',
        ]),
        isEmpty,
      );
      await shared.close();
      await ideas.close();
      await db.close();
    },
  );
}
