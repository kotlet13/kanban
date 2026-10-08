import 'package:flutter/material.dart';

import '../../../l10n/l10n.dart';
import '../../domain/garden_models.dart';

Future<GardenArea?> showGardenAreaForm(
  BuildContext context,
  GardenArea area, {
  bool allowKindChange = true,
}) => showDialog<GardenArea>(
  context: context,
  builder: (_) => _AreaForm(area: area, allowKindChange: allowKindChange),
);

class _AreaForm extends StatefulWidget {
  const _AreaForm({required this.area, required this.allowKindChange});
  final GardenArea area;
  final bool allowKindChange;
  @override
  State<_AreaForm> createState() => _AreaFormState();
}

class _AreaFormState extends State<_AreaForm> {
  final _form = GlobalKey<FormState>();
  late final _label = TextEditingController(text: widget.area.label);
  late final _numbers =
      [widget.area.x, widget.area.y, widget.area.width, widget.area.height]
          .map((n) => TextEditingController(text: (n * 100).toStringAsFixed(1)))
          .toList();
  late final _initialNumbers = [
    widget.area.x,
    widget.area.y,
    widget.area.width,
    widget.area.height,
  ].map((number) => (number * 100).toStringAsFixed(1)).toList();
  late var _kind = widget.area.kind;
  String? _geometryError;

  @override
  void dispose() {
    _label.dispose();
    for (final field in _numbers) {
      field.dispose();
    }
    super.dispose();
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    final original = [
      widget.area.x,
      widget.area.y,
      widget.area.width,
      widget.area.height,
    ];
    final values = [
      for (var i = 0; i < _numbers.length; i++)
        _numbers[i].text == _initialNumbers[i]
            ? original[i]
            : double.parse(_numbers[i].text.replaceAll(',', '.')) / 100,
    ];
    if (values[0] + values[2] > 1 || values[1] + values[3] > 1) {
      setState(() => _geometryError = context.l10n.gardenGeometryError);
      return;
    }
    Navigator.pop(
      context,
      widget.area.copyWith(
        label: _label.text.trim(),
        kind: _kind,
        x: values[0],
        y: values[1],
        width: values[2],
        height: values[3],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final labels = [
      l.gardenPositionX,
      l.gardenPositionY,
      l.gardenWidth,
      l.gardenHeight,
    ];
    return AlertDialog(
      title: Text(l.gardenEditArea),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  key: const ValueKey('garden-area-label'),
                  controller: _label,
                  decoration: InputDecoration(labelText: l.gardenAreaLabel),
                  maxLength: 200,
                  validator: (value) =>
                      value!.trim().isEmpty ? l.gardenLabelRequired : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<GardenAreaKind>(
                  key: const ValueKey('garden-area-kind'),
                  initialValue: _kind,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: l.gardenAreaKind),
                  items: [
                    DropdownMenuItem(
                      value: GardenAreaKind.bed,
                      child: Text(l.gardenBed),
                    ),
                    DropdownMenuItem(
                      value: GardenAreaKind.zone,
                      child: Text(l.gardenZone),
                    ),
                  ],
                  onChanged: widget.allowKindChange
                      ? (v) => setState(() => _kind = v!)
                      : null,
                ),
                const SizedBox(height: 12),
                Text(
                  l.gardenGeometryHelp,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                for (var row = 0; row < 2; row++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var column = 0; column < 2; column++) ...[
                          if (column > 0) const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              key: ValueKey(
                                'garden-area-number-${row * 2 + column}',
                              ),
                              controller: _numbers[row * 2 + column],
                              decoration: InputDecoration(
                                labelText: labels[row * 2 + column],
                                suffixText: '%',
                              ),
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              validator: (value) {
                                final index = row * 2 + column;
                                final n = value == _initialNumbers[index]
                                    ? [
                                            widget.area.x,
                                            widget.area.y,
                                            widget.area.width,
                                            widget.area.height,
                                          ][index] *
                                          100
                                    : double.tryParse(
                                        value!.replaceAll(',', '.'),
                                      );
                                final position = row == 0;
                                return n == null ||
                                        !n.isFinite ||
                                        (position ? n < 0 : n <= 0) ||
                                        n > 100
                                    ? l.gardenNumberError
                                    : null;
                              },
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                Text(
                  l.gardenConfirmDraft,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (_geometryError != null)
                  Text(
                    _geometryError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        FilledButton(
          key: const ValueKey('garden-area-save'),
          onPressed: _save,
          child: Text(l.save),
        ),
      ],
    );
  }
}
