import 'organizer_models.dart';
import 'finance_reminder_plans.dart';
import 'collaboration_models.dart';

class AgendaItem {
  AgendaItem({
    required this.type,
    required this.id,
    required this.title,
    this.scopeId,
    this.projectId,
    this.startAt,
    this.endAt,
    this.dueAt,
    Iterable<String> assigneeAccountIds = const [],
    this.isCompleted = false,
  }) : assigneeAccountIds = List.unmodifiable(assigneeAccountIds);
  final String type, id, title;
  final String? scopeId, projectId;
  final DateTime? startAt, endAt, dueAt;
  final List<String> assigneeAccountIds;
  final bool isCompleted;
  DateTime? get sortAt => startAt ?? dueAt ?? endAt;
}

List<AgendaItem> projectTimeline(
  SharedScopeData data, {
  required String scopeId,
  String? projectId,
}) {
  final items = <AgendaItem>[
    for (final p in data.projects.where(
      (p) => projectId == null || p.id == projectId,
    ))
      AgendaItem(
        type: 'project',
        id: p.id,
        title: p.title,
        scopeId: scopeId,
        projectId: p.id,
        startAt: p.startAt,
        endAt: p.endAt,
      ),
    for (final t in data.tasks.where(
      (t) => projectId == null || t.projectId == projectId,
    ))
      AgendaItem(
        type: 'task',
        id: t.id,
        title: t.title,
        scopeId: scopeId,
        projectId: t.projectId,
        startAt: t.startAt,
        endAt: t.endAt,
        dueAt: t.dueAt,
        assigneeAccountIds: t.assigneeAccountIds,
        isCompleted: t.isCompleted,
      ),
    for (final e in data.events.where(
      (e) => projectId == null || e.projectId == projectId,
    ))
      AgendaItem(
        type: 'event',
        id: e.id,
        title: e.title,
        scopeId: scopeId,
        projectId: e.projectId,
        startAt: e.startAt,
        endAt: e.endAt,
        assigneeAccountIds: e.assigneeAccountIds,
      ),
  ];
  items.sort((a, b) {
    if (a.sortAt == null) return b.sortAt == null ? a.id.compareTo(b.id) : 1;
    if (b.sortAt == null) return -1;
    final c = a.sortAt!.compareTo(b.sortAt!);
    return c == 0 ? a.id.compareTo(b.id) : c;
  });
  return List.unmodifiable(items);
}

List<AgendaItem> dailyAgenda(
  SharedScopeData data, {
  required String scopeId,
  required DateTime day,
}) {
  // Construct both local midnights, rather than adding 24h across DST changes.
  final start = DateTime(day.year, day.month, day.day),
      end = DateTime(day.year, day.month, day.day + 1);
  bool onDay(DateTime? d) => d != null && !d.isBefore(start) && d.isBefore(end);
  return List.unmodifiable(
    projectTimeline(data, scopeId: scopeId).where(
      (e) =>
          !e.isCompleted &&
          (onDay(e.dueAt) ||
              onDay(e.startAt) ||
              (e.startAt != null &&
                  e.endAt != null &&
                  e.startAt!.isBefore(end) &&
                  e.endAt!.isAfter(start))),
    ),
  );
}

/// Active plans include past dates so reconcile does not cancel an already
/// delivered notification until its source changes, completes or disappears.
List<ReminderPlan> desiredReminderPlans({
  required OrganizerSnapshot personal,
  required CollaborationState shared,
}) {
  final plans = <ReminderPlan>[
    ...desiredFinanceReminderPlans(personal: personal, shared: shared),
  ];
  for (final t in personal.tasks.where(
    (t) => !t.isCompleted && t.dueAt != null,
  )) {
    plans.add(
      ReminderPlan(
        stableKey: 'personal:task:${t.id}:due',
        scheduledAt: t.dueAt!.toUtc(),
        reason: 'task_due',
        target: NotificationTarget(
          records: [NotificationRecordTarget(type: 'task', recordId: t.id)],
        ),
      ),
    );
  }
  for (final e in personal.events) {
    plans.add(
      ReminderPlan(
        stableKey: 'personal:event:${e.id}:start',
        scheduledAt: e.startsAt.toUtc(),
        reason: 'event_start',
        target: NotificationTarget(
          records: [NotificationRecordTarget(type: 'event', recordId: e.id)],
        ),
      ),
    );
  }
  final session = shared.session;
  if (session == null) return List.unmodifiable(plans);
  for (final scope in shared.scopes.where((s) => !s.revoked && !s.archived)) {
    final prefs = shared.notificationPreferences[scope.id];
    final data = shared.dataForScope(scope.id);
    NotificationTarget target(String type, String id) => NotificationTarget(
      serverUrl: session.serverUrl,
      serverId: session.serverId,
      accountId: session.accountId,
      scopeId: scope.id,
      records: [NotificationRecordTarget(type: type, recordId: id)],
    );
    final custom = shared.scheduledReminders
        .where((r) => r.scopeId == scope.id && r.state != 'cancelled')
        .toList();
    if (prefs?.forCategory('reminders').inApp != false) {
      for (final t in data.tasks.where(
        (t) =>
            !t.isCompleted &&
            t.dueAt != null &&
            !custom.any((r) => r.targetType == 'task' && r.targetId == t.id),
      )) {
        plans.add(
          ReminderPlan(
            stableKey: '${session.partition}:${scope.id}:task:${t.id}:due',
            scheduledAt: t.dueAt!.toUtc(),
            reason: 'task_due',
            target: target('task', t.id),
          ),
        );
      }
    }
    if (prefs?.forCategory('reminders').inApp != false) {
      for (final e in data.events.where(
        (e) =>
            !custom.any((r) => r.targetType == 'event' && r.targetId == e.id),
      )) {
        plans.add(
          ReminderPlan(
            stableKey: '${session.partition}:${scope.id}:event:${e.id}:start',
            scheduledAt: e.startAt.toUtc(),
            reason: 'event_start',
            target: target('event', e.id),
          ),
        );
      }
    }
    if (prefs?.forCategory('reminders').inApp != false) {
      for (final r in custom) {
        final valid = switch (r.targetType) {
          'task' => data.tasks.any((t) => t.id == r.targetId && !t.isCompleted),
          'event' => data.events.any((e) => e.id == r.targetId),
          'financeEntry' =>
            shared.financePolicyForScope(scope.id).canRead &&
                data.financeEntries.any(
                  (e) =>
                      e.id == r.targetId &&
                      e.status == SharedFinanceStatus.planned,
                ),
          _ => false,
        };
        if (valid) {
          plans.add(
            ReminderPlan(
              stableKey: '${session.partition}:reminder:${r.id}',
              scheduledAt: r.remindAt,
              reason: 'custom_reminder',
              target: target(r.targetType, r.targetId),
            ),
          );
        }
      }
    }
  }
  return List.unmodifiable(plans);
}
