import 'package:flutter/material.dart';
import '../../../l10n/l10n.dart';
import '../../domain/organizer_models.dart';
import '../../data/organizer_repository.dart' show newLocalId;
import '../organizer_editors.dart';
import 'date_time_field.dart';

class OrganizerRecordPlanningFields extends StatelessWidget {
  const OrganizerRecordPlanningFields({
    super.key,
    required this.draft,
    required this.project,
    required this.projects,
    required this.people,
    required this.financeAccounts,
    required this.costEditingEnabled,
    required this.costAccountRequired,
    required this.enabled,
    required this.onChanged,
    this.wrap,
  });
  final OrganizerDraft draft;
  final bool project, costEditingEnabled, costAccountRequired, enabled;
  final List<LocalProject> projects;
  final List<HouseholdPerson> people;
  final List<LocalFinanceAccount> financeAccounts;
  final VoidCallback onChanged;
  final Widget Function(Widget)? wrap;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final chosenProject = projects
        .where((p) => p.id == draft.projectId)
        .firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (project)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            initiallyExpanded: draft.phases.isNotEmpty,
            title: Text(l.planningPhases),
            children: [
              for (final phase in draft.phases)
                Padding(
                  key: ValueKey('phase-editor-${phase.id}'),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextFormField(
                        initialValue: phase.title,
                        decoration: InputDecoration(
                          labelText: l.planningPhaseTitle,
                        ),
                        validator: (v) => v == null || v.trim().isEmpty
                            ? l.organizerRequired
                            : null,
                        onSaved: (v) => _phase(
                          phase.id,
                          (p) => p.copyWith(title: v!.trim()),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        initialValue: phase.milestone,
                        decoration: InputDecoration(
                          labelText: l.planningMilestone,
                        ),
                        onSaved: (v) => _phase(
                          phase.id,
                          (p) => p.copyWith(milestone: v?.trim() ?? ''),
                        ),
                      ),
                      OrganizerDateTimeField(
                        label: l.planningStart,
                        value: phase.startAt,
                        withTime: false,
                        enabled: enabled,
                        wrap: wrap,
                        onChanged: (v) {
                          _phase(phase.id, (p) => p.copyWith(startAt: v));
                          onChanged();
                        },
                      ),
                      OrganizerDateTimeField(
                        label: l.planningEnd,
                        value: phase.endAt,
                        withTime: false,
                        enabled: enabled,
                        wrap: wrap,
                        onChanged: (v) {
                          _phase(phase.id, (p) => p.copyWith(endAt: v));
                          onChanged();
                        },
                      ),
                      TextButton.icon(
                        onPressed: !enabled
                            ? null
                            : () {
                                draft.phases = draft.phases
                                    .where((p) => p.id != phase.id)
                                    .toList();
                                onChanged();
                              },
                        icon: const Icon(Icons.remove_circle_outline),
                        label: Text(l.planningRemovePhase),
                      ),
                    ],
                  ),
                ),
              OutlinedButton.icon(
                key: const ValueKey('planning-add-phase'),
                onPressed: !enabled || draft.phases.length >= 50
                    ? null
                    : () {
                        draft.phases = [
                          ...draft.phases,
                          ProjectPhase(id: newLocalId(), title: ''),
                        ];
                        onChanged();
                      },
                icon: const Icon(Icons.add),
                label: Text(l.planningAddPhase),
              ),
            ],
          ),
        if (!project &&
            chosenProject != null &&
            chosenProject.phases.isNotEmpty) ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: ValueKey('task-phase-${chosenProject.id}'),
            initialValue: draft.phaseId ?? '',
            isExpanded: true,
            decoration: InputDecoration(labelText: l.planningPhases),
            items: [
              DropdownMenuItem(value: '', child: Text(l.planningNoPhase)),
              for (final p in chosenProject.phases)
                DropdownMenuItem(
                  value: p.id,
                  child: Text(
                    p.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: !enabled
                ? null
                : (v) => draft.phaseId = v == '' ? null : v,
          ),
        ],
        if (!project) ...[
          const SizedBox(height: 12),
          TextFormField(
            key: const ValueKey('task-estimate'),
            initialValue: draft.estimateMinutes?.toString() ?? '',
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: l.planningEstimateMinutes),
            validator: (v) =>
                _positive(v, 525600) ? null : l.planningInvalidMinutes(525600),
            onChanged: (v) {
              draft.estimateMinutes = int.tryParse(v);
              onChanged();
            },
            onSaved: (v) => draft.estimateMinutes = int.tryParse(v ?? ''),
          ),
        ],
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: Text(l.planningAvailabilityMinutes),
          initiallyExpanded: draft.availabilityMinutes != null,
          children: [
            TextFormField(
              initialValue: draft.availabilityMinutes?.toString() ?? '',
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: l.planningAvailabilityMinutes,
              ),
              validator: (v) =>
                  _positive(
                    v,
                    draft.availabilityPeriod == AvailabilityPeriod.day
                        ? 1440
                        : 10080,
                  )
                  ? null
                  : l.planningInvalidMinutes(
                      draft.availabilityPeriod == AvailabilityPeriod.day
                          ? 1440
                          : 10080,
                    ),
              onSaved: (v) {
                draft.availabilityMinutes = int.tryParse(v ?? '');
                if (draft.availabilityMinutes == null) {
                  draft.availabilityPeriod = null;
                } else {
                  draft.availabilityPeriod ??= AvailabilityPeriod.week;
                }
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<AvailabilityPeriod>(
              initialValue: draft.availabilityPeriod ?? AvailabilityPeriod.week,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: l.planningAvailabilityPeriod,
              ),
              items: [
                DropdownMenuItem(
                  value: AvailabilityPeriod.day,
                  child: Text(l.planningPerDay),
                ),
                DropdownMenuItem(
                  value: AvailabilityPeriod.week,
                  child: Text(l.planningPerWeek),
                ),
              ],
              onChanged: !enabled
                  ? null
                  : (v) {
                      draft.availabilityPeriod = v;
                      onChanged();
                    },
            ),
          ],
        ),
        if (!project && people.isNotEmpty) ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: draft.assigneePersonId ?? '',
            isExpanded: true,
            decoration: InputDecoration(labelText: l.planningAssignees),
            items: [
              DropdownMenuItem(value: '', child: Text(l.planningUnassigned)),
              for (final p in people.where(
                (p) => !p.archived || p.id == draft.assigneePersonId,
              ))
                DropdownMenuItem(
                  value: p.id,
                  child: Text(
                    p.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: !enabled
                ? null
                : (v) {
                    draft.assigneePersonId = v == '' ? null : v;
                    onChanged();
                  },
          ),
          const SizedBox(height: 8),
          Text(l.peopleTaskSubjects),
          Wrap(
            spacing: 8,
            children: [
              for (final p in people.where(
                (p) => !p.archived || draft.subjectPersonIds.contains(p.id),
              ))
                FilterChip(
                  label: Text(p.name),
                  selected: draft.subjectPersonIds.contains(p.id),
                  onSelected: !enabled
                      ? null
                      : (selected) {
                          draft.subjectPersonIds = selected
                              ? [...draft.subjectPersonIds, p.id]
                              : draft.subjectPersonIds
                                    .where((id) => id != p.id)
                                    .toList();
                          onChanged();
                        },
                ),
            ],
          ),
        ],
        if (!project && !costEditingEnabled && draft.costEnabled)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              '${l.taskCostTitle}: ${draft.costAmount} ${draft.costCurrency} · ${draft.costPaid ? l.taskCostPaid : l.taskCostPlanned}',
            ),
          ),
        if (!project && costEditingEnabled)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text(l.taskCostTitle),
            initiallyExpanded: draft.costEnabled,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l.taskCostEnabled),
                value: draft.costEnabled,
                onChanged: !enabled
                    ? null
                    : (v) {
                        draft.costEnabled = v;
                        onChanged();
                      },
              ),
              if (!draft.costEnabled)
                Text(
                  l.taskCostDetachHint,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              if (draft.costEnabled) ...[
                TextFormField(
                  key: const ValueKey('task-cost-amount'),
                  initialValue: draft.costAmount,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(labelText: l.amount),
                  validator: (v) {
                    try {
                      parseMoneyMinor(v ?? '');
                      return null;
                    } catch (_) {
                      return l.organizerInvalidMoney;
                    }
                  },
                  onSaved: (v) => draft.costAmount = v ?? '',
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: draft.costCurrency,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: l.organizerCurrency),
                  items: [
                    for (final c in supportedCurrencies)
                      DropdownMenuItem(value: c, child: Text(c)),
                  ],
                  onChanged: !enabled
                      ? null
                      : (v) {
                          draft.costCurrency = v!;
                          draft.ledgerAccountId = null;
                          onChanged();
                        },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: ValueKey('task-cost-account-${draft.costCurrency}'),
                  initialValue:
                      draft.ledgerAccountId ??
                      (costAccountRequired ? null : ''),
                  isExpanded: true,
                  decoration: InputDecoration(labelText: l.taskCostAccount),
                  items: [
                    if (!costAccountRequired)
                      DropdownMenuItem(
                        value: '',
                        child: Text(l.taskCostUnassignedAccount),
                      ),
                    for (final a in financeAccounts.where(
                      (a) =>
                          a.currency == draft.costCurrency &&
                          (!a.archived || a.id == draft.ledgerAccountId),
                    ))
                      DropdownMenuItem(
                        value: a.id,
                        child: Text(
                          a.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  validator: (value) =>
                      costAccountRequired && (value == null || value.isEmpty)
                      ? l.taskCostSelectAccount
                      : null,
                  onChanged: !enabled
                      ? null
                      : (v) => draft.ledgerAccountId = v == '' ? null : v,
                ),
                if (costAccountRequired &&
                    financeAccounts
                        .where(
                          (a) =>
                              a.currency == draft.costCurrency && !a.archived,
                        )
                        .isEmpty)
                  Text(l.financeNoAccounts),
                for (final f in [
                  ('payer', l.taskCostPayer, draft.payerPersonId),
                  ('recipient', l.taskCostRecipient, draft.recipientPersonId),
                ]) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: f.$3 ?? '',
                    isExpanded: true,
                    decoration: InputDecoration(labelText: f.$2),
                    items: [
                      DropdownMenuItem(
                        value: '',
                        child: Text(l.planningUnassigned),
                      ),
                      for (final p in people.where(
                        (p) => !p.archived || p.id == f.$3,
                      ))
                        DropdownMenuItem(
                          value: p.id,
                          child: Text(
                            p.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: !enabled
                        ? null
                        : (v) {
                            final id = v == '' ? null : v;
                            if (f.$1 == 'payer') {
                              draft.payerPersonId = id;
                            } else if (f.$1 == 'recipient') {
                              draft.recipientPersonId = id;
                            } else {
                              draft.recipientPersonId = id;
                            }
                          },
                  ),
                ],
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l.taskCostPaid),
                  value: draft.costPaid,
                  onChanged: !enabled || draft.costWasPaid
                      ? null
                      : (v) {
                          draft.costPaid = v ?? false;
                          draft.costPaidAt = draft.costPaid
                              ? draft.costPaidAt ?? DateTime.now()
                              : null;
                          onChanged();
                        },
                ),
                if (draft.costPaid)
                  OrganizerDateTimeField(
                    label: l.taskCostPaid,
                    value: draft.costPaidAt,
                    enabled: enabled && !draft.costWasPaid,
                    wrap: wrap,
                    onChanged: (value) {
                      draft.costPaidAt = value;
                      onChanged();
                    },
                  ),
                if (draft.date == null && !draft.costPaid)
                  Text(l.taskCostNoDue),
              ],
            ],
          ),
      ],
    );
  }

  void _phase(String id, ProjectPhase Function(ProjectPhase) transform) =>
      draft.phases = draft.phases
          .map((p) => p.id == id ? transform(p) : p)
          .toList();
  bool _positive(String? v, int max) =>
      v == null ||
      v.trim().isEmpty ||
      (int.tryParse(v) != null && int.parse(v) > 0 && int.parse(v) <= max);
}
