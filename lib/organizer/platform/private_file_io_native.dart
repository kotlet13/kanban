import 'dart:io';
import 'dart:typed_data';

import 'private_file_channel.dart';
import 'private_file_types.dart';

const _client = PrivateFileChannel();
bool get usesPrivateMobileFileIo => Platform.isAndroid || Platform.isIOS;

/// Read the provider's stream directly into bounded RAM, without file_picker's
/// app-owned import cache. OS providers may retain their own source copies.
Future<PrivatePickedFile?> pickPrivateFile({
  required List<String> extensions,
  required int maxBytes,
}) {
  if (!usesPrivateMobileFileIo) {
    throw UnsupportedError('Native mobile file picker unavailable');
  }
  return _client.pick(extensions: extensions, maxBytes: maxBytes);
}

Future<PrivateSaveStatus> savePrivateFile({
  required Uint8List bytes,
  required String name,
  required String title,
}) {
  if (!usesPrivateMobileFileIo) {
    throw UnsupportedError('Native mobile file picker unavailable');
  }
  return _client.save(bytes: bytes, name: name, title: title);
}

Future<void> cleanPrivateFileStaging() async {
  if (usesPrivateMobileFileIo) await _client.cleanup();
}
