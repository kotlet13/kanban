import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../l10n/l10n.dart';
import '../../state/organizer_provider.dart';
import '../../state/collaboration_provider.dart';
import '../shared/sharing_errors.dart';

/// Explicit standalone copy of the currently authorized personal projection.
/// It can later be imported in local mode; it carries no sync identity or queue.
Future<void> exportPersonalJsonForLocalRestore(
  BuildContext context,
  WidgetRef ref,
) async {
  final l = context.l10n, messenger = ScaffoldMessenger.of(context);
  final container = ProviderScope.containerOf(context, listen: false);
  final session = ref.read(collaborationProvider).valueOrNull?.session;
  String identity(AccountSession? p) => '${p?.partition}:${p?.deviceId}';
  final captured = identity(session);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l.deletionPersonalExport),
      content: Text(l.deletionJsonWarning),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(l.organizerExport),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  try {
    if (identity(container.read(collaborationProvider).valueOrNull?.session) !=
        captured) {
      throw const CollaborationException('session_changed');
    }
    final json = await container
        .read(organizerProvider.notifier)
        .exportBackup();
    if (identity(container.read(collaborationProvider).valueOrNull?.session) !=
        captured) {
      throw const CollaborationException('session_changed');
    }
    if (!context.mounted) return;
    await FilePicker.platform.saveFile(
      dialogTitle: l.deletionPersonalExport,
      fileName:
          'jivie-personal-${DateTime.now().toIso8601String().substring(0, 10)}.json',
      type: FileType.custom,
      allowedExtensions: ['json'],
      bytes: Uint8List.fromList(utf8.encode(json)),
    );
  } catch (e) {
    if (messenger.mounted && context.mounted) {
      messenger.showSnackBar(
        SnackBar(content: Text(sharingErrorMessage(context, e))),
      );
    }
  }
}
