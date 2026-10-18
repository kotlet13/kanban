import 'dart:convert';
import 'dart:typed_data';
import 'package:sodium/sodium.dart' show SodiumException;

import 'account_directory_v2.dart';
import 'crypto_anchor_lock.dart';
import 'crypto_business_json.dart';
import 'crypto_business_router.dart';
import 'crypto_business_documents.dart';
import 'crypto_finance_account_choices.dart';
import 'crypto_json.dart';
import 'crypto_record_address.dart';
import 'crypto_record_proof_codec.dart';
import 'crypto_scoped_authority.dart';
import 'crypto_sync_repository.dart';
import 'session_crypto_access.dart';

class VerifiedScopedDisclosure {
  const VerifiedScopedDisclosure({
    required this.disclosure,
    required this.subjectToken,
    required this.sourceRevision,
    required this.sourceRecordProofHash,
    required this.certificateHash,
    this.historicalEvidence = false,
  });
  final Map<String, dynamic> disclosure;
  final String subjectToken, sourceRecordProofHash, certificateHash;
  final int sourceRevision;
  final bool historicalEvidence;
  // This is a selected issuer's attestation, never ledger completeness.
}

/// Target-manager-selected, narrowly scoped financial disclosure. Values stay
/// inside the target finance ciphertext. Proofs disclose only context, field
/// names and opaque commitments; a foreign issuer never becomes a global pin.
class CryptoScopedExports {
  CryptoScopedExports(this.access);
  final SessionCryptoAccess access;
  static const offerDomain = 'JivieE2EE/exportOffer/v2\n';
  static const certificateDomain = 'JivieE2EE/scopedExport/v2\n';
  static const allowedFields = <String, List<String>>{
    'financeAccountChoice': [
      'accountId',
      'accountScopeId',
      'archived',
      'currency',
      'name',
      'sourceRevision',
    ],
    'paymentSource': [
      'amountMinor',
      'currency',
      'eventId',
      'expectReimbursement',
      'paidAt',
      'payerAccountId',
      'reimbursements',
      'revision',
      'sourceEntryId',
      'sourceRevision',
      'sourceScopeId',
      'sourceState',
    ],
  };
  static Map<String, dynamic> commitmentContext(Map proofBody) => {
    for (final field in const [
      'version',
      'serverId',
      'scopeId',
      'purpose',
      'membershipHeadHash',
      'sourceScopeToken',
      'subjectToken',
      'sourceMembershipHeadHash',
      'sourceRecordProofHash',
      'sourceRevision',
      'accountId',
      'deviceId',
      'deviceSnapshotHash',
    ])
      field: proofBody[field],
  };

  /// Salt is secret disclosure material. It is carried only in the sealed
  /// bridge or the target finance AEAD witness, never in the public proof.
  static Future<String> disclosureHash({
    required Map<String, dynamic> disclosure,
    required Map proofBody,
    required String disclosureSaltBase64,
  }) async {
    final salt = cryptoBase64(disclosureSaltBase64, length: 32);
    try {
      return await cryptoSha256([
        ...utf8.encode('JivieScopedDisclosureCommitment/v2\n'),
        ...CryptoJson.encode(commitmentContext(proofBody)),
        10,
        ...salt,
        ...CryptoBusinessJson.encode(disclosure),
      ]);
    } finally {
      salt.fillRange(0, salt.length, 0);
    }
  }

  static Future<String> proofHash(Map<String, dynamic> proof) =>
      cryptoSha256(CryptoJson.encode(proof));
  void _fields(Map value, Set<String> fields) {
    if (value.length != fields.length ||
        value.keys.any((k) => !fields.contains(k))) {
      throw const FormatException('scoped_export_fields');
    }
  }

  void _hash(Object? value) {
    if (value is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(value)) {
      throw const FormatException('scoped_export_hash');
    }
  }

  Map<String, dynamic> _command(Map<String, dynamic> proof) =>
      Map<String, dynamic>.from(
        CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map,
      );
  bool _same(Object? a, Object? b) =>
      base64Encode(CryptoJson.encode(a)) == base64Encode(CryptoJson.encode(b));

  static Map<String, dynamic> bridgeContext(
    Map c,
    Map delegation,
    Map<String, dynamic> delegationProof,
  ) => {
    'version': 2,
    'purpose': 'JivieScopedDisclosure',
    'serverId': c['serverId'],
    'scopeId': c['scopeId'],
    'targetMembershipHeadHash': c['membershipHeadHash'],
    'expectedAccessRevision': delegation['expectedAccessRevision'],
    'delegationProofHash': c['delegationProofHash'],
    'offerHash': c['offerHash'],
    'sourceScopeToken': c['sourceScopeToken'],
    'subjectToken': c['subjectToken'],
    'exportPurpose': c['purpose'],
    'sourceRevision': c['sourceRevision'],
    'sourceRecordProofHash': c['sourceRecordProofHash'],
    'disclosureHash': c['disclosureHash'],
    'requestId': c['bridge']['requestId'],
    'recipient': delegation['bridgeRecipient'],
  };
  void validateBridge(Map c, Map delegation) {
    final recipient = delegation['bridgeRecipient'];
    if (recipient == null &&
        c['bridge'] == null &&
        c['purpose'] == 'paymentSource') {
      return;
    }
    if (recipient is! Map) {
      throw const FormatException('scoped_export_recipient');
    }
    _fields(recipient, {
      'accountId',
      'deviceId',
      'directoryHeadHash',
      'deviceSnapshotHash',
      'encryptionPublicKeyBase64',
    });
    if (!isCryptoCanonicalUuid(recipient['accountId']) ||
        !isCryptoCanonicalUuid(recipient['deviceId'])) {
      throw const FormatException('scoped_export_recipient');
    }
    _hash(recipient['directoryHeadHash']);
    _hash(recipient['deviceSnapshotHash']);
    cryptoBase64(recipient['encryptionPublicKeyBase64'], length: 32);
    final bridge = c['bridge'];
    if (bridge == null) {
      if (c['purpose'] == 'financeAccountChoice') {
        throw const FormatException('scoped_export_bridge_required');
      }
      return;
    }
    if (bridge is! Map) throw const FormatException('scoped_export_bridge');
    _fields(bridge, {
      'recipient',
      'requestId',
      'sealedDisclosureBase64',
      'ciphertextHash',
    });
    if (!_same(bridge['recipient'], recipient) ||
        !isCryptoCanonicalUuid(bridge['requestId'])) {
      throw const FormatException('scoped_export_bridge');
    }
    _hash(bridge['ciphertextHash']);
    final bytes = cryptoBase64(bridge['sealedDisclosureBase64']);
    if (bytes.length < 48 || bytes.length > 65536) {
      throw const FormatException('scoped_export_bridge_size');
    }
  }

  static const deliveryOperations = {
    'crypto2.exports.propose',
    'crypto2.exports.delegate',
    'crypto2.exports.certify',
  };

  /// Rechecks the immutable locally approved intent at the delivery boundary.
  /// Imported drafts remain quarantined and never enter this live table.
  static Future<void> verifyDelivery(SessionCryptoAccess access, Map c) async {
    if ((c['payload'] as Map?)?['variant'] ==
        CryptoFinanceAccountChoices.variant) {
      return CryptoFinanceAccountChoices.verifyDelivery(access, c);
    }
    final own = await access.account.directory.requireFresh();
    final rows = await access.account.store.database.rows(
      "SELECT payload FROM crypto_export_drafts WHERE partition=? AND json_extract(payload,'\$.requestId')=?",
      [access.account.store.partition, c['requestId']],
    );
    if (rows.length != 1) {
      throw const CryptoAuthorityPending('scoped_export_intent_missing');
    }
    final saved = jsonDecode(rows.single['payload'] as String) as Map;
    final helper = CryptoScopedExports(access);
    if (saved['operation'] != c['operation'] ||
        !helper._same(saved['payload'], c['payload'])) {
      throw const FormatException('scoped_export_intent_substitution');
    }
    final p = c['payload'] as Map;
    if (c['operation'] == 'crypto2.exports.delegate') {
      final head = await access.currentHead(p['scopeId'], online: true);
      if (head.headHash != p['membershipHeadHash'] ||
          head.accessRevision != p['expectedAccessRevision'] ||
          head.member(own.accountId)['manageKeys'] != true) {
        throw const CryptoAuthorityPending('scoped_export_target_changed');
      }
      final reference = await access.directoryAt(
        scopeId: p['scopeId'],
        scopeHeadHash: head.headHash,
        accountId: own.accountId,
        directoryHeadHash: p['authorDirectoryHeadHash'],
      );
      if (reference.deviceSnapshotHash != own.deviceSnapshotHash) {
        throw const CryptoAuthorityPending('scoped_export_manager_changed');
      }
      await CryptoScopedAuthority(access).current(
        scopeId: p['scopeId'],
        scopeHeadHash: head.headHash,
        accountId: p['issuerAccountId'],
        signingPublicKey: p['issuerRootSigningKeyBase64'],
        encryptionPublicKey: p['issuerRootEncryptionKeyBase64'],
        identityEpochId: p['issuerIdentityEpochId'],
        deviceSnapshotHash: p['issuerDeviceSnapshotHash'],
      );
    } else {
      final original = saved['sourceContext'] as Map;
      final proof = Map<String, dynamic>.from(
        p[c['operation'] == 'crypto2.exports.propose'
                ? 'offerProof'
                : 'certificateProof']
            as Map,
      );
      final body = helper._command(proof);
      final head = await access.currentHead(original['scopeId'], online: true);
      if (head.headHash != body['sourceMembershipHeadHash'] ||
          head.member(own.accountId)['financeRole'] == 'none' ||
          body['accountId'] != own.accountId ||
          body['deviceId'] != access.account.deviceId ||
          body['deviceSnapshotHash'] != own.deviceSnapshotHash) {
        throw const CryptoAuthorityPending('scoped_export_source_changed');
      }
      final record = await access.account.store.database.rows(
        'SELECT crypto_revision,record_proof_hash,deleted FROM crypto_business_records WHERE partition=? AND scope_id=? AND domain=? AND id=? AND type=?',
        [
          access.account.store.partition,
          original['scopeId'],
          'finance',
          original['id'],
          original['type'],
        ],
      );
      if (c['operation'] == 'crypto2.exports.propose' &&
          p['sourceProof'] != null) {
        final future = await verifyFuturePaymentSource(
          access,
          Map<String, dynamic>.from(p['sourceProof'] as Map),
          scopeId: original['scopeId'],
          canonicalId: original['canonicalId'],
        );
        if (body['purpose'] != 'paymentSource' ||
            body['sourceRevision'] != 1 ||
            future['proofHash'] != body['sourceRecordProofHash'] ||
            !helper._same(future['raw'], original['raw'])) {
          throw const FormatException('scoped_export_future_source');
        }
      } else if (record.length != 1 ||
          record.single['deleted'] == 1 ||
          record.single['crypto_revision'] != body['sourceRevision'] ||
          record.single['record_proof_hash'] != body['sourceRecordProofHash']) {
        throw const CryptoAuthorityPending('scoped_export_source_changed');
      }
      access.account.directory.reducer.crypto.verifyDomain(
        proof,
        cryptoBase64(
          own.activeDevice(access.account.deviceId)['signingKeyBase64'],
          length: 32,
        ),
        c['operation'] == 'crypto2.exports.propose'
            ? offerDomain
            : certificateDomain,
      );
      if (body['disclosureHash'] !=
          await disclosureHash(
            disclosure: Map<String, dynamic>.from(
              original['disclosure'] as Map,
            ),
            proofBody: body,
            disclosureSaltBase64: original['disclosureSaltBase64'],
          )) {
        throw const FormatException('scoped_export_commitment');
      }
    }
    if (!access.account.directory.isCurrent()) {
      throw const CryptoAuthorityPending('crypto_identity_changed');
    }
  }

  /// A private batch binding is deliverable only from this installation's
  /// immutable prepared intent. Restored candidate drafts are never installed
  /// in this live journal and cannot silently authorize a new delivery.
  static Future<void> verifyBatchDelivery(
    SessionCryptoAccess access,
    Map command,
  ) async {
    final payload = command['payload'] as Map;
    final bindings = payload['exportBindings'] as List? ?? const [];
    if (bindings.length > 32) {
      throw const FormatException('scoped_export_batch_bindings');
    }
    final records = <String, Map<String, dynamic>>{};
    for (final proof in payload['records'] as List) {
      final record = Map<String, dynamic>.from(
        CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map,
      );
      records['${record['scopeId']}:${record['id']}'] = record;
    }
    final commitment = Map<String, dynamic>.from(
      CryptoJson.decode(cryptoBase64(payload['commitment']['commandBase64']))
          as Map,
    );
    for (final value in bindings) {
      final binding = Map<String, dynamic>.from(value as Map);
      final certificate = Map<String, dynamic>.from(
        binding['certificateProof'] as Map,
      );
      final rows = await access.account.store.database.rows(
        "SELECT payload FROM crypto_export_drafts WHERE partition=? AND json_extract(payload,'\$.operation')=? AND json_extract(payload,'\$.payload.binding.certificateProof.commandBase64')=? AND json_extract(payload,'\$.payload.binding.certificateProof.signatureBase64')=? LIMIT 2",
        [
          access.account.store.partition,
          'crypto2.records.batch.exportBinding',
          certificate['commandBase64'],
          certificate['signatureBase64'],
        ],
      );
      if (rows.length != 1) {
        throw const CryptoAuthorityPending('scoped_export_intent_missing');
      }
      final saved = jsonDecode(rows.single['payload'] as String) as Map;
      final exact = saved['payload'] as Map;
      final helper = CryptoScopedExports(access);
      if (!helper._same(exact['binding'], binding)) {
        throw const FormatException('scoped_export_intent_substitution');
      }
      final target =
          records['${binding['targetScopeId']}:${binding['targetId']}'];
      final source =
          records['${binding['sourceScopeId']}:${binding['sourceId']}'];
      if (target == null ||
          source == null ||
          source['type'] != 'paymentEvent') {
        throw const FormatException('scoped_export_batch_records');
      }
      final witness = Map<String, dynamic>.from(exact['witness'] as Map);
      await helper.verify(
        targetScopeId: binding['targetScopeId'],
        purpose: 'paymentSource',
        disclosure: Map<String, dynamic>.from(witness['disclosure'] as Map),
        disclosureSaltBase64: witness['disclosureSaltBase64'],
        delegationProof: Map<String, dynamic>.from(
          witness['delegationProof'] as Map,
        ),
        certificateProof: certificate,
        targetRecord: target,
        batchCommitment: commitment,
        rememberFloor: false,
      );
    }
  }

  /// A future offer can reserve only a fresh, already sealed payment event.
  /// It grants no source visibility and never writes the business record.
  static Future<Map<String, dynamic>> verifyFuturePaymentSource(
    SessionCryptoAccess access,
    Map<String, dynamic> proof, {
    required String scopeId,
    required String canonicalId,
  }) async {
    final own = await access.account.directory.requireFresh();
    final crypto = access.account.directory.reducer.crypto;
    final body = crypto.verifyDomain(
      proof,
      cryptoBase64(
        own.activeDevice(access.account.deviceId)['signingKeyBase64'],
        length: 32,
      ),
      'JivieE2EE/record/v2\n',
    );
    final codec = CryptoRecordProofCodec(crypto);
    codec.validateUntrustedRecord(body);
    final head = await access.currentHead(scopeId, online: true);
    final address = CryptoRecordAddress.forType(
      serverId: own.serverId,
      scopeId: scopeId,
      type: 'paymentEvent',
      canonicalId: canonicalId,
      domain: 'finance',
    );
    if (body['serverId'] != own.serverId ||
        body['accountId'] != own.accountId ||
        body['deviceId'] != access.account.deviceId ||
        body['scopeId'] != scopeId ||
        body['domain'] != 'finance' ||
        body['type'] != 'paymentEvent' ||
        body['id'] != address.wireId ||
        body['expectedRevision'] != 0 ||
        body['deleted'] != false ||
        body['previousRecordHash'] != cryptoZeroHash ||
        body['membershipHeadHash'] != head.headHash ||
        body['epoch'] != head.epoch ||
        body['accessRevision'] != head.accessRevision ||
        head.member(own.accountId)['financeRole'] != 'write' ||
        CryptoBusinessJson.canonical(body['metadata']['identity']) !=
            CryptoBusinessJson.canonical(address.identity)) {
      throw const FormatException('scoped_export_future_source');
    }
    final rows = await access.account.store.database.rows(
      'SELECT 1 FROM crypto_business_records WHERE partition=? AND scope_id=? AND domain=? AND id=?',
      [access.account.store.partition, scopeId, 'finance', address.wireId],
    );
    if (rows.isNotEmpty) {
      throw const CryptoAuthorityPending('scoped_export_source_changed');
    }
    final key = await access.getScopeKey(scopeId, 'finance', head.epoch);
    Uint8List? bytes;
    try {
      bytes = codec.openVerified(body, key.key);
      if (bytes == null) {
        throw const FormatException('scoped_export_future_source');
      }
      final envelope = jsonDecode(utf8.decode(bytes));
      if (envelope is! Map ||
          envelope.length != 3 ||
          envelope['format'] != 2 ||
          envelope['payload'] is! Map ||
          CryptoBusinessJson.canonical(envelope['identity']) !=
              CryptoBusinessJson.canonical(address.identity)) {
        throw const FormatException('scoped_export_future_source');
      }
      return {
        'record': body,
        'raw': Map<String, dynamic>.from(envelope['payload'] as Map),
        'proofHash': await codec.digest(proof),
      };
    } finally {
      bytes?.fillRange(0, bytes.length, 0);
      key.release();
    }
  }

  Future<VerifiedScopedDisclosure> openBridge({
    required String targetScopeId,
    required String purpose,
    required Map<String, dynamic> delegationProof,
    required Map<String, dynamic> certificateProof,
  }) async {
    final c = _command(certificateProof),
        d = _command(delegationProof),
        p = d['payload'] as Map;
    validateBridge(c, p);
    if (c['bridge'] == null) {
      throw const FormatException('scoped_export_bridge_required');
    }
    final recipient = p['bridgeRecipient'] as Map,
        own = await access.account.directory.requireFresh();
    final device = own.activeDevice(access.account.deviceId);
    if (recipient['accountId'] != own.accountId ||
        recipient['deviceId'] != access.account.deviceId ||
        recipient['deviceSnapshotHash'] != own.deviceSnapshotHash ||
        recipient['encryptionPublicKeyBase64'] !=
            device['encryptionKeyBase64']) {
      throw const CryptoAuthorityPending('scoped_export_recipient_changed');
    }
    final cipher = cryptoBase64(c['bridge']['sealedDisclosureBase64']);
    if (await cryptoSha256(cipher) != c['bridge']['ciphertextHash']) {
      throw const FormatException('scoped_export_bridge_hash');
    }
    final key = await access.account.encryptionKey();
    Uint8List? bytes;
    try {
      try {
        bytes = access.account.directory.reducer.crypto.sodium.crypto.box
            .sealOpen(
              cipherText: cipher,
              publicKey: key.publicKey,
              secretKey: key.secretKey,
            );
      } on SodiumException {
        throw const FormatException('crypto_authentication');
      }
      final raw = jsonDecode(utf8.decode(bytes)) as Map;
      _fields(raw, {'context', 'disclosure', 'disclosureSaltBase64'});
      if (!_same(raw['context'], bridgeContext(c, p, delegationProof))) {
        throw const FormatException('scoped_export_bridge_context');
      }
      return await verify(
        targetScopeId: targetScopeId,
        purpose: purpose,
        disclosure: Map<String, dynamic>.from(raw['disclosure'] as Map),
        disclosureSaltBase64: raw['disclosureSaltBase64'] as String,
        delegationProof: delegationProof,
        certificateProof: certificateProof,
      );
    } finally {
      bytes?.fillRange(0, bytes.length, 0);
      key.secretKey.dispose();
    }
  }

  /// Only the witness actually encrypted in this independently anchored target
  /// record may use historical issuer authority. Caller-provided raw payloads,
  /// current carriers and imported SQL verdicts cannot enable this path.
  Future<VerifiedScopedDisclosure> verifyHistoricalTarget(
    Map<String, dynamic> targetWire, {
    Map<String, dynamic>? anchorWire,
  }) async {
    final recordCodec = CryptoRecordProofCodec(
      access.account.directory.reducer.crypto,
    );
    final authority = anchorWire == null
        ? await access.historicalTargetAuthority(targetWire)
        : await access.historicalCarrierAuthority(
            targetWire,
            anchorWire: anchorWire,
          );
    final body = await recordCodec.verifyWire(
      serverId: access.account.directory.session.profile.serverId,
      wire: targetWire,
      trustedSigningKey: authority.signingKey,
      currentEpoch: authority.currentEpoch,
      closedRecordProofHash: authority.closedRecordProofHash,
    );
    if (body['domain'] != 'finance' ||
        !const {'cashMovement', 'paymentProjection'}.contains(body['type'])) {
      throw const FormatException('scoped_export_historical_target');
    }
    final historical = await _HistoricalExportEvidence.open(
      access,
      targetWire,
      body,
      anchorWire: anchorWire,
    );
    final key = await access.getScopeKey(
      body['scopeId'],
      'finance',
      body['epoch'],
    );
    Uint8List? bytes;
    try {
      bytes = recordCodec.openVerified(body, key.key);
      if (bytes == null) {
        throw const FormatException('scoped_export_historical_target');
      }
      final envelope = jsonDecode(utf8.decode(bytes));
      if (envelope is! Map ||
          envelope.length != 3 ||
          envelope['format'] != 2 ||
          !_same(envelope['identity'], body['metadata']['identity']) ||
          envelope['payload'] is! Map) {
        throw const FormatException('scoped_export_historical_target');
      }
      final incoming = CryptoProjectionRecord(
        targetWire,
        body,
        bytes,
        historyBasis: authority.historyBasis ?? 'verifiedCheckpoint',
        batchKey: body['batchId'],
      );
      final documents = CryptoBusinessDocuments(
        CryptoBusinessSession(
          access.account,
          access,
          access.account.store.database,
        ),
      );
      await documents.prepareRecords([incoming]);
      final expanded = await documents.expandPayload(
        incoming,
        Map<String, dynamic>.from(envelope['payload'] as Map),
      );
      final witness = expanded['paymentSourceWitness'];
      if (witness is! Map) {
        throw const CryptoAuthorityPending('scoped_export_witness_pending');
      }
      _fields(witness, {
        'version',
        'delegationProof',
        'certificateProof',
        'disclosureSaltBase64',
        'disclosure',
      });
      if (witness['version'] != 2 || witness['disclosure'] is! Map) {
        throw const FormatException('scoped_export_witness');
      }
      historical.certificateHash = await proofHash(
        Map<String, dynamic>.from(witness['certificateProof'] as Map),
      );
      final batchProof = Map<String, dynamic>.from(
        (targetWire['authorization'] as Map)['batchCommitment'] as Map,
      );
      final result = await _verify(
        targetScopeId: body['scopeId'],
        purpose: 'paymentSource',
        disclosure: Map<String, dynamic>.from(witness['disclosure'] as Map),
        disclosureSaltBase64: witness['disclosureSaltBase64'],
        delegationProof: Map<String, dynamic>.from(
          witness['delegationProof'] as Map,
        ),
        certificateProof: Map<String, dynamic>.from(
          witness['certificateProof'] as Map,
        ),
        targetRecord: body,
        batchCommitment: _command(batchProof),
        rememberFloor: false,
        historical: historical,
      );
      await historical.guard();
      return result;
    } finally {
      bytes?.fillRange(0, bytes.length, 0);
      key.release();
    }
  }

  Future<VerifiedScopedDisclosure> verify({
    required String targetScopeId,
    required String purpose,
    required Map<String, dynamic> disclosure,
    required String disclosureSaltBase64,
    required Map<String, dynamic> delegationProof,
    required Map<String, dynamic> certificateProof,
    Map<String, dynamic>? targetRecord,
    Map<String, dynamic>? batchCommitment,
    bool rememberFloor = true,
  }) => _verify(
    targetScopeId: targetScopeId,
    purpose: purpose,
    disclosure: disclosure,
    disclosureSaltBase64: disclosureSaltBase64,
    delegationProof: delegationProof,
    certificateProof: certificateProof,
    targetRecord: targetRecord,
    batchCommitment: batchCommitment,
    rememberFloor: rememberFloor,
  );

  Future<VerifiedScopedDisclosure> _verify({
    required String targetScopeId,
    required String purpose,
    required Map<String, dynamic> disclosure,
    required String disclosureSaltBase64,
    required Map<String, dynamic> delegationProof,
    required Map<String, dynamic> certificateProof,
    Map<String, dynamic>? targetRecord,
    Map<String, dynamic>? batchCommitment,
    bool rememberFloor = true,
    _HistoricalExportEvidence? historical,
  }) async {
    final fields = allowedFields[purpose];
    if (fields == null || !isCryptoCanonicalUuid(targetScopeId)) {
      throw const FormatException('scoped_export_purpose');
    }
    _fields(disclosure, fields.toSet());
    final managerCommand = _command(delegationProof);
    _fields(managerCommand, {
      'version',
      'operation',
      'requestId',
      'serverId',
      'accountId',
      'deviceId',
      'signer',
      'payload',
    });
    final p = Map<String, dynamic>.from(managerCommand['payload'] as Map);
    _fields(p, {
      'scopeId',
      'membershipHeadHash',
      'expectedAccessRevision',
      'authorDirectoryHeadHash',
      'delegationId',
      'purpose',
      'offerHash',
      'issuerAccountId',
      'issuerDirectoryHeadHash',
      'issuerRootSigningKeyBase64',
      'issuerRootEncryptionKeyBase64',
      'issuerIdentityEpochId',
      'issuerDeviceSnapshotHash',
      'sourceScopeToken',
      'subjectToken',
      'permittedFields',
      'bridgeRecipient',
    });
    final head = historical == null
        ? await access.currentHead(targetScopeId, online: true)
        : await access.headAt(targetScopeId, historical.headHash);
    final server = access.account.directory.session.profile.serverId;
    if (managerCommand['version'] != 2 ||
        managerCommand['operation'] != 'crypto2.exports.delegate' ||
        managerCommand['signer'] != 'device' ||
        managerCommand['serverId'] != server ||
        p['scopeId'] != targetScopeId ||
        p['membershipHeadHash'] != head.headHash ||
        p['expectedAccessRevision'] != head.accessRevision ||
        p['purpose'] != purpose ||
        !_same(p['permittedFields'], fields) ||
        head.member(managerCommand['accountId'])['manageKeys'] != true) {
      throw const FormatException('scoped_export_delegation');
    }
    for (final key in ['requestId', 'accountId', 'deviceId']) {
      if (!isCryptoCanonicalUuid(managerCommand[key])) {
        throw const FormatException('scoped_export_uuid');
      }
    }
    for (final key in [
      'delegationId',
      'issuerAccountId',
      'issuerIdentityEpochId',
    ]) {
      if (!isCryptoCanonicalUuid(p[key])) {
        throw const FormatException('scoped_export_uuid');
      }
    }
    for (final key in [
      'membershipHeadHash',
      'authorDirectoryHeadHash',
      'offerHash',
      'issuerDirectoryHeadHash',
      'issuerDeviceSnapshotHash',
      'sourceScopeToken',
      'subjectToken',
    ]) {
      _hash(p[key]);
    }
    final manager = historical == null
        ? await access.directoryAt(
            scopeId: targetScopeId,
            scopeHeadHash: head.headHash,
            accountId: managerCommand['accountId'],
            directoryHeadHash: p['authorDirectoryHeadHash'],
          )
        : await historical.directory(
            managerCommand['accountId'],
            p['authorDirectoryHeadHash'],
          );
    if (historical == null) {
      final currentManager = await access.currentMemberDirectory(
        targetScopeId,
        head.headHash,
        managerCommand['accountId'],
      );
      if (currentManager.deviceSnapshotHash != manager.deviceSnapshotHash) {
        throw const CryptoAuthorityPending('scoped_export_manager_changed');
      }
    } else {
      historical.matchMember(manager, head.member(managerCommand['accountId']));
    }
    final managerDevice = manager.activeDevice(managerCommand['deviceId']);
    final crypto = access.account.directory.reducer.crypto;
    crypto.verifyDomain(
      delegationProof,
      cryptoBase64(managerDevice['signingKeyBase64'], length: 32),
      cryptoDirectoryDomain,
    );
    final selected = historical == null
        ? await access.directoryAt(
            scopeId: targetScopeId,
            scopeHeadHash: head.headHash,
            accountId: p['issuerAccountId'],
            directoryHeadHash: p['issuerDirectoryHeadHash'],
            online: true,
            allowUnverifiedContact: true,
          )
        : await historical.directory(
            p['issuerAccountId'],
            p['issuerDirectoryHeadHash'],
          );
    final issuer = historical == null
        ? await CryptoScopedAuthority(access).current(
            scopeId: targetScopeId,
            scopeHeadHash: head.headHash,
            accountId: p['issuerAccountId'],
            signingPublicKey: p['issuerRootSigningKeyBase64'],
            encryptionPublicKey: p['issuerRootEncryptionKeyBase64'],
            identityEpochId: p['issuerIdentityEpochId'],
            deviceSnapshotHash: p['issuerDeviceSnapshotHash'],
          )
        : selected;
    if (!issuer.includesAnchor(selected.generation, selected.headHash) ||
        selected.deviceSnapshotHash != p['issuerDeviceSnapshotHash'] ||
        selected.snapshot['rootSigningKeyBase64'] !=
            p['issuerRootSigningKeyBase64'] ||
        selected.snapshot['rootEncryptionKeyBase64'] !=
            p['issuerRootEncryptionKeyBase64'] ||
        selected.identityEpochId != p['issuerIdentityEpochId']) {
      throw const CryptoAuthorityPending('scoped_export_issuer_changed');
    }
    final recipient = p['bridgeRecipient'];
    if (recipient != null) {
      if (recipient is! Map ||
          head.member(recipient['accountId'])['financeRole'] == 'none') {
        throw const FormatException('scoped_export_recipient_role');
      }
      final recipientReference = historical == null
          ? await access.directoryAt(
              scopeId: targetScopeId,
              scopeHeadHash: head.headHash,
              accountId: recipient['accountId'],
              directoryHeadHash: recipient['directoryHeadHash'],
            )
          : await historical.directory(
              recipient['accountId'],
              recipient['directoryHeadHash'],
            );
      final currentRecipient = historical == null
          ? await access.currentMemberDirectory(
              targetScopeId,
              head.headHash,
              recipient['accountId'],
            )
          : recipientReference;
      if (historical != null) {
        historical.matchMember(
          recipientReference,
          head.member(recipient['accountId']),
        );
      }
      final recipientDevice = recipientReference.activeDevice(
        recipient['deviceId'],
      );
      if (currentRecipient.deviceSnapshotHash !=
              recipient['deviceSnapshotHash'] ||
          recipientReference.deviceSnapshotHash !=
              recipient['deviceSnapshotHash'] ||
          recipientDevice['encryptionKeyBase64'] !=
              recipient['encryptionPublicKeyBase64']) {
        throw const CryptoAuthorityPending('scoped_export_recipient_changed');
      }
    }
    final c = _command(certificateProof);
    _fields(c, {
      'version',
      'operation',
      'serverId',
      'purpose',
      'scopeId',
      'membershipHeadHash',
      'sourceScopeToken',
      'subjectToken',
      'sourceMembershipHeadHash',
      'sourceRecordProofHash',
      'sourceRevision',
      'accountId',
      'deviceId',
      'authorDirectoryHeadHash',
      'deviceSnapshotHash',
      'disclosureHash',
      'permittedFields',
      'offerHash',
      'delegationProofHash',
      'bridge',
      if (c.containsKey('batchContext')) 'batchContext',
    });
    if (c['version'] != 2 ||
        c['operation'] != 'crypto2.exports.certificate' ||
        c['serverId'] != server ||
        c['scopeId'] != targetScopeId ||
        c['membershipHeadHash'] != head.headHash ||
        c['purpose'] != purpose ||
        c['sourceScopeToken'] != p['sourceScopeToken'] ||
        c['subjectToken'] != p['subjectToken'] ||
        c['accountId'] != p['issuerAccountId'] ||
        c['deviceSnapshotHash'] != p['issuerDeviceSnapshotHash'] ||
        c['offerHash'] != p['offerHash'] ||
        c['delegationProofHash'] != await proofHash(delegationProof) ||
        !_same(c['permittedFields'], fields) ||
        c['sourceRevision'] is! int ||
        c['sourceRevision'] < 1 ||
        c['sourceRevision'] > 9007199254740991 ||
        c['disclosureHash'] !=
            await disclosureHash(
              disclosure: disclosure,
              proofBody: c,
              disclosureSaltBase64: disclosureSaltBase64,
            )) {
      throw const FormatException('scoped_export_certificate');
    }
    final batch = c['batchContext'];
    if (batch != null) {
      if (batch is! Map || targetRecord == null || batchCommitment == null) {
        throw const FormatException('scoped_export_batch_context');
      }
      _fields(batch, {
        'batchId',
        'sourceOperationId',
        'sourceExpectedRevision',
        'targetOperationId',
        'targetExpectedRevision',
        'targetId',
        'targetIdentity',
        'targetMembershipHeadHash',
      });
      for (final field in [
        'batchId',
        'sourceOperationId',
        'targetOperationId',
      ]) {
        if (!isCryptoCanonicalUuid(batch[field])) {
          throw const FormatException('scoped_export_batch_context');
        }
      }
      if (targetRecord['scopeId'] != targetScopeId ||
          targetRecord['domain'] != 'finance' ||
          !const {
            'cashMovement',
            'paymentProjection',
          }.contains(targetRecord['type']) ||
          !isCryptoWireRecordId(batch['targetId']) ||
          batch['sourceExpectedRevision'] is! int ||
          batch['sourceExpectedRevision'] < 0 ||
          batch['targetExpectedRevision'] is! int ||
          batch['targetExpectedRevision'] < 0 ||
          c['sourceRevision'] != batch['sourceExpectedRevision'] + 1 ||
          batch['batchId'] != targetRecord['batchId'] ||
          batch['batchId'] != batchCommitment['batchId'] ||
          batch['targetOperationId'] != targetRecord['operationId'] ||
          batch['targetExpectedRevision'] != targetRecord['expectedRevision'] ||
          batch['targetId'] != targetRecord['id'] ||
          batch['targetMembershipHeadHash'] !=
              targetRecord['membershipHeadHash'] ||
          batch['targetMembershipHeadHash'] != head.headHash ||
          !_same(
            batch['targetIdentity'],
            targetRecord['metadata']?['identity'],
          ) ||
          c['accountId'] != targetRecord['accountId'] ||
          c['deviceId'] != targetRecord['deviceId'] ||
          batchCommitment['recordDigests'] is! List ||
          !(batchCommitment['recordDigests'] as List).contains(
            c['sourceRecordProofHash'],
          )) {
        throw const FormatException('scoped_export_batch_context');
      }
    }
    validateBridge(c, p);
    if (c['bridge'] != null &&
        await cryptoSha256(
              cryptoBase64(c['bridge']['sealedDisclosureBase64']),
            ) !=
            c['bridge']['ciphertextHash']) {
      throw const FormatException('scoped_export_bridge_hash');
    }
    for (final key in [
      'sourceMembershipHeadHash',
      'sourceRecordProofHash',
      'authorDirectoryHeadHash',
      'disclosureHash',
    ]) {
      _hash(c[key]);
    }
    if (!isCryptoCanonicalUuid(c['deviceId'])) {
      throw const FormatException('scoped_export_uuid');
    }
    final exact = historical == null
        ? await access.directoryAt(
            scopeId: targetScopeId,
            scopeHeadHash: head.headHash,
            accountId: issuer.accountId,
            directoryHeadHash: c['authorDirectoryHeadHash'],
            online: true,
            allowUnverifiedContact: true,
          )
        : await historical.directory(
            issuer.accountId,
            c['authorDirectoryHeadHash'],
          );
    if ((historical == null &&
            !issuer.includesAnchor(exact.generation, exact.headHash)) ||
        exact.deviceSnapshotHash != issuer.deviceSnapshotHash ||
        exact.snapshot['rootSigningKeyBase64'] !=
            p['issuerRootSigningKeyBase64'] ||
        exact.snapshot['rootEncryptionKeyBase64'] !=
            p['issuerRootEncryptionKeyBase64'] ||
        exact.identityEpochId != p['issuerIdentityEpochId']) {
      throw const CryptoAuthorityPending('scoped_export_issuer_changed');
    }
    final device = exact.activeDevice(c['deviceId']);
    crypto.verifyDomain(
      certificateProof,
      cryptoBase64(device['signingKeyBase64'], length: 32),
      certificateDomain,
    );
    final key =
        'scopedExport2:${access.account.store.partition}:$targetScopeId:$purpose:${c['subjectToken']}';
    if (historical != null) {
      await historical.guard();
    } else {
      await withCryptoAnchorLock(access.account.store.partition, () async {
        final scopePin = await access.account.store.secure.read(
          'scope2:${access.account.store.partition}:$targetScopeId',
        );
        if (scopePin == null ||
            (CryptoJson.decode(Uint8List.fromList(utf8.encode(scopePin)))
                    as Map)['headHash'] !=
                head.headHash) {
          throw const CryptoAuthorityPending('scoped_export_target_changed');
        }
        final scopedFloor = await access.account.store.secure.read(
          'scopedAuthority2:${access.account.store.partition}:$targetScopeId:${issuer.accountId}',
        );
        if (scopedFloor != null) {
          final floor =
              CryptoJson.decode(Uint8List.fromList(utf8.encode(scopedFloor)))
                  as Map;
          if (!issuer.includesAnchor(floor['generation'], floor['headHash'])) {
            throw const CryptoAuthorityPending('scoped_export_issuer_changed');
          }
        }
        final knownIssuer = await access.account.store.anchor(issuer.accountId);
        if (knownIssuer != null &&
            knownIssuer['deviceSnapshotHash'] != issuer.deviceSnapshotHash) {
          throw const CryptoAuthorityPending('scoped_export_issuer_changed');
        }
        final raw = await access.account.store.secure.read(key);
        if (raw != null) {
          final floor =
              CryptoJson.decode(Uint8List.fromList(utf8.encode(raw))) as Map;
          if (c['sourceRevision'] < floor['sourceRevision'] ||
              c['sourceRevision'] == floor['sourceRevision'] &&
                  c['sourceRecordProofHash'] !=
                      floor['sourceRecordProofHash']) {
            throw const FormatException('scoped_export_source_rollback');
          }
        }
        if (!access.account.directory.isCurrent()) {
          throw const CryptoAuthorityPending('crypto_identity_changed');
        }
        if (!rememberFloor) return;
        await access.account.store.secure.write(
          key,
          utf8.decode(
            CryptoJson.encode({
              'sourceRevision': c['sourceRevision'],
              'sourceRecordProofHash': c['sourceRecordProofHash'],
              'disclosureHash': c['disclosureHash'],
            }),
          ),
        );
      });
    }
    return VerifiedScopedDisclosure(
      disclosure: Map<String, dynamic>.unmodifiable(disclosure),
      subjectToken: c['subjectToken'],
      sourceRevision: c['sourceRevision'],
      sourceRecordProofHash: c['sourceRecordProofHash'],
      certificateHash: await proofHash(certificateProof),
      historicalEvidence: historical != null,
    );
  }
}

/// An isolated exact-prefix replay. No directory rows, global contacts, secure
/// source floors or live issuance authority are installed by this verifier.
class _HistoricalExportEvidence {
  _HistoricalExportEvidence(
    this.access,
    this.wire,
    this.scopeId,
    this.headHash,
    this.scopePin,
    this.ownPin,
    this.anchorWire,
  );
  final SessionCryptoAccess access;
  final Map<String, dynamic> wire;
  final Map<String, dynamic>? anchorWire;
  final String scopeId, headHash;
  final String? scopePin, ownPin;
  String? certificateHash;
  final _directories = <String, Future<VerifiedAccountDirectory>>{};

  static Future<_HistoricalExportEvidence> open(
    SessionCryptoAccess access,
    Map<String, dynamic> wire,
    Map body, {
    Map<String, dynamic>? anchorWire,
  }) async {
    final partition = access.account.store.partition;
    final scope = body['scopeId'] as String;
    final result = _HistoricalExportEvidence(
      access,
      wire,
      scope,
      body['membershipHeadHash'],
      await access.account.store.secure.read('scope2:$partition:$scope'),
      await access.account.store.secure.read(
        'directory2:$partition:${access.account.directory.accountId}',
      ),
      anchorWire,
    );
    await result.guard();
    return result;
  }

  Future<void> guard() async {
    final partition = access.account.store.partition;
    if (!access.account.directory.isCurrent() ||
        scopePin == null ||
        ownPin == null ||
        await access.account.store.secure.read('scope2:$partition:$scopeId') !=
            scopePin ||
        await access.account.store.secure.read(
              'directory2:$partition:${access.account.directory.accountId}',
            ) !=
            ownPin) {
      throw const CryptoAuthorityPending(
        'scoped_export_historical_authority_changed',
      );
    }
    if (anchorWire == null) {
      await access.historicalTargetAuthority(wire);
    } else {
      await access.historicalCarrierAuthority(wire, anchorWire: anchorWire!);
    }
    if (!access.account.directory.isCurrent() ||
        await access.account.store.secure.read('scope2:$partition:$scopeId') !=
            scopePin ||
        await access.account.store.secure.read(
              'directory2:$partition:${access.account.directory.accountId}',
            ) !=
            ownPin) {
      throw const CryptoAuthorityPending(
        'scoped_export_historical_authority_changed',
      );
    }
  }

  void matchMember(VerifiedAccountDirectory directory, Map member) {
    if (directory.snapshot['rootSigningKeyBase64'] !=
            member['rootSigningKeyBase64'] ||
        directory.snapshot['rootEncryptionKeyBase64'] !=
            member['rootEncryptionKeyBase64'] ||
        directory.identityEpochId != member['identityEpochId'] ||
        directory.deviceSnapshotHash != member['deviceSnapshotHash']) {
      throw const FormatException('scoped_export_historical_member');
    }
  }

  Future<VerifiedAccountDirectory> directory(
    String accountId,
    String headHash,
  ) => _directories.putIfAbsent(
    '$accountId:$headHash',
    () => _load(accountId, headHash),
  );

  Future<VerifiedAccountDirectory> _load(
    String accountId,
    String headHash,
  ) async {
    final reducer = access.account.directory.reducer;
    final server = access.account.directory.session.profile.serverId;
    VerifiedAccountDirectory? state;
    String? genesis, header;
    var after = 0;
    while (true) {
      await guard();
      final page = await access.account.directory
          .call('crypto2.exports.evidence.directory', {
            'scopeId': scopeId,
            'certificateHash': certificateHash,
            'accountId': accountId,
            'directoryHeadHash': headHash,
            'afterGeneration': after,
            'limit': 20,
          });
      final expectedHeader = base64Encode(
        CryptoJson.encode({
          for (final k in const [
            'accountId',
            'generation',
            'headHash',
            'snapshotHash',
            'deviceSnapshotHash',
          ])
            k: page[k],
        }),
      );
      if (page['accountId'] != accountId ||
          page['headHash'] != headHash ||
          page['generation'] is! int ||
          page['generation'] < 1 ||
          header != null && header != expectedHeader ||
          page['proofs'] is! List ||
          (page['proofs'] as List).length > 20) {
        throw const FormatException('scoped_export_historical_directory');
      }
      header ??= expectedHeader;
      for (final raw in page['proofs'] as List) {
        final proof = Map<String, dynamic>.from(raw as Map);
        final command =
            CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map;
        final payload = command['payload'] as Map;
        genesis ??= reducer.crypto.fingerprint(
          cryptoBase64(payload['rootSigningKeyBase64'], length: 32),
          cryptoBase64(payload['rootEncryptionKeyBase64'], length: 32),
        );
        final commandHash = await cryptoSha256(
          cryptoBase64(proof['commandBase64']),
        );
        final generation = (state?.generation ?? 0) + 1;
        final previous = state?.headHash ?? cryptoZeroHash;
        final entryHash = await cryptoSha256(
          utf8.encode(cryptoDirectoryLogDomain) +
              CryptoJson.encode({
                'serverId': server,
                'accountId': accountId,
                'generation': generation,
                'previousHeadHash': previous,
                'commandHash': commandHash,
                'signatureBase64': proof['signatureBase64'],
              }),
        );
        state = await reducer.apply(
          previous: state,
          entry: {
            'generation': generation,
            'previousHeadHash': previous,
            'commandHash': commandHash,
            'headHash': entryHash,
            'authorization': proof,
          },
          serverId: server,
          accountId: accountId,
          pinnedRootFingerprint: genesis,
        );
        if (state.generation > page['generation']) {
          throw const FormatException('scoped_export_historical_directory');
        }
      }
      if (page['hasMore'] != true) {
        if (state == null ||
            state.generation != page['generation'] ||
            state.headHash != headHash ||
            state.snapshotHash != page['snapshotHash'] ||
            state.deviceSnapshotHash != page['deviceSnapshotHash']) {
          throw const FormatException('scoped_export_historical_directory');
        }
        await guard();
        return state;
      }
      if (state == null ||
          state.generation <= after ||
          page['nextGeneration'] != state.generation) {
        throw const FormatException(
          'scoped_export_historical_directory_cursor',
        );
      }
      after = state.generation;
    }
  }
}
