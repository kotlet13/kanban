import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/domain/attachment_models.dart';
import 'package:kanban/organizer/presentation/attachments/attachment_file_io.dart';

import '../domain/attachment_models_test.dart' show fixtureAttachment;

class PickerPlatform extends FilePicker {
  FilePickerResult? result;
  String? savePath;
  int saveCalls = 0;
  Uint8List? savedBytes;
  String? savedName;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = false,
    int compressionQuality = 0,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    expect(type, FileType.custom);
    expect(allowedExtensions, containsAll(attachmentMimeByExtension.keys));
    expect(allowMultiple, false);
    expect(withData, false);
    expect(withReadStream, true);
    return result;
  }

  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async {
    saveCalls++;
    savedName = fileName;
    savedBytes = bytes;
    expect(type, FileType.custom);
    expect(allowedExtensions, ['pdf']);
    return savePath;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PickerPlatform platform;
  setUp(() {
    platform = PickerPlatform();
    FilePicker.platform = platform;
  });

  test('cancelled picker returns no file', () async {
    expect(await AttachmentFilePicker().pick(), isNull);
  });

  test('reads selected bytes from a bounded stream', () async {
    platform.result = FilePickerResult([
      PlatformFile(
        name: 'a.pdf',
        size: 4,
        readStream: Stream.fromIterable([
          [1, 2],
          [3, 4],
        ]),
      ),
    ]);
    final picked = await AttachmentFilePicker().pick();
    expect(picked!.bytes, [1, 2, 3, 4]);
    expect(picked.name, 'a.pdf');
  });

  test('rejects oversize metadata without reading the stream', () async {
    var read = false;
    Stream<List<int>> bytes() async* {
      read = true;
      yield [1];
    }

    platform.result = FilePickerResult([
      PlatformFile(
        name: 'a.pdf',
        size: attachmentMaxBytes + 1,
        readStream: bytes(),
      ),
    ]);
    await expectLater(AttachmentFilePicker().pick(), throwsFormatException);
    expect(read, false);
  });

  test('rejects stream exceeding declared length or ending early', () async {
    for (final chunks in [
      <List<int>>[
        [1, 2, 3, 4, 5],
      ],
      <List<int>>[
        [1, 2],
      ],
    ]) {
      platform.result = FilePickerResult([
        PlatformFile(
          name: 'a.pdf',
          size: 4,
          readStream: Stream.fromIterable(chunks),
        ),
      ]);
      await expectLater(AttachmentFilePicker().pick(), throwsFormatException);
    }
  });

  test('validates memory fallback byte count', () async {
    platform.result = FilePickerResult([
      PlatformFile(name: 'a.pdf', size: 4, bytes: Uint8List(3)),
    ]);
    await expectLater(AttachmentFilePicker().pick(), throwsFormatException);
    platform.result = FilePickerResult([
      PlatformFile(name: 'a.pdf', size: 4, bytes: Uint8List(4)),
    ]);
    expect((await AttachmentFilePicker().pick())!.bytes.length, 4);
  });

  test(
    'export uses explicit save chooser, preserves bytes and cancellation',
    () async {
      final metadata = fixtureAttachment(),
          bytes = Uint8List.fromList([1, 2, 3, 4]);
      final exporter = AttachmentFileExporter();
      expect(
        await exporter.save(attachment: metadata, bytes: bytes, title: 'Save'),
        AttachmentExportStatus.cancelled,
      );
      platform.savePath = '/user-selected/Načrt.pdf';
      expect(
        await exporter.save(attachment: metadata, bytes: bytes, title: 'Save'),
        AttachmentExportStatus.saved,
      );
      expect(platform.savedBytes, bytes);
      expect(platform.savedName, metadata.name);
    },
  );

  test('export refuses truncated content before opening chooser', () async {
    await expectLater(
      AttachmentFileExporter().save(
        attachment: fixtureAttachment(),
        bytes: Uint8List(2),
        title: 'Save',
      ),
      throwsFormatException,
    );
    expect(platform.saveCalls, 0);
  });
}
