import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'local_vault.dart';
import 'local_vault_keys.dart';

/// Only non-sensitive boot choices (theme, locale, window and guide flags)
/// remain plain. Routing/fingerprints and account/scope-keyed settings do not.
abstract interface class LocalVaultPreferences {
  String? getString(String key);
  bool? getBool(String key);
  Future<bool> setString(String key, String value);
  Future<bool> setBool(String key, bool value);
  Future<bool> remove(String key);
}

/// Explicitly unencrypted legacy web storage and injected platform fixtures.
/// Native production providers never select this adapter.
class LegacyLocalVaultPreferences implements LocalVaultPreferences {
  LegacyLocalVaultPreferences(this.preferences);
  final SharedPreferences preferences;
  @override
  String? getString(String key) => preferences.getString(key);
  @override
  bool? getBool(String key) => preferences.getBool(key);
  @override
  Future<bool> setString(String key, String value) =>
      preferences.setString(key, value);
  @override
  Future<bool> setBool(String key, bool value) =>
      preferences.setBool(key, value);
  @override
  Future<bool> remove(String key) => preferences.remove(key);
}

class EncryptedLocalVaultPreferences implements LocalVaultPreferences {
  EncryptedLocalVaultPreferences._(this._preferences, this._key, this._vaultId);
  final SharedPreferences _preferences;
  final SecretKey _key;
  final String _vaultId;
  final _values = <String, Object>{};
  Future<void> _tail = Future.value();
  static const keys = {
    'organizer_notification_ids_v1',
    'organizer_remote_push_sdk_identity_v1',
    'organizer_remote_push_sdk_cleanup_v1',
    'organizer_remote_push_device_opt_in_v1',
    'organizer_local_notification_preferences_v2',
    'organizer_local_reminders_enabled_v1',
    'organizer_local_reminders_sound_v1',
  };
  static String protectedKey(String key) => 'jivie_vault_pref_v1:$key';

  static Future<EncryptedLocalVaultPreferences> open(
    SharedPreferences preferences,
    LocalVaultKey key, {
    bool migrateLegacy = false,
  }) async {
    final result = EncryptedLocalVaultPreferences._(
      preferences,
      await key.derive('preferences'),
      key.id,
    );
    try {
      for (final name in keys) {
        final encoded = preferences.getString(protectedKey(name));
        if (encoded != null) {
          result._values[name] = await result._decode(name, encoded);
          if (migrateLegacy &&
              preferences.containsKey(name) &&
              preferences.get(name) != result._values[name]) {
            throw const LocalVaultException('vault_preferences_conflict');
          }
        } else if (preferences.containsKey(name)) {
          if (!migrateLegacy) {
            throw const LocalVaultException('vault_preferences_pending');
          }
          final value = preferences.get(name);
          if (value is! String && value is! bool) throw const FormatException();
          await result._save(name, value!);
        }
        if (migrateLegacy && preferences.containsKey(name)) {
          if (!await preferences.remove(name)) throw const FormatException();
        }
      }
      return result;
    } catch (_) {
      result._key.destroy();
      throw const LocalVaultException('vault_preferences');
    }
  }

  Future<Object> _decode(String name, String value) async {
    final doc = jsonDecode(value) as Map<String, dynamic>;
    if (doc.length != 3) throw const FormatException();
    final plain = await AesGcm.with256bits().decrypt(
      SecretBox(
        base64Decode(doc['data'] as String),
        nonce: base64Decode(doc['nonce'] as String),
        mac: Mac(base64Decode(doc['mac'] as String)),
      ),
      secretKey: _key,
      aad: utf8.encode('$_vaultId:$name:v1'),
    );
    final result = jsonDecode(utf8.decode(plain));
    if (result is! String && result is! bool) throw const FormatException();
    return result as Object;
  }

  void _checkName(String name) {
    if (!keys.contains(name)) {
      throw const LocalVaultException('vault_preference_key');
    }
  }

  @override
  String? getString(String key) {
    _checkName(key);
    return _values[key] as String?;
  }

  @override
  bool? getBool(String key) {
    _checkName(key);
    return _values[key] as bool?;
  }

  Future<bool> _save(String name, Object value) async {
    _checkName(name);
    final box = await AesGcm.with256bits().encrypt(
      utf8.encode(jsonEncode(value)),
      secretKey: _key,
      nonce: localVaultRandom(12),
      aad: utf8.encode('$_vaultId:$name:v1'),
    );
    final text = jsonEncode({
      'nonce': base64Encode(box.nonce),
      'data': base64Encode(box.cipherText),
      'mac': base64Encode(box.mac.bytes),
    });
    if (!await _preferences.setString(protectedKey(name), text) ||
        _preferences.getString(protectedKey(name)) != text) {
      throw const LocalVaultException('vault_preferences');
    }
    _values[name] = await _decode(name, text);
    return true;
  }

  Future<bool> _queued(Future<bool> Function() action) {
    final future = _tail.then((_) => action());
    _tail = future.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return future;
  }

  @override
  Future<bool> setString(String key, String value) =>
      _queued(() => _save(key, value));
  @override
  Future<bool> setBool(String key, bool value) =>
      _queued(() => _save(key, value));
  @override
  Future<bool> remove(String key) => _queued(() async {
    _checkName(key);
    if (!await _preferences.remove(protectedKey(key))) return false;
    _values.remove(key);
    return true;
  });
}

// Kept for existing isolated fixtures; never selected by the native factory.
typedef TestLocalVaultPreferences = LegacyLocalVaultPreferences;
