import 'dart:convert';
import 'dart:typed_data';

import 'package:sodium/sodium.dart';

import '../recovery_bundle.dart';
import 'account_directory_repository.dart';
import 'account_directory_v2.dart';
import 'crypto_json.dart';
import 'recovery_file_codec.dart';

/// A deliberately non-mutating check against an independently trusted local
/// directory and a new authenticated server status. It checks account keys,
/// including the account section of combined files, not installation recovery
/// or the availability/completeness of encrypted user data.
class AccountRecoveryFileCheck {
  AccountRecoveryFileCheck(this.directory);
  final AccountDirectoryRepository directory;

  void _current() {
    if (!directory.isCurrent() ||
        directory.store.partition != directory.session.profile.partition) {
      throw const CryptoDirectoryException('directory_stale_identity');
    }
  }

  Future<void> check(Uint8List externalFile) async {
    _current();
    // Snapshot caller-owned bytes before the first await; never retain them.
    Uint8List? file;
    Uint8List? ciphertext;
    try {
      file = RecoveryBundleCodec.accountBytes(externalFile);
      final codec = RecoveryFileCodec(directory.reducer.crypto);
      final inspected = codec.inspect(
        file,
        serverId: directory.session.profile.serverId,
        accountId: directory.accountId,
      );
      final fingerprint = inspected['fingerprint'] as String;
      inspected.clear();
      final before = await directory.store.anchor(directory.accountId);
      _current();
      if (before == null ||
          before['trustState'] != 'verified' ||
          before['pendingRootTransition'] != null ||
          before['serverId'] != directory.session.profile.serverId ||
          before['accountId'] != directory.accountId ||
          before['fingerprint'] != fingerprint) {
        throw const CryptoDirectoryException('directory_recovery_identity');
      }
      // This replay neither completes pending promotions nor fills live caches.
      final trusted = await directory.replayFileAnchoredCandidate(fingerprint);
      _current();
      trusted.activeDevice(directory.session.profile.deviceId);
      if (trusted.deviceSnapshotHash != before['deviceSnapshotHash'] ||
          trusted.identityEpochId != before['identityEpochId'] ||
          trusted.snapshot['rootSigningKeyBase64'] !=
              before['rootSigningKeyBase64'] ||
          trusted.snapshot['rootEncryptionKeyBase64'] !=
              before['rootEncryptionKeyBase64']) {
        throw const CryptoDirectoryException('directory_recovery_identity');
      }
      final status = await directory.recoveryFileCheckStatus();
      _current();
      // Do not silently refresh or establish trust. A changed head requires a
      // separate normal sync and a new explicit check. A server can still hide
      // a newer prefix: this verifies the observed head, not global freshness.
      if (status['initialized'] != true ||
          status['serverId'] != trusted.serverId ||
          status['accountId'] != trusted.accountId ||
          status['generation'] != trusted.generation ||
          status['headHash'] != trusted.headHash ||
          status['snapshotHash'] != trusted.snapshotHash ||
          status['deviceSnapshotHash'] != trusted.deviceSnapshotHash) {
        throw const CryptoDirectoryException(
          'directory_recovery_status_changed',
        );
      }
      ciphertext = cryptoBase64(
        status['keyringCiphertextBase64'],
        max: 256 * 1024,
      );
      if (await cryptoSha256(ciphertext) !=
          trusted.snapshot['recoveryRootCiphertextHash']) {
        throw const CryptoDirectoryException('directory_recovery_ciphertext');
      }
      _current();
      final encrypted = CryptoJson.decode(ciphertext) as Map<String, dynamic>;
      final root = codec.open(
        file: file,
        encryptedRoot: encrypted,
        serverId: trusted.serverId,
        accountId: trusted.accountId,
        expectedFingerprint: trusted.rootFingerprint,
      );
      // open authenticates/decrypts the real root envelope, derives both key
      // pairs and checks their public keys/fingerprint; retain no root lease.
      root.dispose();
      final after = await directory.store.anchor(directory.accountId);
      _current();
      if (after == null ||
          base64Encode(CryptoJson.encode(before)) !=
              base64Encode(CryptoJson.encode(after))) {
        throw const CryptoDirectoryException(
          'directory_recovery_status_changed',
        );
      }
    } on FormatException {
      throw const CryptoDirectoryException('directory_recovery_file_invalid');
    } on SodiumException {
      throw const CryptoDirectoryException('directory_recovery_file_invalid');
    } finally {
      ciphertext?.fillRange(0, ciphertext.length, 0);
      file?.fillRange(0, file.length, 0);
    }
  }
}
