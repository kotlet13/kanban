import 'dart:typed_data';

class PrivatePickedFile {
  const PrivatePickedFile({required this.name, required this.bytes});
  final String name;
  final Uint8List bytes;
}

enum PrivateSaveStatus { saved, cancelled, downloadStarted }

void validatePrivateFileRequest(List<String> extensions, int maxBytes) {
  if (extensions.isEmpty ||
      extensions.length > 32 ||
      maxBytes < 1 ||
      maxBytes > 192 * 1024 * 1024 ||
      extensions.any((e) => !RegExp(r'^[a-z0-9-]{1,20}$').hasMatch(e))) {
    throw const FormatException('Invalid private file request');
  }
}

PrivatePickedFile? parsePrivatePickedFile(
  Object? result, {
  required List<String> extensions,
  required int maxBytes,
}) {
  validatePrivateFileRequest(extensions, maxBytes);
  if (result == null) return null;
  if (result is! Map ||
      result.length != 2 ||
      result['name'] is! String ||
      result['bytes'] is! Uint8List) {
    throw const FormatException('Invalid private file response');
  }
  final name = result['name'] as String, bytes = result['bytes'] as Uint8List;
  validatePrivateFileName(name);
  if (!extensions.contains(name.split('.').last.toLowerCase()) ||
      bytes.length > maxBytes) {
    throw const FormatException('Private file exceeds limits');
  }
  return PrivatePickedFile(name: name, bytes: bytes);
}

void validatePrivateFileName(String name) {
  if (name.isEmpty ||
      name.length > 255 ||
      RegExp(r'[\x00-\x1f\x7f/\\]').hasMatch(name) ||
      name == '.' ||
      name == '..') {
    throw const FormatException('Invalid private file name');
  }
}
