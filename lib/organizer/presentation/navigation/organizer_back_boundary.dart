import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../l10n/l10n.dart';
import 'organizer_navigation_observer.dart';

/// Lets the Navigator dismiss overlays first, then handles shell destinations.
/// Only a phone running Android can request the deliberate double-Back exit.
class OrganizerBackBoundary extends StatefulWidget {
  const OrganizerBackBoundary({
    super.key,
    required this.child,
    required this.scaffoldKey,
    required this.hasPrevious,
    required this.navigationRevision,
    required this.phone,
    required this.onBack,
  });
  final Widget child;
  final GlobalKey<ScaffoldState> scaffoldKey;
  final bool hasPrevious, phone;
  final Object navigationRevision;
  final Future<void> Function() onBack;

  @override
  State<OrganizerBackBoundary> createState() => _OrganizerBackBoundaryState();
}

class _OrganizerBackBoundaryState extends State<OrganizerBackBoundary>
    with WidgetsBindingObserver {
  Timer? _exitWindow;
  bool _handlingBack = false;
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? _exitMessage;
  bool get _androidPhone =>
      !kIsWeb &&
      widget.phone &&
      defaultTargetPlatform == TargetPlatform.android;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    organizerRouteActivity.addListener(_resetExit);
  }

  void _resetExit() {
    _exitWindow?.cancel();
    _exitWindow = null;
    _exitMessage?.close();
    _exitMessage = null;
  }

  @override
  void didUpdateWidget(covariant OrganizerBackBoundary oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.navigationRevision != widget.navigationRevision ||
        oldWidget.phone != widget.phone) {
      _resetExit();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _resetExit();
  }

  Future<void> _back(bool didPop) async {
    if (didPop || _handlingBack) return;
    final scaffold = widget.scaffoldKey.currentState;
    if (scaffold?.isDrawerOpen == true) {
      _resetExit();
      scaffold!.closeDrawer();
      return;
    }
    if (ModalRoute.of(context)?.isCurrent != true) return;
    if (widget.hasPrevious) {
      _resetExit();
      _handlingBack = true;
      try {
        await widget.onBack();
      } finally {
        _handlingBack = false;
      }
    } else if (_androidPhone) {
      if (_exitWindow?.isActive == true) {
        _resetExit();
        await SystemNavigator.pop();
      } else {
        _exitMessage = ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.organizerPressBackAgainToExit),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
        _exitWindow = Timer(const Duration(seconds: 2), _resetExit);
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope<Object?>(
    canPop: !widget.hasPrevious && !_androidPhone,
    onPopInvokedWithResult: (didPop, _) => _back(didPop),
    child: widget.child,
  );

  @override
  void dispose() {
    _exitWindow?.cancel();
    organizerRouteActivity.removeListener(_resetExit);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
