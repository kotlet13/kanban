import 'dart:convert';

import 'account_directory_v2.dart';
import 'crypto_business_router.dart';
import 'crypto_capture_archive.dart';
import 'crypto_json.dart';
import 'crypto_migration_cold_controls.dart';
import 'crypto_migration_notification_codec.dart';
import 'crypto_record_address.dart';
import 'crypto_sync_repository.dart';

/// This is an explicitly reviewed scoped manager attestation. It is not a
/// selective cryptographic proof of private parent SQL, or a global contact.
class VerifiedCryptoStructureContext {
  VerifiedCryptoStructureContext._(this.hash, this.card, this.consent);
  final String hash;
  final Map<String, dynamic> card, consent;
  String get purpose => card['purpose'] as String;
  Map<String, dynamic> get facts =>
      Map<String, dynamic>.from(card['facts'] as Map);
}

class VerifiedCryptoStructureReview {
  VerifiedCryptoStructureReview._(this._context);
  final VerifiedCryptoStructureContext _context;
  Map<String, dynamic> get facts =>
      Map<String, dynamic>.from(jsonDecode(jsonEncode(_context.facts)));
}

class CryptoMigrationStructureContexts {
  CryptoMigrationStructureContexts(this.runtime, this.archive)
    : evidence = CryptoMigrationColdEvidence(runtime, archive);
  final CryptoBusinessSession runtime;
  final VerifiedCryptoCaptureArchive archive;
  final CryptoMigrationColdEvidence evidence;

  static const sourceDomain = 'JivieE2EE/structureSource/v3\n';
  static const certificateDomain = 'JivieE2EE/structureSourceCertificate/v3\n';
  static const contextDomain = 'JivieE2EE/structureContext/v3\n';
  static const consentDomain = 'JivieE2EE/structureContextConsent/v3\n';
  static const commonFields = {
    'version',
    'serverId',
    'migrationId',
    'captureId',
    'accountId',
    'sourceInventoryRoot',
  };

  static Map<String, dynamic> body(Map<String, dynamic> proof) {
    CryptoMigrationNotificationCodec.fields(proof, {
      'commandBase64',
      'signatureBase64',
    });
    cryptoBase64(proof['signatureBase64'], length: 64);
    final bytes = cryptoBase64(proof['commandBase64']);
    if (bytes.length > 128 * 1024) {
      throw const FormatException('crypto_structure_context_size');
    }
    final value = CryptoJson.decode(bytes);
    if (value is! Map) {
      throw const FormatException('crypto_structure_context_shape');
    }
    return Map<String, dynamic>.from(value);
  }

  static void _common(Map<String, dynamic> value) {
    CryptoMigrationNotificationCodec.context({
      for (final key in commonFields) key: value[key],
    });
    if (!isCryptoCanonicalUuid(value['deviceId'])) {
      throw const FormatException('crypto_structure_context_device');
    }
    CryptoMigrationNotificationCodec.digest(value['authorDirectoryHeadHash']);
  }

  static void members(Object? value) {
    if (value is! List || value.length > 100) {
      throw const FormatException('crypto_structure_context_members');
    }
    String? previous;
    for (final raw in value) {
      if (raw is! Map) {
        throw const FormatException('crypto_structure_context_members');
      }
      CryptoMigrationNotificationCodec.fields(raw, {
        'accountId',
        'role',
        'leader',
      });
      if (!isCryptoCanonicalUuid(raw['accountId']) ||
          !const ['owner', 'member', 'viewer'].contains(raw['role']) ||
          raw['leader'] is! bool ||
          previous != null && previous.compareTo(raw['accountId']) >= 0) {
        throw const FormatException('crypto_structure_context_members');
      }
      previous = raw['accountId'];
    }
  }

  static void descriptor(Map value) {
    CryptoMigrationNotificationCodec.fields(value, {
      'kind',
      'accessPolicyVersion',
      'ownArchived',
      'parentScopeToken',
      'ownerAccountId',
    });
    _policy(value);
    if (!isCryptoCanonicalUuid(value['ownerAccountId'])) {
      throw const FormatException('crypto_structure_context_owner');
    }
    if (value['parentScopeToken'] != null) {
      CryptoMigrationNotificationCodec.digest(value['parentScopeToken']);
    }
  }

  static void _policy(Map value) {
    if (!const [
          'personal',
          'household',
          'organization',
          'project',
        ].contains(value['kind']) ||
        !const [1, 2, 3].contains(value['accessPolicyVersion']) ||
        value['ownArchived'] is! bool) {
      throw const FormatException('crypto_structure_context_policy');
    }
  }

  static void facts(String purpose, Map value) {
    if (purpose == 'parentAccess') {
      CryptoMigrationNotificationCodec.fields(value, {
        'kind',
        'accessPolicyVersion',
        'ownArchived',
        'members',
      });
      _policy(value);
      members(value['members']);
      final list = value['members'] as List;
      if (value['accessPolicyVersion'] == 1 && list.isNotEmpty ||
          value['accessPolicyVersion'] == 2 &&
              list.any(
                (m) =>
                    value['kind'] != 'organization' ||
                    m['role'] != 'owner' && m['leader'] != true,
              )) {
        throw const FormatException('crypto_structure_parent_excess_facts');
      }
    } else if (purpose == 'scopeContext') {
      CryptoMigrationNotificationCodec.fields(value, {
        'descriptor',
        'members',
        'financePolicy',
        'scopeMetadataProofHash',
        'lifecycleHash',
        if (const [
          'household',
          'organization',
        ].contains((value['descriptor'] as Map)['kind']))
          'financeTopology',
      });
      final root = const [
        'household',
        'organization',
      ].contains((value['descriptor'] as Map)['kind']);
      if (root != value.containsKey('financeTopology') ||
          root && value['financeTopology'] is! Map) {
        throw const FormatException('crypto_structure_context_topology');
      }
      descriptor(value['descriptor'] as Map);
      members(value['members']);
      for (final key in ['scopeMetadataProofHash', 'lifecycleHash']) {
        CryptoMigrationNotificationCodec.digest(value[key]);
      }
      final policy = value['financePolicy'];
      if (policy != null) {
        if (policy is! Map) {
          throw const FormatException('crypto_structure_finance_policy');
        }
        CryptoMigrationNotificationCodec.fields(policy, {
          'enabled',
          'revision',
          'requiredContractVersion',
          'policyHash',
          'grantCount',
        });
        CryptoMigrationNotificationCodec.digest(policy['policyHash']);
        CryptoMigrationNotificationCodec.count(policy['grantCount']);
        CryptoMigrationNotificationCodec.count(policy['revision']);
        CryptoMigrationNotificationCodec.count(
          policy['requiredContractVersion'],
        );
        if (policy['enabled'] is! bool ||
            (policy['requiredContractVersion'] < 1 ||
                policy['requiredContractVersion'] > 3)) {
          throw const FormatException('crypto_structure_finance_policy');
        }
      }
    } else {
      throw const FormatException('crypto_structure_context_purpose');
    }
  }

  /// Cold precommit verification. The own FILE-anchored consent authenticates
  /// the exact foreign prefix. Nothing is added to global identity pins.
  /// Committed historical readers must additionally require final cutover
  /// inclusion; they must not reuse this fresh-author helper after revocation.
  Future<List<VerifiedCryptoStructureContext>> load(
    String scopeId,
    String membershipHeadHash,
  ) async {
    final result = <VerifiedCryptoStructureContext>[];
    final purposes = <String>{};
    String? after;
    while (true) {
      final page = await runtime.account.directory.call(
        'crypto2.migration.structure.contexts',
        {
          for (final key in ['migrationId', 'captureId', 'sourceInventoryRoot'])
            key: evidence.common[key],
          'scopeId': scopeId,
          'membershipHeadHash': membershipHeadHash,
          if (after != null) 'afterHash': after,
          'limit': 20,
        },
      );
      if (page['contexts'] is! List ||
          (page['contexts'] as List).length > 20 ||
          page['hasMore'] is! bool) {
        throw const FormatException('crypto_structure_context_page');
      }
      for (final raw in page['contexts'] as List) {
        if (raw is! Map) {
          throw const FormatException('crypto_structure_context_page');
        }
        final verified = await verifyConsented(
          Map<String, dynamic>.from(raw),
          scopeId,
          membershipHeadHash,
        );
        if (after != null && after.compareTo(verified.hash) >= 0 ||
            !purposes.add(verified.purpose)) {
          throw const FormatException('crypto_structure_context_order');
        }
        after = verified.hash;
        result.add(verified);
      }
      if (page['hasMore'] == false) break;
      if (page['nextAfterHash'] is! String ||
          after == null ||
          (page['nextAfterHash'] as String).compareTo(after) < 0) {
        throw const FormatException('crypto_structure_context_page');
      }
      after = page['nextAfterHash'];
    }
    return result;
  }

  /// Also used before sending an own newly signed consent. The same exact
  /// proof is later recovered from the FILE archive and verified again.
  Future<VerifiedCryptoStructureReview> verifyForReview(
    Map<String, dynamic> item,
    String scope,
    String head,
    VerifiedAccountDirectory issuer,
  ) async => VerifiedCryptoStructureReview._(
    await _verify(item, scope, head, reviewIssuer: issuer),
  );

  Future<VerifiedCryptoStructureContext> verifyConsented(
    Map<String, dynamic> item,
    String scope,
    String head,
  ) => _verify(item, scope, head);

  Future<VerifiedCryptoStructureContext> _verify(
    Map<String, dynamic> item,
    String scope,
    String head, {
    VerifiedAccountDirectory? reviewIssuer,
  }) async {
    CryptoMigrationNotificationCodec.fields(item, {
      'contextProofHash',
      'authorization',
      'consentAuthorization',
      'certificateAuthorization',
      'eventAuthorization',
    });
    final proof = Map<String, dynamic>.from(item['authorization'] as Map);
    final card = body(proof);
    CryptoMigrationNotificationCodec.fields(card, {
      ...commonFields,
      'operation',
      'purpose',
      'targetScopeId',
      'targetMembershipHeadHash',
      'parentScopeToken',
      'sourceCertificateHash',
      'facts',
      'deviceId',
      'authorDirectoryHeadHash',
    });
    _common(card);
    final hash = await cryptoSha256(CryptoJson.encode(proof));
    if (hash != item['contextProofHash'] ||
        card['operation'] != 'crypto2.migration.structure.context' ||
        card['serverId'] != evidence.common['serverId'] ||
        card['migrationId'] != evidence.common['migrationId'] ||
        card['targetScopeId'] != scope ||
        card['targetMembershipHeadHash'] != head) {
      throw const FormatException('crypto_structure_context_binding');
    }
    if (card['parentScopeToken'] != null) {
      CryptoMigrationNotificationCodec.digest(card['parentScopeToken']);
    }
    facts(card['purpose'], card['facts'] as Map);
    var consent = <String, dynamic>{};
    late Map<String, dynamic> authority;
    if (reviewIssuer == null) {
      if (item['consentAuthorization'] == null ||
          item['eventAuthorization'] == null) {
        throw const CryptoAuthorityPending(
          'crypto_structure_context_consent_pending',
        );
      }
      final consentProof = Map<String, dynamic>.from(
        item['consentAuthorization'] as Map,
      );
      consent = body(consentProof);
      CryptoMigrationNotificationCodec.fields(consent, {
        ...commonFields,
        'operation',
        'scopeId',
        'membershipHeadHash',
        'contextProofHash',
        'sourceAuthority',
        'deviceId',
        'authorDirectoryHeadHash',
      });
      _common(consent);
      if (consent['operation'] !=
              'crypto2.migration.structure.contextConsent' ||
          !CryptoMigrationColdEvidence.same({
            for (final k in commonFields) k: consent[k],
          }, evidence.common) ||
          consent['scopeId'] != scope ||
          consent['membershipHeadHash'] != head ||
          consent['contextProofHash'] != hash) {
        throw const FormatException('crypto_structure_context_consent');
      }
      await evidence.verifyOwn(
        consentProof,
        consent['authorDirectoryHeadHash'],
        consent['deviceId'],
        consentDomain,
      );
      authority = Map<String, dynamic>.from(consent['sourceAuthority'] as Map);
    } else {
      if (reviewIssuer.serverId != evidence.common['serverId'] ||
          reviewIssuer.accountId != card['accountId']) {
        throw const FormatException('crypto_structure_context_issuer');
      }
      authority = {
        'accountId': reviewIssuer.accountId,
        'rootSigningKeyBase64': reviewIssuer.snapshot['rootSigningKeyBase64'],
        'rootEncryptionKeyBase64':
            reviewIssuer.snapshot['rootEncryptionKeyBase64'],
        'identityEpochId': reviewIssuer.identityEpochId,
        'deviceSnapshotHash': reviewIssuer.deviceSnapshotHash,
        'directoryHeadHash': reviewIssuer.headHash,
      };
    }
    CryptoMigrationNotificationCodec.fields(authority, {
      'accountId',
      'rootSigningKeyBase64',
      'rootEncryptionKeyBase64',
      'identityEpochId',
      'deviceSnapshotHash',
      'directoryHeadHash',
    });
    if (authority['accountId'] != card['accountId']) {
      throw const FormatException('crypto_structure_context_issuer');
    }
    final directory = await runtime.access.directoryAt(
      scopeId: scope,
      scopeHeadHash: head,
      accountId: card['accountId'],
      directoryHeadHash: authority['directoryHeadHash'],
      online: true,
      allowUnverifiedContact: true,
    );
    if (directory.identityEpochId != authority['identityEpochId'] ||
        directory.deviceSnapshotHash != authority['deviceSnapshotHash'] ||
        directory.snapshot['rootSigningKeyBase64'] !=
            authority['rootSigningKeyBase64'] ||
        directory.snapshot['rootEncryptionKeyBase64'] !=
            authority['rootEncryptionKeyBase64']) {
      throw const FormatException('crypto_structure_context_issuer');
    }
    // A previously authenticated newer global directory is a revocation floor,
    // even though this scoped evidence never creates a global contact pin.
    final known = await runtime.account.store.anchor(directory.accountId);
    if (known != null && known['generation'] > directory.generation) {
      final later = await runtime.access.directoryAt(
        scopeId: scope,
        scopeHeadHash: head,
        accountId: directory.accountId,
        directoryHeadHash: known['headHash'],
        allowUnverifiedContact: true,
      );
      if (!later.includesAnchor(directory.generation, directory.headHash) ||
          later.deviceSnapshotHash != directory.deviceSnapshotHash ||
          later.identityEpochId != directory.identityEpochId) {
        throw const CryptoAuthorityPending(
          'crypto_structure_source_signer_changed',
        );
      }
    }
    Future<void> verifyScoped(
      Map<String, dynamic> p,
      Map b,
      String domain,
    ) async {
      final prefix = await runtime.access.directoryAt(
        scopeId: scope,
        scopeHeadHash: head,
        accountId: directory.accountId,
        directoryHeadHash: b['authorDirectoryHeadHash'],
        online: true,
        allowUnverifiedContact: true,
      );
      if (!directory.includesAnchor(prefix.generation, prefix.headHash) ||
          prefix.deviceSnapshotHash != directory.deviceSnapshotHash ||
          prefix.identityEpochId != directory.identityEpochId) {
        throw const FormatException('crypto_structure_context_issuer_prefix');
      }
      runtime.codec.crypto.verifyDomain(
        p,
        cryptoBase64(
          prefix.activeDevice(b['deviceId'])['signingKeyBase64'],
          length: 32,
        ),
        domain,
      );
    }

    await verifyScoped(proof, card, contextDomain);
    final certificateProof = Map<String, dynamic>.from(
      item['certificateAuthorization'] as Map,
    );
    final certificate = body(certificateProof);
    CryptoMigrationNotificationCodec.fields(certificate, {
      ...commonFields,
      'operation',
      'membershipHeadHash',
      'sourceBindingCount',
      'sourceCommitmentRoot',
      'contentStructureHash',
      'deviceId',
      'authorDirectoryHeadHash',
      'scopeToken',
      'sourceStatementHash',
    });
    _common(certificate);
    if (certificate['operation'] !=
            'crypto2.migration.structure.sourceCertificate' ||
        !CryptoMigrationColdEvidence.same(
          {for (final k in commonFields) k: certificate[k]},
          {for (final k in commonFields) k: card[k]},
        ) ||
        await cryptoSha256(CryptoJson.encode(certificateProof)) !=
            card['sourceCertificateHash']) {
      throw const FormatException('crypto_structure_context_certificate');
    }
    if (card['purpose'] == 'scopeContext' &&
        certificate['membershipHeadHash'] != card['targetMembershipHeadHash']) {
      throw const FormatException('crypto_structure_context_source_head');
    }
    for (final k in [
      'membershipHeadHash',
      'sourceCommitmentRoot',
      'contentStructureHash',
      'scopeToken',
      'sourceStatementHash',
    ]) {
      CryptoMigrationNotificationCodec.digest(certificate[k]);
    }
    CryptoMigrationNotificationCodec.count(certificate['sourceBindingCount']);
    await verifyScoped(certificateProof, certificate, certificateDomain);
    final eventProof = Map<String, dynamic>.from(
      item['eventAuthorization'] as Map,
    );
    final event = body(eventProof);
    CryptoMigrationNotificationCodec.fields(event, {
      'version',
      'operation',
      'serverId',
      'accountId',
      'deviceId',
      'requestId',
      'signer',
      'payload',
    });
    final payload = event['payload'] as Map;
    CryptoMigrationNotificationCodec.fields(payload, {
      'expectedGeneration',
      'previousHeadHash',
      'identityEpochId',
      'resultingSnapshotHash',
      'migrationId',
      'scopeToken',
      'domain',
      'attestationHash',
    });
    CryptoMigrationNotificationCodec.count(payload['expectedGeneration']);
    if (payload['expectedGeneration'] >= 9007199254740991 ||
        !isCryptoCanonicalUuid(event['requestId']) ||
        !isCryptoCanonicalUuid(event['deviceId']) ||
        !isCryptoCanonicalUuid(payload['identityEpochId'])) {
      throw const FormatException('crypto_structure_context_event');
    }
    CryptoMigrationNotificationCodec.digest(payload['previousHeadHash']);
    CryptoMigrationNotificationCodec.digest(payload['resultingSnapshotHash']);
    if (event['version'] != 2 ||
        event['operation'] != 'crypto2.account.migrationAttest' ||
        event['serverId'] != card['serverId'] ||
        event['accountId'] != card['accountId'] ||
        event['signer'] != 'device' ||
        payload['migrationId'] != card['migrationId'] ||
        payload['domain'] != 'content' ||
        payload['scopeToken'] != certificate['scopeToken'] ||
        payload['attestationHash'] != card['sourceCertificateHash']) {
      throw const FormatException('crypto_structure_context_event');
    }
    final commandHash = await cryptoSha256(
      cryptoBase64(eventProof['commandBase64']),
    );
    final eventHash = await cryptoSha256([
      ...utf8.encode(cryptoDirectoryLogDomain),
      ...CryptoJson.encode({
        'serverId': event['serverId'],
        'accountId': event['accountId'],
        'generation': payload['expectedGeneration'] + 1,
        'previousHeadHash': payload['previousHeadHash'],
        'commandHash': commandHash,
        'signatureBase64': eventProof['signatureBase64'],
      }),
    ]);
    if (!directory.includesAnchor(
      payload['expectedGeneration'] + 1,
      eventHash,
    )) {
      throw const FormatException('crypto_structure_context_event_omitted');
    }
    return VerifiedCryptoStructureContext._(hash, card, consent);
  }
}
