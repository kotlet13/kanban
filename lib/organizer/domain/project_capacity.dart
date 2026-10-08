import 'organizer_models.dart';

class ProjectCapacityEstimate {
  const ProjectCapacityEstimate({
    required this.taskCount,
    required this.openTaskCount,
    required this.remainingSeconds,
    required this.missingEstimates,
    required this.missingAvailability,
    required this.estimatedDays,
  });
  final int taskCount, openTaskCount, remainingSeconds;
  final int missingEstimates, missingAvailability;
  final double? estimatedDays;
}

/// Tasks run in sequence. An explicit task capacity overrides project capacity;
/// inherited capacity is shared, rather than multiplied by the task count.
/// Weekly capacity is an average over seven days, not a working-day calendar.
/// No calendar dates or stored records are changed by this projection.
ProjectCapacityEstimate estimateProjectCapacity(
  LocalProject project,
  Iterable<LocalTask> tasks, {
  String? phaseId,
  required DateTime now,
}) {
  final selected = tasks
      .where(
        (task) =>
            task.projectId == project.id &&
            (phaseId == null || task.phaseId == phaseId),
      )
      .toList();
  final open = selected.where((task) => !task.isCompleted).toList();
  var missingEstimates = 0, missingAvailability = 0, remainingSeconds = 0;
  var days = 0.0;
  for (final task in open) {
    final minutes = task.availabilityMinutes ?? project.availabilityMinutes;
    final period = task.availabilityMinutes == null
        ? project.availabilityPeriod
        : task.availabilityPeriod;
    final hasCapacity = minutes != null && minutes > 0 && period != null;
    if (task.estimateMinutes == null) {
      missingEstimates++;
      if (!hasCapacity) {
        missingAvailability++;
      }
      continue;
    }
    final remaining = task.timer.remainingAt(task.estimateMinutes, now);
    remainingSeconds += remaining;
    if (remaining == 0) {
      continue;
    }
    if (!hasCapacity) {
      missingAvailability++;
      continue;
    }
    days +=
        remaining /
        (minutes * 60) *
        (period == AvailabilityPeriod.week ? 7 : 1);
  }
  return ProjectCapacityEstimate(
    taskCount: selected.length,
    openTaskCount: open.length,
    remainingSeconds: remainingSeconds,
    missingEstimates: missingEstimates,
    missingAvailability: missingAvailability,
    estimatedDays: missingEstimates == 0 && missingAvailability == 0
        ? days
        : null,
  );
}
