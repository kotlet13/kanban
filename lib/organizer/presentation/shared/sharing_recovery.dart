import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n.dart';
import '../../state/collaboration_provider.dart';
import 'sharing_errors.dart';

Future<void> exportSharingDrafts(BuildContext context, WidgetRef ref) async {
  final controller = ref.read(collaborationProvider.notifier);
  try {
    final json = await controller.exportUnsentWork();
    if (!context.mounted) return;
    await FilePicker.platform.saveFile(
      dialogTitle: context.l10n.sharingSaveDrafts,
      fileName:
          'vsakdan-unsynced-${DateTime.now().toIso8601String().substring(0, 10)}.json',
      type: FileType.custom,
      allowedExtensions: ['json'],
      bytes: Uint8List.fromList(utf8.encode(json)),
    );
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(sharingErrorMessage(context, error))),
      );
    }
  }
}
