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
  const LocalVaultStatus(this.phase, {this.vaultId, this.errorCode});
  final LocalVaultPhase phase;
  final String? vaultId;
  final String? errorCode;
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
