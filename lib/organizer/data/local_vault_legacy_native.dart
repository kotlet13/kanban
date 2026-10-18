import 'dart:typed_data';
import 'local_vault_native.dart';

Future<Uint8List?> readVaultLegacyHiveBytes() async =>
    (await openLocalVaultService()).readLegacyHiveBytes();
const useProtectedLegacyHive = true;
