import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../l10n/l10n.dart';
import '../../state/collaboration_provider.dart';
import 'sharing_errors.dart';
import 'sharing_session_boundary.dart';

class OrganizationAccessSettings extends ConsumerStatefulWidget {
  const OrganizationAccessSettings({super.key, required this.scope});
  final SharedScope scope;
  @override
  ConsumerState<OrganizationAccessSettings> createState() =>
      _OrganizationAccessSettingsState();
}

class _OrganizationAccessSettingsState
    extends ConsumerState<OrganizationAccessSettings> {
  bool _busy = false, _previewOpen = false;
  String? _error;
  late final _guard = SharingSessionGuard(context, ref);
  bool _allows(CollaborationState state) =>
      !state.sessionInvalid &&
      !state.deletionPending &&
      state.session?.expiresAt.isAfter(DateTime.now()) == true &&
      state.selectedSpaceId == widget.scope.id &&
      !state.allSpacesSelected &&
      state.scopes.any(
        (scope) =>
            scope.id == widget.scope.id && scope.canManage && !scope.blocked,
      );

  Future<void> _review() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final preview = await _guard.controller.previewOrganizationAccess(
        widget.scope.id,
      );
      if (!mounted ||
          !_guard.isCurrent ||
          !_allows(ref.read(collaborationProvider).requireValue)) {
        return;
      }
      setState(() => _previewOpen = true);
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => SharingSessionBoundary(
          guard: _guard,
          visibleWhen: _allows,
          child: AlertDialog(
            scrollable: true,
            title: Text(context.l10n.organizationAccessReview),
            content: SizedBox(
              width: 560,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(context.l10n.organizationAccessReviewDescription),
                  for (final project in preview.projects) ...[
                    const SizedBox(height: 16),
                    Text(
                      project.name,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    if (project.additionalReaders.isEmpty)
                      Text(context.l10n.organizationAccessNoReaders),
                    for (final reader in project.additionalReaders)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.person_outline),
                        title: Text(reader.displayName),
                        subtitle: Text(
                          reader.accessSource == 'leadership'
                              ? context.l10n.organizationLeader
                              : context.l10n.sharingMember,
                        ),
                      ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(context.l10n.cancel),
              ),
              FilledButton(
                key: const ValueKey('organization-access-confirm'),
                onPressed: () => Navigator.pop(context, true),
                child: Text(context.l10n.organizationAccessApply),
              ),
            ],
          ),
        ),
      );
      if (confirmed == true &&
          mounted &&
          _guard.isCurrent &&
          _allows(ref.read(collaborationProvider).requireValue)) {
        await _guard.controller.applyOrganizationAccess(
          widget.scope.id,
          preview.previewHash,
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = sharingErrorMessage(context, error));
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
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _guard.controller.resumeOrganizationAccessChange(widget.scope.id);
    } catch (error) {
      if (mounted) setState(() => _error = sharingErrorMessage(context, error));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _previewOpen = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(collaborationProvider).valueOrNull;
    final scope = state?.scopes
        .where((s) => s.id == widget.scope.id)
        .firstOrNull;
    if (state == null || scope == null || !_allows(state)) {
      return const SizedBox.shrink();
    }
    final l = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (scope.accessPolicyVersion >= 2)
          Text(l.organizationAccessCurrent)
        else
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              key: const ValueKey('organization-access-review'),
              onPressed: _busy ? null : _review,
              icon: const Icon(Icons.visibility_outlined),
              label: Text(l.organizationAccessReview),
            ),
          ),
        if (_busy && !_previewOpen) const LinearProgressIndicator(),
        if (_error != null) ...[
          Text(_error!),
          TextButton(
            onPressed: _busy ? null : _resume,
            child: Text(l.organizationAccessResume),
          ),
        ],
        const SizedBox(height: 16),
      ],
    );
  }
}
