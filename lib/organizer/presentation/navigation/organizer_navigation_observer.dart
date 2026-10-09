import 'package:flutter/material.dart';

/// Resets the exit gesture when a dialog, editor or router page opens/closes.
final organizerRouteActivity = ValueNotifier<int>(0);

class OrganizerNavigationObserver extends NavigatorObserver {
  void _changed() => organizerRouteActivity.value++;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _changed();
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _changed();
  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _changed();
  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _changed();
}
