import 'package:flutter/material.dart';

import '../../../l10n/l10n.dart';
import '../../domain/collaboration_models.dart';
import '../organizer_widgets.dart';
import 'sharing_errors.dart';

/// A membership decision is distinct from authenticating an account.
class SharingInvitationDetails extends StatelessWidget {
  const SharingInvitationDetails({super.key, required this.invitation});
  final SharedInvitationPreview invitation;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          invitation.scopeName,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (invitation.inviterName.isNotEmpty) ...[
          Text(l.emailInviteFrom(invitation.inviterName)),
          const SizedBox(height: 8),
        ],
        if (invitation.contractVersion == 3)
          Text(
            invitation.accessScope == 'project'
                ? l.sharingInviteProjectOnly
                : l.sharingInviteWholeSpace,
          ),
        Text(sharingRoleLabel(context, invitation.role)),
        if (invitation.recipientEmail != null)
          Text(l.emailInviteFor(invitation.recipientEmail!))
        else
          Text(invitation.recipientUsername),
        Text(
          '${l.sharingExpires} ${organizerDate(context, invitation.expiresAt)}',
        ),
        const SizedBox(height: 12),
        Text(l.emailInviteExplicit),
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
        ] else if (invitation.projectFinanceIncluded) ...[
          const SizedBox(height: 12),
          Text(l.organizationProjectFinanceVisibility),
        ] else ...[
          const SizedBox(height: 12),
          Text(
            invitation.kind == SharedScopeKind.project
                ? l.sharingLegacyProjectDescription
                : l.sharingLegacySpaceDescription,
          ),
        ],
      ],
    );
  }
}
