import 'dart:convert';

import 'package:cryptography/cryptography.dart' show Sha256;

import '../collaboration_database.dart';
import 'crypto_record_address.dart' show isCryptoWireRecordId;
import 'crypto_json.dart';
import 'crypto_record_proof_codec.dart';
import 'crypto_sync_repository.dart';

/// Authenticates a bounded, paged signer-observed inventory. Unsigned SQL
/// pagination is only a candidate; it never establishes remote latestness.
class CryptoDomainCheckpointReader {
  CryptoDomainCheckpointReader({
    required this.database,
    required this.partition,
    required this.codec,
    required this.call,
    required this.verify,
  });
  final CollaborationDatabase database;
  final String partition;
  final CryptoRecordProofCodec codec;
  final Future<Map<String, dynamic>> Function(String, Map<String, dynamic>)
  call;

  /// Production resolves the exact directory, device and signed scope head.
  final Future<String> Function(Map<String, dynamic>) verify;

  /// Rechecks the complete bounded descriptor stream, not an imported SQL
  /// completeness flag. This is only an exact own-observed historical anchor.
  Future<bool> retainsObservedInventory(
    String scope,
    String domain,
    CryptoReadContext context,
    Map<String, dynamic> anchor,
  ) async {
    final rows = await database.rows(
      'SELECT snapshot_id,authorization FROM crypto_domain_checkpoints WHERE partition=? AND scope_id=? AND domain=? AND head_hash=? AND sequence=? AND manifest_hash=? AND record_count=?',
      [
        partition,
        scope,
        domain,
        context.headHash,
        anchor['sequence'],
        anchor['manifestHash'],
        anchor['recordCount'],
      ],
    );
    if (rows.length != 1) return false;
    final row = rows.single;
    try {
      final proof = Map<String, dynamic>.from(
        jsonDecode(row['authorization'] as String) as Map,
      );
      if (!(anchor['proofHashes'] as List).contains(
        await codec.digest(proof),
      )) {
        return false;
      }
      final command =
          CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map;
      final payload = command['payload'] as Map;
      if (payload['scopeId'] != scope ||
          payload['domain'] != domain ||
          payload['membershipHeadHash'] != context.headHash ||
          payload['epoch'] != context.epoch ||
          payload['accessRevision'] != context.accessRevision ||
          payload['expectedSequence'] != anchor['sequence'] ||
          payload['manifestHash'] != anchor['manifestHash'] ||
          payload['recordCount'] != anchor['recordCount']) {
        return false;
      }
      if (![
        'verifiedCheckpoint',
        'reviewedRecoveryBaseline',
      ].contains(await verify(proof))) {
        return false;
      }
      final sink = Sha256().newHashSink();
      String? after;
      var count = 0;
      while (true) {
        final page = await database.rows(
          'SELECT * FROM crypto_domain_inventory_rows WHERE partition=? AND snapshot_id=? ${after == null ? '' : 'AND record_id>?'} ORDER BY record_id LIMIT 50',
          [partition, row['snapshot_id'], if (after != null) after],
        );
        for (final descriptor in page) {
          sink.add([
            ...CryptoJson.encode({
              'id': descriptor['record_id'],
              'revision': descriptor['revision'],
              'sequence': descriptor['sequence'],
              'recordEpoch': descriptor['record_epoch'],
              'recordProofHash': descriptor['proof_hash'],
            }),
            10,
          ]);
          count++;
          after = descriptor['record_id'] as String;
        }
        if (page.length < 50) break;
      }
      sink.close();
      final hash = (await sink.hash()).bytes
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
      return count == anchor['recordCount'] && hash == anchor['manifestHash'];
    } on FormatException {
      return false;
    } on TypeError {
      return false;
    } on CryptoAuthorityPending {
      return false;
    }
  }

  Future<String?> reconcile(
    String scope,
    String domain,
    CryptoReadContext context, {
    List<Map<String, dynamic>>? observedAnchors,
  }) async {
    final snapshot = codec.crypto.randomId();
    try {
      final sink = Sha256().newHashSink();
      var count = 0;
      String? after;
      Map<String, dynamic>? checkpoint;
      Map<String, dynamic>? first;
      final selected = observedAnchors?.firstOrNull;
      if (observedAnchors != null &&
          (selected == null || (selected['proofHashes'] as List).isEmpty)) {
        throw const CryptoAuthorityPending('crypto_observed_inventory_pending');
      }
      while (true) {
        final page = await call('crypto2.domain.inventory', {
          'scopeId': scope,
          'domain': domain,
          'accessRevision': context.accessRevision,
          'limit': 50,
          if (selected != null)
            'checkpoint': {
              'membershipHeadHash': selected['membershipHeadHash'],
              'sequence': selected['sequence'],
              'manifestHash': selected['manifestHash'],
              'recordCount': selected['recordCount'],
              'proofHash': (selected['proofHashes'] as List).first,
            },
          if (after != null) 'afterId': after,
        });
        if (page['scopeId'] != scope ||
            page['domain'] != domain ||
            page['epoch'] != context.epoch ||
            page['membershipHeadHash'] != context.headHash ||
            page['scopeSequence'] is! int ||
            page['scopeSequence'] < 0 ||
            page['hasMore'] is! bool ||
            page['descriptors'] is! List ||
            (page['descriptors'] as List).length > 50) {
          throw const FormatException('crypto_inventory_page');
        }
        first ??= page;
        if (page['scopeSequence'] != first['scopeSequence']) {
          throw const CryptoAuthorityPending('crypto_checkpoint_changed');
        }
        if (page['checkpoint'] is Map) {
          checkpoint ??= Map<String, dynamic>.from(page['checkpoint'] as Map);
        }
        for (final raw in page['descriptors'] as List) {
          if (raw is! Map) {
            throw const FormatException('crypto_inventory_descriptor');
          }
          final d = Map<String, dynamic>.from(raw);
          if (d.length != 5 ||
              !isCryptoWireRecordId(d['id']) ||
              after != null && (d['id'] as String).compareTo(after) <= 0 ||
              d['revision'] is! int ||
              d['revision'] < 1 ||
              d['sequence'] is! int ||
              d['sequence'] < 1 ||
              d['sequence'] > page['scopeSequence'] ||
              d['recordEpoch'] is! int ||
              d['recordEpoch'] < 1 ||
              d['recordEpoch'] > context.epoch ||
              d['recordProofHash'] is! String ||
              !RegExp(r'^[a-f0-9]{64}$').hasMatch(d['recordProofHash'])) {
            throw const FormatException('crypto_inventory_descriptor');
          }
          after = d['id'] as String;
          sink.add([...CryptoJson.encode(d), 10]);
          await database.execute(
            'INSERT INTO crypto_domain_inventory_rows VALUES(?,?,?,?,?,?,?)',
            [
              partition,
              snapshot,
              d['id'],
              d['revision'],
              d['recordProofHash'],
              d['sequence'],
              d['recordEpoch'],
            ],
          );
          count++;
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
      if (checkpoint == null) return null;
      if (checkpoint['manifestHash'] != hash ||
          checkpoint['recordCount'] != count ||
          checkpoint['membershipHeadHash'] != context.headHash ||
          checkpoint['domainSequence'] != first['scopeSequence']) {
        throw const FormatException('crypto_inventory_root');
      }
      final accepted = observedAnchors
          ?.where(
            (a) =>
                a['domain'] == domain &&
                a['membershipHeadHash'] == context.headHash &&
                a['sequence'] == first!['scopeSequence'] &&
                a['manifestHash'] == hash &&
                a['recordCount'] == count,
          )
          .toList();
      if (accepted != null && accepted.isEmpty) {
        throw const CryptoAuthorityPending('crypto_observed_inventory_pending');
      }
      Map<String, dynamic>? proof;
      String? basis;
      Map<String, dynamic>? proofPage = checkpoint;
      String? proofCursor;
      // Independent attestations avoid a malicious first signer locking out a
      // trusted peer. Each page is bounded and all retained source rows survive.
      for (var pages = 0; pages < 32 && proofPage != null; pages++) {
        final attestations = proofPage['attestations'];
        if (attestations is! List || attestations.length > 20) {
          throw const FormatException('crypto_inventory_attestations');
        }
        for (final candidate in attestations) {
          late Map<String, dynamic> p;
          try {
            p = Map<String, dynamic>.from(
              (candidate as Map)['authorization'] as Map,
            );
            if (accepted != null) {
              final digest = await codec.digest(p);
              if (!accepted.any(
                (a) => (a['proofHashes'] as List).contains(digest),
              )) {
                continue;
              }
            }
            final b =
                CryptoJson.decode(cryptoBase64(p['commandBase64'])) as Map;
            final payload = Map<String, dynamic>.from(b['payload'] as Map);
            if (payload['scopeId'] != scope ||
                payload['domain'] != domain ||
                payload['epoch'] != context.epoch ||
                payload['membershipHeadHash'] != context.headHash ||
                payload['accessRevision'] != context.accessRevision ||
                payload['expectedSequence'] != first['scopeSequence'] ||
                payload['recordCount'] != count ||
                payload['manifestHash'] != hash) {
              continue;
            }
          } on FormatException {
            continue;
          } on TypeError {
            continue;
          }
          try {
            final verifiedBasis = await verify(p);
            if (![
              'verifiedCheckpoint',
              'reviewedRecoveryBaseline',
            ].contains(verifiedBasis)) {
              continue;
            }
            proof = p;
            basis = verifiedBasis;
            break;
          } on FormatException {
            // A bad server-supplied attestation does not hide another valid peer.
          } on CryptoAuthorityPending {
            // Missing independently trusted identity is not accepted as authority.
          }
        }
        if (proof != null || proofPage['hasMore'] != true) break;
        final next = proofPage['nextAfterProofHash'];
        if (next is! String ||
            next.length != 64 ||
            (proofCursor != null && next.compareTo(proofCursor) <= 0)) {
          throw const FormatException('crypto_inventory_proof_cursor');
        }
        proofCursor = next;
        final page = await call('crypto2.domain.checkpoints', {
          'scopeId': scope,
          'domain': domain,
          'accessRevision': context.accessRevision,
          'membershipHeadHash': context.headHash,
          'sequence': first['scopeSequence'],
          'afterProofHash': next,
          'limit': 20,
        });
        proofPage = page['checkpoint'] is Map
            ? Map<String, dynamic>.from(page['checkpoint'] as Map)
            : null;
      }
      if (proof == null) return null;
      var covered = true;
      await database.transaction(() async {
        final state = (await database.rows(
          'SELECT * FROM crypto_scope_state WHERE partition=? AND scope_id=? AND domain=?',
          [partition, scope, domain],
        )).firstOrNull;
        if (state != null &&
            (context.epoch < (state['floor'] as int) ||
                context.accessRevision < (state['access_revision'] as int))) {
          throw const FormatException('crypto_signed_checkpoint_rollback');
        }
        // Every locally authenticated latest record is a floor. A signed remote
        // inventory cannot omit it, lower it, or substitute a different proof.
        final omittedRestoreAnchor = await database.rows(
          '''SELECT 1 FROM crypto_restore_record_anchors a
          WHERE a.partition=? AND a.scope_id=? AND a.domain=? AND NOT EXISTS(
            SELECT 1 FROM crypto_domain_inventory_rows i WHERE i.partition=a.partition
              AND i.snapshot_id=? AND i.record_id=a.record_id AND i.revision=a.revision
              AND i.proof_hash=a.proof_hash) LIMIT 1''',
          [partition, scope, domain, snapshot],
        );
        if (omittedRestoreAnchor.isNotEmpty) {
          // A successor must first be authenticated through pull/history. An
          // unsigned higher inventory revision cannot retire a restored floor.
          covered = false;
          return;
        }
        String? knownAfter;
        while (true) {
          final known = await database.rows(
            "SELECT r.* FROM crypto_received r WHERE r.partition=? AND r.scope_id=? AND r.domain=? AND r.batch_key IS NOT NULL AND r.record_id>? AND r.revision=(SELECT MAX(x.revision) FROM crypto_received x WHERE x.partition=r.partition AND x.scope_id=r.scope_id AND x.domain=r.domain AND x.record_id=r.record_id AND x.batch_key IS NOT NULL) ORDER BY r.record_id LIMIT 50",
            [partition, scope, domain, knownAfter ?? ''],
          );
          if (known.isEmpty) break;
          for (final r in known) {
            final descriptor = (await database.rows(
              'SELECT * FROM crypto_domain_inventory_rows WHERE partition=? AND snapshot_id=? AND record_id=?',
              [partition, snapshot, r['record_id']],
            )).firstOrNull;
            final wire = jsonDecode(r['wire'] as String) as Map;
            final proofHash = await codec.digest(
              Map<String, dynamic>.from(
                (wire['authorization'] as Map)['recordProof'] as Map,
              ),
            );
            if (descriptor == null ||
                descriptor['revision'] != r['revision'] ||
                descriptor['proof_hash'] != proofHash) {
              covered = false;
              return;
            }
            knownAfter = r['record_id'] as String;
          }
        }
        await database.execute(
          'INSERT OR IGNORE INTO crypto_domain_checkpoints VALUES(?,?,?,?,?,?,?,?,?,?,?,?)',
          [
            partition,
            scope,
            domain,
            context.headHash,
            context.epoch,
            context.accessRevision,
            first!['scopeSequence'],
            hash,
            count,
            snapshot,
            jsonEncode(proof),
            basis,
          ],
        );
        // These three positions are explicitly transport coordinates. Reset them
        // only after signed inventory verification; record/epoch/access floors and
        // all raw observations remain untouched. Projection completeness stays off.
        if (state != null &&
            ((state['transport_cursor'] as int) >
                    (first!['scopeSequence'] as int) ||
                (state['scope_sequence'] as int) >
                    (first['scopeSequence'] as int) ||
                (state['projection_cursor'] as int) >
                    (first['scopeSequence'] as int))) {
          await database.execute(
            'UPDATE crypto_scope_state SET transport_cursor=0,projection_cursor=0,scope_sequence=?,complete=0,scan_generation=scan_generation+1 WHERE partition=? AND scope_id=? AND domain=?',
            [first['scopeSequence'], partition, scope, domain],
          );
        }
      });
      if (!covered) return null;
      final retained = await database.rows(
        'SELECT snapshot_id FROM crypto_domain_checkpoints WHERE partition=? AND scope_id=? AND domain=? AND head_hash=? AND sequence=? AND manifest_hash=?',
        [
          partition,
          scope,
          domain,
          context.headHash,
          first['scopeSequence'],
          hash,
        ],
      );
      return retained.isEmpty ? null : retained.single['snapshot_id'] as String;
    } finally {
      // Unsigned/failed/repeated staging is not historical business evidence.
      // Keep only descriptor sets referenced by a durable signed checkpoint.
      await database.execute(
        'DELETE FROM crypto_domain_inventory_rows WHERE partition=? AND snapshot_id=? AND NOT EXISTS(SELECT 1 FROM crypto_domain_checkpoints c WHERE c.partition=? AND c.snapshot_id=?)',
        [partition, snapshot, partition, snapshot],
      );
    }
  }
}
