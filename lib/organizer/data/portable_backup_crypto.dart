import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import '../domain/collaboration_models.dart';

/// Portable authenticated envelope. Passwords and keys are never persisted.
class PortableBackupCrypto {
  static const maxBytes = 64 * 1024 * 1024;
  static const iterations = 600000;
  final _cipher = AesGcm.with256bits();
  final _kdf = Pbkdf2.hmacSha256(iterations: iterations, bits: 256);
  void _password(String password) {
    if (password.runes.length < 12 || utf8.encode(password).length > 1024) {
      throw const CollaborationException('backup_password_invalid');
    }
  }

  Future<Uint8List> encrypt(
    Map<String, dynamic> document,
    String password,
  ) async {
    _password(password);
    final random = Random.secure();
    final salt = List.generate(16, (_) => random.nextInt(256));
    final nonce = List.generate(12, (_) => random.nextInt(256));
    final header = <String, dynamic>{
      'format': 'vsakdan-encrypted-backup',
      'version': 1,
      'kdf': 'pbkdf2-sha256',
      'iterations': iterations,
      'salt': base64Encode(salt),
      'cipher': 'aes-256-gcm',
      'nonce': base64Encode(nonce),
    };
    final plain = utf8.encode(jsonEncode(document));
    if (plain.length > maxBytes ~/ 2) {
      throw const CollaborationException('backup_too_large');
    }
    final key = await _kdf.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: salt,
    );
    try {
      final box = await _cipher.encrypt(
        plain,
        secretKey: key,
        nonce: nonce,
        aad: utf8.encode(jsonEncode(header)),
      );
      return Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            ...header,
            'ciphertext': base64Encode(box.cipherText),
            'mac': base64Encode(box.mac.bytes),
          }),
        ),
      );
    } finally {
      key.destroy();
    }
  }

  Future<Map<String, dynamic>> decrypt(List<int> bytes, String password) async {
    _password(password);
    if (bytes.length > maxBytes) {
      throw const CollaborationException('backup_too_large');
    }
    Map<String, dynamic> envelope;
    List<int> salt, nonce, ciphertext, mac;
    try {
      envelope = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      if (envelope.length != 9 ||
          envelope['format'] != 'vsakdan-encrypted-backup' ||
          envelope['version'] != 1 ||
          envelope['kdf'] != 'pbkdf2-sha256' ||
          envelope['iterations'] != iterations ||
          envelope['cipher'] != 'aes-256-gcm') {
        throw const FormatException();
      }
      salt = base64Decode(envelope['salt'] as String);
      nonce = base64Decode(envelope['nonce'] as String);
      ciphertext = base64Decode(envelope['ciphertext'] as String);
      mac = base64Decode(envelope['mac'] as String);
      if (salt.length != 16 ||
          nonce.length != 12 ||
          mac.length != 16 ||
          ciphertext.length > maxBytes ~/ 2) {
        throw const FormatException();
      }
    } on Object {
      throw const CollaborationException('backup_unsupported');
    }
    final header = {
      for (final name in [
        'format',
        'version',
        'kdf',
        'iterations',
        'salt',
        'cipher',
        'nonce',
      ])
        name: envelope[name],
    };
    final key = await _kdf.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: salt,
    );
    try {
      final plain = await _cipher.decrypt(
        SecretBox(ciphertext, nonce: nonce, mac: Mac(mac)),
        secretKey: key,
        aad: utf8.encode(jsonEncode(header)),
      );
      return jsonDecode(utf8.decode(plain)) as Map<String, dynamic>;
    } on Object {
      throw const CollaborationException('backup_auth_failed');
    } finally {
      key.destroy();
    }
  }
}
