import 'dart:convert';

import '../collaboration_database.dart';
import 'crypto_record_address.dart';

/// Business rows use wire UUIDv8 addresses. Resolve their canonical identity
/// through the address installed with the verified projection, never by treating
/// the wire UUID or a cached scope root as a canonical project ID.
Future<List<Map<String, Object?>>> cryptoProjectRootCandidates({
  required CollaborationDatabase database,
  required String partition,
  required String serverId,
  required String scopeId,
}) async {
  final rows = await database.rows(
    '''SELECT b.id AS wire_id,b.deleted,b.legacy_revision,b.revision_namespace,
      b.projection,a.canonical_id,a.domain AS address_domain,
      a.source_kind,a.type AS address_type
      FROM crypto_business_records b LEFT JOIN crypto_business_addresses a
        ON a.partition=b.partition AND a.scope_id=b.scope_id AND a.wire_id=b.id
      WHERE b.partition=? AND b.scope_id=? AND b.domain='content' AND b.type='project' ''',
    [partition, scopeId],
  );
  return [
    for (final row in rows)
      {
        ...row,
        'id': _canonicalProjectId(row, serverId: serverId, scopeId: scopeId),
      },
  ];
}

String? _canonicalProjectId(
  Map<String, Object?> row, {
  required String serverId,
  required String scopeId,
}) {
  final canonical = row['canonical_id'];
  if (!isCryptoCanonicalUuid(canonical) ||
      row['address_domain'] != 'content' ||
      row['source_kind'] != 'records' ||
      row['address_type'] != 'project' ||
      CryptoRecordAddress.forType(
            serverId: serverId,
            scopeId: scopeId,
            type: 'project',
            canonicalId: canonical as String,
          ).wireId !=
          row['wire_id']) {
    return null;
  }
  final projection = jsonDecode(row['projection'] as String);
  return projection is Map &&
          projection['id'] == canonical &&
          projection['type'] == 'project'
      ? canonical
      : null;
}

/// Local verified projections only. Discovery/cache root IDs carry no authority.
String? cryptoProjectRootProjection({
  required String scopeId,
  required Map<String, dynamic> descriptor,
  required List<Map<String, Object?>> projects,
  required bool completeVerifiedInventory,
}) {
  if (descriptor['kind'] != 'project') return null;
  final rootPolicy =
      descriptor['accessPolicyVersion'] == 3 ||
      descriptor['parentScopeToken'] != null;
  if (!rootPolicy) return null;
  final active = projects.where((row) => row['deleted'] == 0).toList();
  if (active.length != 1 || !isCryptoCanonicalUuid(active.single['id'])) {
    return null;
  }
  final root = active.single;
  // A newly signed canonical root does not require a second network inventory.
  if (root['id'] == scopeId &&
      root['legacy_revision'] == 0 &&
      root['revision_namespace'] != 'legacy') {
    return scopeId;
  }
  // Converted/migrated project roots can retain another canonical UUID. A
  // partial local list cannot prove that it is the sole project in the scope.
  return completeVerifiedInventory && descriptor['accessPolicyVersion'] == 3
      ? root['id'] as String
      : null;
}
