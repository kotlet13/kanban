import 'package:flutter/material.dart';

import '../../../l10n/l10n.dart';
import 'date_time_field.dart';

class OrganizerPersonOption {
  const OrganizerPersonOption({
    required this.id,
    required this.label,
    this.active = true,
  });
  final String id;
  final String label;
  final bool active;
}

class OrganizerTaskPlanFields extends StatelessWidget {
  const OrganizerTaskPlanFields({
    super.key,
    required this.startAt,
    required this.endAt,
    required this.onStartChanged,
    required this.onEndChanged,
    this.assigneeIds,
    this.people = const [],
    this.onAssigneesChanged,
    this.creatorLabel,
    this.enabled = true,
    this.showStart = true,
    this.wrap,
  });
  final DateTime? startAt;
  final DateTime? endAt;
  final ValueChanged<DateTime?> onStartChanged;
  final ValueChanged<DateTime?> onEndChanged;
  final List<String>? assigneeIds;
  final List<OrganizerPersonOption> people;
  final ValueChanged<List<String>>? onAssigneesChanged;
  final String? creatorLabel;
  final bool enabled;
  final bool showStart;
  final Widget Function(Widget)? wrap;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final compact = MediaQuery.sizeOf(context).width < 600;
    final selected = assigneeIds ?? const <String>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (onAssigneesChanged != null) ...[
          SizedBox(height: compact ? 12 : 16),
          Text(
            l.planningAssignees,
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 8),
          if (selected.isEmpty)
            Text(
              l.planningUnassigned,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final person in people.where(
                (p) => p.active || selected.contains(p.id),
              ))
                FilterChip(
                  key: ValueKey('task-assignee-${person.id}'),
                  label: Text(person.label),
                  selected: selected.contains(person.id),
                  onSelected:
                      !enabled ||
                          (!person.active && !selected.contains(person.id))
                      ? null
                      : (add) {
                          final next = [...selected];
                          if (add) {
                            next.add(person.id);
                          } else {
                            next.remove(person.id);
                          }
                          onAssigneesChanged!(next);
                        },
                ),
              for (final id in selected.where(
                (id) => !people.any((person) => person.id == id),
              ))
                InputChip(
                  label: Text(l.planningFormerMember),
                  onDeleted: enabled
                      ? () => onAssigneesChanged!(
                          selected.where((other) => other != id).toList(),
                        )
                      : null,
                ),
            ],
          ),
        ],
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          minTileHeight: 48,
          initiallyExpanded: (showStart && startAt != null) || endAt != null,
          title: Text(
            l.planningSchedule,
            style: compact ? Theme.of(context).textTheme.bodyMedium : null,
          ),
          children: [
            if (showStart)
              OrganizerDateTimeField(
                key: const ValueKey('task-start-date'),
                label: l.planningStart,
                value: startAt,
                onChanged: onStartChanged,
                enabled: enabled,
                wrap: wrap,
              ),
            if (showStart) const SizedBox(height: 8),
            OrganizerDateTimeField(
              key: const ValueKey('task-end-date'),
              label: l.planningEnd,
              value: endAt,
              onChanged: onEndChanged,
              enabled: enabled,
              wrap: wrap,
            ),
          ],
        ),
        if (creatorLabel != null) ...[
          const SizedBox(height: 8),
          Text(
            '${l.planningCreatedBy}: $creatorLabel',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}
