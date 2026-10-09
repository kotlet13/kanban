import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../l10n/l10n.dart';
import '../../domain/organizer_models.dart';
import '../../data/organizer_repository.dart';
import '../../state/organizer_provider.dart';
import '../../state/collaboration_provider.dart';
import '../shared/sharing_forms.dart';
import '../shared/sharing_errors.dart';
import '../shared/sharing_session_boundary.dart';
import '../personal_workspace_boundary.dart';

class OrganizerPeoplePage extends ConsumerWidget {
  const OrganizerPeoplePage({
    super.key,
    required this.people,
    required this.tasks,
    this.scope,
    this.onTask,
    this.readOnly = false,
  });
  final List<HouseholdPerson> people;
  final List<LocalTask> tasks;
  final SharedScope? scope;
  final Future<void> Function(LocalTask)? onTask;
  final bool readOnly;
  Future<void> _edit(
    BuildContext context,
    WidgetRef ref, [
    HouseholdPerson? person,
  ]) async {
    final l = context.l10n;
    final guard = scope == null ? null : SharingSessionGuard(context, ref);
    final workspaceKey = ref.read(organizerProvider).valueOrNull?.workspaceKey;
    final localGuard = scope == null && workspaceKey != null
        ? PersonalWorkspaceGuard(context, ref, workspaceKey)
        : null;
    await showSharingForm(
      context,
      title: person == null ? l.peopleAdd : l.peopleTitle,
      fields: [
        SharingField(
          id: 'name',
          label: l.peopleName,
          initialValue: person?.name ?? '',
        ),
        SharingField(
          id: 'notes',
          label: l.peopleNotes,
          initialValue: person?.notes ?? '',
          required: false,
          maxLines: 3,
        ),
      ],
      submitLabel: l.save,
      errorMessage: (error) => sharingErrorMessage(context, error),
      wrap: guard == null
          ? localGuard?.wrap
          : (form) => SharingSessionBoundary(guard: guard, child: form),
      onSubmit: (values) async {
        final name = values['name']!.trim(), notes = values['notes'] ?? '';
        if (scope == null) {
          if (localGuard?.isCurrent != true) {
            throw const OrganizerConflictException(
              'Personal workspace changed',
            );
          }
          final repo = await ref.read(organizerRepositoryProvider.future);
          if (localGuard?.isCurrent != true) {
            throw const OrganizerConflictException(
              'Personal workspace changed',
            );
          }
          if (person == null) {
            await repo.createPerson(
              name: name,
              notes: notes,
              expectedWorkspaceKey: workspaceKey,
            );
          } else {
            await repo.updatePerson(
              person.copyWith(name: name, notes: notes),
              expectedWorkspaceKey: workspaceKey,
            );
          }
        } else {
          if (person == null) {
            await guard!.controller.createPerson(
              scopeId: scope!.id,
              name: name,
              notes: notes,
            );
          } else {
            await guard!.controller.updatePerson(
              scope!.id,
              person.copyWith(name: name, notes: notes),
            );
          }
        }
      },
    );
  }

  Future<void> _archive(
    BuildContext context,
    WidgetRef ref,
    HouseholdPerson person,
  ) async {
    final workspaceKey = ref.read(organizerProvider).valueOrNull?.workspaceKey;
    try {
      if (scope == null) {
        final repo = await ref.read(organizerRepositoryProvider.future);
        await repo.archivePerson(
          person,
          archived: !person.archived,
          expectedWorkspaceKey: workspaceKey,
        );
      } else {
        await ref
            .read(collaborationProvider.notifier)
            .archivePerson(scope!.id, person, archived: !person.archived);
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(sharingErrorMessage(context, error))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l.peopleTitle,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            if (!readOnly)
              FilledButton.icon(
                onPressed: () => _edit(context, ref),
                icon: const Icon(Icons.person_add_alt),
                label: Text(l.peopleAdd),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(l.peopleWithoutAccountDescription),
        if (people.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(l.peopleEmpty),
          ),
        for (final person in people)
          ExpansionTile(
            key: ValueKey('person-${person.id}'),
            title: Text(person.name),
            subtitle: person.archived ? Text(l.peopleArchived) : null,
            children: [
              if (person.notes.isNotEmpty) ListTile(title: Text(person.notes)),
              if (!readOnly)
                Wrap(
                  children: [
                    TextButton(
                      onPressed: () => _edit(context, ref, person),
                      child: Text(l.edit),
                    ),
                    TextButton(
                      onPressed: () => _archive(context, ref, person),
                      child: Text(
                        person.archived ? l.peopleRestore : l.peopleArchive,
                      ),
                    ),
                  ],
                ),
              for (final task in tasks.where(
                (task) =>
                    task.assigneePersonId == person.id ||
                    task.subjectPersonIds.contains(person.id),
              ))
                ListTile(
                  leading: Icon(
                    task.isCompleted
                        ? Icons.check_circle_outline
                        : Icons.radio_button_unchecked,
                  ),
                  title: Text(task.title),
                  onTap: readOnly || onTask == null
                      ? null
                      : () => onTask!(task),
                ),
            ],
          ),
      ],
    );
  }
}
