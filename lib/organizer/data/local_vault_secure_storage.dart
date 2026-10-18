import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Device/session secrets never migrate through Keychain backups. An unreadable
/// Android keystore must raise an error; automatic preference reset is disabled.
const localVaultSecureStorage = FlutterSecureStorage(
  aOptions: AndroidOptions(resetOnError: false),
  iOptions: IOSOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
  ),
  mOptions: MacOsOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
  ),
);

Future<void> protectExistingLocalVaultSecrets() async {
  for (final key in [
    'organizer_device_session_v1',
    'jivie_pending_invitation_v1',
    'organizer_remote_push_intent_v1',
    'organizer_remote_push_cleanup_v1',
    'jivie_account_deletion_receipts_v1',
  ]) {
    final value = await localVaultSecureStorage.read(key: key);
    if (value == null) continue;
    await localVaultSecureStorage.write(key: key, value: value);
    if (await localVaultSecureStorage.read(key: key) != value) {
      throw StateError('Secure device record protection failed');
    }
  }
}
