import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n.dart';
import '../../state/collaboration_provider.dart';
import 'sharing_errors.dart';
import 'sharing_forms.dart';
import 'sharing_session_boundary.dart';
import 'sharing_invitation_details.dart';

Future<void> showAcceptSharingInvite(
  BuildContext context,
  WidgetRef ref, {
  required ValueChanged<String> onAccepted,
  String initialToken = '',
}) async {
  final guard = SharingSessionGuard(context, ref);
  final session = guard.session;
  if (session == null) return;
  String? token;
  SharedInvitationPreview? preview;
  final l = context.l10n;
  await showSharingForm(
    context,
    title: l.sharingHaveInvite,
    description: l.sharingInvitationHint,
    fields: [
      SharingField(
        id: 'token',
        label: l.sharingInvitationCode,
        initialValue: initialToken,
        sensitive: true,
      ),
    ],
    submitLabel: l.sharingPreviewInvite,
    errorMessage: (error) => sharingErrorMessage(context, error),
    wrap: (form) => SharingSessionBoundary(guard: guard, child: form),
    onSubmit: (values) async {
      token = values['token']!.trim();
      await guard.controller.rememberInvitation(
        serverUrl: session.serverUrl,
        token: token!,
        allowLocalHttp: session.allowLocalHttp,
      );
      preview = await guard.controller.previewInvitation(
        serverUrl: session.serverUrl,
        token: token!,
        allowLocalHttp: session.allowLocalHttp,
      );
    },
  );
  if (!context.mounted ||
      !guard.isCurrent ||
      preview == null ||
      token == null) {
    return;
  }
  bool accepted = false;
  final invitation = preview!;
  await showSharingForm(
    context,
    title: l.sharingAcceptInvite,
    leading: SharingInvitationDetails(invitation: invitation),
    fields: const [],
    submitLabel: l.sharingAcceptInvite,
    errorMessage: (error) => sharingErrorMessage(context, error),
    wrap: (form) => SharingSessionBoundary(guard: guard, child: form),
    onSubmit: (_) async {
      await guard.controller.acceptInvitation(token!);
      if (!guard.isCurrent) return;
      await guard.controller.selectSpace(invitation.scopeId);
      accepted = true;
    },
  );
  if (context.mounted && guard.isCurrent && accepted) {
    onAccepted(invitation.scopeId);
  }
}
