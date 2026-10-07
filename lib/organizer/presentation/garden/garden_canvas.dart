import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';

import '../../domain/garden_models.dart';

enum GardenTool { select, draw }

/// A proportional sketch: coordinates are fractions of the whole garden.
/// Gestures preview locally and commit one change only after a complete drag.
class GardenCanvas extends StatefulWidget {
  const GardenCanvas({
    super.key,
    required this.areas,
    required this.tool,
    required this.selectedId,
    required this.onSelect,
    required this.onDraw,
    required this.onMove,
    required this.semanticLabel,
  });
  final List<GardenArea> areas;
  final GardenTool tool;
  final String? selectedId;
  final ValueChanged<String?> onSelect;
  final ValueChanged<Rect> onDraw;
  final ValueChanged<GardenArea> onMove;
  final String semanticLabel;

  @override
  State<GardenCanvas> createState() => _GardenCanvasState();
}

class _GardenCanvasState extends State<GardenCanvas> {
  Offset? _start;
  Rect? _drawing;
  GardenArea? _moving;
  GardenArea? _original;

  Offset _normalized(Offset position, Size size) => Offset(
    (position.dx / size.width).clamp(0.0, 1.0),
    (position.dy / size.height).clamp(0.0, 1.0),
  );

  GardenArea? _hit(Offset point) => widget.areas.reversed
      .where(
        (area) => Rect.fromLTWH(
          area.x,
          area.y,
          area.width,
          area.height,
        ).contains(point),
      )
      .firstOrNull;

  void _clear() => setState(() {
    _start = null;
    _drawing = null;
    _moving = null;
    _original = null;
  });

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: 4 / 3,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final scheme = Theme.of(context).colorScheme;
        return Semantics(
          label: widget.semanticLabel,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: MouseRegion(
              cursor: widget.tool == GardenTool.draw
                  ? SystemMouseCursors.precise
                  : SystemMouseCursors.grab,
              child: GestureDetector(
                key: const ValueKey('garden-canvas'),
                behavior: HitTestBehavior.opaque,
                dragStartBehavior: DragStartBehavior.down,
                onTapDown: widget.tool == GardenTool.select
                    ? (details) => widget.onSelect(
                        _hit(_normalized(details.localPosition, size))?.id,
                      )
                    : null,
                onPanStart: (details) {
                  final point = _normalized(details.localPosition, size);
                  _start = point;
                  if (widget.tool == GardenTool.select) {
                    _original = _hit(point);
                    _moving = _original;
                    widget.onSelect(_original?.id);
                  } else {
                    setState(() => _drawing = Rect.fromPoints(point, point));
                  }
                },
                onPanUpdate: (details) {
                  if (_start == null) return;
                  final point = _normalized(details.localPosition, size);
                  setState(() {
                    if (widget.tool == GardenTool.draw) {
                      _drawing = Rect.fromPoints(_start!, point);
                    } else if (_original != null) {
                      final delta = point - _start!;
                      _moving = _original!.copyWith(
                        x: (_original!.x + delta.dx).clamp(
                          0.0,
                          1.0 - _original!.width,
                        ),
                        y: (_original!.y + delta.dy).clamp(
                          0.0,
                          1.0 - _original!.height,
                        ),
                      );
                    }
                  });
                },
                onPanEnd: (_) {
                  final drawing = _drawing;
                  final moving = _moving;
                  if (drawing != null &&
                      drawing.width >= .01 &&
                      drawing.height >= .01) {
                    widget.onDraw(drawing);
                  } else if (moving != null &&
                      _original != null &&
                      (moving.x != _original!.x || moving.y != _original!.y)) {
                    widget.onMove(moving);
                  }
                  _clear();
                },
                onPanCancel: _clear,
                child: CustomPaint(
                  painter: _GardenPainter(
                    areas: [
                      for (final area in widget.areas)
                        area.id == _moving?.id ? _moving! : area,
                    ],
                    selectedId: widget.selectedId,
                    drawing: _drawing,
                    scheme: scheme,
                    textDirection: Directionality.of(context),
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}

class _GardenPainter extends CustomPainter {
  _GardenPainter({
    required this.areas,
    required this.selectedId,
    required this.drawing,
    required this.scheme,
    required this.textDirection,
  });
  final List<GardenArea> areas;
  final String? selectedId;
  final Rect? drawing;
  final ColorScheme scheme;
  final TextDirection textDirection;

  Rect _pixels(Rect rect, Size size) => Rect.fromLTWH(
    rect.left * size.width,
    rect.top * size.height,
    rect.width * size.width,
    rect.height * size.height,
  );

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = scheme.surfaceContainerLow,
    );
    final grid = Paint()
      ..color = scheme.outlineVariant.withValues(alpha: .55)
      ..strokeWidth = 1;
    for (var i = 0; i <= 10; i++) {
      canvas.drawLine(
        Offset(size.width * i / 10, 0),
        Offset(size.width * i / 10, size.height),
        grid,
      );
      canvas.drawLine(
        Offset(0, size.height * i / 10),
        Offset(size.width, size.height * i / 10),
        grid,
      );
    }
    for (final area in areas) {
      final rect = _pixels(
        Rect.fromLTWH(area.x, area.y, area.width, area.height),
        size,
      );
      final selected = area.id == selectedId;
      canvas.drawRect(
        rect,
        Paint()
          ..color = selected
              ? scheme.primaryContainer
              : scheme.secondaryContainer,
      );
      canvas.drawRect(
        rect.deflate(1),
        Paint()
          ..color = selected ? scheme.primary : scheme.outline
          ..style = PaintingStyle.stroke
          ..strokeWidth = selected ? 2 : 1,
      );
      if (rect.width > 24 && rect.height > 18) {
        final text = TextPainter(
          text: TextSpan(
            text: area.label,
            style: TextStyle(
              fontSize: 12,
              color: selected
                  ? scheme.onPrimaryContainer
                  : scheme.onSecondaryContainer,
            ),
          ),
          textDirection: textDirection,
          maxLines: 2,
          ellipsis: '…',
        )..layout(maxWidth: rect.width - 12);
        canvas.save();
        canvas.clipRect(rect.deflate(3));
        text.paint(canvas, rect.topLeft + const Offset(6, 5));
        canvas.restore();
      }
    }
    if (drawing != null) {
      final rect = _pixels(drawing!, size);
      canvas.drawRect(
        rect,
        Paint()..color = scheme.primary.withValues(alpha: .15),
      );
      canvas.drawRect(
        rect,
        Paint()
          ..color = scheme.primary
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _GardenPainter oldDelegate) => true;
}
