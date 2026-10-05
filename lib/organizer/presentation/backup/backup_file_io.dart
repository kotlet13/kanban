import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class BackupFileTooLarge implements Exception {
  const BackupFileTooLarge();
}

class PickedBackupFile {
  const PickedBackupFile(this.name, this.bytes);
  final String name;
  final Uint8List bytes;
}

enum BackupSaveStatus { saved, cancelled, downloadStarted }

class BackupFileIo {
  Future<PickedBackupFile?> pick({required int maxBytes}) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['vsakdan'],
      withData: false,
      withReadStream: true,
    );
    if (result == null) return null;
    final file = result.files.single;
    return PickedBackupFile(
      file.name,
      await readBoundedBackup(file, maxBytes: maxBytes),
    );
  }

  Future<BackupSaveStatus> save(
    Uint8List bytes, {
    required String title,
    required String name,
  }) async {
    final path = await FilePicker.platform.saveFile(
      dialogTitle: title,
      fileName: name,
      type: FileType.custom,
      allowedExtensions: ['vsakdan'],
      bytes: bytes,
    );
    // Pinned file_picker web returns null after triggering the browser download.
    // Native null is cancellation; neither implies the user kept a disk copy.
    return kIsWeb
        ? BackupSaveStatus.downloadStarted
        : path == null
        ? BackupSaveStatus.cancelled
        : BackupSaveStatus.saved;
  }
}

final backupFileIoProvider = Provider<BackupFileIo>((ref) => BackupFileIo());
Future<Uint8List> readBoundedBackup(
  PlatformFile file, {
  required int maxBytes,
}) async {
  if (file.size > maxBytes) throw const BackupFileTooLarge();
  final stream = file.readStream;
  if (stream == null) {
    final bytes = file.bytes;
    if (bytes == null) throw const FormatException();
    if (bytes.length > maxBytes) throw const BackupFileTooLarge();
    return bytes;
  }
  final builder = BytesBuilder(copy: false);
  var count = 0;
  await for (final chunk in stream) {
    count += chunk.length;
    if (count > maxBytes) throw const BackupFileTooLarge();
    builder.add(chunk);
  }
  if (count != file.size) throw const FormatException();
  return builder.takeBytes();
}
