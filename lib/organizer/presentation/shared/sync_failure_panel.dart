import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n.dart';
import '../../data/e2ee/account_directory_v2.dart'
    show CryptoDirectoryException;
import '../../data/e2ee/crypto_sync_repository.dart'
    show CryptoAuthorityPending;
import '../../state/collaboration_provider.dart';
import '../onboarding/account_email_card.dart';
import '../recovery/account_crypto_wizard.dart';
import '../recovery/crypto_approvals_page.dart';
import 'content_moderation.dart';
import 'received_invitation_notice.dart';
import 'sharing_auth.dart';
import 'sharing_session_boundary.dart';

String _text(BuildContext context, String sl, String en) =>
    Localizations.localeOf(context).languageCode == 'sl' ? sl : en;

/// Older callers can still publish only a summary. Its provenance stays at
/// account level; the selected space must never become an inferred cause.
List<SyncFailureDetails> sharingSyncFailures(
  CollaborationState state,
  Object? backgroundError,
) {
  String reason(Object error) => switch (error) {
    CollaborationException() => error.code,
    CryptoAuthorityPending() => error.reason,
    CryptoDirectoryException() => error.code,
    _ => 'unknown',
  };
  return [
    ...state.syncFailures,
    if (state.syncFailures.isEmpty && state.lastError != null)
      SyncFailureDetails(
        stage: SyncFailureStage.unknown,
        occurredAt: null,
        reason: reason(state.lastError!),
      ),
    if (backgroundError != null &&
        !identical(backgroundError, state.lastError) &&
        !state.syncFailures.any(
          (failure) =>
              failure.reason == safeSyncFailureReason(reason(backgroundError)),
        ))
      SyncFailureDetails(
        stage: SyncFailureStage.unknown,
        occurredAt: null,
        reason: reason(backgroundError),
      ),
  ];
}

enum _Review {
  email,
  protection,
  session,
  invitations,
  approvals,
  rules,
  conflicts,
}

_Review? _reviewFor(String reason) => switch (reason) {
  'email_verification_required' => _Review.email,
  'crypto_migration_required' ||
  'crypto_device_keys_pending' => _Review.protection,
  'auth_required' || 'unauthenticated' || 'session_expired' => _Review.session,
  'invitation_acceptance_required' ||
  'invitation_proof_pending' => _Review.invitations,
  'crypto_access_approval_required' ||
  'crypto_lifecycle_approval_required' ||
  'crypto_inherited_invitation_pending' ||
  'crypto_inherited_invitation_manager_required' => _Review.approvals,
  'policy_acceptance_required' => _Review.rules,
  'conflict' => _Review.conflicts,
  _ => null,
};

String _reviewLabel(BuildContext context, _Review review) => switch (review) {
  _Review.email => _text(
    context,
    'Preveri e-poštni naslov',
    'Review email address',
  ),
  _Review.protection => _text(
    context,
    'Preglej zaščito računa',
    'Review account protection',
  ),
  _Review.session => context.l10n.sharingLoginAction,
  _Review.invitations => _text(
    context,
    'Preglej povabila',
    'Review invitations',
  ),
  _Review.approvals => _text(
    context,
    'Čakajoče odobritve',
    'Pending approvals',
  ),
  _Review.rules => context.l10n.moderationPolicyTitle,
  _Review.conflicts => context.l10n.sharingConflictsButton,
};

String syncFailureExplanation(
  BuildContext context,
  String reason,
) => switch (reason) {
  'email_verification_required' => _text(
    context,
    'Sinhronizacija zahteva potrjen e-poštni naslov tega računa.',
    'Sync requires a verified email address for this account.',
  ),
  'auth_required' || 'unauthenticated' || 'session_expired' => _text(
    context,
    'Prijava je potekla. Za nadaljevanje se znova prijavi v isti račun.',
    'Your session has expired. Sign in to the same account to continue.',
  ),
  'device_revoked' => _text(
    context,
    'Dostop te naprave je bil preklican. Pred nadaljevanjem preveri dostop z upraviteljem.',
    'This device’s access was revoked. Review access with a manager before continuing.',
  ),
  'network' ||
  'network_error' ||
  'network_unavailable' ||
  'timeout' ||
  'server_unavailable' => _text(
    context,
    'Povezava ni uspela. Preveri omrežje in pozneje znova poskusi uskladitev.',
    'The connection failed. Check your network and try syncing again later.',
  ),
  'rate_limited' => _text(
    context,
    'Strežnik trenutno omejuje zahteve. Počakaj in pozneje znova poskusi.',
    'The server is limiting requests. Wait and try again later.',
  ),
  'policy_acceptance_required' => _text(
    context,
    'Pred nadaljevanjem je treba pregledati pravila za deljeno vsebino.',
    'Review the shared content rules before continuing.',
  ),
  'crypto_migration_required' || 'crypto_device_keys_pending' => _text(
    context,
    'Za ta del uskladitve je potreben pregled priprave zaščite. Preglej obstoječi postopek zaščite.',
    'This part of sync requires a review of protection setup. Review the existing protection flow.',
  ),
  'invitation_acceptance_required' || 'invitation_proof_pending' => _text(
    context,
    'Povezava prek povabila še ni dokončana. Preglej obstoječa povabila.',
    'The invitation connection is incomplete. Review your existing invitations.',
  ),
  'crypto_access_approval_required' ||
  'crypto_lifecycle_approval_required' ||
  'crypto_inherited_invitation_pending' ||
  'crypto_inherited_invitation_manager_required' => _text(
    context,
    'Sprememba dostopa čaka na pregled ali odobritev upravitelja.',
    'The access change is awaiting manager review or approval.',
  ),
  'permission_revoked' ||
  'finance_forbidden' ||
  'finance_contribution_forbidden' ||
  'scope_management_forbidden' => _text(
    context,
    'Račun nima potrebnega dostopa za ta del uskladitve. O dostopu se dogovori z upraviteljem.',
    'This account lacks the access needed for this part of sync. Ask a manager to review access.',
  ),
  'scope_deleted' => _text(
    context,
    'Ta prostor je izbrisan.',
    'This space was deleted.',
  ),
  'scope_archived' => _text(
    context,
    'Ta prostor je arhiviran.',
    'This space is archived.',
  ),
  'conflict' => _text(
    context,
    'Nekatere spremembe zahtevajo tvoj pregled, preden jih je mogoče uskladiti.',
    'Some changes need your review before they can be synced.',
  ),
  'server_identity_changed' ||
  'crypto_stale_identity' ||
  'crypto_control_signer_changed' => _text(
    context,
    'Identiteta povezave se je spremenila. Potreben je varen pregled identitete; samodejno nadaljevanje je ustavljeno.',
    'The connection identity changed. A secure identity review is needed; automatic continuation is stopped.',
  ),
  'scope_key_recovery_required' || 'crypto_native_vault_required' => _text(
    context,
    'Potrebni zaščiteni ključi trenutno niso na voljo. Uskladitev je ustavljena; ohrani obstoječe obnovitvene datoteke.',
    'Required protected keys are unavailable. Sync is stopped; retain your existing recovery files.',
  ),
  'finance_access_changed' ||
  'finance_policy_changed_during_read' ||
  'scoped_authority_changed' ||
  'crypto_access_base_changed' ||
  'crypto_member_directory_changed' ||
  'scope_review_changed' => _text(
    context,
    'Dostop se je med preverjanjem spremenil. Uskladitev tega dela še ni potrjena.',
    'Access changed during verification. Sync for this part is not yet confirmed.',
  ),
  'account_deleted' => _text(
    context,
    'Ta račun je izbrisan.',
    'This account was deleted.',
  ),
  _ => _text(
    context,
    'Tega dela uskladitve ni bilo mogoče varno dokončati. Vzrok še ni potrjen. Lokalni podatki in čakajoče spremembe ostanejo ohranjeni; podrobnosti lahko posreduješ podpori.',
    'This part of sync could not be completed safely. The cause is not yet confirmed. Local data and pending changes are retained; you can share the details with support.',
  ),
};

String _stageLabel(BuildContext context, SyncFailureStage stage) =>
    switch (stage) {
      SyncFailureStage.unknown => _text(
        context,
        'Korak ni potrjen',
        'Stage not confirmed',
      ),
      SyncFailureStage.accountCheck => _text(
        context,
        'Preverjanje računa',
        'Account check',
      ),
      SyncFailureStage.accessReview => _text(
        context,
        'Preverjanje dostopa',
        'Access review',
      ),
      SyncFailureStage.preflight => _text(
        context,
        'Priprava uskladitve',
        'Sync preparation',
      ),
      SyncFailureStage.moderation => _text(
        context,
        'Pravila vsebine',
        'Content rules',
      ),
      SyncFailureStage.metadata => _text(
        context,
        'Podatki o prostoru',
        'Space information',
      ),
      SyncFailureStage.upload => _text(
        context,
        'Pošiljanje sprememb',
        'Uploading changes',
      ),
      SyncFailureStage.download => _text(
        context,
        'Prejemanje sprememb',
        'Downloading changes',
      ),
      SyncFailureStage.financePolicy => _text(
        context,
        'Dostop do financ',
        'Finance access',
      ),
      SyncFailureStage.financeUpload => _text(
        context,
        'Pošiljanje financ',
        'Uploading finance changes',
      ),
      SyncFailureStage.financeDownload => _text(
        context,
        'Prejemanje financ',
        'Downloading finance changes',
      ),
      SyncFailureStage.notifications => _text(
        context,
        'Obvestila',
        'Notifications',
      ),
      SyncFailureStage.recordPolicy => _text(
        context,
        'Pravice za vsebino',
        'Content permissions',
      ),
      SyncFailureStage.linkedPayments => _text(
        context,
        'Povezana plačila',
        'Linked payments',
      ),
      SyncFailureStage.localProjection => _text(
        context,
        'Lokalni prikaz',
        'Local display',
      ),
      SyncFailureStage.completion => _text(
        context,
        'Zaključek uskladitve',
        'Sync completion',
      ),
    };

String _failureLocation(
  BuildContext context,
  CollaborationState state,
  SyncFailureDetails failure,
) {
  if (failure.scopeId == null) {
    return _text(
      context,
      'Račun: točen prostor ni potrjen.',
      'Account: the exact space is not confirmed.',
    );
  }
  final scope = state.scopes
      .where((scope) => scope.id == failure.scopeId)
      .firstOrNull;
  return scope == null
      ? _text(
          context,
          'Prizadeti prostor trenutno ni na seznamu.',
          'The affected space is not currently listed.',
        )
      : _text(
          context,
          'Prizadeti prostor: ${scope.name}',
          'Affected space: ${scope.name}',
        );
}

class SyncFailurePanel extends ConsumerWidget {
  const SyncFailurePanel({
    super.key,
    required this.state,
    required this.failures,
    required this.actionsEnabled,
    required this.navigationEnabled,
    required this.onConflicts,
  });
  final CollaborationState state;
  final List<SyncFailureDetails> failures;
  final bool actionsEnabled, navigationEnabled;
  final VoidCallback onConflicts;

  _Review? _availableReview(
    CollaborationState state,
    SyncFailureDetails failure,
  ) {
    if (!state.localAccessAllowed || state.deletionPending) return null;
    final review = _reviewFor(failure.reason);
    final scope = state.scopes
        .where((scope) => scope.id == failure.scopeId)
        .firstOrNull;
    if (review == _Review.approvals && scope?.canManage != true) return null;
    if (review == _Review.email && !state.emailVerificationSupported) {
      return null;
    }
    if (review == _Review.invitations &&
        !state.emailInvitationsSupported &&
        !state.usernameInvitationsSupported) {
      return null;
    }
    if (review == _Review.rules &&
        failure.scopeId != null &&
        scope?.canRead != true) {
      return null;
    }
    if (review == _Review.conflicts &&
        state.conflicts.isEmpty &&
        state.financeConflicts.isEmpty) {
      return null;
    }
    return review;
  }

  Future<void> _openReview(
    BuildContext context,
    WidgetRef ref,
    _Review review,
    SyncFailureDetails failure,
  ) async {
    final guard = SharingSessionGuard(context, ref, session: state.session);
    if (!guard.isCurrent) return;
    final current = ref.read(collaborationProvider).valueOrNull;
    if (current == null ||
        current.deletionPending ||
        !current.localAccessAllowed ||
        current.isSyncing) {
      return;
    }
    if (review != _Review.session &&
        (current.sessionInvalid ||
            current.session?.expiresAt.isAfter(DateTime.now()) != true)) {
      return;
    }
    if (review == _Review.rules) {
      await showSharedContentPolicy(context, scopeId: failure.scopeId);
      return;
    }
    if (_availableReview(current, failure) != review) return;
    if (!sharingSyncFailures(
      current,
      ref.read(collaborationBackgroundErrorProvider),
    ).any(
      (value) =>
          value.stage == failure.stage &&
          value.reason == failure.reason &&
          value.scopeId == failure.scopeId &&
          value.occurredAt == failure.occurredAt,
    )) {
      return;
    }
    if (review == _Review.conflicts) {
      onConflicts();
      return;
    }
    if (review == _Review.invitations) {
      await showReceivedInvitations(context, ref, onAccepted: (_) {});
      return;
    }
    final session = current.session!;
    if (review == _Review.session) {
      // Login intentionally clears/replaces the session while authenticating.
      // The existing sign-in route owns that transition after this guarded open.
      await showSharingSignIn(context, initialServer: session.serverUrl);
      return;
    }
    final Widget child = switch (review) {
      _Review.email => AccountEmailCard(session: session),
      _Review.protection => const AccountCryptoPanel(),
      _Review.approvals => const CryptoApprovalsPage(),
      _ => const SizedBox.shrink(),
    };
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (routeContext) => SharingSessionBoundary(
          guard: guard,
          visibleWhen: (value) =>
              !value.deletionPending && value.localAccessAllowed,
          child: review == _Review.approvals
              ? child
              : Scaffold(
                  appBar: AppBar(
                    title: Text(_reviewLabel(routeContext, review)),
                  ),
                  body: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: child,
                  ),
                ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (failures.isEmpty) return const SizedBox.shrink();
    return Column(
      key: const ValueKey('sync-failure-panel'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Text(
          _text(context, 'Kaj je ustavilo uskladitev', 'What stopped sync'),
          style: Theme.of(context).textTheme.titleSmall,
        ),
        for (final failure in failures) ...[
          const SizedBox(height: 12),
          Text(_failureLocation(context, state, failure)),
          Text(
            '${_stageLabel(context, failure.stage)}: ${syncFailureExplanation(context, failure.reason)}',
          ),
          if (_availableReview(state, failure) case final review?)
            TextButton(
              key: ValueKey('sync-remediation-${review.name}'),
              onPressed:
                  navigationEnabled &&
                      state.localAccessAllowed &&
                      !state.deletionPending &&
                      (review == _Review.session || actionsEnabled)
                  ? () => _openReview(context, ref, review, failure)
                  : null,
              child: Text(_reviewLabel(context, review)),
            ),
        ],
        TextButton.icon(
          key: const ValueKey('sync-error-details'),
          onPressed: () => _showDetails(context, ref),
          icon: const Icon(Icons.info_outline, size: 18),
          label: Text(_text(context, 'Podrobnosti napake', 'Error details')),
        ),
      ],
    );
  }

  Future<void> _showDetails(BuildContext context, WidgetRef ref) async {
    final guard = SharingSessionGuard(
      context,
      ref,
      session: state.session,
      allowSignedOut: state.session == null,
    );
    if (!guard.isCurrent) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => SharingSessionBoundary(
        guard: guard,
        child: Consumer(
          builder: (context, ref, _) {
            final current = ref.watch(collaborationProvider).valueOrNull;
            final background = ref.watch(collaborationBackgroundErrorProvider);
            final entries = current == null
                ? <SyncFailureDetails>[]
                : sharingSyncFailures(current, background);
            return AlertDialog(
              title: Text(
                _text(context, 'Podrobnosti napake', 'Error details'),
              ),
              content: SizedBox(
                width: 440,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _text(
                          context,
                          'Kopija vsebuje le korak uskladitve, varno oznako vzroka in zabeleženi čas. Imena, identifikatorji, naslovi in skrivnosti niso vključeni.',
                          'The copy includes only the sync stage, a safe reason code and recorded time. Names, identifiers, addresses and secrets are excluded.',
                        ),
                      ),
                      const SizedBox(height: 12),
                      SelectableText(
                        syncFailureDiagnosticsJson(entries),
                        key: const ValueKey('sync-safe-diagnostics'),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  key: const ValueKey('sync-copy-diagnostics'),
                  onPressed: entries.isEmpty
                      ? null
                      : () async {
                          if (!guard.isCurrent) return;
                          final latest = ref
                              .read(collaborationProvider)
                              .valueOrNull;
                          if (latest == null) return;
                          await Clipboard.setData(
                            ClipboardData(
                              text: syncFailureDiagnosticsJson(
                                sharingSyncFailures(
                                  latest,
                                  ref.read(
                                    collaborationBackgroundErrorProvider,
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                  child: Text(
                    _text(context, 'Kopiraj podrobnosti', 'Copy details'),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(context.l10n.close),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
