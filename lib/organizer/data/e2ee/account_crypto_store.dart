import '../local_vault_secure_storage.dart';

abstract interface class AccountCryptoStore {
  Future<String?> read(String partition);
  Future<void> write(String partition, String value);
}

/// Account/device material is independent of the physical database key. It is
/// never exported as an installation key or sent to the authentication API.
class SecureAccountCryptoStore implements AccountCryptoStore {
  const SecureAccountCryptoStore();
  static const _storage = localVaultSecureStorage;
  String _key(String partition) => 'jivie_account_crypto_v1_$partition';
  @override
  Future<String?> read(String partition) async {
    try {
      return await _storage.read(key: _key(partition));
    } catch (_) {
      throw const AccountCryptoStorageException();
    }
  }

  @override
  Future<void> write(String partition, String value) async {
    try {
      await _storage.write(key: _key(partition), value: value);
      if (await _storage.read(key: _key(partition)) != value) {
        throw const AccountCryptoStorageException();
      }
    } catch (_) {
      throw const AccountCryptoStorageException();
    }
  }
}

class AccountCryptoStorageException implements Exception {
  const AccountCryptoStorageException();
  @override
  String toString() => 'AccountCryptoStorageException';
}
