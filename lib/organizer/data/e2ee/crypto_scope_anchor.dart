import 'dart:convert';
import 'dart:typed_data';

import 'account_crypto_store.dart';
import 'account_directory_v2.dart';
import 'crypto_anchor_lock.dart';
import 'crypto_json.dart';

/// Cheap directional check over an already verified exact directory prefix.
/// This grants no current authority: callers must separately verify freshness.
bool cryptoScopeKnownForwardRoot({
  required Map<String, dynamic> known,
  required VerifiedAccountDirectory referenced,
}) {
  final generation = known['generation'], hash = known['headHash'];
  return generation is int &&
      generation > 0 &&
      hash is String &&
      known['pendingRootTransition'] == null &&
      known['trustState'] == 'verified' &&
      known['serverId'] == referenced.serverId &&
      known['accountId'] == referenced.accountId &&
      known['fingerprint'] is String &&
      known['fingerprint'] == referenced.rootFingerprint &&
      referenced.generation > generation &&
      referenced.includesAnchor(generation, hash) &&
      known['rootSigningKeyBase64'] is String &&
      known['rootEncryptionKeyBase64'] is String &&
      known['rootSigningKeyBase64'] ==
          referenced.snapshot['rootSigningKeyBase64'] &&
      known['rootEncryptionKeyBase64'] ==
          referenced.snapshot['rootEncryptionKeyBase64'];
}

/// Resolves only an older local pin, never a newer revocation or root handoff.
/// Both directories must already have complete signed reducer verification;
/// the caller additionally obtains [current] through its fresh scoped status
/// check and rechecks the same secure pin/session before using this result.
bool cryptoScopeForwardDirectoryReference({
  required Map<String, dynamic> known,
  required VerifiedAccountDirectory referenced,
  required VerifiedAccountDirectory current,
}) =>
    cryptoScopeKnownForwardRoot(known: known, referenced: referenced) &&
    current.serverId == referenced.serverId &&
    current.accountId == referenced.accountId &&
    current.includesAnchor(referenced.generation, referenced.headHash) &&
    current.deviceSnapshotHash == referenced.deviceSnapshotHash &&
    current.identityEpochId == referenced.identityEpochId &&
    current.snapshot['rootSigningKeyBase64'] ==
        referenced.snapshot['rootSigningKeyBase64'] &&
    current.snapshot['rootEncryptionKeyBase64'] ==
        referenced.snapshot['rootEncryptionKeyBase64'];

/// Commits an already authenticated scope prefix. Re-read inside the shared
/// lock: a candidate verified before another observer advanced the floor must
/// intersect that observer's exact head, including when its epoch is higher.
Future<void> commitCryptoScopeAnchor({
  required String partition,
  required String key,
  required AccountCryptoStore secure,
  required int epoch,
  required String headHash,
  required Map<int, String> verifiedPrefix,
  required bool Function() isCurrent,
  Future<void> Function(Map<String, dynamic>? floor)? validateCurrent,
}) => withCryptoAnchorLock(partition, () async {
  final previous = await secure.read(key);
  final floor = previous == null
      ? null
      : Map<String, dynamic>.from(
          CryptoJson.decode(Uint8List.fromList(utf8.encode(previous))) as Map,
        );
  if (floor != null) {
    final knownEpoch = floor['epoch'] as int;
    if (knownEpoch > epoch) throw const FormatException('scope_known_rollback');
    if (verifiedPrefix[knownEpoch] != floor['headHash']) {
      throw const FormatException('scope_known_fork');
    }
  }
  await validateCurrent?.call(floor);
  if (!isCurrent()) throw const FormatException('crypto_identity_changed');
  await secure.write(
    key,
    utf8.decode(CryptoJson.encode({'epoch': epoch, 'headHash': headHash})),
  );
});
