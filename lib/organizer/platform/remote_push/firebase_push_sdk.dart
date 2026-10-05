import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'firebase_mobile_config.dart';
import 'remote_push_sdk.dart';

/// The OS renders the server's generic notification. Background code neither
/// opens the private database nor authenticates, logs, navigates or duplicates it.
@pragma('vm:entry-point')
Future<void> familyHubPushBackground(RemoteMessage message) async {}

class FirebasePushSdk implements RemotePushSdk {
  final _subscriptions = <StreamSubscription<dynamic>>[];
  FirebaseMessaging? _messaging;
  static const _native = MethodChannel('vsakdan/remote_push_readiness');
  @override
  bool get supported =>
      !kIsWeb &&
      {
        TargetPlatform.android,
        TargetPlatform.iOS,
      }.contains(defaultTargetPlatform);
  @override
  String get platform =>
      defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';
  @override
  Future<Map<String, Object?>?> initialize(
    FirebaseMobileConfig config, {
    required void Function(Map<String, Object?>) onForeground,
    required void Function(Map<String, Object?>) onOpened,
    required void Function(String) onToken,
    required void Function() onError,
  }) async {
    if (!supported) throw UnsupportedError('Remote push platform');
    final actual = await _native.invokeMethod<String>('applicationId');
    if (actual != config.applicationId) {
      throw const FormatException('Firebase application identifier mismatch');
    }
    await stopListening();
    final app = Firebase.apps.isEmpty
        ? await Firebase.initializeApp(options: config.options)
        : Firebase.app();
    if (app.options.appId != config.appId ||
        app.options.projectId != config.projectId) {
      throw const FormatException('Firebase project mismatch');
    }
    final messaging = _messaging = FirebaseMessaging.instance;
    await messaging.setAutoInitEnabled(false);
    await messaging.setForegroundNotificationPresentationOptions(
      alert: false,
      badge: false,
      sound: false,
    );
    FirebaseMessaging.onBackgroundMessage(familyHubPushBackground);
    if (platform == 'android') {
      final android = FlutterLocalNotificationsPlugin()
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      await android?.createNotificationChannel(
        const AndroidNotificationChannel(
          'familyhub_push_silent_v1',
          'Vsakdan',
          importance: Importance.defaultImportance,
          playSound: false,
        ),
      );
      await android?.createNotificationChannel(
        const AndroidNotificationChannel(
          'familyhub_push_sound_v1',
          'Vsakdan',
          importance: Importance.defaultImportance,
          playSound: true,
        ),
      );
    }
    _subscriptions.addAll([
      FirebaseMessaging.onMessage.listen(
        (m) => onForeground(Map<String, Object?>.from(m.data)),
        onError: (_) => onError(),
      ),
      FirebaseMessaging.onMessageOpenedApp.listen(
        (m) => onOpened(Map<String, Object?>.from(m.data)),
        onError: (_) => onError(),
      ),
      messaging.onTokenRefresh.listen(onToken, onError: (_) => onError()),
    ]);
    final initial = await messaging.getInitialMessage();
    return initial == null ? null : Map<String, Object?>.from(initial.data);
  }

  RemotePushPermission _permission(NotificationSettings settings) =>
      switch (settings.authorizationStatus) {
        AuthorizationStatus.authorized ||
        AuthorizationStatus.provisional => RemotePushPermission.granted,
        AuthorizationStatus.denied => RemotePushPermission.denied,
        _ => RemotePushPermission.unknown,
      };
  @override
  Future<RemotePushPermission> permissionStatus() async =>
      _permission(await _messaging!.getNotificationSettings());
  @override
  Future<RemotePushPermission> requestPermission() async => _permission(
    await _messaging!.requestPermission(alert: true, badge: false, sound: true),
  );
  @override
  Future<bool> prepareApns() async {
    if (platform != 'ios') return true;
    // Native registration is explicit while FCM auto-init remains disabled.
    // Only after APNs delivered its token do we enable the FCM SDK.
    await _native.invokeMethod<void>('registerApns');
    for (var attempt = 0; attempt < 10; attempt++) {
      if (await _native.invokeMethod<bool>('hasApnsToken') == true) return true;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    return false;
  }

  @override
  Future<void> setAutoInit(bool enabled) async {
    if (_messaging != null) await _messaging!.setAutoInitEnabled(enabled);
  }

  @override
  Future<String?> token() async {
    if (platform == 'ios' && await _messaging!.getAPNSToken() == null) {
      return null;
    }
    return _messaging!.getToken();
  }

  @override
  Future<void> deleteToken() async {
    if (_messaging != null) await _messaging!.deleteToken();
  }

  @override
  Future<void> stopListening() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
  }
}
