part of 'crypto_business_router.dart';

extension CryptoAcceptedScope on CryptoBusinessSession {
  Future<CryptoAcceptedScopeRead> acceptedScope(
    String scopeId,
    int cursor,
  ) async {
    // Invitation activation has already installed its exact signed anchor and
    // keys. This still performs the normal online membership/lifecycle/content
    // verification, without discovering or downloading the rest of the account.
    await access.currentHead(scopeId, online: true);
    await pullVerified(scopeId, 'content');
    return access.withVerifiedOperation(() async {
      await access.currentHead(scopeId, online: true);
      Future<String> state() async => CryptoBusinessJson.canonical(
        await db.rows(
          'SELECT * FROM crypto_scope_state WHERE partition=? AND scope_id=? AND domain=?',
          [p, scopeId, 'content'],
        ),
      );
      final materialized = await state();
      final descriptors = <String, Map<String, dynamic>>{};
      final projected = await _projectScopeForRead({
        'id': scopeId,
      }, descriptors);
      final value = projected.value;
      if (projected.pending ||
          value == null ||
          value['metadataRevision'] == 0) {
        throw const CryptoAuthorityPending('crypto_reconciliation_required');
      }
      final candidates = [
        for (final row in await db.rows(
          'SELECT data FROM scopes WHERE partition=?',
          [p],
        ))
          Map<String, dynamic>.from(jsonDecode(row['data'] as String) as Map),
        {'id': scopeId},
      ];
      await _finishScopeForRead(
        value,
        candidates,
        descriptors,
        forcePolicyCheck: true,
      );
      final head = await access.currentHead(scopeId);
      final read = await access.readContext(scopeId, 'content');
      if (read.headHash != head.headHash ||
          !await hasReusableCheckpoint(scopeId, 'content', read) ||
          !await _observedComplete(scopeId, 'content')) {
        throw const CryptoAuthorityPending('crypto_reconciliation_required');
      }
      // Read the same verified stream as ordinary sync. Document projections
      // are already installed by pullVerified; their sequence still advances.
      final records = <Map<String, dynamic>>[];
      var next = cursor;
      while (true) {
        final rows = await db.rows(
          'SELECT b.type,b.projection,r.sequence FROM crypto_business_records b JOIN crypto_received r ON r.partition=b.partition AND r.scope_id=b.scope_id AND r.domain=b.domain AND r.record_id=b.id AND r.revision=b.crypto_revision WHERE b.partition=? AND b.scope_id=? AND b.domain=? AND r.sequence>? ORDER BY r.sequence LIMIT 100',
          [p, scopeId, 'content', next],
        );
        for (final row in rows) {
          final projection = jsonDecode(row['projection'] as String);
          if (projection is! Map<String, dynamic> ||
              projection['type'] != row['type']) {
            throw const FormatException('crypto_business_projection_type');
          }
          if (!const {
            'scopeMetadata',
            'taskDerivationIntent',
            'taskDerivationResolution',
            'financeAccountChoice',
            'table',
            'attachment',
          }.contains(row['type'])) {
            records.add(projection);
          }
        }
        if (rows.isNotEmpty) next = rows.last['sequence'] as int;
        if (rows.length < 100) break;
      }
      final lease = await access.verifiedReadLease();
      if (materialized != await state() ||
          lease == null ||
          !await access.isVerifiedReadLeaseCurrent(lease)) {
        throw const CryptoAuthorityPending('crypto_reconciliation_required');
      }
      return CryptoAcceptedScopeRead(
        scope: value,
        records: records,
        cursor: next,
        isCurrent: () async =>
            await access.isVerifiedReadLeaseCurrent(lease) &&
            materialized == await state() &&
            await access.isVerifiedReadLeaseCurrent(lease),
      );
    }, freshBoundary: true);
  }
}
