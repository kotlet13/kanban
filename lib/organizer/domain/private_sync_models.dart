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

/// Derived from a validated copy, never a claim that its server data is active.
class BackupContentSummary {
  BackupContentSummary({
    this.localSpaceCount = 0,
    this.personalScopeCount = 0,
    this.retainedLocalSpaceCount = 0,
    Map<String, int> localCounts = const {},
    Map<String, int> retainedLocalCounts = const {},
    Map<String, int> downloadedCounts = const {},
    Map<String, int> linkedPaymentCounts = const {},
    this.linkedPendingCount = 0,
    this.blockedCount = 0,
    this.deletedRecordCount = 0,
    this.standaloneFinanceLimited = false,
  }) : localCounts = Map.unmodifiable(localCounts),
       retainedLocalCounts = Map.unmodifiable(retainedLocalCounts),
       downloadedCounts = Map.unmodifiable(downloadedCounts),
       linkedPaymentCounts = Map.unmodifiable(linkedPaymentCounts);

  final int localSpaceCount, personalScopeCount, retainedLocalSpaceCount;
  final Map<String, int> retainedLocalCounts;
  final Map<String, int> localCounts, downloadedCounts, linkedPaymentCounts;
  final int linkedPendingCount, blockedCount, deletedRecordCount;
  final bool standaloneFinanceLimited;
}

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
    this.contentSummary,
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
  // Old stored previews have no detailed summary. Opening their encrypted copy
  // derives it again without changing the portable format or stored preview keys.
  final BackupContentSummary? contentSummary;
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
