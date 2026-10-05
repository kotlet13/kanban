import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n.dart';
import '../../state/collaboration_provider.dart';

/// UI lifetime guard. The repository and server still enforce identity and ACL.
class SharingSessionGuard {
  SharingSessionGuard(
    BuildContext context,
    WidgetRef ref, {
    AccountSession? session,
    this.allowSignedOut = false,
  }) : _context = context,
       _container = ProviderScope.containerOf(context, listen: false),
       session =
           session ?? ref.read(collaborationProvider).valueOrNull?.session,
       _controller = ref.read(collaborationProvider.notifier);
  final BuildContext _context;
  final ProviderContainer _container;
  final AccountSession? session;
  final bool allowSignedOut;
  final CollaborationController _controller;

  bool get isCurrent {
    if (!_context.mounted) return false;
    try {
      final current = _container
          .read(collaborationProvider)
          .valueOrNull
          ?.session;
      if (session == null) return allowSignedOut && current == null;
      return current?.partition == session!.partition &&
          current?.deviceId == session!.deviceId;
    } catch (_) {
      return false;
    }
  }

  CollaborationController get controller {
    if (!isCurrent) throw const CollaborationException('session_changed');
    return _controller;
  }
}

class SharingSessionBoundary extends ConsumerStatefulWidget {
  const SharingSessionBoundary({
    super.key,
    required this.guard,
    required this.child,
    this.visibleWhen,
  });
  final SharingSessionGuard guard;
  final Widget child;
  final bool Function(CollaborationState)? visibleWhen;
  @override
  ConsumerState<SharingSessionBoundary> createState() =>
      _SharingSessionBoundaryState();
}

class _SharingSessionBoundaryState
    extends ConsumerState<SharingSessionBoundary> {
  bool _closing = false;
  @override
  Widget build(BuildContext context) {
    final current = ref.watch(collaborationProvider).valueOrNull;
    final route = ModalRoute.of(context);
    if (widget.guard.isCurrent &&
        (widget.visibleWhen == null ||
            (current != null && widget.visibleWhen!(current)))) {
      return widget.child;
    }
    if (!_closing && route?.isCurrent == true) {
      _closing = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && ModalRoute.of(context)?.isCurrent == true) {
          Navigator.of(context).pop();
        } else {
          _closing = false;
        }
      });
    }
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Text(context.l10n.sharingSessionExpired),
    );
  }
}
