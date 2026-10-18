import '../../platform/private_file_io.dart';
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
    final bytes = Uint8List.fromList(utf8.encode(json));
    final name =
        'jivie-unsynced-${DateTime.now().toIso8601String().substring(0, 10)}.json';
    if (usesPrivateMobileFileIo) {
      await savePrivateFile(
        bytes: bytes,
        name: name,
        title: context.l10n.sharingSaveDrafts,
      );
    } else {
      await FilePicker.platform.saveFile(
        dialogTitle: context.l10n.sharingSaveDrafts,
        fileName: name,
        type: FileType.custom,
        allowedExtensions: ['json'],
        bytes: bytes,
      );
    }
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(sharingErrorMessage(context, error))),
      );
    }
  }
}
