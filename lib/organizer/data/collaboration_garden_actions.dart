part of 'collaboration_repository.dart';

extension CollaborationGardenActions on CollaborationRepository {
  Future<void> saveGarden(
    String scopeId,
    Garden garden, {
    bool isNew = false,
  }) => _edit(scopeId, (partition) async {
    garden.validate();
    await _put(
      partition,
      scopeId,
      SharedRecordType.garden,
      garden.id,
      garden.toJson(),
      expectedLocalRevision: isNew ? null : garden.revision,
    );
  });
  Future<void> deleteGarden(String scopeId, Garden garden) => _edit(
    scopeId,
    (partition) => _put(
      partition,
      scopeId,
      SharedRecordType.garden,
      garden.id,
      null,
      deleted: true,
      expectedLocalRevision: garden.revision,
    ),
  );
}

/// The same garden editors operate on the captured household's durable rows.
/// Credentials are used only for later transport, never for opening this copy.
class SharedGardenStorage extends GardenStorage {
  SharedGardenStorage(this.repository, this.partition, this.scopeId)
    : super(repository.database);
  final CollaborationRepository repository;
  final String partition, scopeId;
  @override
  String get workspaceKey => 'shared:$partition:$scopeId';
  @override
  int get identityGeneration => repository._epoch;
  @override
  Stream<void> get changes => repository.changes.map<void>((_) {});
  void _identity() {
    if (repository._session?.profile.partition != partition ||
        !repository.state.localAccessAllowed) {
      throw const CollaborationException('session_changed');
    }
    final scope = repository.state.scopes
        .where((s) => s.id == scopeId)
        .firstOrNull;
    if (scope == null ||
        scope.revoked ||
        scope.kind != SharedScopeKind.household) {
      throw const CollaborationException('permission_revoked');
    }
  }

  @override
  Future<GardenSnapshot> read() async {
    _identity();
    final epoch = repository._epoch;
    final data = await repository._scopeData(partition, scopeId);
    final revision =
        (await database.rows(
              "SELECT COALESCE(SUM(local_revision),0) AS revision FROM records WHERE partition=? AND scope_id=? AND type='garden'",
              [partition, scopeId],
            )).single['revision']
            as int;
    repository._checkEpoch(epoch);
    _identity();
    return GardenSnapshot(
      revision: revision,
      workspaceKey: workspaceKey,
      gardens: data.gardens,
    );
  }

  @override
  Future<void> write(
    GardenSnapshot snapshot, {
    required int expectedRevision,
    bool allSpaces = false,
    String? expectedWorkspaceKey,
    int? expectedIdentityGeneration,
  }) async {
    _identity();
    if (allSpaces ||
        (expectedWorkspaceKey != null &&
            expectedWorkspaceKey != workspaceKey) ||
        (expectedIdentityGeneration != null &&
            expectedIdentityGeneration != identityGeneration)) {
      throw const OrganizerConflictException('Garden workspace changed');
    }
    snapshot.validate();
    await repository._edit(scopeId, (p) async {
      _identity();
      final previous = await read();
      if (previous.revision != expectedRevision) {
        throw const OrganizerConflictException('Garden changed; reload');
      }
      final old = {for (final garden in previous.gardens) garden.id: garden};
      final next = {for (final garden in snapshot.gardens) garden.id: garden};
      for (final garden in previous.gardens.where(
        (g) => !next.containsKey(g.id),
      )) {
        await repository._put(
          p,
          scopeId,
          SharedRecordType.garden,
          garden.id,
          null,
          deleted: true,
          expectedLocalRevision: garden.revision,
        );
      }
      for (final garden in snapshot.gardens) {
        if (old[garden.id] != null &&
            jsonEncode(old[garden.id]!.toJson()) ==
                jsonEncode(garden.toJson())) {
          continue;
        }
        await repository._put(
          p,
          scopeId,
          SharedRecordType.garden,
          garden.id,
          garden.toJson(),
          expectedLocalRevision: old[garden.id]?.revision,
        );
      }
    });
  }
}
