import 'all_spaces_projection.dart';

/// A read-only overview keeps the concrete source alongside each record.
class UtripItem {
  const UtripItem({
    required this.source,
    required this.id,
    required this.type,
    required this.title,
    this.startAt,
    this.endAt,
    this.dueAt,
  });
  final AllSpacesSource source;
  final String id, type, title;
  final DateTime? startAt, endAt, dueAt;
}

class UtripProjection {
  UtripProjection(AllSpacesSnapshot snapshot, {required DateTime now}) {
    final local = now.toLocal();
    final today = DateTime(local.year, local.month, local.day);
    final tomorrow = DateTime(local.year, local.month, local.day + 1);
    final weekEnd = DateTime(local.year, local.month, local.day + 8);
    final events = <UtripItem>[
      for (final row in snapshot.localEvents)
        UtripItem(
          source: row.source,
          id: row.value.id,
          type: 'event',
          title: row.value.title,
          startAt: row.value.startsAt,
          endAt: row.value.endsAt,
        ),
      for (final row in snapshot.sharedEvents)
        UtripItem(
          source: row.source,
          id: row.value.id,
          type: 'event',
          title: row.value.title,
          startAt: row.value.startAt,
          endAt: row.value.endAt,
        ),
    ]..sort(_chronological);
    // End timestamps are exclusive: an event ending at midnight belongs to
    // the previous day. Events without an end belong to their start day.
    todayEvents = List.unmodifiable(
      events.where((event) {
        final start = event.startAt!.toLocal();
        final end = event.endAt?.toLocal();
        return start.isBefore(tomorrow) &&
            (end != null && end.isAfter(start)
                ? end.isAfter(today)
                : !start.isBefore(today));
      }),
    );
    // Multi-day events already under Today are not duplicated in Coming up.
    upcomingEvents = List.unmodifiable(
      events.where((event) {
        final start = event.startAt!.toLocal();
        return !start.isBefore(tomorrow) && start.isBefore(weekEnd);
      }),
    );
    ongoingProjects = List.unmodifiable(
      <UtripItem>[
        for (final row in snapshot.projects)
          if ((row.value.startAt == null ||
                  row.value.startAt!.toLocal().isBefore(tomorrow)) &&
              (row.value.endAt == null ||
                  !row.value.endAt!.toLocal().isBefore(today)))
            UtripItem(
              source: row.source,
              id: row.value.id,
              type: 'project',
              title: row.value.title,
              startAt: row.value.startAt,
              endAt: row.value.endAt,
            ),
      ]..sort((a, b) {
        final aEnd = a.endAt, bEnd = b.endAt;
        if (aEnd != null && bEnd != null) {
          final order = aEnd.compareTo(bEnd);
          if (order != 0) return order;
        } else if (aEnd != null) {
          return -1;
        } else if (bEnd != null) {
          return 1;
        }
        return _identity(a).compareTo(_identity(b));
      }),
    );
    dueTasks = List.unmodifiable(
      <UtripItem>[
        for (final row in snapshot.tasks)
          if (!row.value.isCompleted &&
              ((row.value.dueAt != null &&
                      row.value.dueAt!.toLocal().isBefore(tomorrow)) ||
                  (row.value.startAt != null &&
                      row.value.startAt!.toLocal().isBefore(tomorrow) &&
                      (row.value.endAt == null ||
                          row.value.endAt!.toLocal().isAfter(today)))))
            UtripItem(
              source: row.source,
              id: row.value.id,
              type: 'task',
              title: row.value.title,
              startAt: row.value.startAt,
              endAt: row.value.endAt,
              dueAt: row.value.dueAt,
            ),
      ]..sort(_chronological),
    );
  }

  late final List<UtripItem> todayEvents,
      upcomingEvents,
      ongoingProjects,
      dueTasks;
}

String _identity(UtripItem item) =>
    '${item.title.toLowerCase()}:${item.source.key}:${item.id}';

int _chronological(UtripItem a, UtripItem b) {
  final aDate = a.dueAt ?? a.startAt, bDate = b.dueAt ?? b.startAt;
  if (aDate != null && bDate != null) {
    final order = aDate.compareTo(bDate);
    if (order != 0) return order;
  } else if (aDate != null) {
    return -1;
  } else if (bDate != null) {
    return 1;
  }
  return _identity(a).compareTo(_identity(b));
}
