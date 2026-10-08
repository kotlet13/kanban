part of 'collaboration_repository.dart';

extension CollaborationPersonActions on CollaborationRepository {
  Future<String> createPerson({
    required String scopeId,
    required String name,
    String notes = '',
  }) async {
    if (!_householdPeopleSupported) {
      throw const CollaborationException('client_upgrade_required');
    }
    final id = newSharedId(), now = clock().toUtc();
    final person = HouseholdPerson(
      id: id,
      name: name.trim(),
      notes: notes,
      createdAt: now,
      updatedAt: now,
    );
    person.validate();
    await _edit(
      scopeId,
      (partition) => _put(
        partition,
        scopeId,
        SharedRecordType.householdPerson,
        id,
        _payload(person.toJson()),
      ),
    );
    return id;
  }

  Future<void> updatePerson(String scopeId, HouseholdPerson person) async {
    if (!_householdPeopleSupported) {
      throw const CollaborationException('client_upgrade_required');
    }
    person.validate();
    await _edit(scopeId, (partition) async {
      final current = await _record(partition, scopeId, person.id);
      if (current['type'] != 'householdPerson' ||
          current['local_revision'] != person.revision) {
        throw const CollaborationException('local_conflict');
      }
      final updated = person.copyWith(
        updatedAt: clock().toUtc().isBefore(person.updatedAt)
            ? person.updatedAt
            : clock().toUtc(),
      );
      await _put(
        partition,
        scopeId,
        SharedRecordType.householdPerson,
        person.id,
        _payload(updated.toJson()),
        expectedLocalRevision: person.revision,
      );
    });
  }

  Future<void> archivePerson(
    String scopeId,
    HouseholdPerson person, {
    bool archived = true,
  }) => updatePerson(scopeId, person.copyWith(archived: archived));
}
