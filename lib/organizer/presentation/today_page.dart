import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../domain/organizer_models.dart';
import 'organizer_actions.dart';
import 'organizer_widgets.dart';
import 'onboarding/getting_started.dart';

class OrganizerTodayPage extends StatelessWidget {
  const OrganizerTodayPage({
    super.key,
    required this.snapshot,
    required this.actions,
    required this.onShopping,
    this.showShopping = true,
    required this.onPlans,
    required this.onSharedAgenda,
    this.onGettingStarted,
  });
  final OrganizerSnapshot snapshot;
  final OrganizerActions actions;
  final VoidCallback onShopping;
  final bool showShopping;
  final VoidCallback onPlans;
  final ValueChanged<String> onSharedAgenda;
  final VoidCallback? onGettingStarted;
  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final now = DateTime.now();
    final events =
        snapshot.events
            .where((e) => (e.endsAt ?? e.startsAt).isAfter(now))
            .toList()
          ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    final tasks = snapshot.tasks.where((t) => !t.isCompleted).toList()
      ..sort((a, b) {
        if (a.dueAt == null && b.dueAt == null) {
          return a.createdAt.compareTo(b.createdAt);
        }
        if (a.dueAt == null) return 1;
        if (b.dueAt == null) return -1;
        return a.dueAt!.compareTo(b.dueAt!);
      });
    final nextEvent = OrganizerSection(
      title: l.organizerNextEvent,
      child: events.isEmpty
          ? OrganizerEmpty(
              icon: Icons.event_outlined,
              title: l.organizerNoEvents,
              description: l.organizerNoEventsDescription,
              action: l.organizerAddEvent,
              onAction: () => actions.event(),
            )
          : OrganizerEventCard(
              event: events.first,
              onTap: () => actions.event(events.first),
            ),
    );
    final nextTasks = OrganizerSection(
      title: l.organizerNextTasks,
      action: tasks.isEmpty
          ? null
          : IconButton(
              tooltip: l.organizerAddTask,
              onPressed: () => actions.task(),
              icon: const Icon(Icons.add),
            ),
      child: tasks.isEmpty
          ? OrganizerEmpty(
              icon: Icons.check_circle_outline,
              title: l.organizerNoTasks,
              description: l.organizerNoTasksDescription,
              action: l.organizerAddTask,
              onAction: () => actions.task(),
            )
          : Column(
              children: [
                for (final task in tasks.take(
                  MediaQuery.sizeOf(context).width >= 1100 ? 5 : 3,
                ))
                  OrganizerTaskRow(
                    task: task,
                    snapshot: snapshot,
                    onEdit: () => actions.task(task: task),
                    onCompleted: (v) => actions.run(
                      () => actions.controller.setTaskCompleted(task.id, v),
                    ),
                  ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: onPlans,
                    child: Text(l.organizerAllTasks),
                  ),
                ),
              ],
            ),
    );
    final shopping = Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: InkWell(
        onTap: onShopping,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Icon(
                Icons.shopping_bag_outlined,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.organizerShoppingShortcut,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 5),
                    Text(
                      l.organizerShoppingCount(
                        snapshot.shoppingItems
                            .where((i) => !i.isChecked)
                            .length,
                      ),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: Theme.of(context).colorScheme.primary,
              ),
            ],
          ),
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          organizerDate(context, now, full: true),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        OrganizerHeading(
          title: l.organizerToday,
          subtitle: l.organizerTodayIntro,
        ),
        if (onGettingStarted != null)
          GettingStartedHint(onStart: onGettingStarted!),

        LayoutBuilder(
          builder: (context, constraints) => constraints.maxWidth >= 820
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 5, child: nextTasks),
                    const SizedBox(width: 32),
                    Expanded(
                      flex: 4,
                      child: Column(
                        children: [
                          nextEvent,
                          if (showShopping) ...[
                            const SizedBox(height: 24),
                            shopping,
                          ],
                        ],
                      ),
                    ),
                  ],
                )
              : Column(
                  children: [
                    nextEvent,
                    const SizedBox(height: 24),
                    nextTasks,
                    if (showShopping) ...[const SizedBox(height: 24), shopping],
                  ],
                ),
        ),
      ],
    );
  }
}
