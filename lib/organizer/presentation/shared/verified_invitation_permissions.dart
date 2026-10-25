import 'sharing_role_permissions.dart';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../l10n/l10n.dart';
import '../../data/e2ee/invite_crypto_repository.dart';
import '../../data/e2ee/crypto_json.dart';
import '../../data/e2ee/crypto_invitation_display.dart';

Map verifiedInvitationPayload(VerifiedCryptoInvitation invitation) =>
    invitation.legacyEvidence?.acceptancePayload ??
    (CryptoJson.decode(
              base64Decode(invitation.authorization['commandBase64'] as String),
            )
            as Map)['payload']
        as Map;

bool isPreauthorizedInvitation(VerifiedCryptoInvitation invitation) =>
    verifiedInvitationPayload(invitation)['preauthorization'] is Map;

/// Bind a recipient decision to the requested signed invitation.
void validateInvitationReview(
  VerifiedCryptoInvitation invitation, {
  required String invitationId,
  String? scopeId,
  String? creatorAccountId,
}) {
  parseCryptoInvitationDisplay(invitation.response);
  final signed = verifiedInvitationPayload(invitation);
  final recipient = invitation.legacyEvidence == null
      ? signed['recipient']
      : invitation.invitation['recipient'];
  if (signed['invitationId'] != invitationId ||
      scopeId != null && signed['scopeId'] != scopeId ||
      creatorAccountId != null &&
          creatorAccountId != invitation.creator.accountId ||
      !const {'owner', 'member', 'editor', 'viewer'}.contains(signed['role']) ||
      signed['expiresAt'] is! int ||
      recipient is! Map ||
      !const {'email', 'username'}.contains(recipient['kind']) ||
      recipient['value'] is! String ||
      (recipient['value'] as String).isEmpty) {
    throw const FormatException('invitation_review_binding');
  }
}

/// Recipient roles use the verified signed payload. An owner's existing grant
/// review also shows the current proposed membership projection.
class VerifiedInvitationPermissions extends StatelessWidget {
  const VerifiedInvitationPermissions({
    required this.invitation,
    this.explainContent = false,
    this.showOwnerProjection = false,
    super.key,
  });

  final VerifiedCryptoInvitation invitation;
  final bool explainContent, showOwnerProjection;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final signed = verifiedInvitationPayload(invitation);
    final preauthorization = signed['preauthorization'];
    final proposed = showOwnerProjection
        ? invitation.response['proposedMember'] as Map?
        : preauthorization is Map
        ? preauthorization['member'] as Map?
        : null;
    final role = showOwnerProjection
        ? (proposed?['role'] ?? signed['role'])
        : signed['role'];
    final label = switch (role) {
      'owner' => l.sharingOwner,
      'member' || 'editor' => l.sharingMember,
      'viewer' => l.sharingViewer,
      _ => throw const FormatException('invitation_role'),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Text('${l.cryptoSharingAccessLabel}: $label'),
        if ((invitation.response['scope'] as Map?)?['recordPolicyVersion'] == 1)
          Text(
            sharingPermissionDescription(
              l,
              role as String,
              recordPolicyVersion: 1,
            ),
          ),
        if (proposed != null) ...[
          Text(switch (proposed['financeRole']) {
            'write' => l.cryptoSharingFinanceWrite,
            'read' => l.cryptoSharingFinanceRead,
            _ => l.cryptoSharingFinanceNone,
          }),
          if (proposed['manageKeys'] == true) Text(l.cryptoSharingManageAccess),
        ],
        if (explainContent) ...[
          const SizedBox(height: 12),
          Text(l.invitationFlowContentVisibility),
        ],
      ],
    );
  }
}
