import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../state/collaboration_provider.dart';

import '../../l10n/l10n.dart';
import '../domain/organizer_models.dart';
import 'organizer_actions.dart';
import 'organizer_widgets.dart';
import 'finance/finance_money.dart';

class OrganizerFinancePage extends ConsumerWidget {
  const OrganizerFinancePage({
    super.key,
    required this.snapshot,
    required this.actions,
  });
  final OrganizerSnapshot snapshot;
  final OrganizerActions actions;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final shared = ref.watch(collaborationProvider).valueOrNull;
    final privateScopeId = shared?.privateSync.scopeId;
    final complete =
        shared?.privateSync.enabled != true ||
        privateScopeId == null ||
        shared?.financeSnapshotComplete[privateScopeId] == true;
    final entries = [...snapshot.financeEntries]
      ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    final currencies = entries.map((e) => e.currency).toSet().toList()..sort();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OrganizerHeading(
          title: l.organizerFinances,
          subtitle: l.organizerFinanceIntro,
          action: FilledButton.icon(
            onPressed: () => actions.finance(),
            icon: const Icon(Icons.add, size: 18),
            label: Text(l.organizerAddFinance),
          ),
        ),
        if (!complete)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(l.privateFinanceIncomplete),
          ),
        if (entries.isEmpty && complete)
          OrganizerEmpty(
            icon: Icons.account_balance_wallet_outlined,
            title: l.organizerNoFinance,
            action: l.organizerAddFinance,
            onAction: () => actions.finance(),
          ),
        if (currencies.isNotEmpty && complete)
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              for (final currency in currencies)
                SizedBox(
                  width: 260,
                  child: Card(
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l.organizerBalance,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            sharedMoneyLabel(context, snapshot.exactBalanceForCurrency(currency), currency),
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        const SizedBox(height: 24),
        for (final entry in entries)
          Container(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
              onTap: () => actions.finance(entry),
              leading: Icon(
                entry.kind == FinanceEntryKind.income
                    ? Icons.south_west
                    : Icons.north_east,
                color: Theme.of(context).colorScheme.primary,
                size: 20,
              ),
              title: Text(entry.title),
              subtitle: Text(
                '${organizerDate(context, entry.occurredAt)} · ${entry.kind == FinanceEntryKind.income ? l.organizerIncome : l.organizerExpense}',
              ),
              trailing: Text(
                '${entry.kind == FinanceEntryKind.income ? '+' : '−'}${formatMoneyMinor(entry.amountMinor)} ${entry.currency}',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
          ),
      ],
    );
  }
}
