import 'package:flutter/material.dart';

import '../../../l10n/l10n.dart';
import '../../data/collaboration_repository.dart' show newSharedId;
import '../../data/e2ee/account_crypto_v2_workflow.dart';
import '../../data/e2ee/invite_crypto_repository.dart';
import '../../data/e2ee/session_crypto_access.dart';
import '../../data/e2ee/scope_crypto_manager.dart';
import '../../data/e2ee/crypto_json.dart';
import '../shared/sharing_errors.dart';
import '../shared/hosting_disclosure.dart';
import '../shared/sharing_invitation_details.dart';
import '../shared/verified_invitation_permissions.dart';
import '../../domain/collaboration_models.dart';
import '../../state/application_sync_activity.dart';

/// Recipient acceptance remains explicit. Owners first resume their retained
/// Send consent; changes still require a fresh verified manual review.
class CryptoInvitationPage extends StatefulWidget {
  const CryptoInvitationPage({
    required this.account,
    required this.invitationId,
    this.scopeId,
    this.label,
    this.recipientLabel,
    this.repository,
    this.preview,
    this.kind,
    this.expectedAcceptance,
    this.declineSupported = false,
    this.onDeclined,
    super.key,
  });

  final AccountCryptoV2Workflow account;
  final String invitationId;
  final String? scopeId, label, recipientLabel;
  final InviteCryptoRepository? repository;
  final SharedInvitationPreview? preview;
  final SharedScopeKind? kind;
  final InvitationAcceptanceNotification? expectedAcceptance;
  final bool declineSupported;
  final Future<void> Function()? onDeclined;

  @override
  State<CryptoInvitationPage> createState() => _CryptoInvitationPageState();
}

class _CryptoInvitationPageState extends State<CryptoInvitationPage>
    with WidgetsBindingObserver {
  late final invites =
      widget.repository ??
      InviteCryptoRepository(SessionCryptoAccess(account: widget.account));
  bool _busy = false, _pending = false;
  bool _preauthorizedAccepted = false;
  bool _declined = false;
  bool _approved = false, _ownerPending = false, _manualReview = false;
  AppLifecycleState? _lifecycle;
  int _foregroundGeneration = 0;
  late final _declineActionId = newSharedId();
  Object? _error;
  VerifiedCryptoInvitation? _invite;
  ScopeRotationReview? _review;
  final _refreshClock = Stopwatch()..start();
  Duration? _lastRefresh;

  bool get _current => mounted && widget.account.directory.isCurrent();

  @override
  void initState() {
    super.initState();
    _lifecycle = WidgetsBinding.instance.lifecycleState;
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    _foregroundGeneration++;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state;
    if (!collaborationAppActive(state)) _foregroundGeneration++;
    if (state != AppLifecycleState.resumed ||
        !_current ||
        _busy ||
        _declined ||
        _approved ||
        ModalRoute.of(context)?.isCurrent != true ||
        (_lastRefresh != null &&
            _refreshClock.elapsed - _lastRefresh! <
                const Duration(seconds: 5))) {
      return;
    }
    _load();
  }

  Future<void> _run(
    Future<void> Function() action, {
    bool reconcileOnError = false,
  }) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (error) {
      var reconciled = false;
      if (reconcileOnError && _current) {
        // A concurrent foreground sweep may have consumed this exact request
        // while the older manual view was still open. Only verified completion
        // may replace the error; expired/invalid alone is never success.
        try {
          final result = await _attemptOwnerApproval();
          reconciled =
              result.status == ForegroundInvitationApprovalStatus.completed;
          if (reconciled && _current) setState(() => _approved = true);
        } catch (_) {
          // Keep the original actionable failure and retained local intent.
        }
      }
      if (_current && !reconciled) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<ForegroundInvitationApprovalResult> _attemptOwnerApproval() {
    final generation = _foregroundGeneration;
    return invites.finishForegroundInvitationApproval(
      scopeId: widget.scopeId!,
      invitationId: widget.invitationId,
      expectedAcceptance: widget.expectedAcceptance,
      isForegroundCurrent: () =>
          _current &&
          generation == _foregroundGeneration &&
          collaborationAppActive(_lifecycle),
    );
  }

  Future<void> _load() => _run(() async {
    if (!_current) return;
    _lastRefresh = _refreshClock.elapsed;
    // Failed or stale reloads must not leave an older grant enabled.
    setState(() {
      _invite = null;
      _review = null;
      _manualReview = false;
    });
    if (widget.scopeId != null) {
      final result = await _attemptOwnerApproval();
      if (!_current) return;
      if (result.status == ForegroundInvitationApprovalStatus.completed) {
        setState(() {
          _approved = true;
          _ownerPending = false;
          _manualReview = false;
        });
        return;
      }
      if (result.status == ForegroundInvitationApprovalStatus.pending) {
        debugPrint(
          'invitation_autoapproval pending reason=${safeForegroundInvitationApprovalReason(result.reason ?? 'invitation_approval_pending')}',
        );
        setState(() => _ownerPending = true);
        return;
      }
      setState(() {
        _manualReview = true;
        _ownerPending = false;
      });
    }
    if (widget.scopeId == null) {
      final opened = await invites.resumeAccepted(widget.invitationId);
      if (!mounted || !_current) return;
      if (opened != null) {
        Navigator.of(context).pop(opened);
        return;
      }
    }
    final invite = widget.scopeId == null
        ? await invites.inspect(invitationId: widget.invitationId)
        : await invites.acceptedRecipient(
            widget.scopeId!,
            widget.invitationId,
            acceptanceProofHash: widget.expectedAcceptance?.acceptanceProofHash,
          );
    if (!_current) return;
    final expected = widget.expectedAcceptance;
    if (expected != null) {
      final command =
          CryptoJson.decode(cryptoBase64(invite.authorization['commandBase64']))
              as Map;
      final payload = command['payload'] as Map;
      if (widget.scopeId != expected.scopeId ||
          widget.invitationId != expected.invitationId ||
          invite.response['acceptanceProofHash'] !=
              expected.acceptanceProofHash ||
          payload['creatorProofHash'] != expected.creatorProofHash ||
          payload['tokenHash'] != expected.tokenHash) {
        throw const FormatException('invitation_acceptance_changed');
      }
    }
    if (widget.scopeId == null) {
      validateInvitationReview(
        invite,
        invitationId: widget.invitationId,
        scopeId: widget.preview?.scopeId,
        creatorAccountId: widget.preview?.inviterAccountId,
      );
    }
    await invites.trustCreatorFromDirectory(invite);
    if (!_current) return;
    ScopeRotationReview? review;
    if (widget.scopeId != null) {
      final pending = await invites.manager.pendingRotationReviews(
        widget.scopeId!,
      );
      if (!_current) return;
      review = pending.isNotEmpty
          ? pending.first
          : await invites.manager.reviewRotation(widget.scopeId!);
      if (!_current) return;
    }
    setState(() {
      _invite = invite;
      _review = review;
      _pending =
          widget.scopeId == null &&
          (_pending ||
              widget.preview?.awaitingApproval == true ||
              invite.invitation['state'] == 'accepted');
      _preauthorizedAccepted = _pending && isPreauthorizedInvitation(invite);
    });
  });

  Future<void> _continue() => _run(() async {
    final invite = _invite;
    if (invite == null || !_current || _pending || _declined) return;
    if (widget.scopeId == null) {
      await invites.accept(invite, actionId: widget.invitationId);
      if (!_current) return;
      setState(() {
        _pending = true;
        _preauthorizedAccepted = isPreauthorizedInvitation(invite);
      });
      if (_preauthorizedAccepted) {
        final scope = await invites.resumeAccepted(widget.invitationId);
        if (!mounted || !_current) return;
        if (scope == null) {
          throw const FormatException('invitation_activation_incomplete');
        }
        Navigator.of(context).pop(scope);
      }
      return;
    }
    final review = _review;
    if (review == null) return;
    await invites.admit(invite, review);
    if (mounted && _current) setState(() => _approved = true);
  }, reconcileOnError: widget.scopeId != null);

  bool get _canDecline =>
      widget.declineSupported &&
      widget.scopeId == null &&
      !_pending &&
      !_declined &&
      _invite?.invitation['state'] == 'pending' &&
      _current;

  Future<void> _finishDeclined() async {
    await widget.onDeclined?.call();
    if (mounted && _current) Navigator.of(context).pop();
  }

  Future<void> _decline() => _run(() async {
    if (!_canDecline) return;
    await invites.decline(_invite!, actionId: _declineActionId);
    if (!_current) return;
    setState(() => _declined = true);
    await _finishDeclined();
  });

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.scopeId == null
                ? l.invitationFlowTitle
                : l.cryptoInvitationGrantTitle,
          ),
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  if (widget.preview != null)
                    SharingInvitationDetails(
                      invitation: widget.preview!,
                      showPermissions: false,
                      verifiedInvitation: widget.scopeId == null
                          ? _invite
                          : null,
                    )
                  else if (widget.label != null)
                    Text(
                      widget.label!,
                      style: Theme.of(context).textTheme.titleMedium,
                    )
                  else if (widget.scopeId == null)
                    Text(l.cryptoInvitationTargetUnavailable),
                  const SizedBox(height: 12),
                  Text(
                    widget.scopeId == null
                        ? l.cryptoInvitationVerifyCreator
                        : _approved
                        ? l.autoInviteReviewCompleted
                        : _manualReview
                        ? l.cryptoInvitationGrantExplanation
                        : _busy
                        ? l.autoInviteReviewProgress
                        : l.autoInviteReviewPending,
                  ),
                  HostingDisclosureForServer(
                    serverUrl:
                        widget.account.directory.session.profile.serverUrl,
                    allowLocalHttp:
                        widget.account.directory.session.profile.allowLocalHttp,
                    compact: true,
                  ),
                  if (widget.recipientLabel != null)
                    Text(
                      widget.recipientLabel!,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  if (_busy) const LinearProgressIndicator(),
                  if (_error != null)
                    Text(
                      sharingErrorMessage(context, _error!),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  if (_pending)
                    Text(
                      _preauthorizedAccepted
                          ? l.invitationFlowAccessVerificationPending
                          : l.cryptoInvitationPendingKeys,
                    ),
                  if (_approved)
                    FilledButton.icon(
                      key: const ValueKey('crypto-invitation-approved-close'),
                      onPressed: () =>
                          Navigator.of(context).pop(widget.scopeId),
                      icon: const Icon(Icons.check),
                      label: Text(l.close),
                    ),
                  if (_declined) Text(l.invitationFlowDeclined),
                  if (_invite != null)
                    VerifiedInvitationPermissions(
                      invitation: _invite!,
                      explainContent: widget.scopeId == null,
                      showOwnerProjection: widget.scopeId != null,
                    ),
                  if (_review != null) ...[
                    const SizedBox(height: 16),
                    Text(l.cryptoInvitationContentAccess),
                  ],
                  if (_invite != null &&
                      !_pending &&
                      !_declined &&
                      !_approved &&
                      _error == null &&
                      _current)
                    FilledButton(
                      key: const ValueKey('crypto-invitation-confirm'),
                      onPressed: _busy ? null : _continue,
                      child: Text(
                        widget.scopeId == null
                            ? l.invitationFlowAgreeAccept
                            : l.cryptoInvitationGrantConfirm,
                      ),
                    ),
                  if (_canDecline)
                    OutlinedButton(
                      key: const ValueKey('crypto-invitation-decline'),
                      onPressed: _busy ? null : _decline,
                      child: Text(l.invitationFlowDecline),
                    ),
                  if (_declined)
                    TextButton(
                      key: const ValueKey('crypto-invitation-declined-close'),
                      onPressed: _busy ? null : () => _run(_finishDeclined),
                      child: Text(l.close),
                    ),
                  if (widget.scopeId != null && _error != null)
                    TextButton(
                      key: const ValueKey(
                        'crypto-invitation-pending-approvals',
                      ),
                      onPressed: _busy
                          ? null
                          : () => openCryptoApprovals(context),
                      child: Text(cryptoApprovalsLabel(context)),
                    ),
                  if (!_declined &&
                      !_approved &&
                      (_error != null || _pending || _ownerPending))
                    TextButton(
                      key: const ValueKey('crypto-invitation-retry'),
                      onPressed: _busy || isSharingIdentityChanged(_error)
                          ? null
                          : _load,
                      child: Text(
                        _pending
                            ? l.cryptoSharingCheckAccess
                            : l.cryptoMigrationRetry,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
