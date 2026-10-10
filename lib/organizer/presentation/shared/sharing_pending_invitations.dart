import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n.dart';
import '../../state/collaboration_provider.dart';
import 'sharing_errors.dart';
import 'sharing_invitation_details.dart';
import 'sharing_session_boundary.dart';

class SharingPendingInvitations extends ConsumerWidget {
  const SharingPendingInvitations({
    super.key,
    required this.session,
    required this.supported,
    required this.onAccepted,
  });
  final AccountSession session;
  final bool supported;
  final ValueChanged<String> onAccepted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(securePendingInvitationProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (pending.hasError)
          Text(sharingErrorMessage(context, pending.error!)),
        _PendingInvitations(
          key: ValueKey('${session.partition}:${session.deviceId}'),
          session: session,
          supported: supported,
          pending: pending.valueOrNull,
          onAccepted: onAccepted,
        ),
      ],
    );
  }
}

class _PendingInvitations extends ConsumerStatefulWidget {
  const _PendingInvitations({
    required this.session,
    required this.supported,
    required this.pending,
    required this.onAccepted,
    super.key,
  });
  final AccountSession session;
  final bool supported;
  final PendingInvitation? pending;
  final ValueChanged<String> onAccepted;
  @override
  ConsumerState<_PendingInvitations> createState() =>
      _PendingInvitationsState();
}

class _InvitationInbox {
  const _InvitationInbox(this.entries, {this.savedError, this.inboxError});
  final List<(SharedInvitationPreview, String?)> entries;
  final Object? savedError, inboxError;
}

class _PendingInvitationsState extends ConsumerState<_PendingInvitations> {
  late final _guard = SharingSessionGuard(
    context,
    ref,
    session: widget.session,
  );
  late Future<_InvitationInbox> _future = _load();
  String? _error;
  bool _busy = false;
  bool _reloadAfterBusy = false;

  @override
  void didUpdateWidget(covariant _PendingInvitations oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_pendingIdentity(oldWidget.pending) !=
            _pendingIdentity(widget.pending) ||
        oldWidget.supported != widget.supported) {
      if (_busy) {
        _reloadAfterBusy = true;
      } else {
        _future = _load();
      }
    }
  }

  // Preview persists server metadata and reconstructs this object. Reload only
  // for a different capability/origin/account binding, not our own metadata save.
  (String, String, String?)? _pendingIdentity(PendingInvitation? pending) =>
      pending == null
      ? null
      : (pending.serverUrl, pending.token, pending.accountPartition);

  Future<_InvitationInbox> _load({bool refreshSaved = false}) async {
    if (!_guard.isCurrent ||
        !widget.session.expiresAt.isAfter(DateTime.now())) {
      return const _InvitationInbox([]);
    }
    final result = <(SharedInvitationPreview, String?)>[];
    Object? savedError, inboxError;
    PendingInvitation? pending = widget.pending;
    if (refreshSaved) {
      try {
        // A completed mutation can precede the parent widget's next rebuild.
        // Read its refreshed projection instead of resurrecting the old snapshot.
        pending = await ref.read(securePendingInvitationProvider.future);
      } catch (error) {
        savedError = error;
        pending = null;
      }
    }
    if (!_guard.isCurrent) return const _InvitationInbox([]);
    if (pending != null &&
        pending.serverUrl == widget.session.serverUrl &&
        (pending.accountPartition == null ||
            pending.accountPartition == widget.session.partition)) {
      try {
        final preview = await _guard.controller.previewInvitation(
          serverUrl: pending.serverUrl,
          token: pending.token,
          allowLocalHttp: widget.session.allowLocalHttp,
        );
        if (!_guard.isCurrent) return const _InvitationInbox([]);
        result.add((preview, pending.token));
      } catch (error) {
        savedError = error;
      }
    }
    if (widget.supported && _guard.isCurrent) {
      try {
        final inbox = await _guard.controller.pendingInvitations();
        if (!_guard.isCurrent) return const _InvitationInbox([]);
        for (final invitation in inbox) {
          if (!result.any(
            (entry) => entry.$1.invitationId == invitation.invitationId,
          )) {
            result.add((invitation, null));
          }
        }
      } catch (error) {
        inboxError = error;
      }
    }
    return _InvitationInbox(
      result,
      savedError: savedError,
      inboxError: inboxError,
    );
  }

  void _finishBusy() {
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (_reloadAfterBusy && _guard.isCurrent) {
        _future = _load();
      }
      _reloadAfterBusy = false;
    });
  }

  Future<void> _dismissSaved() async {
    final pending = widget.pending;
    if (_busy || pending == null || !_guard.isCurrent) return;
    setState(() => _busy = true);
    try {
      await _guard.controller.clearPendingInvitation(
        expectedToken: pending.token,
      );
      if (mounted && _guard.isCurrent) {
        setState(() {
          _reloadAfterBusy = false;
          _future = _load(refreshSaved: true);
        });
      }
    } catch (error) {
      if (mounted && _guard.isCurrent) {
        setState(() => _error = sharingErrorMessage(context, error));
      }
    } finally {
      _finishBusy();
    }
  }

  Future<void> _accept(
    SharedInvitationPreview invitation,
    String? token,
  ) async {
    if (_busy || !_guard.isCurrent) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (token != null) {
        await _guard.controller.acceptInvitation(token);
      } else {
        await _guard.controller.acceptPendingInvitation(
          invitation.invitationId!,
        );
      }
      if (!mounted || !_guard.isCurrent) return;
      await _guard.controller.selectSpace(invitation.scopeId);
      if (!mounted || !_guard.isCurrent) return;
      final messenger = ScaffoldMessenger.of(context);
      messenger.removeCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(content: Text(context.l10n.emailInviteAccepted)),
      );
      widget.onAccepted(invitation.scopeId);
      if (mounted) {
        setState(() {
          _reloadAfterBusy = false;
          _future = _load(refreshSaved: true);
        });
      }
    } catch (error) {
      if (mounted && _guard.isCurrent) {
        setState(() => _error = sharingErrorMessage(context, error));
      }
    } finally {
      _finishBusy();
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(collaborationProvider);
    if (!_guard.isCurrent) return const SizedBox.shrink();
    return FutureBuilder<_InvitationInbox>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const LinearProgressIndicator();
        }
        if (snapshot.hasError) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(sharingErrorMessage(context, snapshot.error!)),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => setState(() => _future = _load()),
                child: Text(context.l10n.organizerRetry),
              ),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (invitation, token)
                in snapshot.data?.entries ??
                    <(SharedInvitationPreview, String?)>[])
              Card(
                key: ValueKey(
                  'pending-invitation-${invitation.invitationId ?? invitation.scopeId}',
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.l10n.emailInvitePendingTitle,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      SharingInvitationDetails(invitation: invitation),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        key: ValueKey(
                          'accept-pending-${invitation.invitationId ?? invitation.scopeId}',
                        ),
                        onPressed: _busy
                            ? null
                            : () => _accept(invitation, token),
                        icon: const Icon(Icons.check),
                        label: Text(context.l10n.sharingAcceptInvite),
                      ),
                    ],
                  ),
                ),
              ),
            if (snapshot.data?.savedError != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(context.l10n.emailInvitePendingTitle),
                      const SizedBox(height: 8),
                      Text(
                        sharingErrorMessage(
                          context,
                          snapshot.data!.savedError!,
                        ),
                      ),
                      Wrap(
                        spacing: 8,
                        children: [
                          TextButton(
                            onPressed: _busy
                                ? null
                                : () => setState(() => _future = _load()),
                            child: Text(context.l10n.organizerRetry),
                          ),
                          TextButton(
                            key: const ValueKey('dismiss-saved-invitation'),
                            onPressed: _busy ? null : _dismissSaved,
                            child: Text(context.l10n.emailInviteDismiss),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            if (snapshot.data?.inboxError != null) ...[
              Text(sharingErrorMessage(context, snapshot.data!.inboxError!)),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => setState(() => _future = _load()),
                child: Text(context.l10n.organizerRetry),
              ),
            ],
            if (_busy) const LinearProgressIndicator(),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        );
      },
    );
  }
}
