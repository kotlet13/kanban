part of 'collaboration_repository.dart';

extension CollaborationEventActions on CollaborationRepository {
  Future<String> createEvent({
    required String scopeId,
    required String title,
    String notes = '',
    required DateTime startAt,
    DateTime? endAt,
    String? projectId,
    Iterable<String> assigneeAccountIds = const [],
  }) async {
    if (_recordContractVersion < 2) {
      throw const CollaborationException('client_upgrade_required');
    }
    final id = newSharedId(), now = clock().toUtc();
    final event = SharedEvent(
      id: id,
      title: title.trim(),
      notes: notes,
      startAt: startAt.toUtc(),
      endAt: endAt?.toUtc(),
      projectId: projectId,
      assigneeAccountIds: assigneeAccountIds,
      createdAt: now,
      updatedAt: now,
    );
    await _edit(
      scopeId,
      (p) => _put(
        p,
        scopeId,
        SharedRecordType.event,
        id,
        _payload(event.toJson()),
      ),
    );
    return id;
  }

  Future<void> updateEvent(String scopeId, SharedEvent draft) => _edit(
    scopeId,
    (p) => _put(
      p,
      scopeId,
      SharedRecordType.event,
      draft.id,
      _payload(draft.copyWith(updatedAt: clock().toUtc()).toJson()),
      expectedLocalRevision: draft.revision,
    ),
  );
  Future<void> deleteEvent(String scopeId, String id) => _edit(
    scopeId,
    (p) => _put(p, scopeId, SharedRecordType.event, id, null, deleted: true),
  );
}
