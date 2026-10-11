import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/inbox_projection.dart';
import 'collaboration_provider.dart';
import 'finance_inbox_provider.dart';
import 'inbox_projection_provider.dart';
import 'local_spaces_provider.dart';

/// Receipts only: immutable IDs from the visible projection, never target edits.
/// Rechecks eligibility before every write so late arrivals are not consumed.
typedef InboxReadAction =
    Future<void> Function(
      OrganizerInboxProjection visible, {
      required AccountSession? expectedSession,
    });

final inboxReadActionProvider = Provider<InboxReadAction>((ref) {
  return (visible, {required expectedSession}) async {
    final session = expectedSession;
    bool current() {
      final state = ref.read(collaborationProvider);
      final active = state.valueOrNull?.session;
      return !state.isLoading &&
          !state.hasError &&
          active?.partition == session?.partition &&
          active?.deviceId == session?.deviceId;
    }

    void check() {
      if (!current()) throw const CollaborationException('session_changed');
    }

    bool localVisible(LocalInboxReminder item) =>
        current() &&
        ref
            .read(organizerInboxProjectionProvider)
            .local
            .any(
              (latest) =>
                  latest.workspaceKey == item.workspaceKey &&
                  latest.reminder.id == item.reminder.id &&
                  latest.reminder.dueAt == item.reminder.dueAt &&
                  latest.plan.scheduledAt == item.plan.scheduledAt,
            );
    bool financeVisible(ReminderPlan plan) =>
        current() &&
        ref
            .read(organizerInboxProjectionProvider)
            .finance
            .any(
              (latest) =>
                  latest.stableKey == plan.stableKey &&
                  latest.scheduledAt == plan.scheduledAt,
            );
    bool sharedVisible(int id) {
      if (!current()) return false;
      final inbox = ref.read(organizerInboxProjectionProvider);
      return inbox.local.any((r) => r.remoteEntries.any((e) => e.id == id)) ||
          inbox.shared.any((r) => r.group.entries.any((e) => e.id == id));
    }

    check();
    final remoteIds = {
      for (final item in visible.local)
        for (final entry in item.remoteEntries)
          if (!entry.isRead) entry.id,
      for (final item in visible.shared)
        for (final entry in item.group.entries)
          if (!entry.isRead) entry.id,
    };
    for (final item in visible.local.where((r) => !r.reminder.isRead)) {
      check();
      if (!localVisible(item)) continue;
      await ref
          .read(localSpacesProvider.notifier)
          .markReminderRead(
            item.plan.target.localWorkspaceId,
            item.reminder.id,
            expectedWorkspaceKey: item.workspaceKey,
            stillVisible: () => localVisible(item),
          );
    }
    if (visible.finance.isNotEmpty) {
      final store = await ref.read(financeInboxStoreProvider.future);
      check();
      final reads = await store.readKeys(visible.finance);
      check();
      try {
        for (final plan in visible.finance) {
          check();
          if (reads.contains(plan.stableKey) || !financeVisible(plan)) continue;
          await store.markRead(plan, stillVisible: () => financeVisible(plan));
        }
      } finally {
        if (current()) ref.invalidate(financeInboxReadKeysProvider);
      }
    }
    check();
    final eligibleIds = remoteIds.where(sharedVisible).toList();
    if (session != null && eligibleIds.isNotEmpty) {
      await ref
          .read(collaborationProvider.notifier)
          .markVisibleInboxRead(
            eligibleIds,
            expectedPartition: session.partition,
            stillEligible: sharedVisible,
          );
    }
  };
});
