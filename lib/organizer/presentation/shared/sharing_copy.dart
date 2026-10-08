import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n.dart';
import '../../domain/organizer_models.dart';
import '../../state/collaboration_provider.dart';
import 'sharing_errors.dart';
import 'sharing_forms.dart';
import 'sharing_session_boundary.dart';

Future<void> showPublishPersonalCopy(
  BuildContext context,
  WidgetRef ref, {
  required OrganizerSnapshot personal,
  LocalShoppingList? list,
  LocalProject? project,
  required VoidCallback onConnect,
  required void Function(String scopeId, String recordId) onPublished,
}) async {
  assert((list == null) != (project == null));
  CollaborationState state;
  try {
    state = await ref.read(collaborationProvider.future);
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(sharingErrorMessage(context, error))),
      );
      onConnect();
    }
    return;
  }
  if (!context.mounted) return;
  final session = state.session;
  if (session == null) {
    onConnect();
    return;
  }
  final scopes = state.scopes
      .where(
        (scope) =>
            scope.canEdit &&
            scope.kind != SharedScopeKind.personal &&
            scope.kind != SharedScopeKind.organization &&
            (project == null ||
                (scope.projectRootId == null && scope.organizationId == null)),
      )
      .toList();
  if (scopes.isEmpty) {
    onConnect();
    return;
  }
  final guard = SharingSessionGuard(context, ref, session: session);
  String? copiedId;
  String? destinationId;
  final l = context.l10n;
  final referencedPeople = <String>{
    for (final task in personal.tasks.where(
      (task) => task.projectId == project?.id,
    )) ...[
      if (task.assigneePersonId != null) task.assigneePersonId!,
      ...task.subjectPersonIds,
    ],
  };
  final personReview = project != null && referencedPeople.isNotEmpty
      ? '\n\n${l.peopleCopyDescription}\n${personal.people.where((person) => referencedPeople.contains(person.id)).map((person) => person.name).join(', ')}'
      : '';
  await showSharingForm(
    context,
    title: l.sharingCopyAction,
    description:
        '${list?.title ?? project!.title}\n\n${l.sharingCopyDescription}$personReview',
    fields: [
      SharingField(
        id: 'destination',
        label: l.sharingSelectDestination,
        initialValue: scopes.first.id,
        options: {for (final scope in scopes) scope.id: scope.name},
      ),
    ],
    submitLabel: l.sharingCopyAction,
    errorMessage: (error) => sharingErrorMessage(context, error),
    wrap: (form) => SharingSessionBoundary(guard: guard, child: form),
    onSubmit: (values) async {
      final current = ref.read(collaborationProvider).valueOrNull?.session;
      if (current?.partition != session.partition ||
          current?.deviceId != session.deviceId) {
        throw const CollaborationException('session_changed');
      }
      final scopeId = values['destination']!;
      final controller = guard.controller;
      copiedId = list != null
          ? await controller.publishShoppingList(
              scopeId: scopeId,
              list: list,
              items: personal.shoppingItems
                  .where((item) => item.listId == list.id)
                  .toList(),
            )
          : await controller.publishProject(
              scopeId: scopeId,
              project: project!,
              people: personal.people,
              tasks: personal.tasks
                  .where((task) => task.projectId == project.id)
                  .toList(),
            );
      destinationId = scopeId;
    },
  );
  if (context.mounted && copiedId != null && destinationId != null) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l.sharingCopyDone)));
    onPublished(destinationId!, copiedId!);
  }
}
