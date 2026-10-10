/// Reviewed readers gaining access when an existing organization opts in.
class OrganizationAccessReader {
  const OrganizationAccessReader({
    required this.accountId,
    required this.displayName,
    required this.accessSource,
  });
  final String accountId, displayName, accessSource;
  factory OrganizationAccessReader.fromJson(Map<String, dynamic> json) =>
      OrganizationAccessReader(
        accountId: _string(json, 'accountId'),
        displayName: _string(json, 'displayName'),
        accessSource: _string(json, 'accessSource'),
      );
}

class OrganizationAccessProject {
  OrganizationAccessProject({
    required this.scopeId,
    required this.name,
    required this.financeWasEnabled,
    required Iterable<OrganizationAccessReader> additionalReaders,
    Iterable<OrganizationAccessReader> additionalWriters = const [],
  }) : additionalReaders = List.unmodifiable(additionalReaders),
       additionalWriters = List.unmodifiable(additionalWriters);
  final String scopeId, name;
  final bool financeWasEnabled;
  final List<OrganizationAccessReader> additionalReaders, additionalWriters;
  factory OrganizationAccessProject.fromJson(Map<String, dynamic> json) =>
      OrganizationAccessProject(
        scopeId: _string(json, 'scopeId'),
        name: _string(json, 'name'),
        financeWasEnabled: json['financeWasEnabled'] == true,
        additionalWriters: (json['additionalWriters'] as List? ?? const []).map(
          (value) => OrganizationAccessReader.fromJson(_map(value)),
        ),
        additionalReaders: _list(
          json,
          'additionalReaders',
        ).map((value) => OrganizationAccessReader.fromJson(_map(value))),
      );
}

class OrganizationAccessPreview {
  OrganizationAccessPreview({
    required this.scopeId,
    required this.fromVersion,
    required this.toVersion,
    required Iterable<OrganizationAccessProject> projects,
    required this.previewHash,
    this.pendingInvitationsRevoked = 0,
    this.canApply = true,
    Iterable<Map<String, dynamic>> blockers = const [],
    Iterable<String> revokedInvitationIds = const [],
  }) : projects = List.unmodifiable(projects),
       revokedInvitationIds = List.unmodifiable(revokedInvitationIds),
       blockers = List.unmodifiable(blockers);
  final String scopeId, previewHash;
  final int fromVersion, toVersion, pendingInvitationsRevoked;
  final List<OrganizationAccessProject> projects;
  final List<String> revokedInvitationIds;
  final bool canApply;
  final List<Map<String, dynamic>> blockers;
  factory OrganizationAccessPreview.fromJson(Map<String, dynamic> json) {
    final from = json['fromVersion'], to = json['toVersion'];
    final hash = _string(json, 'previewHash');
    if (from is! int ||
        !const [1, 2, 3].contains(from) ||
        !const [2, 3].contains(to) ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(hash)) {
      throw const FormatException('Invalid organization access preview');
    }
    return OrganizationAccessPreview(
      scopeId: _string(json, 'scopeId'),
      fromVersion: from,
      toVersion: to as int,
      projects: _list(
        json,
        'projects',
      ).map((value) => OrganizationAccessProject.fromJson(_map(value))),
      previewHash: hash,
      canApply: json['canApply'] != false,
      blockers: (json['blockers'] as List? ?? const []).map(
        (value) => Map<String, dynamic>.unmodifiable(value as Map),
      ),
      pendingInvitationsRevoked:
          json['pendingInvitationsRevoked'] as int? ??
          (json['revokedInvitationIds'] as List? ?? const []).length,
      revokedInvitationIds: (json['revokedInvitationIds'] as List? ?? const [])
          .cast<String>(),
    );
  }
}

String _string(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw const FormatException('Invalid organization access field');
  }
  return value;
}

List<dynamic> _list(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! List) {
    throw const FormatException('Invalid organization access list');
  }
  return value;
}

Map<String, dynamic> _map(Object? value) {
  if (value is! Map<String, dynamic>) {
    throw const FormatException('Invalid organization access object');
  }
  return value;
}

/// The same reviewed transition also covers household spaces.
typedef SpaceAccessPreview = OrganizationAccessPreview;
