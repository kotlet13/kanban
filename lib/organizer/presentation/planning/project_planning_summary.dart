import 'package:flutter/material.dart';
import '../../../l10n/l10n.dart';
import '../../domain/organizer_models.dart';
import 'task_timer_panel.dart';
import 'project_calendar.dart';
import 'project_capacity_panel.dart';

class ProjectPlanningSummary extends StatelessWidget {
  const ProjectPlanningSummary({
    super.key,
    required this.project,
    required this.tasks,
    this.onTaskSelected,
  });
  final LocalProject project;
  final List<LocalTask> tasks;
  final ValueChanged<LocalTask>? onTaskSelected;
  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final projectTasks = tasks
        .where((task) => task.projectId == project.id)
        .toList();
    final estimate = projectTasks.fold(
      0,
      (sum, t) => sum + (t.estimateMinutes ?? 0),
    );
    final timeline = [
      if (project.startAt != null || project.endAt != null)
        (title: project.title, start: project.startAt, end: project.endAt),
      for (final p in project.phases)
        if (p.startAt != null || p.endAt != null)
          (title: p.title, start: p.startAt, end: p.endAt),
      for (final t in projectTasks)
        if (t.startAt != null || t.endAt != null || t.dueAt != null)
          (title: t.title, start: t.startAt ?? t.dueAt, end: t.endAt),
    ]..sort((a, b) => (a.start ?? a.end!).compareTo(b.start ?? b.end!));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (estimate > 0)
          Text('${l.planningEstimated}: ${planningDuration(estimate * 60)}'),
        if (project.availabilityMinutes != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '${l.planningAvailabilityMinutes}: ${project.availabilityMinutes} · ${project.availabilityPeriod == AvailabilityPeriod.day ? l.planningPerDay : l.planningPerWeek}',
            ),
          ),
        ProjectCapacityPanel(project: project, tasks: projectTasks),
        if (project.phases.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            l.planningPhases,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          for (final phase in project.phases)
            Builder(
              builder: (context) {
                final phaseTasks = projectTasks
                    .where((t) => t.phaseId == phase.id)
                    .toList();
                final done = phaseTasks.where((t) => t.isCompleted).length;
                final minutes = phaseTasks.fold(
                  0,
                  (sum, t) => sum + (t.estimateMinutes ?? 0),
                );
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    key: ValueKey('project-phase-${phase.id}'),
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        phase.title,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      if (phase.milestone.isNotEmpty) Text(phase.milestone),
                      Text(
                        '${l.organizerProjectProgress(done, phaseTasks.length)} · ${l.planningEstimated}: ${planningDuration(minutes * 60)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      for (final task in phaseTasks)
                        _taskRow(context, task, 'phase-${phase.id}'),
                      ProjectCapacityPanel(
                        project: project,
                        tasks: phaseTasks,
                        phaseId: phase.id,
                      ),
                      if (phaseTasks.isNotEmpty)
                        LinearProgressIndicator(
                          value: done / phaseTasks.length,
                        ),
                    ],
                  ),
                );
              },
            ),
        ],
        if (project.phases.isNotEmpty &&
            projectTasks.any((t) => t.phaseId == null))
          Column(
            key: const ValueKey('project-phase-unassigned'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l.planningNoPhase,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              for (final task in projectTasks.where((t) => t.phaseId == null))
                _taskRow(context, task, 'unassigned'),
            ],
          ),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: Text(l.planningCalendar),
          initiallyExpanded: timeline.isNotEmpty,
          children: [
            ProjectCalendar(
              project: project,
              tasks: projectTasks,
              onTaskSelected: onTaskSelected,
            ),
          ],
        ),
        if (estimate > 0 || project.phases.isNotEmpty || timeline.isNotEmpty)
          const SizedBox(height: 16),
      ],
    );
  }

  Widget _taskRow(
    BuildContext context,
    LocalTask task,
    String group,
  ) => Semantics(
    checked: task.isCompleted,
    child: ListTile(
      key: ValueKey('project-phase-task-$group-${task.id}'),
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        task.isCompleted ? Icons.check_circle : Icons.circle_outlined,
      ),
      title: Text(task.title),
      subtitle: task.estimateMinutes == null
          ? null
          : Text(
              '${context.l10n.planningEstimated}: ${planningDuration(task.estimateMinutes! * 60)}',
            ),
      onTap: onTaskSelected == null ? null : () => onTaskSelected!(task),
    ),
  );
}
