import 'dart:convert';

import '../collaboration_database.dart';
import 'crypto_business_router.dart';
import 'crypto_capture_keys.dart';
import 'crypto_finance_topology.dart';
import 'crypto_inventory_json.dart';
import 'crypto_migration_cold_controls.dart';
import 'crypto_sync_repository.dart';

/// Preparatory observation committed by the private source archive and checked
/// again by FILE StructureControl and final frozen-source installation.
abstract final class CryptoMigrationTopology {
  static String name(String partition, String captureId, String scopeId) =>
      'migration_scope_topology:$partition:$captureId:$scopeId';

  static Future<Map<String, dynamic>> load(
    CollaborationDatabase database,
    String partition,
    String captureId,
    String scopeId,
    String serverId,
  ) async {
    final rows = await database.rows(
      'SELECT value FROM local_meta WHERE name=?',
      [name(partition, captureId, scopeId)],
    );
    if (rows.length != 1) {
      throw const CryptoAuthorityPending('crypto_finance_topology_pending');
    }
    final value = Map<String, dynamic>.from(
      jsonDecode(rows.single['value'] as String),
    );
    await CryptoFinanceTopology.validate(
      value,
      serverId: serverId,
      scopeId: scopeId,
    );
    return value;
  }

  static Future<void> stageAll(
    CryptoBusinessSession runtime,
    CryptoCaptureKeyDescriptor capture,
    String root,
  ) async {
    var after = '';
    while (true) {
      final rows = await runtime.db.rows(
        "SELECT binding_id,context,typed_row FROM crypto_capture_sources WHERE partition=? AND capture_id=? AND binding_id>? AND json_extract(context,'\$.sourceTable')='familyhub_scopes' ORDER BY binding_id LIMIT 1",
        [runtime.partition, capture.captureId, after],
      );
      if (rows.isEmpty) return;
      final row = rows.single;
      after = row['binding_id'] as String;
      final context = Map<String, dynamic>.from(
        jsonDecode(row['context'] as String),
      );
      final cells = CryptoMigrationColdEvidence.cells(
        Map<String, dynamic>.from(jsonDecode(row['typed_row'] as String)),
      );
      if (!const ['household', 'organization'].contains(cells['kind'])) {
        continue;
      }
      final scope = context['scopeId'] as String;
      final key = name(runtime.partition, capture.captureId, scope);
      final existing = await runtime.db.rows(
        'SELECT value FROM local_meta WHERE name=?',
        [key],
      );
      if (existing.isNotEmpty) {
        await load(
          runtime.db,
          runtime.partition,
          capture.captureId,
          scope,
          context['serverId'],
        );
        continue;
      }
      final reply = await runtime.account.directory
          .call('crypto2.migration.capture.topology', {
            'migrationId': capture.migrationId,
            'captureId': capture.captureId,
            'sourceInventoryRoot': root,
            'bindingId': after,
          });
      if (reply.length != 4 ||
          reply['captureVersion'] != 3 ||
          reply['bindingId'] != after ||
          reply['scopeId'] != scope ||
          reply['topology'] is! Map) {
        throw const FormatException('crypto_finance_topology_context');
      }
      final value = Map<String, dynamic>.from(reply['topology']);
      await CryptoFinanceTopology.validate(
        value,
        serverId: context['serverId'],
        scopeId: scope,
      );
      await runtime.db.execute(
        'INSERT INTO local_meta(name,value) VALUES(?,?)',
        [key, CryptoInventoryJson.canonical(value)],
      );
    }
  }
}
