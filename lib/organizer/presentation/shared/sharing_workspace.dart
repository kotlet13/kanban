import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n.dart';
import '../../state/collaboration_provider.dart';
import '../organizer_widgets.dart';
import '../finance/shared_finance_workspace.dart';
import '../finance/shared_finance_actions.dart';
import '../projects_page.dart';
import '../shopping_page.dart';
import '../planning/shared_agenda_page.dart';
import '../inbox/notification_target_view.dart';
import 'collaboration_actions.dart';
import 'organization_workspace.dart';
import '../all_spaces/all_spaces_page.dart';
import '../../domain/all_spaces_projection.dart';
import '../../domain/organizer_models.dart';
import '../people/people_page.dart';
import 'sharing_sync_conflicts.dart';
import 'sharing_errors.dart';
import 'sharing_forms.dart';
import 'sharing_recovery.dart';
import 'sharing_session_boundary.dart';
import 'sharing_status.dart';

enum SharingView {
  shopping,
  projects,
  tasks,
  agenda,
  timeline,
  finances,
  people,
}

class SharingWorkspace extends ConsumerWidget {
  const SharingWorkspace({
    super.key,
    required this.view,
    required this.selectedScopeId,
    required this.onScopeSelected,
    required this.onConnect,
    this.selectedListId,
    this.selectedProjectId,
    this.onListSelected,
    this.onProjectSelected,
    this.onMembers,
    this.showScopePicker = true,
    this.onSource,
  });
  final SharingView view;
  final String? selectedScopeId;
  final ValueChanged<String> onScopeSelected;
  final VoidCallback onConnect;
  final String? selectedListId;
  final String? selectedProjectId;
  final ValueChanged<String?>? onListSelected;
  final ValueChanged<String?>? onProjectSelected;
  final ValueChanged<String>? onMembers;
  final bool showScopePicker;
  final Future<void> Function(AllSpacesSource, AllSpacesArea, String?)?
  onSource;

  Future<void> _sync(BuildContext context, WidgetRef ref) async {
    final controller = ref.read(collaborationProvider.notifier);
    try {
      await controller.syncNow();
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(sharingErrorMessage(context, error))),
        );
      }
    }
  }

  String _title(BuildContext context) {
    final l = context.l10n;
    return switch (view) {
      SharingView.shopping => l.organizerShopping,
      SharingView.projects => l.organizerProjects,
      SharingView.tasks => l.organizerTasks,
      SharingView.agenda => l.planningSharedToday,
      SharingView.timeline => l.planningTimeline,
      SharingView.finances => l.organizerFinances,
      SharingView.people => l.peopleTitle,
    };
  }

  Widget _syncDetails(
    BuildContext context,
    WidgetRef ref,
    CollaborationState state,
    String scopeId,
    bool actionsEnabled,
    BuildContext originContext,
  ) {
    if (!originContext.mounted) return const SizedBox.shrink();
    final originGuard = SharingSessionGuard(originContext, ref);
    final scope = state.scopes.where((s) => s.id == scopeId).firstOrNull;
    if (scope == null) return const SizedBox.shrink();
    final l = context.l10n;
    final actions = CollaborationActions(
      context,
      ref,
      scope,
      state.dataForScope(scopeId),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (scope.revoked) ...[
          Text(l.sharingSaveDraftsDescription),
          TextButton.icon(
            onPressed: () {
              if (!originContext.mounted || !originGuard.isCurrent) return;
              exportSharingDrafts(context, ref);
            },
            icon: const Icon(Icons.file_download_outlined, size: 18),
            label: Text(l.sharingSaveDrafts),
          ),
        ],
        if (scope.blocked) ...[
          Text(l.sharingBlockedDescription),
          if (scope.role != SharedRole.viewer)
            TextButton(
              onPressed: actionsEnabled
                  ? () async {
                      if (!originContext.mounted || !originGuard.isCurrent) {
                        return;
                      }
                      final confirmed = await confirmSharingAction(
                        context,
                        title: l.sharingResumeBlocked,
                        description: l.sharingResumeBlockedDescription,
                        confirmLabel: l.sharingResumeBlocked,
                        wrap: (dialog) => SharingSessionBoundary(
                          guard: actions.guard,
                          child: dialog,
                        ),
                      );
                      if (confirmed &&
                          context.mounted &&
                          originContext.mounted &&
                          originGuard.isCurrent) {
                        await actions.run(
                          () =>
                              actions.controller.resumeBlockedChanges(scopeId),
                        );
                      }
                    }
                  : null,
              child: Text(l.sharingResumeBlocked),
            ),
        ],
        if (view == SharingView.finances)
          SharedFinanceSyncDetails(
            state: state,
            scopeId: scopeId,
            actionsEnabled: actionsEnabled,
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    return ref
        .watch(collaborationProvider)
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(sharingErrorMessage(context, error)),
              TextButton(
                onPressed: () =>
                    ref.invalidate(collaborationRepositoryProvider),
                child: Text(l.organizerRetry),
              ),
            ],
          ),
          data: (state) {
            if (state.session == null) {
              return OrganizerEmpty(
                icon: Icons.people_outline,
                title: l.sharingShared,
                description: l.sharingConnectBeforeShared,
                action: l.sharingConnect,
                onAction: onConnect,
              );
            }
            if (!state.localAccessAllowed) return Text(l.sharingAccessRevoked);
            final scopes = state.scopes
                .where((scope) => scope.kind != SharedScopeKind.personal)
                .toList();
            if (scopes.isEmpty) {
              return OrganizerEmpty(
                icon: Icons.people_outline,
                title: l.sharingNoSpaces,
                description: l.sharingScopeDescription,
                action: l.sharingGoToAccount,
                onAction: onConnect,
              );
            }
            final scope =
                scopes
                    .where((item) => item.id == selectedScopeId)
                    .firstOrNull ??
                scopes.first;
            if (selectedScopeId != null &&
                !scopes.any((scope) => scope.id == selectedScopeId)) {
              return Text(l.sharingAccessRevoked);
            }
            if (scope.kind == SharedScopeKind.organization &&
                view != SharingView.people &&
                view != SharingView.shopping) {
              if (scope.revoked || scope.blocked || !state.localAccessAllowed) {
                return Text(l.sharingAccessRevoked);
              }
              if (view == SharingView.projects) {
                return OrganizationWorkspace(
                  organization: scope,
                  onProject: onScopeSelected,
                  onMembers: (id) => onMembers?.call(id),
                );
              }
              final personal = OrganizerSnapshot();
              final aggregate = projectAllSpaces(
                personal: personal,
                shared: state,
              );
              return AllSpacesPage(
                key: ValueKey('organization-${scope.id}-$view'),
                area: switch (view) {
                  SharingView.agenda => AllSpacesArea.today,
                  SharingView.timeline => AllSpacesArea.calendar,
                  SharingView.finances => AllSpacesArea.finances,
                  _ => AllSpacesArea.tasks,
                },
                snapshot: AllSpacesSnapshot(
                  aggregate.sources.where(
                    (source) =>
                        source.scopeId == scope.id ||
                        source.scope?.parentSpaceId == scope.id,
                  ),
                ),
                showDescription: false,
                onSource:
                    onSource ??
                    (source, area, id) async {
                      if (source.scopeId != null) {
                        onScopeSelected(source.scopeId!);
                      }
                    },
              );
            }
            final data = state.dataForScope(scope.id);
            final actions = CollaborationActions(context, ref, scope, data);
            final readOnly = !scope.canEdit || !state.localAccessAllowed;
            final status = SharingStatus(
              key: ValueKey('sharing-status-${scope.id}-$view'),
              state: state,
              scopeId: scope.id,
              onSync: () => _sync(context, ref),
              onConflicts: () => showSharingSyncConflicts(context, ref),
              onExport: () => exportSharingDrafts(context, ref),
              onConnect: onConnect,
              detailsBuilder: (dialogContext, current, actionsEnabled) =>
                  _syncDetails(
                    dialogContext,
                    ref,
                    current,
                    scope.id,
                    actionsEnabled,
                    context,
                  ),
            );
            final householdProjects =
                scope.kind == SharedScopeKind.household &&
                scope.accessPolicyVersion == 3 &&
                state.spaceProjectMembershipSupported;
            if (householdProjects && view == SharingView.projects) {
              return OrganizationWorkspace(
                organization: scope,
                onProject: onScopeSelected,
                onMembers: (id) => onMembers?.call(id),
                titleAccessory: status,
                legacyProjects: data.projects.isEmpty
                    ? null
                    : OrganizerProjectsPage(
                        snapshot: sharedPresentationSnapshot(data),
                        actions: actions,
                        selectedId: selectedProjectId,
                        onSelection: onProjectSelected ?? (_) {},
                        readOnly: readOnly,
                        allowProjectCreation: false,
                        scopeLabel: '${scope.name} · ${l.sharingShared}',
                      ),
              );
            }
            if (householdProjects &&
                const {
                  SharingView.agenda,
                  SharingView.timeline,
                  SharingView.tasks,
                  SharingView.finances,
                }.contains(view) &&
                state.scopes.any(
                  (child) => child.parentSpaceId == scope.id && !child.revoked,
                )) {
              final aggregate = projectAllSpaces(
                personal: OrganizerSnapshot(),
                shared: state,
              );
              return AllSpacesPage(
                key: ValueKey('household-${scope.id}-$view'),
                titleAccessory: status,
                allowCreation: !readOnly,
                canCreateInSource: (source) =>
                    source.scope?.canEdit == true &&
                    (view != SharingView.finances ||
                        state.financePolicyForScope(source.scopeId!).canWrite &&
                            state.financeSnapshotComplete[source.scopeId] ==
                                true),
                onCreateSource: (source) async {
                  final current = ref.read(collaborationProvider).valueOrNull;
                  final target = current?.scopes
                      .where((s) => s.id == source.scopeId)
                      .firstOrNull;
                  if (current == null ||
                      target?.canEdit != true ||
                      !current.localAccessAllowed ||
                      current.session?.partition != state.session?.partition) {
                    return;
                  }
                  final targetActions = CollaborationActions(
                    context,
                    ref,
                    target!,
                    current.dataForScope(target.id),
                  );
                  switch (view) {
                    case SharingView.finances:
                      if (current.financePolicyForScope(target.id).canWrite &&
                          current.financeSnapshotComplete[target.id] == true) {
                        await SharedFinanceActions(
                          context,
                          ref,
                          target,
                          current,
                        ).entry();
                      }
                    case SharingView.timeline:
                      await targetActions.event();
                    default:
                      await targetActions.task();
                  }
                },
                area: switch (view) {
                  SharingView.agenda => AllSpacesArea.today,
                  SharingView.timeline => AllSpacesArea.calendar,
                  SharingView.finances => AllSpacesArea.finances,
                  _ => AllSpacesArea.tasks,
                },
                snapshot: AllSpacesSnapshot(
                  aggregate.sources.where(
                    (source) =>
                        source.scopeId == scope.id ||
                        source.scope?.parentSpaceId == scope.id,
                  ),
                ),
                showDescription: false,
                onSource:
                    onSource ??
                    (source, area, id) async {
                      if (source.scopeId != null) {
                        onScopeSelected(source.scopeId!);
                      }
                    },
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (showScopePicker) ...[
                  SharingScopePicker(
                    scopes: scopes,
                    selectedId: scope.id,
                    onChanged: onScopeSelected,
                  ),
                  const SizedBox(height: 16),
                ],
                if (scope.revoked) ...[
                  OrganizerHeading(
                    title: _title(context),
                    titleAccessory: status,
                  ),
                  Text(l.sharingAccessRevoked),
                  Text(l.sharingSaveDraftsDescription),
                ] else ...[
                  if (readOnly && !scope.blocked)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(l.sharingReadOnly),
                    ),
                  if (scope.archived)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(l.scopeArchivedDescription),
                    ),
                  if (state.projectArchivingSupported &&
                      scope.canManage &&
                      (scope.projectRootId != null ||
                          scope.parentSpaceId != null))
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        icon: Icon(
                          scope.archived
                              ? Icons.unarchive_outlined
                              : Icons.archive_outlined,
                        ),
                        label: Text(
                          scope.archived ? l.peopleRestore : l.peopleArchive,
                        ),
                        onPressed: () => actions.run(
                          () => actions.controller.archiveProjectScope(
                            scope.id,
                            archived: !scope.archived,
                          ),
                        ),
                      ),
                    ),
                  switch (view) {
                    SharingView.people => OrganizerPeoplePage(
                      titleAccessory: status,
                      people: data.people,
                      tasks: data.tasks,
                      scope: scope,
                      readOnly: readOnly || !state.householdPeopleSupported,
                      onTask: (task) => actions.task(task: task),
                    ),
                    SharingView.finances => SharedFinanceWorkspace(
                      titleAccessory: status,
                      scope: scope,
                      state: state,
                    ),
                    SharingView.shopping => OrganizerShoppingPage(
                      titleAccessory: status,
                      key: ValueKey(
                        'shared-shopping-${state.session!.partition}-${scope.id}',
                      ),
                      snapshot: sharedPresentationSnapshot(data),
                      actions: actions,
                      selectedId: selectedListId,
                      onSelection: onListSelected ?? (_) {},
                      readOnly: readOnly,
                      scopeLabel: '${scope.name} · ${l.sharingShared}',
                      emptyDescription: l.sharingNoSharedListsDescription,
                    ),
                    SharingView.projects => OrganizerProjectsPage(
                      titleAccessory: status,
                      reminderScopeId: scope.id,
                      allowProjectCreation:
                          scope.projectRootId == null &&
                          scope.parentSpaceId == null,
                      key: ValueKey(
                        'shared-projects-${state.session!.partition}-${scope.id}',
                      ),
                      snapshot: sharedPresentationSnapshot(data),
                      actions: actions,
                      selectedId: selectedProjectId,
                      onSelection: onProjectSelected ?? (_) {},
                      readOnly: readOnly,
                      scopeLabel: '${scope.name} · ${l.sharingShared}',
                    ),
                    SharingView.agenda ||
                    SharingView.timeline => SharedAgendaPage(
                      titleAccessory: status,
                      key: ValueKey(
                        'agenda-${state.session!.partition}-${scope.id}-$view',
                      ),
                      scope: scope,
                      data: data,
                      people: actions.people,
                      timeline: view == SharingView.timeline,
                      selectedProjectId: selectedProjectId,
                      onProjectSelected: onProjectSelected,
                      onAddEvent: readOnly ? null : () => actions.event(),
                      onOpen: (item) => showNotificationTarget(
                        context,
                        ref,
                        NotificationTarget(
                          serverUrl: state.session!.serverUrl,
                          serverId: state.session!.serverId,
                          accountId: state.session!.accountId,
                          scopeId: scope.id,
                          records: [
                            NotificationRecordTarget(
                              type: item.type,
                              recordId: item.id,
                            ),
                          ],
                        ),
                        onAccount: onConnect,
                      ),
                    ),
                    SharingView.tasks => OrganizerTasksPage(
                      titleAccessory: status,
                      reminderScopeId: scope.id,
                      snapshot: sharedPresentationSnapshot(data),
                      actions: actions,
                      readOnly: readOnly,
                      scopeLabel: '${scope.name} · ${l.sharingShared}',
                    ),
                  },
                ],
              ],
            );
          },
        );
  }
}
