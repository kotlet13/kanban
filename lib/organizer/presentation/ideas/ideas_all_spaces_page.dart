import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n.dart';
import '../../state/collaboration_provider.dart';
import '../../state/idea_provider.dart';
import '../../state/local_spaces_provider.dart';
import '../../state/local_database_provider.dart';
import '../../data/idea_storage.dart';
import '../../data/collaboration_repository.dart';
import '../organizer_widgets.dart';
import 'ideas_page.dart';

/// All is a reading projection. Every create/open explicitly selects its source.
class IdeasAllSpacesPage extends ConsumerStatefulWidget {
  const IdeasAllSpacesPage({super.key, required this.onOpenSource});
  final Future<void> Function({
    required bool shared,
    required String spaceId,
    String? boardId,
  })
  onOpenSource;
  @override
  ConsumerState<IdeasAllSpacesPage> createState() => _IdeasAllSpacesPageState();
}

class _IdeasAllSpacesPageState extends ConsumerState<IdeasAllSpacesPage> {
  String _search = '';
  bool _busy = false;
  Future<void> _open(IdeaSpaceEntry entry) async {
    if (_busy) return;
    final state = ref.read(collaborationProvider).valueOrNull;
    if (entry.sharedScopeId != null &&
        entry.workspaceKey !=
            'shared:${state?.session?.partition}:${entry.sharedScopeId}') {
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.onOpenSource(
        shared: entry.sharedScopeId != null,
        spaceId: entry.sharedScopeId ?? entry.localSpaceId ?? 'local',
        boardId: entry.board.id,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _lifecycle(IdeaSpaceEntry entry, bool delete) async {
    if (_busy || !entry.canEdit) return;
    final state = ref.read(collaborationProvider).valueOrNull;
    final identity = (state?.session?.partition, state?.session?.deviceId);
    if (delete) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.l10n.ideasDeleteConfirm),
          content: Text('${entry.board.title} · ${entry.sourceName}'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.l10n.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(
                context.l10n.delete,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    final latest = ref.read(collaborationProvider).valueOrNull;
    if ((latest?.session?.partition, latest?.session?.deviceId) != identity) {
      return;
    }
    setState(() => _busy = true);
    try {
      if (entry.sharedScopeId != null) {
        if (entry.workspaceKey !=
            'shared:${latest?.session?.partition}:${entry.sharedScopeId}') {
          return;
        }
        final repo = await ref.read(collaborationRepositoryProvider.future);
        if (delete) {
          await repo.deleteIdea(entry.sharedScopeId!, entry.board);
        } else {
          await repo.saveIdea(
            entry.sharedScopeId!,
            entry.board.copyWith(archived: !entry.board.archived),
          );
        }
      } else {
        final db = await ref.read(localDatabaseProvider.future);
        await changeLocalIdeaLifecycle(
          db,
          entry.workspaceKey,
          entry.board,
          delete: delete,
        );
      }
      ref.invalidate(ideaAllSpacesProvider);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.l10n.ideasSaveError)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _create() async {
    final local = ref.read(localSpacesProvider).valueOrNull;
    final shared = ref.read(collaborationProvider).valueOrNull;
    final identity = (shared?.session?.partition, shared?.session?.deviceId);
    final target = await showDialog<(bool, String)>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(context.l10n.allSpacesChooseTarget),
        children: [
          for (final space
              in local?.spaces.where(
                    (s) =>
                        s.binding == null &&
                        !(s.id == 'local' &&
                            shared?.privateSync.enabled == true),
                  ) ??
                  <LocalSpace>[])
            SimpleDialogOption(
              key: ValueKey('idea-target-local-${space.id}'),
              onPressed: () => Navigator.pop(context, (false, space.id)),
              child: Text(space.name),
            ),
          if (shared?.localAccessAllowed == true)
            for (final scope in shared!.scopes.where(
              (s) => s.canEdit && !s.revoked && !s.blocked && !s.archived,
            ))
              SimpleDialogOption(
                key: ValueKey('idea-target-shared-${scope.id}'),
                onPressed: () => Navigator.pop(context, (true, scope.id)),
                child: Text(
                  '${scope.name} · ${scope.kind == SharedScopeKind.personal ? context.l10n.organizerPersonal : context.l10n.sharingShared}',
                ),
              ),
        ],
      ),
    );
    if (target == null || !mounted) return;
    final current = ref.read(collaborationProvider).valueOrNull;
    if ((current?.session?.partition, current?.session?.deviceId) != identity) {
      return;
    }
    await widget.onOpenSource(shared: target.$1, spaceId: target.$2);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final currentSharing = ref.watch(collaborationProvider).valueOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OrganizerHeading(
          title: l.ideasTitle,
          subtitle: l.allSpacesDescription,
          action: FilledButton.icon(
            key: const ValueKey('idea-all-add'),
            onPressed: _busy ? null : _create,
            icon: const Icon(Icons.add),
            label: Text(l.ideasAdd),
          ),
        ),
        TextField(
          decoration: InputDecoration(
            labelText: l.ideasSearch,
            prefixIcon: const Icon(Icons.search),
          ),
          onChanged: (value) => setState(() => _search = value),
        ),
        const SizedBox(height: 16),
        ref
            .watch(ideaAllSpacesProvider)
            .when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => Text(l.organizerLoadError),
              data: (entries) {
                final visible =
                    entries
                        .where(
                          (e) =>
                              e.sharedScopeId == null ||
                              currentSharing?.localAccessAllowed == true &&
                                  e.workspaceKey ==
                                      'shared:${currentSharing?.session?.partition}:${e.sharedScopeId}' &&
                                  currentSharing!.scopes.any(
                                    (s) =>
                                        s.id == e.sharedScopeId &&
                                        !s.revoked &&
                                        !s.blocked,
                                  ),
                        )
                        .where(
                          (e) =>
                              '${e.board.title} ${e.sourceName} ${e.board.elements.map((v) => v.text).join(' ')}'
                                  .toLowerCase()
                                  .contains(_search.toLowerCase()),
                        )
                        .toList()
                      ..sort(
                        (a, b) =>
                            b.board.updatedAt.compareTo(a.board.updatedAt),
                      );
                return Column(
                  children: [
                    if (!visible.any((e) => !e.board.archived))
                      OrganizerEmpty(
                        icon: Icons.lightbulb_outline,
                        title: l.ideasTitle,
                        description: l.ideasEmpty,
                      ),
                    for (final entry in visible.where((e) => !e.board.archived))
                      IdeaCard(
                        board: entry.board,
                        workspaceKey: entry.workspaceKey,
                        subtitle: entry.sourceName,
                        onArchive: entry.canEdit
                            ? () => _lifecycle(entry, false)
                            : null,
                        onDelete: entry.canEdit
                            ? () => _lifecycle(entry, true)
                            : null,
                        onOpen: () => _open(entry),
                      ),
                    if (visible.any((e) => e.board.archived))
                      ExpansionTile(
                        title: Text(l.ideasArchived),
                        children: [
                          for (final entry in visible.where(
                            (e) => e.board.archived,
                          ))
                            IdeaCard(
                              board: entry.board,
                              workspaceKey: entry.workspaceKey,
                              subtitle: entry.sourceName,
                              onArchive: entry.canEdit
                                  ? () => _lifecycle(entry, false)
                                  : null,
                              onDelete: entry.canEdit
                                  ? () => _lifecycle(entry, true)
                                  : null,
                              onOpen: () => _open(entry),
                            ),
                        ],
                      ),
                  ],
                );
              },
            ),
      ],
    );
  }
}
