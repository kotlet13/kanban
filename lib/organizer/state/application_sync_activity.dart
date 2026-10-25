import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// An unfocused but visible desktop window still participates in collaboration.
/// Hidden/minimized apps stop polling. Mobile background execution is unchanged.
bool collaborationAppActive(
  AppLifecycleState? lifecycle, {
  TargetPlatform? platform,
  bool? isWeb,
}) {
  if (lifecycle == AppLifecycleState.resumed) return true;
  return !(isWeb ?? kIsWeb) &&
      lifecycle == AppLifecycleState.inactive &&
      const {
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.linux,
      }.contains(platform ?? defaultTargetPlatform);
}
