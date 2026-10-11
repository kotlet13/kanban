part of 'portable_backup_repository.dart';

/// Count saved content, not transport maps, revisions or copies of a payment.
BackupContentSummary _backupContentSummary(Map<String, dynamic> doc) {
  final scopes = backupRows(doc, 'scopes');
  // The default Personal snapshot is also present in localSpaces in format 4.
  // Published spaces retain their original device snapshot; count it separately
  // from current downloaded records, rather than as another active local space.
  final localSpaces = (doc['localSpaces'] as List? ?? const [])
      .map(backupMap)
      .where((r) => backupMap(r['space'])['id'] != 'local')
      .toList();
  final localCounts = <String, int>{}, retained = <String, int>{};
  var localSpaceCount = 0, retainedSpaceCount = 0;
  void add(Map<String, int> target, Map<String, int> counts) {
    for (final entry in counts.entries) {
      target.update(
        entry.key,
        (n) => n + entry.value,
        ifAbsent: () => entry.value,
      );
    }
  }

  for (final raw in localSpaces) {
    final linked = LocalSpace.fromJson(backupMap(raw['space'])).binding != null;
    if (linked) {
      retainedSpaceCount++;
    } else {
      localSpaceCount++;
    }
    add(
      linked ? retained : localCounts,
      personalCounts(OrganizerBackupCodec.decode(raw['snapshot'] as String)),
    );
  }
  for (final raw in doc['gardenSpaceLinks'] as List? ?? const []) {
    final space = localSpaces.firstWhere(
      (r) => backupMap(r['space'])['id'] == raw['space_id'],
    );
    final target = backupMap(space['space'])['binding'] == null
        ? localCounts
        : retained;
    target.update('gardens', (n) => n + 1, ifAbsent: () => 1);
  }
  final downloaded = <String, int>{};
  var deleted = 0;
  for (final table in ['records', 'finance_records']) {
    for (final row in backupRows(doc, table)) {
      if (row['deleted'] == 1) {
        deleted++;
        continue;
      }
      final type = row['type'] as String;
      downloaded.update(type, (n) => n + 1, ifAbsent: () => 1);
    }
  }
  final privateReminders =
      (backupMap(doc['privateData'])['reminders'] as List).length;
  if (privateReminders > 0) downloaded['reminders'] = privateReminders;
  for (final table in ['inbox', 'scheduled_reminders']) {
    final count = backupRows(doc, table).length;
    if (count > 0) downloaded[table] = count;
  }
  final linked = doc['linkedPayments'] as Map?;
  final scopeIds = scopes.map((r) => r['id'] as String).toSet();
  final intents = (linked?['intents'] as List? ?? const []).cast<Map>();
  final unresolved = intents.where(
    (r) => const [
      'pending',
      'waiting_source_publication',
      'quarantine',
    ].contains(r['state']),
  );
  return BackupContentSummary(
    localSpaceCount: localSpaceCount,
    retainedLocalSpaceCount: retainedSpaceCount,
    retainedLocalCounts: retained,
    personalScopeCount: scopes
        .where(
          (r) =>
              SharedScope.fromJson(
                backupMap(jsonDecode(r['data'] as String)),
              ).kind ==
              SharedScopeKind.personal,
        )
        .length,
    localCounts: localCounts,
    downloadedCounts: downloaded,
    linkedPaymentCounts: {
      for (final kind in ['events', 'projections', 'cashMovements'])
        kind: (linked?[kind] as List? ?? const []).length,
    },
    linkedPendingCount: unresolved.length,
    blockedCount:
        [
          ...backupRows(doc, 'outbox'),
          ...backupRows(doc, 'finance_outbox'),
          ...backupRows(doc, 'commands'),
        ].where((r) => r['state'] != 'pending').length +
        unresolved.where((r) => r['state'] == 'quarantine').length,
    deletedRecordCount: deleted,
    standaloneFinanceLimited:
        (downloaded['financeTransfer'] ?? 0) > 0 ||
        ['events', 'projections', 'cashMovements'].any(
          (kind) => (linked?[kind] as List? ?? const []).any(
            (raw) => scopeIds.any(
              (id) => (raw['space_key'] as String).endsWith(':$id'),
            ),
          ),
        ) ||
        intents.any(
          (row) => scopeIds.contains(
            PaymentSourceRef.fromJson(
              backupMap(backupMap(jsonDecode(row['data'] as String))['source']),
            ).space.id,
          ),
        ),
  );
}
