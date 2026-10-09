import 'dart:io';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/data/garden_repository.dart';
import 'package:kanban/organizer/data/garden_storage.dart';
import 'package:kanban/organizer/data/local_spaces_repository.dart';
import 'package:kanban/organizer/data/organizer_repository.dart';
import 'package:kanban/organizer/data/portable_backup_repository.dart';
import 'package:kanban/organizer/data/sqlite_organizer_storage.dart';
import 'collaboration_repository_test.dart' show FakeServer, MemorySessionStore;
import 'private_sync_test_support.dart' show PersonalTransport;

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  test(
    'schema6 disk upgrade preserves personal, gardens, private binding and immutable pending request',
    () async {
      final directory = await Directory.systemTemp.createTemp('jivie-schema6-');
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/existing.sqlite');
      var db = CollaborationDatabase(NativeDatabase(file));
      var storage = SqliteOrganizerStorage(db);
      await storage.initialize();
      var local = OrganizerRepository(storage);
      await local.initialize();
      final sessions = MemorySessionStore(),
          transport = PersonalTransport(FakeServer());
      var shared = CollaborationRepository(
        db,
        transport,
        sessions,
        ownsDatabase: false,
      );
      await shared.initialize();
      await shared.login(
        serverUrl: 'https://example.test',
        username: 'alice',
        password: 'secret',
      );
      await local.createTask(title: 'Original private');
      await shared.enablePrivateSync(
        expectedRevision: (await shared.previewPrivateSync()).revision,
      );
      await shared.pausePrivateSync();
      db.activatePersonal(null);
      await local.reload();
      await local.createTask(title: 'Unpublished personal');
      db.activatePersonal(shared.state.session);
      final garden = GardenRepository(GardenStorage(db));
      await garden.initialize();
      await garden.createGarden(name: 'Legacy unassigned garden');
      await garden.close();
      final scope = await shared.createScope('Original shared');
      transport.offline = true;
      await shared.createTask(scopeId: scope, title: 'Pending original');
      // Reconstruct the actual v6 schema: only these two tables are added by v7.
      final beforePersonal = await db.rows(
        'SELECT * FROM personal_records ORDER BY workspace,id',
      );
      final beforeGardens = await db.rows(
        'SELECT * FROM device_gardens ORDER BY id',
      );
      final beforeBinding = await db.rows(
        'SELECT * FROM personal_workspaces ORDER BY id',
      );
      final beforeOutbox = await db.rows(
        'SELECT * FROM outbox ORDER BY sequence',
      );
      expect(beforePersonal, isNotEmpty);
      expect(beforeGardens, isNotEmpty);
      expect(beforeOutbox, isNotEmpty);
      await shared.close();
      await local.close();
      await db.execute('DROP TABLE garden_space_links');
      await db.execute('DROP TABLE local_spaces');
      await db.execute('DROP TABLE linked_payment_cash');
      await db.execute('DROP TABLE linked_payment_events');
      await db.execute('DROP TABLE linked_payment_projections');
      await db.execute('DROP TABLE linked_payment_intents');
      await db.execute('PRAGMA user_version=6');
      await db.close();
      db = CollaborationDatabase(NativeDatabase(file));
      storage = SqliteOrganizerStorage(db);
      await storage.initialize();
      local = OrganizerRepository(storage);
      await local.initialize();
      shared = CollaborationRepository(
        db,
        transport,
        sessions,
        ownsDatabase: false,
      );
      await shared.initialize();
      addTearDown(() async {
        await local.close();
        await shared.close();
        await db.close();
      });
      expect((await db.rows('PRAGMA user_version')).single['user_version'], 8);
      expect(
        await db.rows('SELECT * FROM personal_records ORDER BY workspace,id'),
        beforePersonal,
      );
      expect(
        await db.rows('SELECT * FROM device_gardens ORDER BY id'),
        beforeGardens,
      );
      expect(
        await db.rows('SELECT * FROM personal_workspaces ORDER BY id'),
        beforeBinding,
      );
      expect(
        await db.rows('SELECT * FROM outbox ORDER BY sequence'),
        beforeOutbox,
      );
      final catalog = await LocalSpacesRepository(db).read();
      expect(catalog.spaces.single.id, 'local');
      expect(catalog.spaces.single.name, isEmpty);
      expect(
        (await storage.localSnapshot()).tasks.single.title,
        'Unpublished personal',
      );
      expect(
        (await GardenStorage(db).read()).gardens.single.name,
        'Legacy unassigned garden',
      );
      final backup = PortableBackupRepository(
        db,
        storage,
        MemoryBackupUiPreferencesStore(),
        collaboration: () => shared,
      );
      const password = 'original durable backup password';
      final document = await backup.crypto.decrypt(
        await backup.exportEncryptedBackup(password),
        password,
      );
      expect(document['version'], 4);
      expect(document['databaseVersion'], 8);
      expect((document['localSpaces'] as List).single['space']['id'], 'local');
      expect((document['tables'] as Map)['outbox'], beforeOutbox);
    },
  );
}
