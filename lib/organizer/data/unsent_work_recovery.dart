import 'dart:convert';
import 'dart:typed_data';

import '../domain/idea_models.dart';
import 'idea_repository.dart' show verifyIdeaAsset;

/// A file-only review of explicit local candidates. It has no repository,
/// session, ACL, importer, outbox mutation or remote delivery capability.
class UnsentWorkRecovery {
  UnsentWorkRecovery._(this.candidates, this.assets);
  final List<UnsentWorkCandidate> candidates;
  final Map<String, Uint8List> assets;

  static Future<UnsentWorkRecovery> decode(String text) async {
    if (utf8.encode(text).length > 180 * 1024 * 1024) {
      throw const FormatException('Recovery file too large');
    }
    final doc = jsonDecode(text) as Map<String, dynamic>;
    if (doc['format'] != 'vsakdan-unsent-work' ||
        ![1, 2].contains(doc['schemaVersion'])) {
      throw const FormatException('Unsupported recovery file');
    }
    final entries = <UnsentWorkCandidate>[];
    final required = <String, IdeaAsset>{};
    void add(String workspace, String type, Map<String, dynamic> payload) {
      final board = type == 'idea' ? IdeaBoard.fromJson(payload) : null;
      if (board != null) {
        for (final asset in board.assets) {
          required['$workspace:${asset.sha256}'] = asset;
        }
      }
      entries.add(UnsentWorkCandidate(workspace, type, payload, board));
    }

    final account = doc['account'] as Map;
    final partition =
        '${Uri.encodeComponent(account['serverUrl'] as String)}:${account['serverId']}:${account['accountId']}';
    for (final table in ['operations', 'financeOperations']) {
      for (final raw in doc[table] as List? ?? []) {
        final row = raw as Map;
        final operation = row['operation'] as Map;
        final payload = operation['payload'];
        if (payload == null) continue;
        add(
          'shared:$partition:${row['scopeId']}',
          operation['type'] as String,
          Map<String, dynamic>.from(payload as Map),
        );
      }
    }
    for (final raw in doc['ideaDrafts'] as List? ?? []) {
      final row = raw as Map;
      final workspace = row['workspace'] as String;
      if (!workspace.startsWith('shared:$partition:')) {
        throw const FormatException('Recovery identity mismatch');
      }
      add(workspace, 'idea', Map<String, dynamic>.from(row['payload'] as Map));
    }
    final media = <String, Uint8List>{};
    var total = 0;
    for (final raw in doc['ideaAssets'] as List? ?? []) {
      final row = raw as Map;
      final metadata = IdeaAsset.fromJson(
        Map<String, dynamic>.from(row['metadata'] as Map),
      );
      final key = '${row['workspace']}:${metadata.sha256}';
      if (!required.containsKey(key) ||
          media.containsKey(key) ||
          jsonEncode(required[key]!.toJson()) !=
              jsonEncode(metadata.toJson())) {
        throw const FormatException('Unexpected recovery image');
      }
      final bytes = base64Decode(row['bytes'] as String);
      total += bytes.length;
      if (total > 128 * 1024 * 1024) {
        throw const FormatException('Recovery images too large');
      }
      await verifyIdeaAsset(metadata, bytes);
      media[key] = bytes;
    }
    if (required.keys.any((key) => !media.containsKey(key))) {
      throw const FormatException('Incomplete recovery images');
    }
    return UnsentWorkRecovery._(
      List.unmodifiable(entries),
      Map.unmodifiable(media),
    );
  }
}

class UnsentWorkCandidate {
  const UnsentWorkCandidate(
    this.workspace,
    this.type,
    this.payload,
    this.board,
  );
  final String workspace, type;
  final Map<String, dynamic> payload;
  final IdeaBoard? board;
  String get title => (payload['title'] ?? payload['name'] ?? type).toString();
}
