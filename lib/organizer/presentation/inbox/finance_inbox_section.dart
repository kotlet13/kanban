import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n.dart';
import '../../state/collaboration_provider.dart';
import '../../state/finance_inbox_provider.dart';
import '../../state/inbox_projection_provider.dart';
import 'reminder_snooze.dart';
import '../shared/sharing_errors.dart';
import 'notification_target_view.dart';

class FinanceInboxSection extends ConsumerStatefulWidget {
  const FinanceInboxSection({super.key, required this.plans});
  final List<ReminderPlan> plans;
  @override
  ConsumerState<FinanceInboxSection> createState() =>
      _FinanceInboxSectionState();
}

class _FinanceInboxSectionState extends ConsumerState<FinanceInboxSection> {
  bool _busy = false;
  String? _error;
  bool _visible(ReminderPlan plan) {
    if (!mounted) return false;
    return ref
        .read(organizerInboxProjectionProvider)
        .finance
        .any(
          (p) =>
              p.stableKey == plan.stableKey &&
              p.scheduledAt == plan.scheduledAt,
        );
  }

  Future<void> _read(ReminderPlan plan) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final store = await ref.read(financeInboxStoreProvider.future);
      if (!_visible(plan)) {
        throw const CollaborationException('finance_forbidden');
      }
      await store.markRead(plan, stillVisible: () => _visible(plan));
      ref.invalidate(financeInboxReadKeysProvider);
    } catch (e) {
      if (mounted) setState(() => _error = sharingErrorMessage(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final readsAsync = ref.watch(financeInboxReadKeysProvider);
    final reads = readsAsync.isLoading || readsAsync.hasError
        ? null
        : readsAsync.valueOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (readsAsync.isLoading) const LinearProgressIndicator(),
        if (readsAsync.hasError)
          Text(
            sharingErrorMessage(context, readsAsync.error!),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        if (_error != null)
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        for (final plan in widget.plans)
          Card(
            child: ListTile(
              leading: Icon(
                reads == null
                    ? Icons.more_horiz
                    : reads.contains(plan.stableKey)
                    ? Icons.mark_email_read_outlined
                    : Icons.mark_email_unread_outlined,
              ),
              title: Text(
                plan.reason == 'salary_check'
                    ? l.financePlanSalaryQuestion
                    : plan.reason == 'income_check'
                    ? l.financePlanIncomeQuestion
                    : l.financePlanExpenseQuestion,
              ),
              subtitle: Text(
                '${plan.target.isPersonal ? l.inboxForMe : l.inboxInSharedSpace} · ${organizerDateTime(context, plan.scheduledAt)}',
              ),
              onTap: _busy
                  ? null
                  : () async {
                      if (!_visible(plan)) return;
                      await showNotificationTarget(context, ref, plan.target);
                    },
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: l.reminderSnooze,
                    key: ValueKey('finance-inbox-snooze-${plan.stableKey}'),
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
                  ),
                  IconButton(
                    tooltip: l.inboxMarkRead,
                    key: ValueKey('finance-inbox-read-${plan.stableKey}'),
                    onPressed:
                        _busy || reads == null || reads.contains(plan.stableKey)
                        ? null
                        : () => _read(plan),
                    icon: const Icon(Icons.done),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
