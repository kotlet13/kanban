import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../l10n/l10n.dart';
import '../../domain/organizer_models.dart';
import '../../state/organizer_provider.dart';
import '../../state/reminder_snooze_provider.dart';
import '../personal_workspace_boundary.dart';
import '../shared/sharing_errors.dart';
import '../../state/collaboration_provider.dart';
import 'remote_reminder_editor.dart';

/// Device-only tasks use the same deadline choices without requiring a server.
class LocalTaskReminderButton extends ConsumerWidget {
  const LocalTaskReminderButton({
    super.key,
    required this.task,
    required this.workspaceKey,
  });
  final LocalTask task;
  final String workspaceKey;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(organizerProvider).valueOrNull;
    if (snapshot == null ||
        snapshot.workspaceKey != workspaceKey ||
        task.isCompleted ||
        task.dueAt == null) {
      return const SizedBox.shrink();
    }
    if (workspaceKey.startsWith('private:')) {
      final state = ref.watch(collaborationProvider).valueOrNull;
      final remoteId = state?.privateRecordIds.entries
          .where((e) => e.value == task.id)
          .firstOrNull
          ?.key;
      final scope = state?.privateSync.scopeId;
      if (remoteId != null && scope != null) {
        return RemoteReminderButton(
          scopeId: scope,
          targetType: 'task',
          targetId: remoteId,
        );
      }
      return const SizedBox.shrink();
    }
    return IconButton(
      key: ValueKey('local-task-reminder-${task.id}'),
      tooltip: context.l10n.localTaskReminderTitle,
      icon: const Icon(Icons.notifications_outlined, size: 20),
      onPressed: () async {
        final guard = PersonalWorkspaceGuard(context, ref, workspaceKey);
        final l = context.l10n;
        final offset = await showDialog<int>(
          context: context,
          builder: (context) => guard.wrap(
            SimpleDialog(
              title: Text(l.localTaskReminderTitle),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 8,
                  ),
                  child: Text(l.reminderRelativeExplanation),
                ),
                for (final choice in [
                  (0, l.reminderAtDeadline),
                  (60, l.reminderHourBefore),
                  (1440, l.reminderDayBefore),
                  (-1, l.remoteReminderCancel),
                ])
                  SimpleDialogOption(
                    onPressed: () => Navigator.pop(context, choice.$1),
                    child: Text(choice.$2),
                  ),
              ],
            ),
          ),
        );
        if (offset == null || !context.mounted || !guard.isCurrent) return;
        bool current() {
          final snapshot = ref.read(organizerProvider).valueOrNull;
          final now = snapshot?.tasks.where((t) => t.id == task.id).firstOrNull;
          return guard.isCurrent &&
              now != null &&
              now.createdAt == task.createdAt &&
              !now.isCompleted &&
              now.dueAt == task.dueAt;
        }

        try {
          final localId = workspaceKey.startsWith('private:')
              ? 'local'
              : workspaceKey;
          final plan = ReminderPlan(
            stableKey:
                '${localId == 'local' ? 'personal' : 'local:$localId'}:task:${task.id}:due',
            scheduledAt: task.dueAt!,
            reason: 'task_due',
            target: NotificationTarget(
              localSpaceId: localId == 'local' ? null : localId,
              records: [
                NotificationRecordTarget(type: 'task', recordId: task.id),
              ],
            ),
          );
          final store = await ref.read(reminderSnoozeStoreProvider.future);
          await store.setDeadlineOffset(
            plan,
            offset == -1 ? null : offset,
            stillCurrent: current,
          );
          ref.invalidate(effectiveReminderPlansProvider);
        } catch (error) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(sharingErrorMessage(context, error))),
            );
          }
        }
      },
    );
  }
}
