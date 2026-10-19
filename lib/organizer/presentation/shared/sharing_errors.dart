import 'package:flutter/material.dart';

import '../../../l10n/l10n.dart';
import '../../domain/collaboration_models.dart';
import '../organizer_errors.dart';
import '../../data/e2ee/account_directory_v2.dart'
    show CryptoDirectoryException;
import '../../data/e2ee/crypto_sync_repository.dart'
    show CryptoAuthorityPending;
import '../recovery/crypto_approvals_page.dart';

bool isCryptoApprovalPending(Object error) =>
    error is CryptoAuthorityPending &&
    const {
      'crypto_access_approval_required',
      'crypto_inherited_invitation_pending',
      'crypto_inherited_invitation_manager_required',
      'crypto_lifecycle_delegation_required',
      'crypto_lifecycle_approval_required',
      'crypto_access_cleanup_required',
      'crypto_leave_approval_required',
    }.contains(error.reason);

String cryptoApprovalsLabel(BuildContext context) =>
    Localizations.localeOf(context).languageCode == 'sl'
    ? 'Čakajoče odobritve'
    : 'Pending approvals';

void openCryptoApprovals(BuildContext context) => Navigator.of(
  context,
).push<void>(MaterialPageRoute(builder: (_) => const CryptoApprovalsPage()));

SnackBarAction? sharingApprovalAction(BuildContext context, Object error) =>
    !isCryptoApprovalPending(error)
    ? null
    : SnackBarAction(
        label: cryptoApprovalsLabel(context),
        onPressed: () => openCryptoApprovals(context),
      );

bool isSharingIdentityChanged(Object? error) =>
    error is CryptoDirectoryException &&
    const {
      'directory_root_changed',
      'directory_server_mismatch',
      'directory_anchor_fork',
      'directory_rollback',
    }.contains(error.code);

String sharingErrorMessage(BuildContext context, Object error) {
  if (isSharingIdentityChanged(error)) {
    return context.l10n.cryptoSharingIdentityChanged;
  }
  if (error is CryptoDirectoryException &&
          error.code == 'directory_stale_identity' ||
      error is CryptoAuthorityPending &&
          error.reason == 'crypto_stale_identity') {
    return context.l10n.sharingSessionExpired;
  }
  if (error is CryptoAuthorityPending) {
    if (const {
      'crypto_inherited_invitation_pending',
      'crypto_inherited_invitation_manager_required',
    }.contains(error.reason)) {
      return context.l10n.cryptoSharingProjectsPending;
    }
    if (const {
      'crypto_inherited_invitation_changed',
      'crypto_inherited_invitation_policy',
      'crypto_inherited_invitation_parent',
    }.contains(error.reason)) {
      return context.l10n.cryptoSharingAccessChanged;
    }
  }
  if (error is CryptoAuthorityPending &&
      error.reason == 'crypto_leave_renewal_required') {
    return Localizations.localeOf(context).languageCode == 'sl'
        ? 'Zahteva za izstop je potekla ali se je članstvo spremenilo. V Čakajočih odobritvah prekličite staro zahtevo in po novem pregledu oddajte novo.'
        : 'The leave request expired or membership changed. Cancel the old request in Pending approvals and submit a new one after reviewing the current membership.';
  }
  if (isCryptoApprovalPending(error)) {
    return Localizations.localeOf(context).languageCode == 'sl'
        ? 'Sprememba čaka na pregled upraviteljev. Odprite Čakajoče odobritve, nato nadaljujte isto shranjeno spremembo.'
        : 'This change awaits manager review. Open Pending approvals, then resume the same saved change.';
  }
  if (error is! CollaborationException) {
    return organizerErrorMessage(context, error);
  }
  final l = context.l10n;
  return switch (error.code) {
    'crypto_reconciliation_required' ||
    'crypto_transport_required' ||
    'crypto_server_upgrade_required' => l.cryptoConnectionPending,
    'email_verification_required' => l.cryptoEmailVerificationRequired,
    'policy_acceptance_cancelled' => l.moderationPolicyRequired,
    'report_stale' ||
    'report_not_found' ||
    'target_not_found' => l.moderationPreviewStale,
    'ideas_unsupported' ||
    'idea_unsupported' ||
    'idea_assets_unsupported' => l.ideasUnsupported,
    'idea_asset_missing' || 'asset_unavailable' => l.ideasMissingPhoto,
    'policy_acceptance_required' => l.moderationPolicyRequired,
    'moderation_upgrade_required' ||
    'moderation_unsupported' => l.moderationUpgradeRequired,
    'report_preview_stale' ||
    'report_target_missing' ||
    'report_target_unavailable' => l.moderationPreviewStale,
    'report_offline' => l.moderationOffline,
    'password_too_short' => l.accountPasswordTooShort,
    'space_creation_wrong_account' => l.spaceFlowCreateOtherAccount,
    'recipient_unavailable' => l.spaceFlowRecipientUnavailable,
    'username_invitations_unavailable' => l.spaceFlowUsernameUnsupported,
    'invitation_resend_unavailable' => l.sharingScopedUnsupported,
    'invitation_already_accepted' => l.sharingAccepted,
    'username_unavailable' => l.emailInviteUsernameUnavailable,
    'email_invitations_unavailable' ||
    'email_invitations_unsupported' ||
    'invitation_email_unavailable' => l.emailInviteUnsupported,
    'scoped_invitations_unsupported' ||
    'space_project_membership_unsupported' => l.sharingScopedUnsupported,
    'space_access_upgrade_required' => l.sharingScopeUpgradeRequired,
    'project_sharing_pending_changes' => l.sharingProjectSharingPending,
    'project_sharing_blocked' ||
    'project_sharing_dependency' ||
    'project_sharing_dependencies' => l.sharingProjectSharingBlocked,
    'invitation_authentication_required' => l.emailInviteExistingAccount,
    'invitation_identity_mismatch' ||
    'invitation_recipient_mismatch' ||
    'invitation_email_verification_required' => l.emailInviteWrongAccount,
    'space_bound_to_other_account' => l.localSpaceConnectionOtherAccount,
    'additional_personal_sync_unsupported' ||
    'garden_sync_unsupported' ||
    'finance_sync_unsupported' ||
    'client_upgrade_required' => l.localSpaceConnectionUnsupported,
    'use_private_sync' => l.privateSyncDescription,
    'organization_access_pending' => l.organizationAccessPending,
    'organization_preview_stale' ||
    'organization_access_preview_stale' => l.organizationAccessPreviewStale,
    'local_space_publication_pending' => l.localSpacePublicationPending,
    'scope_archived' || 'project_archived' => l.scopeArchivedDescription,
    'scope_deleted' => l.scopeDeletedDescription,
    'scope_deletion_preview_changed' => l.scopeDeletePreviewChanged,
    'scope_deletion_blocked' => l.scopeDeleteBlocked,
    'project_owner_transfer_required' => l.scopeOwnerTransferRequired,
    'single_project_guard' => l.sharingInviteProjectDescription,
    'recurring_entry_managed_by_rule' ||
    'rule_currency_immutable' => l.financePlanManageRule,
    'requires_finance_resolution' => l.financePairedConflict,
    'duplicate_finance_reference' => l.financeDuplicateOccurrence,
    'finance_account_missing' => l.financeNoAccounts,
    'task_cost_date_mismatch' => l.sharingStaleEditor,
    'deletion_pending' => l.deletionUnknown,
    'deletion_cancelled' => l.deletionCancelled,
    'deletion_unavailable' => l.deletionUnavailable,
    'deletion_preview_stale' => l.deletionStale,
    'deletion_blocked' => l.deletionBlocked,
    'account_deleted' => l.deletionSuccess,
    'email_unavailable' => l.accountEmailUnavailable,
    'account_token_invalid' || 'bootstrap_invalid' => l.accountCodeInvalid,
    'enrollment_closed' ||
    'enrollment_unavailable' => l.accountEnrollmentUnavailable,
    'two_factor_required' => l.sharingLoginNeedsOtp,
    'invalid_credentials' => l.sharingInvalidCredentials,
    'invitation_invalid' ||
    'invalid_invitation' ||
    'invitation_expired' ||
    'invitation_used' ||
    'invitation_revoked' ||
    'invalid_token' => l.sharingInvalidInvite,
    'auth_required' ||
    'unauthenticated' ||
    'session_expired' ||
    'session_changed' => l.sharingSessionExpired,
    'device_revoked' => l.sharingSessionRevoked,
    'forbidden' || 'permission_denied' => l.sharingPermissionDenied,
    'finance_forbidden' || 'finance_disabled' => l.financeNoAccess,
    'unsupported_currency' => l.financeUnsupportedCurrency,
    'finance_incomplete' => l.financeLoadingSnapshot,
    'permission_revoked' ||
    'access_revoked' ||
    'revoked' => l.sharingAccessRevoked,
    'feature_disabled' ||
    'unsupported' ||
    'unsupported_version' ||
    'native_disabled' => l.sharingUnsupported,
    'conflict' || 'stale_revision' => l.sharingConflictDescription,
    'linked_payment_exists' => l.paymentAlreadyLinked,
    'waiting_source_publication' => l.paymentWaitingSource,
    'metadata_conflict' => l.sharingStaleEditor,
    'stale_edit' => l.sharingStaleEditor,
    'changes_blocked' => l.sharingBlockedDescription,
    'record_deleted' => l.sharingDeletedConflict,
    'requires_remote_resolution' ||
    'parent_missing' ||
    'live_children' => l.sharingRelatedConflict,
    'secure_storage' ||
    'secure_storage_unavailable' => l.secureStorageUnavailable,
    'durable_storage_unavailable' => l.sharingStorageUnavailable,
    'invalid_server_url' => l.sharingInvalidServer,
    'network' => l.sharingNetworkError,
    'rate_limited' => l.sharingRateLimited,
    'auth_provider_unsupported' => l.sharingUnsupportedAuth,
    'incompatible_server' => l.sharingIncompatibleServer,
    'invalid_response' || 'redirect_rejected' => l.sharingInvalidResponse,
    'idempotency_mismatch' => l.sharingRequestMismatch,
    'validation_error' => l.sharingValidationError,
    'https_required' || 'unsafe_url' => l.secureConnectionRequired,
    _ => l.sharingOperationFailed,
  };
}

String sharingRoleLabel(BuildContext context, SharedRole role) =>
    switch (role) {
      SharedRole.owner => context.l10n.sharingOwner,
      SharedRole.member => context.l10n.sharingMember,
      SharedRole.viewer => context.l10n.sharingViewer,
    };

String sharingScopeKindLabel(BuildContext context, SharedScopeKind kind) =>
    kind == SharedScopeKind.organization
    ? context.l10n.organizationTitle
    : kind == SharedScopeKind.household
    ? context.l10n.sharingHousehold
    : kind == SharedScopeKind.personal
    ? context.l10n.privateSyncTitle
    : context.l10n.sharingProject;
