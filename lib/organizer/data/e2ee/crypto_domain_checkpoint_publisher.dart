import 'dart:convert';
import '../../domain/payment_completion_diagnostics.dart';
import 'package:cryptography/cryptography.dart' show Sha256;

import 'crypto_business_router.dart';
import '../collaboration_transport.dart' show CollaborationApiException;
import 'crypto_json.dart';
import 'crypto_sync_repository.dart';
import 'crypto_checkpoint_supersession.dart';

/// Attests only the exact authenticated, projected record set this device has
/// observed. This is not evidence that the server disclosed unseen history.
class CryptoDomainCheckpointPublisher {
  CryptoDomainCheckpointPublisher(this.context);
  final CryptoBusinessSession context;

  Future<PaymentCheckpointStep> publish(String scope, String domain) async {
    final read = await context.access.readContext(scope, domain);
    if (await context.hasReusableCheckpoint(scope, domain, read)) {
      await _reconcileReusableReceipt(scope, domain, read);
      await CryptoCheckpointSupersession(
        context,
      ).reconcile(scope, domain, read);
      return PaymentCheckpointStep.reusableCheckpoint;
    }
    final snapshot = context.codec.crypto.randomId();
    final db = context.database, partition = context.partition;
    final initialState = (await db.rows(
      'SELECT * FROM crypto_scope_state WHERE partition=? AND scope_id=? AND domain=?',
      [partition, scope, domain],
    )).firstOrNull;
    if (initialState == null) return PaymentCheckpointStep.scopeStateMissing;
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
        if (sequence != page['scopeSequence']) {
          return PaymentCheckpointStep.inventorySequenceChanged;
        }
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
            return projected == null
                ? PaymentCheckpointStep.projectedRecordMissing
                : projected['crypto_revision'] != descriptor['revision']
                ? PaymentCheckpointStep.projectedRevisionMismatch
                : PaymentCheckpointStep.projectedProofMismatch;
          }
          if (!const [
            'currentEpoch',
            'verifiedCheckpoint',
            'reviewedRecoveryBaseline',
            'migrationCapturedSource',
            'inlineProjectDeletion',
            'managerAttestedProjectRelocation',
          ].contains(projected['history_basis'])) {
            return PaymentCheckpointStep.projectedHistoryUnverified;
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
      if (uncovered.isNotEmpty) {
        return PaymentCheckpointStep.receivedInventoryUncovered;
      }
      if ((await db.rows(
        '''SELECT 1 FROM crypto_restore_record_anchors a
        WHERE a.partition=? AND a.scope_id=? AND a.domain=? AND NOT EXISTS(
          SELECT 1 FROM crypto_domain_inventory_rows i WHERE i.partition=a.partition
            AND i.snapshot_id=? AND i.record_id=a.record_id AND i.revision=a.revision
            AND i.proof_hash=a.proof_hash) LIMIT 1''',
        [partition, scope, domain, snapshot],
      )).isNotEmpty) {
        return PaymentCheckpointStep.restoreAnchorUncovered;
      }
      final omitted = await db.rows(
        '''SELECT 1 FROM crypto_business_records b
        WHERE b.partition=? AND b.scope_id=? AND b.domain=? AND NOT EXISTS(
          SELECT 1 FROM crypto_domain_inventory_rows i WHERE i.partition=b.partition
          AND i.snapshot_id=? AND i.record_id=b.id AND i.revision=b.crypto_revision
          AND i.proof_hash=b.record_proof_hash) LIMIT 1''',
        [partition, scope, domain, snapshot],
      );
      if (omitted.isNotEmpty) {
        return PaymentCheckpointStep.businessRecordOmitted;
      }
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
        return PaymentCheckpointStep.commandAuthorityPending;
      } on CollaborationApiException catch (error) {
        if (!const {
          'crypto_checkpoint_changed',
          'crypto_checkpoint_immutable',
        }.contains(error.code)) {
          rethrow;
        }
        return error.code == 'crypto_checkpoint_changed'
            ? PaymentCheckpointStep.commandCheckpointChanged
            : PaymentCheckpointStep.commandCheckpointImmutable;
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
      if (verified == null) {
        return PaymentCheckpointStep.checkpointVerificationPending;
      }
      final result = await db.transaction(() async {
        final state = (await db.rows(
          'SELECT * FROM crypto_scope_state WHERE partition=? AND scope_id=? AND domain=?',
          [partition, scope, domain],
        )).firstOrNull;
        if (state == null) {
          return PaymentCheckpointStep.completionStateMissing;
        }
        if (state['floor'] != read.epoch) {
          return PaymentCheckpointStep.completionFloorChanged;
        }
        if (state['access_revision'] != read.accessRevision) {
          return PaymentCheckpointStep.completionAccessRevisionChanged;
        }
        if (state['scope_sequence'] != sequence) {
          return PaymentCheckpointStep.completionScopeSequenceChanged;
        }
        if (state['scan_generation'] != initialState['scan_generation']) {
          return PaymentCheckpointStep.completionScanGenerationChanged;
        }
        if ((state['projection_cursor'] as int) < sequence!) {
          return PaymentCheckpointStep.completionProjectionCursorBehind;
        }
        if (!context.account.directory.isCurrent()) {
          return PaymentCheckpointStep.completionSessionChanged;
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
        if (checkpoint.length != 1) {
          return PaymentCheckpointStep.completionCheckpointMissing;
        }
        final stale = await db.rows(
          """SELECT 1 FROM crypto_business_records b
          WHERE b.partition=? AND b.scope_id=? AND b.domain=? AND NOT EXISTS(
            SELECT 1 FROM crypto_domain_inventory_rows i WHERE i.partition=b.partition
              AND i.snapshot_id=? AND i.record_id=b.id AND i.revision=b.crypto_revision
              AND i.proof_hash=b.record_proof_hash) LIMIT 1""",
          [partition, scope, domain, verified],
        );
        if (stale.isNotEmpty) {
          return PaymentCheckpointStep.completionBusinessRecordStale;
        }
        if ((await db.rows(
          '''SELECT 1 FROM crypto_restore_record_anchors a
          WHERE a.partition=? AND a.scope_id=? AND a.domain=? AND NOT EXISTS(
            SELECT 1 FROM crypto_domain_inventory_rows i WHERE i.partition=a.partition
              AND i.snapshot_id=? AND i.record_id=a.record_id AND i.revision=a.revision
              AND i.proof_hash=a.proof_hash) LIMIT 1''',
          [partition, scope, domain, verified],
        )).isNotEmpty) {
          return PaymentCheckpointStep.completionRestoreAnchorUncovered;
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
              return PaymentCheckpointStep.completionReceivedUnverified;
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
            if (matched.length != 1) {
              return PaymentCheckpointStep.completionReceivedProofUnmatched;
            }
            cursor = r['record_id'] as String;
          }
        }
        final projectedCount = (await db.rows(
          'SELECT COUNT(*) AS n FROM crypto_business_records WHERE partition=? AND scope_id=? AND domain=?',
          [partition, scope, domain],
        )).single['n'];
        if (projectedCount != count) {
          return PaymentCheckpointStep.completionCountMismatch;
        }
        await db.execute(
          'UPDATE crypto_scope_state SET complete=1 WHERE partition=? AND scope_id=? AND domain=?',
          [partition, scope, domain],
        );
        return PaymentCheckpointStep.complete;
      });
      if (result == PaymentCheckpointStep.complete) {
        await CryptoCheckpointSupersession(
          context,
        ).reconcile(scope, domain, read);
      }
      return result;
    } finally {
      await db.execute(
        'DELETE FROM crypto_domain_inventory_rows WHERE partition=? AND snapshot_id=?',
        [partition, snapshot],
      );
    }
  }

  /// A pulled, verified own attestation may precede a lost command ACK. Settle
  /// only that exact retained request; the observed projection cannot replace
  /// its receipt or authorize retransmission, including from an older device.
  Future<void> _reconcileReusableReceipt(
    String scope,
    String domain,
    CryptoReadContext read,
  ) async {
    final rows = await context.database.rows(
      '''SELECT c.authorization,c.sequence,c.manifest_hash,c.record_count
      FROM crypto_domain_checkpoints c JOIN crypto_scope_state s
      ON s.partition=c.partition AND s.scope_id=c.scope_id AND s.domain=c.domain
      WHERE c.partition=? AND c.scope_id=? AND c.domain=? AND c.head_hash=?
        AND c.epoch=? AND c.access_revision=? AND c.sequence=s.scope_sequence
        AND s.floor=? AND s.access_revision=? AND s.complete=1
        AND s.projection_cursor>=s.transport_cursor LIMIT 2''',
      [
        context.partition,
        scope,
        domain,
        read.headHash,
        read.epoch,
        read.accessRevision,
        read.epoch,
        read.accessRevision,
      ],
    );
    if (rows.length != 1) return;
    final checkpoint = rows.single;
    late Map<String, dynamic> proof;
    late Map command, payload;
    try {
      proof = Map<String, dynamic>.from(
        jsonDecode(checkpoint['authorization'] as String) as Map,
      );
      command = CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map;
      payload = command['payload'] as Map;
    } on FormatException {
      return;
    } on TypeError {
      return;
    }
    final session = context.account.directory.session.profile;
    if (command['version'] != 2 ||
        command['operation'] != 'crypto2.domain.checkpoint' ||
        command['serverId'] != session.serverId ||
        command['accountId'] != session.accountId ||
        command['requestId'] is! String ||
        payload['scopeId'] != scope ||
        payload['domain'] != domain ||
        payload['membershipHeadHash'] != read.headHash ||
        payload['epoch'] != read.epoch ||
        payload['accessRevision'] != read.accessRevision ||
        payload['expectedSequence'] != checkpoint['sequence'] ||
        payload['manifestHash'] != checkpoint['manifest_hash'] ||
        payload['recordCount'] != checkpoint['record_count']) {
      return;
    }
    final request = command['requestId'] as String;
    final saved = await context.queue.store.outgoing(request);
    if (saved == null ||
        saved['operation'] != 'crypto2.domain.checkpoint' ||
        !const {'pending', 'blocked'}.contains(saved['state']) ||
        base64Encode(
              CryptoJson.encode(jsonDecode(saved['signed_body'] as String)),
            ) !=
            base64Encode(CryptoJson.encode(proof))) {
      return;
    }
    await context.queue.reconcileTerminalReceipts(requestIds: {request});
  }
}
