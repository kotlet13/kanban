import 'dart:convert';
import 'dart:typed_data';

import 'package:sodium/sodium.dart';

import 'crypto_codec.dart';
import 'crypto_json.dart';
import '../recovery_bundle.dart';

/// The account section contains no installation key, session token, data
/// snapshot or routine device private key. A combined file wraps this section
/// alongside independent installation recovery material.
class AccountRecoveryMaterial {
  AccountRecoveryMaterial({
    required this.file,
    required this.encryptedRoot,
    required this.signingPublicKey,
    required this.encryptionPublicKey,
    required this.fingerprint,
  });
  final Uint8List file;
  final Map<String, dynamic> encryptedRoot;
  final Uint8List signingPublicKey;
  final Uint8List encryptionPublicKey;
  final String fingerprint;
  void dispose() => file.fillRange(0, file.length, 0);
}

class RecoveredAccountRoot {
  RecoveredAccountRoot(
    this.signing,
    this.encryption, [
    this.historicalEncryption = const [],
  ]);
  final KeyPair signing;
  final KeyPair encryption;
  final List<KeyPair> historicalEncryption;
  void dispose() {
    signing.secretKey.dispose();
    encryption.secretKey.dispose();
    for (final historical in historicalEncryption) {
      historical.secretKey.dispose();
    }
  }
}

class RecoveryFileCodec {
  RecoveryFileCodec(this.crypto);
  final CryptoCodec crypto;
  static const maxBytes = 64 * 1024;

  AccountRecoveryMaterial create({
    required String serverId,
    required String accountId,
    List<KeyPair> historicalEncryption = const [],
    bool replacement = false,
  }) {
    final sodium = crypto.sodium;
    final signingSeed = sodium.secureRandom(32);
    final encryptionSeed = sodium.secureRandom(32);
    final secret = sodium.secureRandom(32);
    final signing = sodium.crypto.sign.seedKeyPair(signingSeed);
    final encryption = sodium.crypto.box.seedKeyPair(encryptionSeed);
    final fingerprint = crypto.fingerprint(
      signing.publicKey,
      encryption.publicKey,
    );
    final context = <String, dynamic>{
      'accountId': accountId,
      'fingerprint': fingerprint,
      'purpose': 'accountRecoveryRoot',
      'recoveryId': crypto.randomId(),
      'serverId': serverId,
    };
    final signBytes = signingSeed.extractBytes();
    final encryptionBytes = encryptionSeed.extractBytes();
    final secretBytes = secret.extractBytes();
    Uint8List? plaintext;
    try {
      plaintext = CryptoJson.encode({
        'encryptionSeedBase64': base64Encode(encryptionBytes),
        'signingSeedBase64': base64Encode(signBytes),
        'version': replacement ? 2 : 1,
        if (replacement)
          'historicalEncryptionKeys': [
            for (final historical in historicalEncryption)
              _exportEncryption(historical),
          ],
      });
      final encrypted = crypto.encrypt(
        plaintext: plaintext,
        key: secret,
        context: context,
      );
      final file = CryptoJson.encode({
        'accountId': accountId,
        'encryptionPublicKeyBase64': base64Encode(encryption.publicKey),
        'fingerprint': fingerprint,
        'recoveryId': context['recoveryId'],
        'scope': 'account',
        'secretBase64': base64Encode(secretBytes),
        'serverId': serverId,
        'signingPublicKeyBase64': base64Encode(signing.publicKey),
        'suite': CryptoCodec.suite,
        'version': replacement ? 2 : 1,
      });
      return AccountRecoveryMaterial(
        file: file,
        encryptedRoot: encrypted,
        signingPublicKey: signing.publicKey,
        encryptionPublicKey: encryption.publicKey,
        fingerprint: fingerprint,
      );
    } finally {
      signBytes.fillRange(0, signBytes.length, 0);
      encryptionBytes.fillRange(0, encryptionBytes.length, 0);
      secretBytes.fillRange(0, secretBytes.length, 0);
      plaintext?.fillRange(0, plaintext.length, 0);
      signing.secretKey.dispose();
      encryption.secretKey.dispose();
      signingSeed.dispose();
      encryptionSeed.dispose();
      secret.dispose();
    }
  }

  /// [expectedFingerprint] is pinned independently of the server response: the
  /// original local setup or the externally selected account file supplies it.
  /// Supplying a new server key as this argument defeats identity verification.
  RecoveredAccountRoot open({
    required Uint8List file,
    required Map<String, dynamic> encryptedRoot,
    required String serverId,
    required String accountId,
    required String expectedFingerprint,
  }) {
    final decoded = inspect(file, serverId: serverId, accountId: accountId);
    if (decoded['fingerprint'] != expectedFingerprint) {
      throw const FormatException('recovery_identity');
    }
    final rawSecret = cryptoBase64(decoded['secretBase64'], length: 32);
    final secret = crypto.sodium.secureCopy(rawSecret);
    rawSecret.fillRange(0, rawSecret.length, 0);
    Uint8List? plaintext;
    try {
      plaintext = crypto.decrypt(
        envelope: encryptedRoot,
        key: secret,
        context: {
          'accountId': accountId,
          'fingerprint': expectedFingerprint,
          'purpose': 'accountRecoveryRoot',
          'recoveryId': decoded['recoveryId'],
          'serverId': serverId,
        },
      );
      final root = CryptoJson.decode(plaintext) as Map<String, dynamic>;
      if (root['version'] != decoded['version'] ||
          ![1, 2].contains(root['version'])) {
        throw const FormatException('recovery_version');
      }
      final historical = <KeyPair>[];
      final signingSeed = _seed(root['signingSeedBase64']);
      SecureKey? encryptionSeed;
      KeyPair? signing;
      KeyPair? encryption;
      try {
        encryptionSeed = _seed(root['encryptionSeedBase64']);
        signing = crypto.sodium.crypto.sign.seedKeyPair(signingSeed);
        encryption = crypto.sodium.crypto.box.seedKeyPair(encryptionSeed);
        if (crypto.fingerprint(signing.publicKey, encryption.publicKey) !=
                expectedFingerprint ||
            base64Encode(signing.publicKey) !=
                decoded['signingPublicKeyBase64'] ||
            base64Encode(encryption.publicKey) !=
                decoded['encryptionPublicKeyBase64']) {
          throw const FormatException('recovery_identity');
        }
        if (root['version'] == 2) {
          final rows = root['historicalEncryptionKeys'];
          if (rows is! List) throw const FormatException('recovery_history');
          final seen = <String>{base64Encode(encryption.publicKey)};
          for (final row in rows) {
            if (row is! Map ||
                row.length != 2 ||
                !seen.add(row['publicKeyBase64'] as String)) {
              throw const FormatException('recovery_history');
            }
            final public = cryptoBase64(row['publicKeyBase64'], length: 32);
            final private = _seed(row['secretKeyBase64']);
            try {
              // A round trip proves the supplied public/private pair matches.
              final probe = crypto.sodium.randombytes.buf(32);
              final sealed = crypto.sodium.crypto.box.seal(
                message: probe,
                publicKey: public,
              );
              final opened = crypto.sodium.crypto.box.sealOpen(
                cipherText: sealed,
                publicKey: public,
                secretKey: private,
              );
              if (base64Encode(probe) != base64Encode(opened)) {
                throw const FormatException('recovery_history');
              }
              opened.fillRange(0, opened.length, 0);
              probe.fillRange(0, probe.length, 0);
              historical.add(KeyPair(publicKey: public, secretKey: private));
            } catch (_) {
              private.dispose();
              rethrow;
            }
          }
        }
        return RecoveredAccountRoot(signing, encryption, historical);
      } catch (_) {
        signing?.secretKey.dispose();
        encryption?.secretKey.dispose();
        for (final key in historical) {
          key.secretKey.dispose();
        }
        rethrow;
      } finally {
        signingSeed.dispose();
        encryptionSeed?.dispose();
      }
    } finally {
      secret.dispose();
      plaintext?.fillRange(0, plaintext.length, 0);
    }
  }

  Map<String, dynamic> inspect(
    Uint8List file, {
    required String serverId,
    required String accountId,
  }) {
    final accountFile = RecoveryBundleCodec.accountBytes(file);
    dynamic decoded;
    try {
      decoded = CryptoJson.decode(accountFile, limit: maxBytes);
    } finally {
      accountFile.fillRange(0, accountFile.length, 0);
    }
    if (decoded is! Map<String, dynamic> ||
        decoded.length != 10 ||
        ![1, 2].contains(decoded['version']) ||
        decoded['suite'] != CryptoCodec.suite ||
        decoded['scope'] != 'account' ||
        decoded['serverId'] != serverId ||
        decoded['accountId'] != accountId ||
        decoded['recoveryId'] is! String ||
        !RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ).hasMatch(decoded['recoveryId'] as String)) {
      throw const FormatException('recovery_format');
    }
    final secret = cryptoBase64(decoded['secretBase64'], length: 32);
    secret.fillRange(0, secret.length, 0);
    final sign = cryptoBase64(decoded['signingPublicKeyBase64'], length: 32);
    final enc = cryptoBase64(decoded['encryptionPublicKeyBase64'], length: 32);
    if (crypto.fingerprint(sign, enc) != decoded['fingerprint']) {
      throw const FormatException('recovery_identity');
    }
    return decoded;
  }

  Map<String, dynamic> _exportEncryption(KeyPair key) {
    final raw = key.secretKey.extractBytes();
    try {
      return {
        'publicKeyBase64': base64Encode(key.publicKey),
        'secretKeyBase64': base64Encode(raw),
      };
    } finally {
      raw.fillRange(0, raw.length, 0);
    }
  }

  /// The old signing authority is intentionally never retained. The caller
  /// keeps both external files until the immutable transition is confirmed.
  AccountRecoveryMaterial replacement({
    required String serverId,
    required String accountId,
    required RecoveredAccountRoot previous,
  }) => create(
    serverId: serverId,
    accountId: accountId,
    replacement: true,
    historicalEncryption: [
      previous.encryption,
      ...previous.historicalEncryption,
    ],
  );

  SecureKey _seed(Object? value) {
    final bytes = cryptoBase64(value, length: 32);
    try {
      return crypto.sodium.secureCopy(bytes);
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  }
}
