import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../domain/organizer_models.dart';
import '../state/organizer_provider.dart';
import '../state/collaboration_provider.dart';
import 'finance/finance_access_guard.dart';
import 'collection_actions.dart';
import 'organizer_editors.dart';
import 'organizer_errors.dart';
import 'personal_workspace_boundary.dart';
import '../data/organizer_repository.dart'
    show OrganizerConflictException, newLocalId;

class OrganizerActions implements OrganizerCollectionActions {
  OrganizerActions(this.context, this.ref, this.snapshot)
    : _guard = PersonalWorkspaceGuard(context, ref, snapshot.workspaceKey);
  final PersonalWorkspaceGuard _guard;
  final BuildContext context;
  final WidgetRef ref;
  final OrganizerSnapshot snapshot;
  OrganizerController get controller {
    if (!_guard.isCurrent) {
      throw const OrganizerConflictException('Personal workspace changed');
    }
    return ref.read(organizerProvider.notifier);
  }

  @override
  String errorMessage(Object error) => organizerErrorMessage(context, error);

  @override
  Future<void> createShoppingItem({
    required String listId,
    required String title,
  }) => controller.createShoppingItem(listId: listId, title: title);

  @override
  Future<void> setShoppingItemChecked(String id, bool value) =>
      run(() => controller.setShoppingItemChecked(id, value));

  @override
  Future<void> setTaskCompleted(String id, bool value) =>
      run(() => controller.setTaskCompleted(id, value));

  @override
  Future<void> run(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(organizerErrorMessage(context, error))),
        );
      }
    }
  }

  @override
  Future<void> project([
    LocalProject? project,
    ProjectArea area = ProjectArea.personal,
  ]) => showOrganizerEditor(
    context,
    heading: project == null
        ? context.l10n.organizerAddProject
        : context.l10n.organizerEditProject,
    wrap: _guard.wrap,
    kind: OrganizerEditorKind.project,
    draft: OrganizerDraft(
      phases: project?.phases ?? const [],
      availabilityMinutes: project?.availabilityMinutes,
      availabilityPeriod: project?.availabilityPeriod,
      title: project?.title ?? '',
      notes: project?.description ?? '',
      area: project?.area ?? area,
      startAt: project?.startAt,
      endAt: project?.endAt,
    ),
    onSave: (d) => project == null
        ? controller.createProject(
            phases: d.phases,
            availabilityMinutes: d.availabilityMinutes,
            availabilityPeriod: d.availabilityPeriod,
            title: d.title,
            description: d.notes,
            area: d.area,
            startAt: d.startAt,
            endAt: d.endAt,
          )
        : controller.updateProject(
            project.copyWith(
              phases: d.phases,
              availabilityMinutes: d.availabilityMinutes,
              availabilityPeriod: d.availabilityPeriod,
              title: d.title,
              description: d.notes,
              area: d.area,
              startAt: d.startAt,
              endAt: d.endAt,
            ),
          ),
    onDelete: project == null
        ? null
        : () => controller.deleteProject(project.id),
  );

  @override
  Future<void> task({LocalTask? task, String? projectId}) async {
    final localIds = await controller.deviceLocalRecordIds();
    if (!context.mounted || !_guard.isCurrent) return;
    final existingLocal = task == null ? null : localIds.contains(task.id);
    var source = task;
    final cost = task == null
        ? null
        : snapshot.financeEntries.where((e) => e.taskId == task.id).firstOrNull;
    final collaboration = ref.read(collaborationProvider).valueOrNull;
    final privateScopeId = collaboration?.privateSync.scopeId;
    final privateCost =
        cost != null && task != null && !localIds.contains(task.id);
    final financialGuard = privateCost && privateScopeId != null
        ? FinanceAccessGuard(context, ref, privateScopeId)
        : null;
    final costWritable =
        existingLocal == true ||
        snapshot.workspaceKey == 'local' ||
        (privateScopeId != null &&
            collaboration!.financePolicyForScope(privateScopeId).canWrite);
    final draft = OrganizerDraft(
      title: task?.title ?? '',
      notes: task?.notes ?? '',
      projectId: task?.projectId ?? projectId,
      date: task?.dueAt,
      startAt: task?.startAt,
      endAt: task?.endAt,
      phaseId: task?.phaseId,
      estimateMinutes: task?.estimateMinutes,
      availabilityMinutes: task?.availabilityMinutes,
      availabilityPeriod: task?.availabilityPeriod,
      timer: task?.timer ?? const TaskTimerState(),
      assigneePersonId: task?.assigneePersonId,
      subjectPersonIds: task?.subjectPersonIds ?? const [],
      costEnabled: cost != null,
      costAmount: cost == null ? '' : formatMoneyMinor(cost.amountMinor),
      costCurrency: cost?.currency ?? 'EUR',
      costPaid: cost?.status == FinanceEntryStatus.posted,
      costWasPaid: cost?.status == FinanceEntryStatus.posted,
      costPaidAt: cost?.paidAt,
      ledgerAccountId: cost?.ledgerAccountId,
      payerPersonId: cost?.payerPersonId,
      recipientPersonId: cost?.recipientPersonId,
      createdByPersonId: cost?.createdByPersonId,
    );
    await showOrganizerEditor(
      context,
      heading: task == null
          ? context.l10n.organizerAddTask
          : context.l10n.organizerEditTask,
      wrap: (child) => _guard.wrap(financialGuard?.wrap(child) ?? child),
      kind: OrganizerEditorKind.task,
      projects: existingLocal == null
          ? snapshot.projects
          : snapshot.projects
                .where((p) => localIds.contains(p.id) == existingLocal)
                .toList(),
      localRecordIds: localIds,
      recordId: task?.id,
      defaultLocalOwnership: snapshot.workspaceKey == 'local',
      householdPeople: snapshot.people,
      financeAccounts: snapshot.financeAccounts,
      costEditingEnabled: costWritable,
      draft: draft,
      onTimerToggle: task == null
          ? null
          : () async {
              final current = source!;
              if (current.timer.running) {
                await controller.pauseTaskTimer(
                  current.id,
                  runId: current.timer.runId!,
                  expectedWorkspaceKey: snapshot.workspaceKey,
                );
              } else {
                await controller.startTaskTimer(
                  current.id,
                  expectedRevision: current.revision,
                  expectedWorkspaceKey: snapshot.workspaceKey,
                );
              }
              final repo = await ref.read(organizerRepositoryProvider.future);
              source = repo.snapshot.tasks.firstWhere(
                (t) => t.id == current.id,
              );
              return source!;
            },
      onSave: (d) {
        if (financialGuard?.isCurrent == false) {
          throw const CollaborationException('finance_forbidden');
        }
        final now = DateTime.now().toUtc();
        final record =
            source ??
            LocalTask(
              id: newLocalId(),
              title: d.title,
              notes: d.notes,
              projectId: d.projectId,
              dueAt: d.date,
              isCompleted: false,
              createdAt: now,
              updatedAt: now,
            );
        return controller.saveTaskWithCost(
          task: record.copyWith(
            title: d.title,
            notes: d.notes,
            projectId: d.projectId,
            dueAt: d.date,
            startAt: d.startAt,
            endAt: d.endAt,
            phaseId: d.phaseId,
            estimateMinutes: d.estimateMinutes,
            availabilityMinutes: d.availabilityMinutes,
            availabilityPeriod: d.availabilityPeriod,
            assigneePersonId: d.assigneePersonId,
            subjectPersonIds: d.subjectPersonIds,
            timer: d.timer,
          ),
          isNew: source == null,
          expectedWorkspaceKey: snapshot.workspaceKey,
          expectedFinanceRevision: cost?.revision,
          removeCost: costWritable && cost != null && !d.costEnabled,
          cost: costWritable && d.costEnabled
              ? TaskCostDraft(
                  amountMinor: parseMoneyMinor(d.costAmount),
                  currency: d.costCurrency,
                  ledgerAccountId: d.ledgerAccountId,
                  payerPersonId: d.payerPersonId,
                  recipientPersonId: d.recipientPersonId,
                  createdByPersonId: d.createdByPersonId,
                  paid: d.costPaid,
                  paidAt: d.costPaidAt,
                )
              : null,
        );
      },
      onDelete: task == null ? null : () => controller.deleteTask(task.id),
    );
  }

  Future<void> event([LocalEvent? event]) => showOrganizerEditor(
    context,
    heading: event == null
        ? context.l10n.organizerAddEvent
        : context.l10n.organizerEditEvent,
    wrap: _guard.wrap,
    kind: OrganizerEditorKind.event,
    projects: snapshot.projects,
    draft: OrganizerDraft(
      title: event?.title ?? '',
      notes: event?.notes ?? '',
      projectId: event?.projectId,
      date: event?.startsAt ?? DateTime.now(),
      endAt: event?.endsAt,
    ),
    onSave: (d) => event == null
        ? controller.createEvent(
            title: d.title,
            notes: d.notes,
            projectId: d.projectId,
            startsAt: d.date!,
            endsAt: d.endAt,
          )
        : controller.updateEvent(
            event.copyWith(
              title: d.title,
              notes: d.notes,
              projectId: d.projectId,
              startsAt: d.date!,
              endsAt: d.endAt,
            ),
          ),
    onDelete: event == null ? null : () => controller.deleteEvent(event.id),
  );

  @override
  Future<void> shoppingList([LocalShoppingList? list]) => showOrganizerEditor(
    context,
    heading: list == null
        ? context.l10n.organizerAddList
        : context.l10n.organizerEditList,
    wrap: _guard.wrap,
    kind: OrganizerEditorKind.shoppingList,
    draft: OrganizerDraft(title: list?.title ?? ''),
    onSave: (d) => list == null
        ? controller.createShoppingList(title: d.title)
        : controller.updateShoppingList(list.copyWith(title: d.title)),
    onDelete: list == null
        ? null
        : () => controller.deleteShoppingList(list.id),
  );

  @override
  Future<void> shoppingItem(String listId, [LocalShoppingItem? item]) =>
      showOrganizerEditor(
        context,
        heading: item == null
            ? context.l10n.organizerAddItem
            : context.l10n.organizerEditItem,
        wrap: _guard.wrap,
        kind: OrganizerEditorKind.shoppingItem,
        draft: OrganizerDraft(
          title: item?.title ?? '',
          quantity: item?.quantity ?? '1',
        ),
        onSave: (d) => item == null
            ? controller.createShoppingItem(
                listId: listId,
                title: d.title,
                quantity: d.quantity,
              )
            : controller.updateShoppingItem(
                item.copyWith(title: d.title, quantity: d.quantity),
              ),
        onDelete: item == null
            ? null
            : () => controller.deleteShoppingItem(item.id),
      );

  Future<void> finance([FinanceEntry? entry]) => showOrganizerEditor(
    context,
    heading: entry == null
        ? context.l10n.organizerAddFinance
        : context.l10n.organizerEditFinance,
    wrap: _guard.wrap,
    kind: OrganizerEditorKind.finance,
    projects: snapshot.projects,
    draft: OrganizerDraft(
      title: entry?.title ?? '',
      notes: entry?.notes ?? '',
      projectId: entry?.projectId,
      date: entry?.occurredAt ?? DateTime.now(),
      amount: entry == null ? '' : formatMoneyMinor(entry.amountMinor),
      kind: entry?.kind ?? FinanceEntryKind.expense,
      financeIdentityLocked: entry?.recurrenceRuleId != null,
      currency: entry?.currency ?? 'EUR',
    ),
    onSave: (d) => entry == null
        ? controller.createFinanceEntry(
            title: d.title,
            amountMinor: parseMoneyMinor(d.amount),
            kind: d.kind,
            occurredAt: d.date!,
            currency: d.currency,
            notes: d.notes,
            projectId: d.projectId,
          )
        : controller.updateFinanceEntry(
            entry.copyWith(
              title: d.title,
              amountMinor: parseMoneyMinor(d.amount),
              kind: d.kind,
              occurredAt: d.date!,
              paidAt: entry.paidAt == null ? null : d.date!,
              currency: d.currency,
              notes: d.notes,
              projectId: d.projectId,
            ),
          ),
    onDelete: entry == null || entry.recurrenceRuleId != null
        ? null
        : () => controller.deleteFinanceEntry(entry.id),
  );
}
