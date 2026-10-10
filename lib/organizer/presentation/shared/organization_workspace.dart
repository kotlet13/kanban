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
    this.allowProjectCreation = true,
    this.legacyProjects,
    this.titleAccessory,
  });
  final SharedScope organization;
  final ValueChanged<String> onProject;
  final ValueChanged<String> onMembers;
  final bool allowProjectCreation;
  final Widget? legacyProjects, titleAccessory;

  bool _canCreateProject(CollaborationState? state, SharedScope scope) =>
      allowProjectCreation &&
      scope.canManage &&
      scope.canEdit &&
      state?.sessionInvalid != true &&
      state?.session?.expiresAt.isAfter(DateTime.now()) == true;

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final l = context.l10n, guard = SharingSessionGuard(context, ref);
    String? id, submittedName;
    final createId = newSharedId(), requestId = newSharedId();
    await showSharingForm(
      context,
      title: organization.kind == SharedScopeKind.household
          ? l.organizerAddProject
          : l.organizationCreateProject,
      description:
          '${organization.kind == SharedScopeKind.household ? organization.name : l.organizationProjectPreview(organization.name)}\n\n${organization.accessPolicyVersion == 3 ? l.sharingProjectNewVisibility : l.organizationProjectInitialVisibility}',
      fields: [SharingField(id: 'name', label: l.organizerTitle)],
      submitLabel: organization.kind == SharedScopeKind.household
          ? l.organizerAddProject
          : l.organizationCreateProject,
      errorMessage: (error) => sharingErrorMessage(context, error),
      wrap: (form) => SharingSessionBoundary(
        guard: guard,
        visibleWhen: (state) => state.scopes.any(
          (scope) =>
              scope.id == organization.id && _canCreateProject(state, scope),
        ),
        child: form,
      ),
      onSubmit: (values) async {
        id = await guard.controller.createScope(
          submittedName ??= values['name']!.trim(),
          kind: SharedScopeKind.project,
          id: createId,
          requestId: requestId,
          parentScopeId: organization.id,
          organizationId: organization.kind == SharedScopeKind.organization
              ? organization.id
              : null,
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
          content: Text(
            organization.accessPolicyVersion == 3
                ? l.sharingProjectNewVisibility
                : l.organizationProjectInitialVisibility,
          ),
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
                  scope.parentSpaceId == organization.id && !scope.revoked,
            )
            .toList() ??
        <SharedScope>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              organization.kind == SharedScopeKind.household
                  ? l.organizerProjects
                  : l.organizationProjects,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (titleAccessory != null) titleAccessory!,
            if (_canCreateProject(state, organization))
              FilledButton.icon(
                onPressed: () => _create(context, ref),
                icon: const Icon(Icons.add),
                label: Text(
                  organization.kind == SharedScopeKind.household
                      ? l.organizerAddProject
                      : l.organizationCreateProject,
                ),
              ),
          ],
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
        if (legacyProjects != null) legacyProjects!,
        if (projects.isEmpty && legacyProjects == null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(l.organizerNoProjects),
          ),
      ],
    );
  }
}
