import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'local_vault.dart';
import 'local_vault_secure_storage.dart';

abstract interface class LocalVaultKeyStore {
  Future<String?> read();
  Future<void> write(String value);
}

class SecureLocalVaultKeyStore implements LocalVaultKeyStore {
  const SecureLocalVaultKeyStore();
  static const key = 'jivie_installation_vault_v1';
  static const _storage = localVaultSecureStorage;
  @override
  Future<String?> read() async {
    try {
      return await _storage.read(key: key);
    } catch (_) {
      throw const LocalVaultException('vault_secure_storage');
    }
  }

  @override
  Future<void> write(String value) async {
    try {
      await _storage.write(key: key, value: value);
      if (await read() != value) throw const FormatException();
    } catch (_) {
      throw const LocalVaultException('vault_secure_storage');
    }
  }
}

Uint8List localVaultRandom(int length) {
  final random = Random.secure();
  return Uint8List.fromList(List.generate(length, (_) => random.nextInt(256)));
}

class LocalVaultKey {
  LocalVaultKey(this.id, this.bytes);
  factory LocalVaultKey.generate() => LocalVaultKey(
    base64Url.encode(localVaultRandom(24)).replaceAll('=', ''),
    localVaultRandom(32),
  );
  final String id;
  final Uint8List bytes;
  String encode() => jsonEncode({
    'format': 'jivie-installation-recovery',
    'version': 1,
    'vaultId': id,
    'key': base64Encode(bytes),
  });

  static LocalVaultKey decode(String text) {
    if (utf8.encode(text).length > 4096) {
      throw const LocalVaultException('vault_recovery_invalid');
    }
    try {
      final json = jsonDecode(text) as Map<String, dynamic>;
      if (json.length != 4 ||
          json['format'] != 'jivie-installation-recovery' ||
          json['version'] != 1 ||
          json['vaultId'] is! String ||
          !RegExp(r'^[A-Za-z0-9_-]{32}$').hasMatch(json['vaultId'] as String)) {
        throw const FormatException();
      }
      final bytes = base64Decode(json['key'] as String);
      if (bytes.length != 32) throw const FormatException();
      return LocalVaultKey(json['vaultId'] as String, bytes);
    } catch (_) {
      throw const LocalVaultException('vault_recovery_invalid');
    }
  }

  Future<SecretKey> derive(String purpose) =>
      Hkdf(hmac: Hmac.sha256(), outputLength: 32).deriveKey(
        secretKey: SecretKey(bytes),
        nonce: utf8.encode(id),
        info: utf8.encode('Jivie/local-vault/v1/$purpose'),
      );

  Future<Map<String, dynamic>> makeProbe() async {
    final derived = await derive('verification');
    try {
      final box = await AesGcm.with256bits().encrypt(
        utf8.encode('Jivie installation recovery verified'),
        secretKey: derived,
        nonce: localVaultRandom(12),
        aad: utf8.encode(id),
      );
      return {
        'nonce': base64Encode(box.nonce),
        'data': base64Encode(box.cipherText),
        'mac': base64Encode(box.mac.bytes),
      };
    } finally {
      derived.destroy();
    }
  }

  Future<void> verifyProbe(Map<String, dynamic> probe) async {
    final derived = await derive('verification');
    try {
      final bytes = await AesGcm.with256bits().decrypt(
        SecretBox(
          base64Decode(probe['data'] as String),
          nonce: base64Decode(probe['nonce'] as String),
          mac: Mac(base64Decode(probe['mac'] as String)),
        ),
        secretKey: derived,
        aad: utf8.encode(id),
      );
      if (utf8.decode(bytes) != 'Jivie installation recovery verified') {
        throw const FormatException();
      }
    } catch (_) {
      throw const LocalVaultException('vault_recovery_mismatch');
    } finally {
      derived.destroy();
    }
  }
}
