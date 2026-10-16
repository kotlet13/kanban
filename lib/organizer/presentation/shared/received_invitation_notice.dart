import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n.dart';
import '../../state/collaboration_provider.dart';
import '../../state/received_invitation_notice_provider.dart';
import 'sharing_pending_invitations.dart';
import 'sharing_session_boundary.dart';

/// A compact entry into the existing explicit invitation decision screen.
class ReceivedInvitationNotice extends ConsumerStatefulWidget {
  const ReceivedInvitationNotice({super.key, required this.onAccepted});
  final ValueChanged<String> onAccepted;

  @override
  ConsumerState<ReceivedInvitationNotice> createState() =>
      _ReceivedInvitationNoticeState();
}

class _ReceivedInvitationNoticeState
    extends ConsumerState<ReceivedInvitationNotice>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(receivedInvitationNoticeProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(collaborationProvider).valueOrNull;
    final summary = ref.watch(receivedInvitationNoticeProvider).valueOrNull;
    final session = state?.session;
    if (state == null ||
        session == null ||
        state.sessionInvalid ||
        state.deletionPending ||
        (!state.emailInvitationsSupported &&
            !state.usernameInvitationsSupported) ||
        !session.expiresAt.isAfter(ref.read(collaborationClockProvider)()) ||
        summary == null ||
        summary.partition != session.partition ||
        summary.deviceId != session.deviceId ||
        summary.count == 0) {
      return const SizedBox.shrink();
    }
    return Card(
      key: const ValueKey('received-invitation-notice'),
      child: ListTile(
        leading: const Icon(Icons.mail_outline),
        title: Text(context.l10n.emailInvitePendingTitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => showReceivedInvitations(
          context,
          ref,
          onAccepted: widget.onAccepted,
        ),
      ),
    );
  }
}

Future<void> showReceivedInvitations(
  BuildContext context,
  WidgetRef ref, {
  required ValueChanged<String> onAccepted,
}) async {
  final state = ref.read(collaborationProvider).valueOrNull;
  final session = state?.session;
  if (state == null ||
      session == null ||
      state.sessionInvalid ||
      state.deletionPending ||
      !session.expiresAt.isAfter(ref.read(collaborationClockProvider)()) ||
      (!state.emailInvitationsSupported &&
          !state.usernameInvitationsSupported)) {
    return;
  }
  final guard = SharingSessionGuard(context, ref, session: session);
  final accepted = await Navigator.of(context).push<String>(
    MaterialPageRoute(
      builder: (routeContext) => SharingSessionBoundary(
        guard: guard,
        visibleWhen: (current) =>
            !current.sessionInvalid && !current.deletionPending,
        child: Scaffold(
          appBar: AppBar(title: Text(routeContext.l10n.sharingInvitations)),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: SharingPendingInvitations(
                session: session,
                supported: true,
                onAccepted: (id) => Navigator.of(routeContext).pop(id),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  if (context.mounted && guard.isCurrent) {
    ref.invalidate(receivedInvitationNoticeProvider);
    if (accepted != null) onAccepted(accepted);
  }
}
