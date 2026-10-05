import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class JsonRpcException implements Exception {
  JsonRpcException(this.message, {this.code});
  final String message;
  final int? code;
  @override
  String toString() => 'JsonRpcException(code: $code, message: $message)';
}

class JsonRpcClient {
  JsonRpcClient({
    required this.endpoint,
    required this.username,
    required this.password,
    this.enableDebugLogs = false,
    this.allowLocalHttp = false,
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client() {
    validateUri(endpoint);
    if (username.toLowerCase() == 'jsonrpc') {
      throw JsonRpcException('An individual user account is required.');
    }
  }

  final Uri endpoint;
  final String username;
  final String password;
  final bool enableDebugLogs;
  final bool allowLocalHttp;
  final http.Client _httpClient;
  int _requestId = 0;

  void close() => _httpClient.close();

  void validateUri(Uri uri) =>
      validateEndpoint(uri, allowLocalHttp: allowLocalHttp);

  static void validateEndpoint(Uri uri, {bool allowLocalHttp = false}) {
    final loopback =
        uri.host == 'localhost' || uri.host == '127.0.0.1' || uri.host == '::1';
    if (uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        (uri.scheme != 'https' &&
            !(allowLocalHttp && uri.scheme == 'http' && loopback))) {
      throw JsonRpcException(
        'HTTPS is required; HTTP is allowed only for explicitly enabled loopback development.',
      );
    }
  }

  bool _sameOrigin(Uri uri) =>
      uri.scheme == endpoint.scheme &&
      uri.host.toLowerCase() == endpoint.host.toLowerCase() &&
      uri.port == endpoint.port;

  /// Shared policy for JSON-RPC and authenticated legacy web requests.
  Future<http.Response> sendAuthenticatedRequest(
    Uri uri, {
    String method = 'POST',
    Map<String, String> headers = const {},
    String? body,
    Map<String, String>? bodyFields,
    bool basicAuth = false,
    bool followSameOriginRedirects = true,
  }) async {
    validateUri(uri);
    if (!_sameOrigin(uri)) {
      throw JsonRpcException('Request origin is not permitted.');
    }
    var current = uri;
    for (var redirects = 0; ; redirects++) {
      final request = http.Request(method, current)..followRedirects = false;
      request.headers.addAll(headers);
      if (basicAuth) {
        request.headers['Authorization'] =
            'Basic ${base64Encode(utf8.encode('$username:$password'))}';
      }
      if (bodyFields != null) {
        request.bodyFields = bodyFields;
      } else if (body != null) {
        request.body = body;
      }
      final streamed = await _httpClient
          .send(request)
          .timeout(const Duration(seconds: 20));
      final response = await http.Response.fromStream(
        streamed,
      ).timeout(const Duration(seconds: 20));
      if (![301, 302, 303, 307, 308].contains(response.statusCode) ||
          !followSameOriginRedirects) {
        return response;
      }
      if (redirects >= 2) throw JsonRpcException('Too many redirects.');
      final location = response.headers['location'];
      if (location == null || location.isEmpty) {
        throw JsonRpcException('Invalid redirect.');
      }
      final next = current.resolve(location);
      validateUri(next);
      if (!_sameOrigin(next)) {
        throw JsonRpcException('Cross-origin redirect rejected.');
      }
      // Never convert a JSON-RPC mutation into a GET or move credentials to a new origin.
      current = next;
    }
  }

  void _log(String message) {
    if (enableDebugLogs) debugPrint('[Kanboard JSON-RPC] $message');
  }

  Future<dynamic> call(String method, [Object? params]) async {
    final requestId = ++_requestId;
    final payload = {
      'jsonrpc': '2.0',
      'method': method,
      'id': requestId,
      if (params != null) 'params': params,
    };
    _log('Request #$requestId started.');
    final response = await sendAuthenticatedRequest(
      endpoint,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
      basicAuth: true,
    );
    _log('Response #$requestId HTTP ${response.statusCode}.');
    if (response.statusCode == 401) {
      throw JsonRpcException('Authentication failed (401).');
    }
    if (response.statusCode == 403) {
      throw JsonRpcException('Permission denied (403).');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw JsonRpcException('HTTP error ${response.statusCode}.');
    }
    Map<String, dynamic> decoded;
    try {
      decoded = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw JsonRpcException('Server returned an invalid JSON response.');
    }
    if (decoded['error'] != null) {
      final error = decoded['error'];
      if (error is! Map<String, dynamic>) {
        throw JsonRpcException('Invalid JSON-RPC error response.');
      }
      throw JsonRpcException(
        error['message']?.toString() ?? 'JSON-RPC request failed.',
        code: error['code'] is int ? error['code'] as int : null,
      );
    }
    if (decoded['jsonrpc'] != '2.0' ||
        decoded['id'] != requestId ||
        !decoded.containsKey('result')) {
      throw JsonRpcException('Invalid JSON-RPC response identity.');
    }
    return decoded['result'];
  }
}
