import 'sharing_member_label.dart';
import '../inbox/visible_task_target_view.dart';
import 'scope_lifecycle_menu.dart';
import 'sharing_members.dart';
import 'project_sharing_settings.dart';
import 'content_moderation.dart';
import 'dart:convert';
import 'dart:async';
import '../../data/collaboration_repository.dart' show newSharedId;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n.dart';
import '../../domain/organizer_models.dart';
import '../../domain/shared_record_permissions.dart';
import '../../state/collaboration_provider.dart';
import '../collection_actions.dart';
import '../finance/finance_access_guard.dart';
import '../organizer_editors.dart';
import '../planning/task_plan_fields.dart';
import 'sharing_errors.dart';
import 'sharing_session_boundary.dart';

class CollaborationActions
    implements OrganizerCollectionActions, OrganizerRecordPermissionActions {
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
  SharedScope? _currentScope(CollaborationState? state) =>
      state?.localAccessAllowed == true && guard.isCurrent
      ? state?.scopes.where((value) => value.id == scope.id).firstOrNull
      : null;
  bool _canEdit(CollaborationState? state, String type, String id) {
    final current = _currentScope(state);
    if (current == null || state?.session == null) return false;
    final rows = state!.dataForScope(scope.id);
    return SharedRecordPermissions.canEdit(
      scope: current,
      accountId: state.session!.accountId,
      creator: rows.recordCreators['content:$id'],
      type: type,
      assignees: type == 'task'
          ? rows.tasks
                    .where((row) => row.id == id)
                    .firstOrNull
                    ?.assigneeAccountIds ??
                const []
          : const [],
    );
  }

  @override
  Future<void> openTask(LocalTask task) async {
    final state = ref.read(collaborationProvider).valueOrNull;
    final session = state?.session;
    final current = _currentScope(state);
    if (session == null || current?.canRead != true) return;
    await showVisibleTaskTarget(
      context,
      ref,
      NotificationTarget(
        serverUrl: session.serverUrl,
        serverId: session.serverId,
        accountId: session.accountId,
        scopeId: scope.id,
        records: [NotificationRecordTarget(type: 'task', recordId: task.id)],
      ),
      isCurrent: () => guard.isCurrent,
    );
  }

  @override
  bool get canCreateRecords =>
      _currentScope(ref.read(collaborationProvider).valueOrNull)?.canEdit ==
      true;
  @override
  bool canEditRecord(String type, String id) =>
      _canEdit(ref.read(collaborationProvider).valueOrNull, type, id);
  @override
  bool get canCheckShoppingItems {
    final current = _currentScope(ref.read(collaborationProvider).valueOrNull);
    return current != null && SharedRecordPermissions.canCheckShopping(current);
  }

  @override
  bool canDeleteRecord(String type, String id) {
    final state = ref.read(collaborationProvider).valueOrNull;
    final current = _currentScope(state);
    if (current == null || state?.session == null) return false;
    final rows = state!.dataForScope(scope.id),
        account = state.session!.accountId;
    if (!SharedRecordPermissions.canDelete(
      scope: current,
      accountId: account,
      creator: rows.recordCreators['content:$id'],
    ))
      return false;
    if (current.recordPolicyVersion != 1 ||
        current.isOwner ||
        current.verifiedParentOwner)
      return true;
    Iterable<String> children = const [];
    if (type == 'shoppingList')
      children = rows.shoppingItems
          .where((row) => row.listId == id)
          .map((row) => 'content:${row.id}');
    if (type == 'project')
      children = [
        for (final row in rows.tasks.where((row) => row.projectId == id))
          'content:${row.id}',
        for (final row in rows.events.where((row) => row.projectId == id))
          'content:${row.id}',
        for (final row in rows.ideas.where((row) => row.projectId == id))
          'content:${row.id}',
        for (final row in rows.financeEntries.where(
          (row) => row.projectId == id,
        ))
          'finance:${row.id}',
      ];
    return children.every((key) => rows.recordCreators[key] == account);
  }

  Widget wrapRecordEditor(
    Widget editor,
    String type,
    String? id, {
    bool preserveReadOnly = false,
    bool Function()? draftIdentityCurrent,
  }) => id == null
      ? wrapEditor(editor)
      : SharingSessionBoundary(
          guard: _guard,
          visibleWhen: (state) {
            if (!preserveReadOnly) return _canEdit(state, type, id);
            return state.localAccessAllowed &&
                !state.sessionInvalid &&
                !state.deletionPending &&
                (draftIdentityCurrent?.call() ?? _guard.isCurrent);
          },
          child: editor,
        );

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
    wrap: (editor) => wrapRecordEditor(editor, 'shoppingList', list?.id),
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
    onDelete: list == null || !canDeleteRecord('shoppingList', list.id)
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
        wrap: (editor) => wrapRecordEditor(editor, 'shoppingItem', item?.id),
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
        onDelete: item == null || !canDeleteRecord('shoppingItem', item.id)
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
    wrap: (editor) => wrapRecordEditor(editor, 'project', project?.id),
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
            !canDeleteRecord('project', project.id) ||
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

  static final _openTaskEditors = <(ProviderContainer, String, String)>{};

  @override
  Future<void> task({LocalTask? task, String? projectId}) async {
    final container = ProviderScope.containerOf(context, listen: false);
    final key = (container, scope.id, task?.id ?? 'new');
    if (!_openTaskEditors.add(key)) return;
    try {
      await _taskEditor(task: task, projectId: projectId);
    } finally {
      _openTaskEditors.remove(key);
    }
  }

  Future<void> _taskEditor({LocalTask? task, String? projectId}) async {
    var timerTask = task;
    final state = ref.read(collaborationProvider).valueOrNull;
    if (!guard.isCurrent || state?.localAccessAllowed != true) return;
    final taskCreator =
        data.recordCreators['content:${task?.id}'] ?? task?.createdByAccountId;
    final principal = state!.session!.accountId;
    if (task != null &&
        !SharedRecordPermissions.canEdit(
          scope: scope,
          accountId: principal,
          creator: taskCreator,
          type: 'task',
          assignees: task.assigneeAccountIds,
        ))
      throw const CollaborationException('record_edit_forbidden');
    final canAssignTask = SharedRecordPermissions.canAssign(
      scope: scope,
      accountId: principal,
      creator: taskCreator,
    );
    final canDeleteTask = SharedRecordPermissions.canDelete(
      scope: scope,
      accountId: principal,
      creator: taskCreator,
    );
    final needsChoices =
        scope.kind == SharedScopeKind.project &&
        scope.parentSpaceId != null &&
        state.organizationFinanceSupported == true;
    var choices = {
      for (final a
          in state.financeAccountChoices[scope.id] ??
              <SharedFinanceAccountChoice>[])
        '${a.scopeId}:${a.id}': a,
    };
    var linkedCost = task == null
        ? null
        : data.financeEntries
              .where((entry) => entry.taskId == task!.id)
              .firstOrNull;
    bool canReadCostPolicy(CollaborationState? value) =>
        value?.localAccessAllowed == true &&
        value?.financePolicyForScope(scope.id).canRead == true;
    bool canReadCost(CollaborationState? value) =>
        canReadCostPolicy(value) &&
        value?.financeSnapshotComplete[scope.id] == true;
    bool costWriteRights(CollaborationState? value) {
      final currentScope = _currentScope(value);
      if (!canReadCostPolicy(value) ||
          currentScope == null ||
          (value?.recordContractVersion ?? 1) < 3 ||
          (value?.financeContractVersion ?? 1) < 2 ||
          value?.financePolicyForScope(scope.id).canWrite != true) {
        return false;
      }
      if (currentScope.recordPolicyVersion != 1) return currentScope.canEdit;
      if (task == null
          ? !currentScope.canEdit
          : !_canEdit(value, 'task', task!.id)) {
        return false;
      }
      final currentData = value!.dataForScope(scope.id);
      final currentCost = task == null
          ? null
          : currentData.financeEntries
                .where((entry) => entry.taskId == task!.id)
                .firstOrNull;
      // Creating a financial record and editing an existing one use their own
      // authority. Task assignment alone never grants a foreign cost edit.
      if (currentCost == null) return currentScope.canEdit;
      return SharedRecordPermissions.canEdit(
        scope: currentScope,
        accountId: value.session!.accountId,
        creator:
            currentData.recordCreators['finance:${currentCost.id}'] ??
            currentCost.createdByAccountId,
        type: 'financeEntry',
      );
    }

    bool canWriteCost(CollaborationState? value) =>
        canReadCost(value) && costWriteRights(value);

    var canEditCost = canWriteCost(state) && !needsChoices;
    final newTaskId = newSharedId();
    var financeGuard = linkedCost == null
        ? null
        : FinanceAccessGuard(context, ref, scope.id);

    final editorController = ref.read(collaborationProvider.notifier);
    final editorIdentity = editorController.editorSessionIdentity;
    bool draftIdentityCurrent() =>
        guard.isCurrent &&
        editorController.editorSessionIdentity == editorIdentity;
    final updates = OrganizerEditorUpdates()
      ..isCurrent = draftIdentityCurrent
      ..allowLocalDraftContinuation =
          task != null && _canEdit(state, 'task', task.id);
    OrganizerDraft taskDraft(LocalTask? task, SharedFinanceEntry? linkedCost) =>
        OrganizerDraft(
          isCompleted: task?.isCompleted ?? false,
          timer: task?.timer ?? const TaskTimerState(),
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
        );

    String costSignature(OrganizerDraft draft) => jsonEncode([
      draft.costEnabled,
      draft.costAmount,
      draft.costCurrency,
      draft.costPaid,
      draft.costPaidAt?.toIso8601String(),
      draft.ledgerAccountId,
      draft.payerPersonId,
      draft.recipientPersonId,
      draft.createdByPersonId,
    ]);
    final initialDraft = taskDraft(task, linkedCost);
    var initialCost = costSignature(initialDraft);
    var open = true;
    var preparationFailed = false;
    var preparationStarted = false;
    var choicesReady = !needsChoices;
    late final VoidCallback prepareChoices;
    updates.financeLoading =
        needsChoices && linkedCost != null && canReadCostPolicy(state);
    void updateFinance(CollaborationState? value, {bool notify = true}) {
      choices = {
        for (final a
            in value?.financeAccountChoices[scope.id] ??
                <SharedFinanceAccountChoice>[])
          '${a.scopeId}:${a.id}': a,
      };
      canEditCost =
          canWriteCost(value) &&
          choicesReady &&
          !updates.financeLoading &&
          !preparationFailed;
      updates.editingAllowed =
          draftIdentityCurrent() &&
          (task == null
              ? _currentScope(value)?.canEdit == true
              : _canEdit(value, 'task', task!.id));
      updates.costEditingEnabled = canEditCost && updates.editingAllowed;
      // Opening the section requests fresh options; it grants no cost authority.
      updates.onCostSectionOpened =
          linkedCost == null &&
              needsChoices &&
              costWriteRights(value) &&
              updates.editingAllowed
          ? prepareChoices
          : null;
      updates.costVisible = canReadCost(value);
      updates.financeUnavailable = preparationFailed;
      updates.financeAccountChoices = {
        for (final choice in choices.entries)
          choice.key: (
            name: choice.value.name,
            currency: choice.value.currency,
            archived: choice.value.archived,
          ),
        if (linkedCost?.accountScopeId != null &&
            !choices.containsKey(
              '${linkedCost!.accountScopeId}:${linkedCost!.accountId}',
            ))
          '${linkedCost!.accountScopeId}:${linkedCost!.accountId}': (
            name: context.l10n.financeUnavailableAccount,
            currency: linkedCost!.currency,
            archived: true,
          ),
      };
      if (notify) updates.financeChanged();
    }

    prepareChoices = () {
      if (!open || !draftIdentityCurrent() || preparationStarted) return;
      final current = ref.read(collaborationProvider).valueOrNull;
      if (linkedCost == null
          ? !costWriteRights(current)
          : !canReadCostPolicy(current)) {
        return;
      }
      preparationStarted = true;
      updates.financeLoading = true;
      updateFinance(current);
      unawaited(() async {
        try {
          await controller.refreshFinanceAccountChoices(scope.id);
          choicesReady = true;
        } catch (_) {
          preparationFailed = true;
        }
        if (!open || !draftIdentityCurrent()) return;
        updates.financeLoading = false;
        updateFinance(ref.read(collaborationProvider).valueOrNull);
      }());
    };
    updateFinance(state, notify: false);
    String? lastTask = task == null ? null : jsonEncode(task.toJson());
    String? lastCost = linkedCost == null
        ? null
        : jsonEncode(linkedCost.toJson());
    final subscription = ProviderScope.containerOf(context, listen: false).listen(
      collaborationProvider,
      (previous, next) {
        // Provider publication can happen during a parent build. Apply once the
        // current frame completes, and never after closing/changing identity.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!open) return;
          if (!draftIdentityCurrent()) {
            updates.editingAllowed = false;
            updates.costVisible = false;
            updates.financeChanged();
            return;
          }
          final value = next.valueOrNull;
          updateFinance(value);
          if (task == null) return;
          final latestData = value?.dataForScope(scope.id);
          final latest = latestData?.tasks
              .where((row) => row.id == task!.id)
              .firstOrNull;
          if (latest == null) {
            updates.editingAllowed = false;
            updates.costVisible = false;
            updates.financeChanged();
            return;
          }
          final cost = latestData?.financeEntries
              .where((row) => row.taskId == latest.id)
              .firstOrNull;
          final taskVersion = jsonEncode(latest.toJson());
          final costVersion = cost == null ? null : jsonEncode(cost.toJson());
          if (lastTask == taskVersion && lastCost == costVersion) return;
          lastTask = taskVersion;
          lastCost = costVersion;
          final replacement = taskDraft(latest, cost);
          updates.replaceDraft(replacement, () {
            task = timerTask = latest;
            linkedCost = cost;
            initialCost = costSignature(replacement);
            financeGuard = cost == null
                ? null
                : FinanceAccessGuard(context, ref, scope.id);
            updateFinance(value, notify: false);
            if (needsChoices && cost != null && !preparationStarted) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                prepareChoices();
              });
            }
          });
        });
      },
    );
    if (needsChoices && linkedCost != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        prepareChoices();
      });
    }
    try {
      await showOrganizerEditor(
        context,
        heading: task == null
            ? context.l10n.organizerAddTask
            : context.l10n.organizerEditTask,
        sharedPolicyScopeId: scope.id,
        updates: updates,
        onReport: task == null
            ? null
            : () => showContentReport(
                context,
                ref,
                scopeId: scope.id,
                targetType: 'record',
                targetId: task!.id,
              ),
        kind: OrganizerEditorKind.task,
        recordId: task?.id,
        projects: data.projects,
        householdPeople: data.people,
        projectSelectionEnabled:
            scope.projectRootId == null && scope.parentSpaceId == null,
        costEditingEnabled: canEditCost,
        costAccountRequired: true,
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
                if (!draftIdentityCurrent()) {
                  throw const CollaborationException('session_changed');
                }
                if (!await showSharedContentPolicy(
                  context,
                  scopeId: scope.id,
                  allowOfflineDraft: true,
                )) {
                  return timerTask!;
                }
                if (!draftIdentityCurrent()) {
                  throw const CollaborationException('session_changed');
                }
                timerTask = await controller.toggleTaskTimer(
                  scope.id,
                  timerTask!,
                );
                return timerTask!;
              },
        people: people,
        assignmentEnabled: task == null || canAssignTask,
        creatorLabel: _creator(task?.createdByAccountId),
        draft: initialDraft,
        errorMessage: (error) => sharingErrorMessage(context, error),
        wrap: (editor) => wrapRecordEditor(
          editor,
          'task',
          task?.id,
          preserveReadOnly: true,
          draftIdentityCurrent: draftIdentityCurrent,
        ),
        onSave: (draft) async {
          if (!draftIdentityCurrent()) {
            throw const CollaborationException('session_changed');
          }
          final costChanged = costSignature(draft) != initialCost;
          if (costChanged &&
              (!canEditCost ||
                  !canWriteCost(ref.read(collaborationProvider).valueOrNull) ||
                  (financeGuard != null && !financeGuard!.isCurrent))) {
            throw const CollaborationException('finance_forbidden');
          }
          // An acknowledgement of this timer edit updates bookkeeping revision.
          // Reuse it only when every business field and timer run is unchanged.
          if (timerTask != null &&
              task != null &&
              timerTask!.timer != task!.timer) {
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
          if (costChanged && (draft.costEnabled || linkedCost != null)) {
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
        onDelete: task == null || !canDeleteTask
            ? null
            : () {
                if (!draftIdentityCurrent()) {
                  throw const CollaborationException('session_changed');
                }
                return controller.deleteTask(scope.id, task!.id);
              },
      );
    } finally {
      open = false;
      subscription.close();
      updates.dispose();
    }
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
    wrap: (editor) => wrapRecordEditor(editor, 'event', event?.id),
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
    onDelete: event == null || !canDeleteRecord('event', event.id)
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
