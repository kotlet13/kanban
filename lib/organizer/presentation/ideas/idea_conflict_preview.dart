import '../../data/collaboration_repository.dart' show CollaborationIdeaActions;
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../l10n/l10n.dart';
import '../../state/collaboration_provider.dart';
import '../../state/idea_provider.dart';
import 'idea_canvas.dart';

class IdeaConflictPreview extends ConsumerStatefulWidget {
  const IdeaConflictPreview({
    super.key,
    required this.board,
    required this.scopeId,
    required this.onReady,
  });
  final IdeaBoard board;
  final String scopeId;
  final ValueChanged<bool> onReady;
  @override
  ConsumerState<IdeaConflictPreview> createState() =>
      _IdeaConflictPreviewState();
}

class _IdeaConflictPreviewState extends ConsumerState<IdeaConflictPreview> {
  final Map<String, ui.Image> _images = {};
  bool _loading = true, _missing = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool download = false}) async {
    await Future<void>.value();
    if (!mounted) return;
    final partition = ref
        .read(collaborationProvider)
        .valueOrNull
        ?.session
        ?.partition;
    if (partition == null) return;
    try {
      if (download) {
        final repo = await ref.read(collaborationRepositoryProvider.future);
        await repo.downloadIdeaAssets(widget.scopeId, widget.board);
        if (!mounted) return;
        for (final asset in widget.board.assets) {
          ref.invalidate(
            ideaWorkspaceAssetProvider((
              'shared:$partition:${widget.scopeId}',
              asset,
            )),
          );
        }
      }
      for (final asset in widget.board.assets) {
        if (_images.containsKey(asset.sha256)) continue;
        final bytes = await ref.read(
          ideaWorkspaceAssetProvider((
            'shared:$partition:${widget.scopeId}',
            asset,
          )).future,
        );
        if (bytes == null) continue;
        final codec = await ui.instantiateImageCodec(
          bytes,
          targetWidth: math.min(1024, asset.width),
        );
        final frame = await codec.getNextFrame();
        codec.dispose();
        if (!mounted) {
          frame.image.dispose();
          return;
        }
        _images[asset.sha256] = frame.image;
      }
    } catch (_) {
      /* Keep both versions, with explicit incomplete-media state. */
    }
    if (!mounted) return;
    final ready = widget.board.assets.every(
      (a) => _images.containsKey(a.sha256),
    );
    setState(() {
      _loading = false;
      _missing = !ready;
    });
    widget.onReady(ready);
  }

  @override
  void dispose() {
    for (final image in _images.values) {
      image.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(widget.board.title, style: Theme.of(context).textTheme.titleMedium),
      SizedBox(
        height: 220,
        child: IdeaCanvas(
          board: widget.board,
          onChanged: (_) {},
          tool: IdeaTool.pan,
          images: _images,
          editable: false,
          onSelected: (_) {},
        ),
      ),
      if (_loading) const LinearProgressIndicator(),
      if (_missing) Text(context.l10n.ideasConflictPhotos),
      if (_missing)
        TextButton.icon(
          onPressed: () => _load(download: true),
          icon: const Icon(Icons.download_outlined),
          label: Text(context.l10n.ideasRefreshPhotos),
        ),
      for (final e in widget.board.elements.where((e) => e.text.isNotEmpty))
        Text(e.text),
    ],
  );
}
