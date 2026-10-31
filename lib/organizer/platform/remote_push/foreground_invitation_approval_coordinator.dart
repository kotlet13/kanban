import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/e2ee/invite_crypto_repository.dart';
import '../../data/e2ee/session_crypto_access.dart';
import '../../data/collaboration_repository.dart'
    show CollaborationNotificationRouting;
import '../../state/collaboration_provider.dart';
import '../../state/application_sync_activity.dart';
import 'remote_push_providers.dart';

typedef ForegroundInvitationApprovalRunner =
    Future<void> Function(
      bool Function() isForegroundCurrent,
      Set<String> invitationIds,
    );

/// Only a foreground signal. The core selects locally retained Send intents and
/// revalidates signed acceptance, authority, policy and the complete graph.
final foregroundInvitationApprovalRunnerProvider =
    Provider<ForegroundInvitationApprovalRunner>(
      (ref) => (isCurrent, invitationIds) async {
        if (!isCurrent()) return;
        final repository = await ref.read(
          collaborationRepositoryProvider.future,
        );
        if (!isCurrent()) return;
        final account = await repository.connectedCryptoAccount();
        if (!isCurrent()) return;
        final result =
            await InviteCryptoRepository(
              SessionCryptoAccess(account: account),
            ).processForegroundAutoApprovals(
              isForegroundCurrent: isCurrent,
              invitationIds: invitationIds,
            );
        if (isCurrent()) {
          // Fixed vocabulary only; no IDs, recipient data or exception text.
          final reasons = result.invitations
              .map(
                (item) =>
                    safeForegroundInvitationApprovalReason(item.errorCode),
              )
              .toSet()
              .join(',');
          debugPrint(
            'invitation_autoapproval completed=${result.completed} pending=${result.pending} reasons=$reasons',
          );
        }
        if (result.completed > 0 && isCurrent()) {
          try {
            await repository.refreshInvitationApprovalInbox(
              isCurrent: isCurrent,
            );
          } catch (_) {
            // Display-only cleanup is separate from the verified completion.
            debugPrint('invitation_autoapproval notice_refresh_pending');
          }
        }
      },
    );

class ForegroundInvitationApprovalCoordinator extends ConsumerStatefulWidget {
  const ForegroundInvitationApprovalCoordinator({
    super.key,
    required this.child,
  });
  final Widget child;

  @override
  ConsumerState<ForegroundInvitationApprovalCoordinator> createState() =>
      _ForegroundInvitationApprovalCoordinatorState();
}

class _ForegroundInvitationApprovalCoordinatorState
    extends ConsumerState<ForegroundInvitationApprovalCoordinator>
    with WidgetsBindingObserver {
  AppLifecycleState? _lifecycle;
  bool _running = false, _scheduled = false, _requestedDuringRun = false;
  String? _identity;
  bool _entered = false, _explicitRequestPending = false;
  final _seenEvents = <String>{};
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _lifecycle = WidgetsBinding.instance.lifecycleState;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _generation++;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final wasActive = collaborationAppActive(_lifecycle);
    _lifecycle = state;
    if (!collaborationAppActive(state)) {
      _generation++;
    } else if (!wasActive) {
      _entered = false;
      _changed(ref.read(collaborationProvider).valueOrNull);
    }
  }

  bool _eligible() {
    final shared = ref.read(collaborationProvider);
    final state = shared.valueOrNull;
    return mounted &&
        collaborationAppActive(_lifecycle) &&
        !shared.isLoading &&
        !shared.hasError &&
        state != null &&
        remotePushAccountUsable(state) &&
        state.localAccessAllowed &&
        !state.deletionPending &&
        !state.isSyncing &&
        state.scopes.any(
          (s) => s.canManage && !s.revoked && !s.blocked && !s.archived,
        );
  }

  void _schedule() {
    if (!mounted || !_eligible()) return;
    if (_running) {
      _requestedDuringRun = true;
      return;
    }
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (mounted && _eligible()) unawaited(_run());
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _run() async {
    if (_running || !_eligible()) return;
    final session = ref.read(collaborationProvider).requireValue.session!;
    final identity = '${session.partition}:${session.deviceId}';
    final generation = _generation;
    final currentState = ref.read(collaborationProvider).requireValue;
    final invitationIds = _entered
        ? {
            for (final item in currentState.inbox)
              if (item.invitationAcceptance != null &&
                  !_seenEvents.contains(
                    '${item.id}:${item.invitationAcceptance!.acceptanceProofHash}',
                  ))
                item.invitationAcceptance!.invitationId,
          }
        : <String>{};
    _entered = true;
    _explicitRequestPending = false;
    _seenEvents.addAll(_acceptedEvents(currentState));
    bool current() {
      if (!mounted || generation != _generation || !_eligible()) return false;
      final now = ref.read(collaborationProvider).valueOrNull?.session;
      return '${now?.partition}:${now?.deviceId}' == identity;
    }

    _running = true;
    try {
      await ref.read(foregroundInvitationApprovalRunnerProvider)(
        current,
        invitationIds,
      );
    } catch (error) {
      debugPrint(
        'invitation_autoapproval pending reason=${safeForegroundInvitationApprovalReason(error)}',
      );
      // The exact retained Send remains available for a later foreground event.
    } finally {
      _running = false;
      if (_requestedDuringRun) {
        _requestedDuringRun = false;
        _schedule();
      }
    }
  }

  void _changed(CollaborationState? state) {
    final session = state?.session;
    final identity = session == null
        ? null
        : '${session.partition}:${session.deviceId}';
    if (identity != _identity) {
      _generation++;
      _entered = false;
      _seenEvents.clear();
      _explicitRequestPending = false;
    }
    _identity = identity;
    if (!_eligible()) return;
    final accepted = _acceptedEvents(state!);
    if (!_explicitRequestPending &&
        _entered &&
        accepted.every(_seenEvents.contains)) {
      return;
    }
    _schedule();
  }

  Set<String> _acceptedEvents(CollaborationState state) => {
    for (final item in state.inbox)
      if (item.invitationAcceptance != null)
        '${item.id}:${item.invitationAcceptance!.acceptanceProofHash}',
  };

  @override
  Widget build(BuildContext context) {
    ref.listen(collaborationProvider, (_, next) => _changed(next.valueOrNull));
    ref.listen(
      foregroundInvitationApprovalRequestProvider,
      // A push can arrive for an already-seen inbox event after a transient
      // failure. An explicit wake-up must be allowed to retry the retained job.
      (_, _) {
        _explicitRequestPending = true;
        _schedule();
      },
    );
    _changed(ref.watch(collaborationProvider).valueOrNull);
    return widget.child;
  }
}
