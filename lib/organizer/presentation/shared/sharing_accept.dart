import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../platform/invitation_links/invitation_link.dart';
import '../../state/collaboration_provider.dart';
import 'invitation_wizard.dart';

Future<void> showAcceptSharingInvite(
  BuildContext context,
  WidgetRef ref, {
  required ValueChanged<String> onAccepted,
  String initialToken = '',
}) async {
  final session = ref.read(collaborationProvider).valueOrNull?.session;
  await showInvitationWizard(
    context,
    ref,
    initialLink: initialToken.isEmpty || session == null
        ? null
        : InvitationLink.tryParseInput(
            initialToken,
            serverUrl: session.serverUrl,
          ),
    onAccepted: onAccepted,
  );
}
