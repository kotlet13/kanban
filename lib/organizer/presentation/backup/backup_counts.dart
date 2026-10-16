import 'package:flutter/material.dart';
import '../../../l10n/l10n.dart';

class BackupCounts extends StatelessWidget {
  const BackupCounts({super.key, required this.counts});
  final Map<String, int> counts;
  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    String label(String key) => switch (key) {
      'people' || 'householdPerson' => l.peopleTitle,
      'financeAccounts' ||
      'financeAccount' ||
      'personalFinanceAccount' => l.financeAccounts,
      'financeRecurrenceRules' || 'financeRecurrenceRule' => l.financePlanRules,
      'projects' || 'project' => l.organizerProjects,
      'tasks' || 'task' => l.organizerTasks,
      'shoppingLists' || 'shoppingList' => l.organizerShopping,
      'shoppingItems' || 'shoppingItem' => l.backupShoppingItems,
      'events' || 'event' => l.organizerCalendar,
      'financeEntries' ||
      'financeEntry' ||
      'personalFinanceEntry' => l.organizerFinances,
      'financeTransfer' => l.backupFinanceTransfers,
      'reminders' => l.inboxCategoryReminders,
      'gardens' || 'garden' => l.gardenTitle,
      'ideas' || 'idea' => l.ideasCountLabel,
      'ideaDrafts' => l.ideaDraftsCountLabel,
      'tableDrafts' =>
        Localizations.localeOf(context).languageCode == 'sl'
            ? 'Osnutki preglednic'
            : 'Spreadsheet drafts',
      'inbox' => l.inboxTitle,
      'scheduled_reminders' => l.backupScheduledReminders,
      'paymentEvents' => l.backupPaymentEvents,
      'paymentProjections' => l.backupPaymentProjections,
      'paymentCashMovements' => l.backupPaymentCashMovements,
      _ => l.backupOtherRecords,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final entry in counts.entries)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Expanded(child: Text(label(entry.key))),
                Text('${entry.value}'),
              ],
            ),
          ),
      ],
    );
  }
}
