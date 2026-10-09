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
  }) : additionalReaders = List.unmodifiable(additionalReaders);
  final String scopeId, name;
  final bool financeWasEnabled;
  final List<OrganizationAccessReader> additionalReaders;
  factory OrganizationAccessProject.fromJson(Map<String, dynamic> json) =>
      OrganizationAccessProject(
        scopeId: _string(json, 'scopeId'),
        name: _string(json, 'name'),
        financeWasEnabled: json['financeWasEnabled'] == true,
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
  }) : projects = List.unmodifiable(projects);
  final String scopeId, previewHash;
  final int fromVersion, toVersion;
  final List<OrganizationAccessProject> projects;
  factory OrganizationAccessPreview.fromJson(Map<String, dynamic> json) {
    final from = json['fromVersion'], to = json['toVersion'];
    final hash = _string(json, 'previewHash');
    if (from is! int ||
        !const [1, 2].contains(from) ||
        to != 2 ||
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
