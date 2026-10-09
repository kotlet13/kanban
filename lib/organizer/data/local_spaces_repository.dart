import 'dart:convert';
import '../domain/local_space_models.dart';
import '../domain/organizer_models.dart';
import '../domain/garden_models.dart';
import 'collaboration_database.dart';
import 'collaboration_repository.dart' show newSharedId;
import 'organizer_repository.dart';
import 'sqlite_organizer_storage.dart';

class LocalSpacesRepository {
  LocalSpacesRepository(this.database);
  final CollaborationDatabase database;
  Stream<void> get changes => database.personalChanges.stream;
  Future<LocalSpacesState> read() => database.transaction(() async {
    final storage = SqliteOrganizerStorage(database);
    final spaces =
        (await database.rows('SELECT data FROM local_spaces ORDER BY rowid'))
            .map(
              (r) => LocalSpace.fromJson(
                jsonDecode(r['data'] as String) as Map<String, dynamic>,
              ),
            )
            .toList();
    return LocalSpacesState(
      spaces: spaces,
      selectedSpaceId: database.selectedLocalWorkspaceId,
      snapshots: {
        for (final s in spaces)
          s.id: s.binding == null
              ? s.id == 'local'
                    ? await storage.defaultPersonalSnapshot()
                    : (await storage.localSnapshot(
                        workspace: s.id,
                      )).copyWith(workspaceKey: s.id)
              : OrganizerSnapshot(workspaceKey: s.id),
      },
    );
  });
  Future<LocalSpace> createSpace({
    required LocalSpaceKind kind,
    required String name,
    String address = '',
  }) async {
    final space = LocalSpace(
      id: newSharedId(),
      kind: kind,
      name: name.trim(),
      address: address.trim(),
    );
    space.validate();
    await database.transaction(() async {
      await database.execute('INSERT INTO local_spaces(id,data) VALUES(?,?)', [
        space.id,
        jsonEncode(space.toJson()),
      ]);
      await database.execute('INSERT INTO personal_workspaces(id) VALUES(?)', [
        space.id,
      ]);
      await database.touchPersonal();
    });
    database.personalChanged();
    return space;
  }

  Future<void> materializeFinanceOccurrences(
    String localSpaceId, {
    required String expectedWorkspaceKey,
    DateTime? through,
    Set<String>? ruleIds,
  }) async {
    final storage = SqliteOrganizerStorage(database, workspaceId: localSpaceId);
    await storage.initialize();
    final repo = OrganizerRepository(storage);
    await repo.initialize();
    try {
      await repo.materializeFinanceOccurrences(
        expectedWorkspaceKey: expectedWorkspaceKey,
        through: through,
        ruleIds: ruleIds,
      );
    } finally {
      await repo.close();
    }
  }

  Future<void> markReminderRead(
    String localSpaceId,
    String reminderId, {
    required String expectedWorkspaceKey,
  }) async {
    final storage = SqliteOrganizerStorage(database, workspaceId: localSpaceId);
    await storage.initialize();
    final repo = OrganizerRepository(storage);
    await repo.initialize();
    try {
      if (repo.snapshot.workspaceKey != expectedWorkspaceKey) {
        throw const OrganizerConflictException('Reminder workspace changed');
      }
      await repo.markReminderRead(reminderId);
    } finally {
      await repo.close();
    }
  }

  Future<void> selectSpace(String id) async {
    await database.transaction(() async {
      if ((await database.rows('SELECT id FROM local_spaces WHERE id=?', [
        id,
      ])).isEmpty) {
        throw const OrganizerConflictException('Local space no longer exists');
      }
      await database.execute(
        "INSERT INTO local_meta(name,value) VALUES('selected_local_space',?) ON CONFLICT(name) DO UPDATE SET value=excluded.value",
        [id],
      );
    });
    database.activateLocalWorkspace(id);
  }

  Future<void> renameSpace(
    String id, {
    required String name,
    String address = '',
  }) async {
    final spaces = (await read()).spaces;
    final old = spaces.where((s) => s.id == id).firstOrNull;
    if (old == null) {
      throw const OrganizerConflictException('Local space no longer exists');
    }
    if (old.binding != null) {
      throw const OrganizerConflictException('Edit the linked space metadata');
    }
    final space = LocalSpace(
      id: id,
      kind: old.kind,
      name: name.trim(),
      address: address.trim(),
      binding: old.binding,
      financeRecoveryIncomplete: old.financeRecoveryIncomplete,
    );
    space.validate();
    await database.execute('UPDATE local_spaces SET data=? WHERE id=?', [
      jsonEncode(space.toJson()),
      id,
    ]);
    database.personalChanged();
  }

  Future<void> _requireHousehold(String id) async {
    final rows = await database.rows(
      'SELECT data FROM local_spaces WHERE id=?',
      [id],
    );
    final space = rows.isEmpty
        ? null
        : LocalSpace.fromJson(
            jsonDecode(rows.single['data'] as String) as Map<String, dynamic>,
          );
    if (space == null ||
        space.kind != LocalSpaceKind.household ||
        space.binding != null) {
      throw const OrganizerConflictException('Choose a household');
    }
  }

  Future<void> assignGardenToHousehold(
    String gardenId,
    String spaceId, {
    required int expectedRevision,
  }) async {
    await database.transaction(() async {
      await _requireHousehold(spaceId);
      final rows = await database.rows(
        'SELECT payload FROM device_gardens WHERE id=?',
        [gardenId],
      );
      if (rows.isEmpty ||
          (jsonDecode(rows.single['payload'] as String) as Map)['revision'] !=
              expectedRevision) {
        throw const OrganizerConflictException('Garden changed; reload');
      }
      final garden = Garden.fromJson(
        jsonDecode(rows.single['payload'] as String) as Map<String, dynamic>,
      );
      await database.execute('UPDATE device_gardens SET payload=? WHERE id=?', [
        jsonEncode(garden.copyWith(revision: garden.revision + 1).toJson()),
        gardenId,
      ]);
      await database.execute(
        "INSERT INTO local_meta(name,value) VALUES('garden_generation','1') ON CONFLICT(name) DO UPDATE SET value=CAST(value AS INTEGER)+1",
      );
      await database.execute(
        'INSERT INTO garden_space_links(garden_id,space_id) VALUES(?,?) ON CONFLICT(garden_id) DO UPDATE SET space_id=excluded.space_id',
        [gardenId, spaceId],
      );
      await database.touchPersonal();
    });
    database.personalChanged();
  }

  Future<void> moveShoppingListToHousehold(
    String listId,
    String spaceId, {
    required int expectedRevision,
  }) async {
    final source = database.selectedLocalWorkspaceId,
        generation = database.personalIdentityGeneration;
    await database.transaction(() async {
      await _requireHousehold(spaceId);
      final rows = await database.rows(
        r"SELECT * FROM personal_records WHERE workspace=? AND (id=? OR (type='shoppingItem' AND json_extract(payload,'$.listId')=?))",
        [source, listId, listId],
      );
      final list = rows
          .where((r) => r['type'] == 'shoppingList' && r['id'] == listId)
          .firstOrNull;
      if (list == null ||
          (jsonDecode(list['payload'] as String) as Map)['revision'] !=
              expectedRevision ||
          generation != database.personalIdentityGeneration) {
        throw const OrganizerConflictException('Shopping list changed; reload');
      }
      if (source == spaceId) return;
      for (final row in rows) {
        if ((await database.rows(
          'SELECT id FROM personal_records WHERE workspace=? AND id=?',
          [spaceId, row['id']],
        )).isNotEmpty) {
          throw const OrganizerConflictException(
            'Destination already contains this record',
          );
        }
        await database.execute(
          'UPDATE personal_records SET workspace=? WHERE workspace=? AND id=?',
          [spaceId, source, row['id']],
        );
      }
      await database.touchPersonal();
    });
    database.personalChanged();
  }
}
