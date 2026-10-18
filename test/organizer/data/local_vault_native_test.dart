import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/local_vault.dart';
import 'package:kanban/organizer/data/local_vault_cipher.dart';
import 'package:kanban/organizer/data/local_vault_keys.dart';
import 'package:kanban/organizer/data/local_vault_files.dart';
import 'package:kanban/organizer/data/local_vault_native.dart';
import 'package:kanban/organizer/data/local_vault_snapshot.dart';
import 'package:kanban/organizer/data/organizer_repository.dart';
import 'package:kanban/organizer/data/organizer_storage.dart';
import 'package:kanban/organizer/data/sqlite_organizer_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'package:sqlite3/sqlite3.dart';

class MemoryVaultKeys implements LocalVaultKeyStore {
  String? value;
  bool unavailable = false, loseWrite = false;
  @override
  Future<String?> read() async {
    if (unavailable) throw const LocalVaultException('vault_secure_storage');
    return value;
  }

  @override
  Future<void> write(String text) async {
    if (unavailable || loseWrite) {
      throw const LocalVaultException('vault_secure_storage');
    }
    value = text;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late Directory directory;
  late SharedPreferences preferences;
  late MemoryVaultKeys keys;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('jivie-vault-test-');
    SharedPreferences.setMockInitialValues({
      'app_locale_code': 'sl',
      'organizer_notification_ids_v1': 'private notification title sentinel',
      'organizer_remote_push_device_opt_in_v1': jsonEncode({
        'signed-out-account:device': false,
      }),
    });
    preferences = await SharedPreferences.getInstance();
    keys = MemoryVaultKeys();
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });
  NativeLocalVaultService service({void Function(String)? checkpoint}) =>
      NativeLocalVaultService(
        directory,
        keys,
        preferences: preferences,
        checkpoint: checkpoint,
      );

  Future<String> createSource() async {
    final file = File('${directory.path}/organizer_shared_v1.sqlite');
    final drift = CollaborationDatabase(NativeDatabase(file));
    await drift.rows('SELECT * FROM local_meta');
    await drift.close();
    final db = sqlite3.open(file.path);
    for (final partition in ['signed-out-a', 'signed-out-b']) {
      db.execute('INSERT INTO accounts VALUES(?,?)', [
        partition,
        '{"unknownProfile":"retained"}',
      ]);
      db.execute('INSERT INTO scopes(partition,id,data) VALUES(?,?,?)', [
        partition,
        'scope-$partition',
        '{"unknownScope":"retained"}',
      ]);
      db.execute(
        'INSERT INTO records(partition,scope_id,id,type,local_revision,server_revision,payload,deleted,remote) VALUES(?,?,?,?,?,?,?,?,?)',
        [
          partition,
          'scope-$partition',
          'record-$partition',
          'task',
          7,
          4,
          '{"unknownPayload":{"keep":[1,2,3]}}',
          0,
          '{"canonical":"retained"}',
        ],
      );
      db.execute(
        'INSERT INTO outbox(op_id,partition,scope_id,record_id,request,state,wire_version) VALUES(?,?,?,?,?,?,?)',
        [
          'operation-$partition',
          partition,
          'scope-$partition',
          'record-$partition',
          '{"unchangedBody":"immutable sentinel"}',
          'blocked',
          6,
        ],
      );
      db.execute('INSERT INTO finance_records VALUES(?,?,?,?,?,?,?,?,?)', [
        partition,
        'scope-$partition',
        'finance-$partition',
        'financeEntry',
        3,
        2,
        '{"amountMinor":123,"futureField":true}',
        0,
        '{"originalRemote":true}',
      ]);
      db.execute(
        'INSERT INTO finance_outbox(op_id,partition,scope_id,record_id,request,state,wire_version) VALUES(?,?,?,?,?,?,?)',
        [
          'finance-op-$partition',
          partition,
          'scope-$partition',
          'finance-$partition',
          '{"immutableFinanceBody":true}',
          'conflict',
          3,
        ],
      );
      db.execute(
        'INSERT INTO commands(id,partition,operation,params,entity_key,state) VALUES(?,?,?,?,?,?)',
        [
          'command-$partition',
          partition,
          'future.operation',
          '{"unknown":true}',
          'entity',
          'blocked',
        ],
      );
      db.execute('INSERT INTO conflicts VALUES(?,?,?,?,?,?,?)', [
        'conflict-$partition',
        partition,
        'scope-$partition',
        'record-$partition',
        'task',
        'future_reason',
        '{"history":true}',
      ]);
      db.execute('INSERT INTO finance_conflicts VALUES(?,?,?,?,?,?,?)', [
        'finance-conflict-$partition',
        partition,
        'scope-$partition',
        'finance-$partition',
        'financeEntry',
        'future_reason',
        '{"history":true}',
      ]);
      db.execute('INSERT INTO idea_assets VALUES(?,?,?,?)', [
        partition,
        'unknown-sha',
        '{"futureMetadata":true}',
        Uint8List.fromList(List.generate(65537, (i) => i % 256)),
      ]);
      db.execute('INSERT INTO idea_drafts VALUES(?,?,?,?)', [
        partition,
        'draft-$partition',
        '{"unsubmittedDraft":true}',
        '{"base":7}',
      ]);
    }
    db.execute('INSERT INTO restored_backups VALUES(?,?,?,?)', [
      'archive',
      '2026-10-17',
      'signed-out-a',
      '{"encrypted":"original archive bytes sentinel"}',
    ]);
    db.execute('INSERT INTO linked_payment_intents VALUES(?,?,?)', [
      'payment-intent',
      '{"originalPrivateMapping":true}',
      'pending',
    ]);
    db.execute(
      'CREATE TABLE unknown(id INTEGER PRIMARY KEY AUTOINCREMENT,payload TEXT,bytes BLOB,n REAL)',
    );
    db.execute('CREATE INDEX unknown_payload ON unknown(payload)');
    db.execute('CREATE VIEW future_view AS SELECT * FROM unknown');
    db.execute(
      'CREATE TRIGGER future_trigger AFTER INSERT ON unknown BEGIN SELECT 1; END',
    );
    db.execute('INSERT INTO unknown(id,payload,bytes,n) VALUES(?,?,?,?)', [
      900,
      'unknown json {"keep":{"all":true}}',
      Uint8List.fromList([0, 1, 255]),
      1.25,
    ]);
    db.execute('DELETE FROM unknown');
    db.execute('INSERT INTO unknown(payload,bytes,n) VALUES(?,?,?)', [
      'all account partitions sentinel',
      Uint8List.fromList([0, 2, 254]),
      1.5,
    ]);
    db.execute('CREATE TABLE implicit(value)');
    db.execute(
      "INSERT INTO implicit(rowid,value) VALUES(1,'first'),(900,'last')",
    );
    db.execute('PRAGMA journal_mode = WAL');
    db.execute(
      "INSERT INTO local_meta VALUES('unknown_future_key','future field sentinel')",
    );
    final expected = await LocalVaultSnapshot.fingerprint(db);
    db.close();
    return expected;
  }

  Future<Uint8List> prepare(NativeLocalVaultService vault) async {
    final bytes = await vault.prepareRecoveryFile();
    expect((await vault.inspect()).phase, LocalVaultPhase.recoveryUnverified);
    expect(
      (await vault.verifyRecoveryFile(bytes)).phase,
      LocalVaultPhase.migrationPending,
    );
    return bytes;
  }

  test(
    'real schema10 all rows unknown schema rowids BLOB sequences survive encrypted disk reopen',
    () async {
      final expected = await createSource();
      final vault = service();
      final recovery = await prepare(vault);
      expect((await vault.migrate()).phase, LocalVaultPhase.ready);
      expect(await vault.sourceFile.exists(), false);
      final key = LocalVaultKey.decode(utf8.decode(recovery));
      final db = sqlite3.open(vault.databaseFile.path);
      LocalVaultCipher.configure(db, key.bytes);
      expect(await LocalVaultSnapshot.fingerprint(db), expected);
      expect(
        db
            .select('SELECT seq FROM sqlite_sequence WHERE name=\'unknown\'')
            .single['seq'],
        901,
      );
      db.close();
      expect(
        String.fromCharCodes(await vault.databaseFile.readAsBytes()),
        isNot(contains('sentinel')),
      );
      expect(
        String.fromCharCodes(await vault.archiveFile.readAsBytes()),
        isNot(contains('sentinel')),
      );
      expect(preferences.get('organizer_notification_ids_v1'), isNull);
      expect(preferences.getString('app_locale_code'), 'sl');
      expect(
        (await vault.openPreferences()).getString(
          'organizer_notification_ids_v1',
        ),
        'private notification title sentinel',
      );
      final active = await vault.openDatabase();
      expect((await active.rows('SELECT * FROM unknown')).length, 1);
      await active.close();
      expect((await service().inspect()).phase, LocalVaultPhase.ready);
    },
  );

  test(
    'lost key never creates empty DB; exact local file recovers same installation',
    () async {
      await createSource();
      final vault = service(), recovery = await prepare(service());
      await vault.migrate();
      final before = await vault.databaseFile.readAsBytes();
      keys.value = null;
      expect((await vault.inspect()).phase, LocalVaultPhase.recoveryRequired);
      await expectLater(
        vault.openDatabase(),
        throwsA(isA<LocalVaultException>()),
      );
      expect(await vault.databaseFile.readAsBytes(), before);
      final other = LocalVaultKey.generate();
      await expectLater(
        vault.recover(Uint8List.fromList(utf8.encode(other.encode()))),
        throwsA(isA<LocalVaultException>()),
      );
      expect(keys.value, isNull);
      expect((await vault.recover(recovery)).phase, LocalVaultPhase.ready);
      expect(await vault.databaseFile.readAsBytes(), before);
    },
  );

  for (final stage in [
    'keyStored',
    'keyPrepared',
    'recoveryVerified',
    'encryptedCandidate',
    'archiveVerified',
    'candidateVerified',
    'targetMoved',
    'switched',
    'preferencesProtected',
    'legacyDeleted',
    'complete',
  ]) {
    test(
      'interruption after $stage resumes original migration without loss',
      () async {
        final expected = await createSource();
        var failed = false;
        final interrupted = service(
          checkpoint: (value) {
            if (value == stage && !failed) {
              failed = true;
              throw StateError('simulated power loss');
            }
          },
        );
        Uint8List? recovery;
        try {
          recovery = await interrupted.prepareRecoveryFile();
          await interrupted.verifyRecoveryFile(recovery);
          await interrupted.migrate();
        } catch (_) {
          /* Same on-disk boundary as process interruption. */
        }
        expect(failed, true);
        final resumed = service();
        final bytes = recovery ?? await resumed.prepareRecoveryFile();
        if ((await resumed.inspect()).phase ==
            LocalVaultPhase.recoveryUnverified) {
          await resumed.verifyRecoveryFile(bytes);
        }
        await resumed.migrate();
        final key = LocalVaultKey.decode(keys.value!);
        final db = sqlite3.open(resumed.databaseFile.path);
        LocalVaultCipher.configure(db, key.bytes);
        expect(await LocalVaultSnapshot.fingerprint(db), expected);
        db.close();
        expect((await resumed.inspect()).phase, LocalVaultPhase.ready);
      },
    );
  }

  test(
    'new writes after switched survive cleanup retry without rollback to old source',
    () async {
      await createSource();
      final interrupted = service(
        checkpoint: (stage) {
          if (stage == 'switched') throw StateError('crash');
        },
      );
      await prepare(interrupted);
      await expectLater(
        interrupted.migrate(),
        throwsA(isA<LocalVaultException>()),
      );
      final resumed = service();
      final db = await resumed.openDatabase();
      await db.execute(
        "INSERT INTO local_meta VALUES('post_switch','preserved new write')",
      );
      await db.close();
      await resumed.migrate();
      final reopened = await resumed.openDatabase();
      expect(
        (await reopened.rows(
          "SELECT value FROM local_meta WHERE name='post_switch'",
        )).single['value'],
        'preserved new write',
      );
      await reopened.close();
    },
  );

  test(
    'Hive-only source preserved in authenticated archive and memory importer after cleanup',
    () async {
      final legacy = await HiveOrganizerStorage.open(directory: directory.path);
      final organizer = OrganizerRepository(legacy);
      await organizer.initialize();
      await organizer.createTask(title: 'Hive only exact retained task');
      await organizer.close();
      final source = await File(
        '${directory.path}/organizer_personal_v1.hive',
      ).readAsBytes();
      final vault = service();
      await prepare(vault);
      await vault.migrate();
      final archived = await vault.readLegacyHiveBytes();
      expect(archived, source);
      final memory = await Hive.openBox<String>(
        'hive_vault_import_test',
        bytes: archived!,
        crashRecovery: false,
      );
      final original = memory.get('committed_snapshot')!;
      await memory.close();
      final db = await vault.openDatabase();
      final storage = SqliteOrganizerStorage(
        db,
        legacyFactory: () async => _LegacyFrame(original),
      );
      await storage.initialize();
      expect(
        (await storage.read()).tasks.single.title,
        'Hive only exact retained task',
      );
      expect(
        (await db.rows(
          'SELECT migration_snapshot FROM personal_workspaces',
        )).single['migration_snapshot'],
        original,
      );
      await db.close();
    },
  );

  test(
    'newer or malformed Hive blocks cleanup and preserves sole original bytes',
    () async {
      final box = await Hive.openBox<String>(
        'organizer_personal_v1',
        path: directory.path,
      );
      await box.put('committed_snapshot', '{"schemaVersion":999}');
      await box.close();
      final file = File('${directory.path}/organizer_personal_v1.hive');
      final before = await file.readAsBytes();
      final vault = service();
      await prepare(vault);
      await expectLater(vault.migrate(), throwsA(isA<LocalVaultException>()));
      expect(await file.readAsBytes(), before);
      expect((await vault.inspect()).canOpenDatabase, false);
    },
  );

  test(
    'secure store outage does not destroy source; no verification means no migration',
    () async {
      await createSource();
      final vault = service();
      keys.unavailable = true;
      await expectLater(
        vault.prepareRecoveryFile(),
        throwsA(isA<LocalVaultException>()),
      );
      expect(await vault.sourceFile.exists(), true);
      keys.unavailable = false;
      await vault.prepareRecoveryFile();
      await expectLater(vault.migrate(), throwsA(isA<LocalVaultException>()));
      expect(await vault.databaseFile.exists(), false);
    },
  );

  test(
    'active DB shared lease prevents concurrent migration in another service',
    () async {
      final vault = service();
      await prepare(vault);
      await vault.migrate();
      final db = await vault.openDatabase();
      await expectLater(
        service().migrate(),
        throwsA(isA<LocalVaultException>()),
      );
      await db.close();
      expect((await service().migrate()).phase, LocalVaultPhase.ready);
    },
  );

  test(
    'WAL-only committed row survives writer fence and all legacy handles close before cleanup',
    () async {
      await createSource();
      final writer = sqlite3.open(service().sourceFile.path);
      writer.execute('PRAGMA journal_mode = WAL');
      writer.execute('PRAGMA wal_autocheckpoint = 0');
      writer.execute(
        "INSERT INTO local_meta VALUES('wal_only','committed WAL sentinel')",
      );
      expect(
        await File('${service().sourceFile.path}-wal').length(),
        greaterThan(0),
      );
      final vault = service();
      await prepare(vault);
      await vault.migrate();
      writer.close();
      final opened = await vault.openDatabase();
      expect(
        (await opened.rows(
          "SELECT value FROM local_meta WHERE name='wal_only'",
        )).single['value'],
        'committed WAL sentinel',
      );
      await opened.close();
      for (final suffix in ['', '-wal', '-shm', '-journal']) {
        expect(await File('${vault.sourceFile.path}$suffix').exists(), false);
      }
    },
  );

  test(
    'corrupt archive after durable switch prevents any legacy cleanup',
    () async {
      await createSource();
      final interrupted = service(
        checkpoint: (stage) {
          if (stage == 'switched') throw StateError('crash');
        },
      );
      await prepare(interrupted);
      await expectLater(
        interrupted.migrate(),
        throwsA(isA<LocalVaultException>()),
      );
      final bytes = await interrupted.archiveFile.readAsBytes();
      bytes[1024] ^= 1;
      await interrupted.archiveFile.writeAsBytes(bytes, flush: true);
      await expectLater(
        service().migrate(),
        throwsA(isA<LocalVaultException>()),
      );
      expect(await interrupted.sourceFile.exists(), true);
      expect((await service().inspect()).phase, LocalVaultPhase.cleanupPending);
    },
  );

  test(
    'missing encrypted DB after completion fails closed without recreating file',
    () async {
      final vault = service();
      await prepare(vault);
      await vault.migrate();
      await vault.databaseFile.delete();
      await expectLater(
        vault.openDatabase(),
        throwsA(isA<LocalVaultException>()),
      );
      expect(await vault.databaseFile.exists(), false);
    },
  );

  test(
    'candidate fsync/disk-full failure retains source and does not switch',
    () async {
      await createSource();
      final vault = NativeLocalVaultService(
        directory,
        keys,
        preferences: preferences,
        files: _FailCandidateFlush(),
      );
      await prepare(vault);
      final before = await vault.sourceFile.readAsBytes();
      await expectLater(vault.migrate(), throwsA(isA<LocalVaultException>()));
      expect(await vault.sourceFile.readAsBytes(), before);
      expect(await vault.databaseFile.exists(), false);
      expect((await service().migrate()).phase, LocalVaultPhase.ready);
    },
  );
  test(
    'unexpected encrypted target with pre-switch journal is never overwritten',
    () async {
      await createSource();
      final vault = service();
      await prepare(vault);
      final sentinel = Uint8List.fromList(List.generate(128, (i) => i));
      await vault.databaseFile.writeAsBytes(sentinel, flush: true);
      await expectLater(
        vault.migrate(),
        throwsA(
          isA<LocalVaultException>().having(
            (e) => e.code,
            'code',
            'vault_state_conflict',
          ),
        ),
      );
      expect(await vault.databaseFile.readAsBytes(), sentinel);
      expect(await vault.sourceFile.exists(), true);
    },
  );

  test(
    'unknown virtual table stops before switch and preserves source',
    () async {
      await createSource();
      final db = sqlite3.open(service().sourceFile.path);
      db.execute('CREATE VIRTUAL TABLE future_search USING fts5(content)');
      db.execute("INSERT INTO future_search VALUES('future private index')");
      db.close();
      final vault = service();
      await prepare(vault);
      final before = await vault.sourceFile.readAsBytes();
      await expectLater(
        vault.migrate(),
        throwsA(
          isA<LocalVaultException>().having(
            (e) => e.code,
            'code',
            'vault_schema_unsupported',
          ),
        ),
      );
      expect(await vault.sourceFile.readAsBytes(), before);
      expect(await vault.databaseFile.exists(), false);
    },
  );

  test(
    'reappeared changed legacy Hive after switch is retained for explicit recovery',
    () async {
      final box = await Hive.openBox<String>(
        'organizer_personal_v1',
        path: directory.path,
      );
      await box.put(
        'committed_snapshot',
        OrganizerBackupCodec.encode(OrganizerSnapshot()),
      );
      await box.close();
      final vault = service();
      await prepare(vault);
      await vault.migrate();
      final file = File('${directory.path}/organizer_personal_v1.hive');
      await file.writeAsString('new legacy writer data', flush: true);
      expect((await vault.inspect()).phase, LocalVaultPhase.cleanupPending);
      await expectLater(vault.migrate(), throwsA(isA<LocalVaultException>()));
      expect(await file.readAsString(), 'new legacy writer data');
    },
  );
}

class _FailCandidateFlush extends LocalVaultFiles {
  @override
  Future<void> flush(File file) async {
    if (file.path.endsWith('/candidate.sqlite')) {
      throw const LocalVaultException('vault_io');
    }
    await super.flush(file);
  }
}

class _LegacyFrame implements OrganizerStorage {
  _LegacyFrame(this.value);
  final String value;
  @override
  Future<OrganizerSnapshot> read() async => OrganizerBackupCodec.decode(value);
  @override
  Future<void> write(OrganizerSnapshot snapshot) async =>
      throw UnimplementedError();
  @override
  Future<void> close() async {}
}
