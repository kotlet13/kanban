import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/presentation/backup/backup_file_io.dart';

void main() {
  test('oversized metadata is rejected before stream subscription', () async {
    var read = false;
    Stream<List<int>> data() async* {
      read = true;
      yield [1];
    }

    final file = PlatformFile(
      name: 'copy.vsakdan',
      size: 100,
      readStream: data(),
    );
    await expectLater(
      readBoundedBackup(file, maxBytes: 10),
      throwsA(isA<BackupFileTooLarge>()),
    );
    expect(read, false);
  });
  test('dishonest size cannot grow a backup past the bound', () async {
    final file = PlatformFile(
      name: 'copy.vsakdan',
      size: 2,
      readStream: Stream.fromIterable([
        [1, 2],
        [3, 4],
      ]),
    );
    await expectLater(
      readBoundedBackup(file, maxBytes: 3),
      throwsA(isA<BackupFileTooLarge>()),
    );
  });
  test('valid bounded stream is complete and byte exact', () async {
    final file = PlatformFile(
      name: 'copy.vsakdan',
      size: 4,
      readStream: Stream.fromIterable([
        [1, 2],
        [3, 4],
      ]),
    );
    expect(await readBoundedBackup(file, maxBytes: 4), [1, 2, 3, 4]);
  });
  test('truncated stream is rejected', () async {
    final file = PlatformFile(
      name: 'copy.vsakdan',
      size: 4,
      readStream: Stream.fromIterable([
        [1, 2],
      ]),
    );
    await expectLater(
      readBoundedBackup(file, maxBytes: 4),
      throwsFormatException,
    );
  });
}
