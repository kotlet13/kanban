import 'organizer_models.dart';

enum LocalSpaceKind { personal, household, organization }

/// A device-owned space has its own durable identity before any server exists.
/// A server link never changes this identity or follows a name match.
class LocalSpace {
  const LocalSpace({
    required this.id,
    required this.kind,
    required this.name,
    this.address = '',
    this.binding,
    this.financeRecoveryIncomplete = false,
  });
  final String id, name, address;
  final LocalSpaceKind kind;
  final LocalSpaceBinding? binding;
  final bool financeRecoveryIncomplete;
  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind.name,
    'name': name,
    'address': address,
    if (binding != null) 'binding': binding!.toJson(),
    if (financeRecoveryIncomplete) 'financeRecoveryIncomplete': true,
  };
  factory LocalSpace.fromJson(Map<String, dynamic> json) {
    final space = LocalSpace(
      id: json['id'] as String,
      kind: LocalSpaceKind.values.byName(json['kind'] as String),
      name: json['name'] as String,
      address: json['address'] as String? ?? '',
      binding: json['binding'] == null
          ? null
          : LocalSpaceBinding.fromJson(json['binding'] as Map<String, dynamic>),
      financeRecoveryIncomplete:
          json['financeRecoveryIncomplete'] as bool? ?? false,
    );
    space.validate();
    return space;
  }
  void validate() {
    if (id.isEmpty ||
        id.length > 200 ||
        name.length > 200 ||
        address.length > 1000 ||
        (id != 'local' && name.trim().isEmpty) ||
        (id == 'local' && kind != LocalSpaceKind.personal)) {
      throw const FormatException('Invalid local space');
    }
  }
}

class LocalSpacesState {
  LocalSpacesState({
    Iterable<LocalSpace> spaces = const [],
    this.selectedSpaceId = 'local',
    Map<String, OrganizerSnapshot> snapshots = const {},
  }) : spaces = List.unmodifiable(spaces),
       snapshots = Map.unmodifiable(snapshots);
  final List<LocalSpace> spaces;
  final String selectedSpaceId;
  final Map<String, OrganizerSnapshot> snapshots;
  LocalSpace? get selectedSpace =>
      spaces.where((s) => s.id == selectedSpaceId).firstOrNull;
}

class LocalSpaceBinding {
  const LocalSpaceBinding({required this.partition, required this.scopeId});
  final String partition, scopeId;
  Map<String, Object?> toJson() => {'partition': partition, 'scopeId': scopeId};
  factory LocalSpaceBinding.fromJson(Map<String, dynamic> json) =>
      LocalSpaceBinding(
        partition: json['partition'] as String,
        scopeId: json['scopeId'] as String,
      );
}

class LocalSpacePublicationItem {
  const LocalSpacePublicationItem({
    required this.space,
    required this.recordCount,
    required this.gardenCount,
    this.projects = const [],
    this.linkedPaymentCount = 0,
  });
  final LocalSpace space;
  final int recordCount, gardenCount;
  final int linkedPaymentCount;
  final List<LocalProjectPublicationDestination> projects;
}

class LocalSpacesPublicationPreview {
  LocalSpacesPublicationPreview({
    required this.partition,
    required this.serverUrl,
    required this.accountName,
    required this.fingerprint,
    required Iterable<LocalSpacePublicationItem> spaces,
    Iterable<String> issues = const [],
  }) : spaces = List.unmodifiable(spaces),
       issues = List.unmodifiable(issues);
  final String partition, serverUrl, accountName, fingerprint;
  final List<LocalSpacePublicationItem> spaces;
  final List<String> issues;
  bool get canPublish => issues.isEmpty && spaces.isNotEmpty;
}

class LocalProjectPublicationDestination {
  const LocalProjectPublicationDestination({
    required this.id,
    required this.name,
    required this.taskCount,
    required this.financeCount,
    required this.personCount,
    required this.accountCount,
  });
  final String id, name;
  final int taskCount, financeCount, personCount, accountCount;
}
