import 'dart:typed_data';
import 'package:shared_preferences/shared_preferences.dart';
import 'local_vault.dart';
import 'preserved_installation_files.dart';
import 'local_vault_preferences.dart';

Future<LocalVaultService> openLocalVaultService() async => _UnsupportedVault();
// The bootstrap explicitly labels this platform unprotected and preserves its
// existing origin and export path. This is never a native error fallback.
Future<LocalVaultPreferences> openLocalVaultPreferences() async =>
    LegacyLocalVaultPreferences(await SharedPreferences.getInstance());

class _UnsupportedVault implements LocalVaultService {
  @override
  Future<LocalVaultStatus> inspect() async =>
      const LocalVaultStatus(LocalVaultPhase.unsupported);
  @override
  Future<Uint8List> prepareRecoveryFile() async =>
      throw const LocalVaultException('vault_platform_unsupported');
  @override
  Future<LocalVaultStatus> verifyRecoveryFile(Uint8List bytes) async =>
      throw const LocalVaultException('vault_platform_unsupported');
  @override
  Future<LocalVaultStatus> migrate() async =>
      throw const LocalVaultException('vault_platform_unsupported');
  @override
  Future<LocalVaultStatus> recover(Uint8List bytes) async =>
      throw const LocalVaultException('vault_platform_unsupported');
}

Future<PreservedInstallationFiles> openPreservedInstallationFiles() async =>
    _NoPreservedFiles();

class _NoPreservedFiles implements PreservedInstallationFiles {
  @override
  Future<List<PreservedInstallationFile>> list({String? afterId}) async => [];
  @override
  Future<Uint8List> read(String id) async =>
      throw const LocalVaultException('vault_platform_unsupported');
}
