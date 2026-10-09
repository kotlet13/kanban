import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n.dart';
import '../../state/collaboration_provider.dart';
import '../organizer_widgets.dart';
import 'sharing_errors.dart';
import 'sharing_members.dart';

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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
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
                usableSession &&
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
                ] else if (selected != null)
                  SharingMembersPage(
                    key: ValueKey(
                      'members-${session.partition}-${session.deviceId}-${selected.id}-${selected.role.name}-${selected.archived}',
                    ),
                    scope: selected,
                    session: session,
                  )
                else ...[
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
