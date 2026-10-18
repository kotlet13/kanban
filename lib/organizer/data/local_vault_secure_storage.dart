import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'local_vault.dart';

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

Future<void> protectExistingLocalVaultSecrets({
  FlutterSecureStorage storage = localVaultSecureStorage,
}) async {
  if (!kIsWeb &&
      {
        TargetPlatform.iOS,
        TargetPlatform.macOS,
      }.contains(defaultTargetPlatform)) {
    final options = defaultTargetPlatform == TargetPlatform.macOS
        ? storage.mOptions.toMap()
        : storage.iOptions.toMap();
    try {
      final protected = await const MethodChannel('jivie/local_vault')
          .invokeMethod<bool>('protectLegacySecrets', {
            'service': options['accountName'],
            'accessGroup': options['groupId'],
          });
      if (protected != true) throw const FormatException();
    } catch (_) {
      throw const LocalVaultException('vault_secure_storage');
    }
    return;
  }
  for (final key in [
    'organizer_device_session_v1',
    'jivie_pending_invitation_v1',
    'organizer_remote_push_intent_v1',
    'organizer_remote_push_cleanup_v1',
    'jivie_account_deletion_receipts_v1',
  ]) {
    final value = await storage.read(key: key);
    if (value == null) continue;
    await storage.write(key: key, value: value);
    if (await storage.read(key: key) != value) {
      throw StateError('Secure device record protection failed');
    }
  }
}
