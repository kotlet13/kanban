import 'dart:convert';
import 'dart:typed_data';

import 'package:sodium/sodium.dart' show SecureKey;

import 'account_directory_v2.dart' show cryptoSha256;
import 'crypto_codec.dart';
import 'crypto_json.dart';
import 'crypto_record_address.dart';

/// A token-holder routing-metadata envelope, NOT a secret from the hosting
/// server: the server already has the old token hash. It contains no space
/// name, content, DEK, recovery key, complete SQL row, or private mail state.
/// Neither successful decryption nor its tag establishes invitation authority.
/// The caller must verify the exact manager signature and final bridge/cutover
/// inclusion before accepting a recipient contribution or issuing any key.
class CryptoLegacyInvitationCapsule {
  CryptoLegacyInvitationCapsule(this.crypto);
  final CryptoCodec crypto;
  static const keyDomain = 'JivieLegacyInvitationCapsuleKey/v3\n';
  static const contextFields = {
    'version',
    'purpose',
    'serverId',
    'migrationId',
    'captureId',
    'sourceInventoryRoot',
    'bridgeId',
    'bindingId',
    'sourceCommitment',
    'scopeId',
    'membershipHeadHash',
  };
  static const metadataFields = {
    'version',
    'invitationId',
    'scopeId',
    'recipient',
    'role',
    'expiresAtEpoch',
    'acceptedAtEpoch',
    'revokedAtEpoch',
    'legacyContractVersion',
    'tokenHash',
  };
  void _context(Map<String, dynamic> value) {
    if (value.length != contextFields.length ||
        value.keys.any((k) => !contextFields.contains(k)) ||
        value['version'] != 3 ||
        value['purpose'] != 'legacyInvitationBridge' ||
        !const [
          'serverId',
          'migrationId',
          'captureId',
          'bridgeId',
          'bindingId',
          'scopeId',
        ].every((k) => isCryptoCanonicalUuid(value[k])) ||
        !const [
          'sourceInventoryRoot',
          'sourceCommitment',
          'membershipHeadHash',
        ].every((k) => _hash(value[k]))) {
      throw const FormatException('crypto_legacy_invitation_capsule_context');
    }
  }

  bool _hash(Object? value) =>
      value is String && RegExp(r'^[a-f0-9]{64}$').hasMatch(value);
  bool _epoch(Object? value) =>
      value is int && value >= 0 && value <= 9007199254740991;
  void _metadata(
    Map<String, dynamic> value,
    Map<String, dynamic> context,
    String tokenHash,
  ) {
    final recipient = value['recipient'];
    if (value.length != metadataFields.length ||
        value.keys.any((k) => !metadataFields.contains(k)) ||
        value['version'] != 3 ||
        !isCryptoCanonicalUuid(value['invitationId']) ||
        value['scopeId'] != context['scopeId'] ||
        !const ['member', 'viewer'].contains(value['role']) ||
        !const [1, 2, 3].contains(value['legacyContractVersion']) ||
        !_epoch(value['expiresAtEpoch']) ||
        value['acceptedAtEpoch'] != null && !_epoch(value['acceptedAtEpoch']) ||
        value['revokedAtEpoch'] != null && !_epoch(value['revokedAtEpoch']) ||
        value['tokenHash'] != tokenHash ||
        recipient is! Map ||
        recipient.length != 3 ||
        !recipient.containsKey('kind') ||
        !recipient.containsKey('value') ||
        !recipient.containsKey('accountId') ||
        !const ['email', 'username'].contains(recipient['kind']) ||
        recipient['value'] is! String ||
        (recipient['value'] as String).isEmpty ||
        utf8.encode(recipient['value'] as String).length > 320 ||
        (recipient['value'] as String).codeUnits.any(
          (c) => c < 32 || c == 127,
        ) ||
        recipient['accountId'] != null &&
            !isCryptoCanonicalUuid(recipient['accountId'])) {
      throw const FormatException('crypto_legacy_invitation_capsule_metadata');
    }
  }

  SecureKey _key(Map<String, dynamic> context, String tokenHash) {
    if (!_hash(tokenHash)) {
      throw const FormatException('crypto_legacy_invitation_token_hash');
    }
    final rawHash = Uint8List.fromList([
      for (var i = 0; i < 64; i += 2)
        int.parse(tokenHash.substring(i, i + 2), radix: 16),
    ]);
    final material = Uint8List.fromList([
      ...utf8.encode(keyDomain),
      ...CryptoJson.encode({
        'version': 3,
        'serverId': context['serverId'],
        'bridgeId': context['bridgeId'],
      }),
      10,
      ...rawHash,
    ]);
    Uint8List? derived;
    try {
      derived = crypto.sodium.crypto.genericHash(message: material, outLen: 32);
      return crypto.sodium.secureCopy(derived);
    } finally {
      derived?.fillRange(0, derived.length, 0);
      material.fillRange(0, material.length, 0);
      rawHash.fillRange(0, rawHash.length, 0);
    }
  }

  /// A new nonce is generated once; the production journal must retain this
  /// exact returned envelope for retries, never regenerate it after delivery.
  Map<String, dynamic> sealMetadata({
    required Map<String, dynamic> context,
    required Map<String, dynamic> metadata,
    required String oldTokenHash,
  }) {
    _context(context);
    _metadata(metadata, context, oldTokenHash);
    final key = _key(context, oldTokenHash),
        bytes = CryptoJson.encode(metadata);
    try {
      return crypto.encrypt(plaintext: bytes, key: key, context: context);
    } finally {
      key.dispose();
      bytes.fillRange(0, bytes.length, 0);
    }
  }

  Future<Map<String, dynamic>> openUntrustedMetadata({
    required Map<String, dynamic> envelope,
    required Map<String, dynamic> context,
    required String token,
  }) async {
    _context(context);
    if (!RegExp(r'^fhi[123]_[a-f0-9]{64}$').hasMatch(token)) {
      throw const FormatException('crypto_legacy_invitation_token');
    }
    return openUntrustedMetadataFromHash(
      envelope: envelope,
      context: context,
      oldTokenHash: await cryptoSha256(utf8.encode(token)),
    );
  }

  /// Private FILE-source comparison only; this hash is already known by the
  /// host. Successful opening never supplies manager or invitation authority.
  Map<String, dynamic> openUntrustedMetadataFromHash({
    required Map<String, dynamic> envelope,
    required Map<String, dynamic> context,
    required String oldTokenHash,
  }) {
    _context(context);
    if (envelope.length != 5 ||
        !envelope.keys.toSet().containsAll({
          'version',
          'suite',
          'context',
          'nonceBase64',
          'ciphertextBase64',
        })) {
      throw const FormatException('crypto_legacy_invitation_capsule_shape');
    }
    final tokenHash = oldTokenHash, key = _key(context, oldTokenHash);
    Uint8List? bytes;
    try {
      bytes = crypto.decrypt(envelope: envelope, key: key, context: context);
      final value = CryptoJson.decode(bytes);
      if (value is! Map<String, dynamic>) {
        throw const FormatException(
          'crypto_legacy_invitation_capsule_metadata',
        );
      }
      _metadata(value, context, tokenHash);
      return Map.unmodifiable(value);
    } finally {
      key.dispose();
      bytes?.fillRange(0, bytes.length, 0);
    }
  }
}
