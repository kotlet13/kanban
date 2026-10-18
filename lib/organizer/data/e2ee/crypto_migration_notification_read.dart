import 'dart:convert';

import 'account_directory_v2.dart';
import 'crypto_business_router.dart';
import 'crypto_json.dart';
import 'crypto_migration_committed_origin.dart';
import 'crypto_migration_notification_codec.dart';
import 'crypto_sync_repository.dart';

/// Historical consent included by a finalized scoped migration publication.
/// This token conveys no current write permission or current scheduler state.
class VerifiedCryptoMigrationNotification {
  VerifiedCryptoMigrationNotification._(this.body, this.proof, this.control);
  final Map<String, dynamic> body, proof;
  final VerifiedCryptoMigrationControl control;
}

class CryptoMigrationNotificationRead {
  CryptoMigrationNotificationRead(this.runtime);
  final CryptoBusinessSession runtime;
  Map<String, dynamic> _map(Object? value) {
    if (value is! Map) {
      throw const FormatException('crypto_notification_migration_evidence');
    }
    return Map<String, dynamic>.from(value);
  }

  Map<String, dynamic> body(Map proof) =>
      _map(CryptoJson.decode(cryptoBase64(proof['commandBase64'])));
  bool _same(Object? a, Object? b) =>
      base64Encode(CryptoJson.encode(a)) == base64Encode(CryptoJson.encode(b));

  /// Withdrawal authenticates only OWN prior consent. It deliberately acquires
  /// no scope/target READ, decrypts no content, and returns no active capability.
  Future<String> verifyOwnWithdrawal(
    Map<String, dynamic> proof,
    String reminderId,
  ) async {
    final own = await runtime.account.directory.requireFresh();
    final b = body(proof), hash = await cryptoSha256(CryptoJson.encode(proof));
    if (b['version'] != 3 ||
        b['operation'] != 'crypto2.migration.schedulingUse' ||
        b['serverId'] != own.serverId ||
        b['accountId'] != own.accountId ||
        b['schedulePutId'] != reminderId) {
      throw const FormatException('scheduling_own_substitution');
    }
    Map<String, dynamic>? first;
    final digests = <String>[];
    String? after;
    while (true) {
      final page = await runtime.account.directory
          .call('crypto2.scheduling.migrationWithdrawalEvidence', {
            'reminderId': reminderId,
            'useProofHash': hash,
            'limit': 20,
            if (after != null) 'afterDigest': after,
          });
      final stable = Map<String, dynamic>.from(page)
        ..remove('digests')
        ..remove('hasMore')
        ..remove('nextAfterDigest');
      if (first == null) {
        first = stable;
      } else if (!_same(first, stable)) {
        throw const FormatException(
          'crypto_notification_migration_page_changed',
        );
      }
      final values = page['digests'];
      if (values is! List ||
          values.length > 20 ||
          digests.length + values.length > 10000000) {
        throw const FormatException('crypto_notification_migration_page');
      }
      for (final value in values) {
        CryptoMigrationNotificationCodec.digest(value);
        if (after != null && after.compareTo(value) >= 0) {
          throw const FormatException('crypto_notification_migration_order');
        }
        digests.add(value);
        after = value;
      }
      if (page['hasMore'] == false) break;
      if (page['hasMore'] != true ||
          values.isEmpty ||
          page['nextAfterDigest'] != after) {
        throw const FormatException('crypto_notification_migration_cursor');
      }
    }
    final certificate = _map(first['certificateAuthorization']),
        command = body(certificate);
    final h = _map(_map(command['payload'])['header']);
    CryptoMigrationNotificationCodec.header(h);
    if (command['operation'] != 'crypto2.migration.notifications.certify' ||
        command['version'] != 2 ||
        command['accountId'] != own.accountId ||
        command['serverId'] != own.serverId ||
        command['signer'] != 'device' ||
        !_same(first['authorization'], proof) ||
        const [
          'serverId',
          'accountId',
          'migrationId',
          'captureId',
          'sourceInventoryRoot',
        ].any((k) => h[k] != b[k]) ||
        await CryptoMigrationNotificationCodec.transformRoot(
              h,
              Stream.fromIterable(digests),
            ) !=
            h['transformRoot']) {
      throw const FormatException('crypto_notification_migration_withdrawal');
    }
    final leaf = _map(first['leaf']);
    if (leaf['bindingId'] != b['bindingId'] ||
        leaf['useProofHash'] != hash ||
        leaf['kind'] != 'reminder' ||
        !digests.contains(
          await CryptoMigrationNotificationCodec.leafDigest(leaf),
        )) {
      throw const FormatException('crypto_notification_migration_leaf');
    }
    final eventProof = _map(first['eventAuthorization']),
        event = body(eventProof);
    final eventHash = await cryptoSha256(
      cryptoBase64(eventProof['commandBase64']),
    );
    final entry = await runtime.account.store.entryByHash(
      own.accountId,
      eventHash,
    );
    final ep = _map(event['payload']);
    if (entry == null ||
        !own.includesAnchor(entry['generation'], entry['headHash']) ||
        !_same(entry['authorization'], eventProof) ||
        first['eventHeadHash'] != entry['headHash'] ||
        first['eventCommandHash'] != eventHash ||
        event['operation'] != 'crypto2.account.migrationAttest' ||
        event['accountId'] != own.accountId ||
        ep['migrationId'] != b['migrationId'] ||
        ep['domain'] != 'content' ||
        ep['scopeToken'] !=
            await CryptoMigrationNotificationCodec.scopeToken(h) ||
        ep['attestationHash'] !=
            await cryptoSha256(CryptoJson.encode(certificate))) {
      throw const CryptoAuthorityPending('scheduling_own_event_pending');
    }
    final pin = await runtime.account.store.anchor(own.accountId);
    if (pin == null) {
      throw const CryptoAuthorityPending('directory_proof_pending');
    }
    final prefixes = <String, VerifiedAccountDirectory>{};
    VerifiedAccountDirectory? state;
    await for (final item in runtime.account.store.streamEntries(
      own.accountId,
    )) {
      state = await runtime.account.directory.reducer.apply(
        previous: state,
        entry: item,
        serverId: own.serverId,
        accountId: own.accountId,
        pinnedRootFingerprint: pin['genesisFingerprint'] ?? pin['fingerprint'],
      );
      if (!own.includesAnchor(state.generation, state.headHash)) {
        throw const FormatException('scheduling_own_fork');
      }
      if (state.headHash == h['authorDirectoryHeadHash'] ||
          state.headHash == b['authorDirectoryHeadHash']) {
        prefixes[state.headHash] = state;
      }
      if (prefixes.containsKey(h['authorDirectoryHeadHash']) &&
          prefixes.containsKey(b['authorDirectoryHeadHash'])) {
        break;
      }
    }
    for (final item in [
      (
        certificate,
        command['deviceId'],
        h['authorDirectoryHeadHash'],
        cryptoDirectoryDomain,
      ),
      (
        proof,
        b['deviceId'],
        b['authorDirectoryHeadHash'],
        'JivieE2EE/migrationSchedulingUse/v3\n',
      ),
    ]) {
      final prefix = prefixes[item.$3];
      if (prefix == null) {
        throw const CryptoAuthorityPending('directory_proof_pending');
      }
      runtime.account.directory.reducer.crypto.verifyDomain(
        item.$1,
        cryptoBase64(
          prefix.activeDevice(item.$2)['signingKeyBase64'],
          length: 32,
        ),
        item.$4,
      );
    }
    if (!runtime.account.directory.isCurrent()) {
      throw const CryptoAuthorityPending('directory_stale_identity');
    }
    return eventHash;
  }

  Future<VerifiedCryptoMigrationNotification> verify({
    required String scopeId,
    required String targetId,
    required Map<String, dynamic> proof,
    bool ownTransform = false,
  }) async {
    final own = await runtime.account.directory.requireFresh();
    final b = body(proof), hash = await cryptoSha256(CryptoJson.encode(proof));
    final expectedHash = ownTransform
        ? await cryptoSha256([
            ...utf8.encode('JivieNotificationTransform/v3\n'),
            ...CryptoJson.encode(proof),
          ])
        : hash;
    final kind = ownTransform ? 'canonical' : null;
    final target = kind == null ? b : _map(b[kind]);
    if (b['version'] != 3 ||
        b['serverId'] != own.serverId ||
        b['operation'] !=
            (ownTransform
                ? 'crypto2.migration.notificationTransform'
                : 'crypto2.migration.schedulingUse') ||
        target['scopeId'] != scopeId ||
        target['targetId'] != targetId ||
        ownTransform &&
            (b['accountId'] != own.accountId || b['kind'] != 'reminder')) {
      throw const FormatException('crypto_notification_migration_binding');
    }
    final read = await runtime.access.readContext(scopeId, target['domain']);
    Map<String, dynamic>? first;
    VerifiedCryptoMigrationControl? verified;
    final digests = <String>[];
    String? after;
    while (true) {
      final page = await runtime.account.directory
          .call('crypto2.scheduling.migrationEvidence', {
            'scopeId': scopeId,
            'targetId': targetId,
            ownTransform ? 'transformHash' : 'useProofHash': expectedHash,
            if (after != null) 'afterDigest': after,
            'limit': 20,
          });
      final stable = Map<String, dynamic>.from(page)
        ..remove('digests')
        ..remove('hasMore')
        ..remove('nextAfterDigest');
      if (first == null) {
        first = stable;
        if (page['version'] != 3 || !_same(page['authorization'], proof)) {
          throw const FormatException(
            'crypto_notification_migration_substitution',
          );
        }
        verified = await CryptoMigrationCommittedOrigin(runtime.access)
            .verifyControlEvidence(
              domain: 'content',
              kind: 'notifications',
              evidence: _map(page['activationEvidence']),
              contributionAuthorization: _map(
                page['contributionAuthorization'],
              ),
              contributionEventAuthorization: _map(
                page['contributionEventAuthorization'],
              ),
              certificateAuthorization: _map(page['certificateAuthorization']),
              certificateEventAuthorization: _map(
                page['certificateEventAuthorization'],
              ),
            );
        final h = verified.contributionHeader,
            contributor = body(_map(page['contributionAuthorization']));
        if (contributor['accountId'] != b['accountId'] ||
            verified.activation['scopeId'] != scopeId ||
            h['migrationId'] != b['migrationId'] ||
            h['captureId'] != b['captureId'] ||
            h['sourceInventoryRoot'] != b['sourceInventoryRoot']) {
          throw const FormatException(
            'crypto_notification_migration_contributor',
          );
        }
      } else if (!_same(first, stable)) {
        throw const FormatException(
          'crypto_notification_migration_page_changed',
        );
      }
      final values = page['digests'];
      if (values is! List || values.length > 20) {
        throw const FormatException('crypto_notification_migration_page');
      }
      for (final value in values) {
        CryptoMigrationNotificationCodec.digest(value);
        if (after != null && after.compareTo(value) >= 0 ||
            digests.length >= verified!.controlLeaf['selectionCount']) {
          throw const FormatException('crypto_notification_migration_order');
        }
        digests.add(value);
        after = value;
      }
      if (page['hasMore'] == false) break;
      if (page['hasMore'] != true ||
          values.isEmpty ||
          page['nextAfterDigest'] != after) {
        throw const FormatException('crypto_notification_migration_cursor');
      }
    }
    final leaf = _map(first['leaf']);
    if (leaf['bindingId'] != b['bindingId'] ||
        leaf['kind'] != 'reminder' ||
        (ownTransform
            ? leaf['transformHash'] != expectedHash
            : leaf['useProofHash'] != hash) ||
        !digests.contains(
          await CryptoMigrationNotificationCodec.leafDigest(leaf),
        )) {
      throw const FormatException('crypto_notification_migration_leaf');
    }
    final common = {
      'version': 3,
      for (final key in const [
        'serverId',
        'migrationId',
        'captureId',
        'accountId',
        'sourceInventoryRoot',
      ])
        key: b[key],
    };
    if (await CryptoMigrationNotificationCodec.selectionRoot(
          common,
          verified!.controlLeaf['selectionCount'],
          Stream.fromIterable(digests),
        ) !=
        verified.controlLeaf['selectionRoot']) {
      throw const FormatException('crypto_notification_migration_root');
    }
    final prefix = await runtime.access.directoryAt(
      scopeId: scopeId,
      scopeHeadHash: read.headHash,
      accountId: b['accountId'],
      directoryHeadHash: b['authorDirectoryHeadHash'],
      online: true,
    );
    final device = prefix.activeDevice(b['deviceId']);
    runtime.account.directory.reducer.crypto.verifyDomain(
      proof,
      cryptoBase64(device['signingKeyBase64'], length: 32),
      ownTransform
          ? 'JivieE2EE/notificationTransform/v3\n'
          : 'JivieE2EE/migrationSchedulingUse/v3\n',
    );
    if (!runtime.account.directory.isCurrent() ||
        (await runtime.access.readContext(
              scopeId,
              target['domain'],
            )).headHash !=
            read.headHash) {
      throw const CryptoAuthorityPending(
        'crypto_notification_migration_read_changed',
      );
    }
    return VerifiedCryptoMigrationNotification._(b, proof, verified);
  }
}
