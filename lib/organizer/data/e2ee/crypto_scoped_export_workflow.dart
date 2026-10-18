import 'dart:convert';
import 'dart:typed_data';
import 'package:sodium/sodium.dart' show SecureKey;
import '../../domain/linked_payment_models.dart';
import 'account_directory_v2.dart';
import 'crypto_business_router.dart';
import 'crypto_business_json.dart';
import 'crypto_json.dart';
import 'crypto_record_address.dart';
import 'crypto_scoped_exports.dart';
import 'crypto_sync_repository.dart';

/// Source financial facts are read and verified locally. The target receives
/// only a selected issuer's bounded attestation; this never transfers source
/// ledger membership or grants its decryption keys.
class CryptoScopedExportWorkflow {
  CryptoScopedExportWorkflow(this.context);
  final CryptoBusinessSession context;
  String get partition => context.partition;
  Map<String, dynamic> _decode(Object value) => Map<String, dynamic>.from(
    value is String
        ? jsonDecode(value)
        : CryptoJson.decode(Uint8List.fromList((value as List).cast<int>()))
              as Map,
  );
  Future<Map<String, dynamic>> _stage({
    required String actionId,
    required String targetScopeId,
    required String operation,
    required Map<String, dynamic> intent,
    required Future<Map<String, dynamic>> Function(
      String requestId,
      SecureKey key,
    )
    build,
    Map<String, dynamic>? sourceContext,
  }) async {
    if (!isCryptoCanonicalUuid(actionId)) {
      throw const FormatException('scoped_export_action_id');
    }
    await context.database.execute(
      '''CREATE TABLE IF NOT EXISTS crypto_export_drafts (
      partition TEXT NOT NULL, scope_id TEXT NOT NULL, action_id TEXT NOT NULL,
      payload TEXT NOT NULL, PRIMARY KEY(partition,scope_id,action_id))''',
    );
    final hash = await CryptoBusinessJson.hash({
      'operation': operation,
      'intent': intent,
    });
    final rows = await context.database.rows(
      "SELECT payload FROM crypto_export_drafts WHERE partition=? AND scope_id=? AND action_id=?",
      [partition, targetScopeId, actionId],
    );
    late Map<String, dynamic> saved;
    if (rows.isNotEmpty) {
      saved = _decode(rows.single['payload']!);
      if (saved['intentHash'] != hash) {
        throw const FormatException('scoped_export_immutable_intent');
      }
    } else {
      final request = context.codec.crypto.randomId(),
          lease = await context.account.signingKey();
      try {
        saved = {
          'intentHash': hash,
          'requestId': request,
          'operation': operation,
          'payload': await build(request, lease.key),
          'sourceContext': sourceContext,
        };
      } finally {
        lease.release();
      }
      await context.database.execute(
        'INSERT INTO crypto_export_drafts VALUES(?,?,?,?)',
        [
          partition,
          targetScopeId,
          actionId,
          CryptoBusinessJson.canonical(saved),
        ],
      );
    }
    final request = await context.queue.enqueueCommand(
      actionKey: 'scopedExport:$actionId',
      operation: operation,
      payload: Map<String, dynamic>.from(saved['payload'] as Map),
      requestId: saved['requestId'],
    );
    await context.queue.resumeUnresolved(requestIds: {request});
    final payload = Map<String, dynamic>.from(saved['payload'] as Map);
    final private = saved['sourceContext'] as Map?;
    final result = <String, dynamic>{
      ...await context.queue.commandResult(request),
      'requestId': request,
      'preparedPayload': payload,
      'privateContext': private,
    };
    if (operation == 'crypto2.exports.propose' ||
        operation == 'crypto2.exports.certify') {
      final name = operation.endsWith('propose') ? 'offer' : 'certificate';
      final proof = Map<String, dynamic>.from(payload['${name}Proof'] as Map);
      result.addAll({
        '${name}Proof': proof,
        '${name}Hash': await CryptoScopedExports.proofHash(proof),
        'disclosure': private!['disclosure'],
        'disclosureSaltBase64': private['disclosureSaltBase64'],
        if (private['delegationProof'] != null)
          'delegationProof': private['delegationProof'],
      });
    } else {
      final row = (await context.database.rows(
        'SELECT signed_body FROM crypto_outbox WHERE partition=? AND request_id=?',
        [partition, request],
      )).single;
      final proof = Map<String, dynamic>.from(
        jsonDecode(row['signed_body'] as String) as Map,
      );
      result.addAll({
        'delegationProof': proof,
        'delegationHash': await CryptoScopedExports.proofHash(proof),
      });
    }
    return result;
  }

  Future<Map<String, dynamic>?> _resume({
    required String actionId,
    required String targetScopeId,
    required String operation,
    required Map<String, dynamic> intent,
  }) async {
    final table = await context.database.rows(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='crypto_export_drafts'",
    );
    if (table.isEmpty) return null;
    final rows = await context.database.rows(
      'SELECT payload FROM crypto_export_drafts WHERE partition=? AND scope_id=? AND action_id=?',
      [partition, targetScopeId, actionId],
    );
    if (rows.isEmpty) return null;
    return _stage(
      actionId: actionId,
      targetScopeId: targetScopeId,
      operation: operation,
      intent: intent,
      build: (_, _) async =>
          throw StateError('Stored export must never regenerate'),
    );
  }

  static Map<String, dynamic> paymentDisclosure(Map<String, dynamic> raw) {
    final model = PaymentEvent.fromJson(raw);
    final known = model.toJson();
    known['reimbursements'] = [
      for (final leg in model.reimbursements) leg.toJson(projection: true),
    ];
    known['sourceState'] = raw['sourceState'];
    if (!['active', 'canceled', 'deleted'].contains(known['sourceState'])) {
      throw const FormatException('scoped_payment_source_state');
    }
    return {
      for (final field in CryptoScopedExports.allowedFields['paymentSource']!)
        field: known[field],
    };
  }

  Future<Map<String, dynamic>> propose({
    required String actionId,
    required String purpose,
    required String sourceScopeId,
    required String sourceCanonicalId,
    required String sourceType,
    required String targetScopeId,
    required String targetHeadHash,
    required String subjectNonce,
    Map<String, dynamic>? sourceProof,
  }) async {
    final intent = <String, dynamic>{
      'purpose': purpose,
      'sourceScopeId': sourceScopeId,
      'sourceCanonicalId': sourceCanonicalId,
      'sourceType': sourceType,
      'targetScopeId': targetScopeId,
      'targetHeadHash': targetHeadHash,
      'subjectNonce': subjectNonce,
      if (sourceProof != null)
        'sourceProofHash': await context.codec.digest(sourceProof),
    };
    final resumed = await _resume(
      actionId: actionId,
      targetScopeId: targetScopeId,
      operation: 'crypto2.exports.propose',
      intent: intent,
    );
    if (resumed != null) return resumed;
    if (!isCryptoCanonicalUuid(subjectNonce)) {
      throw const FormatException('scoped_export_nonce');
    }
    await context.pullVerified(sourceScopeId, 'finance', attest: false);
    Map<String, Object?>? row = await context.record(
      sourceScopeId,
      'finance',
      sourceCanonicalId,
      type: sourceType,
    );
    Map<String, dynamic> raw;
    if (sourceProof != null) {
      if (purpose != 'paymentSource' || sourceType != 'paymentEvent') {
        throw const FormatException('scoped_export_future_source');
      }
      final future = await CryptoScopedExports.verifyFuturePaymentSource(
        context.access,
        sourceProof,
        scopeId: sourceScopeId,
        canonicalId: sourceCanonicalId,
      );
      raw = Map<String, dynamic>.from(future['raw'] as Map);
      row = {
        'deleted': 0,
        'raw_payload': CryptoBusinessJson.canonical(raw),
        'record_proof_hash': future['proofHash'],
        'crypto_revision': 1,
      };
    } else {
      if (row == null || row['deleted'] == 1 || row['raw_payload'] == null) {
        throw const CryptoAuthorityPending('scoped_export_source_missing');
      }
      raw = _decode(row['raw_payload']!);
    }
    final Map<String, dynamic> disclosure;
    if (purpose == 'paymentSource' && sourceType == 'paymentEvent') {
      disclosure = paymentDisclosure(raw);
    } else if (purpose == 'financeAccountChoice' &&
        sourceType == 'financeAccount') {
      disclosure = {
        'accountId': sourceCanonicalId,
        'accountScopeId': sourceScopeId,
        'name': raw['name'],
        'currency': raw['currency'],
        'archived': raw['archived'],
        'sourceRevision': row['legacy_revision'],
      };
    } else {
      throw const FormatException('scoped_export_source_type');
    }
    final sourceHead = await context.access.currentHead(
          sourceScopeId,
          online: true,
        ),
        own = await context.account.directory.requireFresh();
    if (sourceHead.member(own.accountId)['financeRole'] == 'none') {
      throw const CryptoAuthorityPending('finance_forbidden');
    }
    final wire = context
        .address(sourceScopeId, 'finance', sourceType, sourceCanonicalId)
        .wireId;
    final scopeToken = await cryptoSha256(
      utf8.encode('JivieExportScope/v2\n') +
          CryptoJson.encode({
            'version': 2,
            'serverId': own.serverId,
            'scopeId': targetScopeId,
            'sourceScopeId': sourceScopeId,
          }),
    );
    final subjectToken = await cryptoSha256(
      utf8.encode('JivieExportSubject/v2\n') +
          CryptoJson.encode({
            'version': 2,
            'serverId': own.serverId,
            'scopeId': targetScopeId,
            'purpose': purpose,
            'sourceScopeToken': scopeToken,
            'sourceId': wire,
            'subjectNonce': subjectNonce,
          }),
    );
    final offer = {
      'version': 2,
      'operation': 'crypto2.exports.offer',
      'serverId': own.serverId,
      'purpose': purpose,
      'scopeId': targetScopeId,
      'membershipHeadHash': targetHeadHash,
      'sourceScopeToken': scopeToken,
      'subjectToken': subjectToken,
      'sourceMembershipHeadHash': sourceHead.headHash,
      'sourceRecordProofHash': row['record_proof_hash'],
      'sourceRevision': row['crypto_revision'],
      'accountId': own.accountId,
      'deviceId': context.account.deviceId,
      'authorDirectoryHeadHash': own.headHash,
      'deviceSnapshotHash': own.deviceSnapshotHash,
      'permittedFields': CryptoScopedExports.allowedFields[purpose],
    };
    final privateContext = <String, dynamic>{
      'scopeId': sourceScopeId,
      'id': wire,
      'type': sourceType,
      'canonicalId': sourceCanonicalId,
      'disclosure': disclosure,
      if (sourceProof != null) 'raw': raw,
    };
    final result = await _stage(
      actionId: actionId,
      targetScopeId: targetScopeId,
      operation: 'crypto2.exports.propose',
      intent: intent,
      sourceContext: privateContext,
      build: (request, key) async {
        final salt = context.codec.crypto.sodium.randombytes.buf(32);
        try {
          privateContext['disclosureSaltBase64'] = base64Encode(salt);
          final exactOffer = {
            ...offer,
            'disclosureHash': await CryptoScopedExports.disclosureHash(
              disclosure: disclosure,
              proofBody: offer,
              disclosureSaltBase64: base64Encode(salt),
            ),
          };
          return {
            'sourceScopeId': sourceScopeId,
            'sourceId': wire,
            'subjectNonce': subjectNonce,
            if (sourceProof != null) 'sourceProof': sourceProof,
            'offerProof': context.codec.crypto.signDomain(
              exactOffer,
              key,
              CryptoScopedExports.offerDomain,
            ),
          };
        } finally {
          salt.fillRange(0, salt.length, 0);
        }
      },
    );
    final proof = Map<String, dynamic>.from(
      result['preparedPayload']['offerProof'] as Map,
    );
    return {
      ...result,
      'offerHash': await CryptoScopedExports.proofHash(proof),
      'offerProof': proof,
      'disclosure': result['privateContext']['disclosure'],
      'disclosureSaltBase64': result['privateContext']['disclosureSaltBase64'],
    };
  }

  Map<String, dynamic> _body(Map<String, dynamic> proof) =>
      Map<String, dynamic>.from(
        CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map,
      );

  Future<Map<String, dynamic>> delegate({
    required String actionId,
    required String targetScopeId,
    required Map<String, dynamic> offerProof,
    Map<String, dynamic>? bridgeRecipient,
  }) async {
    final intent = <String, dynamic>{
      'targetScopeId': targetScopeId,
      'offerHash': await CryptoScopedExports.proofHash(offerProof),
      'bridgeRecipient': bridgeRecipient,
    };
    final resumed = await _resume(
      actionId: actionId,
      targetScopeId: targetScopeId,
      operation: 'crypto2.exports.delegate',
      intent: intent,
    );
    if (resumed != null) return resumed;
    final offer = _body(offerProof);
    final purpose = offer['purpose'] as String;
    final fields = CryptoScopedExports.allowedFields[purpose];
    final head = await context.access.currentHead(targetScopeId, online: true);
    final own = await context.account.directory.requireFresh();
    if (fields == null ||
        head.member(own.accountId)['manageKeys'] != true ||
        offer['version'] != 2 ||
        offer['operation'] != 'crypto2.exports.offer' ||
        offer['serverId'] != own.serverId ||
        offer['scopeId'] != targetScopeId ||
        offer['membershipHeadHash'] != head.headHash ||
        base64Encode(CryptoJson.encode(offer['permittedFields'])) !=
            base64Encode(CryptoJson.encode(fields))) {
      throw const FormatException('scoped_export_offer');
    }
    // A manager explicitly selects an independently compared issuer identity.
    // Server directory pointers are discovery only, never first-contact trust.
    final issuer = await context.access.currentMemberDirectory(
      targetScopeId,
      head.headHash,
      offer['accountId'],
    );
    final reference = await context.access.directoryAt(
      scopeId: targetScopeId,
      scopeHeadHash: head.headHash,
      accountId: offer['accountId'],
      directoryHeadHash: offer['authorDirectoryHeadHash'],
    );
    if (issuer.deviceSnapshotHash != offer['deviceSnapshotHash'] ||
        reference.deviceSnapshotHash != issuer.deviceSnapshotHash) {
      throw const CryptoAuthorityPending('scoped_export_issuer_changed');
    }
    context.codec.crypto.verifyDomain(
      offerProof,
      cryptoBase64(
        reference.activeDevice(offer['deviceId'])['signingKeyBase64'],
        length: 32,
      ),
      CryptoScopedExports.offerDomain,
    );
    if (purpose == 'financeAccountChoice' && bridgeRecipient == null) {
      throw const CryptoAuthorityPending('scoped_export_recipient_required');
    }
    if (bridgeRecipient != null) {
      if (head.member(bridgeRecipient['accountId'])['financeRole'] == 'none') {
        throw const FormatException('scoped_export_recipient_role');
      }
      final recipient = await context.access.currentMemberDirectory(
        targetScopeId,
        head.headHash,
        bridgeRecipient['accountId'],
      );
      final device = recipient.activeDevice(bridgeRecipient['deviceId']);
      if (recipient.headHash != bridgeRecipient['directoryHeadHash'] ||
          recipient.deviceSnapshotHash !=
              bridgeRecipient['deviceSnapshotHash'] ||
          device['encryptionKeyBase64'] !=
              bridgeRecipient['encryptionPublicKeyBase64']) {
        throw const CryptoAuthorityPending('scoped_export_recipient_changed');
      }
    }
    final offerHash = await CryptoScopedExports.proofHash(offerProof);
    final payload = <String, dynamic>{
      'scopeId': targetScopeId,
      'membershipHeadHash': head.headHash,
      'expectedAccessRevision': head.accessRevision,
      'authorDirectoryHeadHash': own.headHash,
      'delegationId': actionId,
      'purpose': purpose,
      'offerHash': offerHash,
      'issuerAccountId': issuer.accountId,
      'issuerDirectoryHeadHash': issuer.headHash,
      'issuerRootSigningKeyBase64': issuer.snapshot['rootSigningKeyBase64'],
      'issuerRootEncryptionKeyBase64':
          issuer.snapshot['rootEncryptionKeyBase64'],
      'issuerIdentityEpochId': issuer.identityEpochId,
      'issuerDeviceSnapshotHash': issuer.deviceSnapshotHash,
      'sourceScopeToken': offer['sourceScopeToken'],
      'subjectToken': offer['subjectToken'],
      'permittedFields': fields,
      'bridgeRecipient': bridgeRecipient,
    };
    final result = await _stage(
      actionId: actionId,
      targetScopeId: targetScopeId,
      operation: 'crypto2.exports.delegate',
      intent: intent,
      build: (_, _) async => payload,
    );
    final row = (await context.database.rows(
      'SELECT signed_body FROM crypto_outbox WHERE partition=? AND request_id=?',
      [partition, result['requestId']],
    )).single;
    final proof = Map<String, dynamic>.from(
      jsonDecode(row['signed_body'] as String) as Map,
    );
    return {
      ...result,
      'delegationProof': proof,
      'delegationHash': await CryptoScopedExports.proofHash(proof),
    };
  }

  Future<Map<String, dynamic>> certify({
    required String actionId,
    required String offerActionId,
    required String targetScopeId,
    required Map<String, dynamic> delegationProof,
  }) async {
    final intent = <String, dynamic>{
      'offerActionId': offerActionId,
      'delegationHash': await CryptoScopedExports.proofHash(delegationProof),
    };
    final resumed = await _resume(
      actionId: actionId,
      targetScopeId: targetScopeId,
      operation: 'crypto2.exports.certify',
      intent: intent,
    );
    if (resumed != null) return resumed;
    final drafts = await context.database.rows(
      'SELECT payload FROM crypto_export_drafts WHERE partition=? AND scope_id=? AND action_id=?',
      [partition, targetScopeId, offerActionId],
    );
    if (drafts.length != 1) {
      throw const CryptoAuthorityPending('scoped_export_offer_draft_missing');
    }
    final saved = _decode(drafts.single['payload']!);
    final original = Map<String, dynamic>.from(saved['sourceContext'] as Map);
    final offerProof = Map<String, dynamic>.from(
      saved['payload']['offerProof'] as Map,
    );
    final offer = _body(offerProof), manager = _body(delegationProof);
    final delegation = Map<String, dynamic>.from(manager['payload'] as Map);
    final offerHash = await CryptoScopedExports.proofHash(offerProof);
    final delegationHash = await CryptoScopedExports.proofHash(delegationProof);
    // The direct path has target membership and verifies its current manager.
    // An absent-target issuer waits for the bounded public authority proof.
    final head = await context.access.currentHead(targetScopeId, online: true);
    final author = await context.access.currentMemberDirectory(
      targetScopeId,
      head.headHash,
      manager['accountId'],
    );
    final reference = await context.access.directoryAt(
      scopeId: targetScopeId,
      scopeHeadHash: head.headHash,
      accountId: manager['accountId'],
      directoryHeadHash: delegation['authorDirectoryHeadHash'],
    );
    if (manager['operation'] != 'crypto2.exports.delegate' ||
        manager['version'] != 2 ||
        manager['signer'] != 'device' ||
        manager['serverId'] !=
            context.account.directory.session.profile.serverId ||
        delegation['scopeId'] != targetScopeId ||
        delegation['membershipHeadHash'] != head.headHash ||
        delegation['expectedAccessRevision'] != head.accessRevision ||
        head.member(author.accountId)['manageKeys'] != true ||
        author.deviceSnapshotHash != reference.deviceSnapshotHash ||
        delegation['offerHash'] != offerHash ||
        delegation['issuerAccountId'] != context.account.directory.accountId) {
      throw const FormatException('scoped_export_delegation');
    }
    context.codec.crypto.verifyDomain(
      delegationProof,
      cryptoBase64(
        reference.activeDevice(manager['deviceId'])['signingKeyBase64'],
        length: 32,
      ),
      cryptoDirectoryDomain,
    );
    await context.pullVerified(original['scopeId'], 'finance', attest: false);
    final source = await context.record(
      original['scopeId'],
      'finance',
      original['canonicalId'],
      type: original['type'],
    );
    final sourceHead = await context.access.currentHead(
      original['scopeId'],
      online: true,
    );
    final own = await context.account.directory.requireFresh();
    if (source == null ||
        source['deleted'] == 1 ||
        source['crypto_revision'] != offer['sourceRevision'] ||
        source['record_proof_hash'] != offer['sourceRecordProofHash'] ||
        sourceHead.headHash != offer['sourceMembershipHeadHash'] ||
        own.deviceSnapshotHash != offer['deviceSnapshotHash'] ||
        own.accountId != offer['accountId'] ||
        context.account.deviceId != offer['deviceId']) {
      throw const CryptoAuthorityPending('scoped_export_source_changed');
    }
    final disclosure = Map<String, dynamic>.from(original['disclosure'] as Map);
    final salt = original['disclosureSaltBase64'] as String;
    final result = await _stage(
      actionId: actionId,
      targetScopeId: targetScopeId,
      operation: 'crypto2.exports.certify',
      intent: intent,
      sourceContext: {...original, 'delegationProof': delegationProof},
      build: (request, key) async {
        final certificate = <String, dynamic>{
          ...offer,
          'operation': 'crypto2.exports.certificate',
          'offerHash': offerHash,
          'delegationProofHash': delegationHash,
          'bridge': null,
        };
        final recipient = delegation['bridgeRecipient'];
        if (recipient != null) {
          certificate['bridge'] = {
            'recipient': recipient,
            'requestId': request,
          };
          final bytes = CryptoBusinessJson.encode({
            'context': CryptoScopedExports.bridgeContext(
              certificate,
              delegation,
              delegationProof,
            ),
            'disclosure': disclosure,
            'disclosureSaltBase64': salt,
          });
          try {
            final cipher = context.codec.crypto.sodium.crypto.box.seal(
              message: bytes,
              publicKey: cryptoBase64(
                recipient['encryptionPublicKeyBase64'],
                length: 32,
              ),
            );
            certificate['bridge'] = {
              ...certificate['bridge'] as Map,
              'sealedDisclosureBase64': base64Encode(cipher),
              'ciphertextHash': await cryptoSha256(cipher),
            };
          } finally {
            bytes.fillRange(0, bytes.length, 0);
          }
        }
        final proof = context.codec.crypto.signDomain(
          certificate,
          key,
          CryptoScopedExports.certificateDomain,
        );
        // Verify the exact target policy, selected issuer, and commitment before
        // publishing; malformed disclosure never becomes a signed target fact.
        await CryptoScopedExports(context.access).verify(
          targetScopeId: targetScopeId,
          purpose: offer['purpose'],
          disclosure: disclosure,
          disclosureSaltBase64: salt,
          delegationProof: delegationProof,
          certificateProof: proof,
          rememberFloor: false,
        );
        return {
          'offerHash': offerHash,
          'delegationHash': delegationHash,
          'sourceRevision': source['crypto_revision'],
          'sourceRecordProofHash': source['record_proof_hash'],
          'certificateProof': proof,
        };
      },
    );
    final proof = Map<String, dynamic>.from(
      result['preparedPayload']['certificateProof'] as Map,
    );
    return {
      ...result,
      'certificateProof': proof,
      'certificateHash': await CryptoScopedExports.proofHash(proof),
      'disclosure': disclosure,
      'disclosureSaltBase64': salt,
      'delegationProof': delegationProof,
    };
  }

  /// Creates no RPC and advances no source floor. The caller seals the returned
  /// witness into the exact target record and journals the complete batch before
  /// sending its private exportBindings in the same atomic records command.
  Future<Map<String, dynamic>> prepareBatchCertificate({
    required String actionId,
    required String targetScopeId,
    required String offerActionId,
    required Map<String, dynamic> delegationProof,
    required Map<String, dynamic> sourceProof,
    required Map<String, dynamic> sourceRaw,
    required Map<String, dynamic> targetRecord,
  }) async {
    if (!isCryptoCanonicalUuid(actionId)) {
      throw const FormatException('scoped_export_action_id');
    }
    final sourceHash = await context.codec.digest(sourceProof);
    final delegationHash = await CryptoScopedExports.proofHash(delegationProof);
    final intent = {
      'offerActionId': offerActionId,
      'delegationHash': delegationHash,
      'sourceProofHash': sourceHash,
      'sourceRawHash': await CryptoBusinessJson.hash(sourceRaw),
      'targetRecord': targetRecord,
    };
    final intentHash = await CryptoBusinessJson.hash(intent);
    final savedRows = await context.database.rows(
      'SELECT payload FROM crypto_export_drafts WHERE partition=? AND scope_id=? AND action_id=?',
      [partition, targetScopeId, actionId],
    );
    if (savedRows.isNotEmpty) {
      final saved = _decode(savedRows.single['payload']!);
      if (saved['operation'] != 'crypto2.records.batch.exportBinding' ||
          saved['intentHash'] != intentHash) {
        throw const FormatException('scoped_export_immutable_intent');
      }
      return Map<String, dynamic>.from(saved['payload'] as Map);
    }
    final offered = await context.database.rows(
      'SELECT payload FROM crypto_export_drafts WHERE partition=? AND scope_id=? AND action_id=?',
      [partition, targetScopeId, offerActionId],
    );
    if (offered.length != 1) {
      throw const CryptoAuthorityPending('scoped_export_offer_draft_missing');
    }
    final offerDraft = _decode(offered.single['payload']!);
    final offerProof = Map<String, dynamic>.from(
      offerDraft['payload']['offerProof'] as Map,
    );
    final offer = _body(offerProof);
    final own = await context.account.directory.requireFresh();
    final source = context.codec.crypto.verifyDomain(
      sourceProof,
      cryptoBase64(
        own.activeDevice(context.account.deviceId)['signingKeyBase64'],
        length: 32,
      ),
      'JivieE2EE/record/v2\n',
    );
    context.codec.validateUntrustedRecord(source);
    final sourceScope = source['scopeId'] as String;
    final head = await context.access.currentHead(sourceScope, online: true);
    final previous = await context.wireRecord(
      sourceScope,
      'finance',
      source['id'],
    );
    final original = offerDraft['sourceContext'] as Map;
    if (sourceScope != original['scopeId'] ||
        source['id'] != original['id'] ||
        source['serverId'] != own.serverId ||
        source['accountId'] != own.accountId ||
        source['deviceId'] != context.account.deviceId ||
        source['type'] != 'paymentEvent' ||
        source['domain'] != 'finance' ||
        source['deleted'] != false ||
        source['membershipHeadHash'] != head.headHash ||
        source['epoch'] != head.epoch ||
        source['accessRevision'] != head.accessRevision ||
        head.member(own.accountId)['financeRole'] != 'write' ||
        (previous?['crypto_revision'] ?? 0) != source['expectedRevision'] ||
        (previous?['record_proof_hash'] ?? cryptoZeroHash) !=
            source['previousRecordHash'] ||
        offer['purpose'] != 'paymentSource' ||
        offer['scopeId'] != targetScopeId ||
        offer['accountId'] != own.accountId ||
        offer['deviceId'] != context.account.deviceId ||
        offer['deviceSnapshotHash'] != own.deviceSnapshotHash ||
        source['batchId'] != targetRecord['batchId'] ||
        source['expectedRevision'] == 0 &&
            offer['sourceRecordProofHash'] != sourceHash) {
      throw const CryptoAuthorityPending('scoped_export_source_changed');
    }
    final key = await context.access.getScopeKey(
      sourceScope,
      'finance',
      head.epoch,
    );
    Uint8List? bytes;
    try {
      bytes = context.codec.openVerified(source, key.key);
      if (bytes == null) {
        throw const FormatException('scoped_export_source_payload');
      }
      final envelope = jsonDecode(utf8.decode(bytes)) as Map;
      if (envelope.length != 3 ||
          envelope['format'] != 2 ||
          CryptoBusinessJson.canonical(envelope['identity']) !=
              CryptoBusinessJson.canonical(source['metadata']['identity'])) {
        throw const FormatException('scoped_export_source_payload');
      }
      var raw = Map<String, dynamic>.from(envelope['payload'] as Map);
      if (context.expandPayload != null) {
        raw = await context.expandPayload!(
          CryptoProjectionRecord(
            const {},
            source,
            bytes,
            historyBasis: 'currentEpoch',
            batchKey: source['batchId'],
          ),
          raw,
        );
      }
      if (CryptoBusinessJson.canonical(raw) !=
          CryptoBusinessJson.canonical(sourceRaw)) {
        throw const FormatException('scoped_export_source_payload');
      }
    } finally {
      bytes?.fillRange(0, bytes.length, 0);
      key.release();
    }
    final disclosure = paymentDisclosure(sourceRaw);
    final salt = context.codec.crypto.sodium.randombytes.buf(32);
    final lease = await context.account.signingKey();
    try {
      final body = <String, dynamic>{
        ...offer,
        'operation': 'crypto2.exports.certificate',
        'sourceMembershipHeadHash': source['membershipHeadHash'],
        'sourceRecordProofHash': sourceHash,
        'sourceRevision': source['expectedRevision'] + 1,
        'authorDirectoryHeadHash': own.headHash,
        'deviceSnapshotHash': own.deviceSnapshotHash,
        'offerHash': await CryptoScopedExports.proofHash(offerProof),
        'delegationProofHash': delegationHash,
        'bridge': null,
        'batchContext': {
          'batchId': source['batchId'],
          'sourceOperationId': source['operationId'],
          'sourceExpectedRevision': source['expectedRevision'],
          'targetOperationId': targetRecord['operationId'],
          'targetExpectedRevision': targetRecord['expectedRevision'],
          'targetId': targetRecord['id'],
          'targetIdentity': targetRecord['metadata']['identity'],
          'targetMembershipHeadHash': targetRecord['membershipHeadHash'],
        },
      };
      final saltText = base64Encode(salt);
      body['disclosureHash'] = await CryptoScopedExports.disclosureHash(
        disclosure: disclosure,
        proofBody: body,
        disclosureSaltBase64: saltText,
      );
      final proof = context.codec.crypto.signDomain(
        body,
        lease.key,
        CryptoScopedExports.certificateDomain,
      );
      await CryptoScopedExports(context.access).verify(
        targetScopeId: targetScopeId,
        purpose: 'paymentSource',
        disclosure: disclosure,
        disclosureSaltBase64: saltText,
        delegationProof: delegationProof,
        certificateProof: proof,
        targetRecord: targetRecord,
        batchCommitment: {
          'batchId': source['batchId'],
          'recordDigests': [sourceHash],
        },
        rememberFloor: false,
      );
      final result = <String, dynamic>{
        'binding': {
          'sourceScopeId': sourceScope,
          'sourceId': source['id'],
          'sourceRecordProofHash': sourceHash,
          'targetScopeId': targetScopeId,
          'targetId': targetRecord['id'],
          'delegationHash': delegationHash,
          'certificateProof': proof,
        },
        'witness': {
          'version': 2,
          'delegationProof': delegationProof,
          'certificateProof': proof,
          'disclosureSaltBase64': saltText,
          'disclosure': disclosure,
        },
      };
      await context.database.execute(
        'INSERT INTO crypto_export_drafts VALUES(?,?,?,?)',
        [
          partition,
          targetScopeId,
          actionId,
          CryptoBusinessJson.canonical({
            'operation': 'crypto2.records.batch.exportBinding',
            'intentHash': intentHash,
            'payload': result,
          }),
        ],
      );
      return result;
    } finally {
      salt.fillRange(0, salt.length, 0);
      lease.release();
    }
  }
}
