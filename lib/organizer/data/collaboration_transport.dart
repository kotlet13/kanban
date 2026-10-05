import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../domain/collaboration_models.dart';

class CollaborationApiException extends CollaborationException {
  const CollaborationApiException(super.code, {this.details = const {}});
  final Map<String, dynamic> details;
}

abstract interface class CollaborationTransport {
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  });
  void close();
}

String normalizeCollaborationServer(
  String value, {
  bool allowLocalHttp = false,
}) {
  final uri = Uri.tryParse(value.trim());
  final loopback =
      uri != null && ['127.0.0.1', 'localhost', '::1'].contains(uri.host);
  if (uri == null ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      (uri.scheme != 'https' &&
          !(allowLocalHttp && uri.scheme == 'http' && loopback))) {
    throw const CollaborationException('invalid_server_url');
  }
  final normalized = uri.normalizePath();
  final path = normalized.path.endsWith('/')
      ? normalized.path
      : '${normalized.path}/';
  return Uri(
    scheme: uri.scheme,
    host: uri.host.toLowerCase(),
    port: uri.hasPort && uri.port != (uri.scheme == 'https' ? 443 : 80)
        ? uri.port
        : null,
    path: path,
  ).toString();
}

class HttpCollaborationTransport implements CollaborationTransport {
  HttpCollaborationTransport({
    http.Client? client,
    this.requestTimeout = const Duration(seconds: 20),
  }) : _client = client ?? http.Client();
  final http.Client _client;
  final Duration requestTimeout;
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
    final base = normalizeCollaborationServer(
      serverUrl,
      allowLocalHttp: allowLocalHttp,
    );
    final endpoint = Uri.parse(base)
        .resolve('index.php')
        .replace(
          queryParameters: {
            'controller': 'NativeApiController',
            'action': 'handle',
            'plugin': 'FamilyHub',
          },
        );
    try {
      final request = http.Request('POST', endpoint)..followRedirects = false;
      request.headers['Content-Type'] = 'application/json';
      if (token != null) request.headers['Authorization'] = 'Bearer $token';
      request.body = jsonEncode({'v': 1, 'op': operation, 'params': params});
      final deadline = DateTime.now().add(requestTimeout);
      final streamed = await _client.send(request).timeout(requestTimeout);
      final bytes = <int>[];
      final iterator = StreamIterator(streamed.stream);
      try {
        while (true) {
          final remaining = deadline.difference(DateTime.now());
          if (remaining <= Duration.zero) {
            throw TimeoutException('Request deadline');
          }
          if (!await iterator.moveNext().timeout(remaining)) break;
          final chunk = iterator.current;
          if (bytes.length + chunk.length > 2 * 1024 * 1024) {
            throw const CollaborationException('invalid_response');
          }
          bytes.addAll(chunk);
        }
      } finally {
        await iterator.cancel();
      }
      if (streamed.statusCode >= 300 && streamed.statusCode < 400) {
        throw const CollaborationException('redirect_rejected');
      }
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map<String, dynamic> || decoded['v'] != 1) {
        throw const CollaborationException('incompatible_server');
      }
      if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
        final error = decoded['error'];
        if (error is! Map<String, dynamic> || error['code'] is! String) {
          throw const CollaborationException('invalid_response');
        }
        throw CollaborationApiException(
          error['code'] as String,
          details: error['details'] is Map<String, dynamic>
              ? error['details'] as Map<String, dynamic>
              : const {},
        );
      }
      if (decoded['data'] is! Map<String, dynamic>) {
        throw const CollaborationException('invalid_response');
      }
      return decoded['data'] as Map<String, dynamic>;
    } on CollaborationException {
      rethrow;
    } on FormatException {
      throw const CollaborationException('invalid_response');
    } catch (_) {
      throw const CollaborationException('network');
    }
  }

  @override
  void close() => _client.close();
}
