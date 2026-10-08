import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n.dart';
import '../../state/collaboration_provider.dart';
import '../../state/organizer_provider.dart';
import '../../domain/organizer_models.dart';
import '../organizer_actions.dart';
import '../finance/shared_finance_actions.dart';
import '../finance/finance_money.dart';
import '../finance/finance_plan_forms.dart';
import '../finance/finance_entry_editing.dart';
import '../finance/finance_access_guard.dart';
import '../personal_workspace_boundary.dart';
import '../collection_actions.dart';
import '../organizer_widgets.dart';
import '../shared/collaboration_actions.dart';
import '../shared/sharing_errors.dart';
import '../shared/sharing_session_boundary.dart';
import 'reminder_snooze.dart';
import 'remote_reminder_editor.dart';

Future<bool> showNotificationTarget(
  BuildContext context,
  WidgetRef ref,
  NotificationTarget target, {
  VoidCallback? onAccount,
  ValueChanged<String>? onMembers,
}) async {
  final capturedSession = ref.read(collaborationProvider).valueOrNull?.session;
  try {
    final result = await ref
        .read(collaborationProvider.notifier)
        .openNotificationTarget(target);
    if (!context.mounted) return false;
    final current = ref.read(collaborationProvider).valueOrNull;
    if (!target.isPersonal &&
        (capturedSession?.partition != current?.session?.partition ||
            capturedSession?.deviceId != current?.session?.deviceId)) {
      return false;
    }
    final l = context.l10n;
    if (result.status != NotificationOpenStatus.available &&
        result.status != NotificationOpenStatus.offline) {
      final message = switch (result.status) {
        NotificationOpenStatus.deleted => l.inboxDeleted,
        NotificationOpenStatus.permissionDenied => l.sharingAccessRevoked,
        NotificationOpenStatus.wrongAccount => l.inboxWrongAccount,
        _ => l.inboxNeedsConnection,
      };
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l.inboxTitle),
          content: Text(message),
          actions: [
            if (result.status == NotificationOpenStatus.wrongAccount &&
                onAccount != null)
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  onAccount();
                },
                child: Text(l.sharingGoToAccount),
              ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l.close),
            ),
          ],
        ),
      );
      return false;
    }
    if (!target.isPersonal &&
        (current?.session == null || !target.matches(current!.session!))) {
      return false;
    }
    if (await _openFinanceConfirmation(context, ref, target)) return true;
    if (!context.mounted) return false;
    final guard = target.isPersonal ? null : SharingSessionGuard(context, ref);
    await showDialog<void>(
      context: context,
      builder: (context) {
        final dialog = AlertDialog(
          title: Text(
            target.isPersonal
                ? l.inboxForMe
                : current!.scopes
                          .where((s) => s.id == target.scopeId)
                          .firstOrNull
                          ?.name ??
                      l.sharingShared,
          ),
          content: SizedBox(
            width: 760,
            child: SingleChildScrollView(
              child: NotificationTargetContent(
                target: target,
                offline: result.status == NotificationOpenStatus.offline,
                onMembers: onMembers,
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l.close),
            ),
          ],
        );
        return guard == null
            ? dialog
            : SharingSessionBoundary(
                guard: guard,
                visibleWhen: (state) =>
                    state.scopes.any(
                      (scope) => scope.id == target.scopeId && !scope.revoked,
                    ) &&
                    (!target.records.any(
                          (r) => SharedFinanceRecordType.values.any(
                            (type) => type.name == r.type,
                          ),
                        ) ||
                        state.financePolicyForScope(target.scopeId!).canRead),
                child: dialog,
              );
      },
    );
    return true;
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(sharingErrorMessage(context, error))),
      );
    }
    return false;
  }
}

class NotificationTargetContent extends ConsumerWidget {
  const NotificationTargetContent({
    super.key,
    required this.target,
    this.offline = false,
    this.onMembers,
  });
  final NotificationTarget target;
  final bool offline;
  final ValueChanged<String>? onMembers;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final personal = ref.watch(organizerProvider).valueOrNull;
    final state = ref.watch(collaborationProvider).valueOrNull;
    final scope = state?.scopes
        .where((s) => s.id == target.scopeId)
        .firstOrNull;
    if (!target.isPersonal &&
        (state?.session == null ||
            !target.matches(state!.session!) ||
            scope == null ||
            scope.revoked)) {
      return Text(l.sharingAccessRevoked);
    }
    if (scope?.kind == SharedScopeKind.personal &&
        (state?.sessionInvalid == true ||
            state?.session?.expiresAt.isAfter(DateTime.now()) != true)) {
      return Text(l.sharingSessionExpired);
    }
    if (personal == null) return const CircularProgressIndicator();
    final personalPresentation =
        target.isPersonal || scope?.kind == SharedScopeKind.personal;
    final data = state?.dataForScope(target.scopeId ?? '');
    String localId(NotificationRecordTarget record) =>
        scope?.kind == SharedScopeKind.personal
        ? state!.personalRecordId(record.recordId)
        : record.recordId;
    final snapshot = personalPresentation
        ? personal
        : sharedPresentationSnapshot(data!);
    final sharedActions = personalPresentation
        ? null
        : CollaborationActions(context, ref, scope!, data!);
    final personalActions = OrganizerActions(context, ref, personal);
    final OrganizerCollectionActions actions = sharedActions ?? personalActions;
    final canEdit =
        personalPresentation ||
        (scope!.canEdit && state!.session!.expiresAt.isAfter(DateTime.now()));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (offline)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(l.inboxOfflineView),
          ),
        for (final record in target.records) ...[
          if (record.type == 'membership') ...[
            Text(l.inboxJoinedScope),
            for (final member
                in state!.membersForScope(scope!.id).where((m) => m.active))
              ListTile(
                title: Text(
                  member.displayName.isEmpty
                      ? member.username
                      : member.displayName,
                ),
                subtitle: Text(sharingRoleLabel(context, member.role)),
              ),
            if (onMembers != null)
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  onMembers!(scope.id);
                },
                child: Text(l.sharingMembers),
              ),
          ] else if (record.type == 'task') ...[
            for (final task in snapshot.tasks.where(
              (t) => t.id == localId(record),
            ))
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (task.notes.isNotEmpty) Text(task.notes),
                      if (!personalPresentation)
                        Text(
                          task.assigneeAccountIds.isEmpty
                              ? l.planningUnassigned
                              : task.assigneeAccountIds
                                    .map(
                                      (id) =>
                                          state!
                                              .membersForScope(scope!.id)
                                              .where((m) => m.accountId == id)
                                              .firstOrNull
                                              ?.displayName ??
                                          l.planningFormerMember,
                                    )
                                    .join(', '),
                        ),
                      if (task.startAt != null)
                        Text(
                          '${l.planningStart}: ${organizerDateTime(context, task.startAt!)}',
                        ),
                      if (task.endAt != null)
                        Text(
                          '${l.planningEnd}: ${organizerDateTime(context, task.endAt!)}',
                        ),
                      if (task.dueAt != null)
                        Text(
                          '${l.planningDue}: ${organizerDateTime(context, task.dueAt!)}',
                        ),
                      Text(
                        task.isCompleted
                            ? l.organizerCompleted
                            : l.organizerTasks,
                      ),
                      if (!personalPresentation && !task.isCompleted)
                        RemoteReminderButton(
                          scopeId: scope!.id,
                          targetType: 'task',
                          targetId: task.id,
                        ),
                      if (!task.isCompleted)
                        ReminderSnoozeButton(
                          target: NotificationTarget(
                            serverUrl: target.serverUrl,
                            serverId: target.serverId,
                            accountId: target.accountId,
                            scopeId: target.scopeId,
                            records: [record],
                          ),
                        ),
                      if (!personalPresentation &&
                          task.createdByAccountId != null)
                        Text(
                          '${l.planningCreatedBy}: ${state?.membersForScope(scope!.id).where((m) => m.accountId == task.createdByAccountId).firstOrNull?.displayName ?? l.planningFormerMember}',
                        ),
                      if (canEdit)
                        TextButton(
                          onPressed: () => (sharedActions ?? personalActions)
                              .task(task: task),
                          child: Text(l.organizerEditTask),
                        ),
                    ],
                  ),
                ),
              ),
          ] else if (record.type == 'event') ...[
            if (personalPresentation)
              for (final event in personal.events.where(
                (e) => e.id == localId(record),
              ))
                OrganizerEventCard(
                  event: event,
                  onTap: () => personalActions.event(event),
                )
            else
              for (final event in data!.events.where(
                (e) => e.id == localId(record),
              ))
                Card(
                  child: ListTile(
                    title: Text(event.title),
                    subtitle: Text(
                      '${organizerDateTime(context, event.startAt)}\n${event.notes}',
                    ),
                    trailing: RemoteReminderButton(
                      scopeId: scope!.id,
                      targetType: 'event',
                      targetId: event.id,
                    ),
                    onTap: canEdit ? () => sharedActions!.event(event) : null,
                  ),
                ),
          ] else if (record.type == 'project') ...[
            for (final project in snapshot.projects.where(
              (p) => p.id == localId(record),
            ))
              Card(
                child: ListTile(
                  title: Text(project.title),
                  subtitle: Text(project.description),
                  onTap: canEdit ? () => actions.project(project) : null,
                ),
              ),
          ] else if (record.type == 'shoppingList') ...[
            for (final list in snapshot.shoppingLists.where(
              (v) => v.id == localId(record),
            ))
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        list.title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      for (final item in snapshot.shoppingItems.where(
                        (i) => i.listId == list.id,
                      ))
                        Text(
                          '${item.isChecked ? '✓' : '○'} ${item.title} · ${item.quantity}',
                        ),
                    ],
                  ),
                ),
              ),
          ] else if (record.type == 'shoppingItem') ...[
            for (final item in snapshot.shoppingItems.where(
              (v) => v.id == localId(record),
            ))
              Card(
                color: Theme.of(context).colorScheme.primaryContainer,
                child: ListTile(
                  title: Text(item.title),
                  subtitle: Text(
                    '${item.quantity} · ${snapshot.shoppingLists.where((v) => v.id == item.listId).firstOrNull?.title ?? l.organizerShopping}',
                  ),
                  onTap: canEdit
                      ? () => actions.shoppingItem(item.listId, item)
                      : null,
                ),
              ),
          ] else if (record.type == 'personalFinanceEntry' ||
              (record.type == 'financeEntry' && personalPresentation)) ...[
            if (target.isPersonal ||
                (state!.financePolicyForScope(scope!.id).canRead &&
                    state.financeSnapshotComplete[scope.id] == true))
              for (final entry in personal.financeEntries.where(
                (entry) => entry.id == localId(record),
              ))
                Card(
                  child: ListTile(
                    title: Text(entry.title),
                    subtitle: Text(
                      '${sharedMoneyLabel(context, BigInt.from(entry.amountMinor), entry.currency)} · ${organizerDateTime(context, entry.occurredAt)}\n${entry.notes}',
                    ),
                    onTap: canEdit
                        ? () async {
                            if (entry.status != FinanceEntryStatus.planned) {
                              if (entry.recurrenceRuleId != null) {
                                await editRecordedPersonalOccurrence(
                                  context,
                                  ref,
                                  personal,
                                  entry,
                                );
                              } else {
                                await personalActions.finance(entry);
                              }
                              return;
                            }
                            final guard = PersonalWorkspaceGuard(
                              context,
                              ref,
                              personal.workspaceKey,
                            );
                            final financial = target.isPersonal
                                ? null
                                : FinanceAccessGuard(
                                    context,
                                    ref,
                                    scope!.id,
                                    write: true,
                                  );
                            await showFinanceOccurrenceConfirmation(
                              context,
                              entry: entry,
                              sourceWorkspaceKey: personal.workspaceKey,
                              initialPaidAt: ref.read(organizerClockProvider)(),
                              wrap: (child) =>
                                  guard.wrap(financial?.wrap(child) ?? child),
                              onConfirm: (amount, date) async {
                                if (!guard.isCurrent ||
                                    financial?.isCurrent == false) {
                                  throw const CollaborationException(
                                    'finance_forbidden',
                                  );
                                }
                                await ref
                                    .read(organizerProvider.notifier)
                                    .confirmFinanceOccurrence(
                                      entry: entry,
                                      amountMinor: amount,
                                      paidAt: date,
                                      expectedWorkspaceKey:
                                          personal.workspaceKey,
                                    );
                              },
                            );
                          }
                        : null,
                  ),
                )
            else
              Text(l.sharingAccessRevoked),
          ] else if (record.type.startsWith('finance')) ...[
            if (state!.financePolicyForScope(scope!.id).canRead &&
                state.financeSnapshotComplete[scope.id] == true) ...[
              for (final account in data!.financeAccounts.where(
                (v) =>
                    record.type == 'financeAccount' && v.id == localId(record),
              ))
                Card(
                  child: ListTile(
                    title: Text(account.name),
                    subtitle: Text(
                      sharedMoneyLabel(
                        context,
                        BigInt.from(account.openingBalanceMinor ?? 0),
                        account.currency,
                      ),
                    ),
                    onTap: state.financePolicyForScope(scope.id).canWrite
                        ? () => SharedFinanceActions(
                            context,
                            ref,
                            scope,
                            state,
                          ).account(account)
                        : null,
                  ),
                ),
              for (final entry in data.financeEntries.where(
                (v) => record.type == 'financeEntry' && v.id == localId(record),
              ))
                Card(
                  child: ListTile(
                    title: Text(entry.title),
                    subtitle: Text(
                      '${sharedMoneyLabel(context, BigInt.from(entry.amountMinor), entry.currency)} · ${organizerDateTime(context, entry.occurredAt)}\n${entry.notes}',
                    ),
                    trailing: entry.status == SharedFinanceStatus.planned
                        ? RemoteReminderButton(
                            scopeId: scope.id,
                            targetType: 'financeEntry',
                            targetId: entry.id,
                          )
                        : null,
                    onTap: state.financePolicyForScope(scope.id).canWrite
                        ? () async {
                            if (entry.status != SharedFinanceStatus.planned) {
                              await SharedFinanceActions(
                                context,
                                ref,
                                scope,
                                state,
                              ).entry(entry);
                              return;
                            }
                            final guard = FinanceAccessGuard(
                              context,
                              ref,
                              scope.id,
                              write: true,
                            );
                            final local = FinanceEntry(
                              id: entry.id,
                              title: entry.title,
                              amountMinor: entry.amountMinor,
                              currency: entry.currency,
                              kind: entry.kind,
                              occurredAt: entry.occurredAt,
                              projectId: null,
                              taskId: entry.taskId,
                              notes: entry.notes,
                              createdAt: entry.createdAt,
                              updatedAt: entry.updatedAt,
                            );
                            await showFinanceOccurrenceConfirmation(
                              context,
                              entry: local,
                              sourceScopeId: scope.id,
                              sourcePartition: state.session!.partition,
                              wrap: guard.wrap,
                              onConfirm: (amount, date) => guard.controller
                                  .confirmFinanceOccurrenceForScope(
                                    scope.id,
                                    entry,
                                    amountMinor: amount,
                                    paidAt: date,
                                  ),
                            );
                          }
                        : null,
                  ),
                ),
              for (final transfer in data.financeTransfers.where(
                (v) =>
                    record.type == 'financeTransfer' && v.id == localId(record),
              ))
                Card(
                  child: ListTile(
                    title: Text(transfer.title),
                    subtitle: Text(
                      '${sharedMoneyLabel(context, BigInt.from(transfer.amountMinor), transfer.currency)} · ${organizerDateTime(context, transfer.occurredAt)}',
                    ),
                    onTap: state.financePolicyForScope(scope.id).canWrite
                        ? () => SharedFinanceActions(
                            context,
                            ref,
                            scope,
                            state,
                          ).transfer(transfer)
                        : null,
                  ),
                ),
              TextButton(
                onPressed: () => SharedFinanceActions(
                  context,
                  ref,
                  scope,
                  state,
                ).audit(localId(record)),
                child: Text(l.financeAudit),
              ),
            ] else if (state.financePolicyForScope(scope.id).canRead)
              Text(l.financeLoadingSnapshot)
            else
              Text(l.sharingAccessRevoked),
          ],
        ],
      ],
    );
  }
}

String organizerDateTime(BuildContext context, DateTime value) {
  final local = value.toLocal();
  return '${organizerDate(context, local)} · ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(local))}';
}

Future<bool> _openFinanceConfirmation(
  BuildContext context,
  WidgetRef ref,
  NotificationTarget target,
) async {
  if (target.records.length != 1) return false;
  final record = target.records.single;
  if (!['financeEntry', 'personalFinanceEntry'].contains(record.type)) {
    return false;
  }
  final state = ref.read(collaborationProvider).valueOrNull;
  final personal = ref.read(organizerProvider).valueOrNull;
  final scope = state?.scopes.where((s) => s.id == target.scopeId).firstOrNull;
  if (target.isPersonal || scope?.kind == SharedScopeKind.personal) {
    final id = scope?.kind == SharedScopeKind.personal
        ? state!.personalRecordId(record.recordId)
        : record.recordId;
    final entry = personal?.financeEntries.where((e) => e.id == id).firstOrNull;
    if (entry == null || entry.status != FinanceEntryStatus.planned) {
      return false;
    }
    final guard = PersonalWorkspaceGuard(context, ref, personal!.workspaceKey);
    final financeScope =
        target.scopeId ??
        (personal.workspaceKey == 'local' ? null : state?.privateSync.scopeId);
    final financial = financeScope == null
        ? null
        : FinanceAccessGuard(context, ref, financeScope, write: true);
    if (!guard.isCurrent || financial?.isCurrent == false) return false;
    await showFinanceOccurrenceConfirmation(
      context,
      entry: entry,
      sourceWorkspaceKey: personal.workspaceKey,
      initialPaidAt: ref.read(organizerClockProvider)(),
      wrap: (child) => guard.wrap(financial?.wrap(child) ?? child),
      isCurrent: () => guard.isCurrent && (financial?.isCurrent ?? true),
      onConfirm: (amount, date) async {
        if (!guard.isCurrent || financial?.isCurrent == false) {
          throw const CollaborationException('finance_forbidden');
        }
        await ref
            .read(organizerProvider.notifier)
            .confirmFinanceOccurrence(
              entry: entry,
              amountMinor: amount,
              paidAt: date,
              expectedWorkspaceKey: personal.workspaceKey,
            );
      },
    );
    return true;
  }
  if (state == null || scope == null) return false;
  final entry = state
      .dataForScope(scope.id)
      .financeEntries
      .where((e) => e.id == record.recordId)
      .firstOrNull;
  if (entry == null || entry.status != SharedFinanceStatus.planned) {
    return false;
  }
  final guard = FinanceAccessGuard(context, ref, scope.id, write: true);
  if (!guard.isCurrent) return false;
  final local = FinanceEntry(
    id: entry.id,
    title: entry.title,
    amountMinor: entry.amountMinor,
    currency: entry.currency,
    kind: entry.kind,
    occurredAt: entry.occurredAt,
    projectId: null,
    taskId: entry.taskId,
    notes: entry.notes,
    createdAt: entry.createdAt,
    updatedAt: entry.updatedAt,
  );
  await showFinanceOccurrenceConfirmation(
    context,
    entry: local,
    sourceScopeId: scope.id,
    sourcePartition: state.session!.partition,
    initialPaidAt: ref.read(organizerClockProvider)(),
    wrap: guard.wrap,
    isCurrent: () => guard.isCurrent,
    onConfirm: (amount, date) =>
        guard.controller.confirmFinanceOccurrenceForScope(
          scope.id,
          entry,
          amountMinor: amount,
          paidAt: date,
        ),
  );
  return true;
}
