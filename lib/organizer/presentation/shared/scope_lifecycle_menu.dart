import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n.dart';
import '../../state/collaboration_provider.dart';
import 'sharing_errors.dart';
import 'sharing_session_boundary.dart';

/// Named, counted destructive preview. Fetching it never deletes or archives.
Future<bool> showScopeDeletionDialog(
  BuildContext context,
  WidgetRef ref,
  SharedScope scope, {
  String? projectId,
}) async {
  final guard = SharingSessionGuard(context, ref);
  bool permitted(CollaborationState state) =>
      state.localAccessAllowed &&
      !state.sessionInvalid &&
      state.session?.expiresAt.isAfter(DateTime.now()) == true &&
      state.scopes.any(
        (s) =>
            s.id == scope.id &&
            !s.revoked &&
            (projectId == null || projectId == s.projectRootId
                ? s.isOwner && !s.blocked
                : s.canEdit),
      );
  try {
    final preview = await guard.controller.previewScopeDeletion(
      scope.id,
      projectId: projectId,
    );
    if (!context.mounted ||
        !guard.isCurrent ||
        !permitted(ref.read(collaborationProvider).requireValue)) {
      return false;
    }
    final counts = Map<String, dynamic>.from(preview['counts'] as Map);
    final l = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => SharingSessionBoundary(
        guard: guard,
        visibleWhen: permitted,
        child: AlertDialog(
          scrollable: true,
          title: Text('${l.scopeDeleteTitle} · ${preview['name']}'),
          content: SizedBox(
            width: 480,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(l.scopeDeleteDescription),
                const SizedBox(height: 16),
                for (final name in preview['scopeNames'] as List)
                  Text('• $name'),
                const SizedBox(height: 12),
                Text(
                  l.scopeDeleteCounts(
                    counts['projects'] as int,
                    counts['tasks'] as int,
                    counts['events'] as int,
                    counts['ideas'] as int,
                    counts['photos'] as int,
                    counts['finance'] as int,
                    counts['other'] as int,
                  ),
                ),
                const SizedBox(height: 12),
                Text(l.sharingSaveDraftsDescription),
                if (preview['canDelete'] != true) ...[
                  const SizedBox(height: 12),
                  Text(l.scopeDeleteBlocked),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              autofocus: true,
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(l.cancel),
            ),
            TextButton(
              key: const ValueKey('scope-delete-confirm'),
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(dialogContext).colorScheme.error,
              ),
              onPressed: preview['canDelete'] == true
                  ? () => Navigator.pop(dialogContext, true)
                  : null,
              child: Text(l.delete),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true ||
        !context.mounted ||
        !guard.isCurrent ||
        !permitted(ref.read(collaborationProvider).requireValue)) {
      return false;
    }
    await guard.controller.deleteScopeContents(preview, projectId: projectId);
    return true;
  } catch (error) {
    if (context.mounted && guard.isCurrent) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(sharingErrorMessage(context, error))),
      );
    }
    return false;
  }
}

class ScopeLifecycleMenu extends ConsumerWidget {
  const ScopeLifecycleMenu({super.key, required this.scope});
  final SharedScope scope;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(collaborationProvider).valueOrNull;
    final current = state?.scopes.where((s) => s.id == scope.id).firstOrNull;
    if (current == null ||
        current.revoked ||
        current.blocked ||
        !current.canManage ||
        state?.localAccessAllowed != true ||
        state?.sessionInvalid == true) {
      return const SizedBox.shrink();
    }
    final archive =
        state!.scopeArchivingSupported ||
        state.projectArchivingSupported &&
            current.kind == SharedScopeKind.project &&
            current.projectRootId != null;
    final delete = state.scopeDeletionSupported && current.isOwner;
    if (!archive && !delete) return const SizedBox.shrink();
    final l = context.l10n;
    return PopupMenuButton<String>(
      key: ValueKey('scope-lifecycle-${scope.id}'),
      tooltip: '${l.scopeLifecycleMenu} · ${current.name}',
      icon: const Icon(Icons.more_horiz),
      onSelected: (action) async {
        final guard = SharingSessionGuard(context, ref);
        if (action == 'delete') {
          await showScopeDeletionDialog(context, ref, current);
        } else {
          try {
            await guard.controller.archiveProjectScope(
              current.id,
              archived: !current.archived,
            );
          } catch (error) {
            if (context.mounted && guard.isCurrent) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(sharingErrorMessage(context, error))),
              );
            }
          }
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem<String>(enabled: false, child: Text(current.name)),
        if (archive)
          PopupMenuItem<String>(
            value: 'archive',
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                current.archived
                    ? Icons.unarchive_outlined
                    : Icons.archive_outlined,
              ),
              title: Text(current.archived ? l.peopleRestore : l.peopleArchive),
            ),
          ),
        if (archive && delete) const PopupMenuDivider(),
        if (delete)
          PopupMenuItem<String>(
            value: 'delete',
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.delete_outline,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(
                l.delete,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ),
      ],
    );
  }
}
