import 'package:flutter/material.dart';

import '../../../l10n/l10n.dart';
import '../../domain/collaboration_models.dart';
import '../organizer_errors.dart';

String sharingErrorMessage(BuildContext context, Object error) {
  if (error is! CollaborationException) {
    return organizerErrorMessage(context, error);
  }
  final l = context.l10n;
  return switch (error.code) {
    'password_too_short' => l.accountPasswordTooShort,
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
    'scope_archived' => l.scopeArchivedDescription,
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
