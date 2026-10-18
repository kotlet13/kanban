import 'dart:convert';
import 'package:sodium/sodium.dart';

import 'crypto_business_json.dart';

import 'crypto_business_router.dart';
import 'crypto_capture_v3.dart';
import 'crypto_finance_account_choices.dart';
import 'crypto_finance_choice_capture.dart';
import 'crypto_record_address.dart';
import 'crypto_migration_record_source.dart';
import 'crypto_sync_repository.dart';
import 'scope_crypto_codec.dart';

/// The sanitized handoff has its own derived companion. It never substitutes
/// for a parent's raw account record or a generic same-type source decoder.
abstract final class CryptoMigrationCapturedChoices {
  static String name(String partition, String capture, String scope) =>
      'migration_choice_handoff:$partition:$capture:$scope';

  static bool needed(CryptoMigrationRecordSource source) =>
      source.type == 'financeEntry' &&
      !source.deleted &&
      source.rawPayload?['accountScopeId'] is String &&
      source.rawPayload!['accountScopeId'] != source.scopeId;

  static Future<Map<String, dynamic>> load(
    CryptoBusinessSession runtime,
    String capture,
    String scope,
    VerifiedScopeHead head,
  ) async {
    final rows = await runtime.db.rows(
      'SELECT value FROM local_meta WHERE name=?',
      [name(runtime.partition, capture, scope)],
    );
    if (rows.length != 1) {
      throw const CryptoAuthorityPending(
        'crypto_account_choices_capture_review_pending',
      );
    }
    final raw = Map<String, dynamic>.from(
      jsonDecode(rows.single['value'] as String),
    );
    final c = raw['capture3']['context'] as Map;
    if (c['target']['captureId'] != capture ||
        c['target']['scopeId'] != scope ||
        c['target']['accountId'] != runtime.account.directory.accountId) {
      throw const FormatException('crypto_account_choices_capture_context');
    }
    await CryptoFinanceAccountChoices(
      runtime,
    ).verifyCapturedHandoff(raw, exactTargetHead: head);
    return raw;
  }

  static Map<String, dynamic> decorate(
    Map<String, dynamic> source, {
    required String manifestId,
    required String proofHash,
    required String headHash,
    required String selectionHash,
  }) {
    if (source.containsKey('accountChoiceWitness')) {
      throw const FormatException('crypto_account_choices_reserved_field');
    }
    return {
      ...source,
      'accountChoiceWitness': {
        'version': 2,
        'manifestId': manifestId,
        'revision': 1,
        'recordProofHash': proofHash,
        'targetHeadHash': headHash,
        'selectionHash': selectionHash,
      },
    };
  }

  /// Checks only the exact technical addition against a signed local reference.
  /// The referenced manifest's purpose verifier independently checks the issuer
  /// and target-manager signatures and its final scoped publication.
  static Future<Map<String, dynamic>> expectedPrimary(
    CryptoMigrationRecordSource source,
    Map<String, dynamic> record,
    Map<String, dynamic> envelope,
    Future<String> Function(String, String) reservedId,
  ) async {
    final original = source.rawPayload!;
    if (!needed(source)) return original;
    final actual = envelope['payload'];
    if (actual is! Map || actual['accountChoiceWitness'] is! Map) {
      throw const FormatException('crypto_account_choices_capture_witness');
    }
    final w = Map<String, dynamic>.from(actual['accountChoiceWitness']);
    const keys = {
      'version',
      'manifestId',
      'revision',
      'recordProofHash',
      'targetHeadHash',
      'selectionHash',
    };
    final manifestId = await reservedId(
      source.scopeId,
      'financeAccountChoices',
    );
    if (w.length != keys.length ||
        !w.keys.every(keys.contains) ||
        w['version'] != 2 ||
        w['manifestId'] != manifestId ||
        w['revision'] != 1 ||
        w['targetHeadHash'] != record['membershipHeadHash']) {
      throw const FormatException('crypto_account_choices_capture_witness');
    }
    for (final key in ['recordProofHash', 'selectionHash']) {
      if (w[key] is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(w[key])) {
        throw const FormatException('crypto_account_choices_capture_witness');
      }
    }
    final wire = runtimeWire(record['serverId'], source.scopeId, manifestId);
    final refs = (record['metadata']['referenceVersions'] as List)
        .where(
          (r) =>
              r['scopeId'] == source.scopeId &&
              r['domain'] == 'finance' &&
              r['id'] == wire &&
              r['revision'] == 1 &&
              r['recordProofHash'] == w['recordProofHash'],
        )
        .toList();
    if (refs.length != 1) {
      throw const FormatException('crypto_account_choices_capture_witness');
    }
    return decorate(
      original,
      manifestId: manifestId,
      proofHash: w['recordProofHash'],
      headHash: w['targetHeadHash'],
      selectionHash: w['selectionHash'],
    );
  }

  static String runtimeWire(String server, String scope, String id) =>
      cryptoWireRecordId(server, scope, 'financeAccountChoice', id);

  /// Preparatory only. A companion is emitted by its exact captured child
  /// binding; all other preserved entries reference that same immutable proof.
  static Future<
    ({Map<String, dynamic>? proof, String hash, Map<String, dynamic> raw})
  >
  prepareCompanion(
    CryptoBusinessSession runtime, {
    required String migrationId,
    required String captureId,
    required String bindingId,
    required String batchId,
    required String operationId,
    required Map<String, dynamic> migrationTag,
    required VerifiedScopeHead head,
    required SecureKey financeKey,
    required SecureKey signingKey,
  }) async {
    final raw = await load(runtime, captureId, head.scopeId, head);
    final sourceBinding = raw['capture3']['context']['childBinding'] as Map;
    final id = await runtime.reservedRecordId(
      head.scopeId,
      'financeAccountChoices',
    );
    final address = runtime.address(
      head.scopeId,
      'finance',
      'financeAccountChoice',
      id,
    );
    if (sourceBinding['bindingId'] != bindingId) {
      final staged = await runtime.db.rows(
        'SELECT record_proof_hash FROM crypto_migration_staged_records WHERE partition=? AND migration_id=? AND scope_id=? AND domain=? AND record_id=?',
        [
          runtime.partition,
          migrationId,
          head.scopeId,
          'finance',
          address.wireId,
        ],
      );
      if (staged.length != 1) {
        throw const CryptoAuthorityPending(
          'crypto_account_choices_capture_companion_pending',
        );
      }
      return (
        proof: null,
        hash: staged.single['record_proof_hash'] as String,
        raw: raw,
      );
    }
    final bytes = CryptoBusinessJson.encode({
      'format': 2,
      'identity': address.identity,
      'payload': raw,
    });
    try {
      final proof = runtime.codec.sealRecord(
        serverId: runtime.account.directory.session.profile.serverId,
        accountId: runtime.account.directory.accountId,
        deviceId: runtime.account.deviceId,
        batchId: batchId,
        scopeId: head.scopeId,
        id: address.wireId,
        type: 'financeAccountChoice',
        expectedRevision: 0,
        epoch: head.epoch,
        accessRevision: head.accessRevision,
        membershipHeadHash: head.headHash,
        domain: 'finance',
        contentContract: 3,
        operationId: operationId,
        previousRecordHash: '0' * 64,
        deleted: false,
        plaintext: bytes,
        metadata: {
          'migrationOrigin': migrationTag,
          'identity': address.identity,
          'references': <Object>[],
          'referenceVersions': <Object>[],
          'uniqueRefs': <String>[],
          'blobIds': <String>[],
        },
        contentKey: financeKey,
        signingKey: signingKey,
      );
      return (proof: proof, hash: await runtime.codec.digest(proof), raw: raw);
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  }

  static Future<String> verifyCompanion(
    CryptoBusinessSession runtime, {
    required Map<String, dynamic> raw,
    required Map<String, dynamic> record,
    required Map<String, dynamic> sourceBinding,
    required VerifiedScopeHead head,
  }) async {
    CryptoFinanceChoiceCapture.validate(raw);
    final c = raw['capture3']['context'] as Map;
    final tag = record['metadata']['migrationOrigin'] as Map;
    final target = c['target'] as Map;
    final binding = CryptoCaptureBinding.fromJson(
      Map<String, dynamic>.from(c['childBinding'] as Map),
    );
    if (record['type'] != 'financeAccountChoice' ||
        record['domain'] != 'finance' ||
        record['deleted'] != false ||
        record['expectedRevision'] != 0 ||
        record['previousRecordHash'] != '0' * 64 ||
        target['scopeId'] != record['scopeId'] ||
        target['membershipHeadHash'] != record['membershipHeadHash'] ||
        target['accountId'] != record['accountId'] ||
        target['migrationId'] != tag['migrationId'] ||
        target['captureId'] != tag['captureId'] ||
        target['sourceInventoryRoot'] != tag['sourceInventoryRoot'] ||
        binding.bindingId != tag['bindingId'] ||
        binding.bindingId != sourceBinding['bindingId'] ||
        binding.sourceCommitment != sourceBinding['sourceCommitment'] ||
        binding.scopeId != record['scopeId'] ||
        binding.domain != 'finance' ||
        record['metadata']['identity']['canonicalId'] !=
            await runtime.reservedRecordId(
              record['scopeId'],
              'financeAccountChoices',
            )) {
      throw const FormatException('crypto_account_choices_capture_companion');
    }
    return CryptoFinanceAccountChoices(
      runtime,
    ).verifyCapturedHandoff(raw, exactTargetHead: head);
  }
}
