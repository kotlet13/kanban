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
    kind == SharedScopeKind.household
    ? context.l10n.sharingHousehold
    : kind == SharedScopeKind.personal
    ? context.l10n.privateSyncTitle
    : context.l10n.sharingProject;
