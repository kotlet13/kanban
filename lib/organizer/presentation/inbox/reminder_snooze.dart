import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n.dart';
import '../../data/reminder_snooze_store.dart';
import '../../domain/organizer_projections.dart';
import '../../state/collaboration_provider.dart';
import '../../state/organizer_provider.dart';
import '../../state/reminder_snooze_provider.dart';
import '../../state/notification_local_spaces_provider.dart';
import '../shared/sharing_errors.dart';

Future<DateTime?> chooseReminderSnooze(
  BuildContext context,
  DateTime now,
) async {
  final l = context.l10n;
  final choice = await showModalBottomSheet<int>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(
                    l.reminderSnooze,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(l.reminderSnoozeDeviceOnly),
                ],
              ),
            ),
            for (final item in <(int, String)>[
              (15, l.reminderSnooze15Minutes),
              (60, l.reminderSnooze1Hour),
              (1440, l.reminderSnoozeTomorrow),
              (0, l.reminderSnoozeChooseTime),
            ])
              ListTile(
                title: Text(item.$2),
                onTap: () => Navigator.pop(context, item.$1),
              ),
          ],
        ),
      ),
    ),
  );
  if (choice == null || !context.mounted) return null;
  if (choice == 1440) {
    final local = now.toLocal();
    return DateTime(
      local.year,
      local.month,
      local.day + 1,
      local.hour,
      local.minute,
    );
  }
  if (choice != 0) return now.add(Duration(minutes: choice));
  final local = now.toLocal();
  final date = await showDatePicker(
    context: context,
    initialDate: local,
    firstDate: DateTime(local.year, local.month, local.day),
    lastDate: DateTime(local.year + 5, 12, 31),
  );
  if (date == null || !context.mounted) return null;
  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(local.add(const Duration(hours: 1))),
  );
  if (time == null) return null;
  return DateTime(date.year, date.month, date.day, time.hour, time.minute);
}

Future<void> snoozeReminder(
  BuildContext context,
  WidgetRef ref,
  ReminderPlan selected,
) async {
  final personal = ref.read(organizerProvider).valueOrNull;
  final shared = ref.read(collaborationProvider).valueOrNull;
  if (personal == null || shared == null) return;
  final partition = shared.session?.partition;
  final deviceId = shared.session?.deviceId;
  ReminderPlan? currentPlan() {
    final currentPersonal = ref.read(organizerProvider).valueOrNull;
    final currentShared = ref.read(collaborationProvider).valueOrNull;
    if (currentPersonal == null ||
        currentShared == null ||
        currentShared.session?.partition != partition ||
        currentShared.session?.deviceId != deviceId) {
      return null;
    }
    return desiredReminderPlans(
      personal: currentPersonal,
      shared: currentShared,
      localSnapshots: ref
          .read(notificationLocalSnapshotsProvider)
          .asData
          ?.value,
    ).where((p) => p.stableKey == selected.stableKey).firstOrNull;
  }

  final original = currentPlan();
  if (original == null) return;
  final until = await chooseReminderSnooze(
    context,
    ref.read(organizerClockProvider)(),
  );
  if (until == null || !context.mounted) return;
  if (!until.isAfter(ref.read(organizerClockProvider)())) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.reminderSnoozeFutureRequired)),
    );
    return;
  }
  try {
    bool stillCurrent() {
      final current = currentPlan();
      return current != null &&
          ReminderSnoozeStore.signature(current) ==
              ReminderSnoozeStore.signature(original);
    }

    if (!stillCurrent()) {
      throw const CollaborationException('session_changed');
    }
    if (!original.target.isPersonal) {
      final result = await ref
          .read(collaborationProvider.notifier)
          .openNotificationTarget(original.target);
      if (!context.mounted) return;
      if (result.status != NotificationOpenStatus.available &&
          result.status != NotificationOpenStatus.offline &&
          result.status != NotificationOpenStatus.requiresConnection) {
        throw const CollaborationException('permission_revoked');
      }
    }
    final store = await ref.read(reminderSnoozeStoreProvider.future);
    await store.snooze(original, until, stillCurrent: stillCurrent);
    ref.invalidate(effectiveReminderPlansProvider);
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.reminderSnoozeSaved)));
    }
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(sharingErrorMessage(context, error))),
      );
    }
  }
}

class ReminderSnoozeButton extends ConsumerStatefulWidget {
  const ReminderSnoozeButton({super.key, required this.target});
  final NotificationTarget target;
  @override
  ConsumerState<ReminderSnoozeButton> createState() =>
      _ReminderSnoozeButtonState();
}

class _ReminderSnoozeButtonState extends ConsumerState<ReminderSnoozeButton> {
  bool _busy = false;
  @override
  Widget build(BuildContext context) {
    final plans = ref.watch(effectiveReminderPlansProvider).valueOrNull;
    final matching = plans
        ?.where(
          (plan) =>
              plan.target.serverUrl == widget.target.serverUrl &&
              plan.target.serverId == widget.target.serverId &&
              plan.target.accountId == widget.target.accountId &&
              plan.target.scopeId == widget.target.scopeId &&
              plan.target.records.length == 1 &&
              widget.target.records.length == 1 &&
              plan.target.records.single.type ==
                  widget.target.records.single.type &&
              plan.target.records.single.recordId ==
                  widget.target.records.single.recordId,
        )
        .toList();
    if (matching == null || matching.isEmpty) return const SizedBox.shrink();
    matching.sort((a, b) => b.scheduledAt.compareTo(a.scheduledAt));
    final plan = matching.first;
    return TextButton.icon(
      onPressed: _busy
          ? null
          : () async {
              setState(() => _busy = true);
              try {
                await snoozeReminder(context, ref, plan);
              } finally {
                if (mounted) setState(() => _busy = false);
              }
            },
      icon: const Icon(Icons.snooze_outlined),
      label: Text(context.l10n.reminderSnooze),
    );
  }
}
