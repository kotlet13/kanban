import 'dart:convert';
import 'dart:typed_data';

import 'package:sodium/sodium.dart';

import 'crypto_json.dart';

/// Native libsodium operations. Sealed boxes are anonymous; only the outer
/// verified device signature authenticates their origin and intended context.
class CryptoCodec {
  CryptoCodec(this.sodium);
  final Sodium sodium;
  static const suite = 'sodium-box-seal-xchacha20poly1305-ed25519-v1';

  String randomId() {
    final bytes = sodium.randombytes.buf(16);
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  String fingerprint(Uint8List signing, Uint8List encryption) => base64Encode(
    sodium.crypto.genericHash(
      message: CryptoJson.encode({
        'encryptionKeyBase64': base64Encode(encryption),
        'signingKeyBase64': base64Encode(signing),
        'suite': suite,
      }),
      outLen: 32,
    ),
  );

  Map<String, dynamic> sign(Map<String, dynamic> command, SecureKey key) {
    return signDomain(command, key, 'JivieE2EE/v1\n');
  }

  Map<String, dynamic> signDomain(
    Map<String, dynamic> command,
    SecureKey key,
    String domain,
  ) {
    final bytes = CryptoJson.encode(command);
    return {
      'commandBase64': base64Encode(bytes),
      'signatureBase64': base64Encode(
        sodium.crypto.sign.detached(
          message: Uint8List.fromList([...utf8.encode(domain), ...bytes]),
          secretKey: key,
        ),
      ),
    };
  }

  Map<String, dynamic> verify(
    Map<String, dynamic> signed,
    Uint8List publicKey,
  ) {
    return verifyDomain(signed, publicKey, 'JivieE2EE/v1\n');
  }

  Map<String, dynamic> verifyDomain(
    Map<String, dynamic> signed,
    Uint8List publicKey,
    String domain,
  ) {
    if (signed.length != 2 || !signed.containsKey('signatureBase64')) {
      throw const FormatException('crypto_signature_shape');
    }
    final bytes = cryptoBase64(signed['commandBase64']);
    final value = CryptoJson.decode(bytes);
    bool valid;
    try {
      valid = sodium.crypto.sign.verifyDetached(
        message: Uint8List.fromList([...utf8.encode(domain), ...bytes]),
        signature: cryptoBase64(signed['signatureBase64'], length: 64),
        publicKey: publicKey,
      );
    } on SodiumException {
      throw const FormatException('crypto_authentication');
    }
    if (value is! Map<String, dynamic> || !valid) {
      throw const FormatException('crypto_signature');
    }
    return value;
  }

  Map<String, dynamic> encrypt({
    required Uint8List plaintext,
    required SecureKey key,
    required Map<String, dynamic> context,
  }) {
    final nonce = sodium.randombytes.buf(24);
    return {
      'version': 1,
      'suite': suite,
      'context': context,
      'nonceBase64': base64Encode(nonce),
      'ciphertextBase64': base64Encode(
        sodium.crypto.aeadXChaCha20Poly1305IETF.encrypt(
          message: plaintext,
          nonce: nonce,
          key: key,
          additionalData: CryptoJson.encode(context),
        ),
      ),
    };
  }

  Uint8List decrypt({
    required Map<String, dynamic> envelope,
    required SecureKey key,
    required Map<String, dynamic> context,
  }) {
    if (envelope['version'] != 1 ||
        envelope['suite'] != suite ||
        base64Encode(CryptoJson.encode(envelope['context'])) !=
            base64Encode(CryptoJson.encode(context))) {
      throw const FormatException('crypto_context');
    }
    try {
      return sodium.crypto.aeadXChaCha20Poly1305IETF.decrypt(
        cipherText: cryptoBase64(envelope['ciphertextBase64']),
        nonce: cryptoBase64(envelope['nonceBase64'], length: 24),
        key: key,
        additionalData: CryptoJson.encode(context),
      );
    } on SodiumException {
      throw const FormatException('crypto_authentication');
    }
  }

  String sealKey({
    required SecureKey key,
    required Uint8List recipientPublicKey,
    required Map<String, dynamic> context,
  }) {
    final bytes = key.extractBytes();
    try {
      final plaintext = CryptoJson.encode({
        'context': context,
        'keyBase64': base64Encode(bytes),
        'suite': suite,
        'version': 1,
      });
      try {
        return base64Encode(
          sodium.crypto.box.seal(
            message: plaintext,
            publicKey: recipientPublicKey,
          ),
        );
      } finally {
        plaintext.fillRange(0, plaintext.length, 0);
      }
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  }

  SecureKey openKey({
    required String sealed,
    required KeyPair recipient,
    required Map<String, dynamic> context,
  }) {
    late Uint8List bytes;
    try {
      bytes = sodium.crypto.box.sealOpen(
        cipherText: cryptoBase64(sealed),
        publicKey: recipient.publicKey,
        secretKey: recipient.secretKey,
      );
    } on SodiumException {
      throw const FormatException('crypto_authentication');
    }
    try {
      final decoded = CryptoJson.decode(bytes) as Map<String, dynamic>;
      if (decoded['version'] != 1 ||
          decoded['suite'] != suite ||
          base64Encode(CryptoJson.encode(decoded['context'])) !=
              base64Encode(CryptoJson.encode(context))) {
        throw const FormatException('crypto_context');
      }
      final raw = cryptoBase64(decoded['keyBase64'], length: 32);
      try {
        return sodium.secureCopy(raw);
      } finally {
        raw.fillRange(0, raw.length, 0);
      }
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  }
}
