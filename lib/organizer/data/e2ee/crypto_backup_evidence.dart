import '../collaboration_database.dart';
import '../../domain/shared_payload_validation.dart' show isSharedUuid;
import 'dart:convert';
import 'dart:typed_data';

/// Portable encrypted container evidence; account private keys are deliberately
/// absent. Imported evidence remains in restored_backups, never live grants,
/// active cursors or a deliverable outbox. Resume requires the same pinned
/// identity, fresh membership and cryptographic validation of every receipt.
const cryptoEvidenceTables = <String, List<String>>{
  'crypto_migration_witnesses': [
    'partition',
    'binding_id',
    'context',
    'descriptor',
  ],
  'crypto_migration_file_objects': [
    'partition',
    'binding_id',
    'context',
    'descriptor',
  ],
  'crypto_restore_record_anchors': [
    'partition',
    'scope_id',
    'domain',
    'record_id',
    'revision',
    'proof_hash',
    'wire',
  ],
  'crypto_restore_scoped_directories': [
    'partition',
    'scope_id',
    'head_hash',
    'account_id',
    'directory_head_hash',
    'entries',
  ],
  'crypto_business_addresses': [
    'partition',
    'scope_id',
    'domain',
    'source_kind',
    'canonical_id',
    'wire_id',
    'type',
  ],
  'crypto_business_history_proofs': [
    'partition',
    'scope_id',
    'domain',
    'record_id',
    'revision',
    'proof_hash',
    'wire',
    'history_basis',
  ],
  'crypto_business_history_jobs': [
    'partition',
    'scope_id',
    'domain',
    'record_id',
    'target_revision',
    'target_hash',
    'next_revision',
    'next_hash',
    'complete',
  ],
  'crypto_business_requests': [
    'partition',
    'operation_id',
    'scope_id',
    'domain',
    'request_hash',
    'request_id',
    'record_id',
  ],
  'crypto_archive_jobs': [
    'partition',
    'migration_id',
    'key_id',
    'state',
    'manifest',
  ],
  'crypto_archive_key_wrappers': [
    'partition',
    'migration_id',
    'key_id',
    'context',
    'envelopes',
    'state',
  ],
  'crypto_archive_segments': [
    'partition',
    'migration_id',
    'key_id',
    'id',
    'segment_index',
    'size',
    'sha256',
    'state',
  ],
  'crypto_archive_chunks': ['partition', 'segment_id', 'chunk_offset', 'bytes'],
  'crypto_scope_review_records': [
    'partition',
    'scope_id',
    'review_id',
    'domain',
    'record_id',
    'wire',
    'descriptor',
  ],
  'crypto_scope_key_grants': [
    'partition',
    'scope_id',
    'domain',
    'epoch',
    'epoch_id',
    'key_id',
    'scope_head_hash',
    'grant',
    'recovery_wrapping_durable',
    'write_ready',
  ],
  'crypto_scope_closures': [
    'partition',
    'scope_id',
    'domain',
    'epoch',
    'candidate_head_hash',
    'manifest_hash',
    'history_basis',
    'authorization',
    'descriptors',
  ],
  'crypto_outbox_attempts': [
    'sequence',
    'partition',
    'request_id',
    'event',
    'details',
  ],
  'crypto_command_keys': [
    'partition',
    'action_key',
    'request_id',
    'payload_hash',
  ],
  'crypto_membership_intents': [
    'partition',
    'scope_id',
    'intent_id',
    'state',
    'payload',
    'authorization',
  ],
  'crypto_membership_action_keys': [
    'partition',
    'scope_id',
    'action_key',
    'request_id',
  ],
  'crypto_outbox_reconciliations': [
    'partition',
    'old_request_id',
    'new_request_id',
    'reason',
  ],
  'crypto_outbox_records': [
    'partition',
    'scope_id',
    'domain',
    'record_id',
    'expected_revision',
    'request_id',
  ],
  'crypto_restore_evidence': ['partition', 'backup_id', 'evidence'],
  'crypto_restore_fences': [
    'partition',
    'minimum_transport',
    'backup_id',
    'state',
  ],
  'crypto_directory_pins': [
    'partition',
    'server_id',
    'account_id',
    'root_signing_public',
    'root_encryption_public',
    'fingerprint',
    'min_generation',
    'head_hash',
    'snapshot_hash',
    'device_snapshot_hash',
    'identity_epoch_id',
    'trust_state',
  ],
  'crypto_directory_entries': [
    'partition',
    'account_id',
    'generation',
    'head_hash',
    'previous_head_hash',
    'command_hash',
    'authorization',
  ],
  'crypto_directory_snapshots': [
    'partition',
    'account_id',
    'head_hash',
    'generation',
    'snapshot_hash',
    'device_snapshot_hash',
    'snapshot',
  ],
  'crypto_trusted_identities': [
    'partition',
    'server_id',
    'account_id',
    'root_signing_public',
    'root_encryption_public',
    'fingerprint',
    'verification_method',
    'compared_head_hash',
    'compared_generation',
  ],
  'crypto_scope_heads': [
    'partition',
    'scope_id',
    'head_hash',
    'generation',
    'epoch',
    'epoch_id',
    'previous_head_hash',
    'body',
    'authorization',
  ],
  'crypto_identity_requests': [
    'partition',
    'request_id',
    'operation',
    'stage',
    'authorization',
    'receipt',
    'retired',
  ],
  'crypto_scope_state': [
    'scan_generation',
    'partition',
    'scope_id',
    'domain',
    'state',
    'epoch',
    'access_revision',
    'transport_cursor',
    'projection_cursor',
    'scope_sequence',
    'complete',
    'floor',
    'manifest',
  ],
  'crypto_outbox': [
    'sequence',
    'partition',
    'request_id',
    'operation',
    'signed_body',
    'request_hash',
    'state',
    'response',
  ],
  'crypto_domain_inventory_rows': [
    'partition',
    'snapshot_id',
    'record_id',
    'revision',
    'proof_hash',
    'sequence',
    'record_epoch',
  ],
  'crypto_domain_checkpoints': [
    'partition',
    'scope_id',
    'domain',
    'head_hash',
    'epoch',
    'access_revision',
    'sequence',
    'manifest_hash',
    'record_count',
    'snapshot_id',
    'authorization',
    'history_basis',
  ],
  'crypto_received_candidates': [
    'partition',
    'scope_id',
    'domain',
    'record_id',
    'revision',
    'candidate_hash',
    'sequence',
    'wire',
    'verdict',
    'error',
    'batch_key',
    'last_attempt',
  ],
  'crypto_received': [
    'partition',
    'scope_id',
    'domain',
    'record_id',
    'revision',
    'sequence',
    'wire',
    'verdict',
    'error',
    'superseded_by_revision',
    'history_basis',
    'last_attempt',
    'batch_key',
  ],
  'crypto_migrations': ['partition', 'id', 'state', 'journal'],
  'crypto_migration_staged_records': [
    'partition',
    'migration_id',
    'scope_id',
    'domain',
    'record_id',
    'record_proof_hash',
    'record_proof',
    'batch_commitment',
    'source_binding',
  ],
  'crypto_legacy_receipts': [
    'partition',
    'scope_id',
    'domain',
    'legacy_id',
    'legacy_hash',
    'outcome',
    'replacement_id',
    'response',
  ],
};

Future<Map<String, dynamic>> exportCryptoEvidence(
  CollaborationDatabase database,
  String? partition,
) async {
  final tables = <String, dynamic>{};
  for (final table in cryptoEvidenceTables.keys) {
    final rows = partition == null
        ? <Map<String, Object?>>[]
        : await database.rows(
            'SELECT ${cryptoEvidenceTables[table]!.join(',')} FROM ${table == 'crypto_scope_key_grants'
                ? 'crypto_scope_keys'
                : table == 'crypto_archive_key_wrappers'
                ? 'crypto_archive_secrets'
                : table} WHERE partition=? ORDER BY ${cryptoEvidenceTables[table]!.where((c) => c != 'partition').take(2).join(',')}',
            [partition],
          );
    tables[table] = [
      for (final row in rows)
        {
          for (final cell in row.entries)
            cell.key: cell.value is Uint8List
                ? {'blobBase64': base64Encode(cell.value as Uint8List)}
                : cell.value,
        },
    ];
  }
  return {'version': 1, 'partition': partition, 'tables': tables};
}

bool _cell(Object? value) {
  if (value == null || value is String || value is int) return true;
  if (value is Map && value.length == 1 && value['blobBase64'] is String) {
    try {
      return base64Encode(base64Decode(value['blobBase64'] as String)) ==
          value['blobBase64'];
    } on FormatException {
      return false;
    }
  }
  return false;
}

/// Restoring evidence can only tighten routing, never grant access or queue
/// delivery. The source partition is checked against the enclosing backup.
Future<void> fenceRestoredCryptoEvidence(
  CollaborationDatabase database,
  Object? evidence,
  String? partition,
  String backupId,
) async {
  if (partition == null) return;
  validateCryptoEvidence(evidence, partition);
  final tables = (evidence as Map)['tables'] as Map;
  final scoped = tables['crypto_scope_state'] as List;
  final prior = tables['crypto_restore_fences'] as List;
  final upgraded =
      scoped.any(
        (row) => [
          'active',
          'committed',
          'retired',
          'fenced',
          'verified',
        ].contains((row as Map)['state']),
      ) ||
      prior.isNotEmpty ||
      scoped.any((row) => (row as Map)['floor'] is int && row['floor'] > 0) ||
      (tables['crypto_directory_pins'] as List).isNotEmpty ||
      (tables['crypto_restore_evidence'] as List).isNotEmpty;
  if (!upgraded) return;
  // Keep each decoded public evidence candidate available to offline trust
  // reconciliation; the original encrypted backup alone cannot be read without
  // requesting its password again. No candidate grants rights by being stored.
  final candidates = <String, Object?>{};
  void collect(Object? candidate, String id, int depth) {
    if (depth > 16 || candidates.length > 10000) {
      throw const FormatException('crypto_backup_evidence_depth');
    }
    validateCryptoEvidence(candidate, partition);
    final value = Map<String, dynamic>.from(candidate as Map);
    final candidateTables = Map<String, dynamic>.from(value['tables'] as Map);
    final nested = candidateTables['crypto_restore_evidence'] as List;
    candidateTables['crypto_restore_evidence'] = <Object>[];
    value['tables'] = candidateTables;
    final priorCandidate = candidates[id];
    if (priorCandidate != null &&
        jsonEncode(priorCandidate) != jsonEncode(value)) {
      throw const FormatException('crypto_backup_equivocation');
    }
    candidates[id] = value;
    for (final row in nested) {
      final r = row as Map;
      if (r['backup_id'] is! String || r['evidence'] is! String) {
        throw const FormatException('crypto_backup_candidate');
      }
      collect(
        jsonDecode(r['evidence'] as String),
        r['backup_id'] as String,
        depth + 1,
      );
    }
  }

  collect(evidence, backupId, 0);
  for (final entry in candidates.entries) {
    final encoded = jsonEncode(entry.value);
    final old = await database.rows(
      'SELECT evidence FROM crypto_restore_evidence WHERE partition=? AND backup_id=?',
      [partition, entry.key],
    );
    if (old.isNotEmpty && old.single['evidence'] != encoded) {
      throw const FormatException('crypto_backup_equivocation');
    }
    await database.execute(
      'INSERT OR IGNORE INTO crypto_restore_evidence(partition,backup_id,evidence) VALUES(?,?,?)',
      [partition, entry.key, encoded],
    );
  }
  await database.execute(
    "INSERT INTO crypto_restore_fences(partition,minimum_transport,backup_id,state) VALUES(?,2,?,'requires_reconciliation') ON CONFLICT(partition) DO UPDATE SET minimum_transport=MAX(crypto_restore_fences.minimum_transport,excluded.minimum_transport),state='requires_reconciliation'",
    [partition, backupId],
  );
  // Unverified backup metadata can tighten only the transport fence. Epoch,
  // access and sequence floors remain candidates until signed proofs establish
  // them; existing authenticated live floors are never overwritten here.
}

void validateCryptoEvidence(Object? value, String? partition) {
  if (value is! Map<String, dynamic> ||
      value.length != 3 ||
      value['version'] != 1 ||
      value['partition'] != partition ||
      value['tables'] is! Map) {
    throw const FormatException('crypto_backup_evidence');
  }
  final tables = value['tables'] as Map;
  if (tables.length != cryptoEvidenceTables.length ||
      tables.keys.any((key) => !cryptoEvidenceTables.containsKey(key))) {
    throw const FormatException('crypto_backup_tables');
  }
  for (final entry in cryptoEvidenceTables.entries) {
    final rows = tables[entry.key];
    if (rows is! List || rows.length > 100000) {
      throw const FormatException('crypto_backup_rows');
    }
    for (final row in rows) {
      if (entry.key == 'crypto_scope_state' && row is Map) {
        if (!isSharedUuid(row['scope_id']) ||
            !['content', 'finance'].contains(row['domain']) ||
            [
              'epoch',
              'scan_generation',
              'access_revision',
              'transport_cursor',
              'projection_cursor',
              'scope_sequence',
              'floor',
            ].any((k) => row[k] is! int || row[k] < 0) ||
            row['floor'] > row['epoch'] ||
            row['projection_cursor'] > row['transport_cursor'] ||
            row['transport_cursor'] > row['scope_sequence']) {
          throw const FormatException('crypto_backup_scope_candidate');
        }
      }
      if (partition == null ||
          row is! Map ||
          row.length != entry.value.length ||
          row.keys.any((k) => !entry.value.contains(k)) ||
          row['partition'] != partition ||
          row.values.any((v) => !_cell(v))) {
        throw const FormatException('crypto_backup_row');
      }
    }
  }
}
