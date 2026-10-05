import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/kanboard_models.dart';

class CredentialsStorageException implements Exception {
  const CredentialsStorageException();

  @override
  String toString() => 'Secure credential storage is unavailable.';
}

class CredentialsStore {
  const CredentialsStore();

  static const _storage = FlutterSecureStorage();
  static const _recordKey = 'kanboard_credentials_v2';
  static const _urlKey = 'kanboard_server_url';
  static const _userKey = 'kanboard_username';
  static const _tokenKey = 'kanboard_token';
  static const _authModeKey = 'kanboard_auth_mode';
  static const _legacyKeys = [_urlKey, _userKey, _tokenKey, _authModeKey];

  Future<void> save(KanboardCredentials credentials) async {
    try {
      // One secure item avoids partial replacement of separate credential fields.
      await _writeVerified(credentials);
      await _removeLegacy();
    } catch (_) {
      throw const CredentialsStorageException();
    }
  }

  Future<KanboardCredentials?> read() async {
    try {
      final record = await _storage.read(key: _recordKey);
      if (record != null) {
        final credentials = _decode(record);
        await _removeLegacy();
        return credentials;
      }
      final secureUrl = await _storage.read(key: _urlKey);
      final secureUser = await _storage.read(key: _userKey);
      final secureToken = await _storage.read(key: _tokenKey);
      final secureMode = await _storage.read(key: _authModeKey);
      final prefs = await SharedPreferences.getInstance();
      // Never combine fields from different records/accounts.
      final secureComplete =
          secureUrl != null && secureUser != null && secureToken != null;
      final url = secureComplete ? secureUrl : prefs.getString(_urlKey);
      final user = secureComplete ? secureUser : prefs.getString(_userKey);
      final token = secureComplete ? secureToken : prefs.getString(_tokenKey);
      final mode = secureComplete ? secureMode : prefs.getString(_authModeKey);
      if (url == null || user == null || token == null) return null;
      final credentials = KanboardCredentials(
        serverUrl: url,
        username: user,
        token: token,
        authMode: _parseAuthMode(mode),
      );
      // Keep legacy copies intact until the complete secure record is confirmed.
      await _writeVerified(credentials);
      await _removeLegacy();
      return credentials;
    } catch (_) {
      throw const CredentialsStorageException();
    }
  }

  Future<void> clear() async {
    try {
      await _storage.delete(key: _recordKey);
      await _removeLegacy();
    } catch (_) {
      throw const CredentialsStorageException();
    }
  }

  Future<void> _writeVerified(KanboardCredentials credentials) async {
    final record = jsonEncode({
      'url': credentials.serverUrl,
      'username': credentials.username,
      'token': credentials.token,
      'auth_mode': credentials.authMode.name,
      'local_http': credentials.allowLocalHttp,
    });
    await _storage.write(key: _recordKey, value: record);
    if (await _storage.read(key: _recordKey) != record) {
      throw const CredentialsStorageException();
    }
  }

  Future<void> _removeLegacy() async {
    for (final key in _legacyKeys) {
      await _storage.delete(key: key);
    }
    final prefs = await SharedPreferences.getInstance();
    for (final key in _legacyKeys) {
      if (!await prefs.remove(key)) throw const CredentialsStorageException();
    }
  }

  KanboardCredentials _decode(String record) {
    final json = jsonDecode(record) as Map<String, dynamic>;
    return KanboardCredentials(
      serverUrl: json['url'] as String,
      username: json['username'] as String,
      token: json['token'] as String,
      authMode: _parseAuthMode(json['auth_mode'] as String?),
      allowLocalHttp: json['local_http'] == true,
    );
  }

  KanboardAuthMode _parseAuthMode(String? value) =>
      KanboardAuthMode.values.firstWhere(
        (mode) => mode.name == value,
        orElse: () => KanboardAuthMode.apiToken,
      );
}
