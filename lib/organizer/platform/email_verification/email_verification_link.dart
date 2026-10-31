import '../../data/collaboration_transport.dart'
    show normalizeCollaborationServer;
import '../../domain/collaboration_models.dart' show AccountSession;
import '../invitation_links/invitation_link.dart';

/// A verification capability, never an invitation or a device session.
class EmailVerificationLink {
  const EmailVerificationLink({
    required this.serverUrl,
    required this.serverId,
    required this.accountId,
    required this.email,
    required this.token,
  });
  final String serverUrl, serverId, accountId, email, token;

  bool matches(AccountSession session) =>
      normalizeCollaborationServer(serverUrl) ==
          normalizeCollaborationServer(session.serverUrl) &&
      serverId == session.serverId &&
      accountId == session.accountId;

  Uri toUri() => Uri(
    scheme: 'jivie',
    host: 'verify-email',
    queryParameters: {
      'server': serverUrl,
      'serverId': serverId,
      'accountId': accountId,
      'email': email,
      'token': token,
    },
  );

  static EmailVerificationLink? tryParse(Uri uri) {
    try {
      if (uri.toString().length > 4096) return null;
      Map<String, List<String>> params;
      String? server;
      if (uri.scheme == 'https') {
        final q = uri.queryParametersAll;
        if (!uri.path.endsWith('/index.php') ||
            uri.userInfo.isNotEmpty ||
            !{3, 4}.contains(q.length) ||
            q.keys.any(
              (k) =>
                  !{'controller', 'action', 'plugin', 'language'}.contains(k),
            ) ||
            q.values.any((v) => v.length != 1) ||
            uri.queryParameters['controller'] !=
                'EmailVerificationController' ||
            uri.queryParameters['action'] != 'show' ||
            uri.queryParameters['plugin'] != 'FamilyHub' ||
            (q.containsKey('language') &&
                !{'sl', 'en'}.contains(uri.queryParameters['language']))) {
          return null;
        }
        params = Uri(query: uri.fragment).queryParametersAll;
        server = Uri(
          scheme: 'https',
          host: uri.host,
          port: uri.hasPort ? uri.port : null,
          path: uri.path.substring(0, uri.path.length - '/index.php'.length),
        ).toString();
        if (params.length != 4) return null;
      } else {
        if (!InvitationLink.supportedSchemes.contains(uri.scheme) ||
            uri.host != 'verify-email' ||
            !{'', '/'}.contains(uri.path) ||
            uri.userInfo.isNotEmpty ||
            uri.hasPort ||
            uri.hasFragment) {
          return null;
        }
        params = uri.queryParametersAll;
        if (params.length != 5) return null;
        server = uri.queryParameters['server'];
      }
      if (params.values.any((v) => v.length != 1) ||
          params.keys.any(
            (k) => !{
              'server',
              'serverId',
              'accountId',
              'email',
              'token',
            }.contains(k),
          )) {
        return null;
      }
      final id = RegExp(
        r'^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$',
      );
      final serverId = params['serverId']?.single,
          accountId = params['accountId']?.single;
      final token = params['token']?.single, email = params['email']?.single;
      if (server == null ||
          serverId == null ||
          accountId == null ||
          token == null ||
          email == null ||
          !id.hasMatch(serverId) ||
          !id.hasMatch(accountId) ||
          !RegExp(r'^fhv1_[a-f0-9]{64}$').hasMatch(token) ||
          email.length > 254 ||
          email.codeUnits.any((unit) => unit < 33 || unit > 126) ||
          !RegExp(r'^[\x21-\x7e]+@[^@]+$').hasMatch(email)) {
        return null;
      }
      // Reuse the established strict HTTPS path/origin validator. Its synthetic
      // invitation is parsed locally and never stored or dispatched.
      if (InvitationLink.tryParse(
            InvitationLink(
              serverUrl: server,
              token: 'fhi1_${'0' * 64}',
            ).toUri(),
          ) ==
          null) {
        return null;
      }
      return EmailVerificationLink(
        serverUrl: server,
        serverId: serverId,
        accountId: accountId,
        email: email,
        token: token,
      );
    } on FormatException {
      return null;
    }
  }
}
