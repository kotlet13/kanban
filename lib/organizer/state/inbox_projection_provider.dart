import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/inbox_projection.dart';
import '../data/finance_inbox_store.dart';
import 'collaboration_provider.dart';
import 'finance_inbox_provider.dart';
import 'organizer_provider.dart';
import 'reminder_snooze_provider.dart';
import 'notification_local_spaces_provider.dart';
import 'local_notification_preferences_provider.dart';

final rawOrganizerInboxProjectionProvider = Provider<OrganizerInboxProjection>((
  ref,
) {
  ref.watch(financeInboxClockProvider);
  final now = ref.read(organizerClockProvider)();
  final personal = ref.watch(organizerProvider);
  final shared = ref.watch(collaborationProvider);
  final snapshots = ref.watch(notificationLocalSnapshotsProvider).valueOrNull;
  final policy = ref.watch(localNotificationPreferencesProvider).valueOrNull;
  final projection = projectOrganizerInbox(
    personal: personal.isLoading || personal.hasError
        ? null
        : personal.valueOrNull,
    localSnapshots: snapshots,
    shared: shared.isLoading || shared.hasError
        ? CollaborationState()
        : shared.valueOrNull ?? CollaborationState(),
    effectivePlans: ref.watch(effectiveReminderPlansProvider).valueOrNull,
    now: now,
  );
  bool visible(NotificationTarget target) {
    if (!target.isPersonal || policy == null) return true;
    final snapshot = snapshots
        ?.where(
          (s) =>
              (s.workspaceKey.startsWith('private:')
                  ? 'local'
                  : s.workspaceKey) ==
              target.localWorkspaceId,
        )
        .firstOrNull;
    return policy
        .resolve(
          snapshot?.workspaceKey ?? target.localWorkspaceId,
          notificationProject(target, snapshot),
        )
        .inApp;
  }

  return OrganizerInboxProjection(
    local: projection.local.where((p) => visible(p.plan.target)).toList(),
    shared: projection.shared,
    finance: projection.finance.where((p) => visible(p.target)).toList(),
  );
});

final organizerInboxProjectionProvider = Provider<OrganizerInboxProjection>((
  ref,
) {
  final raw = ref.watch(rawOrganizerInboxProjectionProvider);
  // Keep known expiry suppression during a background receipt refresh. Keys
  // include the account/scope (or persistent local space), so old account dates
  // cannot hide another account's notification. The badge still treats a
  // loading/error receipt state as unknown below.
  final receipts = ref.watch(financeInboxReadKeysProvider).valueOrNull;
  ref.watch(financeInboxClockProvider);
  final now = ref.read(organizerClockProvider)();
  return OrganizerInboxProjection(
    local: raw.local,
    shared: raw.shared,
    finance: receipts is FinanceInboxReadKeys
        ? raw.finance.where((p) => !receipts.expired(p.stableKey, now)).toList()
        : raw.finance,
  );
});

final financeInboxReadKeysProvider = FutureProvider<Set<String>>((ref) async {
  final plans = ref.watch(rawOrganizerInboxProjectionProvider).finance;
  if (plans.isEmpty) return {};
  final store = await ref.watch(financeInboxStoreProvider.future);
  return store.readKeys(plans);
});

final organizerInboxHasUnreadProvider = Provider<bool>((ref) {
  final inbox = ref.watch(organizerInboxProjectionProvider);
  final readsAsync = ref.watch(financeInboxReadKeysProvider);
  final financeReads = readsAsync.isLoading || readsAsync.hasError
      ? null
      : readsAsync.valueOrNull;
  return inbox.hasUnread(financeReads);
});
