import 'dart:convert';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/data/organizer_repository.dart';
import 'package:kanban/organizer/data/organizer_storage.dart';
import 'package:kanban/organizer/data/portable_backup_crypto.dart';
import 'package:kanban/organizer/data/portable_backup_document.dart';
import 'package:kanban/organizer/data/sqlite_organizer_storage.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';

import 'collaboration_repository_test.dart' show FakeServer, MemorySessionStore;
import 'private_sync_test_support.dart';

const account = '11111111-1111-4111-8111-111111111111';
const serverId = '22222222-2222-4222-8222-222222222222';
const scopeId = '33333333-3333-4333-8333-333333333333';
const recordId = '44444444-4444-4444-8444-444444444444';
const opId = '55555555-5555-4555-8555-555555555555';
const timestamp = '2026-10-05T10:00:00.000Z';
const partition = 'https%3A%2F%2Ftest.invalid%2F:$serverId:$account';

Map<String, dynamic> document() => {
  'format': 'vsakdan-portable-data',
  'version': 1,
  'databaseVersion': 4,
  'id': opId,
  'createdAt': timestamp,
  'source': {
    'partition': partition,
    'serverId': serverId,
    'accountId': account,
    'serverUrl': 'https://test.invalid/',
    'username': 'alice',
    'displayName': 'Alice',
  },
  'personal': OrganizerBackupCodec.encode(OrganizerSnapshot()),
  'privateData': {'binding': null, 'maps': [], 'reminders': []},
  'tables': {
    for (final table in backupTables.keys) table: <Map<String, dynamic>>[],
  },
  'uiPreferences': <String, dynamic>{},
  'completeness': <String>[],
  'exclusions': <String>[],
};

void addScope(Map<String, dynamic> doc, {bool personal = false}) {
  backupRows(doc, 'scopes').add({
    'partition': partition,
    'id': scopeId,
    'data': jsonEncode(
      SharedScope(
        id: scopeId,
        name: 'Synthetic',
        kind: personal ? SharedScopeKind.personal : SharedScopeKind.household,
        role: SharedRole.owner,
      ).toJson(),
    ),
    'cursor': 1,
    'blocked': 0,
    'finance_cursor': 0,
    'finance_access_revision': 1,
    'finance_policy': jsonEncode(const SharedFinancePolicy().toJson()),
    'finance_blocked': 0,
    'finance_complete': 0,
  });
}

Map<String, dynamic> projectPayload() => {
  'title': 'Synthetic project',
  'description': '',
  'area': 'personal',
  'createdAt': timestamp,
  'updatedAt': timestamp,
  'startAt': null,
  'endAt': null,
};

void addRecord(Map<String, dynamic> doc, String type, Object? payload) {
  backupRows(doc, 'records').add({
    'partition': partition,
    'scope_id': scopeId,
    'id': recordId,
    'type': type,
    'local_revision': 1,
    'server_revision': 0,
    'payload': payload == null ? null : jsonEncode(payload),
    'deleted': payload == null ? 1 : 0,
    'remote': null,
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final unsupported = isA<CollaborationException>().having(
    (e) => e.code,
    'code',
    'backup_unsupported',
  );

  test('strict empty and valid typed snapshot accepted', () {
    final doc = document();
    validateBackupDocument(doc);
    addScope(doc);
    addRecord(doc, 'project', projectPayload());
    validateBackupDocument(doc);
  });

  test(
    'unknown schema, table, row fields and mismatched partition rejected',
    () {
      for (final mutate in <void Function(Map<String, dynamic>)>[
        (d) => d['databaseVersion'] = 999,
        (d) => backupMap(d['tables'])['devices'] = <Map<String, dynamic>>[],
        (d) => backupRows(d, 'scopes').single['token'] = 'not-a-real-secret',
        (d) => backupRows(d, 'scopes').single['partition'] = 'another-account',
      ]) {
        final doc = document();
        addScope(doc);
        mutate(doc);
        expect(() => validateBackupDocument(doc), throwsA(unsupported));
      }
    },
  );

  test('tombstones cannot smuggle unknown record types', () {
    final doc = document();
    addScope(doc);
    addRecord(doc, 'deviceToken', null);
    expect(() => validateBackupDocument(doc), throwsA(unsupported));
  });

  test('live shopping item cannot reference absent parent list', () {
    final doc = document();
    addScope(doc);
    addRecord(doc, 'shoppingItem', {
      'title': 'Synthetic item',
      'quantity': '1',
      'notes': '',
      'isPurchased': false,
      'listId': opId,
      'createdAt': timestamp,
      'updatedAt': timestamp,
    });
    expect(() => validateBackupDocument(doc), throwsA(unsupported));
  });

  test('immutable outbox type must match candidate record type', () {
    final doc = document();
    addScope(doc);
    addRecord(doc, 'project', projectPayload());
    backupRows(doc, 'outbox').add({
      'sequence': 1,
      'op_id': opId,
      'partition': partition,
      'scope_id': scopeId,
      'record_id': recordId,
      'state': 'pending',
      'wire_version': 2,
      'request': jsonEncode({
        'opId': opId,
        'recordId': recordId,
        'type': 'shoppingList',
        'expectedRevision': 0,
        'deleted': false,
        'payload': {
          'title': 'Other type',
          'createdAt': timestamp,
          'updatedAt': timestamp,
        },
      }),
    });
    expect(() => validateBackupDocument(doc), throwsA(unsupported));
  });

  test('private map must use supported type and original workspace', () {
    for (final type in ['deviceToken', 'project']) {
      final doc = document();
      addScope(doc, personal: true);
      addRecord(doc, 'project', projectPayload());
      doc['privateData'] = {
        'binding': {
          'id': 'private:$partition',
          'partition': partition,
          'scope_id': scopeId,
          'paused': 0,
        },
        'maps': [
          {
            'workspace': 'another-workspace',
            'id': 'original-id',
            'remote_id': recordId,
            'type': type,
          },
        ],
        'reminders': [],
      };
      expect(() => validateBackupDocument(doc), throwsA(unsupported));
    }
  });

  test('recovery command allowlist blocks auth, grants and credentials', () {
    for (final operation in ['auth.login', 'finance.grant', 'push.register']) {
      expect(
        () => validateBackupCommand(
          operation,
          {'requestId': opId, 'token': 'synthetic-token'},
          {scopeId},
        ),
        throwsA(isA<FormatException>()),
      );
    }
    expect(
      () => validateBackupCommand(
        'inbox.read',
        {
          'id': 1,
          'read': true,
          'expectedRevision': 1,
          'requestId': opId,
          'token': 'synthetic-token',
        },
        {scopeId},
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test(
    'bounded KDF envelope rejects malicious work factor before derivation',
    () async {
      final crypto = PortableBackupCrypto();
      final envelope = {
        'format': 'vsakdan-encrypted-backup',
        'version': 1,
        'kdf': 'pbkdf2-sha256',
        'iterations': 2147483647,
        'salt': base64Encode(List.filled(16, 0)),
        'cipher': 'aes-256-gcm',
        'nonce': base64Encode(List.filled(12, 0)),
        'ciphertext': '',
        'mac': base64Encode(List.filled(16, 0)),
      };
      await expectLater(
        crypto.decrypt(
          utf8.encode(jsonEncode(envelope)),
          'long synthetic password',
        ),
        throwsA(unsupported),
      );
    },
  );

  test(
    'real KDF and AEAD roundtrip preserves Unicode and unknown business text',
    () async {
      final crypto = PortableBackupCrypto();
      final source = {
        'text': 'Čebela 🐝',
        'nested': {'amountMinor': 17},
      };
      final encrypted = await crypto.encrypt(source, 'long synthetic password');
      expect(utf8.decode(encrypted), isNot(contains('Čebela')));
      expect(
        await crypto.decrypt(encrypted, 'long synthetic password'),
        source,
      );
    },
  );

  test(
    'restored conflict resolves against newest authorized canonical, not backup remote',
    () async {
      final server = FakeServer();
      final transport = PersonalTransport(server);
      Future<CollaborationRepository> open() async {
        final repo = CollaborationRepository(
          CollaborationDatabase(NativeDatabase.memory()),
          transport,
          MemorySessionStore(),
        );
        await repo.initialize();
        addTearDown(repo.close);
        await repo.login(
          serverUrl: 'https://test.invalid',
          username: 'alice',
          password: 'synthetic',
        );
        return repo;
      }

      final a = await open();
      final scope = await a.createScope('Recovery');
      final id = await a.createTask(scopeId: scope, title: 'Original');
      await a.syncNow();
      transport.offline = true;
      await a.updateTask(
        scope,
        a.state
            .dataForScope(scope)
            .tasks
            .single
            .copyWith(title: 'Local pending'),
      );
      void remoteEdit(String title) {
        final old = server.records[scope]![id]!;
        server.records[scope]![id] = {
          ...old,
          'revision': (old['revision'] as int) + 1,
          'sequence': server.sequence[scope] = server.sequence[scope]! + 1,
          'payload': {...old['payload'] as Map, 'title': title},
        };
      }

      remoteEdit('Server at backup');
      transport.offline = false;
      await a.syncNow();
      expect(a.state.conflicts.length, 1);
      final doc = document(), profile = a.state.session!;
      doc['source'] = {
        'partition': profile.partition,
        'serverId': profile.serverId,
        'accountId': profile.accountId,
        'serverUrl': profile.serverUrl,
        'username': profile.username,
        'displayName': profile.displayName,
      };
      doc['tables'] = {
        for (final table in backupTables.keys)
          table: [
            for (final row in await a.database.rows(
              'SELECT * FROM $table WHERE partition=?',
              [profile.partition],
            ))
              {for (final col in backupTables[table]!) col: row[col]},
          ],
      };
      validateBackupDocument(doc);
      remoteEdit('Newest authorized server');
      final b = await open();
      await b.resumePortableBackup(doc);
      final conflict = b.state.conflicts.single;
      await b.resolveConflict(conflictId: conflict.id, keepLocal: false);
      expect(
        b.state.dataForScope(scope).tasks.single.title,
        'Newest authorized server',
      );
      expect(await b.database.rows('SELECT * FROM outbox'), isEmpty);
    },
  );

  test(
    'private recovery leaves unrelated anonymous work and immutable ACK replay intact',
    () async {
      final transport = PersonalTransport(FakeServer());
      Future<
        ({
          CollaborationDatabase db,
          SqliteOrganizerStorage storage,
          OrganizerRepository local,
          CollaborationRepository shared,
        })
      >
      client() async {
        final db = CollaborationDatabase(NativeDatabase.memory());
        final storage = SqliteOrganizerStorage(db);
        await storage.initialize();
        final local = OrganizerRepository(storage);
        await local.initialize();
        final shared = CollaborationRepository(
          db,
          transport,
          MemorySessionStore(),
          ownsDatabase: false,
        );
        await shared.initialize();
        addTearDown(() async {
          await local.close();
          await shared.close();
          await db.close();
        });
        return (db: db, storage: storage, local: local, shared: shared);
      }

      final a = await client();
      await a.local.createTask(title: 'Recovery original task');
      await a.shared.login(
        serverUrl: 'https://test.invalid',
        username: 'alice',
        password: 'synthetic',
      );
      await a.local.reload();
      await a.shared.enablePrivateSync(
        expectedRevision: (await a.shared.previewPrivateSync()).revision,
      );
      await a.local.reload();
      transport.offline = true;
      await a.local.updateTask(
        a.local.snapshot.tasks.single.copyWith(title: 'Lost response edit'),
      );
      final source = await a.db.rows('SELECT * FROM outbox');
      final maps = await a.db.rows('SELECT * FROM personal_record_map');
      final binding = (await a.storage.activeBinding())!;
      final doc = document();
      final profile = a.shared.state.session!;
      doc['source'] = {
        'partition': profile.partition,
        'serverId': profile.serverId,
        'accountId': profile.accountId,
        'serverUrl': profile.serverUrl,
        'username': profile.username,
        'displayName': profile.displayName,
      };
      doc['tables'] = {
        for (final table in backupTables.keys)
          table: [
            for (final row in await a.db.rows(
              'SELECT * FROM $table WHERE partition=?',
              [profile.partition],
            ))
              {for (final col in backupTables[table]!) col: row[col]},
          ],
      };
      doc['privateData'] = {
        'binding': {
          'id': binding['id'],
          'partition': binding['partition'],
          'scope_id': binding['scope_id'],
          'paused': binding['paused'],
        },
        'maps': maps,
        'reminders': [],
      };
      validateBackupDocument(doc);
      transport.offline = false;
      await a.shared
          .syncNow(); // Server accepted original op before restore/replay.
      final b = await client();
      await b.local.createProject(title: 'Must remain anonymous');
      await b.shared.login(
        serverUrl: 'https://test.invalid',
        username: 'alice',
        password: 'synthetic',
      );
      await b.local.reload();
      await b.shared.resumePortableBackup(doc);
      expect(
        (await b.storage.localSnapshot()).projects.single.title,
        'Must remain anonymous',
      );
      expect(transport.server.records.values.single.length, 1);
      expect(
        jsonDecode(
          transport.server.replay[source.single['op_id']]!.request,
        )['operation'],
        jsonDecode(source.single['request'] as String),
      );
      expect(await b.db.rows('SELECT * FROM outbox'), isEmpty);
      expect(
        (await b.db.rows(
          'SELECT remote_id FROM personal_record_map',
        )).single['remote_id'],
        maps.single['remote_id'],
      );
    },
  );
}
