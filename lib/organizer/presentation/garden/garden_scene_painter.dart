part of 'garden_scene_view.dart';

/// Code-native illustrations remain crisp at every zoom and need no new assets.
class GardenScenePainter extends CustomPainter {
  GardenScenePainter({
    required this.garden,
    required this.year,
    required this.today,
    required this.plot,
    required this.emptyLabel,
    required this.dark,
    required this.direction,
    required this.labelStyle,
  });
  final Garden garden;
  final int? year;
  final DateTime today;
  final Rect plot;
  final String emptyLabel;
  final bool dark;
  final TextDirection direction;
  final TextStyle labelStyle;

  @override
  void paint(Canvas canvas, Size size) {
    final grass = Paint()
      ..color = dark ? const Color(0xff385b3b) : const Color(0xff8bbd68);
    canvas.drawRRect(
      RRect.fromRectAndRadius(plot, const Radius.circular(18)),
      grass,
    );
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(plot, const Radius.circular(18)));
    // Deterministic patches and tufts; redrawing never makes the scenery jump.
    final random = math.Random(42);
    for (var i = 0; i < 85; i++) {
      final point = Offset(
        plot.left + random.nextDouble() * plot.width,
        plot.top + random.nextDouble() * plot.height,
      );
      canvas.drawOval(
        Rect.fromCenter(
          center: point,
          width: 18 + random.nextDouble() * 42,
          height: 9 + random.nextDouble() * 19,
        ),
        Paint()
          ..color =
              (i.isEven ? const Color(0xffb6d98c) : const Color(0xff598b49))
                  .withValues(alpha: dark ? .12 : .2),
      );
      if (i % 3 == 0) {
        final p = Paint()
          ..color = const Color(0xff4e8243).withValues(alpha: .35)
          ..strokeWidth = 1;
        canvas.drawLine(point, point + const Offset(-2, -4), p);
        canvas.drawLine(point, point + const Offset(3, -5), p);
      }
    }
    for (final area in garden.areas.where((a) => !a.archived)) {
      final rect = Rect.fromLTWH(
        plot.left + area.x * plot.width,
        plot.top + area.y * plot.height,
        area.width * plot.width,
        area.height * plot.height,
      );
      _bed(canvas, rect, area);
    }
    canvas.restore();
    canvas.drawRRect(
      RRect.fromRectAndRadius(plot.deflate(1), const Radius.circular(18)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xff487441).withValues(alpha: .5),
    );
  }

  void _bed(Canvas canvas, Rect rect, GardenArea area) {
    final radius = Radius.circular(math.min(12, rect.shortestSide / 6));
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.shift(const Offset(2, 4)), radius),
      Paint()..color = const Color(0xff1b361a).withValues(alpha: .24),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, radius),
      Paint()
        ..color = area.kind == GardenAreaKind.bed
            ? const Color(0xffb88750)
            : const Color(0xffbac699),
    );
    final soil = rect.deflate(math.min(6, rect.shortestSide / 12));
    canvas.drawRRect(
      RRect.fromRectAndRadius(soil, radius),
      Paint()
        ..color = area.kind == GardenAreaKind.bed
            ? const Color(0xff6c482f)
            : const Color(0xffa0b984),
    );
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(soil, radius));
    if (area.kind == GardenAreaKind.bed) {
      for (var y = soil.top + 10; y < soil.bottom; y += 14) {
        canvas.drawLine(
          Offset(soil.left, y),
          Offset(soil.right, y),
          Paint()
            ..color = const Color(0xff553924).withValues(alpha: .65)
            ..strokeWidth = 3,
        );
        canvas.drawLine(
          Offset(soil.left, y + 2),
          Offset(soil.right, y + 2),
          Paint()
            ..color = const Color(0xff9e6b45).withValues(alpha: .35)
            ..strokeWidth = 1,
        );
      }
    }
    final plantings = gardenVisiblePlantings(garden, year, area.id);
    for (var index = 0; index < plantings.length; index++) {
      final planting = plantings[index];
      final strip = Rect.fromLTWH(
        soil.left + index * soil.width / plantings.length,
        soil.top,
        soil.width / plantings.length,
        soil.height,
      );
      final available = strip.deflate(math.min(8, strip.shortestSide / 8));
      final columns = garden.hasPhysicalSize && planting.spacingCm != null
          ? (area.width *
                    garden.widthMeters! *
                    100 /
                    planting.spacingCm! /
                    plantings.length)
                .floor()
                .clamp(1, 12)
          : (available.width / 28).floor().clamp(1, 8);
      final rows = garden.hasPhysicalSize && planting.spacingCm != null
          ? (area.height * garden.heightMeters! * 100 / planting.spacingCm!)
                .floor()
                .clamp(1, 10)
          : (available.height / 32).floor().clamp(1, 8);
      final cellWidth = available.width / columns,
          cellHeight = available.height / rows;
      final radius = math.min(16.0, math.min(cellWidth, cellHeight) * .42);
      for (var row = 0; row < rows; row++) {
        for (var col = 0; col < columns; col++) {
          final center = Offset(
            available.left + cellWidth * (col + .5),
            available.top + cellHeight * (row + .5),
          );
          _plant(
            canvas,
            center,
            radius,
            planting,
            gardenVisualGrowth(planting, today),
          );
        }
      }
    }
    canvas.restore();
    // A light sign keeps names legible over any crop; tiny beds retain semantics.
    if (rect.width > 50 && rect.height > 38) {
      final label = [
        area.label,
        if (garden.hasPhysicalSize)
          gardenAreaSize(garden, area)
        else if (plantings.isEmpty)
          emptyLabel
        else
          plantings.map((p) => p.crop).join(' · '),
      ].join('\n');
      final text = TextPainter(
        text: TextSpan(
          text: label,
          style: labelStyle.copyWith(
            fontSize: 11,
            height: 1.2,
            fontWeight: FontWeight.w600,
            color: Color(0xff2b412b),
          ),
        ),
        textDirection: direction,
        maxLines: 2,
        ellipsis: '…',
      )..layout(maxWidth: math.max(1, rect.width - 18));
      final labelRect = Rect.fromLTWH(
        rect.left + 5,
        rect.top + 5,
        math.min(rect.width - 10, text.width + 10),
        text.height + 7,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(labelRect, const Radius.circular(5)),
        Paint()..color = const Color(0xfffaf8e9).withValues(alpha: .93),
      );
      text.paint(canvas, labelRect.topLeft + const Offset(5, 3));
    }
  }

  void _plant(
    Canvas c,
    Offset center,
    double radius,
    GardenPlanting planting,
    double growth,
  ) {
    if (radius < 1) return;
    c.save();
    c.translate(center.dx, center.dy);
    final r = radius * (.35 + .65 * growth);
    final shadow = Paint()
      ..color = const Color(0xff251d10).withValues(alpha: .3);
    c.drawOval(
      Rect.fromCenter(
        center: Offset(1, r * .45),
        width: r * 1.8,
        height: r * .8,
      ),
      shadow,
    );
    final leaf = Paint()
      ..color = planting.status == GardenPlantingStatus.planned
          ? const Color(0xffa6c27e)
          : const Color(0xff4a9f42);
    final light = Paint()..color = const Color(0xff93cf60);
    final stem = Paint()
      ..color = const Color(0xff2b6835)
      ..strokeWidth = math.max(1, r * .12)
      ..strokeCap = StrokeCap.round;
    void ellipse(double x, double y, double w, double h, Paint paint) =>
        c.drawOval(
          Rect.fromCenter(
            center: Offset(x * r, y * r),
            width: w * r,
            height: h * r,
          ),
          paint,
        );
    void sprig() {
      c.drawLine(Offset(0, r * .65), Offset(0, -r * .6), stem);
      ellipse(-.35, -.2, .85, .46, leaf);
      ellipse(.35, -.45, .85, .46, light);
    }

    final kind = planting.illustration;
    if (growth < .3 || kind == GardenCropIllustration.generic) {
      sprig();
    } else if (kind == GardenCropIllustration.lettuce ||
        kind == GardenCropIllustration.cabbage) {
      for (var j = 0; j < 6; j++) {
        c.save();
        c.rotate(j * math.pi / 3);
        ellipse(0, -.35, 1.02, 1.25, j.isEven ? leaf : light);
        c.restore();
      }
      ellipse(
        0,
        0,
        .9,
        .85,
        Paint()
          ..color = kind == GardenCropIllustration.cabbage
              ? const Color(0xffbada8e)
              : const Color(0xffc3e47a),
      );
      c.drawArc(
        Rect.fromCircle(center: Offset.zero, radius: r * .26),
        -.8,
        3.5,
        false,
        stem
          ..strokeWidth = 1
          ..style = PaintingStyle.stroke,
      );
    } else if (kind == GardenCropIllustration.carrot) {
      final root = Path()
        ..moveTo(-r * .36, -r * .05)
        ..quadraticBezierTo(-r * .4, r * .25, 0, r * .95)
        ..quadraticBezierTo(r * .45, r * .1, r * .32, -r * .08)
        ..close();
      c.drawPath(root, Paint()..color = const Color(0xffffa030));
      for (var j = -1; j <= 1; j++) {
        c.drawLine(Offset(0, -r * .03), Offset(j * r * .45, -r * .85), stem);
      }
      ellipse(-.4, -.6, .45, .65, leaf);
      ellipse(.4, -.6, .45, .65, light);
    } else if (kind == GardenCropIllustration.onion) {
      ellipse(0, .35, 1.15, 1.15, Paint()..color = const Color(0xffe6bb79));
      for (var j = -1; j <= 1; j++) {
        c.drawLine(Offset(j * r * .12, 0), Offset(j * r * .32, -r), stem);
      }
      c.drawLine(
        Offset(-r * .1, r * .4),
        Offset(-r * .15, r * .75),
        Paint()
          ..color = const Color(0xfff9dfb5)
          ..strokeWidth = 2,
      );
    } else if (kind == GardenCropIllustration.pumpkin) {
      sprig();
      for (var j = -1; j <= 1; j++) {
        ellipse(
          j * .34,
          .2,
          .82,
          1.22,
          Paint()
            ..color = j.isEven
                ? const Color(0xffffb134)
                : const Color(0xffed8429),
        );
      }
      c.drawLine(Offset(0, -r * .38), Offset(r * .2, -r * .65), stem);
    } else if (kind == GardenCropIllustration.bean) {
      sprig();
      for (var j = 0; j < 2; j++) {
        c.drawArc(
          Rect.fromLTWH((-.6 + j * .6) * r, -.2 * r, .6 * r, r),
          -.8,
          2.1,
          false,
          Paint()
            ..color = const Color(0xffb3d85b)
            ..strokeWidth = r * .23
            ..strokeCap = StrokeCap.round
            ..style = PaintingStyle.stroke,
        );
      }
    } else {
      sprig();
      ellipse(-.35, .2, 1.1, 1.25, leaf);
      ellipse(.35, -.05, 1.1, 1.25, light);
      if (growth > .55) {
        final fruit = Paint()
          ..color = kind == GardenCropIllustration.pepper
              ? const Color(0xffffcd45)
              : const Color(0xffed5946);
        ellipse(
          -.38,
          .2,
          .7,
          kind == GardenCropIllustration.pepper ? 1.05 : .7,
          fruit,
        );
        ellipse(
          .4,
          -.1,
          .7,
          kind == GardenCropIllustration.pepper ? 1.05 : .7,
          fruit,
        );
        ellipse(-.48, .08, .18, .17, Paint()..color = const Color(0xffffdca0));
      }
    }
    c.restore();
  }

  @override
  bool shouldRepaint(covariant GardenScenePainter old) =>
      garden != old.garden ||
      year != old.year ||
      gardenDay(today) != gardenDay(old.today) ||
      plot != old.plot ||
      dark != old.dark ||
      emptyLabel != old.emptyLabel;
}
