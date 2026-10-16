import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'collaboration_provider.dart';

class ReceivedInvitationNoticeState {
  const ReceivedInvitationNoticeState({
    required this.partition,
    required this.deviceId,
    required this.count,
  });
  final String partition, deviceId;
  final int count;
}

/// A session-scoped, event-driven summary; no timer or background polling.
final receivedInvitationNoticeProvider =
    FutureProvider<ReceivedInvitationNoticeState?>((ref) async {
      ref.watch(pendingInvitationRevisionProvider);
      final now = ref.read(collaborationClockProvider);
      final identity = ref.watch(
        collaborationProvider.select((value) {
          final state = value.valueOrNull;
          final session = state?.session;
          if (state == null ||
              session == null ||
              state.sessionInvalid ||
              state.deletionPending ||
              !session.expiresAt.isAfter(now()) ||
              (!state.emailInvitationsSupported &&
                  !state.usernameInvitationsSupported)) {
            return null;
          }
          return (session.partition, session.deviceId);
        }),
      );
      if (identity == null) return null;
      final invitations = await ref
          .read(collaborationProvider.notifier)
          .pendingInvitations();
      return ReceivedInvitationNoticeState(
        partition: identity.$1,
        deviceId: identity.$2,
        count: invitations.length,
      );
    });
