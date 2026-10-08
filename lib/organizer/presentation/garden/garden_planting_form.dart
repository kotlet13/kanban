import 'package:flutter/material.dart';

import '../../../l10n/l10n.dart';
import '../../domain/garden_models.dart';
import '../../domain/garden_rotation.dart';
import 'garden_family_labels.dart';
import 'garden_calendar_date.dart';

Future<GardenPlanting?> showGardenPlantingForm(
  BuildContext context,
  GardenPlanting planting, {
  required bool isNew,
}) => showDialog<GardenPlanting>(
  context: context,
  builder: (_) => _PlantingForm(planting: planting, isNew: isNew),
);

class _PlantingForm extends StatefulWidget {
  const _PlantingForm({required this.planting, required this.isNew});
  final GardenPlanting planting;
  final bool isNew;
  @override
  State<_PlantingForm> createState() => _PlantingFormState();
}

class _PlantingFormState extends State<_PlantingForm> {
  final _form = GlobalKey<FormState>();
  late final _crop = TextEditingController(text: widget.planting.crop);
  late final _variety = TextEditingController(text: widget.planting.variety);
  late final _family = TextEditingController(text: widget.planting.family);
  late final _notes = TextEditingController(text: widget.planting.notes);
  late var _status = widget.planting.status;
  late final List<DateTime?> _dates = [
    widget.planting.sowAt,
    widget.planting.plantAt,
    widget.planting.harvestAt,
  ];
  String? _error;
  @override
  void dispose() {
    for (final c in [_crop, _variety, _family, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _date(int i) async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _dates[i] ?? DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime(9999, 12, 31),
    );
    if (selected != null && mounted) {
      setState(() {
        _dates[i] = DateTime.utc(selected.year, selected.month, selected.day);
        _error = null;
      });
    }
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    final planting = widget.planting.copyWith(
      crop: _crop.text.trim(),
      variety: _variety.text.trim(),
      family: _family.text.trim(),
      notes: _notes.text,
      status: _status,
      sowAt: _dates[0],
      clearSowAt: _dates[0] == null,
      plantAt: _dates[1],
      clearPlantAt: _dates[1] == null,
      harvestAt: _dates[2],
      clearHarvestAt: _dates[2] == null,
    );
    try {
      planting.validate();
      Navigator.pop(context, planting);
    } on FormatException {
      setState(() => _error = context.l10n.gardenPlantingDatesError);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      title: Text(widget.isNew ? l.gardenAddPlanting : l.gardenEditPlanting),
      scrollable: true,
      content: SizedBox(
        width: 480,
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                key: const ValueKey('garden-crop'),
                controller: _crop,
                decoration: InputDecoration(labelText: l.gardenCrop),
                maxLength: 200,
                validator: (v) =>
                    v!.trim().isEmpty ? l.gardenCropRequired : null,
              ),
              TextFormField(
                key: const ValueKey('garden-variety'),
                controller: _variety,
                decoration: InputDecoration(labelText: l.gardenVariety),
                maxLength: 200,
              ),
              DropdownButtonFormField<GardenPlantingStatus>(
                key: const ValueKey('garden-planting-status'),
                initialValue: _status,
                isExpanded: true,
                decoration: InputDecoration(labelText: l.gardenPlantingStatus),
                items: [
                  DropdownMenuItem(
                    value: GardenPlantingStatus.planned,
                    child: Text(l.gardenPlantingPlanned),
                  ),
                  DropdownMenuItem(
                    value: GardenPlantingStatus.actual,
                    child: Text(l.gardenPlantingActual),
                  ),
                ],
                onChanged: (v) => setState(() => _status = v!),
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const ValueKey('garden-family'),
                controller: _family,
                maxLength: 200,
                decoration: InputDecoration(
                  labelText: l.gardenFamily,
                  suffixIcon: PopupMenuButton<String>(
                    tooltip: l.gardenFamily,
                    onSelected: (v) => setState(() => _family.text = v),
                    itemBuilder: (_) => [
                      for (final family in gardenKnownFamilies)
                        PopupMenuItem(
                          value: family,
                          child: Text(gardenFamilyLabel(context, family)),
                        ),
                    ],
                  ),
                ),
              ),
              Text(
                l.gardenFamilyHelp,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              for (var i = 0; i < _dates.length; i++)
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        key: ValueKey('garden-planting-date-$i'),
                        onPressed: () => _date(i),
                        icon: const Icon(
                          Icons.calendar_today_outlined,
                          size: 18,
                        ),
                        label: Text(
                          '${[l.gardenSowDate, l.gardenPlantDate, l.gardenHarvestDate][i]}: ${_dates[i] == null ? l.gardenChooseDate : gardenCalendarDate(context, _dates[i]!)}',
                        ),
                      ),
                    ),
                    if (_dates[i] != null)
                      IconButton(
                        tooltip: l.gardenClearDate,
                        onPressed: () => setState(() => _dates[i] = null),
                        icon: const Icon(Icons.close, size: 18),
                      ),
                  ],
                ),
              const SizedBox(height: 16),
              TextFormField(
                key: const ValueKey('garden-planting-notes'),
                controller: _notes,
                decoration: InputDecoration(
                  labelText: l.organizerNotes,
                  alignLabelWithHint: true,
                ),
                minLines: 2,
                maxLines: 4,
                maxLength: 20000,
              ),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
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
          key: const ValueKey('garden-planting-save'),
          onPressed: _save,
          child: Text(l.save),
        ),
      ],
    );
  }
}
