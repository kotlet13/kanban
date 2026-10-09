import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n.dart';
import '../../state/collaboration_provider.dart';
import '../organizer_widgets.dart';
import 'sharing_errors.dart';
import 'sharing_forms.dart';
import 'sharing_session_boundary.dart';
import '../../platform/invitation_links/invitation_link.dart';

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
  late final _guard = SharingSessionGuard(
    context,
    ref,
    session: widget.session,
  );
  late Future<(List<SharedMember>, List<SharedInvitation>)> _future = _load();
  bool _busy = false;

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
          SnackBar(content: Text(sharingErrorMessage(context, error))),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _invite() async {
    final scopeId = widget.scope.id;
    SharedInvitation? invitation;
    final l = context.l10n;
    await showSharingForm(
      context,
      title: l.sharingInvitePerson,
      fields: [
        SharingField(id: 'recipient', label: l.username),
        SharingField(
          id: 'role',
          label: l.sharingRole,
          initialValue: 'member',
          options: {'member': l.sharingMember, 'viewer': l.sharingViewer},
        ),
      ],
      submitLabel: l.sharingCreateInvite,
      errorMessage: (error) => sharingErrorMessage(context, error),
      wrap: (form) => SharingSessionBoundary(
        guard: _guard,
        visibleWhen: _scopeIsCurrent,
        child: form,
      ),
      onSubmit: (values) async {
        if (!_isCurrent) throw const CollaborationException('access_revoked');
        invitation = await _guard.controller.createInvitation(
          scopeId: scopeId,
          recipientUsername: values['recipient']!.trim(),
          role: SharedRole.values.byName(values['role']!),
        );
      },
    );
    if (!mounted || !_isCurrent || invitation == null) return;
    final created = invitation!;
    if (created.token != null) {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => SharingSessionBoundary(
          guard: _guard,
          visibleWhen: _scopeIsCurrent,
          child: AlertDialog(
            title: Text(l.sharingInvitation),
            content: SizedBox(
              width: 440,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${widget.scope.name} · ${created.recipientUsername}'),
                    const SizedBox(height: 12),
                    Text(l.sharingInviteCodeOnce),
                    const SizedBox(height: 16),
                    SelectableText(
                      created.token!,
                      key: const ValueKey('sharing-created-token'),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '${l.sharingExpires} ${organizerDate(context, created.expiresAt)}',
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              if (Uri.parse(widget.session.serverUrl).scheme == 'https')
                TextButton.icon(
                  onPressed: () async {
                    try {
                      await Clipboard.setData(
                        ClipboardData(
                          text: InvitationLink(
                            serverUrl: widget.session.serverUrl,
                            token: created.token!,
                          ).toUri().toString(),
                        ),
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(l.sharingInviteCopied)),
                        );
                      }
                    } catch (_) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(l.sharingOperationFailed)),
                        );
                      }
                    }
                  },
                  icon: const Icon(Icons.link),
                  label: Text(l.inviteCopyLink),
                ),
              TextButton.icon(
                onPressed: () async {
                  try {
                    await Clipboard.setData(
                      ClipboardData(text: created.token!),
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(l.sharingInviteCopied)),
                      );
                    }
                  } catch (error) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(sharingErrorMessage(context, error)),
                        ),
                      );
                    }
                  }
                },
                icon: const Icon(Icons.copy, size: 18),
                label: Text(l.sharingCopyInvite),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: Text(l.close),
              ),
            ],
          ),
        ),
      );
    }
    if (mounted && _isCurrent) _refresh();
  }

  Future<void> _remove(SharedMember member) async {
    final confirmed = await confirmSharingAction(
      context,
      title: context.l10n.sharingRemoveMember,
      description: context.l10n.sharingRemoveMemberConfirm,
      confirmLabel: context.l10n.sharingRemoveMember,
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
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OrganizerHeading(
              title: l.sharingMembers,
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
                    '${member.username} · ${sharingRoleLabel(context, member.role)}',
                  ),
                  trailing:
                      widget.scope.canManage && member.role != SharedRole.owner
                      ? IconButton(
                          tooltip: l.sharingRemoveMember,
                          onPressed: _busy ? null : () => _remove(member),
                          icon: const Icon(Icons.person_remove_outlined),
                        )
                      : null,
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
              for (final invitation in invitations)
                Card(
                  child: ListTile(
                    title: Text(invitation.recipientUsername),
                    subtitle: Text(
                      '${sharingRoleLabel(context, invitation.role)} · ${invitation.acceptedAt != null
                          ? l.sharingAccepted
                          : invitation.revokedAt != null
                          ? l.sharingRevoked
                          : invitation.expiresAt.isBefore(DateTime.now())
                          ? l.sharingExpired
                          : '${l.sharingExpires} ${organizerDate(context, invitation.expiresAt)}'}',
                    ),
                    trailing:
                        invitation.acceptedAt == null &&
                            invitation.revokedAt == null &&
                            invitation.expiresAt.isAfter(DateTime.now())
                        ? IconButton(
                            tooltip: l.sharingRevokeInvite,
                            onPressed: _busy
                                ? null
                                : () {
                                    _run(
                                      () => _guard.controller.revokeInvitation(
                                        widget.scope.id,
                                        invitation.id,
                                      ),
                                    );
                                  },
                            icon: const Icon(Icons.cancel_outlined),
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
