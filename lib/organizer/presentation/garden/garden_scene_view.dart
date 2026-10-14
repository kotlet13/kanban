import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../l10n/l10n.dart';
import '../../domain/garden_models.dart';
import '../../domain/garden_scene.dart';

part 'garden_scene_painter.dart';

/// The viewing scene never installs drag recognizers that compete with pinch.
/// Buttons/keyboard provide an alternative to every viewing gesture.
class GardenSceneView extends StatefulWidget {
  const GardenSceneView({
    super.key,
    required this.garden,
    required this.year,
    required this.onBed,
    this.today,
  });
  final Garden garden;
  final int? year;
  final ValueChanged<GardenArea> onBed;
  final DateTime? today;
  @override
  State<GardenSceneView> createState() => _GardenSceneViewState();
}

class _GardenSceneViewState extends State<GardenSceneView> {
  final _transform = TransformationController();
  Size _viewport = Size.zero;
  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  void _zoom(double factor) {
    final current = _transform.value.getMaxScaleOnAxis();
    final scale = (current * factor).clamp(1.0, 5.0);
    if (scale == 1) {
      _transform.value = Matrix4.identity();
      return;
    }
    final ratio = scale / current;
    final translation = _transform.value.getTranslation();
    final center = Offset(_viewport.width / 2, _viewport.height / 2);
    _transform.value = Matrix4.identity()
      ..translateByDouble(
        center.dx - (center.dx - translation.x) * ratio,
        center.dy - (center.dy - translation.y) * ratio,
        0,
        1,
      )
      ..scaleByDouble(scale, scale, scale, 1);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final areas = widget.garden.areas.where((a) => !a.archived).toList();
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.equal, control: true):
            _SceneZoomIntent(1.25),
        SingleActivator(LogicalKeyboardKey.equal, meta: true): _SceneZoomIntent(
          1.25,
        ),
        SingleActivator(LogicalKeyboardKey.minus, control: true):
            _SceneZoomIntent(.8),
        SingleActivator(LogicalKeyboardKey.minus, meta: true): _SceneZoomIntent(
          .8,
        ),
      },
      child: Actions(
        actions: {
          _SceneZoomIntent: CallbackAction<_SceneZoomIntent>(
            onInvoke: (i) {
              _zoom(i.factor);
              return null;
            },
          ),
        },
        child: Focus(
          skipTraversal: true,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final viewport = constraints.biggest;
              _viewport = viewport;
              final ratio = widget.garden.hasPhysicalSize
                  ? widget.garden.widthMeters! / widget.garden.heightMeters!
                  : 4 / 3;
              // Retain the physical aspect ratio without changing normalized data.
              final maxWidth = math.max(280.0, viewport.width - 40);
              final maxHeight = math.max(220.0, viewport.height - 48);
              final width = math.min(maxWidth, maxHeight * ratio);
              final height = width / ratio;
              final plot = Rect.fromCenter(
                center: Offset(viewport.width / 2, viewport.height / 2),
                width: width,
                height: height,
              );
              return Stack(
                children: [
                  Positioned.fill(
                    child: ColoredBox(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? const Color(0xff203c2c)
                          : const Color(0xffdcecc0),
                    ),
                  ),
                  Positioned.fill(
                    child: InteractiveViewer(
                      key: const ValueKey('garden-scene-viewer'),
                      transformationController: _transform,
                      minScale: 1,
                      maxScale: 5,
                      child: CustomPaint(
                        key: const ValueKey('garden-scene-paint'),
                        painter: GardenScenePainter(
                          garden: widget.garden,
                          year: widget.year,
                          today: widget.today ?? DateTime.now(),
                          plot: plot,
                          emptyLabel: l.gardenEmptyBed,
                          labelStyle:
                              Theme.of(context).textTheme.bodySmall ??
                              const TextStyle(),
                          dark: Theme.of(context).brightness == Brightness.dark,
                          direction: Directionality.of(context),
                        ),
                        child: Stack(
                          children: [
                            for (final area in areas)
                              Positioned.fromRect(
                                rect: Rect.fromLTWH(
                                  plot.left + area.x * plot.width,
                                  plot.top + area.y * plot.height,
                                  area.width * plot.width,
                                  area.height * plot.height,
                                ),
                                child: Semantics(
                                  button: true,
                                  label:
                                      '${area.label}, ${gardenVisiblePlantings(widget.garden, widget.year, area.id).map((p) => p.crop).join(', ')}',
                                  child: Tooltip(
                                    message: area.label,
                                    child: Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        key: ValueKey(
                                          'garden-scene-bed-${area.id}',
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                        onTap: () => widget.onBed(area),
                                        child: const SizedBox.expand(),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 12,
                    bottom: 12,
                    child: Material(
                      elevation: 3,
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(24),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            key: const ValueKey('garden-scene-zoom-out'),
                            tooltip: l.gardenZoomOut,
                            onPressed: () => _zoom(.8),
                            icon: const Icon(Icons.remove),
                          ),
                          IconButton(
                            key: const ValueKey('garden-scene-zoom-in'),
                            tooltip: l.gardenZoomIn,
                            onPressed: () => _zoom(1.25),
                            icon: const Icon(Icons.add),
                          ),
                          IconButton(
                            tooltip: l.gardenResetView,
                            onPressed: () =>
                                _transform.value = Matrix4.identity(),
                            icon: const Icon(Icons.fit_screen),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _SceneZoomIntent extends Intent {
  const _SceneZoomIntent(this.factor);
  final double factor;
}

String gardenMeters(double value) => value
    .toStringAsFixed(value >= 10 ? 1 : 2)
    .replaceFirst(RegExp(r'\.?0+$'), '');
String gardenAreaSize(Garden garden, GardenArea area) =>
    '≈ ${gardenMeters(area.width * garden.widthMeters!)} × ${gardenMeters(area.height * garden.heightMeters!)} m';
