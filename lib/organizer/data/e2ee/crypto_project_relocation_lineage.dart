import 'dart:convert';

import 'crypto_business_router.dart';
import 'crypto_json.dart';
import 'crypto_sync_repository.dart';

/// Logical revision is inherited only through the exact signed predecessor
/// chain. Cached SQL offsets are never sufficient to establish this lineage.
Future<Map<String, dynamic>?> verifiedProjectRelocationLineage(
  CryptoBusinessSession context,
  CryptoProjectionRecord target,
) async {
  if (target.relocationOrigin != null) return target.relocationOrigin;
  if (target.wire['revision'] == 1) return null;
  final r = target.record, root = target.historicalAnchorWire ?? target.wire;
  final rootProof = Map<String, dynamic>.from(
    root['authorization']['recordProof'] as Map,
  );
  final rootBody = Map<String, dynamic>.from(
    CryptoJson.decode(cryptoBase64(rootProof['commandBase64'])) as Map,
  );
  final evidence = {
    'scopeId': rootBody['scopeId'],
    'id': rootBody['id'],
    'revision': root['revision'],
    'recordProofHash': await context.codec.digest(rootProof),
  };
  final chain = await context.access.openHistoryChain(
    target.wire,
    carrierAnchorWire: target.historicalAnchorWire,
  );
  var budget = 32;
  while (chain.nextRevision > 0) {
    final revision = chain.nextRevision, hash = chain.nextHash;
    Map<String, dynamic> wire;
    if (revision == target.wire['revision'] &&
        hash ==
            await context.codec.digest(
              Map<String, dynamic>.from(
                target.wire['authorization']['recordProof'] as Map,
              ),
            )) {
      wire = target.wire;
    } else {
      final cached = await context.db.rows(
        'SELECT wire FROM crypto_business_history_proofs WHERE partition=? AND scope_id=? AND domain=? AND record_id=? AND revision=? AND proof_hash=?',
        [context.partition, r['scopeId'], r['domain'], r['id'], revision, hash],
      );
      if (cached.length > 1)
        throw const FormatException('crypto_project_relocation_lineage');
      if (cached.isNotEmpty) {
        wire = Map<String, dynamic>.from(
          jsonDecode(cached.single['wire'] as String) as Map,
        );
      } else {
        if (budget-- <= 0)
          throw const CryptoAuthorityPending(
            'crypto_project_relocation_lineage_pending',
          );
        final read = await context.access.readContext(
          r['scopeId'],
          r['domain'],
        );
        final page = await context.account.directory
            .call('crypto2.records.historyGet', {
              'scopeId': r['scopeId'],
              'domain': r['domain'],
              'accessRevision': read.accessRevision,
              'id': r['id'],
              'revision': revision,
              'recordProofHash': hash,
              'evidenceFor': evidence,
            });
        wire = Map<String, dynamic>.from(page['record'] as Map);
      }
    }
    final authority = await chain.authority(wire);
    await context.codec.verifyWire(
      serverId: context.account.directory.session.profile.serverId,
      wire: wire,
      trustedSigningKey: authority.signingKey,
      currentEpoch: authority.currentEpoch,
      closedRecordProofHash: authority.closedRecordProofHash,
    );
    if (!context.account.directory.isCurrent())
      throw const CryptoAuthorityPending('crypto_stale_identity');
    await context.db.execute(
      'INSERT OR IGNORE INTO crypto_business_history_proofs VALUES(?,?,?,?,?,?,?,?)',
      [
        context.partition,
        r['scopeId'],
        r['domain'],
        r['id'],
        revision,
        hash,
        jsonEncode(wire),
        authority.historyBasis ?? 'currentEpoch',
      ],
    );
    if (authority.relocationOrigin != null)
      return Map.unmodifiable(authority.relocationOrigin!);
  }
  return null;
}
