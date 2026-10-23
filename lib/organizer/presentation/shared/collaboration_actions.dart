import 'sharing_member_label.dart';
import 'scope_lifecycle_menu.dart';
import 'sharing_members.dart';
import 'project_sharing_settings.dart';
import 'content_moderation.dart';
import 'dart:convert';
import '../../data/collaboration_repository.dart' show newSharedId;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n.dart';
import '../../domain/organizer_models.dart';
import '../../state/collaboration_provider.dart';
import '../collection_actions.dart';
import '../finance/finance_access_guard.dart';
import '../organizer_editors.dart';
import '../planning/task_plan_fields.dart';
import 'sharing_errors.dart';
import 'sharing_session_boundary.dart';

class CollaborationActions implements OrganizerCollectionActions {
  CollaborationActions(this.context, this.ref, this.scope, this.data)
    : _guard = SharingSessionGuard(context, ref);
  final BuildContext context;
  final WidgetRef ref;
  final SharedScope scope;
  final SharedScopeData data;
  final SharingSessionGuard _guard;

  List<SharedMember> get _members =>
      ref.read(collaborationProvider).valueOrNull?.membersForScope(scope.id) ??
      const [];
  List<OrganizerPersonOption> get people => [
    for (final member in _members)
      if (member.accountId.isNotEmpty)
        OrganizerPersonOption(
          id: member.accountId,
          label: sharingMemberLabel(context, member),
          active: member.active,
        ),
  ];
  String? _creator(String? id) => id == null
      ? null
      : people.where((person) => person.id == id).firstOrNull?.label ??
            context.l10n.planningFormerMember;
  Widget wrapEditor(Widget editor) => SharingSessionBoundary(
    guard: _guard,
    visibleWhen: (state) =>
        state.localAccessAllowed &&
        (state.scopes
                .where((item) => item.id == scope.id)
                .firstOrNull
                ?.canEdit ??
            false),
    child: editor,
  );

  @override
  String errorMessage(Object error) => sharingErrorMessage(context, error);

  SharingSessionGuard get guard => _guard;
  CollaborationController get controller => _guard.controller;

  @override
  Future<void> run(Future<void> Function() action) async {
    try {
      if (!await showSharedContentPolicy(
        context,
        scopeId: scope.id,
        allowOfflineDraft: true,
      )) {
        return;
      }
      if (!context.mounted || !guard.isCurrent) return;
      await action();
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(sharingErrorMessage(context, error))),
        );
      }
    }
  }

  @override
  Future<void> createShoppingItem({
    required String listId,
    required String title,
    String quantity = '1',
  }) async {
    if (!await showSharedContentPolicy(
      context,
      scopeId: scope.id,
      allowOfflineDraft: true,
    )) {
      throw const CollaborationException('policy_acceptance_cancelled');
    }
    if (!context.mounted || !guard.isCurrent) return;
    await controller.createShoppingItem(
      scopeId: scope.id,
      listId: listId,
      title: title,
      quantity: quantity,
    );
  }

  @override
  Future<void> setShoppingItemChecked(String id, bool value) =>
      run(() => controller.setShoppingItemChecked(scope.id, id, value));

  @override
  Future<void> setTaskCompleted(String id, bool value) =>
      run(() => controller.setTaskCompleted(scope.id, id, value));

  @override
  Future<void> shoppingList([LocalShoppingList? list]) => showOrganizerEditor(
    context,
    heading: list == null
        ? context.l10n.sharingCreateSharedList
        : context.l10n.organizerEditList,
    sharedPolicyScopeId: scope.id,
    onReport: list == null
        ? null
        : () => showContentReport(
            context,
            ref,
            scopeId: scope.id,
            targetType: 'record',
            targetId: list.id,
          ),
    kind: OrganizerEditorKind.shoppingList,
    draft: OrganizerDraft(title: list?.title ?? ''),
    errorMessage: (error) => sharingErrorMessage(context, error),
    wrap: wrapEditor,
    onSave: (draft) async {
      if (list == null) {
        await controller.createShoppingList(
          scopeId: scope.id,
          title: draft.title,
        );
      } else {
        await controller.updateShoppingList(
          scope.id,
          list.copyWith(title: draft.title),
        );
      }
    },
    onDelete: list == null
        ? null
        : () => controller.deleteShoppingList(scope.id, list.id),
  );

  @override
  Future<void> shoppingItem(String listId, [LocalShoppingItem? item]) =>
      showOrganizerEditor(
        context,
        heading: item == null
            ? context.l10n.organizerAddItem
            : context.l10n.organizerEditItem,
        sharedPolicyScopeId: scope.id,
        onReport: item == null
            ? null
            : () => showContentReport(
                context,
                ref,
                scopeId: scope.id,
                targetType: 'record',
                targetId: item.id,
              ),
        kind: OrganizerEditorKind.shoppingItem,
        draft: OrganizerDraft(
          title: item?.title ?? '',
          quantity: item?.quantity ?? '1',
        ),
        errorMessage: (error) => sharingErrorMessage(context, error),
        wrap: wrapEditor,
        onSave: (draft) async {
          if (item == null) {
            await controller.createShoppingItem(
              scopeId: scope.id,
              listId: listId,
              title: draft.title,
              quantity: draft.quantity,
            );
          } else {
            await controller.updateShoppingItem(
              scope.id,
              item.copyWith(title: draft.title, quantity: draft.quantity),
            );
          }
        },
        onDelete: item == null
            ? null
            : () => controller.deleteShoppingItem(scope.id, item.id),
      );

  @override
  Future<void> archiveProject(LocalProject project, {bool archived = true}) =>
      run(() async {
        if (project.id == scope.projectRootId) {
          await controller.archiveProjectScope(scope.id, archived: archived);
        } else {
          await controller.updateProject(
            scope.id,
            project.copyWith(archived: archived),
          );
        }
      });

  @override
  Future<void> deleteProject(LocalProject project) async {
    await showScopeDeletionDialog(
      context,
      ref,
      scope,
      projectId: project.id == scope.projectRootId ? null : project.id,
    );
  }

  Future<void> shareProject(LocalProject project) async {
    if (!guard.isCurrent) return;
    final state = ref.read(collaborationProvider).valueOrNull;
    final current = state?.scopes
        .where((item) => item.id == scope.id)
        .firstOrNull;
    final session = state?.session;
    if (state == null ||
        session == null ||
        current == null ||
        !state.localAccessAllowed ||
        !current.canRead ||
        current.blocked ||
        current.deleted ||
        state.data[current.id]?.projects.any((item) => item.id == project.id) !=
            true) {
      return;
    }
    final root = project.id == current.projectRootId;
    final inline =
        current.kind == SharedScopeKind.household &&
        current.canManage &&
        current.accessPolicyVersion == 3 &&
        state.spaceProjectMembershipSupported;
    if (!root && !inline) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(context.l10n.sharingProjectMembersAction),
          content: Text(context.l10n.sharingProjectMembershipUnavailable),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(context.l10n.close),
            ),
          ],
        ),
      );
      return;
    }
    if (!guard.isCurrent) return;
    await Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute(
        builder: (routeContext) => SharingSessionBoundary(
          guard: guard,
          visibleWhen: (fresh) {
            final target = fresh.scopes
                .where((item) => item.id == current.id)
                .firstOrNull;
            return fresh.localAccessAllowed &&
                target != null &&
                target.canRead &&
                !target.deleted &&
                !target.blocked &&
                fresh.data[current.id]?.projects.any(
                      (item) => item.id == project.id,
                    ) ==
                    true &&
                (root
                    ? target.projectRootId == project.id
                    : target.kind == SharedScopeKind.household &&
                          target.canManage &&
                          target.accessPolicyVersion == 3 &&
                          fresh.spaceProjectMembershipSupported);
          },
          child: Scaffold(
            appBar: AppBar(
              title: Text(
                '${context.l10n.sharingProjectMembersAction} · ${project.title}',
              ),
            ),
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: root
                  ? SharingMembersPage(scope: current, session: session)
                  : ProjectSharingSettings(
                      scope: current,
                      projectId: project.id,
                      onProjectSelected: (id) async {
                        if (!guard.isCurrent) return;
                        await guard.controller.selectSpace(id);
                        if (guard.isCurrent && routeContext.mounted) {
                          Navigator.of(routeContext).pop();
                        }
                      },
                    ),
            ),
          ),
        ),
      ),
    );
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
    sharedPolicyScopeId: scope.id,
    onReport: project == null
        ? null
        : () => showContentReport(
            context,
            ref,
            scopeId: scope.id,
            targetType: 'record',
            targetId: project.id,
          ),
    kind: OrganizerEditorKind.project,
    projectAreaEnabled: false,
    projectContext: scope.name,
    onShare: project == null ? null : () => shareProject(project),
    draft: OrganizerDraft(
      title: project?.title ?? '',
      notes: project?.description ?? '',
      area: project?.area ?? area,
      startAt: project?.startAt,
      endAt: project?.endAt,
      phases: project?.phases ?? const [],
      availabilityMinutes: project?.availabilityMinutes,
      availabilityPeriod: project?.availabilityPeriod,
    ),
    errorMessage: (error) => sharingErrorMessage(context, error),
    wrap: wrapEditor,
    creatorLabel: _creator(project?.createdByAccountId),
    onSave: (draft) async {
      if (project == null) {
        await controller.createProject(
          scopeId: scope.id,
          title: draft.title,
          description: draft.notes,
          area: draft.area,
          startAt: draft.startAt,
          endAt: draft.endAt,
          phases: draft.phases,
          availabilityMinutes: draft.availabilityMinutes,
          availabilityPeriod: draft.availabilityPeriod,
        );
      } else {
        await controller.updateProject(
          scope.id,
          project.copyWith(
            title: draft.title,
            description: draft.notes,
            area: draft.area,
            startAt: draft.startAt,
            endAt: draft.endAt,
            phases: draft.phases,
            availabilityMinutes: draft.availabilityMinutes,
            availabilityPeriod: draft.availabilityPeriod,
          ),
        );
      }
    },
    onDeleteWithReview:
        project == null ||
            ref
                    .read(collaborationProvider)
                    .valueOrNull
                    ?.scopeDeletionSupported !=
                true
        ? null
        : () => showScopeDeletionDialog(
            context,
            ref,
            scope,
            projectId: project.id == scope.projectRootId ? null : project.id,
          ),
  );

  @override
  Future<void> task({LocalTask? task, String? projectId}) async {
    var timerTask = task;
    var state = ref.read(collaborationProvider).valueOrNull;
    final identity = (state?.session?.partition, state?.session?.deviceId);
    if (scope.kind == SharedScopeKind.project &&
        scope.parentSpaceId != null &&
        state?.organizationFinanceSupported == true) {
      try {
        await ref
            .read(collaborationProvider.notifier)
            .refreshFinanceAccountChoices(scope.id);
      } catch (_) {}
      if (!context.mounted) return;
      state = ref.read(collaborationProvider).valueOrNull;
      if ((state?.session?.partition, state?.session?.deviceId) != identity) {
        return;
      }
    }
    final choices = {
      for (final a
          in state?.financeAccountChoices[scope.id] ??
              <SharedFinanceAccountChoice>[])
        '${a.scopeId}:${a.id}': a,
    };
    final linkedCost = task == null
        ? null
        : data.financeEntries
              .where((entry) => entry.taskId == task.id)
              .firstOrNull;
    final canEditCost =
        state?.sessionInvalid != true &&
        scope.canEdit &&
        (state?.recordContractVersion ?? 1) >= 3 &&
        (state?.financeContractVersion ?? 1) >= 2 &&
        state?.financePolicyForScope(scope.id).canWrite == true &&
        state?.financeSnapshotComplete[scope.id] == true;
    final newTaskId = newSharedId();
    final financeGuard = linkedCost == null
        ? null
        : FinanceAccessGuard(context, ref, scope.id);

    return showOrganizerEditor(
      context,
      heading: task == null
          ? context.l10n.organizerAddTask
          : context.l10n.organizerEditTask,
      sharedPolicyScopeId: scope.id,
      onReport: task == null
          ? null
          : () => showContentReport(
              context,
              ref,
              scopeId: scope.id,
              targetType: 'record',
              targetId: task.id,
            ),
      kind: OrganizerEditorKind.task,
      recordId: task?.id,
      projects: data.projects,
      householdPeople: data.people,
      projectSelectionEnabled:
          scope.projectRootId == null && scope.parentSpaceId == null,
      costEditingEnabled: canEditCost,
      costAccountRequired: true,
      financeAccountChoices: {
        for (final choice in choices.entries)
          choice.key: (
            name: choice.value.name,
            currency: choice.value.currency,
            archived: choice.value.archived,
          ),
        if (linkedCost?.accountScopeId != null &&
            !choices.containsKey(
              '${linkedCost!.accountScopeId}:${linkedCost.accountId}',
            ))
          '${linkedCost.accountScopeId}:${linkedCost.accountId}': (
            name: context.l10n.financeUnavailableAccount,
            currency: linkedCost.currency,
            archived: true,
          ),
      },
      financeAccounts: [
        for (final account in data.financeAccounts)
          LocalFinanceAccount(
            id: account.id,
            name: account.name,
            currency: account.currency,
            openingBalanceMinor: account.openingBalanceMinor,
            openingBalanceAt: account.openingBalanceAt,
            archived: account.archived,
            createdAt: account.createdAt,
            updatedAt: account.updatedAt,
          ),
      ],
      onTimerToggle:
          task == null ||
              (ref
                          .read(collaborationProvider)
                          .valueOrNull
                          ?.recordContractVersion ??
                      1) <
                  3
          ? null
          : () async {
              if (!await showSharedContentPolicy(
                context,
                scopeId: scope.id,
                allowOfflineDraft: true,
              )) {
                return timerTask!;
              }
              timerTask = await controller.toggleTaskTimer(
                scope.id,
                timerTask!,
              );
              return timerTask!;
            },
      people: people,
      assignmentEnabled: true,
      creatorLabel: _creator(task?.createdByAccountId),
      draft: OrganizerDraft(
        isCompleted: task?.isCompleted ?? false,
        costEnabled: linkedCost != null,
        costAmount: linkedCost == null
            ? ''
            : formatMoneyMinor(linkedCost.amountMinor),
        costCurrency: linkedCost?.currency ?? 'EUR',
        costPaid: linkedCost?.status == SharedFinanceStatus.posted,
        costWasPaid: linkedCost?.status == SharedFinanceStatus.posted,
        costPaidAt: linkedCost?.paidAt,
        ledgerAccountId: linkedCost?.accountScopeId == null
            ? linkedCost?.ledgerAccountId ?? linkedCost?.accountId
            : '${linkedCost!.accountScopeId}:${linkedCost.accountId}',
        payerPersonId: linkedCost?.payerPersonId,
        recipientPersonId: linkedCost?.recipientPersonId,
        createdByPersonId: linkedCost?.createdByPersonId,
        title: task?.title ?? '',
        notes: task?.notes ?? '',
        projectId:
            task?.projectId ??
            projectId ??
            scope.projectRootId ??
            (scope.parentSpaceId != null ? scope.id : null),
        date: task?.dueAt,
        startAt: task?.startAt,
        endAt: task?.endAt,
        assigneeIds: task?.assigneeAccountIds ?? const [],
        assigneePersonId: task?.assigneePersonId,
        subjectPersonIds: task?.subjectPersonIds ?? const [],
        phaseId: task?.phaseId,
        estimateMinutes: task?.estimateMinutes,
        availabilityMinutes: task?.availabilityMinutes,
        availabilityPeriod: task?.availabilityPeriod,
      ),
      errorMessage: (error) => sharingErrorMessage(context, error),
      wrap: (editor) => wrapEditor(financeGuard?.wrap(editor) ?? editor),
      onSave: (draft) async {
        if (financeGuard != null && !financeGuard.isCurrent) {
          throw const CollaborationException('finance_forbidden');
        }
        // An acknowledgement of this timer edit updates bookkeeping revision.
        // Reuse it only when every business field and timer run is unchanged.
        if (timerTask != null &&
            task != null &&
            timerTask!.timer != task.timer) {
          final latest = ref
              .read(collaborationProvider)
              .valueOrNull
              ?.dataForScope(scope.id)
              .tasks
              .where((row) => row.id == timerTask!.id)
              .firstOrNull;
          Map<String, Object?> business(LocalTask row) => row.toJson()
            ..remove('revision')
            ..remove('createdByAccountId')
            ..remove('updatedByAccountId');
          if (latest != null &&
              jsonEncode(business(latest)) ==
                  jsonEncode(business(timerTask!))) {
            timerTask = latest;
          }
        }
        if (canEditCost && (draft.costEnabled || linkedCost != null)) {
          final current = timerTask;
          final now = DateTime.now().toUtc();
          final saved =
              current?.copyWith(
                isCompleted: draft.isCompleted,
                title: draft.title,
                notes: draft.notes,
                projectId: draft.projectId,
                dueAt: draft.date,
                startAt: draft.startAt,
                endAt: draft.endAt,
                assigneeAccountIds: draft.assigneeIds,
                assigneePersonId: draft.assigneePersonId,
                subjectPersonIds: draft.subjectPersonIds,
                phaseId: draft.phaseId,
                estimateMinutes: draft.estimateMinutes,
                availabilityMinutes: draft.availabilityMinutes,
                availabilityPeriod: draft.availabilityPeriod,
              ) ??
              LocalTask(
                id: newTaskId,
                title: draft.title,
                notes: draft.notes,
                projectId: draft.projectId,
                dueAt: draft.date,
                startAt: draft.startAt,
                endAt: draft.endAt,
                isCompleted: false,
                assigneeAccountIds: draft.assigneeIds,
                assigneePersonId: draft.assigneePersonId,
                subjectPersonIds: draft.subjectPersonIds,
                phaseId: draft.phaseId,
                estimateMinutes: draft.estimateMinutes,
                availabilityMinutes: draft.availabilityMinutes,
                availabilityPeriod: draft.availabilityPeriod,
                createdAt: now,
                updatedAt: now,
              );
          await controller.saveTaskWithCost(
            scope.id,
            saved,
            isNew: current == null,
            cost: draft.costEnabled
                ? TaskCostDraft(
                    accountScopeSpecified: true,
                    amountMinor: parseMoneyMinor(draft.costAmount),
                    currency: draft.costCurrency,
                    ledgerAccountId:
                        choices[draft.ledgerAccountId]?.id ??
                        (draft.ledgerAccountId ==
                                    '${linkedCost?.accountScopeId}:${linkedCost?.accountId}' &&
                                linkedCost?.accountScopeId != null
                            ? linkedCost!.accountId
                            : draft.ledgerAccountId),
                    accountScopeId:
                        choices[draft.ledgerAccountId]?.scopeId ??
                        (draft.ledgerAccountId ==
                                '${linkedCost?.accountScopeId}:${linkedCost?.accountId}'
                            ? linkedCost?.accountScopeId
                            : null),
                    payerPersonId: draft.payerPersonId,
                    recipientPersonId: draft.recipientPersonId,
                    createdByPersonId: draft.createdByPersonId,
                    paid: draft.costPaid,
                    paidAt: draft.costPaidAt,
                  )
                : null,
            removeCost: linkedCost != null && !draft.costEnabled,
            expectedFinanceRevision: linkedCost?.revision,
          );
          return;
        }
        if (task == null) {
          await controller.createTask(
            scopeId: scope.id,
            title: draft.title,
            notes: draft.notes,
            projectId: draft.projectId,
            dueAt: draft.date,
            startAt: draft.startAt,
            endAt: draft.endAt,
            assigneeAccountIds: draft.assigneeIds,
            assigneePersonId: draft.assigneePersonId,
            subjectPersonIds: draft.subjectPersonIds,
            phaseId: draft.phaseId,
            estimateMinutes: draft.estimateMinutes,
            availabilityMinutes: draft.availabilityMinutes,
            availabilityPeriod: draft.availabilityPeriod,
          );
        } else {
          await controller.updateTask(
            scope.id,
            timerTask!.copyWith(
              isCompleted: draft.isCompleted,
              title: draft.title,
              notes: draft.notes,
              projectId: draft.projectId,
              dueAt: draft.date,
              startAt: draft.startAt,
              endAt: draft.endAt,
              assigneeAccountIds: draft.assigneeIds,
              assigneePersonId: draft.assigneePersonId,
              subjectPersonIds: draft.subjectPersonIds,
              phaseId: draft.phaseId,
              estimateMinutes: draft.estimateMinutes,
              availabilityMinutes: draft.availabilityMinutes,
              availabilityPeriod: draft.availabilityPeriod,
            ),
          );
        }
      },
      onDelete: task == null
          ? null
          : () => controller.deleteTask(scope.id, task.id),
    );
  }

  Future<void> event([SharedEvent? event]) => showOrganizerEditor(
    context,
    heading: event == null
        ? context.l10n.organizerAddEvent
        : context.l10n.organizerEditEvent,
    sharedPolicyScopeId: scope.id,
    onReport: event == null
        ? null
        : () => showContentReport(
            context,
            ref,
            scopeId: scope.id,
            targetType: 'record',
            targetId: event.id,
          ),
    kind: OrganizerEditorKind.event,
    projects: data.projects,
    projectSelectionEnabled:
        scope.projectRootId == null && scope.parentSpaceId == null,
    people: people,
    assignmentEnabled: true,
    creatorLabel: _creator(event?.createdByAccountId),
    draft: OrganizerDraft(
      title: event?.title ?? '',
      notes: event?.notes ?? '',
      projectId:
          event?.projectId ??
          scope.projectRootId ??
          (scope.parentSpaceId != null ? scope.id : null),
      date: event?.startAt ?? DateTime.now(),
      endAt: event?.endAt,
      assigneeIds: event?.assigneeAccountIds ?? const [],
    ),
    wrap: wrapEditor,
    errorMessage: (error) => sharingErrorMessage(context, error),
    onSave: (draft) async {
      if (event == null) {
        await controller.createEvent(
          scopeId: scope.id,
          title: draft.title,
          notes: draft.notes,
          projectId: draft.projectId,
          startAt: draft.date!,
          endAt: draft.endAt,
          assigneeAccountIds: draft.assigneeIds,
        );
      } else {
        await controller.updateEvent(
          scope.id,
          event.copyWith(
            title: draft.title,
            notes: draft.notes,
            projectId: draft.projectId,
            startAt: draft.date!,
            endAt: draft.endAt,
            assigneeAccountIds: draft.assigneeIds,
          ),
        );
      }
    },
    onDelete: event == null
        ? null
        : () => controller.deleteEvent(scope.id, event.id),
  );
}

OrganizerSnapshot sharedPresentationSnapshot(SharedScopeData data) =>
    OrganizerSnapshot(
      projects: data.projects,
      people: data.people,
      tasks: data.tasks,
      shoppingLists: data.shoppingLists,
      shoppingItems: data.shoppingItems,
    );
