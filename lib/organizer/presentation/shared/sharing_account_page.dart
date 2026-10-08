import '../../data/collaboration_repository.dart' show newSharedId;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n.dart';
import '../../state/collaboration_provider.dart';
import '../organizer_widgets.dart';
import 'sharing_accept.dart';
import 'sharing_auth.dart';
import 'sharing_conflicts.dart';
import 'sharing_errors.dart';
import 'sharing_forms.dart';
import 'sharing_members.dart';
import 'sharing_recovery.dart';
import 'sharing_session_boundary.dart';
import 'sharing_status.dart';
import 'sharing_workspace.dart';
import '../../platform/invitation_links/invitation_link.dart';
import '../onboarding/getting_started.dart';
import '../onboarding/private_sync_panel.dart';
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
    this.showMembers = false,
    this.initialInvitation,
    this.onInvitationHandled,
    this.setupIntent,
  });
  final String? selectedScopeId;
  final InvitationLink? initialInvitation;
  final VoidCallback? onInvitationHandled;
  final SetupIntent? setupIntent;
  final ValueChanged<String?> onScopeSelected;
  final SharingView initialView;
  final String? selectedListId;
  final String? selectedProjectId;
  final ValueChanged<String?>? onListSelected;
  final ValueChanged<String?>? onProjectSelected;
  final bool showMembers;
  @override
  ConsumerState<SharingAccountPage> createState() => _SharingAccountPageState();
}

class _SharingAccountPageState extends ConsumerState<SharingAccountPage> {
  bool _authActive = false;
  bool _busy = false;
  late SharingView _view = widget.initialView;
  late bool _members = widget.showMembers;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
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
        setState(() {
          _authActive = false;
          _members = false;
        });
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
    final backgroundError = ref.watch(collaborationBackgroundErrorProvider);
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
            if (session == null ||
                _authActive ||
                widget.initialInvitation != null) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SharingAuthPanel(
                    onStart: () => setState(() => _authActive = true),
                    onConnected: () {
                      setState(() => _authActive = false);
                      widget.onInvitationHandled?.call();
                    },
                    initialServer:
                        widget.initialInvitation?.serverUrl ??
                        session?.serverUrl ??
                        '',
                    initialToken: widget.initialInvitation?.token ?? '',
                    invitationMode: widget.initialInvitation != null,
                  ),
                  if (session != null)
                    TextButton(
                      onPressed: () => setState(() => _authActive = false),
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
                                          widget.onScopeSelected(id),
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
                                onPressed: () =>
                                    setState(() => _authActive = true),
                                child: Text(l.sharingLoginAction),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                PrivateSyncPanel(
                  onConnect: () => setState(() => _authActive = true),
                ),
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
                if (backgroundError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(sharingErrorMessage(context, backgroundError)),
                  ),
                const SizedBox(height: 20),
                if (selected == null) ...[
                  SharingStatus(
                    state: state,
                    onSync: () => _run(
                      () => ref.read(collaborationProvider.notifier).syncNow(),
                    ),
                    onConflicts: () => showSharingConflicts(context, ref),
                    onExport: () => exportSharingDrafts(context, ref),
                  ),
                  const SizedBox(height: 24),
                  OrganizerHeading(
                    title: l.sharingSpaces,
                    subtitle: l.sharingScopeDescription,
                    action: FilledButton.icon(
                      onPressed: _busy ? null : _createScope,
                      icon: const Icon(Icons.add, size: 18),
                      label: Text(l.sharingCreateSpace),
                    ),
                  ),
                  if (!state.scopes.any(
                    (scope) => scope.kind != SharedScopeKind.personal,
                  ))
                    Text(l.sharingNoSpaces),
                  for (final scope in state.scopes.where(
                    (scope) => scope.kind != SharedScopeKind.personal,
                  ))
                    Card(
                      child: ListTile(
                        leading: Icon(
                          scope.kind == SharedScopeKind.household
                              ? Icons.home_outlined
                              : Icons.folder_outlined,
                        ),
                        title: Text(scope.name),
                        subtitle: Text(
                          '${sharingScopeKindLabel(context, scope.kind)} · ${scope.revoked ? l.sharingRevoked : sharingRoleLabel(context, scope.role)}',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => widget.onScopeSelected(scope.id),
                      ),
                    ),
                ] else ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => widget.onScopeSelected(null),
                      icon: const Icon(Icons.arrow_back, size: 18),
                      label: Text(l.sharingSpaces),
                    ),
                  ),
                  Text(
                    selected.name,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  Text(
                    '${sharingScopeKindLabel(context, selected.kind)} · ${sharingRoleLabel(context, selected.role)}',
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<SharingView>(
                          key: ValueKey('shared-view-$_view-$_members'),
                          initialValue: _view,
                          isExpanded: true,
                          decoration: InputDecoration(labelText: l.sharingView),
                          items: [
                            for (final view in SharingView.values)
                              DropdownMenuItem(
                                value: view,
                                child: Text(switch (view) {
                                  SharingView.shopping => l.organizerShopping,
                                  SharingView.projects => l.organizerProjects,
                                  SharingView.tasks => l.organizerTasks,
                                  SharingView.agenda => l.planningSharedToday,
                                  SharingView.timeline => l.planningTimeline,
                                  SharingView.finances => l.organizerFinances,
                                  SharingView.people => l.peopleTitle,
                                }, overflow: TextOverflow.ellipsis),
                              ),
                          ],
                          onChanged: (view) {
                            if (view != null) {
                              setState(() {
                                _view = view;
                                _members = false;
                              });
                            }
                          },
                        ),
                      ),
                      if (!selected.revoked) ...[
                        const SizedBox(width: 8),
                        ChoiceChip(
                          selected: _members,
                          label: Text(l.sharingMembers),
                          onSelected: (_) => setState(() => _members = true),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 24),
                  if (_members && !selected.revoked)
                    SharingMembersPage(
                      key: ValueKey(
                        'members-${session.partition}-${session.deviceId}-${selected.id}',
                      ),
                      scope: selected,
                      session: session,
                    )
                  else
                    SharingWorkspace(
                      view: _view,
                      showScopePicker: false,
                      selectedScopeId: selected.id,
                      onScopeSelected: (id) => widget.onScopeSelected(id),
                      onConnect: () => setState(() => _authActive = true),
                      selectedListId: widget.selectedListId,
                      selectedProjectId: widget.selectedProjectId,
                      onListSelected: widget.onListSelected,
                      onProjectSelected: widget.onProjectSelected,
                    ),
                ],
              ],
            );
          },
        );
  }
}
