import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/account_deletion_store.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/data/garden_repository.dart';
import 'package:kanban/organizer/data/garden_storage.dart';
import 'package:kanban/organizer/data/organizer_repository.dart';
import 'package:kanban/organizer/data/organizer_storage.dart';
import 'package:kanban/organizer/data/portable_backup_document.dart';
import 'package:kanban/organizer/data/portable_backup_repository.dart';
import 'package:kanban/organizer/data/sqlite_organizer_storage.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:kanban/organizer/domain/garden_models.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';

import 'account_deletion_repository_test.dart' show DeletionServer;
import 'collaboration_repository_test.dart' show MemorySessionStore;
import 'private_sync_test_support.dart';

const gardenId = '11111111-1111-4111-8111-111111111111';
const areaId = '22222222-2222-4222-8222-222222222222';
final now = DateTime.utc(2026, 10, 7);
GardenArea area({double x = 0.1, double width = 0.4}) => GardenArea(
  id: areaId,
  label: 'Paradižnik',
  x: x,
  y: 0.2,
  width: width,
  height: 0.3,
);
Garden garden() => Garden(
  id: gardenId,
  name: 'Doma',
  notes: 'Severni rob 🌱',
  areas: [area()],
  createdAt: now,
  updatedAt: now,
);

/// The pre-garden JSON v2 fixture has only tasks, with the fields that existed
/// before planning v4. Do not relabel a current document as an older format.
String legacyTaskBackup(OrganizerSnapshot snapshot) {
  expect(snapshot.people, isEmpty);
  expect(snapshot.financeAccounts, isEmpty);
  expect(snapshot.financeRecurrenceRules, isEmpty);
  expect(snapshot.projects, isEmpty);
  expect(snapshot.financeEntries, isEmpty);
  final data = snapshot.toJson();
  for (final key in ['people', 'financeAccounts', 'financeRecurrenceRules']) {
    data.remove(key);
  }
  data['tasks'] = snapshot.tasks.map((task) {
    expect(task.phaseId, isNull);
    expect(task.estimateMinutes, isNull);
    expect(task.availabilityMinutes, isNull);
    expect(task.availabilityPeriod, isNull);
    expect(task.assigneePersonId, isNull);
    expect(task.subjectPersonIds, isEmpty);
    expect(task.timer.toJson(), const TaskTimerState().toJson());
    return Map<String, Object?>.from(task.toJson())..removeWhere(
      (key, _) => const {
        'phaseId',
        'estimateMinutes',
        'availabilityMinutes',
        'availabilityPeriod',
        'timer',
        'assigneePersonId',
        'subjectPersonIds',
      }.contains(key),
    );
  }).toList();
  return jsonEncode({
    'format': 'vsakdan-personal-backup',
    'schemaVersion': 2,
    'workspace': 'personal',
    'data': data,
  });
}

Future<
  ({
    CollaborationDatabase db,
    GardenRepository garden,
    OrganizerRepository personal,
    SqliteOrganizerStorage storage,
    PortableBackupRepository backup,
  })
>
client({File? file}) async {
  final db = CollaborationDatabase(
    file == null ? NativeDatabase.memory() : NativeDatabase(file),
  );
  final storage = SqliteOrganizerStorage(db);
  await storage.initialize();
  final personal = OrganizerRepository(storage);
  await personal.initialize();
  final gardens = GardenRepository(GardenStorage(db));
  await gardens.initialize();
  addTearDown(() async {
    await gardens.close();
    await personal.close();
    await db.close();
  });
  return (
    db: db,
    garden: gardens,
    personal: personal,
    storage: storage,
    backup: PortableBackupRepository(
      db,
      storage,
      MemoryBackupUiPreferencesStore(),
    ),
  );
}

class GardenPersonalTransport extends PersonalTransport {
  GardenPersonalTransport(super.server);
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
    final result = await super.call(
      serverUrl: serverUrl,
      operation: operation,
      params: params,
      token: token,
      allowLocalHttp: allowLocalHttp,
    );
    if (operation == 'capabilities') {
      (result['features'] as Map)['accountDeletion'] = true;
    }
    return result;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  test(
    'device-local named gardens, notes and layout survive actual file restart',
    () async {
      final dir = await Directory.systemTemp.createTemp('jivie-garden-');
      final file = File('${dir.path}/local.sqlite');
      Future<(CollaborationDatabase, GardenRepository)> open() async {
        final db = CollaborationDatabase(NativeDatabase(file));
        final repo = GardenRepository(GardenStorage(db), clock: () => now);
        await repo.initialize();
        return (db, repo);
      }

      final (db, repo) = await open();
      try {
        expect(repo.snapshot.gardens, isEmpty);
        final id = await repo.createGarden(
          name: ' Doma ',
          notes: 'Severni rob 🌱',
          areas: [area()],
        );
        await repo.createGarden(name: 'Vikend');
        final old = repo.snapshot.gardens.firstWhere((g) => g.id == id);
        await repo.updateGarden(
          old.copyWith(areas: [area(x: 0.3, width: 0.2)]),
        );
        final expected = repo.snapshot.toJson();
        expect(await db.rows('SELECT * FROM outbox'), isEmpty);
        expect(db.personalProfile, isNull);
        await repo.close();
        await db.close();
        final (reopenedDb, reopened) = await open();
        try {
          expect(reopened.snapshot.toJson(), expected);
          final saved = reopened.snapshot.gardens.firstWhere((g) => g.id == id);
          expect(saved.name, 'Doma');
          expect(saved.areas.single.x, 0.3);
          await reopened.deleteGarden(saved);
          expect(reopened.snapshot.gardens.single.name, 'Vikend');
        } finally {
          await reopened.close();
          await reopenedDb.close();
        }
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );

  test(
    'two repositories preserve unrelated writes and reject stale edit/delete',
    () async {
      final c = await client();
      final second = GardenRepository(GardenStorage(c.db));
      await second.initialize();
      addTearDown(second.close);
      await c.garden.createGarden(name: 'Prvi');
      final stale = c.garden.snapshot.gardens.single;
      await second.createGarden(name: 'Drugi');
      await second.updateGarden(stale.copyWith(notes: 'Novejši zapis'));
      await expectLater(
        c.garden.updateGarden(stale.copyWith(name: 'Staro')),
        throwsA(isA<OrganizerConflictException>()),
      );
      await expectLater(
        c.garden.deleteGarden(stale),
        throwsA(isA<OrganizerConflictException>()),
      );
      await c.garden.reload();
      expect(c.garden.snapshot.gardens.length, 2);
      expect(
        c.garden.snapshot.gardens.firstWhere((g) => g.id == stale.id).notes,
        'Novejši zapis',
      );
    },
  );

  test('malformed/newer data, identities, coordinates and bounds rejected', () {
    final valid = GardenSnapshot(gardens: [garden()]).toJson();
    expect(
      GardenSnapshot.fromJson(
        jsonDecode(jsonEncode(valid)) as Map<String, dynamic>,
      ).gardens.single.notes,
      'Severni rob 🌱',
    );
    for (final mutate in <void Function(Map<String, dynamic>)>[
      (j) => j['version'] = 3,
      (j) => j['token'] = 'unknown',
      (j) => (j['gardens'] as List).first['revision'] = -1,
      (j) => (j['gardens'] as List).first['createdAt'] =
          '2026-02-30T10:00:00.000Z',
      (j) => (j['gardens'] as List).first['name'] = '',
      (j) => (j['gardens'] as List).first['name'] = 'x' * 201,
      (j) => (j['gardens'] as List).first['notes'] = 'x' * 20001,
      (j) => (j['gardens'] as List).first['id'] = 'invalid',
      (j) => (j['gardens'] as List).first['areas'][0]['x'] = 0.9,
      (j) => (j['gardens'] as List).first['areas'][0]['height'] = 0,
      (j) => (j['gardens'] as List).first['areas'][0]['label'] = '',
      (j) => (j['gardens'] as List).first['areas'].add(
        (j['gardens'] as List).first['areas'][0],
      ),
    ]) {
      final changed = jsonDecode(jsonEncode(valid)) as Map<String, dynamic>;
      mutate(changed);
      expect(() => GardenSnapshot.fromJson(changed), throwsFormatException);
    }
    expect(() => area(x: double.nan).validate(), throwsFormatException);
    expect(
      () => area(x: 0, width: 1.0000000001).validate(),
      throwsFormatException,
    );
    expect(
      () => area(x: 0.6000000001, width: 0.4).validate(),
      throwsFormatException,
    );
    expect(
      () => area(width: double.infinity).validate(),
      throwsFormatException,
    );
    expect(
      () => GardenSnapshot(gardens: List.filled(501, garden())).validate(),
      throwsFormatException,
    );
    expect(
      () => garden().copyWith(areas: List.filled(1001, area())).validate(),
      throwsFormatException,
    );
  });

  test('oversized valid garden collection rejected before persistence', () {
    final notes = 'ž' * 20000;
    final tooLarge = GardenSnapshot(
      gardens: List.generate(
        300,
        (i) => Garden(
          id: '00000000-0000-4000-8000-${i.toRadixString(16).padLeft(12, '0')}',
          name: 'Vrt $i',
          notes: notes,
          createdAt: now,
          updatedAt: now,
        ),
      ),
    );
    expect(tooLarge.validate, throwsFormatException);
  });

  test('corrupt or newer committed garden rows never reset to empty', () async {
    final c = await client();
    final payload = jsonEncode({...garden().toJson(), 'futureField': true});
    await c.db.execute('INSERT INTO device_gardens(id,payload) VALUES(?,?)', [
      gardenId,
      payload,
    ]);
    await expectLater(c.garden.reload(), throwsFormatException);
    await expectLater(
      c.garden.createGarden(name: 'Do not replace corrupt data'),
      throwsFormatException,
    );
    expect(
      (await c.db.rows('SELECT payload FROM device_gardens')).single['payload'],
      payload,
    );
  });

  test('unit canvas exact right and lower edge placement remains valid', () {
    for (final width in [1.0, 0.99, 0.67, 0.3333333333333, 0.1, 0.01]) {
      GardenArea(
        id: areaId,
        label: 'Rob',
        x: 1 - width,
        y: 1 - width,
        width: width,
        height: width,
      ).validate();
    }
  });

  test('schema four database upgrade preserves personal records', () async {
    final dir = await Directory.systemTemp.createTemp('garden-migration-');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/local.sqlite');
    final original = CollaborationDatabase(NativeDatabase(file));
    final storage = SqliteOrganizerStorage(original);
    await storage.initialize();
    final personal = OrganizerRepository(storage);
    await personal.initialize();
    await personal.createTask(title: 'Ohranjeno opravilo');
    await personal.close();
    // Reconstruct schema 4, including its actual pre-schema-6 finance table.
    // Merely lowering user_version on a current database leaves wire_version
    // in place and is not a legacy migration fixture.
    await original.execute(
      'ALTER TABLE finance_outbox DROP COLUMN wire_version',
    );
    await original.execute('DROP TABLE device_gardens');
    final rows = await original.rows('SELECT id,payload FROM personal_records');
    final legacy = jsonDecode(legacyTaskBackup(personal.snapshot)) as Map;
    final legacyTask = ((legacy['data'] as Map)['tasks'] as List).single;
    await original.execute('UPDATE personal_records SET payload=? WHERE id=?', [
      jsonEncode(legacyTask),
      rows.single['id'],
    ]);
    await original.execute(
      "DELETE FROM local_meta WHERE name LIKE 'personal_record_revision:%'",
    );
    expect(
      (await original.rows(
        'PRAGMA table_info(finance_outbox)',
      )).any((column) => column['name'] == 'wire_version'),
      isFalse,
    );
    await original.execute('DROP TABLE garden_space_links');
    await original.execute('DROP TABLE local_spaces');
    await original.execute('DROP TABLE linked_payment_cash');
    await original.execute('DROP TABLE linked_payment_events');
    await original.execute('DROP TABLE linked_payment_projections');
    await original.execute('DROP TABLE linked_payment_intents');
    await original.execute('PRAGMA user_version=4');
    await original.close();
    final upgraded = await client(file: file);
    expect(upgraded.personal.snapshot.tasks.single.title, 'Ohranjeno opravilo');
    expect(upgraded.garden.snapshot.gardens, isEmpty);
    expect(upgraded.personal.snapshot.tasks.single.timer.running, isFalse);
    expect(
      (await upgraded.db.rows('PRAGMA table_info(finance_outbox)')).singleWhere(
        (column) => column['name'] == 'wire_version',
      )['dflt_value'],
      '1',
    );
    await upgraded.garden.createGarden(name: 'Nov vrt');
  });

  test(
    'personal JSON carries fresh gardens, rejects collision and rolls both domains back',
    () async {
      final a = await client(), b = await client();
      await a.personal.createTask(title: 'Naloga');
      await a.garden.createGarden(
        name: 'Vrt',
        notes: 'Čebula',
        areas: [area()],
      );
      final json = await a.personal.exportBackup();
      final document = OrganizerBackupCodec.decodeDocument(json);
      expect(document.gardens!.gardens.single.notes, 'Čebula');
      expect(jsonDecode(json)['schemaVersion'], 4);
      final unknown = jsonDecode(json) as Map<String, dynamic>;
      (unknown['gardens'] as Map)['futureField'] = true;
      await expectLater(
        b.personal.importBackup(jsonEncode(unknown)),
        throwsFormatException,
      );
      expect((await b.storage.read()).tasks, isEmpty);
      expect((await GardenStorage(b.db).read()).gardens, isEmpty);
      await b.db.execute(
        "CREATE TRIGGER fail_garden BEFORE INSERT ON device_gardens BEGIN SELECT RAISE(ABORT,'test abort'); END",
      );
      await expectLater(b.personal.importBackup(json), throwsA(anything));
      expect((await b.storage.read()).tasks, isEmpty);
      expect((await GardenStorage(b.db).read()).gardens, isEmpty);
      await b.db.execute('DROP TRIGGER fail_garden');
      // JSON v3 was the garden release, before planning collections existed.
      final gardenV3 = jsonDecode(legacyTaskBackup(a.personal.snapshot)) as Map;
      gardenV3['schemaVersion'] = 3;
      gardenV3['gardens'] = document.gardens!.toJson();
      await b.personal.importBackup(jsonEncode(gardenV3));
      expect((await b.storage.read()).tasks.single.title, 'Naloga');
      expect(
        (await GardenStorage(b.db).read()).gardens.single.areas.single.label,
        'Paradižnik',
      );
      final committed = (await GardenStorage(b.db).read()).toJson();
      await expectLater(b.personal.importBackup(json), throwsA(anything));
      expect((await GardenStorage(b.db).read()).toJson(), committed);
      // Older personal JSON still restores without touching garden data.
      final old = await client();
      await old.personal.createTask(title: 'Star izvoz');
      final legacy = legacyTaskBackup(old.personal.snapshot);
      await b.personal.importBackup(legacy);
      expect((await GardenStorage(b.db).read()).toJson(), committed);
      expect((await b.storage.read()).tasks.length, 2);
      // Restoring the same id after deletion must invalidate its old editor.
      final c = await client();
      await c.garden.createGarden(name: 'Ponovljena identiteta');
      final openEditor = c.garden.snapshot.gardens.single;
      final jsonOnlyGarden = await c.personal.exportBackup();
      await c.garden.deleteGarden(openEditor);
      await c.personal.importBackup(jsonOnlyGarden);
      await expectLater(
        c.garden.updateGarden(openEditor.copyWith(notes: 'ABA JSON')),
        throwsA(isA<OrganizerConflictException>()),
      );
      expect(
        (await GardenStorage(c.db).read()).gardens.single.revision,
        greaterThan(openEditor.revision),
      );
    },
  );

  test(
    'actual encrypted backup atomically restores layout, stale review and collisions; legacy preserves gardens',
    () async {
      const password = 'a sufficiently long garden password';
      final a = await client(), b = await client();
      await a.garden.createGarden(
        name: 'Vrt kopije',
        notes: 'Brez strežnika',
        areas: [area()],
      );
      await a.personal.createTask(title: 'V isti transakciji');
      final bytes = await a.backup.exportEncryptedBackup(password);
      expect(utf8.decode(bytes), isNot(contains('Brez strežnika')));
      final preview = await a.backup.inspectEncryptedBackup(bytes, password);
      expect(preview.personalCounts['gardens'], 1);
      final revision = (await b.storage.read()).revision;
      await b.db.execute(
        "CREATE TRIGGER fail_garden_restore BEFORE INSERT ON device_gardens BEGIN SELECT RAISE(ABORT,'restore abort'); END",
      );
      await expectLater(
        b.backup.restoreEncryptedBackup(
          bytes,
          password,
          mode: BackupRestoreMode.replace,
          expectedPersonalRevision: revision,
        ),
        throwsA(anything),
      );
      expect((await b.storage.read()).tasks, isEmpty);
      expect(await b.db.rows('SELECT * FROM restored_backups'), isEmpty);
      await b.db.execute('DROP TRIGGER fail_garden_restore');
      // Portable v2/schema 5 carried gardens but neither operation pairs nor
      // finance inbox receipts. Restore that real old shape, not current v3.
      final gardenV2 = await a.backup.crypto.decrypt(bytes, password);
      gardenV2.remove('operationPairs');
      gardenV2.remove('financeInboxReads');
      gardenV2.remove('localSpaces');
      gardenV2.remove('gardenSpaceLinks');
      gardenV2.remove('linkedPayments');
      gardenV2['version'] = 2;
      gardenV2['databaseVersion'] = 5;
      gardenV2['personal'] = legacyTaskBackup(a.personal.snapshot);
      validateBackupDocument(gardenV2);
      final gardenV2Bytes = await a.backup.crypto.encrypt(gardenV2, password);
      await b.backup.restoreEncryptedBackup(
        gardenV2Bytes,
        password,
        mode: BackupRestoreMode.replace,
        expectedPersonalRevision: revision,
      );
      await b.garden.reload();
      final stale = b.garden.snapshot.gardens.single;
      expect(stale.notes, 'Brez strežnika');
      expect(stale.areas.single.toJson(), area().toJson());
      await expectLater(
        b.backup.restoreEncryptedBackup(
          bytes,
          password,
          mode: BackupRestoreMode.merge,
          expectedPersonalRevision: (await b.storage.read()).revision,
        ),
        throwsA(
          isA<CollaborationException>().having(
            (e) => e.code,
            'code',
            'backup_conflict',
          ),
        ),
      );
      final oldDoc = await a.backup.crypto.decrypt(bytes, password);
      oldDoc.remove('gardens');
      oldDoc.remove('operationPairs');
      oldDoc.remove('financeInboxReads');
      oldDoc.remove('localSpaces');
      oldDoc.remove('gardenSpaceLinks');
      oldDoc.remove('linkedPayments');
      oldDoc['version'] = 1;
      oldDoc['databaseVersion'] = 4;
      oldDoc['personal'] = legacyTaskBackup(a.personal.snapshot);
      validateBackupDocument(oldDoc);
      final legacyBytes = await a.backup.crypto.encrypt(oldDoc, password);
      await b.backup.restoreEncryptedBackup(
        legacyBytes,
        password,
        mode: BackupRestoreMode.replace,
        expectedPersonalRevision: (await b.storage.read()).revision,
      );
      expect(
        (await GardenStorage(b.db).read()).gardens.single.toJson(),
        stale.toJson(),
      );
      // Replacing a present garden invalidates an editor captured before restore.
      await b.backup.restoreEncryptedBackup(
        bytes,
        password,
        mode: BackupRestoreMode.replace,
        expectedPersonalRevision: (await b.storage.read()).revision,
      );
      await expectLater(
        b.garden.updateGarden(stale.copyWith(notes: 'Prepis')),
        throwsA(isA<OrganizerConflictException>()),
      );
      await b.garden.reload();
      final beforeDeletion = b.garden.snapshot.gardens.single;
      await b.garden.deleteGarden(beforeDeletion);
      await b.backup.restoreEncryptedBackup(
        bytes,
        password,
        mode: BackupRestoreMode.replace,
        expectedPersonalRevision: (await b.storage.read()).revision,
      );
      await expectLater(
        b.garden.updateGarden(beforeDeletion.copyWith(notes: 'ABA encrypted')),
        throwsA(isA<OrganizerConflictException>()),
      );
      final reviewRevision = (await b.storage.read()).revision;
      await b.garden.createGarden(name: 'Po pregledu');
      await expectLater(
        b.backup.restoreEncryptedBackup(
          bytes,
          password,
          mode: BackupRestoreMode.replace,
          expectedPersonalRevision: reviewRevision,
        ),
        throwsA(
          isA<CollaborationException>().having(
            (e) => e.code,
            'code',
            'backup_stale',
          ),
        ),
      );
    },
  );

  test(
    'private sync, logout and confirmed server account deletion never upload or erase gardens',
    () async {
      final c = await client();
      final server = DeletionServer();
      final transport = GardenPersonalTransport(server);
      final shared = CollaborationRepository(
        c.db,
        transport,
        MemorySessionStore(),
        ownsDatabase: false,
        deletionStore: MemoryAccountDeletionStore(),
      );
      await shared.initialize();
      addTearDown(shared.close);
      await c.garden.createGarden(name: 'Samo ta naprava', areas: [area()]);
      final saved = (await GardenStorage(c.db).read()).toJson();
      await shared.login(
        serverUrl: 'https://test.invalid',
        username: 'alice',
        password: 'test',
      );
      await shared.enablePrivateSync(
        expectedRevision: (await shared.previewPrivateSync()).revision,
      );
      await c.garden.updateGarden(
        c.garden.snapshot.gardens.single.copyWith(
          notes: 'Po vključeni sinhronizaciji',
        ),
      );
      await shared.syncNow();
      expect(await c.db.rows('SELECT * FROM outbox'), isEmpty);
      expect(await c.db.rows('SELECT * FROM personal_record_map'), isEmpty);
      expect(server.records.values.expand((r) => r.values), isEmpty);
      expect(saved['gardens'], isNotEmpty);
      await shared.signOut();
      expect(
        (await GardenStorage(c.db).read()).gardens.single.name,
        'Samo ta naprava',
      );
      await shared.login(
        serverUrl: 'https://test.invalid',
        username: 'alice',
        password: 'test',
      );
      final beforeDelete = (await GardenStorage(c.db).read()).toJson();
      final preview = await shared.previewAccountDeletion();
      await shared.confirmAccountDeletion(
        previewHash: preview['previewHash'] as String,
        password: 'test',
      );
      expect(shared.state.session, isNull);
      expect((await GardenStorage(c.db).read()).toJson(), beforeDelete);
      expect(await c.db.rows('SELECT * FROM accounts'), isEmpty);
    },
  );
}
