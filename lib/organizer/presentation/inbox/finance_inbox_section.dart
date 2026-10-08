import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n.dart';
import '../../domain/finance_reminder_plans.dart';
import '../../state/collaboration_provider.dart';
import '../../state/organizer_provider.dart';
import '../../state/finance_inbox_provider.dart';
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
  Set<String> _reads = {};
  String? _loadedSignature;
  String? _error;
  bool _visible(ReminderPlan plan) {
    if (!mounted) return false;
    final personal = ref.read(organizerProvider).valueOrNull;
    final shared = ref.read(collaborationProvider).valueOrNull;
    if (personal == null || shared == null) return false;
    return dueFinanceInboxPlans(
      personal: personal,
      shared: shared,
      now: ref.read(organizerClockProvider)(),
    ).any(
      (p) =>
          p.stableKey == plan.stableKey &&
          !p.scheduledAt.isAfter(ref.read(organizerClockProvider)()),
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
      if (mounted && _visible(plan)) setState(() => _reads.add(plan.stableKey));
    } catch (e) {
      if (mounted) setState(() => _error = sharingErrorMessage(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final signature = widget.plans.map((p) => p.stableKey).join('|');
    if (_loadedSignature != signature) {
      _loadedSignature = signature;
      final plans = widget.plans;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        try {
          final store = await ref.read(financeInboxStoreProvider.future);
          final reads = await store.readKeys(plans);
          if (mounted && _loadedSignature == signature) {
            setState(() => _reads = reads);
          }
        } catch (e) {
          if (mounted) setState(() => _error = sharingErrorMessage(context, e));
        }
      });
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_error != null)
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        for (final plan in widget.plans)
          Card(
            child: ListTile(
              leading: Icon(
                _reads.contains(plan.stableKey)
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
              trailing: IconButton(
                tooltip: l.inboxMarkRead,
                key: ValueKey('finance-inbox-read-${plan.stableKey}'),
                onPressed: _busy || _reads.contains(plan.stableKey)
                    ? null
                    : () => _read(plan),
                icon: const Icon(Icons.done),
              ),
            ),
          ),
      ],
    );
  }
}
