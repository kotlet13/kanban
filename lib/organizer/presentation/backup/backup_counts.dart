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
      'projects' => l.organizerProjects,
      'tasks' => l.organizerTasks,
      'shoppingLists' => l.organizerShopping,
      'shoppingItems' => l.backupShoppingItems,
      'events' => l.organizerCalendar,
      'financeEntries' || 'personalFinanceEntry' => l.organizerFinances,
      'reminders' => l.inboxCategoryReminders,
      'gardens' => l.gardenTitle,
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
