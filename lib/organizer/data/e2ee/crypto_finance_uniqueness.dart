import 'dart:convert';
import 'dart:typed_data';

import 'crypto_json.dart';
import 'crypto_sync_repository.dart';
import 'account_directory_v2.dart';
import 'session_crypto_access.dart';
import 'crypto_project_relocation_target.dart';

/// Stable private uniqueness across finance rotations. Only verified ancestry
/// chooses the earliest finance key; an unavailable historical key is pending.
/// These tags do not hide metadata from a holder of that historical key.
class CryptoFinanceUniqueTags {
  CryptoFinanceUniqueTags(this.access);
  final SessionCryptoAccess access;
  final _bases = <String, ({String anchor, int epoch})>{};

  Future<String> tag(
    String scopeId, {
    required String purpose,
    required Object value,
    CryptoMigrationCandidate? migrationCandidate,
    PreparedProjectRelocationTarget? relocationTarget,
  }) async {
    if (!RegExp(r'^[A-Za-z][A-Za-z0-9]{0,63}$').hasMatch(purpose)) {
      throw const FormatException('crypto_finance_unique_purpose');
    }
    final account = access.account;
    if (migrationCandidate != null && relocationTarget != null) {
      throw const FormatException('crypto_finance_unique_candidate_context');
    }
    final relocationOwnHead = await relocationTarget?.requireFinanceTagContext(
      access,
      scopeId,
    );
    if (migrationCandidate != null &&
        (!migrationCandidate.isFor(access, scopeId) ||
            migrationCandidate.head.epoch != 1 ||
            migrationCandidate.head.body['previousHeadHash'] !=
                cryptoZeroHash ||
            migrationCandidate.head.body['keyIds']['finance'] == null)) {
      throw const FormatException('crypto_finance_unique_migration_context');
    }
    final head =
        relocationTarget?.head ??
        migrationCandidate?.head ??
        await access.currentHead(scopeId);
    final own = await account.store.anchor(account.directory.accountId);
    if (own == null) {
      throw const CryptoAuthorityPending('crypto_finance_unique_basis');
    }
    final pin = base64Encode(
      CryptoJson.encode({
        'headHash': head.headHash,
        'root': own['rootSigningKeyBase64'],
        'identityEpochId': own['identityEpochId'],
      }),
    );
    var basis = migrationCandidate == null && relocationTarget == null
        ? _bases[scopeId]
        : (anchor: pin, epoch: 1);
    if (basis == null || basis.anchor != pin) {
      var cursor = head;
      int? epoch;
      while (true) {
        if (cursor.body['keyIds']['finance'] != null) epoch = cursor.epoch;
        if (cursor.body['previousHeadHash'] == cryptoZeroHash) break;
        cursor = await access.headAt(scopeId, cursor.body['previousHeadHash']);
      }
      if (epoch == null) {
        throw const CryptoAuthorityPending('crypto_finance_unique_basis');
      }
      basis = (anchor: pin, epoch: epoch);
      _bases[scopeId] = basis;
    }
    final key = relocationTarget != null
        ? CryptoKeyLease.owned(await relocationTarget.key('finance'))
        : migrationCandidate == null
        ? await access.getScopeKey(scopeId, 'finance', basis.epoch)
        : await migrationCandidate.key('finance');
    Uint8List? derivedBytes;
    try {
      final sodium = account.directory.reducer.crypto.sodium;
      derivedBytes = sodium.crypto.genericHash(
        key: key.key,
        outLen: 32,
        message: Uint8List.fromList([
          ...utf8.encode('JivieFinanceUniqueKey/v2\n'),
          ...CryptoJson.encode({
            'version': 2,
            'serverId': account.directory.session.profile.serverId,
            'scopeId': scopeId,
            'domain': 'finance',
            'purpose': purpose,
          }),
        ]),
      );
      final derived = sodium.secureCopy(derivedBytes);
      try {
        final digest = sodium.crypto.genericHash(
          key: derived,
          outLen: 32,
          message: Uint8List.fromList([
            ...utf8.encode('JivieFinanceUnique/v2\n'),
            ...CryptoJson.encode(value),
          ]),
        );
        final tag = digest
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join();
        await relocationTarget?.requireFinanceTagContext(
          access,
          scopeId,
          ownHeadHash: relocationOwnHead,
        );
        return tag;
      } finally {
        derived.dispose();
      }
    } finally {
      derivedBytes?.fillRange(0, derivedBytes.length, 0);
      key.release();
    }
  }
}
