import 'dart:typed_data';

import 'package:share_plus/share_plus.dart';

const Map<String, String> _attachmentMimeTypes = <String, String>{
  'csv': 'text/csv',
  'doc': 'application/msword',
  'docx':
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'gif': 'image/gif',
  'jpeg': 'image/jpeg',
  'jpg': 'image/jpeg',
  'json': 'application/json',
  'pdf': 'application/pdf',
  'png': 'image/png',
  'svg': 'image/svg+xml',
  'txt': 'text/plain',
  'webp': 'image/webp',
  'xls': 'application/vnd.ms-excel',
  'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'zip': 'application/zip',
};

String attachmentMimeType(String filename) {
  final dotIndex = filename.lastIndexOf('.');
  if (dotIndex < 0 || dotIndex == filename.length - 1) {
    return 'application/octet-stream';
  }
  final extension = filename.substring(dotIndex + 1).toLowerCase();
  return _attachmentMimeTypes[extension] ?? 'application/octet-stream';
}

Future<void> shareAttachmentBytes({
  required Uint8List bytes,
  required String filename,
}) {
  return SharePlus.instance.share(
    ShareParams(
      files: <XFile>[
        XFile.fromData(
          bytes,
          name: filename,
          mimeType: attachmentMimeType(filename),
        ),
      ],
      fileNameOverrides: <String>[filename],
      text: filename,
    ),
  );
}
