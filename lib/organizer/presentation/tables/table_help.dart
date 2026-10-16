import 'package:flutter/material.dart';
import 'tables_strings.dart';

Future<void> showTableHelp(BuildContext context) {
  final s = TablesStrings.of(context);
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(s.help),
      scrollable: true,
      content: SizedBox(
        width: 480,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.helpInput),
            const SizedBox(height: 16),
            Text(
              s.helpFunctions,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            for (final example in [
              ('=SUM(A1:A10)', s.sum),
              ('=AVERAGE(A1:A10)', s.average),
              ('=COUNT(A1:A10)', s.count),
              ('=MIN(A1:A10)', s.minimum),
              ('=MAX(A1:A10)', s.maximum),
            ]) ...[
              const SizedBox(height: 12),
              SelectableText(example.$1),
              Text(example.$2),
            ],
            const SizedBox(height: 16),
            Text(s.helpArithmetic),
            const SizedBox(height: 16),
            Text(s.helpZoom),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(s.close),
        ),
      ],
    ),
  );
}
