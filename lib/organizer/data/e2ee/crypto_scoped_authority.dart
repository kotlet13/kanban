import 'dart:convert';
import 'dart:typed_data';

import 'account_directory_v2.dart';
import 'crypto_json.dart';
import 'crypto_anchor_lock.dart';
import 'crypto_sync_repository.dart';
import 'session_crypto_access.dart';

/// A child-scoped delegation authenticates one exact foreign issuer without
/// making that issuer a global contact or disclosing its parent roster/keys.
class CryptoScopedAuthority {
  CryptoScopedAuthority(this.access);
  final SessionCryptoAccess access;
  static final _queues = <String, Future<void>>{};

  Future<VerifiedAccountDirectory> current({
    required String scopeId,
    required String scopeHeadHash,
    required String accountId,
    required String signingPublicKey,
    required String encryptionPublicKey,
    required String identityEpochId,
    required String deviceSnapshotHash,
  }) async {
    final key = '${access.account.store.partition}:$scopeId:$accountId';
    final task = (_queues[key] ?? Future<void>.value()).then((_) async {
      void active() {
        if (!access.account.directory.isCurrent()) {
          throw const FormatException('scoped_authority_identity_changed');
        }
      }

      active();
      final status = await access.account.directory.call(
        'crypto2.directory.status',
        {'scopeId': scopeId, 'headHash': scopeHeadHash, 'accountId': accountId},
      );
      final directory = await access.directoryAt(
        scopeId: scopeId,
        scopeHeadHash: scopeHeadHash,
        accountId: accountId,
        directoryHeadHash: status['headHash'],
        online: true,
        allowUnverifiedContact: true,
      );
      if (directory.snapshot['rootSigningKeyBase64'] != signingPublicKey ||
          directory.snapshot['rootEncryptionKeyBase64'] !=
              encryptionPublicKey ||
          directory.identityEpochId != identityEpochId ||
          directory.deviceSnapshotHash != deviceSnapshotHash) {
        throw const CryptoAuthorityPending('scoped_authority_changed');
      }
      return withCryptoAnchorLock(access.account.store.partition, () async {
        final secureKey = 'scopedAuthority2:$key';
        final saved = await access.account.store.secure.read(secureKey);
        final floor = saved == null
            ? null
            : CryptoJson.decode(Uint8List.fromList(utf8.encode(saved))) as Map;
        if (floor != null) {
          if (directory.generation < floor['generation'] ||
              !directory.includesAnchor(
                floor['generation'] as int,
                floor['headHash'] as String,
              )) {
            throw const FormatException('scoped_authority_known_fork');
          }
        }
        active();
        await access.account.store.secure.write(
          secureKey,
          utf8.decode(
            CryptoJson.encode({
              'generation': directory.generation,
              'headHash': directory.headHash,
            }),
          ),
        );
        active();
        return directory;
      });
    });
    final marker = task.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    _queues[key] = marker;
    try {
      return await task;
    } finally {
      if (identical(_queues[key], marker)) _queues.remove(key);
    }
  }
}
