import 'package:flutter/services.dart';

import 'private_file_types.dart';

/// Typed, bounded contract shared by the mobile entry points and test doubles.
/// Native handlers independently check every request before accessing a file.
class PrivateFileChannel {
  const PrivateFileChannel({
    this.channel = const MethodChannel('jivie/private_file_io'),
  });

  final MethodChannel channel;

  Future<Map<String, String>> legacyPickerRoots() async {
    final value = await channel.invokeMethod<Object?>('legacyPickerRoots');
    if (value is! Map ||
        value.isEmpty ||
        value.length > 2 ||
        value.keys.any(
          (k) => !const {
            'androidPicker',
            'iosTemporary',
            'iosDocuments',
          }.contains(k),
        ) ||
        value.values.any(
          (v) => v is! String || v.isEmpty || v.contains('\u0000'),
        )) {
      throw const FormatException('Invalid legacy picker roots');
    }
    return Map<String, String>.from(value);
  }

  Future<PrivatePickedFile?> pick({
    required List<String> extensions,
    required int maxBytes,
  }) async {
    validatePrivateFileRequest(extensions, maxBytes);
    final result = await channel.invokeMethod<Object?>('pick', {
      'extensions': extensions,
      'maxBytes': maxBytes,
    });
    return parsePrivatePickedFile(
      result,
      extensions: extensions,
      maxBytes: maxBytes,
    );
  }

  Future<PrivateSaveStatus> save({
    required Uint8List bytes,
    required String name,
    required String title,
  }) async {
    validatePrivateFileName(name);
    if (bytes.length > 192 * 1024 * 1024) {
      throw const FormatException('Invalid private export');
    }
    final result = await channel.invokeMethod<String>('save', {
      'bytes': bytes,
      'name': name,
      'title': title,
    });
    return switch (result) {
      'saved' => PrivateSaveStatus.saved,
      'cancelled' => PrivateSaveStatus.cancelled,
      _ => throw const FormatException('Invalid private save response'),
    };
  }

  Future<void> shareRecovery({
    required Uint8List bytes,
    required String name,
    required String title,
  }) async {
    if (!RegExp(
          r'^jivie-(installation|account)-[a-f0-9]{32}\.jivie-recovery$',
        ).hasMatch(name) ||
        bytes.isEmpty ||
        bytes.length > 64 * 1024)
      throw const FormatException('Invalid recovery share');
    final result = await channel.invokeMethod<String>('shareRecovery', {
      'bytes': bytes,
      'name': name,
      'title': title,
    });
    if (result != 'shareStarted' && result != 'cancelled')
      throw const FormatException('Invalid recovery share response');
  }

  Future<void> cleanup() async {
    if (await channel.invokeMethod<bool>('cleanup') != true) {
      throw const FormatException('Private export cleanup failed');
    }
  }
}
