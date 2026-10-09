import 'dart:convert';
import '../domain/garden_models.dart';
import 'collaboration_database.dart';
import 'organizer_repository.dart' show OrganizerConflictException;

/// Device-local rows deliberately have no account partition or sync operation.
class GardenStorage {
  GardenStorage(this.database);
  final CollaborationDatabase database;
  String get workspaceKey => database.selectedLocalWorkspaceId;
  int get identityGeneration => database.personalIdentityGeneration;
  Stream<void> get changes => database.personalChanges.stream;
  Future<GardenSnapshot> read() => database.transaction(() async {
    final all = await readAll();
    final space = database.selectedLocalWorkspaceId;
    final links = await database.rows(
      'SELECT garden_id,space_id FROM garden_space_links',
    );
    final ownership = {
      for (final link in links) link['garden_id']: link['space_id'],
    };
    return GardenSnapshot(
      revision: all.revision,
      workspaceKey: workspaceKey,
      gardens: all.gardens.where(
        (g) => space == 'local'
            ? !ownership.containsKey(g.id)
            : ownership[g.id] == space,
      ),
    );
  });
  Future<GardenSnapshot> readAll() => database.transaction(() async {
    final generation = await database.rows(
      "SELECT value FROM local_meta WHERE name='garden_generation'",
    );
    final rows = await database.rows(
      'SELECT id,payload FROM device_gardens ORDER BY id',
    );
    final snapshot = GardenSnapshot(
      revision: generation.isEmpty
          ? 0
          : int.parse(generation.single['value'] as String),
      gardens: rows.map((r) {
        final garden = Garden.fromJson(
          jsonDecode(r['payload'] as String) as Map<String, dynamic>,
        );
        if (garden.id != r['id']) {
          throw const FormatException('Garden row identity mismatch');
        }
        return garden;
      }),
    );
    snapshot.validate();
    return snapshot;
  });

  /// Caller may already own a larger restore transaction. No changes are sent
  /// remotely; personal generation guards existing backup confirmation screens.
  Future<void> write(
    GardenSnapshot snapshot, {
    required int expectedRevision,
    bool allSpaces = false,
    String? expectedWorkspaceKey,
    int? expectedIdentityGeneration,
  }) => database.transaction(() async {
    snapshot.validate();
    if ((expectedWorkspaceKey != null &&
            expectedWorkspaceKey != database.selectedLocalWorkspaceId) ||
        (expectedIdentityGeneration != null &&
            expectedIdentityGeneration !=
                database.personalIdentityGeneration)) {
      throw const OrganizerConflictException('Garden workspace changed');
    }
    final previous = allSpaces ? await readAll() : await read();
    final identity = database.personalIdentityGeneration;
    final space = database.selectedLocalWorkspaceId;
    if (previous.revision != expectedRevision) {
      throw const OrganizerConflictException(
        'Garden changed; reload before writing',
      );
    }
    final old = {for (final garden in previous.gardens) garden.id: garden};
    final next = {for (final garden in snapshot.gardens) garden.id: garden};
    for (final garden in previous.gardens) {
      if (!next.containsKey(garden.id)) {
        // Keep a non-content revision floor after deletion. Restoring the same
        // UUID must not make a previously open editor valid again (ABA).
        final floor = await _revisionFloor(garden.id);
        await _saveFloor(
          garden.id,
          floor != null && floor > garden.revision
              ? floor
              : garden.revision + 1,
        );
        await database.execute(
          'DELETE FROM garden_space_links WHERE garden_id=?',
          [garden.id],
        );
        await database.execute('DELETE FROM device_gardens WHERE id=?', [
          garden.id,
        ]);
      }
    }
    for (final garden in snapshot.gardens) {
      final existing = old[garden.id];
      if (existing == null &&
          !allSpaces &&
          (await database.rows('SELECT id FROM device_gardens WHERE id=?', [
            garden.id,
          ])).isNotEmpty) {
        throw const OrganizerConflictException(
          'Garden belongs to another space',
        );
      }
      if (existing != null &&
          jsonEncode(existing.toJson()) == jsonEncode(garden.toJson())) {
        continue;
      }
      final floor = await _revisionFloor(garden.id);
      var minimum = existing == null ? 0 : existing.revision + 1;
      if (floor != null && floor + 1 > minimum) {
        minimum = floor + 1;
      }
      final committed = garden.copyWith(
        revision: garden.revision < minimum ? minimum : garden.revision,
      );
      await database.execute(
        'INSERT INTO device_gardens(id,payload) VALUES(?,?) ON CONFLICT(id) DO UPDATE SET payload=excluded.payload',
        [committed.id, jsonEncode(committed.toJson())],
      );
      await _saveFloor(committed.id, committed.revision);
      if (!allSpaces && existing == null && space != 'local') {
        final household = await database.rows(
          r"SELECT id FROM local_spaces WHERE id=? AND json_extract(data,'$.kind')='household'",
          [space],
        );
        if (household.isEmpty) {
          throw const OrganizerConflictException(
            'Choose a household for a garden',
          );
        }
        await database.execute(
          'INSERT INTO garden_space_links(garden_id,space_id) VALUES(?,?)',
          [committed.id, space],
        );
      }
    }
    await database.execute(
      "INSERT INTO local_meta(name,value) VALUES('garden_generation',?) ON CONFLICT(name) DO UPDATE SET value=excluded.value",
      [(expectedRevision + 1).toString()],
    );
    if (identity != database.personalIdentityGeneration) {
      throw const OrganizerConflictException('Garden workspace changed');
    }
    await database.touchPersonal();
  });

  Future<int?> _revisionFloor(String id) async {
    final rows = await database.rows(
      'SELECT value FROM local_meta WHERE name=?',
      ['garden_record_revision:$id'],
    );
    if (rows.isEmpty) {
      return null;
    }
    final value = int.tryParse(rows.single['value'] as String);
    if (value == null || value < 0) {
      throw const FormatException('Invalid garden revision floor');
    }
    return value;
  }

  Future<void> _saveFloor(String id, int revision) => database.execute(
    'INSERT INTO local_meta(name,value) VALUES(?,?) ON CONFLICT(name) DO UPDATE SET value=excluded.value',
    ['garden_record_revision:$id', revision.toString()],
  );
}
