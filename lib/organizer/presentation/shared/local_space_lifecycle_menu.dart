import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n.dart';
import '../../state/local_spaces_provider.dart';
import '../../state/organizer_provider.dart';
import '../../domain/organizer_models.dart';
import '../personal_workspace_boundary.dart';
import 'sharing_errors.dart';

Future<bool> showLocalSpaceDeletionDialog(
  BuildContext context,
  WidgetRef ref,
  LocalSpace space,
) async {
  final identity = ref.read(localSpacesProvider).valueOrNull?.selectedSpaceId;
  final guard = PersonalWorkspaceGuard(context, ref, space.id);
  bool current() =>
      context.mounted &&
      ref.read(localSpacesProvider).valueOrNull?.selectedSpaceId == identity &&
      ref
              .read(localSpacesProvider)
              .valueOrNull
              ?.spaces
              .any((s) => s.id == space.id && s.binding == null) ==
          true;
  try {
    final controller = ref.read(localSpacesProvider.notifier);
    final preview = await controller.previewSpaceDeletion(space.id);
    if (!context.mounted || !current()) return false;
    final l = context.l10n, counts = preview['counts'] as Map;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => PersonalWorkspaceBoundary(
        guard: guard,
        child: AlertDialog(
          scrollable: true,
          title: Text('${l.scopeDeleteTitle} · ${preview['name']}'),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.scopeDeleteDescription),
                const SizedBox(height: 16),
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
                Text(
                  l.scopeDeleteLocalExtras(
                    counts['gardens'] as int,
                    counts['drafts'] as int,
                  ),
                ),
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
              key: const ValueKey('local-space-delete-confirm'),
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
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
    if (confirmed != true || !current()) return false;
    await controller.deleteSpace(preview);
    return true;
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(sharingErrorMessage(context, error))),
      );
    }
    return false;
  }
}

class LocalSpaceLifecycleMenu extends ConsumerWidget {
  const LocalSpaceLifecycleMenu({super.key, required this.space});
  final LocalSpace space;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (space.id == 'local' || space.binding != null) {
      return const SizedBox.shrink();
    }
    final l = context.l10n;
    return PopupMenuButton<String>(
      key: ValueKey('local-space-lifecycle-${space.id}'),
      tooltip: '${l.scopeLifecycleMenu} · ${space.name}',
      icon: const Icon(Icons.more_horiz),
      onSelected: (action) async {
        if (action == 'delete') {
          await showLocalSpaceDeletionDialog(context, ref, space);
        } else {
          try {
            await ref
                .read(localSpacesProvider.notifier)
                .archiveSpace(space.id, archived: !space.archived);
          } catch (error) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(sharingErrorMessage(context, error))),
              );
            }
          }
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem<String>(enabled: false, child: Text(space.name)),
        PopupMenuItem<String>(
          value: 'archive',
          child: Text(space.archived ? l.peopleRestore : l.peopleArchive),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'delete',
          child: Text(
            l.delete,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      ],
    );
  }
}

/// The local project preview includes separately stored boards, drafts and photos.
Future<bool> showLocalProjectDeletionDialog(
  BuildContext context,
  WidgetRef ref,
  OrganizerSnapshot snapshot,
  LocalProject project,
) async {
  final guard = PersonalWorkspaceGuard(context, ref, snapshot.workspaceKey);
  try {
    final controller = ref.read(organizerProvider.notifier);
    final preview = await controller.previewProjectDeletion(project.id);
    if (!context.mounted || !guard.isCurrent) return false;
    final l = context.l10n, counts = preview['counts'] as Map;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => guard.wrap(
        AlertDialog(
          scrollable: true,
          title: Text('${l.scopeDeleteTitle} · ${preview['name']}'),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.scopeDeleteDescription),
                const SizedBox(height: 16),
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
                Text(
                  l.scopeDeleteLocalExtras(
                    counts['gardens'] as int,
                    counts['drafts'] as int,
                  ),
                ),
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
              key: const ValueKey('local-project-delete-confirm'),
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
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
    if (confirmed != true || !context.mounted || !guard.isCurrent) return false;
    await controller.deleteProject(
      project.id,
      previewHash: preview['previewHash'] as String,
    );
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
