import '../collaboration_database.dart';

class CryptoArchiveColdDatabase {
  CollaborationDatabase get database =>
      throw UnsupportedError('crypto_native_vault_required');
  static Future<CryptoArchiveColdDatabase> create({Object? parent}) async =>
      throw UnsupportedError('crypto_native_vault_required');
  Future<void> close() async {}
}
