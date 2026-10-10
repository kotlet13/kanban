import '../../data/collaboration_repository.dart' show newSharedId;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n.dart';
import '../../state/collaboration_provider.dart';
import '../organizer_widgets.dart';
import 'sharing_accept.dart';
import 'sharing_auth.dart';
import 'sharing_sync_conflicts.dart';
import 'sharing_errors.dart';
import 'sharing_forms.dart';
import 'sharing_recovery.dart';
import 'sharing_session_boundary.dart';
import 'sharing_status.dart';
import 'sharing_pending_invitations.dart';
import 'sharing_workspace.dart';
import '../../platform/invitation_links/invitation_link.dart';
import '../onboarding/getting_started.dart';
import '../onboarding/private_sync_panel.dart';
import '../onboarding/local_space_connection_panel.dart';
import '../onboarding/account_email_card.dart';
import '../onboarding/account_deletion_panel.dart';

class SharingAccountPage extends ConsumerStatefulWidget {
  const SharingAccountPage({
    super.key,
    this.selectedScopeId,
    required this.onScopeSelected,
    this.initialView = SharingView.shopping,
    this.selectedListId,
    this.selectedProjectId,
    this.onListSelected,
    this.onProjectSelected,
    this.authActive,
    this.onAuthChanged,
    this.onViewChanged,
    this.onSpaceSettings,
    this.initialInvitation,
    this.onInvitationHandled,
    this.onInvitationAccepted,
    this.setupIntent,
  });
  final String? selectedScopeId;
  final InvitationLink? initialInvitation;
  final VoidCallback? onInvitationHandled;
  final ValueChanged<String>? onInvitationAccepted;
  final SetupIntent? setupIntent;
  final ValueChanged<String?> onScopeSelected;
  final SharingView initialView;
  final String? selectedListId;
  final String? selectedProjectId;
  final ValueChanged<String?>? onListSelected;
  final ValueChanged<String?>? onProjectSelected;
  final bool? authActive;
  final ValueChanged<bool>? onAuthChanged;
  final ValueChanged<SharingView>? onViewChanged;
  final ValueChanged<String?>? onSpaceSettings;
  @override
  ConsumerState<SharingAccountPage> createState() => _SharingAccountPageState();
}

class _SharingAccountPageState extends ConsumerState<SharingAccountPage> {
  bool _authActive = false;
  bool _busy = false;
  bool get _currentAuth => widget.authActive ?? _authActive;

  void _selectAuth(bool active) {
    if (widget.onAuthChanged != null) {
      widget.onAuthChanged!(active);
    } else {
      setState(() => _authActive = active);
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (!mounted || _busy) return;
    setState(() => _busy = true);
    try {
      await action();
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

  Future<void> _syncNow() async {
    if (!mounted) return;
    final guard = SharingSessionGuard(context, ref);
    try {
      await guard.controller.syncNow();
    } catch (error) {
      if (mounted && guard.isCurrent) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(sharingErrorMessage(context, error))),
        );
      }
    }
  }

  Future<void> _createScope() async {
    final guard = SharingSessionGuard(context, ref);
    final l = context.l10n;
    String? scopeId, submittedName, submittedKind;
    final createId = newSharedId(), requestId = newSharedId();
    await showSharingForm(
      context,
      title: l.sharingCreateSpace,
      description: l.sharingScopeDescription,
      fields: [
        SharingField(id: 'name', label: l.sharingSpaceName),
        SharingField(
          id: 'kind',
          label: l.sharingScopeType,
          initialValue: 'household',
          options: {
            'household': l.sharingHousehold,
            'project': l.sharingProject,
            if (ref
                    .read(collaborationProvider)
                    .valueOrNull
                    ?.organizationsSupported ==
                true)
              'organization': l.organizationTitle,
          },
        ),
      ],
      submitLabel: l.sharingCreateSpace,
      errorMessage: (error) => sharingErrorMessage(context, error),
      wrap: (form) => SharingSessionBoundary(guard: guard, child: form),
      onSubmit: (values) async {
        scopeId = await guard.controller.createScope(
          submittedName ??= values['name']!.trim(),
          kind: SharedScopeKind.values.byName(
            submittedKind ??= values['kind']!,
          ),
          id: createId,
          requestId: requestId,
        );
      },
    );
    if (mounted && guard.isCurrent && scopeId != null) {
      widget.onScopeSelected(scopeId);
    }
  }

  Future<void> _signOut() async {
    final guard = SharingSessionGuard(context, ref);
    final l = context.l10n;
    final confirmed = await confirmSharingAction(
      context,
      title: l.logout,
      description: l.sharingPendingSignOut,
      confirmLabel: l.logout,
      wrap: (dialog) => SharingSessionBoundary(guard: guard, child: dialog),
    );
    if (!confirmed || !mounted || !guard.isCurrent) return;
    await _run(() async {
      final remotelyRevoked = await guard.controller.signOut();
      if (mounted) {
        widget.onScopeSelected(null);
        _selectAuth(false);
        if (!remotelyRevoked) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(l.sharingOfflineSignOut)));
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return ref
        .watch(collaborationProvider)
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              OrganizerHeading(title: l.sharingAccount),
              Text(sharingErrorMessage(context, error)),
              TextButton(
                onPressed: () =>
                    ref.invalidate(collaborationRepositoryProvider),
                child: Text(l.organizerRetry),
              ),
            ],
          ),
          data: (state) {
            final session = state.session;
            final pending = ref
                .watch(securePendingInvitationProvider)
                .valueOrNull;
            final initialInvitation =
                widget.initialInvitation ??
                (session == null && pending != null
                    ? InvitationLink(
                        serverUrl: pending.serverUrl,
                        token: pending.token,
                      )
                    : null);
            final invitationNeedsAuth =
                initialInvitation != null &&
                (session == null ||
                    session.serverUrl != initialInvitation.serverUrl);
            if (session == null || _currentAuth || invitationNeedsAuth) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SharingAuthPanel(
                    onStart: () => _selectAuth(true),
                    onConnected: () {
                      _selectAuth(false);
                      widget.onInvitationHandled?.call();
                    },
                    initialServer:
                        initialInvitation?.serverUrl ??
                        session?.serverUrl ??
                        '',
                    initialToken: initialInvitation?.token ?? '',
                    invitationMode: initialInvitation != null,
                  ),
                  if (session != null)
                    TextButton(
                      onPressed: () => _selectAuth(false),
                      child: Text(l.sharingAccount),
                    ),
                ],
              );
            }
            final selected = state.scopes
                .where(
                  (scope) =>
                      scope.kind != SharedScopeKind.personal &&
                      scope.id == widget.selectedScopeId,
                )
                .firstOrNull;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                OrganizerHeading(
                  title: l.sharingAccount,
                  titleAccessory: SharingStatus(
                    state: state,
                    onSync: _syncNow,
                    onConflicts: () => showSharingSyncConflicts(context, ref),
                    onExport: () => exportSharingDrafts(context, ref),
                    onConnect: () => _selectAuth(true),
                  ),
                  subtitle: session.displayName.isEmpty
                      ? session.username
                      : session.displayName,
                ),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          session.serverUrl,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 8),
                        if (state.sessionRenewalSupported &&
                            !state.sessionInvalid &&
                            session.expiresAt.isAfter(DateTime.now())) ...[
                          Text(session.username),
                          Text(l.accountSessionAutoRenew),
                        ] else
                          Text(
                            '${session.username} · ${l.sharingSessionEnds} ${organizerDate(context, session.expiresAt)}',
                          ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 12,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: _busy
                                  ? null
                                  : () => showAcceptSharingInvite(
                                      context,
                                      ref,
                                      onAccepted: (id) =>
                                          (widget.onInvitationAccepted ??
                                          widget.onScopeSelected)(id),
                                    ),
                              icon: const Icon(Icons.mail_outline, size: 18),
                              label: Text(l.sharingHaveInvite),
                            ),
                            TextButton(
                              onPressed: _busy ? null : _signOut,
                              child: Text(l.logout),
                            ),
                            if (state.lastError?.code == 'auth_required' ||
                                state.lastError?.code == 'device_revoked' ||
                                !session.expiresAt.isAfter(DateTime.now()))
                              TextButton(
                                onPressed: () => _selectAuth(true),
                                child: Text(l.sharingLoginAction),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                SharingPendingInvitations(
                  key: ValueKey(
                    'pending-${session.partition}-${session.deviceId}',
                  ),
                  session: session,
                  supported: state.emailInvitationsSupported,
                  onAccepted: (id) =>
                      (widget.onInvitationAccepted ?? widget.onScopeSelected)(
                        id,
                      ),
                ),
                if (widget.onSpaceSettings != null)
                  ListTile(
                    leading: const Icon(Icons.settings_outlined),
                    title: Text(l.spaceSettingsTitle),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => widget.onSpaceSettings!(selected?.id),
                  ),
                const SizedBox(height: 20),
                PrivateSyncPanel(onConnect: () => _selectAuth(true)),
                const LocalSpaceConnectionPanel(),
                const SizedBox(height: 20),
                AccountEmailCard(
                  key: ValueKey(
                    'email-${session.partition}-${session.deviceId}',
                  ),
                  session: session,
                ),
                const SizedBox(height: 20),
                AccountDeletionPanel(
                  key: ValueKey(
                    'deletion-${session.partition}-${session.deviceId}',
                  ),
                ),
                if (widget.setupIntent == SetupIntent.household)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : _createScope,
                      icon: const Icon(Icons.home_outlined),
                      label: Text(l.setupHousehold),
                    ),
                  ),
                if (_busy) const LinearProgressIndicator(),
              ],
            );
          },
        );
  }
}
