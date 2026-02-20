import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/kanboard_models.dart';

class CredentialsStore {
  const CredentialsStore();

  static const _storage = FlutterSecureStorage();
  static const _urlKey = 'kanboard_server_url';
  static const _userKey = 'kanboard_username';
  static const _tokenKey = 'kanboard_token';
  static const _authModeKey = 'kanboard_auth_mode';

  Future<void> save(KanboardCredentials credentials) async {
    try {
      await _storage.write(key: _urlKey, value: credentials.serverUrl);
      await _storage.write(key: _userKey, value: credentials.username);
      await _storage.write(key: _tokenKey, value: credentials.token);
      await _storage.write(
        key: _authModeKey,
        value: credentials.authMode.name,
      );
    } on PlatformException catch (_) {
      // macOS can throw -34018 when keychain entitlement is unavailable.
      await _saveWithSharedPrefs(credentials);
    }
  }

  Future<KanboardCredentials?> read() async {
    try {
      final url = await _storage.read(key: _urlKey);
      final username = await _storage.read(key: _userKey);
      final token = await _storage.read(key: _tokenKey);
      final authModeRaw = await _storage.read(key: _authModeKey);

      if (url == null || username == null || token == null) {
        // If secure storage is empty but fallback storage has values, use them.
        return _readFromSharedPrefs();
      }

      return KanboardCredentials(
        serverUrl: url,
        username: username,
        token: token,
        authMode: _parseAuthMode(authModeRaw),
      );
    } on PlatformException catch (_) {
      return _readFromSharedPrefs();
    }
  }

  Future<void> clear() async {
    try {
      await _storage.delete(key: _urlKey);
      await _storage.delete(key: _userKey);
      await _storage.delete(key: _tokenKey);
      await _storage.delete(key: _authModeKey);
    } on PlatformException catch (_) {
      // no-op; fallback is still cleared below
    }
    await _clearSharedPrefs();
  }

  Future<void> _saveWithSharedPrefs(KanboardCredentials credentials) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_urlKey, credentials.serverUrl);
    await prefs.setString(_userKey, credentials.username);
    await prefs.setString(_tokenKey, credentials.token);
    await prefs.setString(_authModeKey, credentials.authMode.name);
    debugPrint(
      '[CredentialsStore] Falling back to SharedPreferences for credential storage.',
    );
  }

  Future<KanboardCredentials?> _readFromSharedPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString(_urlKey);
    final username = prefs.getString(_userKey);
    final token = prefs.getString(_tokenKey);
    final authModeRaw = prefs.getString(_authModeKey);

    if (url == null || username == null || token == null) return null;
    return KanboardCredentials(
      serverUrl: url,
      username: username,
      token: token,
      authMode: _parseAuthMode(authModeRaw),
    );
  }

  Future<void> _clearSharedPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_urlKey);
    await prefs.remove(_userKey);
    await prefs.remove(_tokenKey);
    await prefs.remove(_authModeKey);
  }

  KanboardAuthMode _parseAuthMode(String? value) {
    return KanboardAuthMode.values.firstWhere(
      (mode) => mode.name == value,
      orElse: () => KanboardAuthMode.apiToken,
    );
  }
}
