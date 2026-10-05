import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../domain/collaboration_models.dart';
import '../domain/organizer_models.dart';

class DeviceSession {
  const DeviceSession(this.profile, this.token);
  final AccountSession profile;
  final String token;
}

abstract interface class DeviceSessionStore {
  Future<DeviceSession?> read();
  Future<void> write(DeviceSession session);
  Future<void> clear();
}

class SecureDeviceSessionStore implements DeviceSessionStore {
  const SecureDeviceSessionStore();
  static const _storage = FlutterSecureStorage();
  static const _key = 'organizer_device_session_v1';
  @override
  Future<DeviceSession?> read() async {
    try {
      final value = await _storage.read(key: _key);
      if (value == null) return null;
      final json = jsonDecode(value) as Map<String, dynamic>;
      return DeviceSession(
        AccountSession.fromJson(json['profile'] as Map<String, dynamic>),
        readString(json, 'token'),
      );
    } catch (_) {
      throw const CollaborationException('secure_storage');
    }
  }

  @override
  Future<void> write(DeviceSession session) async {
    try {
      final value = jsonEncode({
        'profile': session.profile.toJson(),
        'token': session.token,
      });
      await _storage.write(key: _key, value: value);
      if (await _storage.read(key: _key) != value) {
        throw const CollaborationException('secure_storage');
      }
    } catch (_) {
      throw const CollaborationException('secure_storage');
    }
  }

  @override
  Future<void> clear() async {
    try {
      await _storage.delete(key: _key);
      if (await _storage.read(key: _key) != null) {
        throw const CollaborationException('secure_storage');
      }
    } catch (_) {
      throw const CollaborationException('secure_storage');
    }
  }
}
