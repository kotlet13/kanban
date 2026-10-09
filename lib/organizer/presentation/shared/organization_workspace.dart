import '../../data/collaboration_repository.dart' show newSharedId;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../l10n/l10n.dart';
import '../../state/collaboration_provider.dart';
import 'sharing_forms.dart';
import 'sharing_errors.dart';
import 'sharing_session_boundary.dart';

class OrganizationWorkspace extends ConsumerWidget {
  const OrganizationWorkspace({
    super.key,
    required this.organization,
    required this.onProject,
    required this.onMembers,
  });
  final SharedScope organization;
  final ValueChanged<String> onProject;
  final ValueChanged<String> onMembers;
  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final l = context.l10n, guard = SharingSessionGuard(context, ref);
    String? id, submittedName;
    final createId = newSharedId(), requestId = newSharedId();
    await showSharingForm(
      context,
      title: l.organizationCreateProject,
      description:
          '${l.organizationProjectPreview(organization.name)}\n\n${l.organizationProjectInitialVisibility}',
      fields: [SharingField(id: 'name', label: l.organizerTitle)],
      submitLabel: l.organizationCreateProject,
      errorMessage: (error) => sharingErrorMessage(context, error),
      wrap: (form) => SharingSessionBoundary(
        guard: guard,
        visibleWhen: (state) => state.scopes.any(
          (scope) => scope.id == organization.id && scope.canManage,
        ),
        child: form,
      ),
      onSubmit: (values) async {
        id = await guard.controller.createScope(
          submittedName ??= values['name']!.trim(),
          kind: SharedScopeKind.project,
          id: createId,
          requestId: requestId,
          organizationId: organization.id,
        );
        await guard.controller.syncNow();
      },
    );
    if (!context.mounted || !guard.isCurrent || id == null) return;
    final createdId = id!;
    final openMembers = await showDialog<bool>(
      context: context,
      builder: (context) => SharingSessionBoundary(
        guard: guard,
        child: AlertDialog(
          scrollable: true,
          title: Text(l.organizationProjectCreated),
          content: Text(l.organizationProjectInitialVisibility),
          actions: [
            TextButton(
              key: const ValueKey('organization-created-open'),
              onPressed: () => Navigator.pop(context, false),
              child: Text(l.organizationProjectOpen),
            ),
            FilledButton(
              key: const ValueKey('organization-created-members'),
              onPressed: () => Navigator.pop(context, true),
              child: Text(l.sharingMembers),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted || !guard.isCurrent) return;
    if (openMembers == true) {
      onMembers(createdId);
    } else if (openMembers == false) {
      onProject(createdId);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n,
        state = ref.watch(collaborationProvider).valueOrNull;
    final projects =
        state?.scopes
            .where(
              (scope) =>
                  scope.organizationId == organization.id && !scope.revoked,
            )
            .toList() ??
        <SharedScope>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 12,
          children: [
            TextButton.icon(
              onPressed: () => onMembers(organization.id),
              icon: const Icon(Icons.group_outlined),
              label: Text(l.sharingMembers),
            ),
            if (organization.canManage && state?.sessionInvalid != true)
              FilledButton.icon(
                onPressed: () => _create(context, ref),
                icon: const Icon(Icons.add),
                label: Text(l.organizationCreateProject),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          l.organizationProjects,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        for (final project in projects.where((project) => !project.archived))
          ListTile(
            key: ValueKey('organization-project-${project.id}'),
            leading: const Icon(Icons.folder_outlined),
            title: Text(project.name),
            onTap: () => onProject(project.id),
          ),
        if (projects.any((project) => project.archived)) ...[
          Text(
            l.scopeArchivedProjects,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          for (final project in projects.where((project) => project.archived))
            ListTile(
              leading: const Icon(Icons.archive_outlined),
              title: Text(project.name),
              onTap: () => onProject(project.id),
            ),
        ],
        if (projects.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(l.organizerNoProjects),
          ),
      ],
    );
  }
}
