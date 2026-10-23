import 'package:flutter/material.dart';

import '../../../l10n/l10n.dart';
import '../../domain/collaboration_models.dart';
import '../organizer_widgets.dart';
import 'sharing_errors.dart';

/// A membership decision is distinct from authenticating an account.
class SharingInvitationDetails extends StatelessWidget {
  const SharingInvitationDetails({
    super.key,
    required this.invitation,
    this.showPermissions = true,
    this.compact = false,
  });
  final SharedInvitationPreview invitation;
  // The final encrypted review renders its verified permission projection.
  final bool showPermissions, compact;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          invitation.scopeNameAvailable
              ? l.invitationFlowInvitationTo(invitation.scopeName)
              : l.cryptoInvitationTargetUnavailable,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          l.emailInviteFrom(
            invitation.inviterName.isNotEmpty
                ? invitation.inviterUsername.isNotEmpty &&
                          invitation.inviterUsername != invitation.inviterName
                      ? '${invitation.inviterName} (${invitation.inviterUsername})'
                      : invitation.inviterName
                : invitation.inviterUsername.isNotEmpty
                ? invitation.inviterUsername
                : invitation.inviterAccountId ??
                      l.cryptoInvitationSenderUnavailable,
          ),
        ),
        const SizedBox(height: 8),
        if (showPermissions && invitation.contractVersion == 3)
          Text(
            invitation.accessScope == 'project'
                ? l.sharingInviteProjectOnly
                : l.sharingInviteWholeSpace,
          ),
        if (showPermissions)
          Text(
            invitation.contractVersion == 3
                ? invitation.role == SharedRole.viewer
                      ? l.invitationFlowViewOnly
                      : l.invitationFlowFullAccess
                : sharingRoleLabel(context, invitation.role),
          ),
        if (!compact) ...[
          if (invitation.recipientEmail != null)
            Text(l.emailInviteFor(invitation.recipientEmail!))
          else
            Text(invitation.recipientUsername),
          Text(
            '${l.sharingExpires} ${organizerDate(context, invitation.expiresAt.toLocal())} ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(invitation.expiresAt.toLocal()), alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context))}',
          ),
          const SizedBox(height: 12),
          Text(l.invitationFlowPersonalStaysPrivate),
          if (showPermissions) ...[
            if (invitation.contractVersion == 3) ...[
              const SizedBox(height: 12),
              Text(
                invitation.accessScope == 'project'
                    ? l.sharingInviteProjectDescription
                    : l.sharingInviteSpaceDescription,
              ),
              const SizedBox(height: 12),
              Text(
                invitation.role == SharedRole.viewer
                    ? l.sharingViewerDescription
                    : l.sharingMemberFullDescription,
              ),
            ] else if (invitation.contractVersion != 4 &&
                invitation.projectFinanceIncluded) ...[
              const SizedBox(height: 12),
              Text(l.organizationProjectFinanceVisibility),
            ] else if (invitation.contractVersion != 4) ...[
              const SizedBox(height: 12),
              Text(
                invitation.kind == SharedScopeKind.project
                    ? l.sharingLegacyProjectDescription
                    : l.sharingLegacySpaceDescription,
              ),
            ],
          ],
        ],
      ],
    );
  }
}
