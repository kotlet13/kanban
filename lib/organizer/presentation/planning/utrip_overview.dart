import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../l10n/l10n.dart';
import '../../domain/all_spaces_projection.dart';
import '../../domain/utrip_projection.dart';
import '../../state/organizer_provider.dart';
import '../all_spaces/all_spaces_rows.dart';
import '../organizer_widgets.dart';
import '../desktop/desktop_layout.dart';

/// The same readable overview serves local, shared and aggregate workspaces.
/// It never creates a synthetic aggregate destination for opening or writing.
class OrganizerUtripOverview extends ConsumerWidget {
  const OrganizerUtripOverview({
    super.key,
    required this.snapshot,
    this.now,
    this.titleAccessory,
    this.onTasks,
    this.onCalendar,
    this.onProjects,
    this.onCreateTask,
    this.onCreateEvent,
    this.onCreateProject,
    this.onOpen,
    this.headerHint,
  });
  final AllSpacesSnapshot snapshot;
  final DateTime? now;
  final Widget? titleAccessory, headerHint;
  final VoidCallback? onTasks, onCalendar, onProjects;
  final VoidCallback? onCreateTask, onCreateEvent, onCreateProject;
  final ValueChanged<UtripItem>? onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final date = now ?? ref.watch(organizerClockProvider)();
    final overview = UtripProjection(snapshot, now: date);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    void open(UtripItem item) {
      if (onOpen != null) {
        onOpen!(item);
      } else {
        openAllSpacesRow(
          context,
          ref,
          AllSpacesRow(
            source: item.source,
            id: item.id,
            type: item.type,
            title: item.title,
            date: item.dueAt ?? item.startAt,
            endDate: item.endAt,
          ),
        );
      }
    }

    Widget section({
      required String title,
      required IconData icon,
      required List<UtripItem> items,
      required String empty,
      required String actionLabel,
      VoidCallback? onAction,
      String? createLabel,
      VoidCallback? onCreate,
      bool showCreateLabel = false,
    }) => _OverviewSection(
      title: title,
      icon: icon,
      items: items,
      empty: empty,
      actionLabel: actionLabel,
      onAction: onAction,
      createLabel: createLabel,
      onCreate: onCreate,
      showCreateLabel: showCreateLabel,
      onOpen: open,
      now: date,
      showSources: snapshot.sources.length > 1,
      itemLimit: organizerUsesDesktopLayout(context) ? 5 : 3,
    );

    final today = section(
      title: l.organizerTodayEvents,
      icon: Icons.event_outlined,
      items: overview.todayEvents,
      empty: l.organizerNoTodayEvents,
      actionLabel: l.organizerCalendar,
      onAction: onCalendar,
      createLabel: l.organizerAddEvent,
      onCreate: onCreateEvent,
      showCreateLabel: true,
    );
    final upcoming = section(
      title: l.organizerUpcomingWeek,
      icon: Icons.date_range_outlined,
      items: overview.upcomingEvents,
      empty: l.organizerNoUpcomingEvents,
      actionLabel: l.organizerCalendar,
      onAction: onCalendar,
    );
    final projects = section(
      title: l.organizerOngoingProjects,
      icon: Icons.folder_outlined,
      items: overview.ongoingProjects,
      empty: l.organizerNoOngoingProjects,
      actionLabel: l.organizerProjects,
      onAction: onProjects,
      createLabel: l.organizerAddProject,
      onCreate: onCreateProject,
    );
    final tasks = section(
      title: l.organizerUtripTasks,
      icon: Icons.check_circle_outline,
      items: overview.dueTasks,
      empty: l.organizerUtripNoTasks,
      actionLabel: l.organizerAllTasks,
      onAction: onTasks,
      createLabel: l.organizerAddTask,
      onCreate: onCreateTask,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            ExcludeSemantics(
              child: Icon(
                Icons.wb_sunny_outlined,
                color: colors.primary,
                size: 20,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                organizerDate(context, date.toLocal(), full: true),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Semantics(
                header: true,
                child: Text(
                  l.organizerPulse,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -.6,
                  ),
                ),
              ),
            ),
            if (titleAccessory != null) titleAccessory!,
          ],
        ),
        const SizedBox(height: 8),
        Text(
          l.organizerUtripIntro,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
        if (headerHint != null) headerHint!,
        const SizedBox(height: 28),
        LayoutBuilder(
          builder: (context, constraints) =>
              constraints.maxWidth >=
                  (organizerUsesDesktopLayout(context)
                      ? 840 *
                            (MediaQuery.textScalerOf(context).scale(14) / 14)
                                .clamp(1, 1.5)
                      : 840)
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        children: [today, const SizedBox(height: 20), upcoming],
                      ),
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      child: Column(
                        children: [projects, const SizedBox(height: 20), tasks],
                      ),
                    ),
                  ],
                )
              : Column(
                  children: [
                    today,
                    const SizedBox(height: 20),
                    upcoming,
                    const SizedBox(height: 20),
                    projects,
                    const SizedBox(height: 20),
                    tasks,
                  ],
                ),
        ),
      ],
    );
  }
}

class _OverviewSection extends StatelessWidget {
  const _OverviewSection({
    required this.title,
    required this.icon,
    required this.items,
    required this.empty,
    required this.actionLabel,
    required this.onOpen,
    required this.now,
    required this.showSources,
    this.itemLimit = 3,
    this.onAction,
    this.createLabel,
    this.onCreate,
    this.showCreateLabel = false,
  });
  final String title, empty, actionLabel;
  final String? createLabel;
  final IconData icon;
  final List<UtripItem> items;
  final VoidCallback? onAction, onCreate;
  final ValueChanged<UtripItem> onOpen;
  final DateTime now;
  final bool showSources, showCreateLabel;
  final int itemLimit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Material(
      color: colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                ExcludeSemantics(
                  child: Icon(icon, size: 20, color: colors.primary),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                if (onCreate != null && !showCreateLabel)
                  IconButton(
                    tooltip: createLabel,
                    constraints: const BoxConstraints(
                      minWidth: 48,
                      minHeight: 48,
                    ),
                    onPressed: onCreate,
                    icon: const Icon(Icons.add, size: 20),
                  ),
              ],
            ),
            if (onCreate != null && showCreateLabel)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: onCreate,
                  icon: const Icon(Icons.add, size: 20),
                  label: Text(createLabel!),
                ),
              ),
            const SizedBox(height: 12),
            if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  empty,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
            for (final item in items.take(itemLimit))
              _OverviewRow(
                item: item,
                now: now,
                showSource: showSources,
                onOpen: () => onOpen(item),
              ),
            if (onAction != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                  onPressed: onAction,
                  child: Text(actionLabel),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _OverviewRow extends StatelessWidget {
  const _OverviewRow({
    required this.item,
    required this.onOpen,
    required this.now,
    required this.showSource,
  });
  final UtripItem item;
  final VoidCallback onOpen;
  final DateTime now;
  final bool showSource;

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _dateTime(BuildContext context, DateTime date) {
    final local = date.toLocal();
    final locale = Localizations.localeOf(context).toLanguageTag();
    return '${DateFormat.MMMEd(locale).format(local)} · ${DateFormat.Hm(locale).format(local)}';
  }

  String _when(BuildContext context) {
    final l = context.l10n;
    if (item.type == 'event') {
      final start = item.startAt!.toLocal();
      final end = item.endAt?.toLocal();
      final locale = Localizations.localeOf(context).toLanguageTag();
      final time = DateFormat.Hm(locale).format(start);
      if (end == null || _sameDay(start, end)) {
        final range = end == null
            ? time
            : '$time–${DateFormat.Hm(locale).format(end)}';
        return _sameDay(start, now.toLocal())
            ? range
            : '${DateFormat.MMMEd(locale).format(start)} · $range';
      }
      return '${_dateTime(context, start)} – ${_dateTime(context, end)}';
    }
    return [
      if (item.startAt != null)
        '${l.planningStart}: ${organizerDate(context, item.startAt!.toLocal())}',
      if (item.endAt != null)
        '${l.planningEnd}: ${organizerDate(context, item.endAt!.toLocal())}',
      if (item.dueAt != null)
        '${l.planningDue}: ${organizerDate(context, item.dueAt!.toLocal())}',
    ].join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final when = _when(context);
    return Semantics(
      button: true,
      child: InkWell(
        key: ValueKey('utrip-${item.source.key}-${item.type}-${item.id}'),
        onTap: onOpen,
        borderRadius: BorderRadius.circular(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 2),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (showSource || when.isNotEmpty) ...[
                        const SizedBox(height: 5),
                        Text(
                          [
                            if (showSource)
                              allSpacesSourceLabel(context, item.source),
                            if (when.isNotEmpty) when,
                          ].join('\n'),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                ExcludeSemantics(
                  child: Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
