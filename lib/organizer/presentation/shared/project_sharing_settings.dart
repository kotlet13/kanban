import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n.dart';
import '../../domain/organizer_models.dart';
import '../../state/collaboration_provider.dart';
import 'sharing_errors.dart';
import 'sharing_session_boundary.dart';
import 'project_sharing_blockers.dart';
import '../finance/finance_money.dart';
import '../organizer_widgets.dart';

/// Inline household projects acquire a separate scope only after review.
class ProjectSharingSettings extends ConsumerStatefulWidget {
  const ProjectSharingSettings({
    super.key,
    required this.scope,
    required this.onProjectSelected,
  });
  final SharedScope scope;
  final ValueChanged<String> onProjectSelected;

  @override
  ConsumerState<ProjectSharingSettings> createState() =>
      _ProjectSharingSettingsState();
}

class _ProjectSharingSettingsState
    extends ConsumerState<ProjectSharingSettings> {
  late final _guard = SharingSessionGuard(context, ref);
  bool _busy = false, _previewOpen = false;
  String? _error;
  bool _uncertain = false;

  bool _allows(CollaborationState state) =>
      !state.sessionInvalid &&
      !state.deletionPending &&
      state.session?.expiresAt.isAfter(DateTime.now()) == true &&
      state.selectedSpaceId == widget.scope.id &&
      !state.allSpacesSelected &&
      state.spaceProjectMembershipSupported &&
      state.scopes.any(
        (scope) =>
            scope.id == widget.scope.id &&
            scope.kind == SharedScopeKind.household &&
            scope.accessPolicyVersion == 3 &&
            scope.canManage &&
            !scope.blocked,
      );

  Future<void> _review(LocalProject project) async {
    if (_busy || !_guard.isCurrent) return;
    setState(() {
      _busy = true;
      _error = null;
      _uncertain = false;
    });
    try {
      final preview = await _guard.controller.previewProjectSharing(
        widget.scope.id,
        project.id,
      );
      if (!mounted ||
          !_guard.isCurrent ||
          !_allows(ref.read(collaborationProvider).requireValue)) {
        return;
      }
      final l = context.l10n;
      setState(() => _previewOpen = true);
      final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => SharingSessionBoundary(
          guard: _guard,
          visibleWhen: _allows,
          child: AlertDialog(
            scrollable: true,
            title: Text(l.sharingProjectSharingReview),
            content: SizedBox(
              width: 520,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    preview.projectName,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  Text(l.sharingProjectSharingDescription),
                  const SizedBox(height: 12),
                  Text(
                    l.sharingProjectSharingCounts(
                      preview.movedRecordIds.length,
                      preview.movedFinanceRecordIds.length,
                      preview.movedReminderIds.length,
                    ),
                  ),
                  if (preview.financeAccounts.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      l.financeAccounts,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    for (final account in preview.financeAccounts)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(account['name'] as String),
                        subtitle: Text(
                          [
                            if (account['openingBalanceMinor'] is int)
                              '${l.financeOpeningBalance}: ${sharedMoneyLabel(context, BigInt.from(account['openingBalanceMinor'] as int), account['currency'] as String)}'
                            else
                              account['currency'] as String,
                            if (account['openingBalanceAt'] is String &&
                                DateTime.tryParse(
                                      account['openingBalanceAt'] as String,
                                    ) !=
                                    null)
                              organizerDate(
                                context,
                                DateTime.parse(
                                  account['openingBalanceAt'] as String,
                                ),
                              ),
                          ].join(' · '),
                        ),
                      ),
                  ],
                  if (preview.householdPeople.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      l.peopleTitle,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    for (final person in preview.householdPeople)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(person['name'] as String),
                        subtitle:
                            person['notes'] is String &&
                                (person['notes'] as String).isNotEmpty
                            ? Text(person['notes'] as String)
                            : null,
                      ),
                  ],
                  if (!preview.canApply) ...[
                    const SizedBox(height: 12),
                    Text(l.sharingProjectSharingBlocked),
                    for (final code
                        in preview.blockers.map((b) => b.code).toSet())
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          projectSharingBlockerMessage(context, code),
                        ),
                      ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(l.cancel),
              ),
              if (preview.canApply)
                FilledButton(
                  key: const ValueKey('project-sharing-confirm'),
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(l.sharingProjectSharingApply),
                ),
            ],
          ),
        ),
      );
      if (mounted) setState(() => _previewOpen = false);
      if (accepted != true ||
          !mounted ||
          !_guard.isCurrent ||
          !_allows(ref.read(collaborationProvider).requireValue)) {
        return;
      }
      final child = await _guard.controller.applyProjectSharing(preview);
      if (!mounted || !_guard.isCurrent) return;
      widget.onProjectSelected(child.id);
    } catch (error) {
      if (mounted && _guard.isCurrent) {
        setState(() {
          _error = sharingErrorMessage(context, error);
          _uncertain =
              error is CollaborationException &&
              const {
                'network',
                'invalid_response',
                'session_changed',
                'auth_required',
              }.contains(error.code);
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _previewOpen = false;
        });
      }
    }
  }

  Future<void> _resume() async {
    if (_busy || !_guard.isCurrent) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final child = await _guard.controller.resumeProjectSharing(
        widget.scope.id,
      );
      if (!mounted || !_guard.isCurrent) return;
      if (child != null) widget.onProjectSelected(child.id);
      setState(() => _uncertain = false);
    } catch (error) {
      if (mounted && _guard.isCurrent) {
        setState(() => _error = sharingErrorMessage(context, error));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(collaborationProvider).valueOrNull;
    if (state == null || !_allows(state)) return const SizedBox.shrink();
    final projects = state.dataForScope(widget.scope.id).projects;
    final pending = state.projectSharingPendingScopeIds.contains(
      widget.scope.id,
    );
    if (projects.isEmpty && !pending) return const SizedBox.shrink();
    final l = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),
        Text(
          l.sharingProjectSharingAction,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        for (final project in projects)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.folder_outlined),
            title: Text(project.title),
            trailing: IconButton(
              key: ValueKey('project-sharing-review-${project.id}'),
              tooltip: l.sharingProjectSharingReview,
              onPressed: _busy || pending ? null : () => _review(project),
              icon: const Icon(Icons.people_outline),
            ),
          ),
        if (_busy && !_previewOpen) const LinearProgressIndicator(),
        if (_error != null) Text(_error!),
        if (_uncertain || pending)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: const ValueKey('project-sharing-resume'),
              onPressed: _busy ? null : _resume,
              child: Text(l.organizationAccessResume),
            ),
          ),
      ],
    );
  }
}
