import 'dart:convert';
import 'package:cryptography/cryptography.dart' show Sha256;

import 'crypto_business_router.dart';
import '../collaboration_transport.dart' show CollaborationApiException;
import 'crypto_json.dart';
import 'crypto_sync_repository.dart';

/// Attests only the exact authenticated, projected record set this device has
/// observed. This is not evidence that the server disclosed unseen history.
class CryptoDomainCheckpointPublisher {
  CryptoDomainCheckpointPublisher(this.context);
  final CryptoBusinessSession context;

  Future<void> publish(String scope, String domain) async {
    final read = await context.access.readContext(scope, domain);
    if (await context.hasReusableCheckpoint(scope, domain, read)) return;
    final snapshot = context.codec.crypto.randomId();
    final db = context.database, partition = context.partition;
    final initialState = (await db.rows(
      'SELECT * FROM crypto_scope_state WHERE partition=? AND scope_id=? AND domain=?',
      [partition, scope, domain],
    )).firstOrNull;
    if (initialState == null) return;
    try {
      final sink = Sha256().newHashSink();
      String? after;
      int? sequence;
      var count = 0;
      var reviewed = false;
      while (true) {
        final page = await context.account.directory
            .call('crypto2.domain.inventory', {
              'scopeId': scope,
              'domain': domain,
              'accessRevision': read.accessRevision,
              'limit': 50,
              if (after != null) 'afterId': after,
            });
        if (page['scopeId'] != scope ||
            page['domain'] != domain ||
            page['epoch'] != read.epoch ||
            page['membershipHeadHash'] != read.headHash ||
            page['scopeSequence'] is! int ||
            page['scopeSequence'] < 0 ||
            page['descriptors'] is! List ||
            (page['descriptors'] as List).length > 50 ||
            page['hasMore'] is! bool) {
          throw const FormatException('crypto_inventory_page');
        }
        sequence ??= page['scopeSequence'] as int;
        if (sequence != page['scopeSequence']) return;
        for (final raw in page['descriptors'] as List) {
          if (raw is! Map) {
            throw const FormatException('crypto_inventory_descriptor');
          }
          final descriptor = Map<String, dynamic>.from(raw);
          final id = descriptor['id'];
          if (descriptor.length != 5 ||
              id is! String ||
              (after != null && id.compareTo(after) <= 0) ||
              descriptor['revision'] is! int ||
              descriptor['revision'] < 1 ||
              descriptor['sequence'] is! int ||
              descriptor['sequence'] < 1 ||
              descriptor['sequence'] > sequence ||
              descriptor['recordEpoch'] is! int ||
              descriptor['recordEpoch'] < 1 ||
              descriptor['recordEpoch'] > read.epoch ||
              descriptor['recordProofHash'] is! String ||
              !RegExp(
                r'^[a-f0-9]{64}$',
              ).hasMatch(descriptor['recordProofHash'])) {
            throw const FormatException('crypto_inventory_descriptor');
          }
          final projected = await context.wireRecord(scope, domain, id);
          if (projected == null ||
              projected['crypto_revision'] != descriptor['revision'] ||
              projected['record_proof_hash'] != descriptor['recordProofHash']) {
            return;
          }
          if (!const [
            'currentEpoch',
            'verifiedCheckpoint',
            'reviewedRecoveryBaseline',
            'migrationCapturedSource',
            'inlineProjectDeletion',
            'managerAttestedProjectRelocation',
          ].contains(projected['history_basis'])) {
            return;
          }
          reviewed |= projected['history_basis'] == 'reviewedRecoveryBaseline';
          await db.execute(
            'INSERT INTO crypto_domain_inventory_rows VALUES(?,?,?,?,?,?,?)',
            [
              partition,
              snapshot,
              id,
              descriptor['revision'],
              descriptor['recordProofHash'],
              descriptor['sequence'],
              descriptor['recordEpoch'],
            ],
          );
          sink.add([...CryptoJson.encode(descriptor), 10]);
          count++;
          after = id;
        }
        if (page['hasMore'] != true) break;
        if ((page['descriptors'] as List).isEmpty ||
            page['nextAfterId'] != after) {
          throw const FormatException('crypto_inventory_cursor');
        }
      }
      sink.close();
      final hash = (await sink.hash()).bytes
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
      // A complete observed snapshot must cover every known authenticated floor,
      // including bad-AEAD or semantically pending records; those cannot be signed
      // away by an inventory omitting or replacing their proof.
      final uncovered = await db.rows(
        '''SELECT 1 FROM crypto_received r
        WHERE r.partition=? AND r.scope_id=? AND r.domain=? AND r.batch_key IS NOT NULL
          AND r.revision=(SELECT MAX(x.revision) FROM crypto_received x
            WHERE x.partition=r.partition AND x.scope_id=r.scope_id AND x.domain=r.domain
              AND x.record_id=r.record_id AND x.batch_key IS NOT NULL)
          AND (r.verdict NOT IN ('verified','superseded') OR NOT EXISTS(
            SELECT 1 FROM crypto_domain_inventory_rows i WHERE i.partition=r.partition
              AND i.snapshot_id=? AND i.record_id=r.record_id AND i.revision=r.revision)) LIMIT 1''',
        [partition, scope, domain, snapshot],
      );
      if (uncovered.isNotEmpty) return;
      if ((await db.rows(
        '''SELECT 1 FROM crypto_restore_record_anchors a
        WHERE a.partition=? AND a.scope_id=? AND a.domain=? AND NOT EXISTS(
          SELECT 1 FROM crypto_domain_inventory_rows i WHERE i.partition=a.partition
            AND i.snapshot_id=? AND i.record_id=a.record_id AND i.revision=a.revision
            AND i.proof_hash=a.proof_hash) LIMIT 1''',
        [partition, scope, domain, snapshot],
      )).isNotEmpty) {
        return;
      }
      final omitted = await db.rows(
        '''SELECT 1 FROM crypto_business_records b
        WHERE b.partition=? AND b.scope_id=? AND b.domain=? AND NOT EXISTS(
          SELECT 1 FROM crypto_domain_inventory_rows i WHERE i.partition=b.partition
          AND i.snapshot_id=? AND i.record_id=b.id AND i.revision=b.crypto_revision
          AND i.proof_hash=b.record_proof_hash) LIMIT 1''',
        [partition, scope, domain, snapshot],
      );
      if (omitted.isNotEmpty) return;
      final directory = await context.account.directory
          .cachedVerifiedDirectory();
      final payload = <String, dynamic>{
        'scopeId': scope,
        'domain': domain,
        'epoch': read.epoch,
        'membershipHeadHash': read.headHash,
        'accessRevision': read.accessRevision,
        'authorDirectoryHeadHash': directory.headHash,
        'expectedSequence': sequence,
        'recordCount': count,
        'manifestHash': hash,
        'historyBasis': reviewed
            ? 'reviewedRecoveryBaseline'
            : 'verifiedCheckpoint',
      };
      final key = await context.codec.digest(payload);
      final request = await context.queue.enqueueCommand(
        actionKey: 'checkpoint:$key',
        operation: 'crypto2.domain.checkpoint',
        payload: payload,
      );
      await context.queue.resumeUnresolved(requestIds: {request});
      try {
        await context.queue.commandResult(request);
      } on CryptoAuthorityPending {
        return;
      } on CollaborationApiException catch (error) {
        if (!const {
          'crypto_checkpoint_changed',
          'crypto_checkpoint_immutable',
        }.contains(error.code)) {
          rethrow;
        }
        return;
      }
      // Command delivery uses the durable queue's transport directly. Its fresh
      // pre-delivery review does not end the caller's outer inventory memo.
      // This applied checkpoint changes that inventory, so retire the outer
      // lease before reading and verifying the newly published attestation.
      context.access.invalidateAuthorityOperation();
      final verified = await context.access.withVerifiedOperation(
        () => context.checkpoints.reconcile(scope, domain, read),
        freshBoundary: true,
      );
      if (verified == null) return;
      await db.transaction(() async {
        final state = (await db.rows(
          'SELECT * FROM crypto_scope_state WHERE partition=? AND scope_id=? AND domain=?',
          [partition, scope, domain],
        )).firstOrNull;
        if (state == null ||
            state['floor'] != read.epoch ||
            state['access_revision'] != read.accessRevision ||
            state['scope_sequence'] != sequence ||
            state['scan_generation'] != initialState['scan_generation'] ||
            (state['projection_cursor'] as int) < sequence! ||
            !context.account.directory.isCurrent()) {
          return;
        }
        final checkpoint = await db.rows(
          'SELECT 1 FROM crypto_domain_checkpoints WHERE partition=? AND scope_id=? AND domain=? AND head_hash=? AND sequence=? AND manifest_hash=? AND snapshot_id=? AND record_count=?',
          [
            partition,
            scope,
            domain,
            read.headHash,
            sequence,
            hash,
            verified,
            count,
          ],
        );
        if (checkpoint.length != 1) return;
        final stale = await db.rows(
          """SELECT 1 FROM crypto_business_records b
          WHERE b.partition=? AND b.scope_id=? AND b.domain=? AND NOT EXISTS(
            SELECT 1 FROM crypto_domain_inventory_rows i WHERE i.partition=b.partition
              AND i.snapshot_id=? AND i.record_id=b.id AND i.revision=b.crypto_revision
              AND i.proof_hash=b.record_proof_hash) LIMIT 1""",
          [partition, scope, domain, verified],
        );
        if (stale.isNotEmpty) return;
        if ((await db.rows(
          '''SELECT 1 FROM crypto_restore_record_anchors a
          WHERE a.partition=? AND a.scope_id=? AND a.domain=? AND NOT EXISTS(
            SELECT 1 FROM crypto_domain_inventory_rows i WHERE i.partition=a.partition
              AND i.snapshot_id=? AND i.record_id=a.record_id AND i.revision=a.revision
              AND i.proof_hash=a.proof_hash) LIMIT 1''',
          [partition, scope, domain, verified],
        )).isNotEmpty) {
          return;
        }
        String? cursor;
        while (true) {
          final known = await db.rows(
            """SELECT r.* FROM crypto_received r
            WHERE r.partition=? AND r.scope_id=? AND r.domain=? AND r.batch_key IS NOT NULL
              AND r.record_id>? AND r.revision=(SELECT MAX(x.revision) FROM crypto_received x
                WHERE x.partition=r.partition AND x.scope_id=r.scope_id AND x.domain=r.domain
                  AND x.record_id=r.record_id AND x.batch_key IS NOT NULL)
            ORDER BY r.record_id LIMIT 50""",
            [partition, scope, domain, cursor ?? ''],
          );
          if (known.isEmpty) break;
          for (final r in known) {
            if (r['verdict'] != 'verified' && r['verdict'] != 'superseded') {
              return;
            }
            final wire = jsonDecode(r['wire'] as String) as Map;
            final proofHash = await context.codec.digest(
              Map<String, dynamic>.from(
                (wire['authorization'] as Map)['recordProof'] as Map,
              ),
            );
            final matched = await db.rows(
              'SELECT 1 FROM crypto_domain_inventory_rows WHERE partition=? AND snapshot_id=? AND record_id=? AND revision=? AND proof_hash=?',
              [partition, verified, r['record_id'], r['revision'], proofHash],
            );
            if (matched.length != 1) return;
            cursor = r['record_id'] as String;
          }
        }
        final projectedCount = (await db.rows(
          'SELECT COUNT(*) AS n FROM crypto_business_records WHERE partition=? AND scope_id=? AND domain=?',
          [partition, scope, domain],
        )).single['n'];
        if (projectedCount != count) return;
        await db.execute(
          'UPDATE crypto_scope_state SET complete=1 WHERE partition=? AND scope_id=? AND domain=?',
          [partition, scope, domain],
        );
      });
    } finally {
      await db.execute(
        'DELETE FROM crypto_domain_inventory_rows WHERE partition=? AND snapshot_id=?',
        [partition, snapshot],
      );
    }
  }
}
