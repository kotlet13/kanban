import '../collaboration_database.dart';
import 'crypto_record_address.dart';
import 'crypto_sync_repository.dart';

/// Derived addresses are installed only while projecting authenticated identity
/// metadata. A raw imported mapping is never an authority or an active grant.
class CryptoBusinessAddresses {
  const CryptoBusinessAddresses(this.db, this.partition, this.serverId);
  final CollaborationDatabase db;
  final String partition, serverId;

  Future<void> install(CryptoRecordAddress address) =>
      db.transaction(() => _install(address));

  Future<void> _install(CryptoRecordAddress address) async {
    if (address.serverId != serverId)
      throw const FormatException('crypto_record_identity');
    final rows = await db.rows(
      'SELECT * FROM crypto_business_addresses WHERE partition=? AND scope_id=? AND source_kind=? AND canonical_id=?',
      [partition, address.scopeId, address.sourceKind, address.canonicalId],
    );
    if (rows.isNotEmpty &&
        (rows.single['wire_id'] != address.wireId ||
            rows.single['domain'] != address.domain ||
            rows.single['type'] != address.type)) {
      throw const FormatException('crypto_record_identity_changed');
    }
    final wire = await db.rows(
      'SELECT * FROM crypto_business_addresses WHERE partition=? AND scope_id=? AND wire_id=?',
      [partition, address.scopeId, address.wireId],
    );
    if (wire.isNotEmpty &&
        (wire.single['source_kind'] != address.sourceKind ||
            wire.single['canonical_id'] != address.canonicalId ||
            wire.single['domain'] != address.domain ||
            wire.single['type'] != address.type)) {
      throw const FormatException('crypto_record_address_collision');
    }
    await db.execute(
      'INSERT OR IGNORE INTO crypto_business_addresses VALUES(?,?,?,?,?,?,?)',
      [
        partition,
        address.scopeId,
        address.domain,
        address.sourceKind,
        address.canonicalId,
        address.wireId,
        address.type,
      ],
    );
    final installed = await db.rows(
      'SELECT * FROM crypto_business_addresses WHERE partition=? AND scope_id=? AND source_kind=? AND canonical_id=?',
      [partition, address.scopeId, address.sourceKind, address.canonicalId],
    );
    if (installed.length != 1 ||
        installed.single['wire_id'] != address.wireId ||
        installed.single['type'] != address.type ||
        installed.single['domain'] != address.domain) {
      throw const FormatException('crypto_record_address_collision');
    }
  }

  Future<String?> existingWireId(
    String scope,
    String domain,
    String canonical, {
    String? type,
  }) async {
    if (type != null)
      return cryptoWireRecordId(
        serverId,
        scope,
        type,
        canonical,
        domain: domain,
      );
    final rows = await db.rows(
      'SELECT wire_id FROM crypto_business_addresses WHERE partition=? AND scope_id=? AND domain=? AND canonical_id=?',
      [partition, scope, domain, canonical],
    );
    if (rows.length > 1)
      throw const CryptoAuthorityPending('crypto_typed_address_required');
    return rows.firstOrNull?['wire_id'] as String?;
  }
}
