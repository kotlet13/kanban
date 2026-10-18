import 'dart:convert';

import '../collaboration_database.dart';
import 'crypto_json.dart';
import 'crypto_record_proof_codec.dart';
import 'crypto_sync_repository.dart';
import 'session_crypto_access.dart';

/// Share one budget across every original leg in one compound ACK pass.
class CryptoBusinessAckHistoryBudget {
  int remaining = 32;
  bool take() => remaining-- > 0;
}

/// Recognizes the original immutable intent only as an exact authenticated
/// ancestor of today's projection. Receipt status and imported verdicts cannot
/// establish this relation, and no old payload replaces the current projection.
Future<void> requireAuthenticatedBusinessAckAncestor({
  required SessionCryptoAccess access,
  required CollaborationDatabase database,
  required Map<String, Object?> currentRecord,
  required Map<String, dynamic> stagedProof,
  CryptoBusinessAckHistoryBudget? budget,
}) async {
  final codec = CryptoRecordProofCodec(access.account.directory.reducer.crypto);
  final staged = Map<String, dynamic>.from(
    CryptoJson.decode(cryptoBase64(stagedProof['commandBase64'])) as Map,
  );
  codec.validateUntrustedRecord(staged);
  final revision = (staged['expectedRevision'] as int) + 1;
  final digest = await codec.digest(stagedProof);
  final scope = staged['scopeId'] as String,
      domain = staged['domain'] as String,
      id = staged['id'] as String;
  if (currentRecord['scope_id'] != scope ||
      currentRecord['domain'] != domain ||
      currentRecord['id'] != id ||
      currentRecord['type'] != staged['type'] ||
      currentRecord['crypto_revision'] is! int ||
      (currentRecord['crypto_revision'] as int) <= revision) {
    throw const CryptoAuthorityPending(
      'crypto_business_ack_projection_pending',
    );
  }
  final partition = access.account.store.partition;
  final roots = await database.rows(
    'SELECT wire FROM crypto_received WHERE partition=? AND scope_id=? AND domain=? AND record_id=? AND revision=?',
    [partition, scope, domain, id, currentRecord['crypto_revision']],
  );
  if (roots.length != 1) {
    throw const CryptoAuthorityPending('crypto_business_ack_history_pending');
  }
  final root = Map<String, dynamic>.from(
    jsonDecode(roots.single['wire'] as String) as Map,
  );
  final rootProof = Map<String, dynamic>.from(
    (root['authorization'] as Map)['recordProof'] as Map,
  );
  if (await codec.digest(rootProof) != currentRecord['record_proof_hash']) {
    throw const FormatException('crypto_business_ack_history_substitution');
  }
  final rootBody = Map<String, dynamic>.from(
    CryptoJson.decode(cryptoBase64(rootProof['commandBase64'])) as Map,
  );
  if (rootBody['type'] != staged['type'] ||
      base64Encode(CryptoJson.encode(rootBody['metadata']['identity'])) !=
          base64Encode(CryptoJson.encode(staged['metadata']['identity']))) {
    throw const FormatException('crypto_business_ack_history_identity');
  }
  final chain = await access.openHistoryChain(root);
  await database.execute(
    '''CREATE TABLE IF NOT EXISTS crypto_business_ack_history (
    partition TEXT NOT NULL,scope_id TEXT NOT NULL,domain TEXT NOT NULL,record_id TEXT NOT NULL,
    revision INTEGER NOT NULL,proof_hash TEXT NOT NULL,wire TEXT NOT NULL,
    PRIMARY KEY(partition,scope_id,domain,record_id,revision,proof_hash))''',
  );
  budget ??= CryptoBusinessAckHistoryBudget();
  while (chain.nextRevision >= revision) {
    final expectedRevision = chain.nextRevision, expectedHash = chain.nextHash;
    var rows = await database.rows(
      'SELECT wire FROM crypto_received WHERE partition=? AND scope_id=? AND domain=? AND record_id=? AND revision=?',
      [partition, scope, domain, id, expectedRevision],
    );
    if (rows.isEmpty) {
      rows = await database.rows(
        'SELECT wire FROM crypto_business_ack_history WHERE partition=? AND scope_id=? AND domain=? AND record_id=? AND revision=? AND proof_hash=?',
        [partition, scope, domain, id, expectedRevision, expectedHash],
      );
    }
    if (rows.isEmpty) {
      final available = await database.rows(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='crypto_business_history_proofs'",
      );
      if (available.isNotEmpty) {
        rows = await database.rows(
          'SELECT wire FROM crypto_business_history_proofs WHERE partition=? AND scope_id=? AND domain=? AND record_id=? AND revision=? AND proof_hash=?',
          [partition, scope, domain, id, expectedRevision, expectedHash],
        );
      }
    }
    Map<String, dynamic> wire;
    var fetched = false;
    if (rows.length == 1) {
      wire = Map<String, dynamic>.from(
        jsonDecode(rows.single['wire'] as String) as Map,
      );
    } else {
      if (rows.isNotEmpty) {
        throw const FormatException('crypto_business_ack_history_equivocation');
      }
      if (!budget.take()) {
        throw const CryptoAuthorityPending(
          'crypto_business_ack_history_pending',
        );
      }
      final head = await access.currentHead(scope, online: true);
      final response = await access.account.directory.call(
        'crypto2.records.historyGet',
        {
          'scopeId': scope,
          'domain': domain,
          'accessRevision': head.accessRevision,
          'id': id,
          'revision': expectedRevision,
          'recordProofHash': expectedHash,
          'evidenceFor': {
            'scopeId': scope,
            'id': id,
            'revision': currentRecord['crypto_revision'],
            'recordProofHash': currentRecord['record_proof_hash'],
          },
        },
      );
      if (response['record'] is! Map) {
        throw const CryptoAuthorityPending(
          'crypto_business_ack_history_pending',
        );
      }
      wire = Map<String, dynamic>.from(response['record'] as Map);
      fetched = true;
    }
    final proof = Map<String, dynamic>.from(
      (wire['authorization'] as Map)['recordProof'] as Map,
    );
    final hash = await codec.digest(proof);
    await chain.authority(wire);
    if (fetched) {
      if (!access.account.directory.isCurrent()) {
        throw const CryptoAuthorityPending('crypto_identity_changed');
      }
      await database.execute(
        'INSERT INTO crypto_business_ack_history VALUES(?,?,?,?,?,?,?) ON CONFLICT DO NOTHING',
        [
          partition,
          scope,
          domain,
          id,
          expectedRevision,
          hash,
          jsonEncode(wire),
        ],
      );
    }
    if (expectedRevision == revision) {
      if (hash != digest ||
          base64Encode(CryptoJson.encode(proof)) !=
              base64Encode(CryptoJson.encode(stagedProof))) {
        throw const FormatException('crypto_business_ack_history_intent');
      }
      return;
    }
  }
  throw const CryptoAuthorityPending('crypto_business_ack_history_pending');
}
