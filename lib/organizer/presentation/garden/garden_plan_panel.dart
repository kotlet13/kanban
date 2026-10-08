import 'package:flutter/material.dart';
import '../../../l10n/l10n.dart';
import '../../domain/garden_models.dart';
import 'garden_canvas.dart';

class GardenPlanPanel extends StatelessWidget {
  const GardenPlanPanel({
    super.key,
    required this.garden,
    required this.year,
    required this.selectedId,
    required this.tool,
    required this.onTool,
    required this.onSelect,
    required this.onDraw,
    required this.onMove,
    required this.onEdit,
    required this.onRemove,
    this.onUndo,
  });
  final Garden garden;
  final int? year;
  final String? selectedId;
  final GardenTool tool;
  final ValueChanged<GardenTool> onTool;
  final ValueChanged<String?> onSelect;
  final ValueChanged<Rect> onDraw;
  final ValueChanged<GardenArea> onMove, onEdit, onRemove;
  final VoidCallback? onUndo;
  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final selected = garden.areas
        .where((area) => area.id == selectedId)
        .firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l.gardenLayout, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              key: const ValueKey('garden-tool-select'),
              avatar: const Icon(Icons.open_with, size: 18),
              selected: tool == GardenTool.select,
              label: Text(l.gardenSelectTool),
              onSelected: (_) => onTool(GardenTool.select),
            ),
            ChoiceChip(
              key: const ValueKey('garden-tool-draw'),
              avatar: const Icon(Icons.crop_square, size: 18),
              selected: tool == GardenTool.draw,
              label: Text(l.gardenDrawTool),
              onSelected: garden.areas.length >= 1000
                  ? null
                  : (_) => onTool(GardenTool.draw),
            ),
            ChoiceChip(
              key: const ValueKey('garden-tool-pan'),
              avatar: const Icon(Icons.zoom_in, size: 18),
              selected: tool == GardenTool.pan,
              label: Text(l.gardenPanTool),
              onSelected: (_) => onTool(GardenTool.pan),
            ),
            IconButton(
              tooltip: l.gardenUndo,
              onPressed: onUndo,
              icon: const Icon(Icons.undo),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          tool == GardenTool.draw
              ? l.gardenDrawHelp
              : tool == GardenTool.pan
              ? l.gardenPanHelp
              : l.gardenSelectHelp,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        GardenCanvas(
          areas: garden.areas.where((a) => !a.archived).toList(),
          areaCaptions: {
            for (final a in garden.areas)
              a.id:
                  (garden.seasonForYear(year ?? 0)?.plantingsForArea(a.id) ??
                          <GardenPlanting>[])
                      .map((p) => p.crop)
                      .join(', '),
          },
          zoomInLabel: l.gardenZoomIn,
          zoomOutLabel: l.gardenZoomOut,
          resetViewLabel: l.gardenResetView,
          tool: tool,
          selectedId: selectedId,
          onSelect: onSelect,
          onDraw: onDraw,
          onMove: onMove,
          semanticLabel: l.gardenCanvasDescription,
        ),
        if (selected != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              children: [
                Text(selected.label),
                TextButton.icon(
                  onPressed: () => onEdit(selected),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: Text(l.edit),
                ),
                TextButton.icon(
                  onPressed: () => onRemove(selected),
                  icon: Icon(
                    selected.archived
                        ? Icons.unarchive_outlined
                        : Icons.archive_outlined,
                    size: 18,
                  ),
                  label: Text(
                    selected.archived
                        ? l.gardenRestoreArea
                        : garden.seasons.any(
                            (s) =>
                                s.plantings.any((p) => p.areaId == selected.id),
                          )
                        ? l.gardenArchiveArea
                        : l.delete,
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 16),
        Text(
          l.gardenSharedGeometry,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        Text(
          l.gardenSketchDisclaimer,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
