import 'collaboration_models.dart';
import 'finance_reminder_plans.dart';
import 'organizer_models.dart';

class LocalInboxReminder {
  const LocalInboxReminder(
    this.reminder,
    this.plan,
    this.remoteEntries, {
    this.task,
    this.workspaceKey = 'local',
  });
  final LocalTask? task;
  final String workspaceKey;
  final LocalReminder reminder;
  final ReminderPlan plan;
  final List<SharedInboxEntry> remoteEntries;
  bool get isRead => reminder.isRead && remoteEntries.every((e) => e.isRead);
}

class SharedInboxReminder {
  const SharedInboxReminder(this.group, this.plan);
  final SharedInboxGroup group;
  final ReminderPlan? plan;
}

/// Account-wide eligibility, shared by the center and its unread indicator.
/// Presentation filters never change eligibility or the global unread state.
class OrganizerInboxProjection {
  const OrganizerInboxProjection({
    this.local = const [],
    this.shared = const [],
    this.finance = const [],
  });
  final List<LocalInboxReminder> local;
  final List<SharedInboxReminder> shared;
  final List<ReminderPlan> finance;
  bool hasUnread(Set<String>? financeReadKeys) =>
      local.any((r) => !r.isRead) ||
      shared.any((r) => !r.group.isRead) ||
      (financeReadKeys != null &&
          finance.any((p) => !financeReadKeys.contains(p.stableKey)));
}

OrganizerInboxProjection projectOrganizerInbox({
  required OrganizerSnapshot? personal,
  required CollaborationState shared,
  required List<ReminderPlan>? effectivePlans,
  required DateTime now,
  Iterable<OrganizerSnapshot>? localSnapshots,
}) {
  final snapshots =
      localSnapshots?.toList() ?? [if (personal != null) personal];
  ReminderPlan? latest(Iterable<ReminderPlan> plans) {
    final sorted = plans.toList()
      ..sort((a, b) => b.scheduledAt.compareTo(a.scheduledAt));
    return sorted.firstOrNull;
  }

  bool activeScope(String? id) => shared.scopes.any(
    (s) => s.id == id && !s.revoked && !s.blocked && !s.archived,
  );
  bool currentPlan(ReminderPlan plan) {
    if (plan.target.isPersonal) {
      return snapshots.any((snapshot) {
        final defaultPrivate = snapshot.workspaceKey.startsWith('private:');
        final localId = defaultPrivate ? 'local' : snapshot.workspaceKey;
        return localId == plan.target.localWorkspaceId &&
            (!defaultPrivate ||
                shared.session != null &&
                    shared.localAccessAllowed &&
                    snapshot.workspaceKey ==
                        'private:${shared.session!.partition}' &&
                    activeScope(shared.privateSync.scopeId));
      });
    }
    return shared.session != null &&
        shared.localAccessAllowed &&
        plan.target.matches(shared.session!) &&
        activeScope(plan.target.scopeId);
  }

  ReminderPlan? localPlan(LocalReminder reminder, OrganizerSnapshot snapshot) =>
      latest(
        (effectivePlans ?? const <ReminderPlan>[]).where(
          (p) =>
              currentPlan(p) &&
              (p.target.isPersonal
                  ? p.target.localWorkspaceId ==
                        (snapshot.workspaceKey.startsWith('private:')
                            ? 'local'
                            : snapshot.workspaceKey)
                  : snapshot.workspaceKey.startsWith('private:')) &&
              p.target.records.any(
                (r) =>
                    r.type == 'task' &&
                    (p.target.isPersonal
                        ? r.recordId == reminder.taskId
                        : p.target.scopeId == shared.privateSync.scopeId &&
                              shared.personalRecordId(r.recordId) ==
                                  reminder.taskId),
              ),
        ),
      );
  ReminderPlan? sharedPlan(SharedInboxEntry entry) => latest(
    (effectivePlans ?? const <ReminderPlan>[]).where(
      (p) =>
          currentPlan(p) &&
          p.target.scopeId == entry.scopeId &&
          p.target.records.any(
            (r) => r.type == entry.targetType && r.recordId == entry.targetId,
          ),
    ),
  );
  bool matches(SharedInboxEntry entry, ReminderPlan plan) =>
      entry.scopeId == plan.target.scopeId &&
      plan.target.records.any(
        (r) => r.type == entry.targetType && r.recordId == entry.targetId,
      );

  bool eligible(SharedInboxEntry entry) {
    if (shared.session == null || !shared.localAccessAllowed) return false;
    final scope = shared.scopes.where((s) => s.id == entry.scopeId).firstOrNull;
    if (scope == null || scope.revoked || scope.blocked || scope.archived) {
      return false;
    }
    if (shared.notificationPreferences[scope.id]
            ?.forCategory(entry.category)
            .inApp ==
        false) {
      return false;
    }
    final financial =
        isFinancialRecordType(entry.targetType) || entry.category == 'finance';
    if (financial &&
        (!shared.financePolicyForScope(scope.id).canRead ||
            shared.financeSnapshotComplete[scope.id] != true)) {
      return false;
    }
    if (entry.kind != 'reminder.due') return true;
    final data = shared.dataForScope(scope.id);
    final active = switch (entry.targetType) {
      'task' => data.tasks.any((t) => t.id == entry.targetId && !t.isCompleted),
      'event' => data.events.any((e) => e.id == entry.targetId),
      'financeEntry' => data.financeEntries.any(
        (e) =>
            e.id == entry.targetId && e.status == SharedFinanceStatus.planned,
      ),
      'personalFinanceEntry' => data.personalFinanceEntries.any(
        (e) => e.id == entry.targetId && e.status == FinanceEntryStatus.planned,
      ),
      _ => false,
    };
    if (!active) return false;
    final plan = sharedPlan(entry);
    // A future effective alarm (including a device snooze) hides older alarms.
    // A delivered server alarm is itself an inbox event and needs no local plan.
    if (plan != null) return !plan.scheduledAt.isAfter(now);
    final schedules = shared.scheduledReminders.where(
      (r) =>
          r.scopeId == entry.scopeId &&
          r.targetType == entry.targetType &&
          r.targetId == entry.targetId,
    );
    return schedules.isEmpty ||
        schedules.any(
          (r) =>
              r.state == 'delivered' &&
              r.syncState != 'blocked' &&
              !r.remindAt.isAfter(now),
        );
  }

  final eligibleEntries = shared.inbox.where(eligible).toList();
  final locals = <LocalInboxReminder>[];
  if (effectivePlans != null) {
    for (final personal in snapshots) {
      for (final reminder in personal.reminders) {
        final task = personal.tasks
            .where((t) => t.id == reminder.taskId)
            .firstOrNull;
        final plan = localPlan(reminder, personal);
        if (task == null ||
            task.isCompleted ||
            task.dueAt != reminder.dueAt ||
            plan == null ||
            plan.scheduledAt.isAfter(now)) {
          continue;
        }
        final mirrors = eligibleEntries
            .where((e) => e.kind == 'reminder.due' && matches(e, plan))
            .toList();
        locals.add(
          LocalInboxReminder(
            reminder,
            plan,
            mirrors,
            task: task,
            workspaceKey: personal.workspaceKey,
          ),
        );
      }
    }
  }
  final remote = <SharedInboxReminder>[];
  final reminderGroups = <String, List<SharedInboxEntry>>{};
  for (final group in groupSharedInbox(eligibleEntries)) {
    if (group.entries.first.kind != 'reminder.due') {
      remote.add(SharedInboxReminder(group, null));
      continue;
    }
    for (final entry in group.entries) {
      if (locals.any((r) => matches(entry, r.plan))) continue;
      final key = '${entry.scopeId}:${entry.targetType}:${entry.targetId}';
      (reminderGroups[key] ??= []).add(entry);
    }
  }
  for (final entries in reminderGroups.values) {
    remote.add(
      SharedInboxReminder(SharedInboxGroup(entries), sharedPlan(entries.first)),
    );
  }
  remote.sort(
    (a, b) => b.group.entries.first.createdAt.compareTo(
      a.group.entries.first.createdAt,
    ),
  );
  final finance = effectivePlans == null
      ? <ReminderPlan>[]
      : dueFinanceInboxPlans(
              personal: personal ?? OrganizerSnapshot(),
              shared: shared,
              now: now,
              localSnapshots: snapshots,
            )
            .map(
              (p) => effectivePlans
                  .where((e) => e.stableKey == p.stableKey)
                  .firstOrNull,
            )
            .whereType<ReminderPlan>()
            .where((p) => currentPlan(p) && !p.scheduledAt.isAfter(now))
            .toList();
  return OrganizerInboxProjection(
    local: locals,
    shared: remote,
    finance: finance,
  );
}
