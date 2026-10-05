import 'firebase_mobile_config.dart';

enum RemotePushPermission { granted, denied, unknown }

/// Injectable SDK boundary; no account/transport/business data in Firebase.
abstract interface class RemotePushSdk {
  bool get supported;
  String get platform;
  Future<Map<String, Object?>?> initialize(
    FirebaseMobileConfig config, {
    required void Function(Map<String, Object?>) onForeground,
    required void Function(Map<String, Object?>) onOpened,
    required void Function(String) onToken,
    required void Function() onError,
  });
  Future<RemotePushPermission> permissionStatus();
  Future<RemotePushPermission> requestPermission();
  Future<bool> prepareApns();
  Future<void> setAutoInit(bool enabled);
  Future<String?> token();
  Future<void> deleteToken();
  Future<void> stopListening();
}
