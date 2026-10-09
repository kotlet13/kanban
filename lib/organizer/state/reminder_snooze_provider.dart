import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/reminder_snooze_store.dart';
import '../domain/organizer_projections.dart';
import '../domain/organizer_models.dart';
import 'collaboration_provider.dart';
import 'local_database_provider.dart';
import 'organizer_provider.dart';
import 'notification_local_spaces_provider.dart';

final reminderSnoozeStoreProvider = FutureProvider<ReminderSnoozeStore>(
  (ref) async => ReminderSnoozeStore(
    await ref.watch(localDatabaseProvider.future),
    clock: ref.watch(organizerClockProvider),
  ),
);

final effectiveReminderPlansProvider = FutureProvider<List<ReminderPlan>>((
  ref,
) async {
  final snapshots = await ref.watch(notificationLocalSnapshotsProvider.future);
  final shared = ref.watch(collaborationProvider);
  if (shared.isLoading) return [];
  final plans = desiredReminderPlans(
    personal: OrganizerSnapshot(),
    localSnapshots: snapshots,
    shared: shared.valueOrNull ?? CollaborationState(),
  );
  final store = await ref.watch(reminderSnoozeStoreProvider.future);
  return store.resolve(plans);
});
