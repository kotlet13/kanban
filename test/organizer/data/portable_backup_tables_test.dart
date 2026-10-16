import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/data/portable_backup_crypto.dart';
import 'package:kanban/organizer/data/portable_backup_document.dart';
import 'package:kanban/organizer/data/portable_backup_repository.dart';
import 'package:kanban/organizer/data/sqlite_organizer_storage.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:kanban/organizer/domain/spreadsheet_models.dart';

import 'collaboration_repository_test.dart' show FakeServer, MemorySessionStore;
import 'private_sync_test_support.dart';

const _password = 'a portable tables backup password';

class _Client {
  _Client(this.db, this.storage, this.shared, this.backup);
  final CollaborationDatabase db;
  final SqliteOrganizerStorage storage;
  final CollaborationRepository shared;
  final PortableBackupRepository backup;

  static Future<_Client> create(
    PersonalTransport transport, {
    String? user,
  }) async {
    final db = CollaborationDatabase(NativeDatabase.memory());
    final storage = SqliteOrganizerStorage(db);
    await storage.initialize();
    final shared = CollaborationRepository(
      db,
      transport,
      MemorySessionStore(),
      ownsDatabase: false,
    );
    await shared.initialize();
    final backup = PortableBackupRepository(
      db,
      storage,
      MemoryBackupUiPreferencesStore(),
      collaboration: () => shared,
    );
    final client = _Client(db, storage, shared, backup);
    addTearDown(() async {
      await shared.close();
      await db.close();
    });
    if (user != null) await client.login(user);
    return client;
  }

  Future<void> login(String user) => shared.login(
    serverUrl: 'https://test.invalid',
    username: user,
    password: 'test',
  );
  String key(String scope, String id) =>
      'table_draft:${shared.state.session!.partition}:$scope:$id';
  Future<void> draft(String scope, SpreadsheetDraft draft) => db.execute(
    'INSERT INTO local_meta(name,value) VALUES(?,?) ON CONFLICT(name) DO UPDATE SET value=excluded.value',
    [key(scope, draft.tableId), jsonEncode(draft.toJson())],
  );
  Future<Uint8List> export() => backup.exportEncryptedBackup(_password);
  Future<Map<String, dynamic>> decode(Uint8List bytes) =>
      PortableBackupCrypto().decrypt(bytes, _password);
  Future<void> restore(Uint8List bytes) async {
    await backup.restoreEncryptedBackup(
      bytes,
      _password,
      mode: BackupRestoreMode.merge,
      expectedPersonalRevision: (await storage.read()).revision,
    );
  }

  Future<List<Map<String, dynamic>>> get drafts => db.rows(
    "SELECT name,value FROM local_meta WHERE name LIKE 'table_draft:%' ORDER BY name",
  );
}

SpreadsheetDraft _draft(
  String id, {
  String title = 'Proračun',
  Map<String, String>? cells,
}) => SpreadsheetDraft(
  tableId: id,
  baseRevision: 7,
  title: title,
  cells: cells ?? {'A1': '12', 'A2': '=SUM(A1:A1)'},
  updatedAt: 1780000000,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final unsupported = isA<CollaborationException>().having(
    (e) => e.code,
    'code',
    'backup_unsupported',
  );

  test(
    'encrypted v7 exports only source account and currently readable scopes, omitting downloaded bytes/leases',
    () async {
      final transport = PersonalTransport(FakeServer());
      final a = await _Client.create(transport, user: 'alice');
      final scope = await a.shared.createScope('Allowed');
      final denied = await a.shared.createScope('Revoked');
      final draft = _draft(newSharedId());
      await a.draft(scope, draft);
      await a.draft(
        denied,
        _draft(newSharedId(), title: 'Excluded revoked text'),
      );
      await a.db.execute('INSERT INTO local_meta(name,value) VALUES(?,?)', [
        'table_draft:other-account:$scope:${newSharedId()}',
        jsonEncode(draft.toJson()),
      ]);
      await a.db.execute('INSERT INTO local_meta(name,value) VALUES(?,?)', [
        'document_cache:${a.shared.state.session!.partition}:$scope:attachment:one',
        'cached-file-secret',
      ]);
      transport.server.confirmRevocation(denied, 'alice');
      await a.shared.syncNow();
      final bytes = await a.export(), doc = await a.decode(bytes);
      validateBackupDocument(doc);
      expect(doc['version'], 7);
      expect(doc['databaseVersion'], 10);
      expect(backupTableDrafts(doc).single['draft'], draft.toJson());
      expect(backupTableDrafts(doc).single['scopeId'], scope);
      expect(jsonEncode(doc), isNot(contains('cached-file-secret')));
      expect(jsonEncode(doc), isNot(contains('Excluded revoked text')));
      expect(jsonEncode(doc), isNot(contains('leaseToken')));
      expect(utf8.decode(bytes), isNot(contains('Proračun')));
      final preview = await a.backup.inspectEncryptedBackup(bytes, _password);
      expect(preview.pendingCount, 1);
      expect(preview.contentSummary!.downloadedCounts['tableDrafts'], 1);
    },
  );

  test(
    'restore quarantines drafts across repository reopen; explicit same-account resume only restores local draft',
    () async {
      final transport = PersonalTransport(FakeServer());
      final a = await _Client.create(transport, user: 'alice');
      final scope = await a.shared.createScope('Shared');
      final original = _draft(newSharedId());
      await a.draft(scope, original);
      final bytes = await a.export(),
          id = (await a.decode(bytes))['id'] as String;
      final b = await _Client.create(transport);
      await b.restore(bytes);
      expect(await b.drafts, isEmpty);
      final stored =
          (await b.db.rows('SELECT data FROM restored_backups')).single['data']
              as String;
      expect(stored, isNot(contains('Proračun')));
      final reopened = PortableBackupRepository(
        b.db,
        b.storage,
        MemoryBackupUiPreferencesStore(),
        collaboration: () => b.shared,
      );
      var review = await reopened.reviewRestoredWork(id, _password);
      expect(review.canResume, false);
      expect(review.items.single.recordType, 'tableDraft');
      expect(review.items.single.title, original.title);
      await expectLater(
        reopened.resumeRestoredWork(id, password: _password),
        throwsA(isA<CollaborationException>()),
      );
      await b.login('bob');
      await expectLater(
        reopened.resumeRestoredWork(id, password: _password),
        throwsA(
          isA<CollaborationException>().having(
            (e) => e.code,
            'code',
            'backup_wrong_account',
          ),
        ),
      );
      expect(await b.drafts, isEmpty);
      await b.shared.signOut();
      await b.login('alice');
      review = await reopened.reviewRestoredWork(id, _password);
      expect(review.canResume, true);
      await reopened.resumeRestoredWork(id, password: _password);
      final recovered = await b.drafts;
      expect(recovered.single['name'], b.key(scope, original.tableId));
      expect(
        jsonDecode(recovered.single['value'] as String),
        original.toJson(),
      );
      expect(await b.db.rows('SELECT * FROM records'), isEmpty);
      expect(
        transport.server.calls.any(
          (call) => call.operation.startsWith('tables.'),
        ),
        false,
      );
      await reopened.resumeRestoredWork(id, password: _password);
      expect((await b.drafts).length, 1);
    },
  );

  test(
    'new local draft conflict rolls back every restored draft and preserves current work',
    () async {
      final transport = PersonalTransport(FakeServer());
      final a = await _Client.create(transport, user: 'alice');
      final scope = await a.shared.createScope('Shared');
      final first = _draft('11111111-1111-4111-8111-111111111111');
      final second = _draft('22222222-2222-4222-8222-222222222222');
      await a.draft(scope, first);
      await a.draft(scope, second);
      final bytes = await a.export(),
          id = (await a.decode(bytes))['id'] as String;
      final b = await _Client.create(transport, user: 'alice');
      final local = _draft(second.tableId, cells: {'A1': 'Newer own work'});
      await b.draft(scope, local);
      await b.restore(bytes);
      await expectLater(
        b.backup.resumeRestoredWork(id, password: _password),
        throwsA(
          isA<CollaborationException>().having(
            (e) => e.code,
            'code',
            'backup_conflict',
          ),
        ),
      );
      final rows = await b.drafts;
      expect(rows.length, 1);
      expect(jsonDecode(rows.single['value'] as String), local.toJson());
    },
  );

  test(
    'fresh viewer/archive/revocation rights forbid resuming drafts with no local activation',
    () async {
      final transport = PersonalTransport(FakeServer());
      final a = await _Client.create(transport, user: 'alice');
      final scope = await a.shared.createScope('Shared');
      await a.draft(scope, _draft(newSharedId()));
      final bytes = await a.export(),
          id = (await a.decode(bytes))['id'] as String;
      final b = await _Client.create(transport, user: 'alice');
      await b.restore(bytes);
      transport.server.members[scope]!['alice'] = 'viewer';
      await expectLater(
        b.backup.resumeRestoredWork(id, password: _password),
        throwsA(
          isA<CollaborationException>().having(
            (e) => e.code,
            'code',
            'permission_revoked',
          ),
        ),
      );
      expect(await b.drafts, isEmpty);
      transport.server.members[scope]!['alice'] = 'owner';
      transport.server.scopes[scope]!['archived'] = true;
      await expectLater(
        b.backup.resumeRestoredWork(id, password: _password),
        throwsA(isA<CollaborationException>()),
      );
      expect(await b.drafts, isEmpty);
      transport.server.scopes[scope]!['archived'] = false;
      transport.server.confirmRevocation(scope, 'alice');
      await expectLater(
        b.backup.resumeRestoredWork(id, password: _password),
        throwsA(isA<CollaborationException>()),
      );
      expect(await b.drafts, isEmpty);
      expect((await b.db.rows('SELECT * FROM restored_backups')).length, 1);
    },
  );

  test(
    'strict v7 draft validation rejects foreign identities, secret fields, unsafe cells and duplicates before restore',
    () async {
      final transport = PersonalTransport(FakeServer());
      final a = await _Client.create(transport, user: 'alice');
      final scope = await a.shared.createScope('Shared');
      await a.draft(scope, _draft(newSharedId()));
      final doc = await a.decode(await a.export());
      for (final change in <void Function(Map<String, dynamic>)>[
        (r) => r['partition'] = 'other',
        (r) => r['scopeId'] = newSharedId(),
        (r) => r['tableId'] = newSharedId(),
        (r) => backupMap(r['draft'])['token'] = 'secret',
        (r) => backupMap(r['draft'])['baseRevision'] = -1,
        (r) => backupMap(r['draft'])['updatedAt'] = -1,
        (r) => backupMap(r['draft'])['cells'] = {'A0': 'bad'},
        (r) => backupMap(r['draft'])['cells'] = {'a1': 'bad'},
        (r) => backupMap(r['draft'])['cells'] = {'ZZZ100001': 'bad'},
        (r) => backupMap(r['draft'])['cells'] = {'A1': 123},
        (r) => backupMap(r['draft'])['cells'] = {
          'A1': List.filled(4097, 'x').join(),
        },
      ]) {
        final invalid = backupMap(jsonDecode(jsonEncode(doc)));
        change(backupTableDrafts(invalid).single);
        expect(() => validateBackupDocument(invalid), throwsA(unsupported));
      }
      final invalid = backupMap(jsonDecode(jsonEncode(doc)));
      (invalid['tableDrafts'] as List).add(backupTableDrafts(invalid).single);
      expect(() => validateBackupDocument(invalid), throwsA(unsupported));
      final bytes = await PortableBackupCrypto().encrypt(invalid, _password);
      final b = await _Client.create(transport);
      await expectLater(b.restore(bytes), throwsA(unsupported));
      expect(await b.drafts, isEmpty);
      expect(await b.db.rows('SELECT * FROM restored_backups'), isEmpty);
    },
  );

  test(
    'versions 1 through 6 remain readable without drafts; v6 reminder preferences survive v7 restore',
    () async {
      final transport = PersonalTransport(FakeServer());
      final a = await _Client.create(transport);
      final current = await a.decode(await a.export());
      for (var version = 1; version <= 6; version++) {
        final legacy = backupMap(jsonDecode(jsonEncode(current)));
        legacy['version'] = version;
        legacy['databaseVersion'] = [0, 4, 5, 6, 7, 9, 10][version];
        legacy.remove('tableDrafts');
        if (version < 6) legacy.remove('localTaskReminderPreferences');
        if (version < 5) {
          for (final field in [
            'ideas',
            'ideaSpaceLinks',
            'ideaAssets',
            'ideaDrafts',
            'ideaOperationHistory',
          ]) {
            legacy.remove(field);
          }
        }
        if (version < 4) {
          for (final field in [
            'localSpaces',
            'gardenSpaceLinks',
            'linkedPayments',
          ]) {
            legacy.remove(field);
          }
        }
        if (version < 3) {
          legacy.remove('operationPairs');
          legacy.remove('financeInboxReads');
        }
        if (version < 2) legacy.remove('gardens');
        validateBackupDocument(legacy);
        expect(backupTableDrafts(legacy), isEmpty);
      }
      const name = 'local_task_deadline_reminder:personal:task:old-task:due';
      const value =
          '{"createdAt":"2026-10-15T10:00:00.000Z","offsetMinutes":60,"enabled":true,"lastRemindAt":"2026-10-16T10:00:00.000Z"}';
      current['localTaskReminderPreferences'] = [
        {'name': name, 'value': value},
      ];
      final b = await _Client.create(transport);
      await b.restore(await PortableBackupCrypto().encrypt(current, _password));
      expect(
        (await b.db.rows('SELECT value FROM local_meta WHERE name=?', [
          name,
        ])).single['value'],
        value,
      );
    },
  );
}
