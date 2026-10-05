import 'dart:convert';

import '../models/kanboard_models.dart';

/// Stable account namespace; never contains the password or API token.
String accountScopeKey(KanboardCredentials credentials) {
  final uri = Uri.parse(credentials.normalizedEndpoint).normalizePath();
  final scheme = uri.scheme.toLowerCase();
  final defaultPort = scheme == 'https' ? 443 : 80;
  final normalized = Uri(
    scheme: scheme,
    host: uri.host.toLowerCase(),
    port: uri.hasPort && uri.port != defaultPort ? uri.port : null,
    path: uri.path,
    query: uri.hasQuery ? uri.query : null,
  );
  return base64UrlEncode(
    utf8.encode(
      jsonEncode([normalized.toString(), credentials.username.trim()]),
    ),
  );
}
