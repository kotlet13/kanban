import 'dart:convert';
import 'crypto_document_backup_recovery.dart'
    show cryptoDocumentRecoverySourceTable;

import '../collaboration_database.dart';
import 'crypto_capture_keys.dart';
import 'crypto_document_backup_drafts.dart';
import 'crypto_inventory_json.dart';
import 'crypto_json.dart';

/// Exact CURRENT-account installation work only. This is private backup data,
/// not a claim that other offline devices have no unsent operations. Recovery
/// leaves every row in quarantine; ordinary legacy queues are never activated.
class CryptoMigrationLocalIntentSnapshot {
  CryptoMigrationLocalIntentSnapshot({
    required this.database,
    required this.partition,
    required this.capture,
    required this.sourceInventoryRoot,
  });
  final CollaborationDatabase database;
  final String partition, sourceInventoryRoot;
  final CryptoCaptureKeyDescriptor capture;
  static const queueTables = {'outbox', 'finance_outbox', 'commands'};
  static const metadataPrefixes = {
    'task_cost_pair:',
    'document_request:',
    'table_draft:',
    'crypto_business_settled:',
  };

  // Only original ordinary record delivery journals. Migration transport and
  // review/key workflows are excluded by exact typed operation, never prefix.
  static const cryptoReceiptTables = <String, List<String>>{
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
    'crypto_command_keys': [
      'partition',
      'action_key',
      'request_id',
      'payload_hash',
    ],
    'crypto_outbox_records': [
      'partition',
      'scope_id',
      'domain',
      'record_id',
      'expected_revision',
      'request_id',
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
    'crypto_outbox_reconciliations': [
      'partition',
      'old_request_id',
      'new_request_id',
      'reason',
    ],
  };

  /// Frames are only quarantined history. They cannot authorize queue replay.
  static void validateReceiptFrame(
    Map<String, dynamic> frame, {
    required String partition,
    required String serverId,
    required String accountId,
  }) {
    final row = frame['row'];
    final columns = cryptoReceiptTables[frame['table']];
    if (frame.length != 3 ||
        frame['kind'] != 'cryptoReceiptRow' ||
        row is! Map ||
        columns == null ||
        row.length != columns.length ||
        row.keys.any((k) => !columns.contains(k)) ||
        row['partition'] != partition ||
        row.values.any((v) => v != null && v is! String && v is! int)) {
      throw const FormatException('crypto_local_artifact_crypto_receipt');
    }
    if (frame['table'] == 'crypto_outbox') {
      final signed = jsonDecode(row['signed_body'] as String) as Map;
      final body =
          CryptoJson.decode(cryptoBase64(signed['commandBase64'])) as Map;
      if (row['operation'] != 'crypto2.records.batch' ||
          body['operation'] != row['operation'] ||
          body['requestId'] != row['request_id'] ||
          body['accountId'] != accountId ||
          body['serverId'] != serverId) {
        throw const FormatException('crypto_local_artifact_crypto_receipt');
      }
    }
  }

  /// Hold the existing database transaction while the bounded consumer stages
  /// these frames. Publication/wrapping happens after the snapshot transaction.
  Stream<List<int>> frames({required String artifactId}) async* {
    // The complete common context is supplied by the archive AAD, not copied
    // from account profiles or session-token tables.
    var count = 0;
    List<int> frame(Map<String, dynamic> value) {
      final bytes = utf8.encode('${CryptoInventoryJson.canonical(value)}\n');
      if (bytes.length > 32 * 1024 * 1024) {
        throw const FormatException('crypto_local_artifact_frame_size');
      }
      return bytes;
    }

    yield frame({
      'kind': 'localIntentHeader',
      'version': 3,
      'artifactId': artifactId,
      'partition': partition,
      'captureId': capture.captureId,
      'migrationId': capture.migrationId,
      'sourceInventoryRoot': sourceInventoryRoot,
    });
    for (final table in (queueTables.toList()..sort())) {
      var cursor = 0;
      while (true) {
        final rows = await database.rows(
          'SELECT rowid AS snapshot_rowid,* FROM $table WHERE partition=? AND rowid>? ORDER BY rowid LIMIT 8',
          [partition, cursor],
        );
        if (rows.isEmpty) break;
        for (final original in rows) {
          final row = Map<String, dynamic>.from(original)
            ..remove('snapshot_rowid');
          cursor = original['snapshot_rowid'] as int;
          if (table == 'commands') {
            if (!const {
              'inbox.read',
              'inbox.preferences.set',
              'reminders.put',
              'reminders.cancel',
            }.contains(row['operation'])) {
              throw const FormatException(
                'crypto_local_intent_operation_pending',
              );
            }
            final params = jsonDecode(row['params'] as String);
            if (params is! Map) {
              throw const FormatException('crypto_local_intent_shape');
            }
          }
          yield frame({'kind': 'legacyRow', 'table': table, 'row': row});
          count++;
        }
      }
    }
    // Existing Idea drafts and original image bytes belong to this account's
    // exact shared workspaces. They remain quarantined after FILE recovery.
    final workspacePrefix = 'shared:$partition:';
    for (final table in const ['idea_drafts', 'idea_assets']) {
      var cursor = 0;
      while (true) {
        final rows = await database.rows(
          'SELECT rowid AS snapshot_rowid,* FROM $table WHERE substr(workspace,1,?)=? AND rowid>? ORDER BY rowid LIMIT 1',
          [workspacePrefix.length, workspacePrefix, cursor],
        );
        if (rows.isEmpty) break;
        final original = rows.single;
        cursor = original['snapshot_rowid'] as int;
        final row = Map<String, dynamic>.from(original)
          ..remove('snapshot_rowid');
        if (table == 'idea_assets') {
          row['bytes'] = base64Encode((row['bytes'] as List).cast<int>());
        }
        yield frame({'kind': 'ideaDraftRow', 'table': table, 'row': row});
        count++;
      }
    }
    for (final table in cryptoReceiptTables.keys) {
      final columns = cryptoReceiptTables[table]!;
      var cursor = 0;
      final relation = table == 'crypto_outbox_reconciliations'
          ? "r.old_request_id=o.request_id AND EXISTS(SELECT 1 FROM crypto_outbox n WHERE n.partition=r.partition AND n.request_id=r.new_request_id AND n.operation='crypto2.records.batch')"
          : 'r.request_id=o.request_id';
      while (true) {
        final rows = await database.rows(
          "SELECT r.rowid AS snapshot_rowid,${columns.map((c) => 'r.$c').join(',')} FROM $table r WHERE r.partition=? AND r.rowid>? AND EXISTS(SELECT 1 FROM crypto_outbox o WHERE o.partition=r.partition AND o.operation='crypto2.records.batch' AND $relation) ORDER BY r.rowid LIMIT 8",
          [partition, cursor],
        );
        if (rows.isEmpty) break;
        for (final original in rows) {
          cursor = original['snapshot_rowid'] as int;
          final row = Map<String, dynamic>.from(original)
            ..remove('snapshot_rowid');
          yield frame({'kind': 'cryptoReceiptRow', 'table': table, 'row': row});
          count++;
        }
      }
    }
    for (final prefix in (metadataPrefixes.toList()..sort())) {
      final exact = '$prefix$partition:';
      String? after;
      while (true) {
        final rows = await database.rows(
          'SELECT name,value FROM local_meta WHERE substr(name,1,?)=?${after == null ? '' : ' AND name>?'} ORDER BY name LIMIT 8',
          [exact.length, exact, if (after != null) after],
        );
        if (rows.isEmpty) break;
        for (final row in rows) {
          after = row['name'] as String;
          yield frame({'kind': 'legacyRow', 'table': 'local_meta', 'row': row});
          count++;
        }
      }
    }
    // Partition is stored inside old linked-payment intents. Filter it before
    // serializing any bytes; null/accountless and foreign-account work stays out.
    String? after;
    while (true) {
      final rows = await database.rows(
        "SELECT id,data,state FROM linked_payment_intents WHERE json_valid(data)=1 AND json_extract(data,'\$.partition')=?${after == null ? '' : ' AND id>?'} ORDER BY id LIMIT 8",
        [partition, if (after != null) after],
      );
      if (rows.isEmpty) break;
      for (final row in rows) {
        after = row['id'] as String;
        final data = jsonDecode(row['data'] as String);
        if (data is! Map) {
          throw const FormatException('crypto_local_intent_shape');
        }
        if (data['partition'] != partition) continue;
        yield frame({
          'kind': 'legacyRow',
          'table': 'linked_payment_intents',
          'row': row,
        });
        count++;
      }
    }
    // All exact active private rows are retained. Unlike portable export this
    // migration snapshot need not discard acknowledged cipher/source copies;
    // preserving extra own-account work is safer than guessing a lost ACK.
    for (final table in (cryptoDocumentDraftTables.keys.toList()..sort())) {
      if (table == cryptoDocumentRecoverySourceTable) {
        continue;
      } // Virtual DTO only.
      if (table == 'crypto_account_choice_selections' &&
          (await database.rows(
            "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?",
            [table],
          )).isEmpty)
        continue;
      final columns = cryptoDocumentDraftTables[table]!;
      var cursor = 0;
      while (true) {
        final rows = await database.rows(
          'SELECT rowid AS snapshot_rowid,${columns.join(',')} FROM $table WHERE partition=? AND rowid>? ORDER BY rowid LIMIT 8',
          [partition, cursor],
        );
        if (rows.isEmpty) break;
        for (final original in rows) {
          cursor = original['snapshot_rowid'] as int;
          final row = <String, dynamic>{
            for (final key in columns)
              key: original[key] is List<int>
                  ? {'blobBase64': base64Encode(original[key] as List<int>)}
                  : original[key],
          };
          yield frame({
            'kind': 'draftRow',
            'candidateId': null,
            'partition': partition,
            'table': table,
            'row': row,
          });
          count++;
        }
      }
    }
    await for (final value in _restoredDraftFrames(artifactId)) {
      yield frame(value);
      count++;
    }
    yield frame({
      'kind': 'localIntentFooter',
      'version': 3,
      'artifactId': artifactId,
      'intentCount': count,
    });
  }

  /// SQLite performs projection/filtering before any row crosses into Dart.
  /// The scratch lives INSIDE the existing encrypted database, never temp files
  /// or active draft/outbox tables; a process loss cannot activate its rows.
  Stream<Map<String, dynamic>> _restoredDraftFrames(String run) async* {
    if ((await database.rows(
      'SELECT 1 FROM restored_backups WHERE source_partition=? AND json_valid(data)=0 LIMIT 1',
      [partition],
    )).isNotEmpty) {
      throw const FormatException('crypto_local_artifact_candidate_pending');
    }
    final invalid = await database.rows(
      "SELECT 1 FROM restored_backups b WHERE source_partition=? AND json_valid(data)=1 AND json_extract(data,'\$.cryptoPrivateDrafts.partition')=? AND (json_extract(data,'\$.cryptoPrivateDrafts.version') IS NOT 1 OR json_type(data,'\$.cryptoPrivateDrafts.tables') IS NOT 'object' OR (json_type(data,'\$.cryptoPrivateDrafts.restoredCandidates') IS NOT NULL AND json_type(data,'\$.cryptoPrivateDrafts.restoredCandidates')<>'array')) LIMIT 1",
      [partition, partition],
    );
    if (invalid.isNotEmpty) {
      throw const FormatException('crypto_local_artifact_candidate_pending');
    }
    await database.execute(
      'CREATE TABLE IF NOT EXISTS crypto_local_intent_candidates(partition TEXT NOT NULL,run_id TEXT NOT NULL,candidate_id TEXT NOT NULL,table_name TEXT NOT NULL,ordinal INTEGER NOT NULL,value TEXT NOT NULL)',
    );
    await database.execute(
      'DELETE FROM crypto_local_intent_candidates WHERE partition=? AND run_id=?',
      [partition, run],
    );
    try {
      // One native SQL scan of each retained JSON source, no full DTO/cipher
      // array is returned to the application. Foreign nested partitions never
      // enter even this encrypted scratch generation.
      await database.execute(
        "INSERT INTO crypto_local_intent_candidates SELECT b.source_partition,?,b.id,t.key,r.key,r.value FROM restored_backups b,json_each(CASE WHEN json_valid(b.data)=1 THEN b.data ELSE '{}' END,'\$.cryptoPrivateDrafts.tables') t,json_each(t.value) r WHERE b.source_partition=? AND json_valid(b.data)=1 AND json_extract(b.data,'\$.cryptoPrivateDrafts.partition')=?",
        [run, partition, partition],
      );
      await database.execute(
        "INSERT INTO crypto_local_intent_candidates SELECT b.source_partition,?,json_extract(c.value,'\$.backupId'),t.key,r.key,r.value FROM restored_backups b,json_each(CASE WHEN json_valid(b.data)=1 THEN b.data ELSE '{}' END,'\$.cryptoPrivateDrafts.restoredCandidates') c,json_each(c.value,'\$.tables') t,json_each(t.value) r WHERE b.source_partition=? AND json_valid(b.data)=1 AND json_extract(b.data,'\$.cryptoPrivateDrafts.partition')=? AND json_extract(c.value,'\$.partition')=?",
        [run, partition, partition, partition],
      );
      if ((await database.rows(
        'SELECT 1 FROM crypto_local_intent_candidates WHERE partition=? AND run_id=? GROUP BY candidate_id,table_name,ordinal HAVING MIN(value)<>MAX(value) LIMIT 1',
        [partition, run],
      )).isNotEmpty) {
        throw const FormatException('crypto_local_artifact_candidate_conflict');
      }
      String? after;
      while (true) {
        final rows = await database.rows(
          "SELECT candidate_id,table_name,ordinal,MIN(value) AS value,candidate_id||'/'||table_name||'/'||printf('%012d',ordinal) AS sort_key FROM crypto_local_intent_candidates WHERE partition=? AND run_id=?${after == null ? '' : " AND candidate_id||'/'||table_name||'/'||printf('%012d',ordinal)>?"} GROUP BY candidate_id,table_name,ordinal ORDER BY sort_key LIMIT 8",
          [partition, run, if (after != null) after],
        );
        if (rows.isEmpty) break;
        for (final row in rows) {
          after = row['sort_key'] as String;
          final columns = cryptoDocumentDraftTables[row['table_name']];
          final value = jsonDecode(row['value'] as String);
          if (columns == null ||
              value is! Map ||
              value['partition'] != partition ||
              value.length != columns.length ||
              value.keys.any((key) => !columns.contains(key))) {
            throw const FormatException(
              'crypto_local_artifact_candidate_pending',
            );
          }
          yield {
            'kind': 'draftRow',
            'candidateId': row['candidate_id'],
            'partition': partition,
            'table': row['table_name'],
            'row': value,
          };
        }
      }
    } finally {
      await database.execute(
        'DELETE FROM crypto_local_intent_candidates WHERE partition=? AND run_id=?',
        [partition, run],
      );
    }
  }
}
