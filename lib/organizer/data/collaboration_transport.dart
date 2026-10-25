import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../domain/collaboration_models.dart';

class CollaborationApiException extends CollaborationException {
  const CollaborationApiException(super.code, {this.details = const {}});
  final Map<String, dynamic> details;
}

final _rateLimitPauseZone = Object();

/// Explicit workflow scope only. The transport retains the exact encoded HTTP
/// body while the caller durably pauses or cancels. Other callers keep their
/// existing error handling; authorization/network denials are never retried.
Future<T> withCollaborationRateLimitPause<T>(
  Future<T> Function() action, {
  required Future<void> Function(int seconds) pause,
}) => runZoned(action, zoneValues: {_rateLimitPauseZone: pause});

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

typedef CollaborationAttempt = Future<Map<String, dynamic>> Function();
typedef CollaborationAttemptGate =
    Future<Map<String, dynamic>> Function(CollaborationAttempt send);

/// A scheduler wraps one physical attempt, never an explicit rate-limit pause.
abstract interface class CollaborationSingleAttemptTransport {
  Future<Map<String, dynamic>> callWithAttemptGate({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
    required CollaborationAttemptGate gate,
  });
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

class HttpCollaborationTransport
    implements CollaborationTransport, CollaborationSingleAttemptTransport {
  HttpCollaborationTransport({
    http.Client? client,
    this.requestTimeout = const Duration(seconds: 20),
    this.onAttempt,
  }) : _client = client ?? http.Client();
  final http.Client _client;
  final Duration requestTimeout;

  /// Optional operation-name diagnostics, never payloads or credentials.
  final void Function(String operation)? onAttempt;
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) => _callWithGate(
    serverUrl: serverUrl,
    operation: operation,
    params: params,
    token: token,
    allowLocalHttp: allowLocalHttp,
  );

  @override
  Future<Map<String, dynamic>> callWithAttemptGate({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
    required CollaborationAttemptGate gate,
  }) => _callWithGate(
    serverUrl: serverUrl,
    operation: operation,
    params: params,
    token: token,
    allowLocalHttp: allowLocalHttp,
    gate: gate,
  );

  Future<Map<String, dynamic>> _callWithGate({
    required String serverUrl,
    required String operation,
    required Map<String, Object?> params,
    required String? token,
    required bool allowLocalHttp,
    CollaborationAttemptGate? gate,
  }) async {
    final encoded = jsonEncode({'v': 1, 'op': operation, 'params': params});
    final pause =
        Zone.current[_rateLimitPauseZone] as Future<void> Function(int)?;
    while (true) {
      try {
        Future<Map<String, dynamic>> send() {
          onAttempt?.call(operation);
          return _callOnce(
            serverUrl: serverUrl,
            requestBody: encoded,
            token: token,
            allowLocalHttp: allowLocalHttp,
          );
        }

        return await (gate == null ? send() : gate(send));
      } on CollaborationApiException catch (error) {
        final retry = error.details['retryAfter'];
        if (pause == null ||
            error.code != 'rate_limited' ||
            retry is! int ||
            retry < 1 ||
            retry > 60) {
          rethrow;
        }
        await pause(retry);
      }
    }
  }

  Future<Map<String, dynamic>> _callOnce({
    required String serverUrl,
    required String requestBody,
    required String? token,
    required bool allowLocalHttp,
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
      request.body = requestBody;
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
      final transientFailure =
          streamed.statusCode >= 500 && streamed.statusCode < 600;
      final Object? decoded;
      try {
        decoded = jsonDecode(utf8.decode(bytes));
      } on FormatException {
        if (transientFailure) {
          throw const CollaborationException('network');
        }
        rethrow;
      }
      if (decoded is! Map<String, dynamic> || decoded['v'] != 1) {
        if (transientFailure &&
            (decoded is! Map<String, dynamic> || !decoded.containsKey('v'))) {
          throw const CollaborationException('network');
        }
        throw const CollaborationException('incompatible_server');
      }
      // A valid Native denial remains authoritative even if a proxy changes
      // its HTTP status. Unavailability must never erase an explicit revocation.
      final error = decoded['error'];
      if (error is Map<String, dynamic> && error['code'] is String) {
        throw CollaborationApiException(
          error['code'] as String,
          details: error['details'] is Map<String, dynamic>
              ? error['details'] as Map<String, dynamic>
              : const {},
        );
      }
      if (streamed.statusCode < 200 ||
          streamed.statusCode >= 300 ||
          decoded.containsKey('error') ||
          decoded['data'] is! Map<String, dynamic>) {
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
