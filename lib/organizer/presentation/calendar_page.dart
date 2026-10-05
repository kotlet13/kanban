import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../l10n/l10n.dart';
import '../domain/organizer_models.dart';
import 'organizer_actions.dart';
import 'organizer_widgets.dart';

class OrganizerCalendarPage extends StatefulWidget {
  const OrganizerCalendarPage({
    super.key,
    required this.snapshot,
    required this.actions,
  });
  final OrganizerSnapshot snapshot;
  final OrganizerActions actions;
  @override
  State<OrganizerCalendarPage> createState() => _OrganizerCalendarPageState();
}

class _OrganizerCalendarPageState extends State<OrganizerCalendarPage> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime? _selected;
  bool _sameDay(DateTime a, DateTime b) {
    final x = a.toLocal();
    final y = b.toLocal();
    return x.year == y.year && x.month == y.month && x.day == y.day;
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final now = DateTime.now();
    final events =
        widget.snapshot.events
            .where(
              (e) => _selected != null
                  ? _sameDay(e.startsAt, _selected!)
                  : (e.endsAt ?? e.startsAt).isAfter(
                      DateTime(now.year, now.month, now.day),
                    ),
            )
            .toList()
          ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    final tasks =
        widget.snapshot.tasks
            .where(
              (t) =>
                  !t.isCompleted &&
                  t.dueAt != null &&
                  (_selected == null || _sameDay(t.dueAt!, _selected!)),
            )
            .toList()
          ..sort((a, b) => a.dueAt!.compareTo(b.dueAt!));
    final agenda = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OrganizerSection(
          title: _selected == null
              ? l.organizerUpcoming
              : organizerDate(context, _selected!, full: true),
          action: _selected == null
              ? null
              : IconButton(
                  tooltip: l.organizerUpcoming,
                  onPressed: () => setState(() => _selected = null),
                  icon: const Icon(Icons.close),
                ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (events.isEmpty)
                OrganizerEmpty(
                  icon: Icons.event_outlined,
                  title: l.organizerNoEvents,
                  action: l.organizerAddEvent,
                  onAction: () => widget.actions.event(),
                ),
              for (final event in events)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: OrganizerEventCard(
                    event: event,
                    onTap: () => widget.actions.event(event),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        if (tasks.isNotEmpty)
          OrganizerSection(
            title: l.organizerTasks,
            child: Column(
              children: [
                for (final task in tasks)
                  OrganizerTaskRow(
                    task: task,
                    snapshot: widget.snapshot,
                    onEdit: () => widget.actions.task(task: task),
                    onCompleted: (v) => widget.actions.run(
                      () => widget.actions.controller.setTaskCompleted(
                        task.id,
                        v,
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OrganizerHeading(
          title: l.organizerCalendar,
          subtitle: l.organizerCalendarIntro,
          action: FilledButton.icon(
            onPressed: () => widget.actions.event(),
            icon: const Icon(Icons.add, size: 18),
            label: Text(l.organizerAddEvent),
          ),
        ),
        LayoutBuilder(
          builder: (context, constraints) => constraints.maxWidth >= 760
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 360, child: _calendar()),
                    const SizedBox(width: 30),
                    Expanded(child: agenda),
                  ],
                )
              : Column(
                  children: [_calendar(), const SizedBox(height: 24), agenda],
                ),
        ),
      ],
    );
  }

  Widget _calendar() {
    final locale = Localizations.localeOf(context).toLanguageTag();
    final firstOffset = (_month.weekday + 6) % 7;
    final count = DateTime(_month.year, _month.month + 1, 0).day;
    final cells = ((firstOffset + count + 6) ~/ 7) * 7;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: MaterialLocalizations.of(
                    context,
                  ).previousMonthTooltip,
                  onPressed: () => setState(
                    () => _month = DateTime(_month.year, _month.month - 1),
                  ),
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: Text(
                    DateFormat.yMMMM(locale).format(_month),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: MaterialLocalizations.of(context).nextMonthTooltip,
                  onPressed: () => setState(
                    () => _month = DateTime(_month.year, _month.month + 1),
                  ),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                for (var i = 0; i < 7; i++)
                  Expanded(
                    child: Center(
                      child: Text(
                        DateFormat.E(locale).format(DateTime(2024, 1, 1 + i)),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: cells,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
              ),
              itemBuilder: (context, index) {
                final day = index - firstOffset + 1;
                if (day < 1 || day > count) return const SizedBox.shrink();
                final date = DateTime(_month.year, _month.month, day);
                final marked =
                    widget.snapshot.events.any(
                      (e) => _sameDay(e.startsAt, date),
                    ) ||
                    widget.snapshot.tasks.any(
                      (t) =>
                          !t.isCompleted &&
                          t.dueAt != null &&
                          _sameDay(t.dueAt!, date),
                    );
                final selected =
                    _selected != null && _sameDay(_selected!, date);
                final today = _sameDay(DateTime.now(), date);
                return Semantics(
                  label: organizerDate(context, date, full: true),
                  selected: selected,
                  button: true,
                  child: InkWell(
                    onTap: () => setState(() => _selected = date),
                    borderRadius: BorderRadius.circular(9),
                    child: Container(
                      margin: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: selected ? scheme.primaryContainer : null,
                        borderRadius: BorderRadius.circular(9),
                        border: today
                            ? Border.all(color: scheme.primary)
                            : null,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '$day',
                            style: TextStyle(
                              color: selected || today ? scheme.primary : null,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Container(
                            width: 4,
                            height: 4,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: marked
                                  ? scheme.primary
                                  : Colors.transparent,
                            ),
                          ),
                        ],
                      ),
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
