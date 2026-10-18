import 'account_directory_v2.dart' show cryptoSha256;
import 'dart:convert';
import 'dart:typed_data';
import '../../domain/idea_models.dart';
import '../collaboration_database.dart';
import '../idea_repository.dart' show verifyIdeaAsset;

/// These are user drafts, not authenticated current business projections. The
/// existing draft chooser opens them for explicit review/save; no old queue or
/// immutable request is activated, and the original quarantine stays intact.
abstract final class CryptoMigrationIdeaDraftRecovery {
  static Future<List<Map<String, dynamic>>> rows(
    CollaborationDatabase db,
    String workspace,
    String table, {
    String? id,
  }) async {
    if (!workspace.startsWith('shared:')) return [];
    final exists = await db.rows(
      "SELECT 1 FROM sqlite_master WHERE type='table' AND name='cold_local_intents'",
    );
    if (exists.isEmpty) return [];
    final dismissed = await db.rows(
      'SELECT name FROM local_meta WHERE name=?',
      ['migration_idea_draft_dismissed:$workspace:$id'],
    );
    if (id != null && dismissed.isNotEmpty) return [];
    final result = <Map<String, dynamic>>[];
    var after = '';
    var ordinal = -1;
    while (true) {
      final page = await db.rows(
        "SELECT artifact_id,ordinal,frame FROM cold_local_intents WHERE (artifact_id>? OR (artifact_id=? AND ordinal>?)) AND json_extract(frame,'\$.kind')='ideaDraftRow' AND json_extract(frame,'\$.table')=? AND json_extract(frame,'\$.row.workspace')=? ${id == null ? '' : "AND json_extract(frame,'\$.row.${table == 'idea_drafts' ? 'id' : 'sha256'}')=?"} ORDER BY artifact_id,ordinal LIMIT 1",
        [after, after, ordinal, table, workspace, if (id != null) id],
      );
      if (page.isEmpty) break;
      for (final value in page) {
        after = value['artifact_id'] as String;
        ordinal = value['ordinal'] as int;
        final row = Map<String, dynamic>.from(
          (jsonDecode(value['frame'] as String) as Map)['row'] as Map,
        );
        if (id == null || row[table == 'idea_drafts' ? 'id' : 'sha256'] == id) {
          result.add(row);
        }
      }
    }
    if (id != null && result.length > 1) {
      final byHash = <String, Map<String, dynamic>>{};
      for (final row in result) {
        byHash[await cryptoSha256(utf8.encode(jsonEncode(row)))] = row;
      }
      if (byHash.length > 1) {
        if(table!='idea_drafts')throw const FormatException('crypto_recovered_idea_asset_conflict');
        final selection = await db.rows(
          'SELECT value FROM local_meta WHERE name=?',
          ['migration_idea_draft_choice:$workspace:$id'],
        );
        final chosen = selection.isEmpty
            ? null
            : byHash[selection.single['value']];
        if (chosen != null) return [chosen];
        final hashes = byHash.keys.toList()..sort();
        throw CryptoRecoveredIdeaDraftConflict(
          id,
          [for (final h in hashes) byHash[h]!],
          (index) async {
            if (index < 0 || index >= hashes.length) {
              throw RangeError.index(index, hashes);
            }
            await db.execute('INSERT OR REPLACE INTO local_meta VALUES(?,?)', [
              'migration_idea_draft_choice:$workspace:$id',
              hashes[index],
            ]);
          },
        );
      }
    }
    final unique = <String, Map<String, dynamic>>{};
    for (final row in result) {
      final key = row[table == 'idea_drafts' ? 'id' : 'sha256'] as String;
      if (table == 'idea_drafts') {
        final hidden = await db.rows('SELECT 1 FROM local_meta WHERE name=?', [
          'migration_idea_draft_dismissed:$workspace:$key',
        ]);
        if (hidden.isNotEmpty) continue;
      }
      final prior = unique[key];
      if (prior != null && jsonEncode(prior) != jsonEncode(row)) {
        if (id != null) {
          throw const FormatException('crypto_recovered_idea_draft_conflict');
        }
        unique[key] = {...prior, 'recoveryConflict': true};
        continue;
      }
      unique[key] = row;
    }
    return unique.values.toList();
  }

  static Future<String?> tableDraft(
    CollaborationDatabase db,
    String partition,
    String scope,
    String id,
  ) async {
    final name = 'table_draft:$partition:$scope:$id';
    final dismissed = await db.rows(
      'SELECT name FROM local_meta WHERE name=?',
      ['migration_table_draft_dismissed:$partition:$scope:$id'],
    );
    if (dismissed.isNotEmpty) return null;
    final exists = await db.rows(
      "SELECT 1 FROM sqlite_master WHERE type='table' AND name='cold_local_intents'",
    );
    if (exists.isEmpty) return null;
    final candidates = await db.rows(
      "SELECT DISTINCT json_extract(frame,'\$.row.value') AS value FROM cold_local_intents WHERE json_extract(frame,'\$.kind')='legacyRow' AND json_extract(frame,'\$.table')='local_meta' AND json_extract(frame,'\$.row.name')=? LIMIT 2",
      [name],
    );
    if (candidates.length > 1) {
      throw const FormatException('crypto_recovered_table_draft_conflict');
    }
    return candidates.isEmpty ? null : candidates.single['value'] as String;
  }

  static Future<Uint8List?> asset(
    CollaborationDatabase db,
    String workspace,
    IdeaAsset asset,
  ) async {
    final candidates = await rows(
      db,
      workspace,
      'idea_assets',
      id: asset.sha256,
    );
    if (candidates.isEmpty) return null;
    final original = IdeaAsset.fromJson(
      Map<String, dynamic>.from(
        jsonDecode(candidates.single['metadata'] as String) as Map,
      ),
    );
    if (jsonEncode(original.toJson()) != jsonEncode(asset.toJson())) {
      throw const FormatException('crypto_recovered_idea_asset');
    }
    final bytes = base64Decode(candidates.single['bytes'] as String);
    try {
      await verifyIdeaAsset(asset, bytes);
      return bytes;
    } catch (_) {
      bytes.fillRange(0, bytes.length, 0);
      rethrow;
    }
  }
}

class CryptoRecoveredIdeaDraftConflict implements Exception {
  const CryptoRecoveredIdeaDraftConflict(this.id, this.versions, this.select);
  final String id;
  final List<Map<String, dynamic>> versions;
  final Future<void> Function(int index) select;
}
