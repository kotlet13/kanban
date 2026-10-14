import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../l10n/l10n.dart';
import '../../data/unsent_work_recovery.dart';
import '../../domain/idea_models.dart';

class UnsentWorkRecoveryButton extends StatelessWidget {
  const UnsentWorkRecoveryButton({super.key});
  @override
  Widget build(BuildContext context) => TextButton.icon(
    icon: const Icon(Icons.folder_open_outlined),
    label: Text(context.l10n.sharingOpenDrafts),
    onPressed: () async {
      try {
        final selected = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['json'],
          withData: true,
        );
        if (selected == null) return;
        final file = selected.files.single;
        final bytes = file.bytes ?? await File(file.path!).readAsBytes();
        final recovery = await UnsentWorkRecovery.decode(utf8.decode(bytes));
        if (!context.mounted) return;
        await showDialog<void>(
          context: context,
          builder: (_) => UnsentWorkRecoveryDialog(recovery: recovery),
        );
      } catch (_) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.sharingRecoveryInvalid)),
        );
      }
    },
  );
}

class UnsentWorkRecoveryDialog extends StatelessWidget {
  const UnsentWorkRecoveryDialog({super.key, required this.recovery});
  final UnsentWorkRecovery recovery;
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(context.l10n.sharingOpenDrafts),
    content: SizedBox(
      width: 560,
      height: (MediaQuery.sizeOf(context).height - 220).clamp(180, 600),
      child: ListView(
        children: [
          Text(context.l10n.sharingRecoveryReviewDescription),
          const SizedBox(height: 12),
          for (final candidate in recovery.candidates)
            ExpansionTile(
              title: Text(candidate.title),
              subtitle: Text(candidate.type),
              childrenPadding: const EdgeInsets.all(12),
              expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final asset
                    in candidate.board?.assets ?? const <IdeaAsset>[])
                  Image.memory(
                    recovery.assets['${candidate.workspace}:${asset.sha256}']!,
                    height: 180,
                    fit: BoxFit.contain,
                  ),
                SelectableText(
                  const JsonEncoder.withIndent('  ').convert(candidate.payload),
                ),
              ],
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.l10n.close),
      ),
    ],
  );
}
