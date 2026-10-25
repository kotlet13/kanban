import 'sharing_role_permissions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n.dart';
import '../../data/collaboration_repository.dart' show newSharedId;
import '../../state/collaboration_provider.dart';
import 'content_moderation.dart';
import 'sharing_errors.dart';
import 'sharing_forms.dart';
import 'sharing_session_boundary.dart';

/// Opens directly at the captured scope. Project sharing never silently changes
/// to its parent space, and legacy policies retain their existing permissions.
Future<bool> showScopeInvitation(
  BuildContext context,
  WidgetRef ref, {
  required SharedScope scope,
  required AccountSession session,
}) async {
  final l = context.l10n;
  final guard = SharingSessionGuard(context, ref, session: session);
  bool current(CollaborationState state) =>
      !state.sessionInvalid &&
      !state.deletionPending &&
      !state.allSpacesSelected &&
      state.selectedSpaceId == scope.id &&
      state.session?.expiresAt.isAfter(DateTime.now()) == true &&
      state.scopes.any(
        (s) =>
            s.id == scope.id &&
            s.canManage &&
            !s.blocked &&
            !s.archived &&
            s.accessRevision == scope.accessRevision &&
            s.accessPolicyVersion == scope.accessPolicyVersion,
      );
  if (!guard.isCurrent ||
      !current(ref.read(collaborationProvider).requireValue)) {
    return false;
  }
  final initial = ref.read(collaborationProvider).requireValue;
  final username =
      initial.usernameInvitationsSupported && scope.accessPolicyVersion == 3;
  if ((!initial.emailInvitationsSupported && !username) ||
      (scope.accessPolicyVersion == 3 && !initial.scopedInvitationsSupported)) {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.emailInviteTitle),
        content: Text(l.emailInviteUnsupported),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l.close),
          ),
        ],
      ),
    );
    return false;
  }
  String? submittedKey, requestId, requestLanguage;
  SharedInvitation? sent;
  await showSharingForm(
    context,
    title: l.sharingInvitePerson,
    description: scope.name,
    fields: [
      SharingField(
        id: 'recipient',
        label: username ? l.spaceFlowRecipient : l.accountEmail,
        keyboardType: TextInputType.emailAddress,
        validator: (value, _) {
          final recipient = value.trim();
          return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(recipient) ||
                  username &&
                      RegExp(r'^[a-zA-Z0-9_.-]{3,64}$').hasMatch(recipient)
              ? null
              : l.spaceFlowRecipientInvalid;
        },
      ),
      SharingField(
        id: 'role',
        label: l.sharingRole,
        initialValue: 'member',
        advanced: true,
        options: {
          'member': scope.accessPolicyVersion == 3
              ? sharingInvitationRoleLabel(
                  l,
                  'member',
                  recordPolicyVersion: scope.recordPolicyVersion,
                )
              : l.sharingMember,
          'viewer': scope.accessPolicyVersion == 3
              ? sharingInvitationRoleLabel(
                  l,
                  'viewer',
                  recordPolicyVersion: scope.recordPolicyVersion,
                )
              : l.sharingViewer,
        },
      ),
    ],
    detailsBuilder: (values) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          scope.accessPolicyVersion == 3
              ? scope.kind == SharedScopeKind.project
                    ? l.sharingInviteProjectDescription
                    : l.sharingInviteSpaceDescription
              : scope.kind == SharedScopeKind.project
              ? l.sharingLegacyProjectDescription
              : l.sharingLegacySpaceDescription,
        ),
        if (scope.accessPolicyVersion == 3) ...[
          const SizedBox(height: 12),
          Text(
            sharingPermissionDescription(
              l,
              values['role'] ?? 'member',
              recordPolicyVersion: scope.recordPolicyVersion,
            ),
          ),
          const SizedBox(height: 12),
          Text(l.sharingInvitationNewAccountAccess),
        ],
      ],
    ),
    submitLabel: l.spaceFlowSend,
    errorMessage: (error) => sharingErrorMessage(context, error),
    wrap: (form) =>
        SharingSessionBoundary(guard: guard, visibleWhen: current, child: form),
    onSubmit: (values) async {
      if (!guard.isCurrent ||
          !current(ref.read(collaborationProvider).requireValue)) {
        throw const CollaborationException('access_revoked');
      }
      if (!await showSharedContentPolicy(context, scopeId: scope.id)) {
        throw const CollaborationException('policy_acceptance_cancelled');
      }
      if (!context.mounted ||
          !guard.isCurrent ||
          !current(ref.read(collaborationProvider).requireValue)) {
        throw const CollaborationException('access_revoked');
      }
      final entered = values['recipient']!.trim();
      final recipient = entered.toLowerCase();
      final key = '${recipient.toLowerCase()}:${values['role']}';
      if (key != submittedKey) {
        submittedKey = key;
        requestId = newSharedId();
        requestLanguage = Localizations.localeOf(context).languageCode;
      }
      sent = await guard.controller.createRecipientInvitation(
        scopeId: scope.id,
        recipient: recipient,
        role: SharedRole.values.byName(values['role']!),
        accessScope: scope.accessPolicyVersion == 3
            ? scope.kind == SharedScopeKind.project
                  ? 'project'
                  : 'space'
            : null,
        requestId: requestId,
        language: requestLanguage!,
      );
    },
  );
  if (sent == null || !context.mounted || !guard.isCurrent) return false;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        sent!.deliveryQueued
            ? l.emailInviteQueued(
                sent!.recipientEmail ?? sent!.recipientUsername,
              )
            : l.spaceFlowInAppSent,
      ),
    ),
  );
  return true;
}
