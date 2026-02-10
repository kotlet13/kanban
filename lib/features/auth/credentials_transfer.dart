import 'dart:convert';

import '../../models/kanboard_models.dart';

const String _transferScheme = 'kanban';
const String _transferHost = 'credentials';
const int _transferVersion = 1;

String buildCredentialsTransferPayload(KanboardCredentials credentials) {
  final payload = <String, dynamic>{
    'v': _transferVersion,
    'url': credentials.serverUrl,
    'u': credentials.username,
    't': credentials.token,
    'iat': DateTime.now().toUtc().millisecondsSinceEpoch,
  };

  final encoded = base64UrlEncode(utf8.encode(jsonEncode(payload)));
  return '$_transferScheme://$_transferHost?d=$encoded';
}

KanboardCredentials parseCredentialsTransferPayload(String rawValue) {
  final trimmed = rawValue.trim();
  if (trimmed.isEmpty) {
    throw const FormatException('Payload is empty.');
  }

  Map<String, dynamic> payload;
  if (trimmed.startsWith('{')) {
    payload = jsonDecode(trimmed) as Map<String, dynamic>;
  } else {
    final uri = Uri.tryParse(trimmed);
    String encoded;
    if (uri != null &&
        uri.scheme == _transferScheme &&
        uri.host == _transferHost) {
      encoded = uri.queryParameters['d'] ?? '';
    } else {
      encoded = trimmed;
    }

    if (encoded.isEmpty) {
      throw const FormatException('Missing transfer payload.');
    }

    final normalized = base64Url.normalize(encoded);
    payload =
        jsonDecode(utf8.decode(base64Url.decode(normalized)))
            as Map<String, dynamic>;
  }

  final version = payload['v'];
  if (version != _transferVersion) {
    throw const FormatException('Unsupported payload version.');
  }

  final serverUrl = payload['url']?.toString().trim() ?? '';
  final username = payload['u']?.toString().trim() ?? '';
  final token = payload['t']?.toString().trim() ?? '';

  if (serverUrl.isEmpty || username.isEmpty || token.isEmpty) {
    throw const FormatException('Transfer payload is incomplete.');
  }

  return KanboardCredentials(
    serverUrl: serverUrl,
    username: username,
    token: token,
  );
}
