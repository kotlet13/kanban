/// Untrusted change hints select work; existing domain verifiers remain authority.
class CollaborationAccountChanges {
  CollaborationAccountChanges._({
    required this.cursor,
    required this.reset,
    required this.accountDomains,
    required this.scopes,
    required this.directoryHintsVersion,
    required this.notificationConfigurationChanged,
  });
  final String cursor;
  final bool reset;
  final Set<String> accountDomains;
  final Map<String, Set<String>> scopes;
  final int? directoryHintsVersion;
  final bool? notificationConfigurationChanged;
  // Older/unknown servers retain the broad inbox fallback. Access changes may
  // introduce new scopes, so they still require configuration even with no bump.
  bool get notificationConfiguration =>
      reset || access || (notificationConfigurationChanged ?? inbox);
  bool get semanticDirectoryHint =>
      directoryHintsVersion == 1 && accountDomains.contains('directory');
  bool get requiresSync =>
      reset ||
      scopes.isNotEmpty ||
      accountDomains.any(
        (domain) => domain != 'directory' || directoryHintsVersion != 1,
      );
  bool get changed => reset || accountDomains.isNotEmpty || scopes.isNotEmpty;
  bool get access =>
      reset ||
      accountDomains.any(const {'access', 'metadata'}.contains) ||
      (directoryHintsVersion != 1 && accountDomains.contains('directory')) ||
      scopes.values.any((d) => d.contains('access'));
  bool get inbox =>
      reset || accountDomains.any(const {'inbox', 'invitations'}.contains);
  bool content(String scope) =>
      reset ||
      scopes[scope]?.any(const {'content', 'documents', 'access'}.contains) ==
          true;
  bool finance(String scope) =>
      reset || scopes[scope]?.any(const {'finance', 'access'}.contains) == true;
  void include(String scope, String domain) =>
      (scopes[scope] ??= {}).add(domain);

  factory CollaborationAccountChanges.parse(
    Map<String, dynamic> value, {
    required String serverId,
    required String accountId,
    required String deviceId,
  }) {
    const accountAllowed = {
      'access',
      'directory',
      'inbox',
      'invitations',
      'metadata',
    };
    const scopeAllowed = {'access', 'content', 'finance', 'documents'};
    Set<String> domains(Object? raw, Set<String> allowed) {
      if (raw is! List ||
          raw.any((d) => d is! String || !allowed.contains(d))) {
        throw const FormatException('account_change_domains');
      }
      return raw.cast<String>().toSet();
    }

    if (value['version'] != 1 ||
        value['serverId'] != serverId ||
        value['accountId'] != accountId ||
        value['deviceId'] != deviceId ||
        value['cursor'] is! String ||
        (value['cursor'] as String).isEmpty ||
        (value['cursor'] as String).length > 1048576 ||
        value['changed'] is! bool ||
        value['resetRequired'] is! bool ||
        value['hasMore'] != false ||
        value['scopes'] is! List) {
      throw const FormatException('account_change_binding');
    }
    final scopes = <String, Set<String>>{};
    for (final row in value['scopes'] as List) {
      if (row is! Map ||
          row['scopeId'] is! String ||
          scopes.containsKey(row['scopeId'])) {
        throw const FormatException('account_change_scope');
      }
      scopes[row['scopeId'] as String] = domains(row['domains'], scopeAllowed);
    }
    if (value['notificationHintsVersion'] == 1 &&
        value['notificationConfigurationChanged'] is! bool) {
      throw const FormatException('account_notification_change_hint');
    }
    final result = CollaborationAccountChanges._(
      notificationConfigurationChanged: value['notificationHintsVersion'] == 1
          ? value['notificationConfigurationChanged'] as bool
          : null,
      cursor: value['cursor'] as String,
      reset: value['resetRequired'] as bool,
      accountDomains: domains(value['accountDomains'], accountAllowed),
      scopes: scopes,
      directoryHintsVersion: value['directoryHintsVersion'] is int
          ? value['directoryHintsVersion'] as int
          : null,
    );
    if (value['changed'] != result.changed) {
      throw const FormatException('account_change_consistency');
    }
    return result;
  }
}
