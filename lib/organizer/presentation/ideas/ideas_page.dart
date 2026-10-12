import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n.dart';
import '../../state/idea_provider.dart';
import '../../state/organizer_provider.dart';
import '../organizer_widgets.dart';
import 'idea_canvas.dart';
import 'idea_editor.dart';

class IdeasPage extends ConsumerStatefulWidget {
  const IdeasPage({super.key, this.projectId});
  final String? projectId;
  @override
  ConsumerState<IdeasPage> createState() => _IdeasPageState();
}

class _IdeasPageState extends ConsumerState<IdeasPage> {
  String _search = '';
  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return ref
        .watch(ideaProvider)
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => Text(l.organizerLoadError),
          data: (snapshot) {
            final drafts =
                ref.watch(ideaDraftsProvider).valueOrNull ?? <IdeaBoard>[];
            final query = _search.toLowerCase();
            final boards =
                snapshot.boards
                    .where(
                      (b) =>
                          (widget.projectId == null ||
                              b.projectId == widget.projectId) &&
                          '${b.title} ${b.elements.map((e) => e.text).join(' ')}'
                              .toLowerCase()
                              .contains(query),
                    )
                    .toList()
                  ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
            final projects =
                ref.watch(organizerProvider).valueOrNull?.projects ?? [];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                OrganizerHeading(
                  title: l.ideasTitle,
                  action: snapshot.canEdit
                      ? FilledButton.icon(
                          key: const ValueKey('idea-add'),
                          onPressed: () => openIdeaEditor(
                            context,
                            ref,
                            projectId: widget.projectId,
                          ),
                          icon: const Icon(Icons.add),
                          label: Text(l.ideasAdd),
                        )
                      : null,
                ),
                TextField(
                  key: const ValueKey('ideas-search'),
                  onChanged: (v) => setState(() => _search = v),
                  decoration: InputDecoration(
                    labelText: l.ideasSearch,
                    prefixIcon: const Icon(Icons.search),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                if (snapshot.canEdit &&
                    drafts.any(
                      (d) => !snapshot.boards.any((b) => b.id == d.id),
                    ))
                  OrganizerSection(
                    title: l.ideasDrafts,
                    child: Column(
                      children: [
                        for (final draft in drafts.where(
                          (d) => !snapshot.boards.any((b) => b.id == d.id),
                        ))
                          ListTile(
                            key: ValueKey('idea-draft-${draft.id}'),
                            leading: const Icon(Icons.edit_note),
                            title: Text(draft.title),
                            subtitle: Text(l.ideasDraftResume),
                            onTap: () => openIdeaEditor(
                              context,
                              ref,
                              board: draft,
                              draftOnly: true,
                            ),
                          ),
                      ],
                    ),
                  ),
                if (!snapshot.canEdit)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(l.ideasReadOnly),
                  ),
                if (boards.isEmpty)
                  OrganizerEmpty(
                    icon: Icons.lightbulb_outline,
                    title: l.ideasTitle,
                    description: l.ideasEmpty,
                  ),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final count = constraints.maxWidth >= 1000
                        ? 3
                        : constraints.maxWidth >= 650
                        ? 2
                        : 1;
                    final width =
                        (constraints.maxWidth - 12 * (count - 1)) / count;
                    return Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        for (final board in boards)
                          SizedBox(
                            width: width,
                            child: IdeaCard(
                              board: board,
                              subtitle: projects
                                  .where((p) => p.id == board.projectId)
                                  .firstOrNull
                                  ?.title,
                              onOpen: () =>
                                  openIdeaEditor(context, ref, board: board),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ],
            );
          },
        );
  }
}

class IdeaCard extends ConsumerStatefulWidget {
  const IdeaCard({
    super.key,
    required this.board,
    required this.onOpen,
    this.subtitle,
    this.workspaceKey,
  });
  final IdeaBoard board;
  final VoidCallback onOpen;
  final String? subtitle, workspaceKey;
  @override
  ConsumerState<IdeaCard> createState() => _IdeaCardState();
}

class _IdeaCardState extends ConsumerState<IdeaCard> {
  final Map<String, ui.Image> _images = {};
  final Set<String> _loading = {};
  int _loadGeneration = 0;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant IdeaCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workspaceKey != widget.workspaceKey ||
        oldWidget.board.id != widget.board.id) {
      _loadGeneration++;
      for (final image in _images.values) {
        image.dispose();
      }
      _images.clear();
      _loading.clear();
    }
    if (oldWidget.board != widget.board ||
        oldWidget.workspaceKey != widget.workspaceKey) {
      _load();
    }
  }

  Future<void> _load() async {
    final generation = _loadGeneration;
    final workspace =
        widget.workspaceKey ?? ref.read(ideaProvider).valueOrNull?.workspaceKey;
    if (workspace == null) return;
    for (final asset in widget.board.assets) {
      if (_images.containsKey(asset.sha256) || !_loading.add(asset.sha256)) {
        continue;
      }
      try {
        final bytes = await ref.read(
          ideaWorkspaceAssetProvider((workspace, asset)).future,
        );
        if (bytes == null) continue;
        final codec = await ui.instantiateImageCodec(
          bytes,
          targetWidth: asset.width.clamp(1, 256),
        );
        final frame = await codec.getNextFrame();
        codec.dispose();
        if (mounted && generation == _loadGeneration) {
          setState(() => _images[asset.sha256] = frame.image);
        } else {
          frame.image.dispose();
        }
      } catch (_) {
        /* Placeholder in preview retains missing status. */
      } finally {
        if (generation == _loadGeneration) _loading.remove(asset.sha256);
      }
    }
  }

  @override
  void dispose() {
    for (final image in _images.values) {
      image.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final workspace =
        widget.workspaceKey ??
        ref.watch(ideaProvider).valueOrNull?.workspaceKey;
    if (workspace != null) {
      for (final asset in widget.board.assets) {
        ref.listen(ideaWorkspaceAssetProvider((workspace, asset)), (_, next) {
          if (next.hasValue &&
              next.value != null &&
              !_images.containsKey(asset.sha256)) {
            _load();
          }
        });
      }
    }
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey('idea-card-${widget.board.id}'),
        onTap: widget.onOpen,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              label: context.l10n.ideasCanvasLabel,
              child: SizedBox(
                height: 170,
                child: ClipRect(
                  child: FittedBox(
                    fit: BoxFit.contain,
                    child: SizedBox(
                      width: widget.board.width,
                      height: widget.board.height,
                      child: CustomPaint(
                        painter: IdeaBoardPainter(
                          elements: widget.board.elements,
                          images: _images,
                          surface: Theme.of(context).colorScheme.surface,
                          missingLabel: context.l10n.ideasMissingPhoto,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.board.title,
                    style: Theme.of(context).textTheme.titleMedium,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (widget.subtitle != null)
                    Text(widget.subtitle!, maxLines: 2),
                  Text(
                    organizerDate(context, widget.board.updatedAt),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
