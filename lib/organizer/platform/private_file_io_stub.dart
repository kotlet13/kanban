import 'dart:typed_data';
import 'private_file_types.dart';

bool get usesPrivateMobileFileIo => false;
Future<PrivatePickedFile?> pickPrivateFile({
  required List<String> extensions,
  required int maxBytes,
}) async => throw UnsupportedError('Native mobile file picker unavailable');
Future<PrivateSaveStatus> savePrivateFile({
  required Uint8List bytes,
  required String name,
  required String title,
}) async => throw UnsupportedError('Native mobile file picker unavailable');
Future<void> cleanPrivateFileStaging() async {}
