import 'package:firebase_core/firebase_core.dart';

/// Public client identifiers only. Service-account/APNs private keys never
/// belong in this configuration. Empty config keeps Firebase uninitialized.
class FirebaseMobileConfig {
  const FirebaseMobileConfig({
    required this.apiKey,
    required this.appId,
    required this.projectId,
    required this.senderId,
    required this.applicationId,
    required this.platform,
  });
  final String apiKey, appId, projectId, senderId, applicationId, platform;
  static const defines = {
    'FIREBASE_PROJECT_ID': String.fromEnvironment('FIREBASE_PROJECT_ID'),
    'FIREBASE_SENDER_ID': String.fromEnvironment('FIREBASE_SENDER_ID'),
    'FIREBASE_ANDROID_API_KEY': String.fromEnvironment(
      'FIREBASE_ANDROID_API_KEY',
    ),
    'FIREBASE_ANDROID_APP_ID': String.fromEnvironment(
      'FIREBASE_ANDROID_APP_ID',
    ),
    'FIREBASE_ANDROID_PACKAGE': String.fromEnvironment(
      'FIREBASE_ANDROID_PACKAGE',
    ),
    'FIREBASE_IOS_API_KEY': String.fromEnvironment('FIREBASE_IOS_API_KEY'),
    'FIREBASE_IOS_APP_ID': String.fromEnvironment('FIREBASE_IOS_APP_ID'),
    'FIREBASE_IOS_BUNDLE_ID': String.fromEnvironment('FIREBASE_IOS_BUNDLE_ID'),
  };
  static FirebaseMobileConfig? fromDefines(
    String platform, {
    Map<String, String> values = defines,
  }) {
    if (!{'android', 'ios'}.contains(platform)) return null;
    final prefix = platform == 'ios' ? 'FIREBASE_IOS' : 'FIREBASE_ANDROID';
    final api = values['${prefix}_API_KEY'] ?? '',
        app = values['${prefix}_APP_ID'] ?? '',
        project = values['FIREBASE_PROJECT_ID'] ?? '',
        sender = values['FIREBASE_SENDER_ID'] ?? '',
        identifier =
            values[platform == 'ios'
                ? 'FIREBASE_IOS_BUNDLE_ID'
                : 'FIREBASE_ANDROID_PACKAGE'] ??
            '';
    if ([api, app, identifier].every((v) => v.isEmpty)) return null;
    if (!RegExp(r'^AIza[A-Za-z0-9_-]{35}$').hasMatch(api) ||
        !RegExp(r'^[a-z][a-z0-9-]{4,28}[a-z0-9]$').hasMatch(project) ||
        !RegExp(r'^\d{6,20}$').hasMatch(sender) ||
        !RegExp('^1:$sender:$platform:[a-fA-F0-9]{8,64}\$').hasMatch(app) ||
        !RegExp(
          r'^[A-Za-z][A-Za-z0-9_-]*(?:\.[A-Za-z][A-Za-z0-9_-]*)+$',
        ).hasMatch(identifier)) {
      throw const FormatException('Invalid Firebase mobile configuration');
    }
    return FirebaseMobileConfig(
      apiKey: api,
      appId: app,
      projectId: project,
      senderId: sender,
      applicationId: identifier,
      platform: platform,
    );
  }

  FirebaseOptions get options => FirebaseOptions(
    apiKey: apiKey,
    appId: appId,
    messagingSenderId: senderId,
    projectId: projectId,
    iosBundleId: platform == 'ios' ? applicationId : null,
  );
}
