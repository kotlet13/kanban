class PrivateSyncState {
  const PrivateSyncState({
    this.available = false,
    this.enabled = false,
    this.paused = false,
    this.scopeId,
    this.partition,
    this.pendingCount = 0,
    this.localPendingCount = 0,
  });
  final bool available, enabled, paused;
  final String? scopeId, partition;
  final int pendingCount, localPendingCount;
}

class PrivateSyncPreview {
  PrivateSyncPreview({
    required this.revision,
    required Map<String, int> recordCounts,
    required this.existingRemoteCount,
    Iterable<String> issues = const [],
  }) : recordCounts = Map.unmodifiable(recordCounts),
       issues = List.unmodifiable(issues);
  final int revision, existingRemoteCount;
  final Map<String, int> recordCounts;
  final List<String> issues;
  bool get canEnable => issues.isEmpty;
}

class AccountStatus {
  const AccountStatus({
    this.email,
    this.pendingEmail,
    required this.emailVerified,
    required this.resetAvailable,
  });
  final String? email, pendingEmail;
  final bool emailVerified, resetAvailable;
}

enum BackupRestoreMode { merge, replace }

class BackupPreview {
  BackupPreview({
    required this.backupId,
    required this.createdAt,
    required this.personalRevision,
    required Map<String, int> personalCounts,
    required this.scopeCount,
    required this.pendingCount,
    required this.hasRemoteRecovery,
    this.sourceAccount,
    this.sourceServer,
    Iterable<String> incompleteScopes = const [],
    Iterable<String> exclusions = const [],
  }) : personalCounts = Map.unmodifiable(personalCounts),
       incompleteScopes = List.unmodifiable(incompleteScopes),
       exclusions = List.unmodifiable(exclusions);
  final String backupId;
  final DateTime createdAt;
  final int personalRevision, scopeCount, pendingCount;
  final Map<String, int> personalCounts;
  final bool hasRemoteRecovery;
  final String? sourceAccount, sourceServer;
  final List<String> incompleteScopes, exclusions;
}

class BackupRestoreResult {
  const BackupRestoreResult({
    required this.backupId,
    required this.personalRecordCount,
    required this.hasRemoteRecovery,
  });
  final String backupId;
  final int personalRecordCount;
  final bool hasRemoteRecovery;
}

class BackupRecoveryItem {
  const BackupRecoveryItem({
    required this.scopeId,
    required this.scopeName,
    required this.recordId,
    required this.recordType,
    required this.title,
    required this.state,
    required this.isFinancial,
  });
  final String scopeId, scopeName, recordId, recordType, title, state;
  final bool isFinancial;
}

class BackupRecoveryReview {
  BackupRecoveryReview({
    required this.backupId,
    this.sourceAccount,
    this.sourceServer,
    this.canResume = false,
    required Iterable<BackupRecoveryItem> items,
  }) : items = List.unmodifiable(items);
  final bool canResume;
  final String backupId;
  final String? sourceAccount, sourceServer;
  final List<BackupRecoveryItem> items;
}
