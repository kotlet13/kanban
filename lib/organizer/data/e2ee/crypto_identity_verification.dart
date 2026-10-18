import 'dart:convert';

import 'account_directory_v2.dart';
import 'crypto_codec.dart';
import 'crypto_identity_store.dart';
import 'crypto_json.dart';
import 'crypto_sync_repository.dart' show CryptoAuthorityPending;

/// First-contact verification is an explicit out-of-band full safety-code
/// comparison. A server response and old-root continuity cannot create this pin.
class CryptoIdentityVerification {
  CryptoIdentityVerification(this.crypto, this.store);
  final CryptoCodec crypto;
  final CryptoIdentityStore store;
  Future<String> safetyCode(VerifiedAccountDirectory directory) async {
    final hash = await cryptoSha256(
      CryptoJson.encode({
        'version': 2,
        'purpose': 'identitySafetyCode',
        'serverId': directory.serverId,
        'accountId': directory.accountId,
        'rootSigningKeyBase64': directory.snapshot['rootSigningKeyBase64'],
        'rootEncryptionKeyBase64':
            directory.snapshot['rootEncryptionKeyBase64'],
        'recoveryRootEpochId': directory.snapshot['recoveryRootEpochId'],
      }),
    );
    return [
      for (var i = 0; i < hash.length; i += 8) hash.substring(i, i + 8),
    ].join(' ');
  }

  String fingerprint(VerifiedAccountDirectory directory) => crypto.fingerprint(
    cryptoBase64(directory.snapshot['rootSigningKeyBase64'], length: 32),
    cryptoBase64(directory.snapshot['rootEncryptionKeyBase64'], length: 32),
  );
  Future<void> compareAndPin({
    required VerifiedAccountDirectory directory,
    required String externallyComparedSafetyCode,
    required int externallyComparedGeneration,
    required String externallyComparedHeadHash,
  }) async {
    final expected = (await safetyCode(directory)).replaceAll(' ', '');
    final actual = externallyComparedSafetyCode.toLowerCase().replaceAll(
      RegExp(r'[\s-]'),
      '',
    );
    if (actual.length != 64 ||
        actual != expected ||
        externallyComparedGeneration != directory.generation ||
        externallyComparedHeadHash != directory.headHash) {
      throw const CryptoDirectoryException('identity_safety_code_mismatch');
    }
    await store.pinComparedIdentity(directory, fingerprint(directory));
    final previous = (await store.database.rows(
      'SELECT fingerprint FROM crypto_trusted_identities WHERE partition=? AND server_id=? AND account_id=?',
      [store.partition, directory.serverId, directory.accountId],
    )).firstOrNull;
    // Explicit comparison deliberately replaces an old pin after a root change;
    // remembered history and pending operations remain untouched.
    await store.database.execute(
      'INSERT INTO crypto_trusted_identities VALUES(?,?,?,?,?,?,?,?,?) ON CONFLICT(partition,server_id,account_id) DO UPDATE SET root_signing_public=excluded.root_signing_public,root_encryption_public=excluded.root_encryption_public,fingerprint=excluded.fingerprint,verification_method=excluded.verification_method,compared_head_hash=excluded.compared_head_hash,compared_generation=excluded.compared_generation',
      [
        store.partition,
        directory.serverId,
        directory.accountId,
        directory.snapshot['rootSigningKeyBase64'],
        directory.snapshot['rootEncryptionKeyBase64'],
        fingerprint(directory),
        previous == null ? 'safetyCode' : 'safetyCodeReverified',
        directory.headHash,
        directory.generation,
      ],
    );
  }

  Future<void> requireVerified(
    String accountId,
    String expectedFingerprint,
  ) async {
    final rows = await store.database.rows(
      'SELECT fingerprint FROM crypto_trusted_identities WHERE partition=? AND account_id=?',
      [store.partition, accountId],
    );
    if (rows.length != 1 || rows.single['fingerprint'] != expectedFingerprint) {
      throw const CryptoAuthorityPending('identity_verification_required');
    }
  }

  /// A shareable card contains public information only. Its head is useful for
  /// comparison but does not authenticate itself when copied from the server.
  Future<String> publicCard(VerifiedAccountDirectory directory) async =>
      utf8.decode(
        CryptoJson.encode({
          'version': 2,
          'purpose': 'identityVerification',
          'serverId': directory.serverId,
          'accountId': directory.accountId,
          'safetyCode': await safetyCode(directory),
          'generation': directory.generation,
          'headHash': directory.headHash,
        }),
      );
}
