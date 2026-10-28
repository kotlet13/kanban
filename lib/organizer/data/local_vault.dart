import 'dart:typed_data';

enum LocalVaultPhase {
  needsSetup,
  recoveryUnverified,
  migrationPending,
  recoveryRequired,
  cleanupPending,
  ready,
  unsupported,
}

class LocalVaultStatus {
  const LocalVaultStatus(
    this.phase, {
    this.vaultId,
    this.errorCode,
    this.retainedCopiesOnly = false,
  });
  final LocalVaultPhase phase;
  final String? vaultId;
  final String? errorCode;

  /// The encrypted installation is complete; only unclassified historical
  /// copies remain. This does not confirm protection of those retained files.
  final bool retainedCopiesOnly;
  bool get canContinueWithRetainedCopies =>
      phase == LocalVaultPhase.cleanupPending && retainedCopiesOnly;
  bool get canOpenDatabase =>
      phase == LocalVaultPhase.ready || phase == LocalVaultPhase.cleanupPending;
}

class LocalVaultException implements Exception {
  const LocalVaultException(this.code);
  final String code;
  @override
  String toString() => 'LocalVaultException($code)';
}

/// The installation key never enters the account protocol, sync or SMTP. A
/// recovery file restores only an existing local vault; it is not a data backup.
abstract interface class LocalVaultService {
  Future<LocalVaultStatus> inspect();
  Future<Uint8List> prepareRecoveryFile();
  Future<LocalVaultStatus> verifyRecoveryFile(Uint8List bytes);
  Future<LocalVaultStatus> migrate();
  Future<LocalVaultStatus> recover(Uint8List bytes);
}

/// Optional native capability. Only an installation with no retained user
/// state may start automatically; this never confirms an external recovery file.
abstract interface class LocalVaultFreshSetup {
  Future<LocalVaultStatus> initializeFreshInstallation();
}
