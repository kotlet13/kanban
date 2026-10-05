import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n.dart';
import '../../domain/organizer_models.dart';
import '../../state/collaboration_provider.dart';
import '../collection_actions.dart';
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
          label: member.displayName.isEmpty
              ? member.username
              : member.displayName,
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
        state.scopes
            .where((item) => item.id == scope.id)
            .firstOrNull
            ?.canEdit ??
        false,
    child: editor,
  );

  @override
  String errorMessage(Object error) => sharingErrorMessage(context, error);

  SharingSessionGuard get guard => _guard;
  CollaborationController get controller => _guard.controller;

  @override
  Future<void> run(Future<void> Function() action) async {
    try {
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
  }) async {
    await controller.createShoppingItem(
      scopeId: scope.id,
      listId: listId,
      title: title,
      quantity: '1',
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
  Future<void> project([
    LocalProject? project,
    ProjectArea area = ProjectArea.personal,
  ]) => showOrganizerEditor(
    context,
    heading: project == null
        ? context.l10n.organizerAddProject
        : context.l10n.organizerEditProject,
    kind: OrganizerEditorKind.project,
    draft: OrganizerDraft(
      title: project?.title ?? '',
      notes: project?.description ?? '',
      area: project?.area ?? area,
      startAt: project?.startAt,
      endAt: project?.endAt,
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
          ),
        );
      }
    },
    onDelete: project == null
        ? null
        : () => controller.deleteProject(scope.id, project.id),
  );

  @override
  Future<void> task({LocalTask? task, String? projectId}) =>
      showOrganizerEditor(
        context,
        heading: task == null
            ? context.l10n.organizerAddTask
            : context.l10n.organizerEditTask,
        kind: OrganizerEditorKind.task,
        projects: data.projects,
        people: people,
        assignmentEnabled: true,
        creatorLabel: _creator(task?.createdByAccountId),
        draft: OrganizerDraft(
          title: task?.title ?? '',
          notes: task?.notes ?? '',
          projectId: task?.projectId ?? projectId,
          date: task?.dueAt,
          startAt: task?.startAt,
          endAt: task?.endAt,
          assigneeIds: task?.assigneeAccountIds ?? const [],
        ),
        errorMessage: (error) => sharingErrorMessage(context, error),
        wrap: wrapEditor,
        onSave: (draft) async {
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
            );
          } else {
            await controller.updateTask(
              scope.id,
              task.copyWith(
                title: draft.title,
                notes: draft.notes,
                projectId: draft.projectId,
                dueAt: draft.date,
                startAt: draft.startAt,
                endAt: draft.endAt,
                assigneeAccountIds: draft.assigneeIds,
              ),
            );
          }
        },
        onDelete: task == null
            ? null
            : () => controller.deleteTask(scope.id, task.id),
      );
  Future<void> event([SharedEvent? event]) => showOrganizerEditor(
    context,
    heading: event == null
        ? context.l10n.organizerAddEvent
        : context.l10n.organizerEditEvent,
    kind: OrganizerEditorKind.event,
    projects: data.projects,
    people: people,
    assignmentEnabled: true,
    creatorLabel: _creator(event?.createdByAccountId),
    draft: OrganizerDraft(
      title: event?.title ?? '',
      notes: event?.notes ?? '',
      projectId: event?.projectId,
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
      tasks: data.tasks,
      shoppingLists: data.shoppingLists,
      shoppingItems: data.shoppingItems,
    );
