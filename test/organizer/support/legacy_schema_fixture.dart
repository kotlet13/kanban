import 'package:kanban/organizer/data/collaboration_database.dart';

/// Fixtures that down-convert a current synthetic schema must remove every
/// table introduced in11 before assigning an older user_version. This is not
/// application migration/cleanup code and is never used on a user database.
Future<void> removeSyntheticCryptoSchema(CollaborationDatabase database) async {
  final rows = await database.rows(
    "SELECT name FROM sqlite_schema WHERE type='table' AND name GLOB 'crypto_*'",
  );
  for (final row in rows) {
    final name = row['name'] as String;
    if (!RegExp(r'^crypto_[a-z_]+$').hasMatch(name))
      throw StateError('Unexpected synthetic table');
    await database.execute('DROP TABLE "$name"');
  }
}
