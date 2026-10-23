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
      var disposed = false;
      ref.onDispose(() => disposed = true);
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
      if (disposed) return null;
      final current = ref.read(collaborationProvider).valueOrNull;
      if (current == null ||
          current.sessionInvalid ||
          current.deletionPending ||
          current.session?.partition != identity.$1 ||
          current.session?.deviceId != identity.$2 ||
          current.session?.expiresAt.isAfter(now()) != true) {
        return null;
      }
      return ReceivedInvitationNoticeState(
        partition: identity.$1,
        deviceId: identity.$2,
        count: invitations.length,
      );
    });
