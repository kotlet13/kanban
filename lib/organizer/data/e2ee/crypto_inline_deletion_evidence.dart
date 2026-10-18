import 'dart:convert';

import 'account_directory_v2.dart';
import 'crypto_inline_deletion_codec.dart';
import 'crypto_json.dart';
import 'crypto_record_proof_codec.dart';
import 'crypto_scope_deletion_codec.dart';
import 'crypto_sync_repository.dart';
import 'session_crypto_access.dart';

/// A purpose tag is never sufficient. Every target is checked against the
/// complete signed publication and its exact scoped leaf before ordinary
/// author/history admission. No private sibling descriptors are requested.
class CryptoInlineDeletionEvidence {
  CryptoInlineDeletionEvidence(this.access, {required this.ordinaryAuthority});
  final SessionCryptoAccess access;
  final Future<CryptoRecordAuthority> Function(Map<String, dynamic>)
  ordinaryAuthority;
  CryptoRecordProofCodec get codec =>
      CryptoRecordProofCodec(access.account.directory.reducer.crypto);
  static Map<String, dynamic> _map(Object? value) {
    if (value is! Map) {
      throw const FormatException('crypto_inline_delete_evidence_shape');
    }
    return Map<String, dynamic>.from(value);
  }

  static Map<String, dynamic> _body(Map<String, dynamic> proof) =>
      _map(CryptoJson.decode(cryptoBase64(proof['commandBase64'])));
  static bool _same(Object? a, Object? b) =>
      base64Encode(CryptoJson.encode(a)) == base64Encode(CryptoJson.encode(b));

  Future<CryptoRecordAuthority> authority(Map<String, dynamic> record) async {
    codec.validateUntrustedRecord(record);
    final tag = _map((record['metadata'] as Map)['inlineDeletion']);
    CryptoScopeDeletionCodec.fields(tag, {'version', 'actionId', 'planHash'});
    if (tag['version'] != 2 ||
        record['deleted'] != true ||
        record['expectedRevision'] < 1) {
      throw const FormatException('crypto_inline_delete_record');
    }
    final scope = record['scopeId'] as String;
    final ownBefore = await access.account.directory.requireFresh();
    ownBefore.activeDevice(access.account.deviceId);
    final current = await access.withVerifiedOperation(
      () => access.currentHead(scope, online: true),
      freshBoundary: true,
    );
    final me = current.member(access.account.directory.accountId);
    if (record['domain'] == 'finance' && me['financeRole'] == 'none') {
      throw const CryptoAuthorityPending('finance_read_required');
    }
    final selector = <String, dynamic>{
      'scopeId': scope,
      'actionId': tag['actionId'],
      'id': record['id'],
      'recordBodyHash': await cryptoSha256(CryptoJson.encode(record)),
      'limit': 32,
    };
    var page = await access.account.directory.call(
      'crypto2.inlineDelete.evidence',
      selector,
    );
    final first = Map<String, dynamic>.from(page);
    final certProof = _map(first['certificateProof']),
        cert = _body(certProof),
        event = _map(first['eventAuthorization']),
        eventBody = _body(event),
        ep = _map(eventBody['payload']);
    CryptoInlineDeletionCodec.certificate(cert);
    final original = _map(first['recordProof']),
        batch = _map(first['batchCommitment']),
        descriptor = _map(first['descriptor']);
    CryptoInlineDeletionCodec.tombstoneDescriptor(descriptor);
    final proofHash = await codec.digest(original),
        batchHash = await codec.digest(batch);
    if (!_same(_body(original), record) ||
        cert['serverId'] != record['serverId'] ||
        cert['scopeId'] != scope ||
        cert['actionId'] != tag['actionId'] ||
        cert['planHash'] != tag['planHash'] ||
        cert['membershipHeadHash'] != record['membershipHeadHash'] ||
        cert['accessRevision'] != record['accessRevision'] ||
        cert['accountId'] != record['accountId'] ||
        cert['deviceId'] != record['deviceId'] ||
        !_same(descriptor, {
          'id': record['id'],
          'domain': record['domain'],
          'type': record['type'],
          'expectedRevision': record['expectedRevision'],
          'previousRecordHash': record['previousRecordHash'],
          'recordProofHash': proofHash,
          'batchCommitmentHash': batchHash,
        })) {
      throw const FormatException('crypto_inline_delete_target_binding');
    }
    final hashes = <String>[],
        batchDigests = (first['batchDigests'] as List).cast<String>();
    String? after;
    var pages = 0;
    while (true) {
      if (++pages > (CryptoInlineDeletionCodec.maxRecords + 31) ~/ 32 ||
          !_same(page['certificateProof'], certProof) ||
          !_same(page['eventAuthorization'], event) ||
          !_same(page['descriptor'], descriptor) ||
          !_same(page['recordProof'], original) ||
          !_same(page['batchCommitment'], batch) ||
          page['eventHeadHash'] != first['eventHeadHash'] ||
          page['eventCommandHash'] != first['eventCommandHash'] ||
          !_same(page['batchDigests'], batchDigests)) {
        throw const FormatException(
          'crypto_inline_delete_evidence_substitution',
        );
      }
      final values = page['tombstoneDigests'];
      if (values is! List || values.length > 32) {
        throw const FormatException('crypto_inline_delete_evidence_page');
      }
      for (final raw in values) {
        CryptoScopeDeletionCodec.digest(raw);
        if (after != null && after.compareTo(raw) >= 0 ||
            hashes.length >= cert['tombstoneCount']) {
          throw const FormatException('crypto_inline_delete_evidence_order');
        }
        hashes.add(raw);
        after = raw;
      }
      if (page['hasMore'] == false) break;
      if (page['hasMore'] != true ||
          values.isEmpty ||
          page['nextAfterHash'] != after) {
        throw const FormatException('crypto_inline_delete_evidence_cursor');
      }
      page = await access.account.directory.call(
        'crypto2.inlineDelete.evidence',
        {...selector, 'afterHash': after},
      );
    }
    if (hashes.length != cert['tombstoneCount'] ||
        batchDigests.length != cert['batchCount'] ||
        !hashes.contains(
          await CryptoInlineDeletionCodec.tombstoneLeaf(descriptor),
        ) ||
        !batchDigests.contains(batchHash) ||
        await CryptoInlineDeletionCodec.tombstoneDigestRoot(hashes) !=
            cert['tombstoneRoot'] ||
        await CryptoInlineDeletionCodec.batchRoot(batchDigests) !=
            cert['batchRoot']) {
      throw const FormatException('crypto_inline_delete_evidence_inclusion');
    }
    final head = await access.headAt(scope, cert['membershipHeadHash']);
    final member = head.member(cert['accountId']);
    if (head.epoch != record['epoch'] ||
        head.accessRevision != cert['accessRevision'] ||
        member['role'] == 'viewer' ||
        record['domain'] == 'finance' && member['financeRole'] != 'write') {
      throw const FormatException('crypto_inline_delete_author');
    }
    final prefix = await access.directoryAt(
      scopeId: scope,
      scopeHeadHash: head.headHash,
      accountId: cert['accountId'],
      directoryHeadHash: cert['authorDirectoryHeadHash'],
      online: true,
      allowUnverifiedContact: true,
    );
    if (prefix.deviceSnapshotHash != member['deviceSnapshotHash'] ||
        prefix.snapshot['rootSigningKeyBase64'] !=
            member['rootSigningKeyBase64'] ||
        prefix.snapshot['rootEncryptionKeyBase64'] !=
            member['rootEncryptionKeyBase64']) {
      throw const FormatException('crypto_inline_delete_directory_binding');
    }
    final key = cryptoBase64(
      prefix.activeDevice(cert['deviceId'])['signingKeyBase64'],
      length: 32,
    );
    codec.crypto.verifyDomain(certProof, key, CryptoInlineDeletionCodec.domain);
    CryptoScopeDeletionCodec.fields(eventBody, {
      'version',
      'operation',
      'serverId',
      'accountId',
      'deviceId',
      'requestId',
      'signer',
      'payload',
    });
    CryptoScopeDeletionCodec.fields(ep, {
      'expectedGeneration',
      'previousHeadHash',
      'identityEpochId',
      'resultingSnapshotHash',
      'scopeToken',
      'certificateHash',
    });
    if (eventBody['version'] != 2 ||
        eventBody['operation'] != 'crypto2.account.scopeDeletion' ||
        eventBody['signer'] != 'device' ||
        eventBody['serverId'] != cert['serverId'] ||
        eventBody['accountId'] != cert['accountId'] ||
        eventBody['deviceId'] != cert['deviceId'] ||
        eventBody['requestId'] != cert['requestId'] ||
        ep['previousHeadHash'] != prefix.headHash ||
        ep['expectedGeneration'] != prefix.generation ||
        ep['identityEpochId'] != prefix.identityEpochId ||
        ep['resultingSnapshotHash'] != prefix.snapshotHash ||
        ep['scopeToken'] != await CryptoInlineDeletionCodec.token(cert) ||
        ep['certificateHash'] != await codec.digest(certProof)) {
      throw const FormatException('crypto_inline_delete_event_binding');
    }
    codec.crypto.verifyDomain(event, key, cryptoDirectoryDomain);
    final commandHash = await cryptoSha256(
      cryptoBase64(event['commandBase64']),
    );
    final eventHash = await cryptoSha256([
      ...utf8.encode(cryptoDirectoryLogDomain),
      ...CryptoJson.encode({
        'serverId': cert['serverId'],
        'accountId': cert['accountId'],
        'generation': prefix.generation + 1,
        'previousHeadHash': prefix.headHash,
        'commandHash': commandHash,
        'signatureBase64': event['signatureBase64'],
      }),
    ]);
    if (first['eventHeadHash'] != eventHash ||
        first['eventCommandHash'] != commandHash) {
      throw const FormatException('crypto_inline_delete_event_inclusion');
    }
    final included = await access.directoryAt(
      scopeId: scope,
      scopeHeadHash: head.headHash,
      accountId: cert['accountId'],
      directoryHeadHash: eventHash,
      online: true,
      allowUnverifiedContact: true,
    );
    if (included.generation != prefix.generation + 1 ||
        !included.includesAnchor(prefix.generation, prefix.headHash) ||
        included.snapshotHash != prefix.snapshotHash) {
      throw const FormatException('crypto_inline_delete_event_inclusion');
    }
    var ownPublication = false;
    if (cert['accountId'] == access.account.directory.accountId) {
      final own = await access.account.directory.cachedVerifiedDirectory();
      ownPublication = own.includesAnchor(
        included.generation,
        included.headHash,
      );
    }
    await codec.verifyWire(
      serverId: cert['serverId'],
      wire: {
        for (final field in [
          'scopeId',
          'id',
          'type',
          'deleted',
          'epoch',
          'envelopeBase64',
          'metadata',
        ])
          field: record[field],
        'revision': record['expectedRevision'] + 1,
        'authorization': {'recordProof': original, 'batchCommitment': batch},
      },
      trustedSigningKey: key,
      currentEpoch: false,
      closedRecordProofHash: proofHash,
    );
    return access.withVerifiedOperation(() async {
      if (!access.account.directory.isCurrent()) {
        throw const CryptoAuthorityPending(
          'crypto_inline_delete_identity_changed',
        );
      }
      final ownAfter = await access.account.directory.requireFresh();
      ownAfter.activeDevice(access.account.deviceId);
      final read = await access.readContext(scope, record['domain']);
      if (ownAfter.accountId != ownBefore.accountId ||
          ownAfter.identityEpochId != ownBefore.identityEpochId ||
          ownAfter.deviceSnapshotHash != ownBefore.deviceSnapshotHash ||
          ownAfter.rootFingerprint != ownBefore.rootFingerprint ||
          read.headHash != current.headHash ||
          read.epoch != current.epoch ||
          read.accessRevision != current.accessRevision) {
        throw const CryptoAuthorityPending('crypto_inline_delete_read_changed');
      }
      try {
        final ordinary = await ordinaryAuthority(record);
        if (ordinary.closedRecordProofHash != null &&
                ordinary.closedRecordProofHash != proofHash ||
            base64Encode(ordinary.signingKey) != base64Encode(key)) {
          throw const FormatException(
            'crypto_inline_delete_closure_substitution',
          );
        }
      } on CryptoAuthorityPending catch (error) {
        if (!ownPublication ||
            !const {
              'history_freshness_pending',
              'history_checkpoint_pending',
            }.contains(error.reason)) {
          rethrow;
        }
      }
      return CryptoRecordAuthority(
        signingKey: key,
        currentEpoch: false,
        closedRecordProofHash: proofHash,
        historyBasis: 'inlineProjectDeletion',
      );
    }, freshBoundary: true);
  }
}
