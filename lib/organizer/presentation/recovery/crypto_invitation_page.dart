import 'package:flutter/material.dart';

import '../../../l10n/l10n.dart';
import '../../data/e2ee/account_crypto_v2_workflow.dart';
import '../../data/e2ee/invite_crypto_repository.dart';
import '../../data/e2ee/session_crypto_access.dart';
import '../../data/e2ee/scope_crypto_manager.dart';
import '../shared/sharing_errors.dart';
import '../shared/hosting_disclosure.dart';
import '../shared/sharing_invitation_details.dart';
import '../shared/verified_invitation_permissions.dart';
import '../../domain/collaboration_models.dart';

/// Joining and granting access remain deliberate. Signed directory validation
/// and secure first-use identity pins run without asking people to copy cards.
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
    super.key,
  });

  final AccountCryptoV2Workflow account;
  final String invitationId;
  final String? scopeId, label, recipientLabel;
  final InviteCryptoRepository? repository;
  final SharedInvitationPreview? preview;
  final SharedScopeKind? kind;

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
  Object? _error;
  VerifiedCryptoInvitation? _invite;
  ScopeRotationReview? _review;
  final _refreshClock = Stopwatch()..start();
  Duration? _lastRefresh;

  bool get _current => mounted && widget.account.directory.isCurrent();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed ||
        !_current ||
        _busy ||
        ModalRoute.of(context)?.isCurrent != true ||
        (_lastRefresh != null &&
            _refreshClock.elapsed - _lastRefresh! <
                const Duration(seconds: 5))) {
      return;
    }
    _load();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (error) {
      if (_current) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _load() => _run(() async {
    if (!_current) return;
    _lastRefresh = _refreshClock.elapsed;
    // Failed or stale reloads must not leave an older grant enabled.
    setState(() {
      _invite = null;
      _review = null;
    });
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
        : await invites.acceptedRecipient(widget.scopeId!, widget.invitationId);
    if (!_current) return;
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
    if (invite == null || !_current || _pending) return;
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
    if (mounted && _current) Navigator.of(context).pop(widget.scopeId);
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
                        : l.cryptoInvitationGrantExplanation,
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
                  if (_error != null || _pending)
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
                  TextButton(
                    onPressed: _busy ? null : () => Navigator.of(context).pop(),
                    child: Text(l.cryptoContinueLocally),
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
