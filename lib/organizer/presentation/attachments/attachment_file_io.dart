import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import '../../domain/attachment_models.dart';
import '../../platform/private_file_io.dart';

class PickedAttachmentFile {
  const PickedAttachmentFile({required this.name, required this.bytes});
  final String name;
  final Uint8List bytes;
}

class AttachmentFilePicker {
  const AttachmentFilePicker({this.mobileIo});
  final PrivateFileChannel? mobileIo;
  Future<PickedAttachmentFile?> pick() async {
    if (mobileIo != null || usesPrivateMobileFileIo) {
      final file = await (mobileIo?.pick ?? pickPrivateFile)(
        extensions: attachmentMimeByExtension.keys.toList(),
        maxBytes: attachmentMaxBytes,
      );
      if (file == null) return null;
      validateAttachmentFile(file.name, file.bytes.length);
      return PickedAttachmentFile(name: file.name, bytes: file.bytes);
    }
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: attachmentMimeByExtension.keys.toList(),
      allowMultiple: false,
      withData: false,
      withReadStream: true,
    );
    if (result == null) return null;
    final file = result.files.single;
    validateAttachmentFile(file.name, file.size);
    final stream = file.readStream;
    Uint8List bytes;
    if (stream == null) {
      bytes = file.bytes ?? (throw const FormatException('Unreadable file'));
    } else {
      final builder = BytesBuilder(copy: false);
      var length = 0;
      await for (final chunk in stream) {
        length += chunk.length;
        if (length > attachmentMaxBytes || length > file.size) {
          throw const FormatException('Attachment exceeds declared size');
        }
        builder.add(chunk);
      }
      bytes = builder.takeBytes();
    }
    if (bytes.length != file.size) {
      throw const FormatException('Attachment size mismatch');
    }
    validateAttachmentFile(file.name, bytes.length);
    return PickedAttachmentFile(name: file.name, bytes: bytes);
  }
}

enum AttachmentExportStatus { saved, cancelled, downloadStarted }

class AttachmentFileExporter {
  const AttachmentFileExporter({this.mobileIo});
  final PrivateFileChannel? mobileIo;

  /// This is an explicit user export through the platform save dialog. The
  /// attachment is never automatically launched or written to a public folder.
  Future<AttachmentExportStatus> save({
    required AttachmentMetadata attachment,
    required Uint8List bytes,
    required String title,
  }) async {
    attachment.validate();
    if (bytes.length != attachment.size) {
      throw const FormatException('Attachment size mismatch');
    }
    if (mobileIo != null || usesPrivateMobileFileIo) {
      return switch (await (mobileIo?.save ?? savePrivateFile)(
        bytes: bytes,
        name: attachment.name,
        title: title,
      )) {
        PrivateSaveStatus.saved => AttachmentExportStatus.saved,
        PrivateSaveStatus.cancelled => AttachmentExportStatus.cancelled,
        PrivateSaveStatus.downloadStarted =>
          AttachmentExportStatus.downloadStarted,
      };
    }
    final path = await FilePicker.platform.saveFile(
      dialogTitle: title,
      fileName: attachment.name,
      type: FileType.custom,
      allowedExtensions: [attachment.name.split('.').last.toLowerCase()],
      bytes: bytes,
    );
    return kIsWeb
        ? AttachmentExportStatus.downloadStarted
        : path == null
        ? AttachmentExportStatus.cancelled
        : AttachmentExportStatus.saved;
  }
}
