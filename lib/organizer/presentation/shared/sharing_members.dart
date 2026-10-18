import '../recovery/crypto_invitation_page.dart';
import 'content_actions_menu.dart';
import 'scope_invitation_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n.dart';
import '../../state/collaboration_provider.dart';
import '../../data/collaboration_repository.dart' show newSharedId;
import '../organizer_widgets.dart';
import 'sharing_errors.dart';
import 'sharing_forms.dart';
import 'sharing_session_boundary.dart';
import 'scope_lifecycle_menu.dart';
import '../../state/account_crypto_provider.dart';
import '../../data/e2ee/account_crypto_v2_workflow.dart';
import '../../data/e2ee/session_crypto_access.dart';
import '../recovery/account_devices_page.dart';

// invitations.list returns creation order (created_at, id). Keep historical
// attempts on the server, but present the current invitation for each email.
// Multiple still-valid links remain individually actionable, even if created
// without first revoking the previous link.
List<(SharedInvitation, bool)> _visibleInvitations(
  List<SharedInvitation> invitations,
  DateTime now,
) {
  final groups = <(String, String, bool), List<SharedInvitation>>{};
  for (final invitation in invitations) {
    final email = invitation.recipientEmail?.trim().toLowerCase();
    final hasEmail = email != null && email.isNotEmpty;
    final hasUsername =
        invitation.contractVersion == 3 &&
        invitation.recipientUsername.trim().isNotEmpty;
    final key = (
      invitation.scopeId,
      hasEmail
          ? email
          : hasUsername
          ? 'username:${invitation.recipientUsername.trim().toLowerCase()}'
          : invitation.id,
      hasEmail || hasUsername,
    );
    groups.putIfAbsent(key, () => []).add(invitation);
  }
  final result = <(SharedInvitation, bool)>[];
  for (final group in groups.values) {
    final pending = group
        .where(
          (invitation) =>
              invitation.acceptedAt == null &&
              invitation.revokedAt == null &&
              invitation.expiresAt.isAfter(now),
        )
        .toList();
    for (final invitation in pending.isEmpty ? [group.last] : pending) {
      result.add((invitation, pending.isNotEmpty && group.length > 1));
    }
  }
  return result;
}

class SharingMembersPage extends ConsumerStatefulWidget {
  const SharingMembersPage({
    super.key,
    required this.scope,
    required this.session,
  });
  final SharedScope scope;
  final AccountSession session;
  @override
  ConsumerState<SharingMembersPage> createState() => _SharingMembersPageState();
}

class _SharingMembersPageState extends ConsumerState<SharingMembersPage> {
  String _memberAccessLabel(SharedMember member) {
    final l = context.l10n;
    final inherited =
        member.accessSource == 'spaceMembership' ||
        member.accessSources.contains('spaceMembership');
    final direct =
        member.accessSource == 'direct' ||
        member.accessSources.contains('direct');
    return [
      if (inherited) l.sharingProjectMembersInherited,
      if (inherited && direct) l.sharingAccessSourceProject,
      if (!inherited && member.organizationLeader) l.organizationLeader,
    ].join(' · ');
  }

  bool _canRemoveMember(SharedMember member) =>
      (widget.scope.canManage ||
          _cryptoScope && member.accountId == widget.session.accountId) &&
      member.role != SharedRole.owner &&
      (member.accessSource == 'direct' ||
          member.accessSources.contains('direct')) &&
      (member.membershipScopeId == null ||
          member.membershipScopeId == widget.scope.id);
  late final _guard = SharingSessionGuard(
    context,
    ref,
    session: widget.session,
  );
  late Future<(List<SharedMember>, List<SharedInvitation>)> _future = _load();
  bool _busy = false, _cryptoScope = false;
  final _resendRequests = <String, ({String requestId, String language})>{};

  bool _scopeIsCurrent(CollaborationState state) =>
      !state.sessionInvalid &&
      state.session?.expiresAt.isAfter(DateTime.now()) == true &&
      !state.allSpacesSelected &&
      state.selectedSpaceId == widget.scope.id &&
      state.scopes.any(
        (scope) =>
            scope.id == widget.scope.id &&
            !scope.revoked &&
            !scope.blocked &&
            scope.role == widget.scope.role &&
            scope.accessPolicyVersion == widget.scope.accessPolicyVersion &&
            scope.accessRevision == widget.scope.accessRevision &&
            scope.archived == widget.scope.archived,
      );

  bool get _isCurrent {
    if (!mounted || !_guard.isCurrent) return false;
    final current = ref.read(collaborationProvider).valueOrNull;
    return current != null && _scopeIsCurrent(current);
  }

  Future<(List<SharedMember>, List<SharedInvitation>)> _load() async {
    if (!_isCurrent) throw const CollaborationException('access_revoked');
    final controller = _guard.controller;
    final scope = widget.scope;
    final repository = await ref.read(collaborationRepositoryProvider.future);
    _cryptoScope = (await repository.database.rows(
      "SELECT scope_id FROM crypto_scope_state WHERE partition=? AND scope_id=? AND (floor>0 OR state IN ('active','committed','retired','fenced','verified'))",
      [widget.session.partition, scope.id],
    )).isNotEmpty;
    final results = await Future.wait<Object>([
      controller.members(scope.id),
      if (scope.canManage) controller.invitations(scope.id),
    ]);
    return (
      results.first as List<SharedMember>,
      scope.canManage
          ? results.last as List<SharedInvitation>
          : <SharedInvitation>[],
    );
  }

  void _refresh() {
    final future = _load();
    setState(() {
      _future = future;
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy || !_isCurrent) return;
    setState(() => _busy = true);
    try {
      await action();
      if (mounted && _isCurrent) _refresh();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(sharingErrorMessage(context, error)),
            action: sharingApprovalAction(context, error),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _invite() async {
    if (await showScopeInvitation(
          context,
          ref,
          scope: widget.scope,
          session: widget.session,
        ) &&
        mounted &&
        _isCurrent) {
      _refresh();
    }
  }

  Future<void> _resend(SharedInvitation invitation) async {
    final l = context.l10n;
    final confirmed = await confirmSharingAction(
      context,
      title: l.spaceFlowResend,
      description: l.spaceFlowResendConfirm,
      confirmLabel: l.spaceFlowResend,
      wrap: (dialog) => SharingSessionBoundary(
        guard: _guard,
        visibleWhen: _scopeIsCurrent,
        child: dialog,
      ),
    );
    if (confirmed && mounted && _isCurrent) {
      await _run(() async {
        await _guard.controller.resendInvitation(
          scopeId: widget.scope.id,
          invitationId: invitation.id,
          requestId: _resendRequests
              .putIfAbsent(
                invitation.id,
                () => (
                  requestId: newSharedId(),
                  language: Localizations.localeOf(context).languageCode,
                ),
              )
              .requestId,
          language: _resendRequests[invitation.id]!.language,
        );
      });
    }
  }

  Future<void> _leader(SharedMember member) async {
    final l = context.l10n;
    final confirmed = await confirmSharingAction(
      context,
      title: member.organizationLeader
          ? l.organizationLeaderRemove
          : l.organizationLeaderGrant,
      description: l.organizationLeaderConfirm,
      confirmLabel: member.organizationLeader
          ? l.organizationLeaderRemove
          : l.organizationLeaderGrant,
      wrap: (dialog) => SharingSessionBoundary(
        guard: _guard,
        visibleWhen: _scopeIsCurrent,
        child: dialog,
      ),
    );
    if (confirmed && mounted && _isCurrent) {
      await _run(
        () => _guard.controller.setOrganizationLeader(
          widget.scope.id,
          member.accountId,
          !member.organizationLeader,
        ),
      );
    }
  }

  Future<void> _verifyIdentity(SharedMember member) async {
    if (_busy || !_isCurrent) return;
    try {
      final workflow = await ref.read(accountCryptoPreviewProvider.future);
      if (!mounted || !_isCurrent) return;
      if (workflow is! AccountCryptoV2Workflow) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.cryptoConnectionPending)),
        );
        return;
      }
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => ContactIdentityVerificationPage(
            access: SessionCryptoAccess(account: workflow),
            scopeId: widget.scope.id,
            accountId: member.accountId,
            displayName: member.displayName.isEmpty
                ? member.username
                : member.displayName,
          ),
        ),
      );
    } catch (_) {
      if (mounted && _isCurrent)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.accountRecoveryFailed)),
        );
    }
  }

  Future<void> _remove(SharedMember member) async {
    final self = _cryptoScope && member.accountId == widget.session.accountId;
    final sl = Localizations.localeOf(context).languageCode == 'sl';
    final directProject =
        widget.scope.kind == SharedScopeKind.project &&
        widget.scope.accessPolicyVersion == 3;
    final confirmed = await confirmSharingAction(
      context,
      title: self
          ? (sl ? 'Zapusti prostor' : 'Leave space')
          : directProject
          ? context.l10n.sharingRemoveProjectMembership
          : context.l10n.sharingRemoveMember,
      description: self
          ? (sl
                ? 'Izstop bo zahteval odobritev upravitelja in novo zaščito prostora. Do zaključka ohranite obstoječi dostop; zahtevo lahko prekličete.'
                : 'Leaving requires a manager’s approval and renewed scope protection. Existing access remains until completion; you can cancel the request.')
          : widget.scope.kind == SharedScopeKind.project &&
                widget.scope.parentSpaceId != null &&
                widget.scope.accessPolicyVersion == 3
          ? context.l10n.sharingProjectDirectRemoval
          : const {
              SharedScopeKind.organization,
              SharedScopeKind.household,
            }.contains(widget.scope.kind)
          ? context.l10n.scopeRemoveMemberDescendants
          : context.l10n.sharingRemoveMemberConfirm,
      confirmLabel: self
          ? (sl ? 'Zahtevaj izstop' : 'Request leave')
          : directProject
          ? context.l10n.sharingRemoveProjectMembership
          : context.l10n.sharingRemoveMember,
      wrap: (dialog) => SharingSessionBoundary(
        guard: _guard,
        visibleWhen: _scopeIsCurrent,
        child: dialog,
      ),
    );
    if (confirmed && mounted && _isCurrent) {
      await _run(
        () => _guard.controller.revokeMember(
          scopeId: widget.scope.id,
          userId: member.userId,
          accountId: member.accountId,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.scope.kind == SharedScopeKind.personal) {
      return Text(context.l10n.privateSyncDescription);
    }
    ref.watch(collaborationProvider);
    if (!_isCurrent) return Text(context.l10n.sharingSessionExpired);
    final l = context.l10n;
    return FutureBuilder<(List<SharedMember>, List<SharedInvitation>)>(
      future: _future,
      builder: (context, result) {
        if (result.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (result.hasError) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(sharingErrorMessage(context, result.error!)),
              TextButton(
                onPressed: () => _refresh(),
                child: Text(l.organizerRetry),
              ),
            ],
          );
        }
        final (members, invitations) = result.data!;
        final now = DateTime.now();
        final visibleInvitations = _visibleInvitations(invitations, now);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OrganizerHeading(
              title: l.sharingMembers,
              titleAccessory: ScopeLifecycleMenu(scope: widget.scope),
              subtitle: widget.scope.name,
              action: widget.scope.canManage && !widget.scope.archived
                  ? FilledButton.icon(
                      onPressed: _busy ? null : _invite,
                      icon: const Icon(Icons.person_add_outlined, size: 18),
                      label: Text(l.sharingInvitePerson),
                    )
                  : null,
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const ValueKey("sharing-refresh-members"),
                onPressed: _busy ? null : () => _refresh(),
                icon: const Icon(Icons.refresh, size: 18),
                label: Text(l.sharingRefreshMembers),
              ),
            ),
            if (_busy) const LinearProgressIndicator(),
            if (members.isEmpty) Text(l.sharingNoMembers),
            for (final member in members)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: Text(
                    member.displayName.isEmpty
                        ? member.username
                        : member.displayName,
                  ),
                  subtitle: Text(
                    [
                      member.username,
                      sharingRoleLabel(context, member.role),
                      if (_memberAccessLabel(member).isNotEmpty)
                        _memberAccessLabel(member),
                    ].join(' · '),
                  ),
                  trailing:
                      (member.accountId.isEmpty ||
                              member.accountId == widget.session.accountId) &&
                          !_canRemoveMember(member)
                      ? null
                      : SharedContentActionsMenu(
                          scopeId: widget.scope.id,
                          targetType: 'user',
                          targetId: member.accountId.isEmpty
                              ? 'member-${member.userId}'
                              : member.accountId,
                          enabled: !_busy,
                          includeReport:
                              member.accountId.isNotEmpty &&
                              member.accountId != widget.session.accountId,
                          actions: [
                            if (member.accountId.isNotEmpty &&
                                member.accountId != widget.session.accountId)
                              ContentMenuAction(
                                label: l.cryptoCompareContact,
                                icon: Icons.verified_user_outlined,
                                onSelected: () => _verifyIdentity(member),
                              ),
                            if (_canRemoveMember(member) &&
                                widget.scope.kind ==
                                    SharedScopeKind.organization &&
                                widget.scope.accessPolicyVersion == 2 &&
                                widget.scope.role == SharedRole.owner &&
                                member.accountId.isNotEmpty)
                              ContentMenuAction(
                                label: member.organizationLeader
                                    ? l.organizationLeaderRemove
                                    : l.organizationLeaderGrant,
                                icon: member.organizationLeader
                                    ? Icons.manage_accounts
                                    : Icons.manage_accounts_outlined,
                                onSelected: () => _leader(member),
                              ),
                            if (_canRemoveMember(member))
                              ContentMenuAction(
                                label:
                                    widget.scope.kind ==
                                            SharedScopeKind.project &&
                                        widget.scope.accessPolicyVersion == 3
                                    ? l.sharingRemoveProjectMembership
                                    : l.sharingRemoveMember,
                                icon: Icons.person_remove_outlined,
                                onSelected: () => _remove(member),
                              ),
                          ],
                        ),
                ),
              ),
            if (widget.scope.canManage) ...[
              const SizedBox(height: 28),
              Text(
                l.sharingInvitations,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              if (invitations.isEmpty) Text(l.sharingNoInvitations),
              for (final (invitation, resent) in visibleInvitations)
                Card(
                  key: ValueKey('sharing-invitation-${invitation.id}'),
                  child: ListTile(
                    title: Text(
                      invitation.recipientEmail ?? invitation.recipientUsername,
                    ),
                    subtitle: Text(
                      '${sharingRoleLabel(context, invitation.role)} · ${invitation.acceptedAt != null
                          ? l.sharingAccepted
                          : invitation.revokedAt != null
                          ? l.sharingRevoked
                          : !invitation.expiresAt.isAfter(now)
                          ? l.sharingExpired
                          : '${resent ? '${l.sharingInvitationResent} · ' : ''}${l.sharingExpires} ${organizerDate(context, invitation.expiresAt.toLocal())} ${TimeOfDay.fromDateTime(invitation.expiresAt.toLocal()).format(context)}'}',
                    ),
                    trailing:
                        invitation.acceptedAt == null &&
                            invitation.revokedAt == null
                        ? Wrap(
                            children: [
                              if (invitation.pendingKeys)
                                IconButton(
                                  tooltip: l.cryptoInvitationGrantTitle,
                                  onPressed: _busy
                                      ? null
                                      : () async {
                                          final repository = await ref.read(
                                            collaborationRepositoryProvider
                                                .future,
                                          );
                                          final account = await repository
                                              .connectedCryptoAccount();
                                          if (!context.mounted ||
                                              !_guard.isCurrent)
                                            return;
                                          await Navigator.of(context).push(
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  CryptoInvitationPage(
                                                    account: account,
                                                    scopeId: widget.scope.id,
                                                    invitationId: invitation.id,
                                                    label: widget.scope.name,
                                                  ),
                                            ),
                                          );
                                          if (mounted && _guard.isCurrent)
                                            setState(() => _future = _load());
                                        },
                                  icon: const Icon(Icons.key_outlined),
                                ),
                              if (invitation.contractVersion == 3 &&
                                  ref
                                          .read(collaborationProvider)
                                          .valueOrNull
                                          ?.invitationResendSupported ==
                                      true)
                                IconButton(
                                  key: ValueKey(
                                    'sharing-resend-invitation-${invitation.id}',
                                  ),
                                  tooltip: l.spaceFlowResend,
                                  onPressed: _busy || widget.scope.archived
                                      ? null
                                      : () => _resend(invitation),
                                  icon: const Icon(
                                    Icons.forward_to_inbox_outlined,
                                  ),
                                ),
                              if (invitation.expiresAt.isAfter(now))
                                IconButton(
                                  key: ValueKey(
                                    'sharing-revoke-invitation-${invitation.id}',
                                  ),
                                  tooltip: l.sharingRevokeInvite,
                                  onPressed: _busy
                                      ? null
                                      : () => _run(
                                          () => _guard.controller
                                              .revokeInvitation(
                                                widget.scope.id,
                                                invitation.id,
                                              ),
                                        ),
                                  icon: const Icon(Icons.cancel_outlined),
                                ),
                            ],
                          )
                        : null,
                  ),
                ),
            ],
          ],
        );
      },
    );
  }
}
