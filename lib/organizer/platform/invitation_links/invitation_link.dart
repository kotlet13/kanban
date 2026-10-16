/// Invitation preparation only. A link carries a one-use invitation, never a
/// device session. Parsing performs no login, preview request or acceptance.
class InvitationLink {
  const InvitationLink({required this.serverUrl, required this.token});
  final String serverUrl, token;
  // The working-name scheme remains valid for previously shared invitations.
  static const supportedSchemes = {'jivie', 'vsakdan'};
  static InvitationLink? tryParse(Uri uri) {
    try {
      return _parse(uri);
    } on FormatException {
      return null;
    }
  }

  /// Accept the original HTTPS email link, an app link, or a bare capability
  /// paired with an explicitly selected server. No input triggers network work.
  static InvitationLink? tryParseInput(String input, {String? serverUrl}) {
    final value = input.trim();
    if (RegExp(r'^fhi[123]_[a-f0-9]{64}$').hasMatch(value)) {
      if (serverUrl == null) return null;
      return tryParse(
        InvitationLink(serverUrl: serverUrl, token: value).toUri(),
      );
    }
    final uri = Uri.tryParse(value);
    return uri == null ? null : tryParse(uri);
  }

  static InvitationLink? _parse(Uri uri) {
    if (uri.scheme == 'https') return _parseEmailLink(uri);
    if (uri.toString().length > 4096 ||
        !supportedSchemes.contains(uri.scheme) ||
        uri.host != 'invite' ||
        !{'', '/'}.contains(uri.path) ||
        uri.userInfo.isNotEmpty ||
        uri.hasPort ||
        uri.fragment.isNotEmpty ||
        !{2, 3}.contains(uri.queryParametersAll.length) ||
        (uri.queryParametersAll.length == 3 &&
            !{'2', '3'}.contains(uri.queryParameters['v'])) ||
        !uri.queryParametersAll.keys.toSet().containsAll({'server', 'token'}) ||
        uri.queryParametersAll.values.any((values) => values.length != 1)) {
      return null;
    }
    final token = uri.queryParameters['token']!,
        server = uri.queryParameters['server']!;
    if (!RegExp(r'^fhi[123]_[a-f0-9]{64}$').hasMatch(token) ||
        (token.startsWith('fhi1_')
            ? uri.queryParameters.containsKey('v')
            : uri.queryParameters['v'] != token.substring(3, 4)) ||
        server.length > 2048) {
      return null;
    }
    // Uri parsing normalizes encoded dot segments, so reject them before
    // normalization can erase evidence of traversal in the supplied origin.
    final rawPath = RegExp(
      r'^https://[^/?#]+([^?#]*)',
    ).firstMatch(server)?.group(1);
    if (rawPath == null ||
        rawPath.split('/').any((part) {
          final decoded = Uri.decodeComponent(part);
          return decoded == '.' ||
              decoded == '..' ||
              decoded.contains('/') ||
              decoded.contains('\\');
        })) {
      return null;
    }
    final base = Uri.tryParse(server);
    if (base == null ||
        base.scheme != 'https' ||
        base.host.isEmpty ||
        base.userInfo.isNotEmpty ||
        base.hasQuery ||
        base.hasFragment ||
        base.path.contains('\\') ||
        base.pathSegments.any(
          (part) =>
              part == '.' ||
              part == '..' ||
              part.contains('/') ||
              part.contains('\\'),
        ) ||
        base.host.contains(RegExp(r'\s')) ||
        (base.hasPort && (base.port < 1 || base.port > 65535))) {
      return null;
    }
    return InvitationLink(serverUrl: base.toString(), token: token);
  }

  static InvitationLink? _parseEmailLink(Uri uri) {
    // The server-generated link keeps the capability in its fragment, never in
    // the query. Only this exact FamilyHub route is an invitation entry point.
    final query = uri.queryParametersAll;
    if (uri.toString().length > 4096 ||
        uri.userInfo.isNotEmpty ||
        !uri.path.endsWith('/index.php') ||
        !{3, 4}.contains(query.length) ||
        query.keys.any(
          (key) =>
              !{'controller', 'action', 'plugin', 'language'}.contains(key),
        ) ||
        query.values.any((values) => values.length != 1) ||
        uri.queryParameters['controller'] != 'InvitationController' ||
        uri.queryParameters['action'] != 'show' ||
        uri.queryParameters['plugin'] != 'FamilyHub' ||
        (query.containsKey('language') &&
            !{'sl', 'en'}.contains(uri.queryParameters['language']))) {
      return null;
    }
    final fragment = Uri.splitQueryString(uri.fragment);
    if (fragment.length != 1 ||
        !fragment.containsKey('token') ||
        !RegExp(r'^token=fhi[23]_[a-f0-9]{64}$').hasMatch(uri.fragment)) {
      return null;
    }
    final server = Uri(
      scheme: 'https',
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: uri.path.substring(0, uri.path.length - '/index.php'.length),
    ).toString();
    final token = fragment['token']!;
    // Reuse the same strict HTTPS origin/path validation as native links.
    return _parse(InvitationLink(serverUrl: server, token: token).toUri());
  }

  Uri toUri() => Uri(
    scheme: 'jivie',
    host: 'invite',
    queryParameters: {
      'server': serverUrl,
      'token': token,
      if (!token.startsWith('fhi1_')) 'v': token.substring(3, 4),
    },
  );
}
