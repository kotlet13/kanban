import 'package:flutter/material.dart';
import '../../../l10n/l10n.dart';
import '../../domain/garden_models.dart';

class GardenAreaList extends StatelessWidget {
  const GardenAreaList({
    super.key,
    required this.garden,
    required this.year,
    required this.selectedId,
    required this.onAdd,
    required this.onSelect,
    required this.onEdit,
  });
  final Garden garden;
  final int? year;
  final String? selectedId;
  final VoidCallback onAdd;
  final ValueChanged<String> onSelect;
  final ValueChanged<GardenArea> onEdit;
  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 20),
        Text(l.gardenAreas, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(
          l.gardenAreaListHelp,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const ValueKey('garden-add-area'),
          onPressed: garden.areas.length >= 1000 ? null : onAdd,
          icon: const Icon(Icons.add),
          label: Text(l.gardenAddArea),
        ),
        if (garden.areas.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(l.gardenNoAreas),
          ),
        for (final area in garden.areas)
          ListTile(
            key: ValueKey('garden-area-${area.id}'),
            contentPadding: EdgeInsets.zero,
            selected: selectedId == area.id,
            leading: Icon(
              area.archived
                  ? Icons.archive_outlined
                  : area.kind == GardenAreaKind.bed
                  ? Icons.crop_square
                  : Icons.landscape_outlined,
            ),
            title: Text(
              area.label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              area.archived
                  ? l.gardenArchivedArea
                  : (garden
                                .seasonForYear(year ?? 0)
                                ?.plantingsForArea(area.id) ??
                            <GardenPlanting>[])
                        .map((p) => p.crop)
                        .join(', '),
            ),
            onTap: () => onSelect(area.id),
            trailing: IconButton(
              tooltip: l.gardenEditArea,
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => onEdit(area),
            ),
          ),
      ],
    );
  }
}
