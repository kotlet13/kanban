part of 'portable_backup_repository.dart';

extension PortableBackupTables on PortableBackupRepository {
  Future<List<Map<String, dynamic>>> _exportTableDrafts(
    Map<String, dynamic> tables,
  ) async {
    final partition = database.personalProfile?.partition;
    if (partition == null) return [];
    final scopes = {
      for (final row in tables['scopes'] as List) (row as Map)['id'],
    };
    final prefix = 'table_draft:$partition:';
    final result = <Map<String, dynamic>>[];
    for (final row in await database.rows(
      'SELECT name,value FROM local_meta WHERE substr(name,1,?)=? ORDER BY name',
      [prefix.length, prefix],
    )) {
      final identity = (row['name'] as String)
          .substring(prefix.length)
          .split(':');
      if (identity.length != 2 || !scopes.contains(identity.first)) continue;
      final draft = backupMap(jsonDecode(row['value'] as String));
      result.add({
        'partition': partition,
        'scopeId': identity.first,
        'tableId': identity.last,
        'draft': draft,
      });
    }
    return result;
  }
}
