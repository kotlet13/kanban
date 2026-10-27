import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../l10n/l10n.dart';
import '../../state/all_spaces_provider.dart';
import '../../domain/organizer_models.dart' show ProjectArea;
import '../../state/organizer_provider.dart';
import '../organizer_widgets.dart';
import '../planning/utrip_overview.dart';
import '../planning/agenda_month_calendar.dart';
import '../../domain/organizer_projections.dart';
import 'all_spaces_rows.dart';
import 'all_spaces_area.dart';
import 'all_spaces_payments.dart';
export 'all_spaces_area.dart';

/// Aggregate presentation never becomes the write target. Opening a row uses
/// its captured source; creating uses the selected space or an explicit choice.
class AllSpacesPage extends ConsumerStatefulWidget {
  const AllSpacesPage({
    super.key,
    required this.area,
    required this.onSource,
    this.snapshot,
    this.subtitle,
    this.allowCreation = true,
    this.showDescription = true,
    this.titleAccessory,
    this.onCreateSource,
    this.canCreateInSource,
    this.onOverviewArea,
    this.creationScopeId,
  });

  /// A concrete selected space remains the write target of its aggregate.
  final String? creationScopeId;
  final AllSpacesSnapshot? snapshot;
  final String? subtitle;
  final bool allowCreation, showDescription;
  final Widget? titleAccessory;
  final Future<void> Function(AllSpacesSource source)? onCreateSource;
  final bool Function(AllSpacesSource source)? canCreateInSource;
  final AllSpacesArea area;
  final ValueChanged<AllSpacesArea>? onOverviewArea;
  final Future<void> Function(
    AllSpacesSource source,
    AllSpacesArea area,
    String? id,
  )
  onSource;
  @override
  ConsumerState<AllSpacesPage> createState() => _AllSpacesPageState();
}

class _AllSpacesPageState extends ConsumerState<AllSpacesPage> {
  DateTime? _month;
  String? _currency;
  bool _showCompleted = false;
  bool _calendar = true;
  DateTime? _day;

  String _title(BuildContext context) => switch (widget.area) {
    AllSpacesArea.today => context.l10n.organizerToday,
    AllSpacesArea.tasks => context.l10n.organizerTasks,
    AllSpacesArea.calendar => context.l10n.organizerCalendar,
    AllSpacesArea.projects => context.l10n.organizerProjects,
    AllSpacesArea.shopping => context.l10n.organizerShopping,
    AllSpacesArea.finances => context.l10n.organizerFinances,
    AllSpacesArea.home => context.l10n.organizerHome,
    AllSpacesArea.people => context.l10n.peopleTitle,
  };

  Future<void> _chooseTarget(AllSpacesSnapshot snapshot) async {
    final selectedScope = widget.creationScopeId;
    if (selectedScope != null) {
      final selected = snapshot.sources
          .where((source) => source.scopeId == selectedScope)
          .firstOrNull;
      // A stale or read-only selection must not redirect a write to a child.
      if (selected == null ||
          widget.canCreateInSource?.call(selected) == false) {
        return;
      }
      await _create(selected);
      return;
    }
    final source = await showDialog<AllSpacesSource>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(context.l10n.allSpacesChooseTarget),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
            child: Text(context.l10n.allSpacesChooseTargetDescription),
          ),
          for (final source in snapshot.sources.where(
            (source) => widget.canCreateInSource?.call(source) ?? true,
          ))
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, source),
              child: Text(allSpacesSourceLabel(context, source)),
            ),
        ],
      ),
    );
    if (source != null && mounted) {
      await _create(source);
    }
  }

  Future<void> _create(AllSpacesSource source) async {
    if (widget.onCreateSource != null) {
      await widget.onCreateSource!(source);
    } else {
      await widget.onSource(source, widget.area, null);
    }
  }

  AgendaItem _calendarItem(AllSpacesRow row) => AgendaItem(
    type: row.type,
    id: row.id,
    title: row.title,
    startAt: (row.startDate ?? (row.type == 'event' ? row.date : null))
        ?.toLocal(),
    endAt: row.endDate?.toLocal(),
    dueAt: row.type == 'task' ? row.date?.toLocal() : null,
    isCompleted: row.completed,
  );

  Future<void> _open(AllSpacesRow row) async {
    if (!allSpacesSourceIsCurrent(ref, row.source)) return;
    if (row.type == 'person' ||
        row.type == 'shoppingList' ||
        row.type == 'project') {
      await widget.onSource(row.source, switch (row.type) {
        'person' => AllSpacesArea.people,
        'shoppingList' => AllSpacesArea.shopping,
        _ =>
          widget.area == AllSpacesArea.home
              ? AllSpacesArea.home
              : AllSpacesArea.projects,
      }, row.id);
      return;
    }
    await openAllSpacesRow(context, ref, row);
  }

  Widget _period(BuildContext context) {
    final l = context.l10n;
    final month = _month;
    return Wrap(
      spacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        IconButton(
          tooltip: MaterialLocalizations.of(context).previousMonthTooltip,
          onPressed: () => setState(() {
            final date = month ?? ref.read(organizerClockProvider)();
            _month = DateTime(date.year, date.month - 1);
          }),
          icon: const Icon(Icons.chevron_left),
        ),
        Text(
          month == null
              ? l.allSpacesAllDates
              : DateFormat.yMMMM(
                  Localizations.localeOf(context).toLanguageTag(),
                ).format(month),
        ),
        IconButton(
          tooltip: MaterialLocalizations.of(context).nextMonthTooltip,
          onPressed: () => setState(() {
            final date = month ?? ref.read(organizerClockProvider)();
            _month = DateTime(date.year, date.month + 1);
          }),
          icon: const Icon(Icons.chevron_right),
        ),
        if (month != null)
          TextButton(
            onPressed: () => setState(() => _month = null),
            child: Text(l.allSpacesAllDates),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.snapshot == null
        ? ref.watch(allSpacesProvider)
        : AsyncData(widget.snapshot!);
    final now = ref.watch(organizerClockProvider)();
    final l = context.l10n;
    return value.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => Text(l.organizerLoadError),
      data: (snapshot) {
        if (widget.area == AllSpacesArea.today) {
          return OrganizerUtripOverview(
            snapshot: snapshot,
            now: now,
            titleAccessory: widget.titleAccessory,
            onTasks: widget.onOverviewArea == null
                ? null
                : () => widget.onOverviewArea!(AllSpacesArea.tasks),
            onCalendar: widget.onOverviewArea == null
                ? null
                : () => widget.onOverviewArea!(AllSpacesArea.calendar),
            onProjects: widget.onOverviewArea == null
                ? null
                : () => widget.onOverviewArea!(AllSpacesArea.projects),
            onCreateTask: widget.allowCreation
                ? () => _chooseTarget(snapshot)
                : null,
            onOpen: (item) => _open(
              AllSpacesRow(
                source: item.source,
                id: item.id,
                type: item.type,
                title: item.title,
                date: item.dueAt ?? item.startAt,
                endDate: item.endAt,
              ),
            ),
          );
        }
        final rows = allSpacesRows(
          snapshot,
          widget.area,
          now: now,
          showCompleted: _showCompleted,
          month: widget.area == AllSpacesArea.calendar && _calendar
              ? null
              : _month,
          currency: _currency,
        );
        final calendarItems = widget.area == AllSpacesArea.calendar
            ? [for (final row in rows) _calendarItem(row)]
            : <AgendaItem>[];
        final selectedDay = _day ?? now;
        final visibleRows = widget.area == AllSpacesArea.calendar && _calendar
            ? rows
                  .where(
                    (row) =>
                        agendaItemCoversDay(_calendarItem(row), selectedDay),
                  )
                  .toList()
            : rows;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OrganizerHeading(
              title: _title(context),
              titleAccessory: widget.titleAccessory,
              subtitle: !widget.showDescription
                  ? null
                  : widget.subtitle ??
                        (widget.area == AllSpacesArea.finances
                            ? l.allSpacesFinanceDescription
                            : l.allSpacesDescription),
              action: !widget.allowCreation
                  ? null
                  : OutlinedButton.icon(
                      onPressed: () => _chooseTarget(snapshot),
                      icon: const Icon(Icons.add),
                      label: Text(
                        widget.creationScopeId == null
                            ? l.allSpacesAdd
                            : switch (widget.area) {
                                AllSpacesArea.calendar => l.organizerAddEvent,
                                AllSpacesArea.finances => l.organizerAddFinance,
                                _ => l.organizerAddTask,
                              },
                      ),
                    ),
            ),
            if (widget.area == AllSpacesArea.tasks) ...[
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: Text(l.organizerTasks),
                    selected: !_showCompleted,
                    onSelected: (_) => setState(() => _showCompleted = false),
                  ),
                  ChoiceChip(
                    label: Text(l.organizerCompleted),
                    selected: _showCompleted,
                    onSelected: (_) => setState(() => _showCompleted = true),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
            if (widget.area == AllSpacesArea.calendar) ...[
              SegmentedButton<bool>(
                key: const ValueKey('aggregate-calendar-view'),
                segments: [
                  ButtonSegment(
                    value: true,
                    icon: const Icon(Icons.calendar_month_outlined),
                    label: Text(l.organizerCalendar),
                  ),
                  ButtonSegment(
                    value: false,
                    icon: const Icon(Icons.view_list_outlined),
                    label: Text(l.planningTimeline),
                  ),
                ],
                selected: {_calendar},
                onSelectionChanged: (selection) =>
                    setState(() => _calendar = selection.single),
              ),
              const SizedBox(height: 12),
              if (_calendar) ...[
                AgendaMonthCalendar(
                  day: selectedDay,
                  items: calendarItems,
                  onSelected: (day) => setState(() {
                    _day = day;
                    _month = null;
                  }),
                ),
                Text(organizerDate(context, selectedDay, full: true)),
                const SizedBox(height: 12),
              ] else
                _period(context),
            ],
            if (widget.area == AllSpacesArea.finances) _period(context),
            if (widget.area == AllSpacesArea.finances) ...[
              if (snapshot.sources.any(
                (source) => source.canReadFinance && !source.financeComplete,
              )) ...[
                Text(l.allSpacesFinanceIncomplete),
                for (final source in snapshot.sources.where(
                  (source) => source.canReadFinance && !source.financeComplete,
                ))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(allSpacesSourceLabel(context, source)),
                    subtitle: Text(l.financeLoadingSnapshot),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () =>
                        widget.onSource(source, AllSpacesArea.finances, null),
                  ),
              ],
              AllSpacesPayments(snapshot: snapshot, onSource: widget.onSource),
              AllSpacesFinanceSummary(
                snapshot: snapshot,
                month: _month,
                currency: _currency,
                onCurrency: (currency) => setState(() => _currency = currency),
              ),
              const SizedBox(height: 12),
            ],
            if (visibleRows.isEmpty)
              OrganizerEmpty(
                icon: Icons.layers_outlined,
                title: widget.area == AllSpacesArea.calendar && _calendar
                    ? l.planningNoAgenda
                    : widget.area == AllSpacesArea.today
                    ? l.allSpacesTodayEmpty
                    : l.allSpacesEmpty,
              ),
            if ((widget.area == AllSpacesArea.projects ||
                    widget.area == AllSpacesArea.home) &&
                snapshot.archivedProjects.any(
                  (p) =>
                      widget.area != AllSpacesArea.home ||
                      p.value.area == ProjectArea.home,
                ))
              ExpansionTile(
                key: ValueKey('all-spaces-archived-projects-${widget.area}'),
                title: Text(l.scopeArchivedSection),
                children: [
                  for (final project in snapshot.archivedProjects.where(
                    (p) =>
                        widget.area != AllSpacesArea.home ||
                        p.value.area == ProjectArea.home,
                  ))
                    AllSpacesRowTile(
                      row: AllSpacesRow(
                        source: project.source,
                        id: project.value.id,
                        type: 'project',
                        title: project.value.title,
                      ),
                      onOpen: () => widget.onSource(
                        project.source,
                        widget.area,
                        project.value.id,
                      ),
                      onSource: () => widget.onSource(
                        project.source,
                        widget.area,
                        project.value.id,
                      ),
                    ),
                ],
              ),
            for (final row in visibleRows)
              AllSpacesRowTile(
                key: ValueKey(
                  'all-tile-${row.source.key}-${row.type}-${row.id}',
                ),
                row: row,
                onOpen: () => _open(row),
                onSource: () =>
                    widget.onSource(row.source, widget.area, row.id),
              ),
          ],
        );
      },
    );
  }
}
