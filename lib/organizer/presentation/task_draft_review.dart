part of 'organizer_editors.dart';

Map<String, Object?> _taskDraftFields(OrganizerDraft d) => {
  'title': d.title,
  'notes': d.notes,
  'assignment': {
    'project': d.projectId,
    'phase': d.phaseId,
    'person': d.assigneePersonId,
    'subjects': [...d.subjectPersonIds],
    'accounts': [...d.assigneeIds],
  },
  'schedule': [
    d.date?.toIso8601String(),
    d.startAt?.toIso8601String(),
    d.endAt?.toIso8601String(),
  ],
  'planning': [
    d.estimateMinutes,
    d.availabilityMinutes,
    d.availabilityPeriod?.name,
  ],
  'completion': d.isCompleted,
  'timer': d.timer.toJson(),
  // Financial fields are one indivisible choice: never mix an account/currency,
  // payment status or historical posting base from separate versions.
  'cost': {
    'enabled': d.costEnabled,
    'amount': d.costAmount,
    'currency': d.costCurrency,
    'paid': d.costPaid,
    'wasPaid': d.costWasPaid,
    'paidAt': d.costPaidAt?.toIso8601String(),
    'account': d.ledgerAccountId,
    'payer': d.payerPersonId,
    'recipient': d.recipientPersonId,
    'creator': d.createdByPersonId,
  },
};

OrganizerDraft _taskDraftFromFields(Map<String, Object?> fields) {
  final assignment = fields['assignment'] as Map;
  final schedule = fields['schedule'] as List;
  final planning = fields['planning'] as List;
  final cost = fields['cost'] as Map;
  DateTime? date(Object? value) =>
      value == null ? null : DateTime.parse(value as String);
  return OrganizerDraft(
    title: fields['title'] as String,
    notes: fields['notes'] as String,
    projectId: assignment['project'] as String?,
    phaseId: assignment['phase'] as String?,
    assigneePersonId: assignment['person'] as String?,
    subjectPersonIds: (assignment['subjects'] as List).cast<String>(),
    assigneeIds: (assignment['accounts'] as List).cast<String>(),
    date: date(schedule[0]),
    startAt: date(schedule[1]),
    endAt: date(schedule[2]),
    estimateMinutes: planning[0] as int?,
    availabilityMinutes: planning[1] as int?,
    availabilityPeriod: planning[2] == null
        ? null
        : AvailabilityPeriod.values.byName(planning[2] as String),
    isCompleted: fields['completion'] as bool,
    timer: TaskTimerState.fromJson(
      Map<String, dynamic>.from(fields['timer'] as Map),
    ),
    costEnabled: cost['enabled'] as bool,
    costAmount: cost['amount'] as String,
    costCurrency: cost['currency'] as String,
    costPaid: cost['paid'] as bool,
    costWasPaid: cost['wasPaid'] as bool,
    costPaidAt: date(cost['paidAt']),
    ledgerAccountId: cost['account'] as String?,
    payerPersonId: cost['payer'] as String?,
    recipientPersonId: cost['recipient'] as String?,
    createdByPersonId: cost['creator'] as String?,
  );
}

class _TaskDraftReviewDialog extends StatefulWidget {
  const _TaskDraftReviewDialog({
    required this.merge,
    required this.labels,
    required this.describe,
    required this.costVisible,
  });
  final DraftThreeWayMerge merge;
  final Map<String, String> labels;
  final String Function(String key, Object? value) describe;
  final bool costVisible;
  @override
  State<_TaskDraftReviewDialog> createState() => _TaskDraftReviewDialogState();
}

class _TaskDraftReviewDialogState extends State<_TaskDraftReviewDialog> {
  final _choices = <String, bool>{};
  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      title: Text(l.organizerDraftCompareTitle),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.organizerDraftCompareHelp),
              for (final key in widget.merge.changed)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.labels[key]!,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      if (key != 'cost' || widget.costVisible) ...[
                        Text(
                          '${l.organizerDraftBase}: ${widget.describe(key, widget.merge.base[key])}',
                        ),
                        Text(
                          '${l.organizerDraftMine}: ${widget.describe(key, widget.merge.mine[key])}',
                        ),
                        Text(
                          '${l.organizerDraftLatest}: ${widget.describe(key, widget.merge.latest[key])}',
                        ),
                      ] else
                        Text(l.recordEditForbidden),
                      if (widget.merge.conflicts.contains(key))
                        Wrap(
                          spacing: 8,
                          children: [
                            ChoiceChip(
                              key: ValueKey('draft-keep-mine-$key'),
                              label: Text(l.organizerDraftMine),
                              selected: _choices[key] == true,
                              onSelected: (_) =>
                                  setState(() => _choices[key] = true),
                            ),
                            ChoiceChip(
                              key: ValueKey('draft-keep-latest-$key'),
                              label: Text(l.organizerDraftLatest),
                              selected: _choices[key] == false,
                              onSelected: (_) =>
                                  setState(() => _choices[key] = false),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        FilledButton(
          key: const ValueKey('draft-apply-review'),
          onPressed: widget.merge.resolve(_choices) == null
              ? null
              : () => Navigator.pop(context, widget.merge.resolve(_choices)),
          child: Text(l.organizerDraftApply),
        ),
      ],
    );
  }
}
