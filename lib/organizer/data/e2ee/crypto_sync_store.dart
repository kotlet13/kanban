import 'dart:convert';
import 'crypto_json.dart';
import 'package:cryptography/cryptography.dart' show Sha256;

import '../collaboration_database.dart';

String _wireText(Object? value) {
  Object? ordered(Object? item) {
    if (item is Map) {
      final keys = item.keys.cast<String>().toList()..sort();
      return {for (final key in keys) key: ordered(item[key])};
    }
    if (item is List) return item.map(ordered).toList();
    return item;
  }

  return jsonEncode(ordered(value));
}

/// Durable transport evidence. Callers validate cryptographic receipts before
/// changing state; an HTTP success alone never deletes outgoing work.
class CryptoSyncStore {
  const CryptoSyncStore(this.database, this.partition);
  final CollaborationDatabase database;
  final String partition;

  Future<T> transaction<T>(Future<T> Function() body) =>
      database.transaction(body);

  Future<List<Map<String, Object?>>> pending() => database.rows(
    "SELECT * FROM crypto_outbox WHERE partition=? AND state='pending' ORDER BY sequence",
    [partition],
  );

  /// Fixed initial watermark and bounded ciphertext pages. Pending requests
  /// retain sequence order; unknown outcomes stay pending for the next pass,
  /// and concurrently enqueued work cannot make this delivery pass endless.
  Stream<Map<String, Object?>> pendingDelivery() => _deliveryRows('pending');

  Stream<Map<String, Object?>> blockedDelivery() => _deliveryRows('blocked');

  Stream<Map<String, Object?>> _deliveryRows(String state) async* {
    final watermark =
        (await database.rows(
              "SELECT MAX(sequence) AS last_sequence FROM crypto_outbox WHERE partition=? AND state=?",
              [partition, state],
            )).single['last_sequence']
            as int?;
    if (watermark == null) return;
    var after = 0;
    while (after < watermark) {
      final page = await database.transaction(() async {
        final metadata = await database.rows(
          "SELECT sequence,LENGTH(CAST(signed_body AS BLOB)) AS body_bytes FROM crypto_outbox WHERE partition=? AND state=? AND sequence>? AND sequence<=? ORDER BY sequence LIMIT 16",
          [partition, state, after, watermark],
        );
        if (metadata.isEmpty) return <Map<String, Object?>>[];
        var bytes = 0, count = 0, last = after;
        for (final row in metadata) {
          final size = row['body_bytes'] as int;
          if (count > 0 && bytes + size > 1024 * 1024) break;
          // Even a single maximum valid immutable body must make progress.
          // Corrupted oversized SQL remains preserved and fails explicitly.
          if (size > 2 * 1024 * 1024) {
            throw const FormatException('crypto_stored_command_size');
          }
          bytes += size;
          count++;
          last = row['sequence'] as int;
        }
        return database.rows(
          "SELECT * FROM crypto_outbox WHERE partition=? AND state=? AND sequence>? AND sequence<=? ORDER BY sequence LIMIT 16",
          [partition, state, after, last],
        );
      });
      if (page.isEmpty) break;
      for (final row in page) {
        after = row['sequence'] as int;
        yield row;
      }
    }
  }

  Future<Map<String, Object?>?> outgoing(String requestId) async =>
      (await database.rows(
        'SELECT * FROM crypto_outbox WHERE partition=? AND request_id=?',
        [partition, requestId],
      )).firstOrNull;

  Future<void> stage({
    required String requestId,
    required String operation,
    required Map<String, dynamic> signed,
    required String requestHash,
  }) async {
    final body = utf8.decode(CryptoJson.encode(signed));
    final old = await outgoing(requestId);
    if (old != null) {
      if (old['operation'] != operation ||
          old['signed_body'] != body ||
          old['request_hash'] != requestHash) {
        throw const FormatException('crypto_immutable_request');
      }
      return;
    }
    await database.execute(
      'INSERT INTO crypto_outbox(partition,request_id,operation,signed_body,request_hash) VALUES(?,?,?,?,?)',
      [partition, requestId, operation, body, requestHash],
    );
  }

  /// A local revision can have only one immutable successor intent. Failed or
  /// unknown outcomes retain this claim until explicit signed reconciliation.
  Future<void> claimRecord(
    Map<String, dynamic> record,
    String requestId, {
    String? replacesRejectedRequestId,
  }) async {
    final rows = await database.rows(
      'SELECT request_id FROM crypto_outbox_records WHERE partition=? AND scope_id=? AND domain=? AND record_id=? AND expected_revision=?',
      [
        partition,
        record['scopeId'],
        record['domain'],
        record['id'],
        record['expectedRevision'],
      ],
    );
    if (rows.isNotEmpty && rows.single['request_id'] != requestId) {
      if (rows.single['request_id'] != replacesRejectedRequestId ||
          (await outgoing(replacesRejectedRequestId!))?['state'] !=
              'rejected') {
        throw const FormatException('crypto_local_revision_claimed');
      }
      await database.execute(
        'UPDATE crypto_outbox_records SET request_id=? WHERE partition=? AND scope_id=? AND domain=? AND record_id=? AND expected_revision=? AND request_id=?',
        [
          requestId,
          partition,
          record['scopeId'],
          record['domain'],
          record['id'],
          record['expectedRevision'],
          replacesRejectedRequestId,
        ],
      );
    }
    await database.execute(
      'INSERT OR IGNORE INTO crypto_outbox_records(partition,scope_id,domain,record_id,expected_revision,request_id) VALUES(?,?,?,?,?,?)',
      [
        partition,
        record['scopeId'],
        record['domain'],
        record['id'],
        record['expectedRevision'],
        requestId,
      ],
    );
  }

  Future<void> outcome(
    String requestId,
    String state,
    Map<String, dynamic> response,
  ) async {
    if (!['applied', 'rejected', 'blocked'].contains(state)) {
      throw const FormatException('crypto_outcome');
    }
    final rows = await outgoing(requestId);
    if (rows == null) throw const FormatException('crypto_missing_request');
    final body = _wireText(response);
    if (rows['state'] != 'pending' &&
        (rows['state'] != state || rows['response'] != body)) {
      throw const FormatException('crypto_receipt_changed');
    }
    if (state == 'blocked') {
      await database.execute(
        'INSERT INTO crypto_outbox_attempts(partition,request_id,event,details) VALUES(?,?,?,?)',
        [partition, requestId, 'blocked', body],
      );
    }
    await database.execute(
      'UPDATE crypto_outbox SET state=?,response=? WHERE partition=? AND request_id=?',
      [state, body, partition, requestId],
    );
  }

  /// Explicit retry retains the same request bytes and revision claim. Only
  /// unresolved blocked work can resume; conclusive outcomes stay immutable.
  Future<void> retryBlocked(String requestId) => transaction(() async {
    final old = await outgoing(requestId);
    if (old == null ||
        old['state'] != 'blocked' ||
        (jsonDecode(old['response'] as String) as Map)['outcome'] !=
            'unresolved')
      throw const FormatException('crypto_retry_not_unresolved');
    await database.execute(
      'INSERT INTO crypto_outbox_attempts(partition,request_id,event,details) VALUES(?,?,?,?)',
      [partition, requestId, 'retry', old['response']],
    );
    await database.execute(
      "UPDATE crypto_outbox SET state='pending',response=NULL WHERE partition=? AND request_id=? AND state='blocked'",
      [partition, requestId],
    );
  });

  Future<Map<String, Object?>?> scope(
    String scopeId,
    String domain,
  ) async => (await database.rows(
    'SELECT * FROM crypto_scope_state WHERE partition=? AND scope_id=? AND domain=?',
    [partition, scopeId, domain],
  )).firstOrNull;

  Future<void> receive({
    required String scopeId,
    required String domain,
    required Map<String, dynamic> wire,
    required String verdict,
    String? error,
    String? historyBasis,
    String? batchKey,
  }) async {
    final text = _wireText(wire);
    final candidateHash = (await Sha256().hash(
      utf8.encode(text),
    )).bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    // Every raw transport observation remains independently exportable. An
    // unauthenticated first response cannot reserve a business revision forever.
    await database.execute(
      "INSERT INTO crypto_received_candidates(partition,scope_id,domain,record_id,revision,candidate_hash,sequence,wire,verdict,error,batch_key) VALUES(?,?,?,?,?,?,?,?,?,?,?) ON CONFLICT(partition,scope_id,domain,record_id,revision,candidate_hash) DO UPDATE SET verdict=CASE WHEN crypto_received_candidates.verdict IN ('verified','superseded') THEN crypto_received_candidates.verdict ELSE excluded.verdict END,error=excluded.error,batch_key=COALESCE(crypto_received_candidates.batch_key,excluded.batch_key)",
      [
        partition,
        scopeId,
        domain,
        wire['id'],
        wire['revision'],
        candidateHash,
        wire['sequence'],
        text,
        verdict,
        error,
        batchKey,
      ],
    );
    final old = (await database.rows(
      'SELECT * FROM crypto_received WHERE partition=? AND scope_id=? AND domain=? AND record_id=? AND revision=?',
      [partition, scopeId, domain, wire['id'], wire['revision']],
    )).firstOrNull;
    if (old != null && old['wire'] != text) {
      if (batchKey == null)
        return; // Retained candidate awaits signature checks.
      final oldWire = jsonDecode(old['wire'] as String) as Map;
      final sameProof =
          _wireText(oldWire['authorization']) ==
          _wireText(wire['authorization']);
      if (old['batch_key'] != null && !sameProof) {
        // Both signatures authenticated: preserve both and invalidate aggregate
        // completeness, rather than choosing whichever the server sent first.
        await database.execute(
          "UPDATE crypto_received SET verdict='quarantined',error='crypto_revision_equivocation' WHERE partition=? AND scope_id=? AND domain=? AND record_id=? AND revision=?",
          [partition, scopeId, domain, wire['id'], wire['revision']],
        );
        await database.execute(
          'UPDATE crypto_scope_state SET complete=0 WHERE partition=? AND scope_id=? AND domain=?',
          [partition, scopeId, domain],
        );
        throw const FormatException('crypto_revision_equivocation');
      }
      if (old['batch_key'] != null && sameProof) {
        // Sequence belongs to untrusted transport, not the signed record proof.
        // Keep verified projection state; a verified checkpoint reconciles its
        // final position separately. Every old observation remains above.
        await database.execute(
          'UPDATE crypto_received SET wire=?,sequence=? WHERE partition=? AND scope_id=? AND domain=? AND record_id=? AND revision=?',
          [
            text,
            wire['sequence'],
            partition,
            scopeId,
            domain,
            wire['id'],
            wire['revision'],
          ],
        );
      } else {
        await database.execute(
          'UPDATE crypto_received SET wire=?,sequence=?,verdict=?,error=?,history_basis=?,batch_key=? WHERE partition=? AND scope_id=? AND domain=? AND record_id=? AND revision=?',
          [
            text,
            wire['sequence'],
            verdict,
            error,
            historyBasis,
            batchKey,
            partition,
            scopeId,
            domain,
            wire['id'],
            wire['revision'],
          ],
        );
      }
    }
    await database.execute(
      "INSERT INTO crypto_received(partition,scope_id,domain,record_id,revision,sequence,wire,verdict,error,history_basis,batch_key) VALUES(?,?,?,?,?,?,?,?,?,?,?) ON CONFLICT(partition,scope_id,domain,record_id,revision) DO UPDATE SET verdict=CASE WHEN crypto_received.verdict IN ('verified','superseded') THEN crypto_received.verdict ELSE excluded.verdict END,error=CASE WHEN crypto_received.verdict IN ('verified','superseded') THEN crypto_received.error ELSE excluded.error END,history_basis=CASE WHEN crypto_received.verdict IN ('verified','superseded') THEN crypto_received.history_basis ELSE excluded.history_basis END,batch_key=COALESCE(crypto_received.batch_key,excluded.batch_key) WHERE crypto_received.wire=excluded.wire",
      [
        partition,
        scopeId,
        domain,
        wire['id'],
        wire['revision'],
        wire['sequence'],
        text,
        verdict,
        error,
        historyBasis,
        batchKey,
      ],
    );
  }

  Future<void> supersede({
    required String scopeId,
    required String domain,
    required String recordId,
    required int revision,
    required String proofHash,
    required int replacementRevision,
  }) async {
    if (replacementRevision != revision + 1) {
      throw const FormatException('crypto_repair_revision');
    }
    final rows = await database.rows(
      'SELECT wire,verdict FROM crypto_received WHERE partition=? AND scope_id=? AND domain=? AND record_id=? AND revision=?',
      [partition, scopeId, domain, recordId, revision],
    );
    if (rows.length != 1) {
      throw const FormatException('crypto_repair_missing_evidence');
    }
    final wire = jsonDecode(rows.single['wire'] as String) as Map;
    final proof = (wire['authorization'] as Map)['recordProof'];
    final hash = (await Sha256().hash(
      CryptoJson.encode(proof),
    )).bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    if (hash != proofHash) {
      throw const FormatException('crypto_repair_substitution');
    }
    if (rows.single['verdict'] == 'quarantined') {
      await database.execute(
        "UPDATE crypto_received SET verdict='superseded',superseded_by_revision=? WHERE partition=? AND scope_id=? AND domain=? AND record_id=? AND revision=?",
        [replacementRevision, partition, scopeId, domain, recordId, revision],
      );
    }
  }

  /// A known crypto floor never decreases, including after an older portable
  /// backup or a server capability rollback. No method sets it back to zero.
  Future<void> checkpoint({
    required String scopeId,
    required String domain,
    required int epoch,
    required int accessRevision,
    required int transportCursor,
    required int projectionCursor,
    required int scopeSequence,
    required bool complete,
  }) async {
    final old = await scope(scopeId, domain);
    if (epoch < 1 ||
        accessRevision < 0 ||
        transportCursor < 0 ||
        projectionCursor < 0 ||
        projectionCursor > transportCursor ||
        transportCursor > scopeSequence ||
        old != null &&
            (epoch < (old['floor'] as int) ||
                transportCursor < (old['transport_cursor'] as int) ||
                accessRevision < (old['access_revision'] as int) ||
                scopeSequence < (old['scope_sequence'] as int) ||
                projectionCursor < (old['projection_cursor'] as int))) {
      throw const FormatException('crypto_checkpoint_rollback');
    }
    await database.execute(
      "INSERT INTO crypto_scope_state(partition,scope_id,domain,state,epoch,access_revision,transport_cursor,projection_cursor,scope_sequence,complete,floor) VALUES(?,?,?,'staged',?,?,?,?,?,?,?) ON CONFLICT(partition,scope_id,domain) DO UPDATE SET epoch=excluded.epoch,access_revision=excluded.access_revision,transport_cursor=excluded.transport_cursor,projection_cursor=excluded.projection_cursor,scope_sequence=excluded.scope_sequence,complete=excluded.complete,floor=MAX(crypto_scope_state.floor,excluded.floor)",
      [
        partition,
        scopeId,
        domain,
        epoch,
        accessRevision,
        transportCursor,
        projectionCursor,
        scopeSequence,
        complete ? 1 : 0,
        epoch,
      ],
    );
  }
}
