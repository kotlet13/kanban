import 'organizer_models.dart' show readString, readInt, readDate, readBool;

/// A profile describes a person; it never implies a login, membership or access.
class HouseholdPerson {
  const HouseholdPerson({
    required this.id,
    required this.name,
    this.notes = '',
    this.archived = false,
    this.revision = 0,
    required this.createdAt,
    required this.updatedAt,
  });
  final String id, name, notes;
  final bool archived;
  final int revision;
  final DateTime createdAt, updatedAt;
  HouseholdPerson copyWith({
    String? name,
    String? notes,
    bool? archived,
    int? revision,
    DateTime? updatedAt,
  }) => HouseholdPerson(
    id: id,
    name: name ?? this.name,
    notes: notes ?? this.notes,
    archived: archived ?? this.archived,
    revision: revision ?? this.revision,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'notes': notes,
    'archived': archived,
    'revision': revision,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };
  factory HouseholdPerson.fromJson(Map<String, dynamic> json) =>
      HouseholdPerson(
        id: readString(json, 'id'),
        name: readString(json, 'name'),
        notes: readString(json, 'notes'),
        archived: readBool(json, 'archived'),
        revision: readInt(json, 'revision'),
        createdAt: readDate(json, 'createdAt'),
        updatedAt: readDate(json, 'updatedAt'),
      );
  void validate() => validateHouseholdPerson(this);
}

void validateHouseholdPerson(HouseholdPerson person) {
  if (person.id.isEmpty ||
      person.name.trim().isEmpty ||
      person.name.length > 500 ||
      person.notes.length > 50000 ||
      person.name.contains('\u0000') ||
      person.notes.contains('\u0000') ||
      person.revision < 0 ||
      person.updatedAt.isBefore(person.createdAt)) {
    throw const FormatException('Invalid person profile');
  }
}
