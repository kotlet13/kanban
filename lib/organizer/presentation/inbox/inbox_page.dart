import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n.dart';
import '../../domain/organizer_models.dart';
import '../../state/collaboration_provider.dart';
import '../../state/organizer_provider.dart';
import '../organizer_widgets.dart';
import '../shared/sharing_errors.dart';
import '../shared/sharing_session_boundary.dart';
import 'notification_target_view.dart';
import 'finance_inbox_section.dart';
import '../../domain/finance_reminder_plans.dart';
import '../../state/finance_inbox_provider.dart';

enum _InboxFilter { all, personal, scope }

class OrganizerInboxPage extends ConsumerStatefulWidget {
  const OrganizerInboxPage({
    super.key,
    required this.onSettings,
    required this.onAccount,
  });
  final VoidCallback onSettings, onAccount;
  @override
  ConsumerState<OrganizerInboxPage> createState() => _OrganizerInboxPageState();
}

class _OrganizerInboxPageState extends ConsumerState<OrganizerInboxPage> {
  _InboxFilter _filter = _InboxFilter.all;
  bool _busy = false;
  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(sharingErrorMessage(context, error))),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _kind(String kind, int count) {
    final l = context.l10n;
    return switch (kind) {
      'task.created' => l.inboxTaskCreated(count),
      'task.assigned' => l.inboxTasksAssigned(count),
      'task.completed' => l.inboxTaskCompleted,
      'event.created' => l.inboxEventCreated,
      'event.assigned' => l.inboxEventAssigned,
      'shoppingList.created' => l.inboxShoppingListCreated,
      'shoppingItem.created' => l.inboxShoppingItemsCreated(count),
      'shoppingItem.checked' => l.inboxShoppingChecked,
      'member.joined' => l.inboxJoinedScope,
      'reminder.due' => l.inboxReminderDue,
      _ =>
        kind.startsWith('finance')
            ? l.inboxFinanceChanged
            : kind.startsWith('project')
            ? l.inboxProjectChanged
            : kind.endsWith('.deleted')
            ? l.inboxRecordDeleted
            : l.inboxRecordUpdated,
    };
  }

  Widget _card({
    required String title,
    required String subtitle,
    required bool read,
    required VoidCallback onOpen,
    required VoidCallback? onRead,
    required String audience,
  }) => Card(
    child: ListTile(
      contentPadding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      leading: Icon(
        read
            ? Icons.notifications_none_outlined
            : Icons.notifications_active_outlined,
      ),
      title: Text(
        title,
        style: read ? null : const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text('$audience · $subtitle'),
      onTap: _busy ? null : onOpen,
      trailing: IconButton(
        tooltip: onRead == null
            ? context.l10n.inboxRead
            : read
            ? context.l10n.inboxMarkUnread
            : context.l10n.inboxMarkRead,
        onPressed: _busy ? null : onRead,
        icon: Icon(
          read
              ? Icons.mark_email_unread_outlined
              : Icons.mark_email_read_outlined,
          size: 20,
        ),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final personal = ref.watch(organizerProvider).valueOrNull;
    final sharedAsync = ref.watch(collaborationProvider);
    final shared = sharedAsync.valueOrNull;
    final session = shared?.session;
    final groups = groupSharedInbox(shared?.inbox ?? const [])
        .where(
          (group) =>
              _filter == _InboxFilter.all ||
              (_filter == _InboxFilter.personal
                  ? group.entries.first.audience == InboxAudience.personal
                  : group.entries.first.audience == InboxAudience.scope),
        )
        .toList();
    final localGroups = <List<LocalReminder>>[];
    if (_filter != _InboxFilter.scope && personal != null) {
      for (final read in [false, true]) {
        final reminders = personal.reminders
            .where((r) => r.isRead == read)
            .toList();
        if (reminders.isNotEmpty) localGroups.add(reminders);
      }
    }
    final now =
        ref.watch(financeInboxClockProvider).valueOrNull ??
        ref.read(organizerClockProvider)();
    final financePlans =
        personal == null || shared == null
              ? <ReminderPlan>[]
              : dueFinanceInboxPlans(
                      personal: personal,
                      shared: shared,
                      now: now,
                    )
                    .where(
                      (p) =>
                          !p.scheduledAt.isAfter(
                            ref.read(organizerClockProvider)(),
                          ) &&
                          (_filter == _InboxFilter.all ||
                              (_filter == _InboxFilter.personal
                                  ? p.target.isPersonal ||
                                        p.target.scopeId ==
                                            shared.privateSync.scopeId
                                  : !p.target.isPersonal &&
                                        p.target.scopeId !=
                                            shared.privateSync.scopeId)),
                    )
                    .toList()
          ..sort((a, b) => b.scheduledAt.compareTo(a.scheduledAt));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OrganizerHeading(
          title: l.inboxTitle,
          action: IconButton(
            tooltip: l.inboxSettings,
            onPressed: widget.onSettings,
            icon: const Icon(Icons.tune_outlined),
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final filter in _InboxFilter.values)
              ChoiceChip(
                selected: _filter == filter,
                label: Text(switch (filter) {
                  _InboxFilter.all => l.inboxAll,
                  _InboxFilter.personal => l.inboxForMe,
                  _InboxFilter.scope => l.inboxInSharedSpace,
                }),
                onSelected: (_) => setState(() => _filter = filter),
              ),
          ],
        ),
        const SizedBox(height: 20),
        if (_busy) const LinearProgressIndicator(),
        if (financePlans.isNotEmpty) FinanceInboxSection(plans: financePlans),
        for (final reminders in localGroups)
          _card(
            title: l.inboxPersonalReminders(reminders.length),
            subtitle: reminders
                .map(
                  (r) =>
                      personal!.tasks
                          .where((t) => t.id == r.taskId)
                          .firstOrNull
                          ?.title ??
                      l.organizerTasks,
                )
                .join(', '),
            read: reminders.every((r) => r.isRead),
            audience: l.inboxForMe,
            onOpen: () => _run(() async {
              await showNotificationTarget(
                context,
                ref,
                NotificationTarget(
                  records: reminders.map(
                    (r) => NotificationRecordTarget(
                      type: 'task',
                      recordId: r.taskId,
                    ),
                  ),
                ),
                onAccount: widget.onAccount,
              );
            }),
            onRead: reminders.every((r) => r.isRead)
                ? null
                : () => _run(() async {
                    for (final reminder in reminders) {
                      if (!reminder.isRead) {
                        await ref
                            .read(organizerProvider.notifier)
                            .markReminderRead(reminder.id);
                      }
                    }
                  }),
          ),
        if (session != null)
          for (final group in groups)
            _card(
              title: _kind(group.entries.first.kind, group.entries.length),
              subtitle:
                  '${shared!.scopes.where((s) => s.id == group.entries.first.scopeId).firstOrNull?.name ?? l.sharingShared} · ${organizerDateTime(context, group.entries.first.createdAt)}',
              read: group.isRead,
              audience: group.entries.first.audience == InboxAudience.personal
                  ? l.inboxForMe
                  : l.inboxInSharedSpace,
              onOpen: () {
                final guard = SharingSessionGuard(context, ref);
                final target = group.targetFor(session);
                _run(() async {
                  if (!guard.isCurrent) return;
                  await showNotificationTarget(
                    context,
                    ref,
                    target,
                    onAccount: widget.onAccount,
                  );
                });
              },
              onRead: () {
                final guard = SharingSessionGuard(context, ref);
                _run(
                  () => guard.controller.markInboxRead(
                    group.ids,
                    read: !group.isRead,
                  ),
                );
              },
            ),
        if (groups.isEmpty && localGroups.isEmpty && financePlans.isEmpty)
          OrganizerEmpty(
            icon: Icons.notifications_none_outlined,
            title: l.inboxEmpty,
          ),
        if (sharedAsync.hasError)
          Text(sharingErrorMessage(context, sharedAsync.error!)),
        if (session != null && shared?.inboxSupported != true)
          Text(l.inboxSharedPreferencesUnavailable),
      ],
    );
  }
}
