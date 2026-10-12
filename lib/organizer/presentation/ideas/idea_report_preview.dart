import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../l10n/l10n.dart';
import '../../domain/idea_models.dart';
import '../../state/collaboration_provider.dart';
import 'idea_canvas.dart';

/// Renders only the immutable board/image references authorized by reportPreview.
class IdeaReportPreview extends ConsumerStatefulWidget {
  const IdeaReportPreview({
    super.key,
    required this.preview,
    required this.onReady,
  });
  final ContentReportPreview preview;
  final ValueChanged<bool> onReady;
  @override
  ConsumerState<IdeaReportPreview> createState() => _IdeaReportPreviewState();
}

class _IdeaReportPreviewState extends ConsumerState<IdeaReportPreview> {
  IdeaBoard? _board;
  final Map<String, ui.Image> _images = {};
  bool _loading = true;
  Object? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await Future<void>.value();
    try {
      final board = IdeaBoard.fromJson(
        Map<String, dynamic>.from(widget.preview.evidence['board'] as Map),
      );
      final controller = ref.read(collaborationProvider.notifier);
      for (final asset in board.assets) {
        if (_images.containsKey(asset.sha256)) continue;
        final bytes = await controller.loadReportIdeaAsset(
          widget.preview,
          asset,
        );
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
      if (mounted) {
        setState(() {
          _board = board;
          _loading = false;
        });
        widget.onReady(true);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error;
          _loading = false;
        });
        widget.onReady(false);
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
    final l = context.l10n;
    if (_loading) {
      return const SizedBox(
        height: 180,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null || _board == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.ideasReportUnavailable),
          TextButton(
            onPressed: () {
              setState(() {
                _error = null;
                _loading = true;
              });
              _load();
            },
            child: Text(l.organizerRetry),
          ),
        ],
      );
    }
    final board = _board!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l.ideasReportDescription),
        const SizedBox(height: 8),
        SizedBox(
          height: 260,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            child: IdeaCanvas(
              board: board,
              onChanged: (_) {},
              tool: IdeaTool.pan,
              images: _images,
              editable: false,
              onSelected: (_) {},
            ),
          ),
        ),
        ExpansionTile(
          title: Text(l.ideasElements),
          children: [
            for (final element in board.elements)
              ListTile(
                dense: true,
                title: Text(
                  element.text.isEmpty
                      ? _kind(context, element.kind)
                      : element.text,
                ),
              ),
          ],
        ),
      ],
    );
  }

  String _kind(BuildContext context, IdeaElementKind kind) => switch (kind) {
    IdeaElementKind.image => context.l10n.ideasPhoto,
    IdeaElementKind.text => context.l10n.ideasText,
    IdeaElementKind.sticky => context.l10n.ideasSticky,
    IdeaElementKind.stroke => context.l10n.ideasPen,
    IdeaElementKind.rectangle => context.l10n.ideasRectangle,
    IdeaElementKind.ellipse => context.l10n.ideasEllipse,
    IdeaElementKind.line => context.l10n.ideasLine,
    IdeaElementKind.arrow => context.l10n.ideasArrow,
  };
}
