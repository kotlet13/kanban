import 'dart:convert';

import 'crypto_business_router.dart';
import 'crypto_finance_topology.dart';
import 'crypto_record_address.dart';
import 'crypto_sync_repository.dart';

/// Preparatory payload only. The caller must include its signed successor in
/// the existing structural publication's atomic final set; this never writes.
class PreparedCryptoFinanceTopologySuccessor {
  PreparedCryptoFinanceTopologySuccessor._(this.previous, this.raw);
  final Map<String, Object?> previous;
  final Map<String, dynamic> raw;
}

abstract final class CryptoFinanceTopologySuccessor {
  static Future<PreparedCryptoFinanceTopologySuccessor> prepare({
    required CryptoBusinessSession runtime,
    required String parentScopeId,
    required String childScopeId,
    required bool remove,
  }) async {
    if (!isCryptoCanonicalUuid(parentScopeId) ||
        !isCryptoCanonicalUuid(childScopeId) ||
        parentScopeId == childScopeId) {
      throw const FormatException('crypto_finance_topology_context');
    }
    final head = await runtime.access.currentHead(parentScopeId, online: true);
    if (head.member(runtime.account.directory.accountId)['manageKeys'] !=
        true) {
      throw const CryptoAuthorityPending(
        'crypto_finance_topology_approval_pending',
      );
    }
    await runtime.pullVerified(parentScopeId, 'content');
    final id = await runtime.reservedRecordId(parentScopeId, 'scopeMetadata');
    final address = runtime.address(
      parentScopeId,
      'content',
      'scopeMetadata',
      id,
    );
    final previous = await runtime.wireRecord(
      parentScopeId,
      'content',
      address.wireId,
    );
    if (previous == null ||
        previous['deleted'] == 1 ||
        previous['raw_payload'] is! String) {
      throw const CryptoAuthorityPending('crypto_finance_topology_pending');
    }
    final raw = Map<String, dynamic>.from(
      jsonDecode(previous['raw_payload'] as String),
    );
    if (!const ['household', 'organization'].contains(raw['kind']) ||
        raw['financeTopology'] is! Map) {
      throw const CryptoAuthorityPending('crypto_finance_topology_pending');
    }
    final old = Map<String, dynamic>.from(raw['financeTopology']);
    final server = runtime.account.directory.session.profile.serverId;
    await CryptoFinanceTopology.validate(
      old,
      serverId: server,
      scopeId: parentScopeId,
    );
    final token = await CryptoFinanceTopology.childToken(
      server,
      parentScopeId,
      childScopeId,
    );
    final tokens = (old['childTokens'] as List).cast<String>().toSet();
    if (remove ? !tokens.remove(token) : !tokens.add(token)) {
      throw const CryptoAuthorityPending('crypto_finance_topology_changed');
    }
    final next = await CryptoFinanceTopology.create(
      serverId: server,
      scopeId: parentScopeId,
      childTokens: tokens.toList(),
      previous: old,
    );
    if ((await runtime.access.currentHead(
              parentScopeId,
              online: true,
            )).headHash !=
            head.headHash ||
        !runtime.account.directory.isCurrent()) {
      throw const CryptoAuthorityPending('crypto_stale_identity');
    }
    return PreparedCryptoFinanceTopologySuccessor._(previous, {
      ...raw,
      'financeTopology': next,
    });
  }
}
