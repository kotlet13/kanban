import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../l10n/l10n.dart';
import '../../state/all_spaces_provider.dart';
import '../../state/organizer_provider.dart';
import '../organizer_widgets.dart';
import 'all_spaces_rows.dart';
import 'all_spaces_area.dart';
import 'all_spaces_payments.dart';
export 'all_spaces_area.dart';

/// Aggregate presentation never becomes the write target. Opening a row uses
/// its captured source; creating first switches to an explicitly chosen space.
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
  });
  final AllSpacesSnapshot? snapshot;
  final String? subtitle;
  final bool allowCreation, showDescription;
  final Widget? titleAccessory;
  final Future<void> Function(AllSpacesSource source)? onCreateSource;
  final bool Function(AllSpacesSource source)? canCreateInSource;
  final AllSpacesArea area;
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
      if (widget.onCreateSource != null) {
        await widget.onCreateSource!(source);
      } else {
        await widget.onSource(source, widget.area, null);
      }
    }
  }

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
        final rows = allSpacesRows(
          snapshot,
          widget.area,
          now: now,
          showCompleted: _showCompleted,
          month: _month,
          currency: _currency,
        );
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
                      label: Text(l.allSpacesAdd),
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
            if (widget.area == AllSpacesArea.finances ||
                widget.area == AllSpacesArea.calendar)
              _period(context),
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
            if (rows.isEmpty)
              OrganizerEmpty(
                icon: Icons.layers_outlined,
                title: widget.area == AllSpacesArea.today
                    ? l.allSpacesTodayEmpty
                    : l.allSpacesEmpty,
              ),
            for (final row in rows)
              AllSpacesRowTile(
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
