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
    this.enableDebugLogs = true,
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  final Uri endpoint;
  final String username;
  final String password;
  final bool enableDebugLogs;
  final http.Client _httpClient;

  int _requestId = 0;

  String get _basicAuth {
    final raw = '$username:$password';
    return 'Basic ${base64Encode(utf8.encode(raw))}';
  }

  void _log(String message) {
    if (!enableDebugLogs) return;
    debugPrint('[Kanboard JSON-RPC] $message');
  }

  String _safePreview(Object? value, {int max = 350}) {
    final text = value?.toString() ?? 'null';
    if (text.length <= max) return text;
    return '${text.substring(0, max)}...';
  }

  Future<dynamic> call(String method, [Object? params]) async {
    _requestId += 1;
    final requestId = _requestId;
    final payload = <String, dynamic>{
      'jsonrpc': '2.0',
      'method': method,
      'id': requestId,
      if (params != null) 'params': params,
    };
    _log(
      'Request #$requestId -> $method @ $endpoint (user="$username", params=${_safePreview(params)})',
    );

    final body = jsonEncode(payload);
    Uri requestUri = endpoint;
    http.Response response = await _httpClient.post(
      requestUri,
      headers: <String, String>{
        'Content-Type': 'application/json',
        'Authorization': _basicAuth,
      },
      body: body,
    );
    var redirects = 0;
    while (response.statusCode >= 300 &&
        response.statusCode < 400 &&
        redirects < 2) {
      final location = response.headers['location'];
      if (location == null || location.isEmpty) break;
      final nextUri = requestUri.resolve(location);
      _log(
        'Request #$requestId redirected (${response.statusCode}) to $nextUri, retrying with same payload.',
      );
      requestUri = nextUri;
      response = await _httpClient.post(
        requestUri,
        headers: <String, String>{
          'Content-Type': 'application/json',
          'Authorization': _basicAuth,
        },
        body: body,
      );
      redirects += 1;
    }
    _log(
      'Response #$requestId <- HTTP ${response.statusCode} ${response.reasonPhrase ?? ''} body=${_safePreview(response.body)}',
    );

    if (response.statusCode == 401) {
      _log('Authentication failed with user "$username".');
      throw JsonRpcException('Authentication failed (401).');
    }
    if (response.statusCode == 403) {
      _log('Authorization failed (403) for user "$username".');
      throw JsonRpcException('Permission denied (403).');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final location = response.headers['location'];
      final locationSuffix = location == null ? '' : ' (location: $location)';
      _log('Unexpected HTTP status ${response.statusCode}$locationSuffix.');
      throw JsonRpcException(
        'HTTP error ${response.statusCode}: ${response.reasonPhrase}$locationSuffix',
      );
    }

    Map<String, dynamic> decoded;
    try {
      decoded = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (error) {
      _log('Invalid JSON response: $error');
      throw JsonRpcException('Server returned non-JSON response.');
    }
    if (decoded['error'] != null) {
      final err = decoded['error'] as Map<String, dynamic>;
      _log('JSON-RPC error: code=${err['code']} message=${err['message']}');
      throw JsonRpcException(
        err['message']?.toString() ?? 'Unknown JSON-RPC error',
        code: err['code'] is int ? err['code'] as int : null,
      );
    }

    _log('Request #$requestId succeeded for method "$method".');
    return decoded['result'];
  }
}
