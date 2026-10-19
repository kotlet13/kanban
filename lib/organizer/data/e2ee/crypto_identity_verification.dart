import 'dart:convert';

import 'account_directory_v2.dart';
import 'crypto_codec.dart';
import 'crypto_identity_store.dart';
import 'crypto_json.dart';
import 'crypto_sync_repository.dart' show CryptoAuthorityPending;
import 'crypto_directory_promotion.dart';

/// First contact trusts the hosting public-key directory after signed-history
/// replay. Optional safety-code comparison records stronger manual provenance.
/// Both paths securely pin the root; hosting trust can never replace that pin.
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

  Future<void> trustHostDirectory({
    required VerifiedAccountDirectory directory,
    required String expectedServerId,
    required bool Function() isCurrent,
  }) async {
    if (fingerprint(directory) != directory.rootFingerprint) {
      throw const CryptoDirectoryException('directory_root_changed');
    }
    final known = await store.anchor(directory.accountId);
    if (known != null &&
        known['serverId'] == expectedServerId &&
        directory.serverId == expectedServerId &&
        known['fingerprint'] == directory.rootFingerprint &&
        (known['generation'] as int) > directory.generation) {
      // An old invitation keeps its original signed author prefix. It may use
      // an existing newer pin only when a replay connects that exact prefix to
      // the secure head. Neither SQL nor the hosting response can lower it.
      await finishCryptoDirectoryPromotion(
        store: store,
        reducer: AccountDirectoryV2(crypto),
        accountId: directory.accountId,
        serverId: expectedServerId,
        isCurrent: isCurrent,
      );
      VerifiedAccountDirectory? state;
      var included = false;
      await for (final entry in store.streamEntries(directory.accountId)) {
        if (entry['generation'] > known['generation']) break;
        state = await AccountDirectoryV2(crypto).apply(
          previous: state,
          entry: entry,
          serverId: expectedServerId,
          accountId: directory.accountId,
          pinnedRootFingerprint:
              known['genesisFingerprint'] ?? directory.genesisRootFingerprint,
        );
        if (state.headHash == directory.headHash &&
            state.snapshotHash == directory.snapshotHash) {
          included = true;
        }
      }
      final latest = await store.anchor(directory.accountId);
      if (!included ||
          state?.headHash != known['headHash'] ||
          state?.snapshotHash != known['snapshotHash'] ||
          latest?['headHash'] != known['headHash'] ||
          !isCurrent()) {
        throw const CryptoDirectoryException('directory_rollback');
      }
      await requireVerified(directory.accountId, directory.rootFingerprint);
      return;
    }
    await store.pinHostDirectory(
      directory,
      expectedServerId: expectedServerId,
      isCurrent: isCurrent,
    );
    final anchor = await store.anchor(directory.accountId);
    if (!isCurrent() || anchor?['fingerprint'] != directory.rootFingerprint) {
      throw const CryptoDirectoryException('directory_stale_identity');
    }
    // SQL is a display/cache projection. The secure root and method above are
    // the authority even if these rows are missing after a database restore.
    await store.database.execute(
      "INSERT INTO crypto_trusted_identities VALUES(?,?,?,?,?,?,?,?,?) ON CONFLICT(partition,server_id,account_id) DO UPDATE SET root_signing_public=excluded.root_signing_public,root_encryption_public=excluded.root_encryption_public,fingerprint=excluded.fingerprint,verification_method=CASE WHEN excluded.verification_method='safetyCode' AND crypto_trusted_identities.verification_method='safetyCodeReverified' THEN crypto_trusted_identities.verification_method ELSE excluded.verification_method END,compared_head_hash=COALESCE(excluded.compared_head_hash,crypto_trusted_identities.compared_head_hash),compared_generation=COALESCE(excluded.compared_generation,crypto_trusted_identities.compared_generation)",
      [
        store.partition,
        directory.serverId,
        directory.accountId,
        directory.snapshot['rootSigningKeyBase64'],
        directory.snapshot['rootEncryptionKeyBase64'],
        directory.rootFingerprint,
        anchor!['verificationMethod'],
        anchor['verificationMethod'] == 'hostDirectory'
            ? directory.headHash
            : anchor['comparedHeadHash'],
        anchor['verificationMethod'] == 'hostDirectory'
            ? directory.generation
            : anchor['comparedGeneration'],
      ],
    );
  }

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
    final anchor = await store.anchor(accountId);
    if (anchor != null &&
        anchor['fingerprint'] != null &&
        anchor['fingerprint'] != expectedFingerprint) {
      throw const CryptoDirectoryException('directory_root_changed');
    }
    if (anchor == null ||
        anchor['trustState'] != 'verified' ||
        anchor['fingerprint'] != expectedFingerprint) {
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
