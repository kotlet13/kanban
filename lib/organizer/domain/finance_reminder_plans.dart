import 'dart:convert';
import 'finance_forecast.dart';
import 'organizer_models.dart';
import 'collaboration_models.dart';

List<ReminderPlan> desiredFinanceReminderPlans({
  required OrganizerSnapshot personal,
  required CollaborationState shared,
  Iterable<OrganizerSnapshot>? localSnapshots,
}) {
  final result = <ReminderPlan>[];
  final session = shared.session;
  bool remotelyScheduled(String scopeId, String type, String id) =>
      shared.scheduledReminders.any(
        (r) =>
            r.scopeId == scopeId &&
            r.targetType == type &&
            r.targetId == id &&
            r.state != 'cancelled' &&
            r.syncState != 'blocked',
      );
  void salary(
    FinanceRecurrenceRule rule,
    String entryId,
    String? occurrenceKey,
    DateTime? plannedAt,
    NotificationTarget target,
    String namespace,
  ) {
    if (!rule.active || !rule.remindersEnabled || plannedAt == null) return;
    final parts = occurrenceKey?.split('-');
    final nominal = parts != null && parts.length == 2
        ? rule.dateForMonth(int.parse(parts[0]), int.parse(parts[1]))
        : plannedAt.toLocal();
    final dates = rule.kind == FinanceRecurrenceKind.salary
        ? salaryCheckDates(rule, nominal)
        : [
            DateTime(
              nominal.year,
              nominal.month,
              nominal.day,
              rule.reminderMinuteOfDay ~/ 60,
              rule.reminderMinuteOfDay % 60,
            ),
          ];
    for (var i = 0; i < dates.length; i++) {
      result.add(
        ReminderPlan(
          stableKey:
              '$namespace:salary:${rule.id}:$occurrenceKey:$entryId:${dates.length == 2 ? (i == 0 ? 'before_weekend' : 'after_weekend') : 'expected_day'}',
          scheduledAt: dates[i].toUtc(),
          target: target,
          reason: rule.kind == FinanceRecurrenceKind.salary
              ? 'salary_check'
              : rule.entryKind == FinanceEntryKind.income
              ? 'income_check'
              : 'finance_due',
        ),
      );
    }
  }

  final privateScope = shared.privateSync.scopeId;
  for (final personal in localSnapshots ?? [personal]) {
    final bound = personal.workspaceKey.startsWith('private:');
    final canReadPrivate =
        (session != null &&
        personal.workspaceKey == 'private:${session.partition}' &&
        shared.privateSync.enabled &&
        shared.localAccessAllowed &&
        privateScope != null &&
        shared.financePolicyForScope(privateScope).canRead &&
        shared.financeSnapshotComplete[privateScope] == true);
    if (!bound ||
        (session != null &&
            shared.localAccessAllowed &&
            personal.workspaceKey == 'private:${session.partition}')) {
      for (final e in personal.financeEntries.where(
        (e) =>
            e.status == FinanceEntryStatus.planned &&
            e.recurrenceRuleId != null,
      )) {
        final rule = personal.financeRecurrenceRules
            .where((r) => r.id == e.recurrenceRuleId)
            .firstOrNull;
        if (rule == null) continue;
        final isPrivate =
            bound && shared.privateRecordIds.values.contains(e.id);
        if (isPrivate && !canReadPrivate) continue;
        final remoteId =
            shared.privateRecordIds.entries
                .where((m) => m.value == e.id)
                .firstOrNull
                ?.key ??
            e.id;
        if (isPrivate &&
            remotelyScheduled(
              privateScope!,
              'personalFinanceEntry',
              remoteId,
            )) {
          continue;
        }
        final target = NotificationTarget(
          serverUrl: isPrivate ? session!.serverUrl : null,
          serverId: isPrivate ? session!.serverId : null,
          accountId: isPrivate ? session!.accountId : null,
          scopeId: isPrivate ? privateScope : null,
          localSpaceId: !bound && personal.workspaceKey != 'local'
              ? personal.workspaceKey
              : null,
          records: [
            NotificationRecordTarget(
              type: isPrivate ? 'personalFinanceEntry' : 'financeEntry',
              recordId: isPrivate ? remoteId : e.id,
            ),
          ],
        );
        salary(
          rule,
          e.id,
          e.occurrenceKey,
          e.plannedAt,
          target,
          isPrivate
              ? '${session!.partition}:$privateScope'
              : bound || personal.workspaceKey == 'local'
              ? 'personal:local'
              : 'local:${personal.workspaceKey}',
        );
      }
    }
  }
  if (session != null && shared.localAccessAllowed) {
    for (final scope in shared.scopes.where(
      (s) =>
          !s.revoked &&
          !s.archived &&
          !s.blocked &&
          s.kind != SharedScopeKind.personal,
    )) {
      if (!shared.financePolicyForScope(scope.id).canRead ||
          shared.financeSnapshotComplete[scope.id] != true ||
          shared.notificationPreferences[scope.id]
                  ?.forCategory('reminders')
                  .inApp ==
              false) {
        continue;
      }
      final data = shared.dataForScope(scope.id);
      for (final e in data.financeEntries.where(
        (e) =>
            e.status == SharedFinanceStatus.planned &&
            e.recurrenceRuleId != null,
      )) {
        if (remotelyScheduled(scope.id, 'financeEntry', e.id)) continue;
        final rule = data.financeRecurrenceRules
            .where((r) => r.id == e.recurrenceRuleId)
            .firstOrNull;
        if (rule == null) continue;
        salary(
          rule,
          e.id,
          e.occurrenceKey,
          e.plannedAt,
          NotificationTarget(
            serverUrl: session.serverUrl,
            serverId: session.serverId,
            accountId: session.accountId,
            scopeId: scope.id,
            records: [
              NotificationRecordTarget(type: 'financeEntry', recordId: e.id),
            ],
          ),
          '${session.partition}:${scope.id}',
        );
      }
    }
  }
  return List.unmodifiable(result);
}

Set<String> allowedFinanceInboxReadNames({
  required OrganizerSnapshot personal,
  required CollaborationState shared,
  Iterable<OrganizerSnapshot>? localSnapshots,
}) => {
  for (final p in desiredFinanceReminderPlans(
    personal: personal,
    shared: shared,
    localSnapshots: localSnapshots,
  ))
    'finance_inbox_read:${p.stableKey}',
};

/// The center shows the latest due check for an occurrence. Reading Friday's
/// check does not pre-read Monday's follow-up or post the underlying entry.
List<ReminderPlan> dueFinanceInboxPlans({
  required OrganizerSnapshot personal,
  required CollaborationState shared,
  required DateTime now,
  Iterable<OrganizerSnapshot>? localSnapshots,
}) {
  final latest = <String, ReminderPlan>{};
  for (final plan in desiredFinanceReminderPlans(
    personal: personal,
    shared: shared,
    localSnapshots: localSnapshots,
  )) {
    if (plan.scheduledAt.isAfter(now)) continue;
    final key = jsonEncode(plan.target.toJson());
    if (latest[key] == null ||
        plan.scheduledAt.isAfter(latest[key]!.scheduledAt)) {
      latest[key] = plan;
    }
  }
  return latest.values.toList()
    ..sort((a, b) => b.scheduledAt.compareTo(a.scheduledAt));
}
