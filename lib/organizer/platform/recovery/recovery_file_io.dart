import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:math';

import '../../presentation/backup/backup_file_io.dart';
import '../private_file_io.dart';
import 'recovery_cache.dart';

/// Recovery imports are always a fresh platform selection. A successful save
/// or return from another application never substitutes for this read.
class RecoveryFileIo {
  static const maxBytes = 64 * 1024;

  Future<void> cleanup() async {
    await cleanPrivateFileStaging();
    await cleanRecoveryCaches();
  }

  Future<Uint8List?> pick() async {
    if (usesPrivateMobileFileIo) {
      return (await pickPrivateFile(
        extensions: const ['jivie-recovery'],
        maxBytes: maxBytes,
      ))?.bytes;
    }
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jivie-recovery'],
      allowMultiple: false,
      withData: false,
      withReadStream: true,
    );
    if (result == null) return null;
    final file = result.files.single;
    try {
      return await readBoundedBackup(file, maxBytes: maxBytes);
    } finally {
      await cleanRecoveryImport(file.path);
    }
  }

  bool get canShare => usesPrivateMobileFileIo;

  String _name(bool accountOnly) {
    final random = Random.secure();
    final suffix = List.generate(
      16,
      (_) => random.nextInt(256),
    ).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return 'jivie-${accountOnly ? 'account' : 'installation'}-$suffix.jivie-recovery';
  }

  /// Opening or returning from the system share sheet proves no external copy.
  /// The wizard still requires a fresh external-file import before activation.
  Future<void> share(
    Uint8List bytes,
    String title, {
    bool accountOnly = false,
  }) async {
    if (!canShare)
      throw UnsupportedError('System recovery sharing unavailable');
    await const PrivateFileChannel().shareRecovery(
      bytes: bytes,
      name: _name(accountOnly),
      title: title,
    );
  }

  Future<BackupSaveStatus> save(
    Uint8List bytes,
    String title, {
    bool accountOnly = false,
  }) async {
    if (bytes.isEmpty || bytes.length > maxBytes) {
      throw const FormatException('Invalid recovery file length');
    }
    final name = _name(accountOnly);
    if (usesPrivateMobileFileIo) {
      final result = await savePrivateFile(
        bytes: bytes,
        name: name,
        title: title,
      );
      return switch (result) {
        PrivateSaveStatus.saved => BackupSaveStatus.saved,
        PrivateSaveStatus.cancelled => BackupSaveStatus.cancelled,
        PrivateSaveStatus.downloadStarted => BackupSaveStatus.downloadStarted,
      };
    }
    String? path;
    try {
      path = await FilePicker.platform.saveFile(
        dialogTitle: title,
        fileName: name,
        type: FileType.custom,
        allowedExtensions: ['jivie-recovery'],
        bytes: bytes,
      );
    } finally {
      // file_picker iOS exports from its own plaintext file in app Documents.
      // Never delete the returned external destination or a desktop original.
      await cleanRecoveryExports(name);
    }
    return kIsWeb
        ? BackupSaveStatus.downloadStarted
        : path == null
        ? BackupSaveStatus.cancelled
        : BackupSaveStatus.saved;
  }
}

final recoveryFileIoProvider = Provider<RecoveryFileIo>(
  (ref) => RecoveryFileIo(),
);
