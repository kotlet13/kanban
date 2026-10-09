import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/inbox_projection.dart';
import 'collaboration_provider.dart';
import 'finance_inbox_provider.dart';
import 'organizer_provider.dart';
import 'reminder_snooze_provider.dart';

final organizerInboxProjectionProvider = Provider<OrganizerInboxProjection>((
  ref,
) {
  final now =
      ref.watch(financeInboxClockProvider).valueOrNull ??
      ref.read(organizerClockProvider)();
  final personal = ref.watch(organizerProvider);
  final shared = ref.watch(collaborationProvider);
  return projectOrganizerInbox(
    personal: personal.isLoading || personal.hasError
        ? null
        : personal.valueOrNull,
    shared: shared.isLoading || shared.hasError
        ? CollaborationState()
        : shared.valueOrNull ?? CollaborationState(),
    effectivePlans: ref.watch(effectiveReminderPlansProvider).valueOrNull,
    now: now,
  );
});

final financeInboxReadKeysProvider = FutureProvider<Set<String>>((ref) async {
  final plans = ref.watch(organizerInboxProjectionProvider).finance;
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
