import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';

import '../../domain/garden_models.dart';

part 'garden_canvas_painter.dart';

enum GardenTool { select, draw, pan }

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
    this.areaCaptions = const {},
    this.zoomInLabel,
    this.zoomOutLabel,
    this.resetViewLabel,
  });
  final List<GardenArea> areas;
  final GardenTool tool;
  final String? selectedId;
  final ValueChanged<String?> onSelect;
  final ValueChanged<Rect> onDraw;
  final ValueChanged<GardenArea> onMove;
  final String semanticLabel;
  final Map<String, String> areaCaptions;
  final String? zoomInLabel, zoomOutLabel, resetViewLabel;

  @override
  State<GardenCanvas> createState() => _GardenCanvasState();
}

class _GardenCanvasState extends State<GardenCanvas> {
  Offset? _start;
  Rect? _drawing;
  GardenArea? _moving;
  GardenArea? _original;
  int? _resizeCorner;
  final _view = TransformationController();

  @override
  void dispose() {
    _view.dispose();
    super.dispose();
  }

  int? _handleAt(Offset point, Size size) {
    final selected = widget.areas
        .where((a) => a.id == widget.selectedId)
        .firstOrNull;
    if (selected == null) return null;
    final corners = [
      Offset(selected.x, selected.y),
      Offset(selected.x + selected.width, selected.y),
      Offset(selected.x, selected.y + selected.height),
      Offset(selected.x + selected.width, selected.y + selected.height),
    ];
    int? nearest;
    var distance = 18 / _view.value.getMaxScaleOnAxis();
    for (var i = 0; i < corners.length; i++) {
      final delta = point - corners[i];
      final candidate = Offset(
        delta.dx * size.width,
        delta.dy * size.height,
      ).distance;
      if (candidate <= distance) {
        nearest = i;
        distance = candidate;
      }
    }
    return nearest;
  }

  GardenArea _resize(GardenArea area, Offset point, int corner) {
    var left = area.x,
        top = area.y,
        right = area.x + area.width,
        bottom = area.y + area.height;
    if (corner == 0 || corner == 2) {
      left = point.dx.clamp(0.0, right - math.min(.01, right));
    } else {
      right = point.dx.clamp(left + math.min(.01, 1 - left), 1.0);
    }
    if (corner == 0 || corner == 1) {
      top = point.dy.clamp(0.0, bottom - math.min(.01, bottom));
    } else {
      bottom = point.dy.clamp(top + math.min(.01, 1 - top), 1.0);
    }
    return area.copyWith(
      x: left,
      y: top,
      width: right - left,
      height: bottom - top,
    );
  }

  void _zoom(double factor) {
    final current = _view.value.getMaxScaleOnAxis();
    final scale = (current * factor).clamp(1.0, 4.0);
    _view.value = Matrix4.identity()..scaleByDouble(scale, scale, scale, 1);
  }

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
    _resizeCorner = null;
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
            child: Stack(
              children: [
                InteractiveViewer(
                  transformationController: _view,
                  panEnabled: widget.tool == GardenTool.pan,
                  scaleEnabled: widget.tool == GardenTool.pan,
                  minScale: 1,
                  maxScale: 4,
                  child: MouseRegion(
                    cursor: widget.tool == GardenTool.draw
                        ? SystemMouseCursors.precise
                        : SystemMouseCursors.grab,
                    child: GestureDetector(
                      key: const ValueKey('garden-canvas'),
                      behavior: HitTestBehavior.opaque,
                      dragStartBehavior: DragStartBehavior.down,
                      onTapDown: widget.tool == GardenTool.select
                          ? (details) {
                              final point = _normalized(
                                details.localPosition,
                                size,
                              );
                              if (_handleAt(point, size) == null) {
                                widget.onSelect(_hit(point)?.id);
                              }
                            }
                          : null,
                      onPanStart: widget.tool == GardenTool.pan
                          ? null
                          : (details) {
                              final point = _normalized(
                                details.localPosition,
                                size,
                              );
                              _start = point;
                              if (widget.tool == GardenTool.select) {
                                _resizeCorner = _handleAt(point, size);
                                _original = _resizeCorner == null
                                    ? _hit(point)
                                    : widget.areas
                                          .where(
                                            (a) => a.id == widget.selectedId,
                                          )
                                          .firstOrNull;
                                _moving = _original;
                                widget.onSelect(_original?.id);
                              } else {
                                setState(
                                  () =>
                                      _drawing = Rect.fromPoints(point, point),
                                );
                              }
                            },
                      onPanUpdate: widget.tool == GardenTool.pan
                          ? null
                          : (details) {
                              if (_start == null) return;
                              final point = _normalized(
                                details.localPosition,
                                size,
                              );
                              setState(() {
                                if (widget.tool == GardenTool.draw) {
                                  _drawing = Rect.fromPoints(_start!, point);
                                } else if (_original != null &&
                                    _resizeCorner != null) {
                                  _moving = _resize(
                                    _original!,
                                    point,
                                    _resizeCorner!,
                                  );
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
                      onPanEnd: widget.tool == GardenTool.pan
                          ? null
                          : (_) {
                              final drawing = _drawing;
                              final moving = _moving;
                              if (drawing != null &&
                                  drawing.width >= .01 &&
                                  drawing.height >= .01) {
                                widget.onDraw(drawing);
                              } else if (moving != null &&
                                  _original != null &&
                                  (moving.x != _original!.x ||
                                      moving.y != _original!.y ||
                                      moving.width != _original!.width ||
                                      moving.height != _original!.height)) {
                                widget.onMove(moving);
                              }
                              _clear();
                            },
                      onPanCancel: widget.tool == GardenTool.pan
                          ? null
                          : _clear,
                      child: CustomPaint(
                        painter: _GardenPainter(
                          areas: [
                            for (final area in widget.areas)
                              area.id == _moving?.id ? _moving! : area,
                          ],
                          selectedId: widget.selectedId,
                          areaCaptions: widget.areaCaptions,
                          drawing: _drawing,
                          scheme: scheme,
                          textDirection: Directionality.of(context),
                          labelStyle:
                              Theme.of(context).textTheme.bodySmall ??
                              const TextStyle(),
                        ),
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 4,
                  bottom: 4,
                  child: Material(
                    color: scheme.surface.withValues(alpha: .92),
                    borderRadius: BorderRadius.circular(12),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          key: const ValueKey('garden-zoom-out'),
                          tooltip: widget.zoomOutLabel,
                          onPressed: () => _zoom(.8),
                          icon: const Icon(Icons.remove, size: 18),
                        ),
                        IconButton(
                          key: const ValueKey('garden-zoom-in'),
                          tooltip: widget.zoomInLabel,
                          onPressed: () => _zoom(1.25),
                          icon: const Icon(Icons.add, size: 18),
                        ),
                        IconButton(
                          key: const ValueKey('garden-view-reset'),
                          tooltip: widget.resetViewLabel,
                          onPressed: () => _view.value = Matrix4.identity(),
                          icon: const Icon(Icons.fit_screen, size: 18),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
