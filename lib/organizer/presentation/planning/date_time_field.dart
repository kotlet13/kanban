import 'package:flutter/material.dart';

import '../../../l10n/l10n.dart';

/// A nullable local date/time field. Dates outside picker bounds remain intact
/// until the user chooses a new value.
class OrganizerDateTimeField extends StatelessWidget {
  const OrganizerDateTimeField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.withTime = true,
    this.enabled = true,
    this.wrap,
  });
  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final bool withTime;
  final bool enabled;
  final Widget Function(Widget)? wrap;

  Future<void> _choose(BuildContext context) async {
    FocusScope.of(context).unfocus();
    final current = value?.toLocal() ?? DateTime.now();
    final first = DateTime(1900);
    final last = DateTime(2200);
    final initial = current.isBefore(first)
        ? first
        : current.isAfter(last)
        ? last
        : current;
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
      builder: wrap == null ? null : (context, child) => wrap!(child!),
    );
    if (date == null || !context.mounted) return;
    if (!withTime) {
      onChanged(DateTime(date.year, date.month, date.day));
      return;
    }
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
      builder: wrap == null ? null : (context, child) => wrap!(child!),
    );
    if (time != null && context.mounted) {
      onChanged(
        DateTime(date.year, date.month, date.day, time.hour, time.minute),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final local = value?.toLocal();
    final material = MaterialLocalizations.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              alignment: Alignment.centerLeft,
              minimumSize: const Size(0, 48),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            onPressed: enabled ? () => _choose(context) : null,
            icon: const Icon(Icons.schedule_outlined, size: 18),
            label: Text(
              local == null
                  ? '$label · ${context.l10n.organizerNoDate}'
                  : '$label · ${material.formatMediumDate(local)}${withTime ? ' · ${material.formatTimeOfDay(TimeOfDay.fromDateTime(local))}' : ''}',
            ),
          ),
        ),
        if (value != null)
          IconButton(
            tooltip: context.l10n.organizerRemoveDate,
            onPressed: enabled ? () => onChanged(null) : null,
            icon: const Icon(Icons.close, size: 18),
          ),
      ],
    );
  }
}
