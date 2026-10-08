import 'package:flutter/material.dart';
import '../../../l10n/l10n.dart';
import '../../data/organizer_repository.dart' show newLocalId;
import '../../domain/garden_models.dart';

class GardenSeasonPanel extends StatelessWidget {
  const GardenSeasonPanel({
    super.key,
    required this.seasons,
    required this.year,
    required this.onSelected,
    required this.onAdd,
    required this.onDelete,
  });
  final List<GardenSeason> seasons;
  final int? year;
  final ValueChanged<int> onSelected;
  final VoidCallback onAdd, onDelete;
  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final sorted = [...seasons]..sort((a, b) => b.year.compareTo(a.year));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (sorted.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(l.gardenNoSeasons),
          ),
        Row(
          children: [
            if (sorted.isNotEmpty)
              Expanded(
                child: DropdownButtonFormField<int>(
                  key: ValueKey('garden-season-$year'),
                  initialValue: year,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: l.gardenSeason),
                  items: [
                    for (final s in sorted)
                      DropdownMenuItem(value: s.year, child: Text('${s.year}')),
                  ],
                  onChanged: (y) {
                    if (y != null) onSelected(y);
                  },
                ),
              ),
            if (sorted.isNotEmpty) const SizedBox(width: 8),
            if (sorted.isEmpty)
              Expanded(
                child: OutlinedButton.icon(
                  key: const ValueKey('garden-new-season'),
                  onPressed: onAdd,
                  icon: const Icon(Icons.add),
                  label: Text(l.gardenNewSeason),
                ),
              )
            else
              IconButton(
                key: const ValueKey('garden-new-season'),
                tooltip: l.gardenNewSeason,
                onPressed: onAdd,
                icon: const Icon(Icons.add),
              ),
            if (sorted.isNotEmpty)
              IconButton(
                tooltip: l.gardenDeleteSeasonAction,
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline),
              ),
          ],
        ),
      ],
    );
  }
}

Future<GardenSeason?> showGardenSeasonForm(
  BuildContext context,
  List<GardenSeason> seasons, {
  required Set<String> activeAreaIds,
}) => showDialog<GardenSeason>(
  context: context,
  builder: (_) => _SeasonForm(seasons: seasons, activeAreaIds: activeAreaIds),
);

class _SeasonForm extends StatefulWidget {
  const _SeasonForm({required this.seasons, required this.activeAreaIds});
  final List<GardenSeason> seasons;
  final Set<String> activeAreaIds;
  @override
  State<_SeasonForm> createState() => _SeasonFormState();
}

class _SeasonFormState extends State<_SeasonForm> {
  final _form = GlobalKey<FormState>();
  late final _year = TextEditingController(
    text:
        '${DateTime.now().year + (widget.seasons.any((s) => s.year == DateTime.now().year) ? 1 : 0)}',
  );
  int? _source;
  @override
  void dispose() {
    _year.dispose();
    super.dispose();
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    final source = widget.seasons.where((s) => s.year == _source).firstOrNull;
    Navigator.pop(
      context,
      GardenSeason(
        year: int.parse(_year.text),
        plantings: [
          for (final p in source?.plantings ?? <GardenPlanting>[])
            if (widget.activeAreaIds.contains(p.areaId))
              GardenPlanting(
                id: newLocalId(),
                areaId: p.areaId,
                crop: p.crop,
                variety: p.variety,
                family: p.family,
                status: GardenPlantingStatus.planned,
              ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      title: Text(l.gardenNewSeason),
      scrollable: true,
      content: SizedBox(
        width: 440,
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                key: const ValueKey('garden-season-year'),
                controller: _year,
                maxLength: 4,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: l.gardenSeasonYear),
                validator: (v) {
                  final year = int.tryParse(v ?? '');
                  return year == null ||
                          year < 1900 ||
                          year > 9999 ||
                          widget.seasons.any((s) => s.year == year)
                      ? l.gardenSeasonYearError
                      : null;
                },
              ),
              DropdownButtonFormField<int>(
                key: const ValueKey('garden-season-copy'),
                initialValue: 0,
                isExpanded: true,
                decoration: InputDecoration(labelText: l.gardenSeasonCopy),
                items: [
                  DropdownMenuItem(value: 0, child: Text(l.gardenSeasonEmpty)),
                  for (final s in widget.seasons)
                    DropdownMenuItem(value: s.year, child: Text('${s.year}')),
                ],
                onChanged: (v) => setState(() => _source = v == 0 ? null : v),
              ),
              const SizedBox(height: 16),
              Text(l.gardenSeasonCopyHelp),
              const SizedBox(height: 12),
              Text(
                l.gardenConfirmDraft,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        FilledButton(
          key: const ValueKey('garden-season-save'),
          onPressed: _save,
          child: Text(l.save),
        ),
      ],
    );
  }
}
