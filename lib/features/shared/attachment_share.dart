import 'dart:typed_data';
import 'dart:io';

import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
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

Future<void> openAttachmentBytes({
  required Uint8List bytes,
  required String filename,
  bool fallbackToShare = true,
}) async {
  final tempDir = await getTemporaryDirectory();
  final safeFilename = _sanitizeFilename(filename);
  final tempPath =
      '${tempDir.path}${Platform.pathSeparator}${DateTime.now().millisecondsSinceEpoch}_$safeFilename';
  final file = File(tempPath);
  await file.writeAsBytes(bytes, flush: true);

  final result = await OpenFilex.open(
    file.path,
    type: attachmentMimeType(filename),
  );
  if (result.type == ResultType.done) return;
  if (fallbackToShare) {
    await shareAttachmentBytes(bytes: bytes, filename: filename);
    return;
  }
  throw StateError(result.message);
}

String _sanitizeFilename(String filename) {
  final trimmed = filename.trim();
  final sanitized = trimmed
      .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
      .replaceAll(RegExp(r'\s+'), ' ');
  if (sanitized.isEmpty) {
    return 'attachment.bin';
  }
  return sanitized;
}
