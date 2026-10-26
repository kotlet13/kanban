import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../../l10n/l10n.dart';
import '../../domain/organizer_projections.dart';

/// Uses local midnight boundaries so ranges and daylight-saving days agree
/// with the shared daily agenda.
bool agendaItemCoversDay(AgendaItem item, DateTime day) {
  final start = DateTime(day.year, day.month, day.day);
  final end = DateTime(day.year, day.month, day.day + 1);
  bool onDay(DateTime? date) =>
      date != null && !date.isBefore(start) && date.isBefore(end);
  return !item.isCompleted &&
      (onDay(item.dueAt) ||
          onDay(item.startAt) ||
          item.startAt != null &&
              item.endAt != null &&
              item.startAt!.isBefore(end) &&
              item.endAt!.isAfter(start));
}

class AgendaMonthCalendar extends StatelessWidget {
  const AgendaMonthCalendar({
    super.key,
    required this.day,
    required this.items,
    required this.onSelected,
  });
  final DateTime day;
  final List<AgendaItem> items;
  final ValueChanged<DateTime> onSelected;

  @override
  Widget build(BuildContext context) {
    final material = MaterialLocalizations.of(context);
    final month = DateTime(day.year, day.month);
    final offset = (month.weekday % 7 - material.firstDayOfWeekIndex + 7) % 7;
    final length = DateTime(day.year, day.month + 1, 0).day;
    final cells = ((offset + length + 6) ~/ 7) * 7;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      key: const ValueKey('shared-month-calendar'),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: material.previousMonthTooltip,
                  onPressed: () =>
                      onSelected(DateTime(day.year, day.month - 1)),
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: Text(
                    material.formatMonthYear(month),
                    textAlign: TextAlign.center,
                  ),
                ),
                IconButton(
                  tooltip: material.nextMonthTooltip,
                  onPressed: () =>
                      onSelected(DateTime(day.year, day.month + 1)),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            LayoutBuilder(
              builder: (context, constraints) {
                final cellSize = math.max(
                  48.0,
                  MediaQuery.textScalerOf(context).scale(14) * 2 + 12,
                );
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: math.max(constraints.maxWidth, cellSize * 7),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            for (var i = 0; i < 7; i++)
                              Expanded(
                                child: Text(
                                  material.narrowWeekdays[(material
                                              .firstDayOfWeekIndex +
                                          i) %
                                      7],
                                  textAlign: TextAlign.center,
                                ),
                              ),
                          ],
                        ),
                        for (var row = 0; row < cells ~/ 7; row++)
                          Row(
                            children: [
                              for (var column = 0; column < 7; column++)
                                Expanded(
                                  child: Builder(
                                    builder: (context) {
                                      final number =
                                          row * 7 + column - offset + 1;
                                      if (number < 1 || number > length) {
                                        return SizedBox(height: cellSize);
                                      }
                                      final date = DateTime(
                                        day.year,
                                        day.month,
                                        number,
                                      );
                                      final count = items
                                          .where(
                                            (item) =>
                                                agendaItemCoversDay(item, date),
                                          )
                                          .length;
                                      final selected = day.day == number;
                                      return Semantics(
                                        button: true,
                                        selected: selected,
                                        label:
                                            '${material.formatFullDate(date)} · ${context.l10n.organizerCalendarScheduledCount(count)}',
                                        child: ExcludeSemantics(
                                          child: InkWell(
                                            key: ValueKey(
                                              'shared-calendar-day-${date.year}-${date.month}-$number',
                                            ),
                                            onTap: () => onSelected(date),
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                            child: Container(
                                              height: cellSize,
                                              margin: const EdgeInsets.all(1),
                                              decoration: BoxDecoration(
                                                color: selected
                                                    ? scheme.primaryContainer
                                                    : null,
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: Column(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: [
                                                  Text('$number'),
                                                  if (count > 0)
                                                    Container(
                                                      margin:
                                                          const EdgeInsets.only(
                                                            top: 4,
                                                          ),
                                                      width: 5,
                                                      height: 5,
                                                      decoration: BoxDecoration(
                                                        color: scheme.primary,
                                                        shape: BoxShape.circle,
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
          ],
        ),
      ),
    );
  }
}
