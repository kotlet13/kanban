part of 'organizer_repository.dart';

extension OrganizerPersonActions on OrganizerRepository {
  Future<void> createPerson({
    required String name,
    String notes = '',
    String? expectedWorkspaceKey,
  }) => _change((s) {
    if (expectedWorkspaceKey != null &&
        expectedWorkspaceKey != s.workspaceKey) {
      throw const OrganizerConflictException('Workspace changed');
    }
    final now = _now();
    return s.copyWith(
      people: [
        ...s.people,
        HouseholdPerson(
          id: _idGenerator(),
          name: name.trim(),
          notes: notes,
          createdAt: now,
          updatedAt: now,
        ),
      ],
    );
  });
  Future<void> updatePerson(
    HouseholdPerson person, {
    String? expectedWorkspaceKey,
  }) => _change((s) {
    if (expectedWorkspaceKey != null &&
        expectedWorkspaceKey != s.workspaceKey) {
      throw const OrganizerConflictException('Workspace changed');
    }
    final current = _find(s.people, person.id, (p) => p.id);
    if (current.revision != person.revision ||
        current.createdAt != person.createdAt) {
      throw const OrganizerConflictException(
        'This person changed; reload before editing',
      );
    }
    final updated = person.copyWith(
      revision: current.revision + 1,
      updatedAt: _updatedAt(current.updatedAt),
    );
    return s.copyWith(
      people: s.people.map((p) => p.id == person.id ? updated : p),
    );
  });
  Future<void> archivePerson(
    HouseholdPerson person, {
    bool archived = true,
    String? expectedWorkspaceKey,
  }) => updatePerson(
    person.copyWith(archived: archived),
    expectedWorkspaceKey: expectedWorkspaceKey,
  );
}
