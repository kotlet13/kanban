import 'dart:io';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/local_spaces_repository.dart';
import 'package:kanban/organizer/data/organizer_repository.dart';
import 'package:kanban/organizer/data/garden_repository.dart';
import 'package:kanban/organizer/data/garden_storage.dart';
import 'package:kanban/organizer/data/sqlite_organizer_storage.dart';
import 'package:kanban/organizer/data/portable_backup_repository.dart';
import 'package:kanban/organizer/domain/local_space_models.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:kanban/organizer/domain/garden_models.dart';
import 'package:kanban/organizer/domain/all_spaces_projection.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  Future<
    (
      CollaborationDatabase,
      SqliteOrganizerStorage,
      LocalSpacesRepository,
      OrganizerRepository,
    )
  >
  client([File? file]) async {
    final db = CollaborationDatabase(
      file == null ? NativeDatabase.memory() : NativeDatabase(file),
    );
    final storage = SqliteOrganizerStorage(db);
    await storage.initialize();
    final repo = OrganizerRepository(storage);
    await repo.initialize();
    addTearDown(() async {
      await repo.close();
      await db.close();
    });
    return (db, storage, LocalSpacesRepository(db), repo);
  }

  test('spaces isolate records and stale editors across selection', () async {
    final (db, storage, spaces, repo) = await client();
    await repo.createTask(title: 'Private');
    final personal = await storage.read();
    final home = await spaces.createSpace(
      kind: LocalSpaceKind.household,
      name: 'Home',
    );
    final work = await spaces.createSpace(
      kind: LocalSpaceKind.organization,
      name: 'Work',
    );
    await spaces.selectSpace(home.id);
    await repo.reload();
    await repo.createTask(title: 'Family');
    expect((await storage.read()).tasks.single.title, 'Family');
    await expectLater(
      storage.write(
        personal.copyWith(revision: (await storage.read()).revision + 1),
      ),
      throwsA(isA<OrganizerConflictException>()),
    );
    await spaces.selectSpace(work.id);
    await repo.reload();
    await repo.createTask(title: 'Company');
    final catalog = await spaces.read();
    final all = projectAllSpaces(
      personal: await storage.read(),
      shared: CollaborationState(),
      localSpaces: catalog,
    );
    expect(all.tasks.map((r) => r.value.title).toSet(), {
      'Private',
      'Family',
      'Company',
    });
    expect(all.sources.map((s) => s.workspaceKey).toSet(), {
      'local',
      home.id,
      work.id,
    });
    expect(db.personalProfile, isNull);
  });
  test(
    'catalog selection and rows survive a database restart without account',
    () async {
      final directory = await Directory.systemTemp.createTemp('jivie-spaces-');
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/local.sqlite');
      final db = CollaborationDatabase(NativeDatabase(file)),
          storage = SqliteOrganizerStorage(db);
      await storage.initialize();
      final spaces = LocalSpacesRepository(db),
          repo = OrganizerRepository(storage);
      await repo.initialize();
      final home = await spaces.createSpace(
        kind: LocalSpaceKind.household,
        name: 'Durable',
      );
      await spaces.selectSpace(home.id);
      await repo.reload();
      await repo.createTask(title: 'Offline');
      await repo.close();
      await db.close();
      final (_, restored, reopened, _) = await client(file);
      expect((await reopened.read()).selectedSpaceId, home.id);
      expect((await restored.read()).tasks.single.title, 'Offline');
    },
  );
  test(
    'legacy garden assignment and shopping migration preserve IDs and isolate households',
    () async {
      final (db, storage, spaces, repo) = await client();
      final gardens = GardenRepository(GardenStorage(db));
      await gardens.initialize();
      addTearDown(gardens.close);
      final id = await gardens.createGarden(name: 'Old garden');
      final garden = (await GardenStorage(db).read()).gardens.single;
      await repo.createShoppingList(title: 'Old shopping');
      final list = (await storage.read()).shoppingLists.single;
      await repo.createShoppingItem(listId: list.id, title: 'Milk');
      final home = await spaces.createSpace(
        kind: LocalSpaceKind.household,
        name: 'Target',
      );
      await spaces.assignGardenToHousehold(
        id,
        home.id,
        expectedRevision: garden.revision,
      );
      await spaces.moveShoppingListToHousehold(
        list.id,
        home.id,
        expectedRevision: list.revision,
      );
      expect((await GardenStorage(db).read()).gardens, isEmpty);
      expect((await storage.read()).shoppingLists, isEmpty);
      await spaces.selectSpace(home.id);
      expect((await GardenStorage(db).read()).gardens.single.id, id);
      expect((await storage.read()).shoppingLists.single.id, list.id);
      expect((await storage.read()).shoppingItems.single.listId, list.id);
      final other = await spaces.createSpace(
        kind: LocalSpaceKind.household,
        name: 'Other',
      );
      await spaces.selectSpace(other.id);
      expect((await GardenStorage(db).read()).gardens, isEmpty);
    },
  );
  test(
    'garden editors and imported IDs cannot cross selected households',
    () async {
      final (db, _, spaces, _) = await client();
      final first = await spaces.createSpace(
        kind: LocalSpaceKind.household,
        name: 'First',
      );
      final second = await spaces.createSpace(
        kind: LocalSpaceKind.household,
        name: 'Second',
      );
      await spaces.selectSpace(first.id);
      final repo = GardenRepository(GardenStorage(db));
      await repo.initialize();
      addTearDown(repo.close);
      final id = await repo.createGarden(
        name: 'One',
        expectedWorkspaceKey: first.id,
      );
      final old = (await GardenStorage(db).read()).gardens.single;
      await spaces.assignGardenToHousehold(
        id,
        second.id,
        expectedRevision: old.revision,
      );
      await spaces.selectSpace(second.id);
      await expectLater(
        repo.updateGarden(old.copyWith(notes: 'stale')),
        throwsA(isA<OrganizerConflictException>()),
      );
      await expectLater(
        repo.createGarden(name: 'wrong', expectedWorkspaceKey: first.id),
        throwsA(isA<OrganizerConflictException>()),
      );
      final foreign = (await GardenStorage(db).read()).gardens.single;
      await spaces.selectSpace(first.id);
      final local = await GardenStorage(db).read();
      await expectLater(
        GardenStorage(db).write(
          GardenSnapshot(revision: local.revision, gardens: [foreign]),
          expectedRevision: local.revision,
        ),
        throwsA(isA<OrganizerConflictException>()),
      );
      await spaces.selectSpace(second.id);
      expect((await GardenStorage(db).read()).gardens.single.notes, isEmpty);
    },
  );
  test(
    'encrypted backup restores all spaces and household garden ownership offline',
    () async {
      final (db, storage, spaces, repo) = await client();
      final home = await spaces.createSpace(
        kind: LocalSpaceKind.household,
        name: 'Backup household',
      );
      await spaces.selectSpace(home.id);
      await repo.reload();
      await repo.createTask(title: 'Saved locally');
      final gardens = GardenRepository(GardenStorage(db));
      await gardens.initialize();
      await gardens.createGarden(name: 'Saved garden');
      await gardens.close();
      final backup = PortableBackupRepository(
        db,
        storage,
        MemoryBackupUiPreferencesStore(),
      );
      const password = 'a sufficiently long password';
      final bytes = await backup.exportEncryptedBackup(password);
      final (restoredDb, restoredStorage, restoredSpaces, _) = await client();
      final restoredBackup = PortableBackupRepository(
        restoredDb,
        restoredStorage,
        MemoryBackupUiPreferencesStore(),
      );
      await restoredBackup.restoreEncryptedBackup(
        bytes,
        password,
        mode: BackupRestoreMode.replace,
        expectedPersonalRevision: (await restoredStorage.read()).revision,
      );
      await restoredSpaces.selectSpace(home.id);
      expect(
        (await restoredStorage.read()).tasks.single.title,
        'Saved locally',
      );
      expect(
        (await GardenStorage(restoredDb).read()).gardens.single.name,
        'Saved garden',
      );
    },
  );
}
