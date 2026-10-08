import 'organizer_models.dart';

enum ProjectCalendarKind { project, phase, task }

class ProjectCalendarItem {
  const ProjectCalendarItem({
    required this.id,
    required this.title,
    required this.kind,
    this.start,
    this.end,
    this.due,
    this.inclusiveEnd = false,
  });
  final String id, title;
  final ProjectCalendarKind kind;
  final DateTime? start, end, due;
  final bool inclusiveEnd;
  bool covers(DateTime day) {
    final date = DateTime(day.year, day.month, day.day),
        next = DateTime(day.year, day.month, day.day + 1);
    bool sameDay(DateTime value) {
      final local = value.toLocal();
      return local.year == day.year &&
          local.month == day.month &&
          local.day == day.day;
    }

    if (due != null && sameDay(due!)) return true;
    if (start == null && end == null) return false;
    if (start == null) return sameDay(end!);
    if (end == null || end == start) return sameDay(start!);
    final a = start!.toLocal(), b = end!.toLocal();
    final last = inclusiveEnd ? DateTime(b.year, b.month, b.day + 1) : b;
    return a.isBefore(next) && last.isAfter(date);
  }
}

List<ProjectCalendarItem> projectCalendarItems(
  LocalProject project,
  Iterable<LocalTask> tasks,
) => [
  if (project.startAt != null || project.endAt != null)
    ProjectCalendarItem(
      id: project.id,
      title: project.title,
      kind: ProjectCalendarKind.project,
      start: project.startAt,
      end: project.endAt,
    ),
  for (final p in project.phases)
    if (p.startAt != null || p.endAt != null)
      ProjectCalendarItem(
        id: p.id,
        title: p.title,
        kind: ProjectCalendarKind.phase,
        start: p.startAt,
        end: p.endAt,
        inclusiveEnd: true,
      ),
  for (final t in tasks.where((t) => t.projectId == project.id))
    if (t.startAt != null || t.endAt != null || t.dueAt != null)
      ProjectCalendarItem(
        id: t.id,
        title: t.title,
        kind: ProjectCalendarKind.task,
        start: t.startAt,
        end: t.endAt,
        due: t.dueAt,
      ),
];
