import 'package:flutter/material.dart';
import '../../../l10n/l10n.dart';
import '../../domain/garden_models.dart';
import '../../domain/garden_rotation.dart';
import 'garden_family_labels.dart';
import 'garden_calendar_date.dart';
import 'garden_scene_view.dart';
import '../../domain/garden_scene.dart';

class GardenBedDetail extends StatelessWidget {
  const GardenBedDetail({
    super.key,
    required this.garden,
    required this.area,
    required this.year,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
    required this.onNotes,
    this.onHarvest,
    this.readOnly = false,
  });
  final Garden garden;
  final bool readOnly;
  final ValueChanged<GardenPlanting>? onHarvest;
  final GardenArea? area;
  final int? year;
  final VoidCallback onAdd;
  final ValueChanged<GardenPlanting> onEdit, onDelete;
  final ValueChanged<String> onNotes;
  String _date(BuildContext context, DateTime value) =>
      gardenCalendarDate(context, value);
  Widget _planting(
    BuildContext context,
    GardenPlanting p, {
    bool history = false,
  }) {
    final l = context.l10n;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 4, right: 10),
                child: Icon(
                  p.status == GardenPlantingStatus.actual
                      ? Icons.grass_outlined
                      : Icons.spa_outlined,
                  size: 22,
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.crop,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (p.variety.isNotEmpty) Text(p.variety),
                    Text(
                      [
                        if (p.family.isNotEmpty)
                          gardenFamilyLabel(context, p.family),
                        p.status == GardenPlantingStatus.actual
                            ? l.gardenPlantingActual
                            : l.gardenPlantingPlanned,
                      ].join(' · '),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (!history && !readOnly && area?.archived != true)
                IconButton(
                  tooltip: l.gardenEditPlanting,
                  onPressed: () => onEdit(p),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                ),
              if (!history && !readOnly)
                IconButton(
                  tooltip: l.delete,
                  onPressed: () => onDelete(p),
                  icon: const Icon(Icons.delete_outline, size: 18),
                ),
            ],
          ),
          if (p.spacingCm != null)
            Text('${l.gardenPlantSpacing}: ${gardenMeters(p.spacingCm!)} cm'),
          if (p.harvested)
            Text(
              l.gardenHarvested,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          if (!history &&
              !readOnly &&
              onHarvest != null &&
              area?.archived != true)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: ValueKey('garden-harvest-${p.id}'),
                onPressed: () => onHarvest!(p),
                icon: Icon(
                  p.harvested ? Icons.undo : Icons.check_circle_outline,
                ),
                label: Text(
                  p.harvested ? l.gardenHarvestUndo : l.gardenHarvestAction,
                ),
              ),
            ),
          if (p.sowAt != null)
            Text('${l.gardenSowDate}: ${_date(context, p.sowAt!)}'),
          if (p.plantAt != null)
            Text('${l.gardenPlantDate}: ${_date(context, p.plantAt!)}'),
          if (p.harvestAt != null)
            Text('${l.gardenHarvestDate}: ${_date(context, p.harvestAt!)}'),
          if (p.notes.isNotEmpty) Text(p.notes),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final selected = area;
    if (selected == null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(l.gardenSelectBed),
      );
    }
    final season = year == null ? null : garden.seasonForYear(year!);
    final plantings =
        season?.plantingsForArea(selected.id) ?? <GardenPlanting>[];
    final history = gardenAreaHistory(
      garden,
      selected.id,
    ).where((s) => s.year != year).toList();
    final warnings = year == null
        ? <GardenRotationWarning>[]
        : gardenRotationWarnings(
            garden,
            year!,
          ).where((w) => w.areaId == selected.id).toList();
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(selected.label, style: Theme.of(context).textTheme.titleLarge),
            if (garden.hasPhysicalSize) ...[
              const SizedBox(height: 8),
              Text(
                '${l.gardenApproximateSize}: ${gardenAreaSize(garden, selected)}',
              ),
              if (garden.areas
                  .where(
                    (a) =>
                        !a.archived &&
                        a.id != selected.id &&
                        a.kind == GardenAreaKind.bed,
                  )
                  .isNotEmpty)
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text(l.gardenBedSpacing),
                  children: [
                    for (final other in garden.areas.where(
                      (a) =>
                          !a.archived &&
                          a.id != selected.id &&
                          a.kind == GardenAreaKind.bed,
                    ))
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(other.label),
                        trailing: Text(
                          '≈ ${gardenMeters(gardenBedGapMeters(garden, selected, other)!)} m',
                        ),
                      ),
                  ],
                ),
            ],
            if (selected.archived)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(l.gardenArchivedArea),
              ),
            const SizedBox(height: 16),
            Text(
              '${l.gardenSeasonPlantings}${year == null ? '' : ' · $year'}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            if (season == null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(l.gardenNoSeasons),
              )
            else ...[
              if (plantings.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(l.gardenNoPlantings),
                ),
              for (final p in plantings) _planting(context, p),
              if (!readOnly &&
                  !selected.archived &&
                  selected.kind == GardenAreaKind.bed)
                OutlinedButton.icon(
                  key: ValueKey('garden-add-planting-${selected.id}'),
                  onPressed: onAdd,
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(l.gardenAddPlanting),
                ),
            ],
            if (selected.kind == GardenAreaKind.bed) ...[
              const SizedBox(height: 16),
              for (final warning in warnings)
                Container(
                  key: ValueKey('garden-rotation-${warning.plantingId}'),
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.info_outline, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          l.gardenRotationRepeated(
                            gardenFamilyLabel(context, warning.family),
                            warning.previousYears.join(', '),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              Text(
                l.gardenRotationInfo,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 20),
              Text(
                l.gardenHistory,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              if (history.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(l.gardenNoHistory),
                ),
              for (final s in history)
                ExpansionTile(
                  key: ValueKey('garden-history-${selected.id}-${s.year}'),
                  tilePadding: EdgeInsets.zero,
                  title: Text('${s.year}'),
                  subtitle: Text(s.plantings.map((p) => p.crop).join(', ')),
                  children: [
                    for (final p in s.plantings)
                      _planting(context, p, history: true),
                  ],
                ),
            ],
            if (season != null && !readOnly) ...[
              const SizedBox(height: 20),
              TextFormField(
                key: ValueKey('garden-season-notes-$year'),
                initialValue: season.notes,
                minLines: 2,
                maxLines: 4,
                maxLength: 20000,
                decoration: InputDecoration(
                  labelText: l.gardenSeasonNotes,
                  alignLabelWithHint: true,
                ),
                onChanged: onNotes,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
