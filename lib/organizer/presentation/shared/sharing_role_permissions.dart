import '../../../l10n/app_localizations.dart';

/// The policy version chooses display copy only; signed membership and record
/// authorization continue to decide permissions.
String sharingPermissionDescription(
  AppLocalizations l,
  String role, {
  required int recordPolicyVersion,
}) {
  if (recordPolicyVersion == 1) {
    return switch (role) {
      'owner' => l.sharingRecordOwnerDescription,
      'viewer' => l.sharingRecordViewerDescription,
      _ => l.sharingRecordMemberDescription,
    };
  }
  return role == 'viewer'
      ? l.sharingViewerDescription
      : l.sharingMemberFullDescription;
}

String sharingInvitationRoleLabel(
  AppLocalizations l,
  String role, {
  required int recordPolicyVersion,
}) => recordPolicyVersion == 1
    ? switch (role) {
        'owner' => l.sharingOwner,
        'viewer' => l.sharingViewer,
        _ => l.sharingMember,
      }
    : role == 'viewer'
    ? l.spaceFlowViewOnly
    : l.spaceFlowFullAccess;
