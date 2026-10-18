import 'dart:convert';

import 'account_directory_repository.dart';
import 'account_directory_v2.dart';
import 'crypto_identity_store.dart';
import 'crypto_json.dart';
import 'crypto_sync_repository.dart';

/// Read-only consistency with an independently retained secure directory floor.
/// This neither downloads an unreferenced tail nor promotes a scoped contact.
Future<void> requireKnownDirectoryPrefix({
  required AccountDirectoryRepository directory,
  required CryptoIdentityStore store,
  required VerifiedAccountDirectory prefix,
}) async {
  if (!directory.isCurrent()) {
    throw const CryptoDirectoryException('directory_stale_identity');
  }
  final anchor = await store.anchor(prefix.accountId);
  if (anchor == null) {
    if (await store.anchor(prefix.accountId) != null) {
      throw const CryptoAuthorityPending('directory_known_anchor_changed');
    }
    if (!directory.isCurrent()) {
      throw const CryptoDirectoryException('directory_stale_identity');
    }
    return;
  }
  final token = utf8.decode(CryptoJson.encode(anchor));
  final generation = anchor['generation'] as int;
  if (!prefix.includesAnchor(generation, anchor['headHash'])) {
    if (prefix.generation >= generation) {
      throw const FormatException('directory_known_fork');
    }
    VerifiedAccountDirectory? known;
    String? genesis = anchor['genesisFingerprint'];
    var count = 0;
    await for (final entry in store.streamEntries(prefix.accountId)) {
      if (++count > 100000) {
        throw const CryptoAuthorityPending('directory_known_ancestry_pending');
      }
      if (genesis == null) {
        final command =
            CryptoJson.decode(
                  cryptoBase64(
                    (entry['authorization'] as Map)['commandBase64'],
                  ),
                )
                as Map;
        final p = command['payload'] as Map;
        genesis = directory.reducer.crypto.fingerprint(
          cryptoBase64(p['rootSigningKeyBase64'], length: 32),
          cryptoBase64(p['rootEncryptionKeyBase64'], length: 32),
        );
      }
      known = await directory.reducer.apply(
        previous: known,
        entry: entry,
        serverId: prefix.serverId,
        accountId: prefix.accountId,
        pinnedRootFingerprint: genesis,
      );
      if (known.generation >= generation) break;
    }
    if (known == null ||
        known.generation != generation ||
        known.headHash != anchor['headHash'] ||
        known.snapshotHash != anchor['snapshotHash'] ||
        !known.includesAnchor(prefix.generation, prefix.headHash)) {
      throw const CryptoAuthorityPending('directory_known_ancestry_pending');
    }
  } else if (prefix.generation == generation &&
      prefix.snapshotHash != anchor['snapshotHash']) {
    throw const FormatException('directory_known_fork');
  }
  final after = await store.anchor(prefix.accountId);
  if (!directory.isCurrent()) {
    throw const CryptoDirectoryException('directory_stale_identity');
  }
  if (after == null || utf8.decode(CryptoJson.encode(after)) != token) {
    throw const CryptoAuthorityPending('directory_known_anchor_changed');
  }
}
