import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart' show Sha256;
import '../collaboration_database.dart';
import 'account_directory_v2.dart' show cryptoSha256;
import 'crypto_json.dart';
import 'crypto_inventory_json.dart';
import 'crypto_record_address.dart';
import 'crypto_document_backup_recovery.dart';

/// PRIVATE backup-container content. This DTO contains unfinished user files
/// and exact write intents; it must never be exposed as public crypto evidence.
/// Import retains it in quarantine, without installing a deliverable command.
const cryptoDocumentDraftTables = <String, List<String>>{
  cryptoDocumentRecoverySourceTable: cryptoDocumentRecoverySourceColumns,
  'crypto_export_drafts': ['partition', 'scope_id', 'action_id', 'payload'],
  'crypto_account_choice_selections': [
    'partition',
    'action_id',
    'scope_id',
    'selection',
  ],
  'crypto_invitation_deliveries': ['partition', 'request_id', 'token'],
  'crypto_invitation_drafts': ['partition', 'action_id', 'payload', 'token'],
  'crypto_document_jobs': [
    'partition',
    'scope_id',
    'id',
    'record_id',
    'operation_id',
    'kind',
    'descriptor',
    'state',
    'source_hash',
  ],
  'crypto_document_chunks': ['partition', 'id', 'offset', 'cipher'],
  'crypto_document_uploads': [
    'partition',
    'scope_id',
    'id',
    'metadata',
    'received',
    'state',
  ],
  'crypto_document_upload_chunks': ['partition', 'id', 'offset', 'bytes'],
  'crypto_document_actions': [
    'partition',
    'request_id',
    'operation',
    'request_hash',
    'intent',
    'result',
  ],
};
Future<Map<String, dynamic>> exportCryptoDocumentDrafts(
  CollaborationDatabase database,
  String? partition, {
  Map<String, VerifiedCryptoUploadRecovery> verifiedUploadRecoveries = const {},
}) async {
  final published = await cryptoDocumentPublishedBlobIds(database, partition);
  final current = await cryptoDocumentCurrentBlobIds(database, partition);
  final keepJobs = <String>{}, resolvedActions = <String>{};
  if (partition != null) {
    final jobs = await database.rows(
      'SELECT id,record_id,operation_id FROM crypto_document_jobs WHERE partition=?',
      [partition],
    );
    final pending = await database.rows(
      'SELECT request_id FROM crypto_document_actions WHERE partition=? AND result IS NULL',
      [partition],
    );
    final unknownOps = pending.map((r) => r['request_id'] as String).toSet();
    for (final job in jobs) {
      final op = job['operation_id'] as String, id = job['id'] as String;
      if (current.contains(id) ||
          !published.contains(id) ||
          unknownOps.any(
            (request) => op == request || op.startsWith('$request:'),
          )) {
        keepJobs.add(id);
      }
      if (published.contains(id) && !unknownOps.contains(op)) {
        resolvedActions.add(op.split(':').first);
      }
    }
  }
  final recoveries = <String, VerifiedCryptoUploadRecovery>{};
  for (final entry in verifiedUploadRecoveries.entries) {
    if (entry.value.row['partition'] == partition &&
        keepJobs.contains(entry.value.row['job_id']) &&
        await cryptoUploadRecoveryStillMatches(database, entry.value)) {
      recoveries[entry.key] = entry.value;
    }
  }
  final tables = <String, dynamic>{};
  for (final entry in cryptoDocumentDraftTables.entries) {
    final optionalMissing =
        entry.key == 'crypto_account_choice_selections' &&
        (await database.rows(
          "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?",
          [entry.key],
        )).isEmpty;
    var rows = optionalMissing
        ? <Map<String, Object?>>[]
        : entry.key == cryptoDocumentRecoverySourceTable
        ? recoveries.values
              .map((proof) => Map<String, Object?>.from(proof.row))
              .toList()
        : partition == null
        ? <Map<String, Object?>>[]
        : await database.rows(
            'SELECT ${entry.value.join(',')} FROM ${entry.key} WHERE partition=? ORDER BY rowid',
            [partition],
          );
    if (entry.key == 'crypto_document_jobs' ||
        entry.key == 'crypto_document_chunks') {
      rows = rows.where((r) => keepJobs.contains(r['id'])).toList();
    }
    if (entry.key == 'crypto_document_upload_chunks') {
      rows = rows.where((row) => !recoveries.containsKey(row['id'])).toList();
    }
    if (entry.key == 'crypto_document_actions') {
      rows = rows
          .where(
            (r) =>
                r['result'] == null ||
                !resolvedActions.contains(r['request_id']),
          )
          .toList();
    }
    tables[entry.key] = [
      for (final row in rows)
        {
          for (final cell in row.entries)
            cell.key: cell.value is List<int>
                ? {'blobBase64': base64Encode(cell.value as List<int>)}
                : cell.value,
        },
    ];
  }
  final retained = <String, Map<String, dynamic>>{};
  void keep(String id, Object? source) {
    if (source is! Map ||
        source['tables'] is! Map ||
        source.containsKey('restoredCandidates'))
      throw const FormatException('crypto_private_drafts_candidate');
    final value = <String, dynamic>{
      'backupId': id,
      'partition': source['partition'],
      'tables': source['tables'],
    };
    final prior = retained[id];
    if (prior != null &&
        CryptoInventoryJson.canonical(prior) !=
            CryptoInventoryJson.canonical(value))
      throw const FormatException('crypto_private_drafts_candidate_conflict');
    retained[id] = value;
  }

  for (final restored
      in partition == null
          ? <Map<String, Object?>>[]
          : await database.rows(
              'SELECT id,data FROM restored_backups WHERE source_partition=? ORDER BY id',
              [partition],
            )) {
    final data = jsonDecode(restored['data'] as String) as Map;
    final drafts = data['cryptoPrivateDrafts'];
    if (drafts == null)
      continue; // Retained encrypted originals may require reimport.
    if (drafts is! Map)
      throw const FormatException('crypto_private_drafts_candidate');
    if (drafts['partition'] != partition) continue;
    keep(restored['id'] as String, {
      'partition': drafts['partition'],
      'tables': drafts['tables'],
    });
    for (final nested in drafts['restoredCandidates'] as List? ?? const []) {
      if (nested is! Map || nested.length != 3 || nested['backupId'] is! String)
        throw const FormatException('crypto_private_drafts_candidate');
      if (nested['partition'] != partition) continue;
      keep(nested['backupId'], {
        'partition': nested['partition'],
        'tables': nested['tables'],
      });
    }
  }
  final result = {
    'version': 1,
    'partition': partition,
    'tables': tables,
    if (retained.isNotEmpty)
      'restoredCandidates': retained.values.toList()
        ..sort(
          (a, b) =>
              (a['backupId'] as String).compareTo(b['backupId'] as String),
        ),
  };
  validateCryptoDocumentDrafts(result, partition);
  return result;
}

void validateCryptoDocumentDrafts(Object? value, String? partition) =>
    _validateCryptoDrafts(value, partition, {'bytes': 0, 'rows': 0});
void _validateCryptoDrafts(
  Object? value,
  String? partition,
  Map<String, int> budget,
) {
  if (value is! Map ||
      !{3, 4}.contains(value.length) ||
      value.keys.any(
        (k) => !{
          'version',
          'partition',
          'tables',
          'restoredCandidates',
        }.contains(k),
      ) ||
      value['version'] != 1 ||
      value['partition'] != partition ||
      value['tables'] is! Map) {
    throw const FormatException('crypto_private_drafts_shape');
  }
  final tables = value['tables'] as Map;
  if (tables.length < cryptoDocumentDraftTables.length - 3 ||
      tables.length > cryptoDocumentDraftTables.length ||
      tables.keys.any((k) => !cryptoDocumentDraftTables.containsKey(k))) {
    throw const FormatException('crypto_private_drafts_tables');
  }

  for (final entry in cryptoDocumentDraftTables.entries) {
    final rows =
        tables[entry.key] ??
        (const {
              'crypto_export_drafts',
              'crypto_account_choice_selections',
              cryptoDocumentRecoverySourceTable,
            }.contains(entry.key)
            ? const []
            : null);
    if (rows is! List || rows.length > 100000) {
      throw const FormatException('crypto_private_drafts_rows');
    }
    final keys = <String>{};
    for (final row in rows) {
      if (partition == null ||
          row is! Map ||
          row.length != entry.value.length ||
          row.keys.any((k) => !entry.value.contains(k)) ||
          row['partition'] != partition) {
        throw const FormatException('crypto_private_drafts_partition');
      }
      budget['rows'] = budget['rows']! + 1;
      if (budget['rows']! > 150000) {
        throw const FormatException('crypto_private_drafts_rows');
      }
      for (final cell in row.entries) {
        final v = cell.value;
        if (v == null) {
          if (!['result', 'token'].contains(cell.key)) {
            throw const FormatException('crypto_private_drafts_null');
          }
          continue;
        }
        if (v is int) {
          if (v < 0 || v > 23068672) {
            throw const FormatException('crypto_private_drafts_integer');
          }
          continue;
        }
        if (v is String) {
          if (utf8.encode(v).length > 8 * 1024 * 1024) {
            throw const FormatException('crypto_private_drafts_text');
          }
          budget['bytes'] = budget['bytes']! + utf8.encode(v).length;
          continue;
        }
        if (v is! Map ||
            v.length != 1 ||
            v['blobBase64'] is! String ||
            !['cipher', 'bytes'].contains(cell.key)) {
          throw const FormatException('crypto_private_drafts_blob');
        }
        final bytes = base64Decode(v['blobBase64'] as String);
        if (base64Encode(bytes) != v['blobBase64'] || bytes.length > 262144) {
          throw const FormatException('crypto_private_drafts_blob');
        }
        budget['bytes'] = budget['bytes']! + bytes.length;
      }
      if (budget['bytes']! > 64 * 1024 * 1024) {
        throw const FormatException('crypto_private_drafts_size');
      }
      final id = row['id'] ?? row['request_id'] ?? row['action_id'];
      if ((!isCryptoCanonicalUuid(id) &&
              !(entry.key == 'crypto_invitation_drafts' &&
                  id is String &&
                  id.startsWith('accept:') &&
                  isCryptoCanonicalUuid(id.substring(7)))) ||
          row.containsKey('scope_id') &&
              !isCryptoCanonicalUuid(row['scope_id']) ||
          row.containsKey('record_id') &&
              !isCryptoCanonicalUuid(row['record_id'])) {
        throw const FormatException('crypto_private_drafts_id');
      }
      final identity = '$id:${row['offset'] ?? ''}';
      if (!keys.add(identity)) {
        throw const FormatException('crypto_private_drafts_duplicate');
      }
      if (row.containsKey('source_hash') &&
          !(row['source_hash'] is String &&
              RegExp(r'^[a-f0-9]{64}$').hasMatch(row['source_hash']))) {
        throw const FormatException('crypto_private_drafts_hash');
      }
      if (entry.key.startsWith('crypto_invitation_') &&
          row['token'] != null &&
          (row['token'] is! String ||
              !RegExp(r'^fhi4_[a-f0-9]{64}$').hasMatch(row['token']))) {
        throw const FormatException('crypto_private_invitation_token');
      }
      for (final jsonField in [
        'metadata',
        'descriptor',
        'intent',
        'result',
        'payload',
      ]) {
        if (row[jsonField] != null) {
          final decoded = jsonDecode(row[jsonField] as String);
          if (decoded is! Map) {
            throw const FormatException('crypto_private_drafts_json');
          }
        }
      }
    }
  }
  for (final ref
      in tables[cryptoDocumentRecoverySourceTable] as List? ?? const []) {
    final uploads = (tables['crypto_document_uploads'] as List)
        .where((r) => r['id'] == ref['id'])
        .toList();
    final jobs = (tables['crypto_document_jobs'] as List)
        .where((r) => r['id'] == ref['job_id'])
        .toList();
    if (uploads.length != 1 ||
        jobs.length != 1 ||
        !isCryptoCanonicalUuid(ref['job_id']) ||
        ref['size'] is! int ||
        ref['size'] < 0 ||
        ref['size'] > 20 * 1024 * 1024 ||
        ref['sha256'] is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(ref['sha256']) ||
        uploads.single['scope_id'] != ref['scope_id'] ||
        uploads.single['received'] != ref['size'] ||
        jobs.single['scope_id'] != ref['scope_id'] ||
        jobs.single['record_id'] != ref['id'] ||
        jobs.single['operation_id'] != ref['id'] ||
        jobs.single['kind'] != 'attachment' ||
        jobs.single['source_hash'] != ref['source_hash'] ||
        (tables['crypto_document_upload_chunks'] as List).any(
          (r) => r['id'] == ref['id'],
        )) {
      throw const FormatException('crypto_private_drafts_recovery_source');
    }
    final metadata = jsonDecode(uploads.single['metadata'] as String) as Map;
    if (metadata['size'] != ref['size'] ||
        metadata['sha256'] != ref['sha256']) {
      throw const FormatException('crypto_private_drafts_recovery_source');
    }
  }
  final candidates = value['restoredCandidates'];
  if (candidates != null) {
    if (candidates is! List || candidates.length > 100)
      throw const FormatException('crypto_private_drafts_candidates');
    String last = '';
    for (final candidate in candidates) {
      if (candidate is! Map ||
          candidate.length != 3 ||
          !candidate.keys.toSet().containsAll({
            'backupId',
            'partition',
            'tables',
          }) ||
          !isCryptoCanonicalUuid(candidate['backupId']) ||
          (candidate['backupId'] as String).compareTo(last) <= 0 ||
          candidate['partition'] != null && candidate['partition'] is! String) {
        throw const FormatException('crypto_private_drafts_candidate');
      }
      last = candidate['backupId'];
      _validateCryptoDrafts(
        {
          'version': 1,
          'partition': candidate['partition'],
          'tables': candidate['tables'],
        },
        candidate['partition'] as String?,
        budget,
      );
    }
  }
}

/// Decodes only a validated quarantined DTO. The caller must reconcile its
/// account identity and receipts before considering any explicit resume import.
Uint8List decodeCryptoDocumentDraftBlob(Object value) =>
    Uint8List.fromList(base64Decode((value as Map)['blobBase64'] as String));

/// Object IDs whose exact own record ACK and verified projection are retained,
/// with a complete locally owned ciphertext copy. Used only to deduplicate
/// applied chunk-command bodies; it never drops pending or unknown outcomes.
Future<Set<String>> cryptoDocumentPublishedBlobIds(
  CollaborationDatabase database,
  String? partition,
) async {
  if (partition == null) return {};
  final result = <String>{};
  final rows = await database.rows(
    "SELECT o.signed_body,o.response,o.request_hash,o.request_id,b.record_id,b.operation_id FROM crypto_outbox o JOIN crypto_business_requests b ON b.partition=o.partition AND b.request_id=o.request_id WHERE o.partition=? AND o.operation='crypto2.records.batch' AND o.state='applied'",
    [partition],
  );
  for (final row in rows) {
    try {
      final proof =
              jsonDecode(row['signed_body'] as String) as Map<String, dynamic>,
          receipt = jsonDecode(row['response'] as String) as Map;
      final commandBytes = base64Decode(proof['commandBase64'] as String);
      final command = jsonDecode(utf8.decode(commandBytes)) as Map;
      if (await cryptoSha256(commandBytes) != row['request_hash'] ||
          receipt['status'] != 200 ||
          receipt['requestId'] != row['request_id'] ||
          receipt['requestHash'] != row['request_hash'] ||
          base64Encode(CryptoJson.encode(receipt['authorization'])) !=
              base64Encode(CryptoJson.encode(proof))) {
        continue;
      }
      final records = command['payload']['records'] as List;
      for (final signed in records) {
        final body =
            jsonDecode(
                  utf8.decode(base64Decode(signed['commandBase64'] as String)),
                )
                as Map;
        if (body['id'] !=
                cryptoWireRecordId(
                  body['serverId'],
                  body['scopeId'],
                  body['type'],
                  row['record_id'] as String,
                  domain: body['domain'],
                ) ||
            body['operationId'] != row['operation_id']) {
          continue;
        }
        final verified = await database.rows(
          "SELECT wire FROM crypto_received WHERE partition=? AND scope_id=? AND domain=? AND record_id=? AND revision=? AND verdict='verified'",
          [
            partition,
            body['scopeId'],
            body['domain'],
            body['id'],
            (body['expectedRevision'] as int) + 1,
          ],
        );
        if (verified.length != 1 ||
            base64Encode(
                  CryptoJson.encode(
                    (jsonDecode(verified.single['wire'] as String)
                        as Map)['authorization']['recordProof'],
                  ),
                ) !=
                base64Encode(CryptoJson.encode(signed))) {
          continue;
        }
        for (final id in body['metadata']['blobIds'] as List) {
          final jobs = await database.rows(
            "SELECT descriptor FROM crypto_document_jobs WHERE partition=? AND scope_id=? AND id=? AND record_id=? AND state='complete'",
            [
              partition,
              body['scopeId'],
              id,
              (body['metadata'] as Map)['identity']?['canonicalId'] ??
                  body['id'],
            ],
          );
          if (jobs.length != 1) continue;
          final descriptor =
              jsonDecode(jobs.single['descriptor'] as String) as Map;
          if (descriptor['domain'] != body['domain']) continue;
          final chunks = await database.rows(
            'SELECT offset,cipher FROM crypto_document_chunks WHERE partition=? AND id=? ORDER BY offset',
            [partition, id],
          );
          var total = 0, valid = true;
          final digest = Sha256().newHashSink();
          for (final chunk in chunks) {
            if (chunk['offset'] != total) {
              valid = false;
              break;
            }
            final bytes = (chunk['cipher'] as List).cast<int>();
            digest.add(bytes);
            total += bytes.length;
          }
          digest.close();
          final hash = (await digest.hash()).bytes
              .map((b) => b.toRadixString(16).padLeft(2, '0'))
              .join();
          if (valid &&
              total == descriptor['cipherSize'] &&
              hash == descriptor['cipherSha256']) {
            result.add(id as String);
          }
        }
      }
    } on FormatException {
      continue;
    } on TypeError {
      continue;
    }
  }
  return result;
}

Future<Set<String>> cryptoDocumentCurrentBlobIds(
  CollaborationDatabase database,
  String? partition,
) async {
  if (partition == null) return {};
  final result = <String>{};
  final rows = await database.rows(
    "SELECT b.record_proof_hash,r.wire FROM crypto_business_records b JOIN crypto_received r ON r.partition=b.partition AND r.scope_id=b.scope_id AND r.domain=b.domain AND r.record_id=b.id AND r.revision=b.crypto_revision WHERE b.partition=? AND b.deleted=0 AND r.verdict='verified'",
    [partition],
  );
  for (final row in rows) {
    try {
      final wire = jsonDecode(row['wire'] as String) as Map,
          proof = wire['authorization']['recordProof'] as Map;
      if (await cryptoSha256(CryptoJson.encode(proof)) !=
          row['record_proof_hash']) {
        continue;
      }
      final record =
          CryptoJson.decode(base64Decode(proof['commandBase64'] as String))
              as Map;
      for (final id in record['metadata']['blobIds'] as List) {
        if (id is String) result.add(id);
      }
    } on FormatException {
      continue;
    } on TypeError {
      continue;
    }
  }
  return result;
}
