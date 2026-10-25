import 'dart:convert';

import '../collaboration_database.dart';
import 'crypto_record_address.dart';
import 'crypto_business_json.dart';
import 'crypto_record_policy.dart';
import 'crypto_sync_repository.dart';

/// A snapshot review never substitutes for policy admission. The ordinary
/// projector has already checked the accepted predecessor/baseline, immutable
/// creator, assignments, HMACs and whole-batch companion before writing this
/// exact proof to crypto_business_records. A raw signature/AEAD check alone
/// cannot establish those semantic facts.
abstract final class CryptoScopeReviewPolicy {
  static bool allowsContentViewer(Map<String, dynamic> record) {
    if (record['domain'] != 'content') return false;
    final metadata = record['metadata'];
    if (metadata is! Map) return false;
    final policy = metadata['recordPolicy'];
    if (record['contentContract'] == 7 &&
        CryptoRecordPolicy.businessTypes.contains(record['type']) &&
        policy is Map &&
        policy['version'] == 1) {
      return true;
    }
    final companion = metadata['recordPolicyCompanion'];
    return record['contentContract'] == 6 &&
        record['type'] == 'taskDerivationIntent' &&
        companion is Map &&
        companion['version'] == 1;
  }

  /// Rebuild only an unfinished local snapshot. A finalized review or any
  /// prepared rotation owns its original bytes and is never reset here.
  static Future<void> resetUnsignedPartialReview({
    required CollaborationDatabase database,
    required String partition,
    required String scopeId,
    required String reviewId,
  }) => database.transaction(() async {
    final retained = await database.rows(
      "SELECT 1 FROM crypto_membership_intents WHERE partition=? AND scope_id=? AND ((intent_id=? AND state IN ('scopeRotationReview','scopeRotationReviewComplete')) OR (state='scopeRotationDraft' AND json_extract(CAST(payload AS TEXT),'\$.reviewId')=?) OR (state='scopeSuccessorDraft' AND intent_id=?)) LIMIT 1",
      [partition, scopeId, reviewId, reviewId, '$reviewId:successor'],
    );
    if (retained.isNotEmpty) {
      throw const CryptoAuthorityPending('scope_review_confirmation_required');
    }
    await database.execute(
      'DELETE FROM crypto_scope_review_records WHERE partition=? AND scope_id=? AND review_id=?',
      [partition, scopeId, reviewId],
    );
  });

  static Future<void> requireVerifiedProjection({
    required CollaborationDatabase database,
    required String partition,
    required Map<String, dynamic> record,
    required String recordProofHash,
    required int revision,
  }) async {
    final metadata = record['metadata'] as Map;
    final policy = metadata['recordPolicy'];
    final companion = metadata['recordPolicyCompanion'];
    if (policy == null && companion == null) return;
    final policyContract = record['domain'] == 'content' ? 7 : 4;
    if (policy != null &&
            (record['contentContract'] != policyContract ||
                !CryptoRecordPolicy.businessTypes.contains(record['type'])) ||
        companion != null && !allowsContentViewer(record)) {
      throw const FormatException('scope_review_policy_contract');
    }
    final rows = await database.rows(
      'SELECT type,crypto_revision,record_proof_hash,deleted,raw_payload,projection FROM crypto_business_records WHERE partition=? AND scope_id=? AND domain=? AND id=?',
      [partition, record['scopeId'], record['domain'], record['id']],
    );
    Never pending() => throw const CryptoAuthorityPending(
      'scope_review_policy_projection_pending',
    );
    if (rows.length != 1) pending();
    final row = rows.single;
    if (row['type'] != record['type'] ||
        row['crypto_revision'] != revision ||
        row['record_proof_hash'] != recordProofHash ||
        (row['deleted'] == 1) != record['deleted']) {
      pending();
    }
    final canonical = jsonDecode(row['projection'] as String);
    if (canonical is! Map ||
        canonical['type'] != record['type'] ||
        canonical['deleted'] != record['deleted'] ||
        canonical['id'] !=
            cryptoRecordAddressFromMetadata(record).canonicalId ||
        (row['raw_payload'] == null) != (record['deleted'] == true)) {
      pending();
    }
    if (policy is Map) {
      CryptoRecordPolicy.validate(Map<String, dynamic>.from(policy));
      if (canonical['createdByAccountId'] != policy['createdByAccountId']) {
        pending();
      }
      if (row['raw_payload'] != null) {
        // Expanded authenticated plaintext retains the private per-record key;
        // transport manifests are never interpreted as editable values here.
        final actual = await CryptoRecordPolicy.commitments(
          serverId: record['serverId'],
          scopeId: record['scopeId'],
          domain: record['domain'],
          wireId: record['id'],
          type: record['type'],
          payload: Map<String, dynamic>.from(
            jsonDecode(row['raw_payload'] as String) as Map,
          ),
        );
        if (CryptoBusinessJson.canonical(actual) !=
            CryptoBusinessJson.canonical(policy['fieldCommitments'])) {
          throw const FormatException('scope_review_policy_payload');
        }
      }
    }
  }
}
