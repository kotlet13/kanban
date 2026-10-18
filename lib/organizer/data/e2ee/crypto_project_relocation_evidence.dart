import 'dart:convert';

import 'account_directory_v2.dart';
import 'crypto_json.dart';
import 'crypto_project_relocation_codec.dart';
import 'crypto_record_proof_codec.dart';
import 'crypto_sync_repository.dart';
import 'session_crypto_access.dart';

/// A verified offset is purpose-specific. It cannot be constructed from SQL
/// revision_namespace/legacy_revision, ordinary metadata or a migration hint.
class VerifiedProjectRelocationRecord {
  const VerifiedProjectRelocationRecord._({
    required this.authority,
    required this.scopeId,
    required this.wireId,
    required this.recordProofHash,
    required this.logicalRevision,
    required this.physicalRevision,
    required this.side,
  });
  final CryptoRecordAuthority authority;
  final String scopeId, wireId, recordProofHash, side;
  final int logicalRevision, physicalRevision;
}

/// Intersects ordinary scope/closure authority with a complete finalized
/// purpose publication. The purpose proof never substitutes a different hash
/// for an independently authenticated closure or grants current membership.
class CryptoProjectRelocationEvidence {
  CryptoProjectRelocationEvidence(
    this.access, {
    required this.ordinaryAuthority,
  });
  final SessionCryptoAccess access;
  final Future<CryptoRecordAuthority> Function(Map<String, dynamic>)
  ordinaryAuthority;
  CryptoRecordProofCodec get codec =>
      CryptoRecordProofCodec(access.account.directory.reducer.crypto);
  static Map<String, dynamic> _map(Object? value) {
    if (value is! Map)
      throw const FormatException('crypto_relocation_evidence_shape');
    return Map<String, dynamic>.from(value);
  }

  static bool _same(Object? a, Object? b) =>
      base64Encode(CryptoJson.encode(a)) == base64Encode(CryptoJson.encode(b));

  Future<CryptoRecordAuthority> authority(Map<String, dynamic> record) async =>
      (await verify(record)).authority;

  Future<VerifiedProjectRelocationRecord> verify(
    Map<String, dynamic> record,
  ) async {
    codec.validateUntrustedRecord(record);
    final tag = _map((record['metadata'] as Map)['projectRelocation']);
    CryptoProjectRelocationCodec.exact(tag, {
      'version',
      'actionId',
      'planHash',
      'side',
    });
    if (tag['version'] != 2 ||
        !const {'source', 'target'}.contains(tag['side']) ||
        tag['side'] == 'source' &&
            ((record['type'] == 'scopeMetadata'
                    ? record['deleted'] != false
                    : record['deleted'] != true) ||
                record['expectedRevision'] < 1) ||
        tag['side'] == 'target' && record['expectedRevision'] != 0) {
      throw const FormatException('crypto_relocation_record_context');
    }
    final scope = record['scopeId'] as String;
    final ownBefore = await access.account.directory.requireFresh();
    ownBefore.activeDevice(access.account.deviceId);
    final current = await access.withVerifiedOperation(
      () => access.currentHead(scope, online: true),
      freshBoundary: true,
    );
    final reader = current.member(ownBefore.accountId);
    if (record['domain'] == 'finance' && reader['financeRole'] == 'none') {
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
      'crypto2.projectRelocation.evidence',
      selector,
    );
    final first = Map<String, dynamic>.from(page);
    final publicationProof = _map(first['authorization']);
    final publication = CryptoProjectRelocationCodec.body(publicationProof);
    CryptoProjectRelocationCodec.publication(publication);
    final original = _map(first['recordProof']);
    final batch = _map(first['batchCommitment']);
    final descriptor = _map(first['descriptor']);
    final proofHash = await codec.digest(original),
        batchHash = await codec.digest(batch);
    final leafHash = await CryptoProjectRelocationCodec.recordLeaf(descriptor);
    if (!_same(
          CryptoJson.decode(cryptoBase64(original['commandBase64'])),
          record,
        ) ||
        publication['serverId'] != record['serverId'] ||
        publication['scopeId'] != scope ||
        publication['side'] != tag['side'] ||
        publication['actionId'] != tag['actionId'] ||
        publication['planHash'] != tag['planHash'] ||
        publication['membershipHeadHash'] != record['membershipHeadHash'] ||
        publication['accessRevision'] != record['accessRevision'] ||
        publication['accountId'] != record['accountId'] ||
        publication['deviceId'] != record['deviceId'] ||
        descriptor['id'] != record['id'] ||
        descriptor['type'] != record['type'] ||
        descriptor['domain'] != record['domain'] ||
        descriptor['recordProofHash'] != proofHash) {
      throw const FormatException('crypto_relocation_record_binding');
    }
    final hashes = <String>[];
    final batches = (first['batchDigests'] as List).cast<String>();
    String? after;
    var pages = 0;
    while (true) {
      if (++pages > (CryptoProjectRelocationCodec.maximumRecords + 32) ~/ 32 ||
          !_same(page['authorization'], publicationProof) ||
          !_same(page['eventAuthorization'], first['eventAuthorization']) ||
          !_same(page['descriptor'], descriptor) ||
          !_same(page['recordProof'], original) ||
          !_same(page['batchCommitment'], batch) ||
          !_same(page['batchDigests'], batches) ||
          page['eventHeadHash'] != first['eventHeadHash'] ||
          page['eventCommandHash'] != first['eventCommandHash'] ||
          page['otherPublicationHash'] != first['otherPublicationHash']) {
        throw const FormatException('crypto_relocation_page_substitution');
      }
      final values = page['recordDigests'];
      if (values is! List || values.length > 32)
        throw const FormatException('crypto_relocation_page');
      for (final hash in values) {
        CryptoProjectRelocationCodec.hashValue(hash);
        if (after != null && after.compareTo(hash) >= 0 ||
            hashes.length >= publication['recordCount']) {
          throw const FormatException('crypto_relocation_order');
        }
        hashes.add(hash);
        after = hash;
      }
      if (page['hasMore'] == false) break;
      if (page['hasMore'] != true ||
          values.isEmpty ||
          page['nextAfterHash'] != after) {
        throw const FormatException('crypto_relocation_cursor');
      }
      page = await access.account.directory.call(
        'crypto2.projectRelocation.evidence',
        {...selector, 'afterHash': after},
      );
    }
    if (hashes.length != publication['recordCount'] ||
        !hashes.contains(leafHash) ||
        batches.length != publication['batchCount'] ||
        !batches.contains(batchHash) ||
        await CryptoProjectRelocationCodec.digestRoot('records', hashes) !=
            publication['recordRoot'] ||
        await CryptoProjectRelocationCodec.digestRoot('batches', batches) !=
            publication['batchRoot']) {
      throw const FormatException('crypto_relocation_inclusion');
    }
    final head = await access.headAt(scope, publication['membershipHeadHash']);
    final author = head.member(publication['accountId']);
    if (head.epoch != record['epoch'] ||
        head.accessRevision != record['accessRevision'] ||
        author['manageKeys'] != true ||
        author['role'] == 'viewer' ||
        record['domain'] == 'finance' && author['financeRole'] != 'write') {
      throw const FormatException('crypto_relocation_authority');
    }
    final headWire = await access.account.directory.call(
      'crypto2.scope.headGet',
      {'scopeId': scope, 'headHash': head.headHash},
    );
    if (headWire['headHash'] != head.headHash ||
        !_same(headWire['authorization'], head.authorization) ||
        await codec.digest(_map(headWire['authorization'])) !=
            publication['proposalProofHash'] ||
        headWire['activationAuthorization'] is! Map ||
        await codec.digest(_map(headWire['activationAuthorization'])) !=
            publication['activationProofHash']) {
      throw const FormatException('crypto_relocation_activation_substitution');
    }
    final prefix = await access.directoryAt(
      scopeId: scope,
      scopeHeadHash: head.headHash,
      accountId: publication['accountId'],
      directoryHeadHash: publication['authorDirectoryHeadHash'],
      online: true,
      allowUnverifiedContact: true,
    );
    if (prefix.deviceSnapshotHash != author['deviceSnapshotHash'] ||
        prefix.snapshot['rootSigningKeyBase64'] !=
            author['rootSigningKeyBase64'] ||
        prefix.snapshot['rootEncryptionKeyBase64'] !=
            author['rootEncryptionKeyBase64']) {
      throw const FormatException('crypto_relocation_signer_binding');
    }
    final device = prefix.activeDevice(publication['deviceId']);
    if (device['keyringWrite'] != true)
      throw const FormatException('crypto_relocation_signer_capability');
    final key = cryptoBase64(device['signingKeyBase64'], length: 32);
    codec.crypto.verifyDomain(
      publicationProof,
      key,
      CryptoProjectRelocationCodec.publicationDomain,
    );
    final event = _map(first['eventAuthorization']);
    final eventBody = CryptoProjectRelocationCodec.body(event),
        ep = _map(CryptoProjectRelocationCodec.body(event)['payload']);
    CryptoProjectRelocationCodec.exact(eventBody, {
      'version',
      'operation',
      'serverId',
      'accountId',
      'deviceId',
      'requestId',
      'signer',
      'payload',
    });
    CryptoProjectRelocationCodec.exact(ep, {
      'expectedGeneration',
      'previousHeadHash',
      'identityEpochId',
      'resultingSnapshotHash',
      'actionId',
      'publicationRoot',
    });
    final publicationHash = await codec.digest(publicationProof);
    final otherHash = first['otherPublicationHash'];
    CryptoProjectRelocationCodec.hashValue(otherHash);
    final pairRoot = await CryptoProjectRelocationCodec.publicationRoot(
      tag['side'] == 'source' ? publicationHash : otherHash,
      tag['side'] == 'target' ? publicationHash : otherHash,
    );
    if (eventBody['version'] != 2 ||
        eventBody['operation'] != 'crypto2.account.projectRelocation' ||
        eventBody['signer'] != 'device' ||
        eventBody['serverId'] != publication['serverId'] ||
        eventBody['accountId'] != publication['accountId'] ||
        eventBody['deviceId'] != publication['deviceId'] ||
        eventBody['requestId'] != publication['requestId'] ||
        ep['previousHeadHash'] != prefix.headHash ||
        ep['expectedGeneration'] != prefix.generation ||
        ep['identityEpochId'] != prefix.identityEpochId ||
        ep['resultingSnapshotHash'] != prefix.snapshotHash ||
        ep['actionId'] != tag['actionId'] ||
        ep['publicationRoot'] != pairRoot) {
      throw const FormatException('crypto_relocation_event_binding');
    }
    codec.crypto.verifyDomain(event, key, cryptoDirectoryDomain);
    final commandHash = await cryptoSha256(
      cryptoBase64(event['commandBase64']),
    );
    final eventHash = await cryptoSha256([
      ...utf8.encode(cryptoDirectoryLogDomain),
      ...CryptoJson.encode({
        'serverId': publication['serverId'],
        'accountId': publication['accountId'],
        'generation': prefix.generation + 1,
        'previousHeadHash': prefix.headHash,
        'commandHash': commandHash,
        'signatureBase64': event['signatureBase64'],
      }),
    ]);
    if (first['eventHeadHash'] != eventHash ||
        first['eventCommandHash'] != commandHash) {
      throw const FormatException('crypto_relocation_event_inclusion');
    }
    final included = await access.directoryAt(
      scopeId: scope,
      scopeHeadHash: head.headHash,
      accountId: publication['accountId'],
      directoryHeadHash: eventHash,
      online: true,
      allowUnverifiedContact: true,
    );
    if (included.generation != prefix.generation + 1 ||
        included.snapshotHash != prefix.snapshotHash ||
        !included.includesAnchor(prefix.generation, prefix.headHash)) {
      throw const FormatException('crypto_relocation_event_inclusion');
    }
    final ownPublication =
        publication['accountId'] == ownBefore.accountId &&
        (await access.account.directory.cachedVerifiedDirectory())
            .includesAnchor(included.generation, included.headHash);
    await codec.verifyWire(
      serverId: publication['serverId'],
      wire: {
        for (final field in const [
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
      if (!access.account.directory.isCurrent())
        throw const CryptoAuthorityPending(
          'crypto_relocation_identity_changed',
        );
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
        throw const CryptoAuthorityPending('crypto_relocation_read_changed');
      }
      try {
        final ordinary = await ordinaryAuthority(record);
        if (!ordinary.currentEpoch && ordinary.closedRecordProofHash == null ||
            ordinary.closedRecordProofHash != null &&
                ordinary.closedRecordProofHash != proofHash ||
            base64Encode(ordinary.signingKey) != base64Encode(key)) {
          throw const FormatException('crypto_relocation_closure_substitution');
        }
      } on CryptoAuthorityPending catch (error) {
        if (!ownPublication ||
            !const {
              'history_freshness_pending',
              'history_checkpoint_pending',
            }.contains(error.reason))
          rethrow;
      }
      return VerifiedProjectRelocationRecord._(
        authority: CryptoRecordAuthority(
          signingKey: key,
          currentEpoch: false,
          closedRecordProofHash: proofHash,
          historyBasis: 'managerAttestedProjectRelocation',
          relocationOrigin: Map<String, dynamic>.unmodifiable({
            'version': 2,
            'actionId': tag['actionId'],
            'side': tag['side'],
            'logicalRevision': descriptor['logicalRevision'],
            'physicalRevision': record['expectedRevision'] + 1,
            'recordProofHash': proofHash,
          }),
        ),
        scopeId: scope,
        wireId: record['id'],
        recordProofHash: proofHash,
        logicalRevision: descriptor['logicalRevision'],
        physicalRevision: record['expectedRevision'] + 1,
        side: tag['side'],
      );
    }, freshBoundary: true);
  }
}
