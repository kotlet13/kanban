import 'dart:convert';

import 'collaboration_database.dart';

/// A dispatched create request remains immutable until its outcome is recovered.
/// Keeping the account partition and request IDs also survives closing the form.
class SpaceCreationDraftStore {
  SpaceCreationDraftStore(this.database);
  final CollaborationDatabase database;
  static const _key = 'space_flow_creation';
  Future<Map<String, dynamic>?> read() async {
    final rows = await database.rows(
      'SELECT value FROM local_meta WHERE name=?',
      [_key],
    );
    return rows.isEmpty
        ? null
        : jsonDecode(rows.single['value'] as String) as Map<String, dynamic>;
  }

  Future<void> save(
    Map<String, dynamic> draft,
  ) => database.transaction(() async {
    final previous = await read();
    if (previous != null && previous['requestId'] != draft['requestId']) {
      throw StateError('An unresolved space creation already exists');
    }
    await database.execute(
      'INSERT INTO local_meta(name,value) VALUES(?,?) ON CONFLICT(name) DO UPDATE SET value=excluded.value',
      [_key, jsonEncode(draft)],
    );
  });
  Future<void> complete(String requestId) => database.transaction(() async {
    if ((await read())?['requestId'] == requestId) {
      await database.execute('DELETE FROM local_meta WHERE name=?', [_key]);
    }
  });
}
