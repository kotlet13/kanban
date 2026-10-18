import 'dart:convert';
import 'dart:typed_data';

import 'account_directory_v2.dart';
import 'crypto_business_router.dart';
import 'crypto_capture_archive.dart';
import 'crypto_finance_policy_actions.dart' show CryptoFinancePolicySnapshot;
import 'crypto_json.dart';
import 'crypto_migration_cold_controls.dart';
import 'crypto_migration_structure_context.dart';
import 'crypto_migration_structure_control.dart';
import 'crypto_sync_repository.dart';

/// Source-only manager attestations precede component verify3. Exact proofs are
/// journaled before HTTP; neither staging nor account-log anchoring activates
/// business records or gives a recipient a scope key.
class CryptoMigrationStructureProducer {
  CryptoMigrationStructureProducer(this.runtime);
  final CryptoBusinessSession runtime;

  Future<Map<String, dynamic>> _sign(
    Map<String, dynamic> value,
    String domain,
  ) async {
    final lease = await runtime.account.signingKey();
    try {
      return runtime.codec.crypto.signDomain(value, lease.key, domain);
    } finally {
      lease.release();
    }
  }

  Future<Map<String, dynamic>> _journal(
    String captureId,
    String key,
    Map<String, dynamic> value,
    String domain,
  ) async {
    final rows = await runtime.db.rows(
      'SELECT payload,authorization FROM crypto_membership_intents '
      'WHERE partition=? AND scope_id=? AND intent_id=?',
      [runtime.partition, captureId, key],
    );
    if (rows.isNotEmpty) {
      final saved = Map<String, dynamic>.from(
        CryptoJson.decode(
              Uint8List.fromList((rows.single['payload'] as List).cast<int>()),
            )
            as Map,
      );
      final expected = {...value}..remove('authorDirectoryHeadHash');
      final original = {...saved}..remove('authorDirectoryHeadHash');
      if (!CryptoMigrationColdEvidence.same(expected, original)) {
        throw const FormatException('crypto_structure_source_immutable');
      }
      return Map<String, dynamic>.from(
        CryptoJson.decode(
              Uint8List.fromList(
                (rows.single['authorization'] as List).cast<int>(),
              ),
            )
            as Map,
      );
    }
    final proof = await _sign(value, domain);
    await runtime.db
        .execute('INSERT INTO crypto_membership_intents VALUES(?,?,?,?,?,?)', [
          runtime.partition,
          captureId,
          key,
          'structureSource',
          CryptoJson.encode(value),
          CryptoJson.encode(proof),
        ]);
    return proof;
  }

  Future<Map<String, dynamic>> _send(
    String action,
    String operation,
    Map<String, dynamic> payload,
  ) async {
    final request = await runtime.queue.enqueueCommand(
      actionKey: action,
      operation: operation,
      payload: payload,
    );
    await runtime.queue.resumeUnresolved(requestIds: {request});
    return runtime.queue.commandResult(request);
  }

  Future<Map<String, dynamic>> publishSource(
    VerifiedCryptoMigrationStructureSource verified,
  ) async {
    final value = verified.value, common = value['common'] as Map;
    final section = value['section'] as Map;
    final current = await runtime.account.directory.requireFresh();
    if (common['accountId'] != current.accountId ||
        common['serverId'] != current.serverId ||
        value['sourceDeviceSnapshotHash'] != current.deviceSnapshotHash ||
        value['sourceIdentityEpochId'] != current.identityEpochId) {
      throw const CryptoAuthorityPending(
        'crypto_structure_source_signer_changed',
      );
    }
    final candidate = await runtime.access.migrationCandidate(
      scopeId: section['scopeId'],
      migrationId: common['migrationId'],
      captureId: common['captureId'],
      headHash: section['membershipHeadHash'],
    );
    final head = candidate.head;
    if (head.headHash != section['membershipHeadHash'] ||
        head.member(current.accountId)['role'] != 'owner') {
      throw const CryptoAuthorityPending(
        'crypto_structure_source_head_changed',
      );
    }
    final statement = <String, dynamic>{
      ...common,
      'operation': 'crypto2.migration.structure.sourceStatement',
      'scopeId': section['scopeId'],
      'membershipHeadHash': section['membershipHeadHash'],
      'scopeMetadataWireId': value['scopeMetadataWireId'],
      'scopeMetadataProofHash': section['scopeMetadataProofHash'],
      'lifecycleHash': section['lifecycleHash'],
      'sourceBindingCount': section['sourceBindingCount'],
      'sourceCommitmentRoot': section['sourceCommitmentRoot'],
      'contentStructureHash': section['structureHash'],
      if (value['contextProofHashes'] != null)
        'contextProofHashes': value['contextProofHashes'],
      'descriptor': value['descriptor'],
      'members': value['members'],
      'financePolicy': value['financePolicy'],
      if (value.containsKey('financeTopology'))
        'financeTopology': value['financeTopology'],
      'deviceId': runtime.account.deviceId,
      'authorDirectoryHeadHash': current.headHash,
    };
    final capture = common['captureId'] as String,
        scope = section['scopeId'] as String;
    final statementProof = await _journal(
      capture,
      'structureSource:$scope',
      statement,
      CryptoMigrationStructureContexts.sourceDomain,
    );
    final saved = CryptoMigrationStructureContexts.body(statementProof);
    final scopeToken = await cryptoSha256([
      ...utf8.encode('JivieStructureSourceToken/v3\n'),
      ...CryptoJson.encode({
        'version': 3,
        'serverId': current.serverId,
        'migrationId': common['migrationId'],
        'accountId': current.accountId,
        'scopeId': scope,
      }),
    ]);
    final certificate = <String, dynamic>{
      for (final k in [
        'version',
        'serverId',
        'migrationId',
        'captureId',
        'accountId',
        'sourceInventoryRoot',
        'membershipHeadHash',
        'sourceBindingCount',
        'sourceCommitmentRoot',
        'contentStructureHash',
        'deviceId',
        'authorDirectoryHeadHash',
      ])
        k: saved[k],
      'operation': 'crypto2.migration.structure.sourceCertificate',
      'scopeToken': scopeToken,
      'sourceStatementHash': await cryptoSha256(
        CryptoJson.encode(statementProof),
      ),
    };
    final certificateProof = await _journal(
      capture,
      'structureSourceCertificate:$scope',
      certificate,
      CryptoMigrationStructureContexts.certificateDomain,
    );
    final hash = await cryptoSha256(CryptoJson.encode(certificateProof));
    final outer = <String, dynamic>{
      for (final k in ['migrationId', 'captureId', 'sourceInventoryRoot'])
        k: common[k],
    };
    final result = await _send(
      'structureSource:$capture:$scope',
      'crypto2.migration.structure.source',
      {
        ...outer,
        'statementAuthorization': statementProof,
        'certificateAuthorization': certificateProof,
      },
    );
    if (result['certificateHash'] != hash ||
        result['sourceBindingCount'] != section['sourceBindingCount'] ||
        result['sourceCommitmentRoot'] != section['sourceCommitmentRoot']) {
      throw const FormatException('crypto_structure_source_receipt');
    }
    final event = await runtime.account.attestMigration(
      migrationId: common['migrationId'],
      scopeToken: scopeToken,
      domain: 'content',
      attestationHash: hash,
    );
    final directory = await runtime.account.directory.cachedVerifiedDirectory();
    if (!directory.includesAnchor(event['generation'], event['headHash'])) {
      throw const FormatException('crypto_structure_source_event');
    }
    runtime.access.invalidateAuthorityOperation();
    final anchored = await _send(
      'structureSourceAnchor:$capture:$scope',
      'crypto2.migration.structure.sourceAnchor',
      {
        ...outer,
        'certificateHash': hash,
        'eventAuthorization': event['authorization'],
      },
    );
    if (anchored['certificateHash'] != hash ||
        anchored['state'] != 'anchored') {
      throw const FormatException('crypto_structure_source_receipt');
    }
    return {
      'statementAuthorization': statementProof,
      'certificateAuthorization': certificateProof,
      'certificateHash': hash,
      'eventAuthorization': event['authorization'],
    };
  }

  Future<Map<String, dynamic>> publishContext({
    required VerifiedCryptoMigrationStructureSource source,
    required String purpose,
    required String targetScopeId,
    required String targetMembershipHeadHash,
  }) async {
    final published = await publishSource(source), value = source.value;
    final common = value['common'] as Map,
        descriptor = value['descriptor'] as Map;
    Map<String, dynamic> facts;
    String? parentToken;
    if (purpose == 'scopeContext') {
      if (targetScopeId != (value['section'] as Map)['scopeId'] ||
          targetMembershipHeadHash !=
              (value['section'] as Map)['membershipHeadHash']) {
        throw const FormatException('crypto_structure_context_target');
      }
      parentToken = descriptor['parentScopeToken'];
      final finance = value['financePolicy'] as Map;
      final snapshot = CryptoFinancePolicySnapshot(
        enabled: finance['enabled'] as bool,
        revision: finance['revision'] as int,
        requiredContractVersion: finance['requiredContractVersion'] as int,
        grants: (finance['grants'] as List).cast<Map<String, dynamic>>(),
      );
      facts = {
        'descriptor': descriptor,
        'members': value['members'],
        'scopeMetadataProofHash':
            (value['section'] as Map)['scopeMetadataProofHash'],
        'lifecycleHash': (value['section'] as Map)['lifecycleHash'],
        if (value.containsKey('financeTopology'))
          'financeTopology': value['financeTopology'],
        'financePolicy': {
          for (final k in ['enabled', 'revision', 'requiredContractVersion'])
            k: finance[k],
          'policyHash': await snapshot.hash(),
          'grantCount': snapshot.grants.length,
        },
      };
    } else if (purpose == 'parentAccess') {
      final policy = descriptor['accessPolicyVersion'];
      final members = (value['members'] as List)
          .where(
            (m) =>
                policy == 3 ||
                policy == 2 &&
                    descriptor['kind'] == 'organization' &&
                    (m['role'] == 'owner' || m['leader'] == true),
          )
          .toList();
      facts = {
        'kind': descriptor['kind'],
        'accessPolicyVersion': policy,
        'ownArchived': descriptor['ownArchived'],
        'members': members,
      };
      parentToken = await cryptoSha256([
        ...utf8.encode('JivieParentLifecycleScope/v2\n'),
        ...CryptoJson.encode({
          'version': 2,
          'serverId': common['serverId'],
          'scopeId': targetScopeId,
          'parentScopeId': (value['section'] as Map)['scopeId'],
        }),
      ]);
    } else {
      throw const FormatException('crypto_structure_context_purpose');
    }
    CryptoMigrationStructureContexts.facts(purpose, facts);
    final own = await runtime.account.directory.requireFresh();
    final card = <String, dynamic>{
      ...common,
      'operation': 'crypto2.migration.structure.context',
      'purpose': purpose,
      'targetScopeId': targetScopeId,
      'targetMembershipHeadHash': targetMembershipHeadHash,
      'parentScopeToken': parentToken,
      'sourceCertificateHash': published['certificateHash'],
      'facts': facts,
      'deviceId': runtime.account.deviceId,
      'authorDirectoryHeadHash': own.headHash,
    };
    final proof = await _journal(
      common['captureId'],
      'structureContext:$purpose:$targetScopeId',
      card,
      CryptoMigrationStructureContexts.contextDomain,
    );
    final hash = await cryptoSha256(CryptoJson.encode(proof));
    final result = await _send(
      'structureContext:${common['captureId']}:$purpose:$targetScopeId',
      'crypto2.migration.structure.context',
      {
        for (final k in ['migrationId', 'captureId', 'sourceInventoryRoot'])
          k: common[k],
        'authorization': proof,
      },
    );
    if (result['contextProofHash'] != hash ||
        result['state'] != 'awaitingConsent') {
      throw const FormatException('crypto_structure_context_receipt');
    }
    return {...published, 'authorization': proof, 'contextProofHash': hash};
  }

  /// The issuer identity must already be independently verified, or be the
  /// exact owner/member identity in this authenticated target head. The review
  /// callback explicitly approves only this card and this contributor's facts.
  Future<void> approve({
    required VerifiedCryptoCaptureArchive archive,
    required Map<String, dynamic> cardEvidence,
    required VerifiedAccountDirectory issuer,
    required Future<bool> Function(
      Map<String, dynamic> facts,
      List<Map<String, dynamic>> members,
    )
    review,
  }) async {
    final hash = await cryptoSha256(
      CryptoJson.encode(cardEvidence['authorization']),
    );
    final card = CryptoMigrationStructureContexts.body(
      Map<String, dynamic>.from(cardEvidence['authorization'] as Map),
    );
    final saved = await runtime.db.rows(
      'SELECT authorization FROM crypto_membership_intents '
      'WHERE partition=? AND scope_id=? AND intent_id=?',
      [
        runtime.partition,
        archive.capture.captureId,
        'structureContextConsent:$hash',
      ],
    );
    if (saved.isNotEmpty) {
      final original = Map<String, dynamic>.from(
        CryptoJson.decode(
              Uint8List.fromList(
                (saved.single['authorization'] as List).cast<int>(),
              ),
            )
            as Map,
      );
      final body = CryptoMigrationStructureContexts.body(original);
      if (body['operation'] != 'crypto2.migration.structure.contextConsent' ||
          body['accountId'] != runtime.account.directory.accountId ||
          body['serverId'] !=
              runtime.account.directory.session.profile.serverId ||
          body['migrationId'] != archive.capture.migrationId ||
          body['captureId'] != archive.capture.captureId ||
          body['sourceInventoryRoot'] != archive.sourceInventoryRoot ||
          body['contextProofHash'] != hash ||
          body['scopeId'] != card['targetScopeId'] ||
          body['membershipHeadHash'] != card['targetMembershipHeadHash']) {
        throw const FormatException('crypto_structure_context_immutable');
      }
      // Exact receipt reconciliation happens before current issuer/head reads.
      // A new send still passes current server CAS; a prior accepted outcome
      // retains its original sourceAuthority prefix and cannot be rewritten.
      final result = await _send(
        'structureContextConsent:${archive.capture.captureId}:$hash',
        'crypto2.migration.structure.contextApprove',
        {
          for (final k in ['migrationId', 'captureId', 'sourceInventoryRoot'])
            k: body[k],
          'authorization': original,
        },
      );
      if (result['contextProofHash'] != hash || result['state'] != 'approved') {
        throw const FormatException('crypto_structure_context_receipt');
      }
      return;
    }
    final candidate = await runtime.access.migrationCandidate(
      scopeId: card['targetScopeId'],
      migrationId: archive.capture.migrationId,
      captureId: archive.capture.captureId,
      headHash: card['targetMembershipHeadHash'],
    );
    final head = candidate.head;
    if (head.headHash != card['targetMembershipHeadHash'] ||
        issuer.accountId != card['accountId']) {
      throw const CryptoAuthorityPending(
        'crypto_structure_context_head_changed',
      );
    }
    final matches = head.members
        .where((m) => m['accountId'] == issuer.accountId)
        .toList();
    if (matches.length == 1) {
      if (matches.single['rootSigningKeyBase64'] !=
              issuer.snapshot['rootSigningKeyBase64'] ||
          matches.single['rootEncryptionKeyBase64'] !=
              issuer.snapshot['rootEncryptionKeyBase64'] ||
          matches.single['deviceSnapshotHash'] != issuer.deviceSnapshotHash) {
        throw const FormatException('crypto_structure_context_identity');
      }
    } else {
      await runtime.access.identities.requireVerified(
        issuer.accountId,
        issuer.rootFingerprint,
      );
    }
    final reviewed = await CryptoMigrationStructureContexts(
      runtime,
      archive,
    ).verifyForReview(cardEvidence, head.scopeId, head.headHash, issuer);
    if (!await review(reviewed.facts, head.members)) {
      throw const CryptoAuthorityPending(
        'crypto_structure_context_review_pending',
      );
    }
    final own = await runtime.account.directory.requireFresh();
    final common = <String, dynamic>{
      'version': 3,
      'serverId': own.serverId,
      'accountId': own.accountId,
      'migrationId': archive.capture.migrationId,
      'captureId': archive.capture.captureId,
      'sourceInventoryRoot': archive.sourceInventoryRoot,
    };
    final consent = <String, dynamic>{
      ...common,
      'operation': 'crypto2.migration.structure.contextConsent',
      'scopeId': head.scopeId,
      'membershipHeadHash': head.headHash,
      'contextProofHash': hash,
      'sourceAuthority': {
        'accountId': issuer.accountId,
        'rootSigningKeyBase64': issuer.snapshot['rootSigningKeyBase64'],
        'rootEncryptionKeyBase64': issuer.snapshot['rootEncryptionKeyBase64'],
        'identityEpochId': issuer.identityEpochId,
        'deviceSnapshotHash': issuer.deviceSnapshotHash,
        'directoryHeadHash': issuer.headHash,
      },
      'deviceId': runtime.account.deviceId,
      'authorDirectoryHeadHash': own.headHash,
    };
    final proof = await _journal(
      archive.capture.captureId,
      'structureContextConsent:$hash',
      consent,
      CryptoMigrationStructureContexts.consentDomain,
    );
    await CryptoMigrationStructureContexts(runtime, archive).verifyConsented(
      {
        'contextProofHash': hash,
        'authorization': cardEvidence['authorization'],
        'consentAuthorization': proof,
        'certificateAuthorization': cardEvidence['certificateAuthorization'],
        'eventAuthorization': cardEvidence['eventAuthorization'],
      },
      head.scopeId,
      head.headHash,
    );
    final result = await _send(
      'structureContextConsent:${archive.capture.captureId}:$hash',
      'crypto2.migration.structure.contextApprove',
      {
        for (final k in ['migrationId', 'captureId', 'sourceInventoryRoot'])
          k: common[k],
        'authorization': proof,
      },
    );
    if (result['contextProofHash'] != hash || result['state'] != 'approved') {
      throw const FormatException('crypto_structure_context_receipt');
    }
  }
}
