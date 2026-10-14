part of 'garden_canvas.dart';

class _GardenPainter extends CustomPainter {
  _GardenPainter({
    required this.areas,
    required this.selectedId,
    required this.areaCaptions,
    required this.drawing,
    required this.scheme,
    required this.textDirection,
    required this.labelStyle,
    this.widthMeters,
    this.heightMeters,
  });
  final List<GardenArea> areas;
  final double? widthMeters, heightMeters;
  final String? selectedId;
  final Rect? drawing;
  final Map<String, String> areaCaptions;
  final ColorScheme scheme;
  final TextDirection textDirection;
  final TextStyle labelStyle;

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
              : area.kind == GardenAreaKind.bed
              ? scheme.surface
              : scheme.surfaceContainerHighest,
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
            text: [
              area.label,
              if (areaCaptions[area.id]?.isNotEmpty == true)
                areaCaptions[area.id]!,
            ].join('\n'),
            style: labelStyle.copyWith(
              fontSize: 12,
              color: selected ? scheme.onPrimaryContainer : scheme.onSurface,
            ),
          ),
          textDirection: textDirection,
          maxLines: 3,
          ellipsis: '…',
        )..layout(maxWidth: rect.width - 12);
        canvas.save();
        canvas.clipRect(rect.deflate(3));
        text.paint(canvas, rect.topLeft + const Offset(6, 5));
        canvas.restore();
      }
      if (selected) {
        for (final corner in [
          rect.topLeft,
          rect.topRight,
          rect.bottomLeft,
          rect.bottomRight,
        ]) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromCenter(center: corner, width: 12, height: 12),
              const Radius.circular(3),
            ),
            Paint()..color = scheme.primary,
          );
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromCenter(center: corner, width: 12, height: 12),
              const Radius.circular(3),
            ),
            Paint()
              ..color = scheme.surface
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5,
          );
        }
      }
    }
    _paintNearestGap(canvas, size);
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

  void _paintNearestGap(Canvas canvas, Size size) {
    if (widthMeters == null || heightMeters == null) return;
    final selected = areas.where((a) => a.id == selectedId).firstOrNull;
    if (selected == null) return;
    Offset? start, end;
    double? closest;
    for (final other in areas.where(
      (a) => a.id != selected.id && a.kind == GardenAreaKind.bed,
    )) {
      double point(double a, double aSize, double b, double bSize) =>
          a + aSize <= b
          ? a + aSize
          : a >= b + bSize
          ? a
          : (math.max(a, b) + math.min(a + aSize, b + bSize)) / 2;
      final a = Offset(
        point(selected.x, selected.width, other.x, other.width),
        point(selected.y, selected.height, other.y, other.height),
      );
      final b = Offset(
        point(other.x, other.width, selected.x, selected.width),
        point(other.y, other.height, selected.y, selected.height),
      );
      final distance = Offset(
        (a.dx - b.dx) * widthMeters!,
        (a.dy - b.dy) * heightMeters!,
      ).distance;
      if (distance > .0001 && (closest == null || distance < closest)) {
        closest = distance;
        start = a;
        end = b;
      }
    }
    if (start == null || end == null || closest == null) return;
    final a = Offset(start.dx * size.width, start.dy * size.height),
        b = Offset(end.dx * size.width, end.dy * size.height);
    canvas.drawLine(
      a,
      b,
      Paint()
        ..color = scheme.primary
        ..strokeWidth = 2,
    );
    for (final endpoint in [a, b]) {
      canvas.drawCircle(endpoint, 3, Paint()..color = scheme.primary);
    }
    final text = TextPainter(
      text: TextSpan(
        text: '≈ ${closest.toStringAsFixed(2)} m',
        style: labelStyle.copyWith(fontSize: 11, color: scheme.onSurface),
      ),
      textDirection: textDirection,
    )..layout(maxWidth: size.width - 12);
    final middle = (a + b) / 2;
    final rect = Rect.fromCenter(
      center: middle,
      width: text.width + 8,
      height: text.height + 4,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(4)),
      Paint()..color = scheme.surface,
    );
    text.paint(canvas, rect.topLeft + const Offset(4, 2));
  }

  @override
  bool shouldRepaint(covariant _GardenPainter oldDelegate) => true;
}
