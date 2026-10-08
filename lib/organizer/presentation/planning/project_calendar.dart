import 'dart:math';
import 'package:flutter/material.dart';
import '../../../l10n/l10n.dart';
import '../../domain/organizer_models.dart';
import '../../domain/project_calendar.dart';
import '../organizer_widgets.dart';

class ProjectCalendar extends StatefulWidget {
  const ProjectCalendar({
    super.key,
    required this.project,
    required this.tasks,
    this.onTaskSelected,
    this.initialMonth,
  });
  final LocalProject project;
  final List<LocalTask> tasks;
  final ValueChanged<LocalTask>? onTaskSelected;
  final DateTime? initialMonth;
  @override
  State<ProjectCalendar> createState() => _ProjectCalendarState();
}

class _ProjectCalendarState extends State<ProjectCalendar> {
  late DateTime _month;
  late DateTime _selected;
  @override
  void initState() {
    super.initState();
    final initial = widget.initialMonth ?? DateTime.now();
    _month = DateTime(initial.year, initial.month);
    _selected = DateTime(initial.year, initial.month, initial.day);
  }

  @override
  void didUpdateWidget(ProjectCalendar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.project.id != widget.project.id) {
      final now = DateTime.now();
      _month = DateTime(now.year, now.month);
      _selected = DateTime(now.year, now.month, now.day);
    }
  }

  void _move(int count) => setState(() {
    _month = DateTime(_month.year, _month.month + count);
    _selected = _month;
  });
  @override
  Widget build(BuildContext context) {
    final l = context.l10n,
        material = MaterialLocalizations.of(context),
        scheme = Theme.of(context).colorScheme;
    final entries = projectCalendarItems(widget.project, widget.tasks);
    final firstWeekday = material.firstDayOfWeekIndex;
    final offset = (_month.weekday % 7 - firstWeekday + 7) % 7;
    final length = DateTime(_month.year, _month.month + 1, 0).day;
    final count = ((offset + length + 6) ~/ 7) * 7;
    final selectedEntries = entries.where((e) => e.covers(_selected)).toList();
    Color color(ProjectCalendarKind kind) => switch (kind) {
      ProjectCalendarKind.project => scheme.secondary,
      ProjectCalendarKind.phase => scheme.tertiary,
      ProjectCalendarKind.task => scheme.primary,
    };
    String kindLabel(ProjectCalendarKind kind) => switch (kind) {
      ProjectCalendarKind.project => l.project,
      ProjectCalendarKind.phase => l.planningPhases,
      ProjectCalendarKind.task => l.organizerTasks,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(
              key: const ValueKey('project-calendar-previous'),
              tooltip: material.previousMonthTooltip,
              onPressed: () => _move(-1),
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Text(
                material.formatMonthYear(_month),
                key: const ValueKey('project-calendar-month'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            IconButton(
              key: const ValueKey('project-calendar-next'),
              tooltip: material.nextMonthTooltip,
              onPressed: () => _move(1),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final height = max(
              48.0,
              MediaQuery.textScalerOf(context).scale(14) + 30,
            );
            final width = max(
              constraints.maxWidth,
              7 * (MediaQuery.textScalerOf(context).scale(14) * 2 + 8),
            );
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: width,
                child: Column(
                  children: [
                    Row(
                      children: [
                        for (var weekday = 0; weekday < 7; weekday++)
                          Expanded(
                            child: Text(
                              material.narrowWeekdays[(firstWeekday + weekday) %
                                  7],
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ),
                      ],
                    ),
                    for (var row = 0; row < count ~/ 7; row++)
                      Row(
                        children: [
                          for (var column = 0; column < 7; column++)
                            Expanded(
                              child: Builder(
                                builder: (context) {
                                  final day = row * 7 + column - offset + 1;
                                  if (day < 1 || day > length) {
                                    return SizedBox(height: height);
                                  }
                                  final date = DateTime(
                                    _month.year,
                                    _month.month,
                                    day,
                                  );
                                  final items = entries
                                      .where((e) => e.covers(date))
                                      .toList();
                                  final selected = _selected == date;
                                  return Semantics(
                                    button: true,
                                    selected: selected,
                                    label:
                                        '${material.formatFullDate(date)}${items.isEmpty ? '' : ' · ${items.map((e) => e.title).join(', ')}'}',
                                    child: ExcludeSemantics(
                                      child: InkWell(
                                        key: ValueKey(
                                          'project-calendar-day-${date.year}-${date.month}-$day',
                                        ),
                                        onTap: () =>
                                            setState(() => _selected = date),
                                        child: Container(
                                          height: height,
                                          margin: const EdgeInsets.all(1),
                                          decoration: BoxDecoration(
                                            color: selected
                                                ? scheme.primaryContainer
                                                : null,
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                            border: items.isEmpty
                                                ? null
                                                : Border.all(
                                                    color:
                                                        scheme.outlineVariant,
                                                  ),
                                          ),
                                          child: Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Text(
                                                '$day',
                                                style: Theme.of(
                                                  context,
                                                ).textTheme.bodyMedium,
                                              ),
                                              if (items.isNotEmpty)
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                        top: 4,
                                                      ),
                                                  child: Wrap(
                                                    spacing: 3,
                                                    children: [
                                                      for (final kind
                                                          in items
                                                              .map(
                                                                (e) => e.kind,
                                                              )
                                                              .toSet())
                                                        Container(
                                                          width: 5,
                                                          height: 5,
                                                          decoration:
                                                              BoxDecoration(
                                                                color: color(
                                                                  kind,
                                                                ),
                                                                shape: BoxShape
                                                                    .circle,
                                                              ),
                                                        ),
                                                    ],
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            for (final kind in ProjectCalendarKind.values)
              Text.rich(
                TextSpan(
                  children: [
                    WidgetSpan(
                      child: Icon(Icons.circle, size: 8, color: color(kind)),
                    ),
                    TextSpan(text: ' ${kindLabel(kind)}'),
                  ],
                ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          material.formatFullDate(_selected),
          style: Theme.of(context).textTheme.titleSmall,
        ),
        if (selectedEntries.isEmpty)
          Text(
            l.organizerNoMatchingTasks,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        for (final item in selectedEntries)
          ListTile(
            key: ValueKey('project-calendar-item-${item.kind.name}-${item.id}'),
            contentPadding: EdgeInsets.zero,
            leading: Icon(switch (item.kind) {
              ProjectCalendarKind.project => Icons.folder_outlined,
              ProjectCalendarKind.phase => Icons.flag_outlined,
              ProjectCalendarKind.task => Icons.check_circle_outline,
            }, color: color(item.kind)),
            title: Text(item.title),
            subtitle: Text(
              [
                kindLabel(item.kind),
                if (item.start != null) organizerDate(context, item.start!),
                if (item.end != null) organizerDate(context, item.end!),
              ].join(' · '),
            ),
            onTap:
                item.kind == ProjectCalendarKind.task &&
                    widget.onTaskSelected != null
                ? () => widget.onTaskSelected!(
                    widget.tasks.firstWhere((t) => t.id == item.id),
                  )
                : null,
          ),
      ],
    );
  }
}
