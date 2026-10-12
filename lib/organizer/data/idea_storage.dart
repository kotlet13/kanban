import 'dart:convert';
import '../domain/idea_models.dart';
import 'collaboration_database.dart';
import 'organizer_repository.dart' show OrganizerConflictException;

/// Device-local rows deliberately have no account partition or sync operation.
class IdeaStorage {
  IdeaStorage(this.database);
  final CollaborationDatabase database;
  String get workspaceKey => database.selectedLocalWorkspaceId;
  int get identityGeneration => database.personalIdentityGeneration;
  void checkAccess() {}
  Future<void> checkWritable() async {
    final profile = database.personalProfile;
    if (workspaceKey == 'local' &&
        profile != null &&
        (await database.rows(
          'SELECT id FROM personal_workspaces WHERE id=? AND partition=? AND enabled=1',
          ['private:${profile.partition}', profile.partition],
        )).isNotEmpty) {
      throw const OrganizerConflictException(
        'Use the private workspace to edit',
      );
    }
    final rows = await database.rows(
      'SELECT data FROM local_spaces WHERE id=?',
      [workspaceKey],
    );
    if (rows.isEmpty) {
      throw const OrganizerConflictException('Idea space no longer exists');
    }
    if ((jsonDecode(rows.single['data'] as String) as Map)['binding'] != null) {
      throw const OrganizerConflictException('Use the linked space to edit');
    }
  }

  Future<void> validateEditorBase(IdeaBoard base) async {
    final rows = await database.rows(
      'SELECT value FROM local_meta WHERE name=?',
      ['idea_deleted_revision:${base.id}'],
    );
    if (rows.isNotEmpty &&
        int.parse(rows.single['value'] as String) > base.revision) {
      throw const OrganizerConflictException(
        'Idea was deleted or restored; reload before editing',
      );
    }
  }

  Future<void> checkDurableAccess() async {
    checkAccess();
  }

  Stream<void> get changes => database.personalChanges.stream;
  Future<IdeaSnapshot> read() => database.transaction(() async {
    final all = await readAll();
    final space = database.selectedLocalWorkspaceId;
    final links = await database.rows(
      'SELECT idea_id,space_id FROM idea_space_links',
    );
    final ownership = {
      for (final link in links) link['idea_id']: link['space_id'],
    };
    return IdeaSnapshot(
      revision: all.revision,
      workspaceKey: workspaceKey,
      boards: all.boards.where(
        (g) => space == 'local'
            ? !ownership.containsKey(g.id)
            : ownership[g.id] == space,
      ),
    );
  });
  Future<IdeaSnapshot> readAll() => database.transaction(() async {
    final generation = await database.rows(
      "SELECT value FROM local_meta WHERE name='idea_generation'",
    );
    final rows = await database.rows(
      'SELECT id,payload FROM device_ideas ORDER BY id',
    );
    final snapshot = IdeaSnapshot(
      revision: generation.isEmpty
          ? 0
          : int.parse(generation.single['value'] as String),
      boards: rows.map((r) {
        final idea = IdeaBoard.fromJson(
          jsonDecode(r['payload'] as String) as Map<String, dynamic>,
        );
        if (idea.id != r['id']) {
          throw const FormatException('Idea row identity mismatch');
        }
        return idea;
      }),
    );
    snapshot.validate();
    return snapshot;
  });

  /// Caller may already own a larger restore transaction. No changes are sent
  /// remotely; personal generation guards existing backup confirmation screens.
  Future<void> write(
    IdeaSnapshot snapshot, {
    required int expectedRevision,
    bool allSpaces = false,
    String? expectedWorkspaceKey,
    int? expectedIdentityGeneration,
  }) => database.transaction(() async {
    snapshot.validate();
    if (!allSpaces) await checkWritable();
    if ((expectedWorkspaceKey != null &&
            expectedWorkspaceKey != database.selectedLocalWorkspaceId) ||
        (expectedIdentityGeneration != null &&
            expectedIdentityGeneration !=
                database.personalIdentityGeneration)) {
      throw const OrganizerConflictException('Idea workspace changed');
    }
    final previous = allSpaces ? await readAll() : await read();
    final identity = database.personalIdentityGeneration;
    final space = database.selectedLocalWorkspaceId;
    if (previous.revision != expectedRevision) {
      throw const OrganizerConflictException(
        'Idea changed; reload before writing',
      );
    }
    final old = {for (final idea in previous.boards) idea.id: idea};
    final next = {for (final idea in snapshot.boards) idea.id: idea};
    for (final idea in previous.boards) {
      if (!next.containsKey(idea.id)) {
        // Keep a non-content revision floor after deletion. Restoring the same
        // UUID must not make a previously open editor valid again (ABA).
        final floor = await _revisionFloor(idea.id);

        await _saveFloor(
          idea.id,
          floor != null && floor > idea.revision ? floor : idea.revision + 1,
        );
        await database.execute(
          'INSERT INTO local_meta(name,value) VALUES(?,?) ON CONFLICT(name) DO UPDATE SET value=excluded.value',
          ['idea_deleted_revision:${idea.id}', (idea.revision + 1).toString()],
        );
        await database.execute('DELETE FROM idea_space_links WHERE idea_id=?', [
          idea.id,
        ]);
        await database.execute('DELETE FROM device_ideas WHERE id=?', [
          idea.id,
        ]);
      }
    }
    for (final idea in snapshot.boards) {
      if (!allSpaces && idea.projectId != null) {
        final projects = await database.rows(
          allSpaces
              ? "SELECT id FROM personal_records WHERE type='project' AND id=?"
              : "SELECT id FROM personal_records WHERE type='project' AND id=? AND workspace=?",
          allSpaces ? [idea.projectId] : [idea.projectId, space],
        );
        if (projects.isEmpty) {
          throw const OrganizerConflictException(
            'Idea project belongs to another space',
          );
        }
      }

      final existing = old[idea.id];
      if (existing == null &&
          !allSpaces &&
          (await database.rows('SELECT id FROM device_ideas WHERE id=?', [
            idea.id,
          ])).isNotEmpty) {
        throw const OrganizerConflictException('Idea belongs to another space');
      }
      if (existing != null &&
          jsonEncode(existing.toJson()) == jsonEncode(idea.toJson())) {
        continue;
      }
      final floor = await _revisionFloor(idea.id);
      if (!allSpaces && existing == null && floor != null) {
        throw const OrganizerConflictException('Idea was deleted');
      }
      var minimum = existing == null ? 0 : existing.revision + 1;
      if (floor != null && floor + 1 > minimum) {
        minimum = floor + 1;
      }
      final committed = idea.copyWith(
        revision: idea.revision < minimum ? minimum : idea.revision,
      );
      await database.execute(
        'INSERT INTO device_ideas(id,payload) VALUES(?,?) ON CONFLICT(id) DO UPDATE SET payload=excluded.payload',
        [committed.id, jsonEncode(committed.toJson())],
      );
      await _saveFloor(committed.id, committed.revision);
      if (!allSpaces && existing == null && space != 'local') {
        await database.execute(
          'INSERT INTO idea_space_links(idea_id,space_id) VALUES(?,?)',
          [committed.id, space],
        );
      }
    }
    await database.execute(
      "INSERT INTO local_meta(name,value) VALUES('idea_generation',?) ON CONFLICT(name) DO UPDATE SET value=excluded.value",
      [(expectedRevision + 1).toString()],
    );
    if (identity != database.personalIdentityGeneration) {
      throw const OrganizerConflictException('Idea workspace changed');
    }
    await database.touchPersonal();
  });

  Future<void> ensureAssets(IdeaBoard board) async {}

  Future<int?> _revisionFloor(String id) async {
    final rows = await database.rows(
      'SELECT value FROM local_meta WHERE name=?',
      ['idea_record_revision:$id'],
    );
    if (rows.isEmpty) {
      return null;
    }
    final value = int.tryParse(rows.single['value'] as String);
    if (value == null || value < 0) {
      throw const FormatException('Invalid idea revision floor');
    }
    return value;
  }

  Future<void> _saveFloor(String id, int revision) => database.execute(
    'INSERT INTO local_meta(name,value) VALUES(?,?) ON CONFLICT(name) DO UPDATE SET value=excluded.value',
    ['idea_record_revision:$id', revision.toString()],
  );
}
