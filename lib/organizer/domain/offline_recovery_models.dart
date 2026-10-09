import 'local_space_models.dart';

class OfflineSpaceRecoveryItem {
  const OfflineSpaceRecoveryItem({
    required this.scopeId,
    required this.name,
    required this.kind,
    required this.recordCount,
    required this.gardenCount,
  });
  final String scopeId, name;
  final LocalSpaceKind kind;
  final int recordCount, gardenCount;
}

class OfflineSpacesRecoveryPreview {
  const OfflineSpacesRecoveryPreview({
    required this.backupId,
    required this.fingerprint,
    required this.spaces,
    required this.limitations,
    required this.blockedScopeIds,
    this.sourceAccount,
    this.sourceServer,
  });
  final String backupId, fingerprint;
  final String? sourceAccount, sourceServer;
  final List<OfflineSpaceRecoveryItem> spaces;
  final List<String> limitations, blockedScopeIds;
  bool get canRecover => spaces.isNotEmpty;
}
