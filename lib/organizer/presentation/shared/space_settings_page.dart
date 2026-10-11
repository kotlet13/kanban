import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n.dart';
import '../../state/collaboration_provider.dart';
import '../organizer_widgets.dart';
import 'sharing_errors.dart';
import 'sharing_members.dart';
import '../../state/local_spaces_provider.dart';
import 'local_space_settings.dart';
import 'organization_access_settings.dart';
import 'project_sharing_settings.dart';
import 'sharing_forms.dart';
import 'sharing_session_boundary.dart';
import '../../data/collaboration_repository.dart' show newSharedId;

/// The only destination that displays shared-space members and invitations.
/// A missing selection is an explicit chooser, including the All view.
class SpaceSettingsPage extends ConsumerWidget {
  const SpaceSettingsPage({
    super.key,
    required this.selectedScopeId,
    required this.onScopeSelected,
    required this.onConnect,
  });

  final String? selectedScopeId;
  final ValueChanged<String?> onScopeSelected;
  final VoidCallback onConnect;

  Future<void> _editRemote(
    BuildContext context,
    WidgetRef ref,
    SharedScope scope,
  ) async {
    final guard = SharingSessionGuard(context, ref);
    final requestId = newSharedId();
    String? name, address;
    bool allows(CollaborationState state) =>
        !state.sessionInvalid &&
        !state.deletionPending &&
        state.session?.expiresAt.isAfter(DateTime.now()) == true &&
        state.selectedSpaceId == scope.id &&
        !state.allSpacesSelected &&
        state.scopes.any(
          (s) =>
              s.id == scope.id &&
              s.canManage &&
              !s.blocked &&
              s.metadataRevision == scope.metadataRevision,
        );
    await showSharingForm(
      context,
      title: context.l10n.localSpaceRename,
      fields: [
        SharingField(
          id: 'name',
          label: context.l10n.sharingSpaceName,
          initialValue: scope.name,
        ),
        SharingField(
          id: 'address',
          label: context.l10n.localSpaceAddress,
          initialValue: scope.address ?? '',
          required: false,
        ),
      ],
      submitLabel: context.l10n.save,
      errorMessage: (error) => sharingErrorMessage(context, error),
      wrap: (form) => SharingSessionBoundary(
        guard: guard,
        visibleWhen: allows,
        child: form,
      ),
      onSubmit: (values) async {
        await guard.controller.updateScopeMetadata(
          scope.id,
          name ??= values['name']!.trim(),
          address ??= values['address'] ?? '',
          expectedRevision: scope.metadataRevision,
          requestId: requestId,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final shared = ref.watch(collaborationProvider).valueOrNull;
    final local = ref.watch(localSpacesProvider).valueOrNull?.selectedSpace;
    if (shared?.allSpacesSelected != true &&
        shared?.selectedSpaceId == null &&
        local != null) {
      return LocalSpaceSettings(space: local, onConnect: onConnect);
    }
    return ref
        .watch(collaborationProvider)
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              OrganizerHeading(title: l.spaceSettingsTitle),
              Text(sharingErrorMessage(context, error)),
              TextButton(
                onPressed: () =>
                    ref.invalidate(collaborationRepositoryProvider),
                child: Text(l.organizerRetry),
              ),
            ],
          ),
          data: (state) {
            final session = state.session;
            final usableSession =
                session != null &&
                !state.sessionInvalid &&
                session.expiresAt.isAfter(DateTime.now());
            final scopes = state.scopes
                .where(
                  (scope) =>
                      scope.kind != SharedScopeKind.personal &&
                      !scope.revoked &&
                      !scope.blocked,
                )
                .toList();
            final selected =
                state.localAccessAllowed &&
                    !state.allSpacesSelected &&
                    state.selectedSpaceId == selectedScopeId
                ? scopes
                      .where((scope) => scope.id == selectedScopeId)
                      .firstOrNull
                : null;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                OrganizerHeading(title: l.spaceSettingsTitle),
                if (!usableSession && selected != null) ...[
                  Text(selected.name),
                  Text(
                    '${sharingScopeKindLabel(context, selected.kind)} · ${sharingRoleLabel(context, selected.role)}${selected.organizationLeader ? ' · ${l.organizationLeader}' : ''}',
                  ),
                  Text(l.localSpaceOfflineWork),
                  for (final member
                      in state
                          .membersForScope(selected.id)
                          .where((m) => m.active))
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        member.displayName.isEmpty
                            ? member.username
                            : member.displayName,
                      ),
                      subtitle: Text(
                        '${sharingRoleLabel(context, member.role)}${member.organizationLeader ? ' · ${l.organizationLeader}' : ''}',
                      ),
                    ),
                ],
                if (!usableSession) ...[
                  Text(
                    session == null
                        ? l.spaceSettingsConnect
                        : l.sharingSessionExpired,
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.icon(
                      onPressed: onConnect,
                      icon: const Icon(Icons.person_outline),
                      label: Text(
                        session == null
                            ? l.sharingConnect
                            : l.sharingLoginAction,
                      ),
                    ),
                  ),
                ] else if (selected != null) ...[
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(selected.name),
                    subtitle: Text(
                      [
                        sharingScopeKindLabel(context, selected.kind),
                        sharingRoleLabel(context, selected.role),
                        if (selected.organizationLeader) l.organizationLeader,
                        if (selected.address?.isNotEmpty == true)
                          selected.address!,
                        l.sharingShared,
                      ].join(' · '),
                    ),
                    trailing:
                        selected.canManage &&
                            const {
                              SharedScopeKind.household,
                              SharedScopeKind.organization,
                            }.contains(selected.kind)
                        ? IconButton(
                            key: const ValueKey('shared-space-edit'),
                            tooltip: l.localSpaceRename,
                            onPressed: () =>
                                _editRemote(context, ref, selected),
                            icon: const Icon(Icons.edit_outlined),
                          )
                        : null,
                  ),
                  if (const {
                        SharedScopeKind.organization,
                        SharedScopeKind.household,
                        SharedScopeKind.project,
                      }.contains(selected.kind) &&
                      selected.parentSpaceId == null &&
                      selected.role == SharedRole.owner &&
                      (state.spaceProjectMembershipSupported ||
                          selected.kind == SharedScopeKind.organization))
                    OrganizationAccessSettings(scope: selected),
                  if (selected.role != SharedRole.owner &&
                      selected.kind != SharedScopeKind.project)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(
                        selected.accessPolicyVersion == 3
                            ? l.sharingAccessCurrent
                            : l.sharingLegacySpaceDescription,
                      ),
                    ),
                  SharingMembersPage(
                    key: ValueKey(
                      'members-${session.partition}-${session.deviceId}-${selected.id}-${selected.role.name}-${selected.archived}-${selected.accessPolicyVersion}-${selected.accessRevision}',
                    ),
                    scope: selected,
                    session: session,
                  ),
                  if (selected.kind == SharedScopeKind.household)
                    ProjectSharingSettings(
                      scope: selected,
                      onProjectSelected: (id) => onScopeSelected(id),
                    ),
                ] else ...[
                  Text(
                    selectedScopeId == null
                        ? l.spaceSettingsChoose
                        : l.spaceSettingsUnavailable,
                  ),
                  const SizedBox(height: 16),
                  if (scopes.isEmpty) Text(l.sharingNoSpaces),
                  for (final scope in scopes)
                    Card(
                      child: ListTile(
                        key: ValueKey('space-settings-scope-${scope.id}'),
                        leading: Icon(switch (scope.kind) {
                          SharedScopeKind.household => Icons.home_outlined,
                          SharedScopeKind.organization =>
                            Icons.business_outlined,
                          _ => Icons.folder_outlined,
                        }),
                        title: Text(scope.name),
                        subtitle: Text(
                          '${sharingScopeKindLabel(context, scope.kind)} · ${sharingRoleLabel(context, scope.role)}',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => onScopeSelected(scope.id),
                      ),
                    ),
                ],
              ],
            );
          },
        );
  }
}
