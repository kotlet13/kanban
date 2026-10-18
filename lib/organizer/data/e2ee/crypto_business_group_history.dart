import 'dart:convert';
import 'dart:typed_data';

import '../collaboration_transport.dart';
import 'crypto_business_router.dart';
import 'crypto_record_address.dart';
import 'crypto_json.dart';
import 'crypto_sync_repository.dart';

/// Reconstructs missing atomic siblings as evidence, never as current effects.
/// The hash-only history response is an untrusted candidate until its exact
/// proof is reached from an independently authenticated current same-record wire.
class CryptoBusinessGroupHistory {
  CryptoBusinessGroupHistory(this.context);
  final CryptoBusinessSession context;

  Future<List<CryptoProjectionRecord>> resolve(
    List<CryptoProjectionRecord> current,
    Set<String> missing,
    CryptoProjectionHistoryBudget budget,
  ) async {
    if (current.isEmpty || missing.length > 32) {
      throw const FormatException('crypto_projection_historical_size');
    }
    final scope = current.first.record['scopeId'] as String;
    final domain = current.first.record['domain'] as String;
    final batchKey = current.first.batchKey;
    final result = <CryptoProjectionRecord>[];
    try {
      for (final hash in missing.toList()..sort()) {
        final wire = await _candidate(scope, domain, hash, budget);
        final proof = _proof(wire);
        final body = _body(wire);
        context.codec.validateUntrustedRecord(body);
        if (body['scopeId'] != scope ||
            body['domain'] != domain ||
            body['batchId'] != current.first.record['batchId'] ||
            await context.codec.digest(proof) != hash ||
            await context.codec.digest(
                  Map<String, dynamic>.from(
                    (wire['authorization'] as Map)['batchCommitment'] as Map,
                  ),
                ) !=
                batchKey) {
          throw const FormatException('crypto_projection_historical_binding');
        }
        final roots = await context.database.rows(
          'SELECT wire FROM crypto_received WHERE partition=? AND scope_id=? AND domain=? AND record_id=? AND revision>? ORDER BY revision DESC LIMIT 1',
          [context.partition, scope, domain, body['id'], wire['revision']],
        );
        if (roots.length != 1) {
          throw const CryptoProjectionPending();
        }
        final anchorWire = Map<String, dynamic>.from(
          jsonDecode(roots.single['wire'] as String) as Map,
        );
        final anchor = _body(anchorWire);
        if (anchor['scopeId'] != scope ||
            anchor['domain'] != domain ||
            anchor['id'] != body['id'] ||
            anchor['type'] != body['type'] ||
            base64Encode(CryptoJson.encode(anchor['metadata']['identity'])) !=
                base64Encode(CryptoJson.encode(body['metadata']['identity']))) {
          throw const FormatException('crypto_projection_historical_identity');
        }
        // openHistoryChain verifies the entire root with independent current /
        // closure / own-observation authority. A signed predecessor hash alone
        // cannot grant a revoked author's missing historical authority.
        final chain = await context.access.openHistoryChain(anchorWire);
        final evidenceFor = <String, dynamic>{
          'scopeId': scope,
          'id': anchor['id'],
          'revision': anchorWire['revision'],
          'recordProofHash': await context.codec.digest(_proof(anchorWire)),
        };
        CryptoRecordAuthority? goalAuthority;
        while (chain.nextRevision >= (wire['revision'] as int)) {
          final revision = chain.nextRevision, expected = chain.nextHash;
          final step = revision == wire['revision']
              ? wire
              : await _candidate(
                  scope,
                  domain,
                  expected,
                  budget,
                  id: body['id'],
                  revision: revision,
                  evidenceFor: evidenceFor,
                );
          final stepBody = _body(step);
          if (stepBody['scopeId'] != scope ||
              stepBody['domain'] != domain ||
              stepBody['id'] != body['id'] ||
              stepBody['type'] != body['type'] ||
              step['revision'] != revision ||
              await context.codec.digest(_proof(step)) != expected) {
            throw const FormatException('crypto_projection_historical_fork');
          }
          final authority = await chain.authority(step);
          await _retain(step, expected, authority);
          if (revision == wire['revision']) {
            if (expected != hash) {
              throw const FormatException('crypto_projection_historical_fork');
            }
            goalAuthority = authority;
            break;
          }
        }
        if (goalAuthority == null) throw const CryptoProjectionPending();
        final verified = await context.codec.verifyWire(
          serverId: context.account.directory.session.profile.serverId,
          wire: wire,
          trustedSigningKey: goalAuthority.signingKey,
          currentEpoch: goalAuthority.currentEpoch,
          closedRecordProofHash: goalAuthority.closedRecordProofHash,
        );
        final lease = await context.access.recordKey(verified);
        late final Uint8List? plaintext;
        try {
          plaintext = context.codec.openVerified(verified, lease.key);
        } finally {
          lease.release();
        }
        result.add(
          CryptoProjectionRecord(
            wire,
            verified,
            plaintext,
            historyBasis: goalAuthority.currentEpoch
                ? 'currentEpoch'
                : goalAuthority.historyBasis ?? 'unconfirmed',
            batchKey: batchKey,
            migrationOrigin: goalAuthority.migrationOrigin,
            migrationWitness: goalAuthority.migrationWitness,
            historicalOnly: true,
            historicalAnchorWire: anchorWire,
          ),
        );
      }
      if (!context.account.directory.isCurrent()) {
        throw const CryptoAuthorityPending('crypto_stale_identity');
      }
      return result;
    } catch (_) {
      for (final value in result) {
        value.plaintext?.fillRange(0, value.plaintext!.length, 0);
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _candidate(
    String scope,
    String domain,
    String hash,
    CryptoProjectionHistoryBudget budget, {
    String? id,
    int? revision,
    Map<String, dynamic>? evidenceFor,
  }) async {
    final cached = await context.database.rows(
      'SELECT wire FROM crypto_business_history_proofs WHERE partition=? AND scope_id=? AND domain=? AND proof_hash=? LIMIT 2',
      [context.partition, scope, domain, hash],
    );
    if (cached.length > 1) {
      throw const FormatException('crypto_projection_historical_ambiguous');
    }
    if (cached.length == 1) {
      return Map<String, dynamic>.from(
        jsonDecode(cached.single['wire'] as String) as Map,
      );
    }
    if (!budget.take()) throw const CryptoProjectionPending();
    final read = await context.access.readContext(scope, domain);
    late final Map<String, dynamic> response;
    try {
      response = await context.account.directory
          .call('crypto2.records.historyGet', {
            'scopeId': scope,
            'domain': domain,
            'accessRevision': read.accessRevision,
            'recordProofHash': hash,
            if (id != null) 'id': id,
            if (revision != null) 'revision': revision,
            if (evidenceFor != null) 'evidenceFor': evidenceFor,
          });
    } on CollaborationApiException catch (error) {
      final notice = error.details['unavailable'];
      if (error.code != 'crypto_content_restricted' ||
          evidenceFor != null ||
          notice is! Map ||
          notice.length != 8 ||
          notice['scopeId'] != scope ||
          notice['domain'] != domain ||
          notice['recordProofHash'] != hash ||
          !isCryptoWireRecordId(notice['id']) ||
          notice['revision'] is! int ||
          (notice['revision'] as int) < 1 ||
          notice['reason'] != 'moderation') {
        throw const CryptoProjectionPending();
      }
      // The notice discovers an address, never authority or display permission.
      final roots = await context.database.rows(
        'SELECT wire FROM crypto_received WHERE partition=? AND scope_id=? AND domain=? AND record_id=? AND revision>? ORDER BY revision DESC LIMIT 1',
        [context.partition, scope, domain, notice['id'], notice['revision']],
      );
      if (roots.length != 1) throw const CryptoProjectionPending();
      final root = Map<String, dynamic>.from(
        jsonDecode(roots.single['wire'] as String) as Map,
      );
      await context.access.openHistoryChain(root);
      return _candidate(
        scope,
        domain,
        hash,
        budget,
        id: notice['id'],
        revision: notice['revision'],
        evidenceFor: {
          'scopeId': scope,
          'id': root['id'],
          'revision': root['revision'],
          'recordProofHash': await context.codec.digest(_proof(root)),
        },
      );
    }
    if (response['record'] is! Map) throw const CryptoProjectionPending();
    return Map<String, dynamic>.from(response['record'] as Map);
  }

  Future<void> _retain(
    Map<String, dynamic> wire,
    String hash,
    CryptoRecordAuthority authority,
  ) async {
    if (!context.account.directory.isCurrent()) {
      throw const CryptoAuthorityPending('crypto_stale_identity');
    }
    final body = _body(wire);
    await context.database.execute(
      'INSERT OR IGNORE INTO crypto_business_history_proofs VALUES(?,?,?,?,?,?,?,?)',
      [
        context.partition,
        body['scopeId'],
        body['domain'],
        body['id'],
        wire['revision'],
        hash,
        jsonEncode(wire),
        authority.currentEpoch
            ? 'currentEpoch'
            : authority.historyBasis ?? 'unconfirmed',
      ],
    );
  }

  Map<String, dynamic> _proof(Map<String, dynamic> wire) =>
      Map<String, dynamic>.from(
        (wire['authorization'] as Map)['recordProof'] as Map,
      );
  Map<String, dynamic> _body(Map<String, dynamic> wire) =>
      Map<String, dynamic>.from(
        CryptoJson.decode(cryptoBase64(_proof(wire)['commandBase64'])) as Map,
      );
}
