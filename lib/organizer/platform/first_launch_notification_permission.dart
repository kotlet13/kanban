import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'local_notification_scheduler.dart';
import 'notification_providers.dart';

// An installation-level, non-sensitive guide flag, not an account preference.
final notificationPromptPreferencesProvider = FutureProvider<SharedPreferences>(
  (ref) => SharedPreferences.getInstance(),
);

/// Runs inside the unlocked app, after its first frame. OS permission does not
/// change account subscriptions, server notification preferences or push opt-in.
class FirstLaunchNotificationPermission extends ConsumerStatefulWidget {
  const FirstLaunchNotificationPermission({super.key, required this.child});
  final Widget child;

  static const attemptedKey = 'jivie_notification_permission_prompt_v1';

  @override
  ConsumerState<FirstLaunchNotificationPermission> createState() =>
      _FirstLaunchNotificationPermissionState();
}

class _FirstLaunchNotificationPermissionState
    extends ConsumerState<FirstLaunchNotificationPermission>
    with WidgetsBindingObserver {
  bool _busy = false, _done = false, _claimed = false;

  bool get _active =>
      mounted &&
      (WidgetsBinding.instance.lifecycleState == null ||
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_request()));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_request());
  }

  Future<void> _request() async {
    if (_busy ||
        _done ||
        !_active ||
        kIsWeb ||
        !{
          TargetPlatform.android,
          TargetPlatform.iOS,
        }.contains(defaultTargetPlatform)) {
      return;
    }
    _busy = true;
    try {
      final prefs = await ref.read(
        notificationPromptPreferencesProvider.future,
      );
      if (!_active) return;
      if (!_claimed &&
          prefs.getBool(FirstLaunchNotificationPermission.attemptedKey) ==
              true) {
        _done = true;
        return;
      }
      final adapter = await ref.read(localNotificationAdapterProvider.future);
      if (!_active) return;
      // Persist before presenting: rejection, dismissal and app termination must
      // not turn this into a prompt on every launch. Settings remain available.
      if (!_claimed) {
        if (!await prefs.setBool(
          FirstLaunchNotificationPermission.attemptedKey,
          true,
        )) {
          throw StateError('Notification prompt preference could not be saved');
        }
        _claimed = true;
      }
      if (!_active) return;
      _done = true;
      if (adapter.status.permission != LocalNotificationPermission.granted &&
          adapter.status.permission !=
              LocalNotificationPermission.unsupported) {
        await adapter.requestPermission();
      }
      if (mounted) {
        ref.read(localNotificationDeviceStatusProvider.notifier).state =
            AsyncData(adapter.status);
      }
    } catch (error, stack) {
      _done = true;
      if (mounted) {
        ref.read(localNotificationDeviceStatusProvider.notifier).state =
            AsyncError(error, stack);
      }
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
