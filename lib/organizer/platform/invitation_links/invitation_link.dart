/// Custom-scheme preparation only. A link carries a one-use invitation, never a
/// device session. Parsing performs no login, preview request or acceptance.
class InvitationLink {
  const InvitationLink({required this.serverUrl, required this.token});
  final String serverUrl, token;
  static InvitationLink? tryParse(Uri uri) {
    try {
      return _parse(uri);
    } on FormatException {
      return null;
    }
  }

  static InvitationLink? _parse(Uri uri) {
    if (uri.toString().length > 4096 ||
        uri.scheme != 'vsakdan' ||
        uri.host != 'invite' ||
        !{'', '/'}.contains(uri.path) ||
        uri.userInfo.isNotEmpty ||
        uri.hasPort ||
        uri.fragment.isNotEmpty ||
        uri.queryParametersAll.length != 2 ||
        !uri.queryParametersAll.keys.toSet().containsAll({'server', 'token'}) ||
        uri.queryParametersAll.values.any((values) => values.length != 1)) {
      return null;
    }
    final token = uri.queryParameters['token']!,
        server = uri.queryParameters['server']!;
    if (!RegExp(r'^fhi1_[a-f0-9]{64}$').hasMatch(token) || server.length > 2048) {
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

  Uri toUri() => Uri(
    scheme: 'vsakdan',
    host: 'invite',
    queryParameters: {'server': serverUrl, 'token': token},
  );
}
