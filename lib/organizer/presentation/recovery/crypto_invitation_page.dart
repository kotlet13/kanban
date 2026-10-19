import 'package:flutter/material.dart';

import '../../../l10n/l10n.dart';
import '../../data/e2ee/account_crypto_v2_workflow.dart';
import '../../data/e2ee/invite_crypto_repository.dart';
import '../../data/e2ee/session_crypto_access.dart';
import '../../data/e2ee/scope_crypto_manager.dart';
import '../shared/sharing_errors.dart';
import '../shared/hosting_disclosure.dart';

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
    super.key,
  });

  final AccountCryptoV2Workflow account;
  final String invitationId;
  final String? scopeId, label, recipientLabel;
  final InviteCryptoRepository? repository;

  @override
  State<CryptoInvitationPage> createState() => _CryptoInvitationPageState();
}

class _CryptoInvitationPageState extends State<CryptoInvitationPage> {
  late final invites =
      widget.repository ??
      InviteCryptoRepository(SessionCryptoAccess(account: widget.account));
  bool _busy = false, _pending = false;
  Object? _error;
  VerifiedCryptoInvitation? _invite;
  ScopeRotationReview? _review;

  bool get _current => mounted && widget.account.directory.isCurrent();

  @override
  void initState() {
    super.initState();
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
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _load() => _run(() async {
    if (!_current) return;
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
    });
  });

  Future<void> _continue() => _run(() async {
    final invite = _invite;
    if (invite == null || !_current || _pending) return;
    if (widget.scopeId == null) {
      await invites.accept(invite, actionId: widget.invitationId);
      if (_current) setState(() => _pending = true);
      return;
    }
    final review = _review;
    if (review == null) return;
    await invites.admit(invite, review);
    if (mounted && _current) Navigator.of(context).pop(widget.scopeId);
  });

  Widget _permissions(VerifiedCryptoInvitation invite) {
    final proposed = invite.response['proposedMember'] as Map?;
    final role = proposed?['role'] ?? invite.invitation['role'];
    final label = switch (role) {
      'owner' => context.l10n.sharingOwner,
      'member' || 'editor' => context.l10n.sharingMember,
      'viewer' => context.l10n.sharingViewer,
      _ => throw const FormatException('invitation_role'),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Text('${context.l10n.cryptoSharingAccessLabel}: $label'),
        if (proposed != null) ...[
          Text(switch (proposed['financeRole']) {
            'write' => context.l10n.cryptoSharingFinanceWrite,
            'read' => context.l10n.cryptoSharingFinanceRead,
            _ => context.l10n.cryptoSharingFinanceNone,
          }),
          if (proposed['manageKeys'] == true)
            Text(context.l10n.cryptoSharingManageAccess),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.label ?? l.cryptoInvitationGrantTitle),
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
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
                  if (_pending) Text(l.cryptoInvitationPendingKeys),
                  if (_invite != null) _permissions(_invite!),
                  if (_review != null) ...[
                    const SizedBox(height: 16),
                    Text(l.cryptoSharingExistingContent),
                    for (final domain in _review!.domains.entries)
                      Text(
                        '${domain.key == 'finance' ? l.organizerFinances : l.cryptoSharingContent}: ${domain.value['count']}',
                      ),
                  ],
                  if (_invite != null && !_pending && _error == null)
                    FilledButton(
                      key: const ValueKey('crypto-invitation-confirm'),
                      onPressed: _busy ? null : _continue,
                      child: Text(
                        widget.scopeId == null
                            ? l.invitationFlowJoinSpace
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
