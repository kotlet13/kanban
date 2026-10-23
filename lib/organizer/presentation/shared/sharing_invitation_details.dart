import 'package:flutter/material.dart';

import '../../../l10n/l10n.dart';
import '../../domain/collaboration_models.dart';
import '../organizer_widgets.dart';
import 'sharing_errors.dart';
import '../../data/e2ee/invite_crypto_repository.dart';
import '../../data/e2ee/crypto_invitation_display.dart';
import 'verified_invitation_permissions.dart';

/// A membership decision is distinct from authenticating an account.
class SharingInvitationDetails extends StatelessWidget {
  const SharingInvitationDetails({
    super.key,
    required this.invitation,
    this.showPermissions = true,
    this.compact = false,
    this.verifiedInvitation,
  });
  final SharedInvitationPreview invitation;
  final VerifiedCryptoInvitation? verifiedInvitation;
  // The final encrypted review renders its verified permission projection.
  final bool showPermissions, compact;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final verified = verifiedInvitation;
    final signed = verified == null
        ? null
        : verifiedInvitationPayload(verified);
    final sender = verified == null
        ? null
        : parseCryptoInvitationDisplay(verified.response);
    final senderEmail = verified == null
        ? invitation.inviterEmail
        : sender?['email'];
    final senderName = verified == null
        ? invitation.inviterName
        : sender?['displayName'] ?? '';
    final senderUsername = verified == null
        ? invitation.inviterUsername
        : sender?['username'] ?? '';
    final senderAccountId = verified == null
        ? invitation.inviterAccountId
        : verified.creator.accountId;
    // Legacy evidence already binds its retained recipient metadata. Current
    // invitations carry the recipient directly in their signed create payload.
    final recipient = verified == null
        ? null
        : (verified.legacyEvidence != null
                  ? verified.invitation['recipient']
                  : signed!['recipient'])
              as Map;
    final recipientEmail = recipient == null
        ? invitation.recipientEmail
        : recipient['kind'] == 'email'
        ? recipient['value'] as String
        : null;
    final recipientUsername = recipient == null
        ? invitation.recipientUsername
        : recipient['value'] as String;
    final expiresAt = signed == null
        ? invitation.expiresAt
        : DateTime.fromMillisecondsSinceEpoch(
            (signed['expiresAt'] as int) * 1000,
            isUtc: true,
          );
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
            senderEmail ??
                (senderName.isNotEmpty
                    ? senderUsername.isNotEmpty && senderUsername != senderName
                          ? '$senderName ($senderUsername)'
                          : senderName
                    : senderUsername.isNotEmpty
                    ? senderUsername
                    : senderAccountId ?? l.cryptoInvitationSenderUnavailable),
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
          if (recipientEmail != null)
            Text(l.emailInviteFor(recipientEmail))
          else
            Text(recipientUsername),
          Text(
            '${l.sharingExpires} ${organizerDate(context, expiresAt.toLocal())} ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(expiresAt.toLocal()), alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context))}',
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
