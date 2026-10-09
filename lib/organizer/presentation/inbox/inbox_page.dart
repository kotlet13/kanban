import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n.dart';
import '../../state/collaboration_provider.dart';
import '../../state/organizer_provider.dart';
import '../organizer_widgets.dart';
import '../shared/sharing_errors.dart';
import '../shared/sharing_session_boundary.dart';
import 'notification_target_view.dart';
import 'finance_inbox_section.dart';
import '../../state/inbox_projection_provider.dart';
import 'reminder_snooze.dart';

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
  bool _showProgress = true;
  Future<void> _run(
    Future<void> Function() action, {
    bool showProgress = true,
  }) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _showProgress = showProgress;
    });
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
    VoidCallback? onSnooze,
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
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onSnooze != null)
            IconButton(
              tooltip: context.l10n.reminderSnooze,
              onPressed: _busy ? null : onSnooze,
              icon: const Icon(Icons.snooze_outlined),
            ),
          IconButton(
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
        ],
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
    final inbox = ref.watch(organizerInboxProjectionProvider);
    final groups = inbox.shared.where((item) {
      final entry = item.group.entries.first;
      return _filter == _InboxFilter.all ||
          (_filter == _InboxFilter.personal
              ? entry.audience == InboxAudience.personal
              : entry.audience == InboxAudience.scope);
    }).toList();
    final localGroups = _filter == _InboxFilter.scope ? const [] : inbox.local;
    final financePlans = inbox.finance
        .where(
          (p) =>
              _filter == _InboxFilter.all ||
              (_filter == _InboxFilter.personal
                  ? p.target.isPersonal ||
                        p.target.scopeId == shared?.privateSync.scopeId
                  : !p.target.isPersonal &&
                        p.target.scopeId != shared?.privateSync.scopeId),
        )
        .toList();
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
        if (_busy && _showProgress) const LinearProgressIndicator(),
        if (financePlans.isNotEmpty) FinanceInboxSection(plans: financePlans),
        for (final item in localGroups)
          _card(
            title: l.inboxPersonalReminders(1),
            subtitle:
                personal!.tasks
                    .where((t) => t.id == item.reminder.taskId)
                    .firstOrNull
                    ?.title ??
                l.organizerTasks,
            read: item.isRead,
            audience: l.inboxForMe,
            onSnooze: () => _run(
              () => snoozeReminder(context, ref, item.plan),
              showProgress: false,
            ),
            onOpen: () => _run(() async {
              await showNotificationTarget(
                context,
                ref,
                item.plan.target,
                onAccount: widget.onAccount,
              );
            }),
            onRead: item.isRead
                ? null
                : () => _run(() async {
                    final guard = SharingSessionGuard(context, ref);
                    if (!item.reminder.isRead) {
                      await ref
                          .read(organizerProvider.notifier)
                          .markReminderRead(item.reminder.id);
                    }
                    if (item.remoteEntries.isNotEmpty && guard.isCurrent) {
                      await guard.controller.markInboxRead(
                        item.remoteEntries.map((e) => e.id).toList(),
                      );
                    }
                  }),
          ),
        if (session != null)
          for (final item in groups)
            _card(
              title: _kind(
                item.group.entries.first.kind,
                item.group.entries.length,
              ),
              subtitle:
                  '${shared!.scopes.where((s) => s.id == item.group.entries.first.scopeId).firstOrNull?.name ?? l.sharingShared} · ${organizerDateTime(context, item.group.entries.first.createdAt)}',
              read: item.group.isRead,
              audience:
                  item.group.entries.first.audience == InboxAudience.personal
                  ? l.inboxForMe
                  : l.inboxInSharedSpace,
              onOpen: () {
                final guard = SharingSessionGuard(context, ref);
                final target = item.group.targetFor(session);
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
              onSnooze: item.plan == null
                  ? null
                  : () => _run(
                      () => snoozeReminder(context, ref, item.plan!),
                      showProgress: false,
                    ),
              onRead: () {
                final guard = SharingSessionGuard(context, ref);
                _run(
                  () => guard.controller.markInboxRead(
                    item.group.ids,
                    read: !item.group.isRead,
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
