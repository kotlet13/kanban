import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../l10n/l10n.dart';
import '../../domain/idea_models.dart';
import '../../data/collaboration_repository.dart' show newSharedId;

enum IdeaTool {
  select,
  pan,
  pen,
  highlighter,
  eraser,
  line,
  arrow,
  rectangle,
  ellipse,
}

/// Board coordinates never depend on the viewport. Image children use unit
/// coordinates in the image's unrotated frame, so marks follow every transform.
Offset ideaElementLocal(
  IdeaElement element,
  Offset boardPoint,
  List<IdeaElement> elements,
) {
  var point = boardPoint;
  if (element.parentImageId != null) {
    final parent = elements
        .where((e) => e.id == element.parentImageId)
        .firstOrNull;
    if (parent != null) {
      point = ideaElementLocal(parent, boardPoint, elements);
      point = Offset(point.dx / parent.width, point.dy / parent.height);
    }
  }
  final delta =
      point -
      Offset(element.x + element.width / 2, element.y + element.height / 2);
  final c = math.cos(element.rotation), s = math.sin(element.rotation);
  return Offset(
    delta.dx * c + delta.dy * s + element.width / 2,
    -delta.dx * s + delta.dy * c + element.height / 2,
  );
}

IdeaElement? ideaHitTest(
  List<IdeaElement> elements,
  Offset point, {
  bool imagesOnly = false,
}) {
  for (final element in elements.reversed) {
    if (imagesOnly && element.kind != IdeaElementKind.image) continue;
    final p = ideaElementLocal(element, point, elements);
    final pad = element.parentImageId == null ? 10.0 : .012;
    if (Rect.fromLTWH(
      -pad,
      -pad,
      element.width + 2 * pad,
      element.height + 2 * pad,
    ).contains(p)) {
      return element;
    }
  }
  return null;
}

class IdeaCanvas extends StatefulWidget {
  const IdeaCanvas({
    super.key,
    required this.board,
    required this.onChanged,
    required this.tool,
    required this.images,
    required this.editable,
    this.selectedId,
    required this.onSelected,
    this.color = 0xff263238,
    this.strokeWidth = 3,
    this.onEditText,
  });
  final IdeaBoard board;
  final ValueChanged<IdeaBoard> onChanged;
  final IdeaTool tool;
  final Map<String, ui.Image> images;
  final bool editable;
  final String? selectedId;
  final ValueChanged<String?> onSelected;
  final int color;
  final double strokeWidth;
  final ValueChanged<IdeaElement>? onEditText;
  @override
  State<IdeaCanvas> createState() => _IdeaCanvasState();
}

class _IdeaCanvasState extends State<IdeaCanvas> {
  final TransformationController _transform = TransformationController();
  IdeaElement? _working;
  Offset? _start;
  IdeaElement? _original;
  bool _resize = false;
  final List<IdeaPoint> _points = [];
  bool _fitted = false;
  @override
  void didUpdateWidget(covariant IdeaCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tool != widget.tool ||
        oldWidget.editable != widget.editable ||
        oldWidget.board.id != widget.board.id) {
      _clearGesture();
    }
  }

  void _clearGesture() {
    _start = null;
    _working = null;
    _original = null;
    _resize = false;
    _points.clear();
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  Offset _inside(Offset p) => Offset(
    p.dx.clamp(0, widget.board.width),
    p.dy.clamp(0, widget.board.height),
  );
  Offset _imagePoint(IdeaElement parent, Offset point) {
    final local = ideaElementLocal(parent, point, widget.board.elements);
    return Offset(local.dx / parent.width, local.dy / parent.height);
  }

  void _begin(DragStartDetails details) {
    if (!widget.editable || widget.tool == IdeaTool.pan) return;
    final point = _inside(details.localPosition);
    _start = point;
    _points.clear();
    if (widget.tool == IdeaTool.select || widget.tool == IdeaTool.eraser) {
      final selected = widget.board.elements
          .where(
            (e) => e.id == widget.selectedId && e.kind == IdeaElementKind.image,
          )
          .firstOrNull;
      final selectedPoint = selected == null
          ? null
          : ideaElementLocal(selected, point, widget.board.elements);
      final hit =
          widget.tool == IdeaTool.select &&
              selected != null &&
              (Offset.zero & Size(selected.width, selected.height)).contains(
                selectedPoint!,
              )
          ? selected
          : ideaHitTest(widget.board.elements, point);
      if (widget.tool == IdeaTool.eraser) {
        if (hit != null && hit.kind != IdeaElementKind.image) _remove(hit.id);
        return;
      }
      widget.onSelected(hit?.id);
      _original = hit;
      _working = hit;
      if (hit != null) {
        final local = ideaElementLocal(hit, point, widget.board.elements);
        final radius = hit.parentImageId == null ? 24.0 : .04;
        _resize = (local - Offset(hit.width, hit.height)).distance < radius;
      }
    } else {
      final parent = ideaHitTest(
        widget.board.elements,
        point,
        imagesOnly: true,
      );
      final origin = parent == null ? point : _imagePoint(parent, point);
      final unit = parent?.width ?? 1.0;
      final kind = switch (widget.tool) {
        IdeaTool.line => IdeaElementKind.line,
        IdeaTool.arrow => IdeaElementKind.arrow,
        IdeaTool.rectangle => IdeaElementKind.rectangle,
        IdeaTool.ellipse => IdeaElementKind.ellipse,
        _ => IdeaElementKind.stroke,
      };
      _working = IdeaElement(
        id: newSharedId(),
        kind: kind,
        x: origin.dx,
        y: origin.dy,
        width: parent == null ? 1 : .001,
        height: parent == null ? 1 : .001,
        color: widget.tool == IdeaTool.highlighter
            ? (widget.color & 0x00ffffff) | 0x66000000
            : widget.color,
        strokeWidth:
            (widget.tool == IdeaTool.highlighter
                ? widget.strokeWidth * 5
                : widget.strokeWidth) /
            unit,
        parentImageId: parent?.id,
        points: [const IdeaPoint(0, 0)],
      );
      _original = _working;
      _points.add(const IdeaPoint(0, 0));
    }
    setState(() {});
  }

  void _update(DragUpdateDetails details) {
    if (_start == null || !widget.editable) return;
    final point = _inside(details.localPosition);
    if (widget.tool == IdeaTool.eraser) {
      final hit = ideaHitTest(widget.board.elements, point);
      if (hit != null && hit.kind != IdeaElementKind.image) _remove(hit.id);
      return;
    }
    final original = _original;
    if (original == null) return;
    final parent = widget.board.elements
        .where((e) => e.id == original.parentImageId)
        .firstOrNull;
    final delta = parent == null
        ? point - _start!
        : _imagePoint(parent, point) - _imagePoint(parent, _start!);
    if (widget.tool == IdeaTool.select) {
      if (_resize) {
        final local = ideaElementLocal(original, point, widget.board.elements);
        final minimum = parent == null ? 20.0 : .02;
        _working = original.copyWith(
          width: local.dx.clamp(
            minimum,
            parent == null ? widget.board.width : 2.0,
          ),
          height: local.dy.clamp(
            minimum,
            parent == null ? widget.board.height : 2.0,
          ),
        );
      } else {
        _working = original.copyWith(
          x: (original.x + delta.dx).clamp(
            parent == null ? 0 : -1,
            parent == null
                ? math.max(0, widget.board.width - original.width)
                : 2,
          ),
          y: (original.y + delta.dy).clamp(
            parent == null ? 0 : -1,
            parent == null
                ? math.max(0, widget.board.height - original.height)
                : 2,
          ),
        );
      }
    } else {
      _points.add(IdeaPoint(delta.dx, delta.dy));
      if (_points.length > 3000) {
        final last = _points.last;
        _points.removeLast();
        for (var i = _points.length - 2; i > 0; i -= 2) {
          _points.removeAt(i);
        }
        _points.add(last);
      }
      final xs = _points.map((p) => p.x), ys = _points.map((p) => p.y);
      final minX = xs.reduce(math.min),
          minY = ys.reduce(math.min),
          maxX = xs.reduce(math.max),
          maxY = ys.reduce(math.max);
      final minimum = parent == null ? 1.0 : .001;
      _working = original.copyWith(
        x: original.x + minX,
        y: original.y + minY,
        width: math.max(minimum, maxX - minX),
        height: math.max(minimum, maxY - minY),
        points:
            (original.kind == IdeaElementKind.stroke
                    ? _points
                    : [const IdeaPoint(0, 0), IdeaPoint(delta.dx, delta.dy)])
                .map((p) => IdeaPoint(p.x - minX, p.y - minY))
                .toList(),
      );
    }
    setState(() {});
  }

  void _end(DragEndDetails details) {
    final working = _working;
    if (working != null) {
      final elements = [...widget.board.elements];
      final index = elements.indexWhere((e) => e.id == working.id);
      if (index < 0) {
        elements.add(working);
      } else {
        elements[index] = working;
      }
      widget.onChanged(widget.board.copyWith(elements: elements));
      widget.onSelected(working.id);
    }
    setState(() {
      _start = null;
      _working = null;
      _original = null;
    });
  }

  void _remove(String id) => widget.onChanged(
    widget.board.copyWith(
      elements: widget.board.elements
          .where((e) => e.id != id && e.parentImageId != id)
          .toList(),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final editingGesture = widget.editable && widget.tool != IdeaTool.pan;
    final elements = [...widget.board.elements];
    if (_working != null) {
      elements.removeWhere((e) => e.id == _working!.id);
      elements.add(_working!);
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!_fitted &&
            constraints.maxWidth.isFinite &&
            constraints.maxHeight.isFinite) {
          _fitted = true;
          final scale = math.min(
            constraints.maxWidth / widget.board.width,
            constraints.maxHeight / widget.board.height,
          );
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _transform.value = Matrix4.identity()
                ..scaleByDouble(scale, scale, 1, 1);
            }
          });
        }
        return ClipRect(
          child: Stack(
            children: [
              Positioned.fill(
                child: InteractiveViewer(
                  key: const ValueKey('idea-viewport'),
                  transformationController: _transform,
                  constrained: false,
                  boundaryMargin: const EdgeInsets.all(160),
                  minScale: .005,
                  maxScale: 5,
                  panEnabled: !widget.editable || widget.tool == IdeaTool.pan,
                  scaleEnabled: !widget.editable || widget.tool == IdeaTool.pan,
                  child: Semantics(
                    label: context.l10n.ideasCanvasLabel,
                    child: GestureDetector(
                      key: const ValueKey('idea-canvas'),
                      dragStartBehavior: DragStartBehavior.down,
                      behavior: HitTestBehavior.opaque,
                      onPanStart: editingGesture ? _begin : null,
                      onPanUpdate: editingGesture ? _update : null,
                      // Even a lone onPanCancel creates a child pan recognizer.
                      // Remove every edit pan callback in viewport mode so the
                      // InteractiveViewer owns both one- and two-finger gestures.
                      onPanCancel: editingGesture
                          ? () => setState(_clearGesture)
                          : null,
                      onPanEnd: editingGesture ? _end : null,
                      onTapUp: widget.tool == IdeaTool.select
                          ? (d) => widget.onSelected(
                              ideaHitTest(elements, d.localPosition)?.id,
                            )
                          : null,
                      onDoubleTapDown:
                          widget.tool == IdeaTool.select && widget.editable
                          ? (d) {
                              final hit = ideaHitTest(
                                elements,
                                d.localPosition,
                              );
                              if (hit != null &&
                                  [
                                    IdeaElementKind.text,
                                    IdeaElementKind.sticky,
                                  ].contains(hit.kind)) {
                                widget.onEditText?.call(hit);
                              }
                            }
                          : null,
                      child: CustomPaint(
                        size: Size(widget.board.width, widget.board.height),
                        painter: IdeaBoardPainter(
                          elements: elements,
                          images: widget.images,
                          selectedId: widget.selectedId,
                          surface: Theme.of(context).colorScheme.surface,
                          missingLabel: context.l10n.ideasMissingPhoto,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 8,
                bottom: 8,
                child: IconButton.filledTonal(
                  tooltip: context.l10n.ideasResetView,
                  onPressed: () {
                    final size = context.size;
                    final scale = size == null
                        ? .4
                        : math.min(
                            size.width / widget.board.width,
                            size.height / widget.board.height,
                          );
                    _transform.value = Matrix4.identity()
                      ..scaleByDouble(scale, scale, 1, 1);
                  },
                  icon: const Icon(Icons.fit_screen),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class IdeaBoardPainter extends CustomPainter {
  IdeaBoardPainter({
    required this.elements,
    required this.images,
    this.selectedId,
    this.surface = Colors.white,
    this.missingLabel = '',
  });
  final List<IdeaElement> elements;
  final Map<String, ui.Image> images;
  final String? selectedId;
  final Color surface;
  final String missingLabel;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = surface);
    final grid = Paint()..color = Color.lerp(surface, Colors.grey, .14)!;
    for (double x = 0; x < size.width; x += 40) {
      for (double y = 0; y < size.height; y += 40) {
        canvas.drawCircle(Offset(x, y), 1, grid);
      }
    }
    for (final element in elements.where((e) => e.parentImageId == null)) {
      _paintElement(canvas, element, false);
      if (element.kind == IdeaElementKind.image) {
        canvas.save();
        _transformElement(canvas, element);
        canvas.scale(element.width, element.height);
        for (final child in elements.where(
          (e) => e.parentImageId == element.id,
        )) {
          _paintElement(canvas, child, true);
        }
        canvas.restore();
      }
    }
  }

  void _transformElement(Canvas canvas, IdeaElement e) {
    canvas.translate(e.x + e.width / 2, e.y + e.height / 2);
    canvas.rotate(e.rotation);
    canvas.translate(-e.width / 2, -e.height / 2);
  }

  void _paintElement(Canvas canvas, IdeaElement e, bool child) {
    canvas.save();
    _transformElement(canvas, e);
    final rect = Rect.fromLTWH(0, 0, e.width, e.height);
    final paint = Paint()
      ..color = Color(e.color)
      ..strokeWidth = e.strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    switch (e.kind) {
      case IdeaElementKind.image:
        final image = images[e.asset?.sha256];
        if (image == null) {
          canvas.drawRect(rect, Paint()..color = const Color(0xffe2e7ee));
          _text(
            canvas,
            missingLabel,
            e.width - 16,
            const Color(0xff263238),
            16,
            const Offset(8, 8),
          );
        } else {
          canvas.drawImageRect(
            image,
            Rect.fromLTWH(
              0,
              0,
              image.width.toDouble(),
              image.height.toDouble(),
            ),
            rect,
            Paint()..filterQuality = FilterQuality.medium,
          );
        }
      case IdeaElementKind.text:
      case IdeaElementKind.sticky:
        if (e.kind == IdeaElementKind.sticky) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(rect, Radius.circular(child ? .015 : 8)),
            Paint()..color = Color(e.color),
          );
        }
        final padding = child ? .015 : 10.0;
        canvas.save();
        canvas.clipRect(rect);
        _text(
          canvas,
          e.text,
          math.max(.01, e.width - padding * 2),
          e.kind == IdeaElementKind.sticky
              ? const Color(0xff17212e)
              : Color(e.color),
          child ? .065 : 22,
          Offset(padding, padding),
        );
        canvas.restore();
      case IdeaElementKind.stroke:
        final path = Path();
        for (var i = 0; i < e.points.length; i++) {
          final p = e.points[i];
          if (i == 0) {
            path.moveTo(p.x, p.y);
          } else {
            path.lineTo(p.x, p.y);
          }
        }
        if (e.points.length == 1) {
          canvas.drawCircle(
            Offset(e.points.first.x, e.points.first.y),
            e.strokeWidth / 2,
            paint..style = PaintingStyle.fill,
          );
        }
        canvas.drawPath(path, paint);
      case IdeaElementKind.rectangle:
        canvas.drawRect(rect, paint);
      case IdeaElementKind.ellipse:
        canvas.drawOval(rect, paint);
      case IdeaElementKind.line:
      case IdeaElementKind.arrow:
        final start = e.points.isEmpty
            ? Offset.zero
            : Offset(e.points.first.x, e.points.first.y);
        final end = e.points.isEmpty
            ? Offset(e.width, e.height)
            : Offset(e.points.last.x, e.points.last.y);
        canvas.drawLine(start, end, paint);
        if (e.kind == IdeaElementKind.arrow) {
          final angle = math.atan2(end.dy - start.dy, end.dx - start.dx),
              length = e.strokeWidth * 5;
          canvas.drawLine(
            end,
            end - Offset(math.cos(angle - .5), math.sin(angle - .5)) * length,
            paint,
          );
          canvas.drawLine(
            end,
            end - Offset(math.cos(angle + .5), math.sin(angle + .5)) * length,
            paint,
          );
        }
    }
    if (e.id == selectedId) {
      final selection = Paint()
        ..color = const Color(0xff2969cc)
        ..style = PaintingStyle.stroke
        ..strokeWidth = child ? .006 : 2;
      canvas.drawRect(rect.inflate(child ? .008 : 3), selection);
      canvas.drawCircle(
        Offset(e.width, e.height),
        child ? .025 : 10,
        Paint()..color = const Color(0xff2969cc),
      );
    }
    canvas.restore();
  }

  void _text(
    Canvas canvas,
    String text,
    double width,
    Color color,
    double fontSize,
    Offset offset,
  ) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontFamily: 'Roboto',
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: width);
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant IdeaBoardPainter oldDelegate) => true;
}
