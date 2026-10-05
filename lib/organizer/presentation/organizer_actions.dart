import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../domain/organizer_models.dart';
import '../state/organizer_provider.dart';
import 'collection_actions.dart';
import 'organizer_editors.dart';
import 'organizer_errors.dart';
import 'personal_workspace_boundary.dart';
import '../data/organizer_repository.dart' show OrganizerConflictException;

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
      title: project?.title ?? '',
      notes: project?.description ?? '',
      area: project?.area ?? area,
      startAt: project?.startAt,
      endAt: project?.endAt,
    ),
    onSave: (d) => project == null
        ? controller.createProject(
            title: d.title,
            description: d.notes,
            area: d.area,
            startAt: d.startAt,
            endAt: d.endAt,
          )
        : controller.updateProject(
            project.copyWith(
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
  Future<void> task({LocalTask? task, String? projectId}) =>
      showOrganizerEditor(
        context,
        heading: task == null
            ? context.l10n.organizerAddTask
            : context.l10n.organizerEditTask,
        wrap: _guard.wrap,
        kind: OrganizerEditorKind.task,
        projects: snapshot.projects,
        draft: OrganizerDraft(
          title: task?.title ?? '',
          notes: task?.notes ?? '',
          projectId: task?.projectId ?? projectId,
          date: task?.dueAt,
          startAt: task?.startAt,
          endAt: task?.endAt,
        ),
        onSave: (d) => task == null
            ? controller.createTask(
                title: d.title,
                notes: d.notes,
                projectId: d.projectId,
                dueAt: d.date,
                startAt: d.startAt,
                endAt: d.endAt,
              )
            : controller.updateTask(
                task.copyWith(
                  title: d.title,
                  notes: d.notes,
                  projectId: d.projectId,
                  dueAt: d.date,
                  startAt: d.startAt,
                  endAt: d.endAt,
                ),
              ),
        onDelete: task == null ? null : () => controller.deleteTask(task.id),
      );

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
              currency: d.currency,
              notes: d.notes,
              projectId: d.projectId,
            ),
          ),
    onDelete: entry == null
        ? null
        : () => controller.deleteFinanceEntry(entry.id),
  );
}
