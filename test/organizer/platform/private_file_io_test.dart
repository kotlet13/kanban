import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/platform/private_file_io.dart';
import 'package:kanban/organizer/presentation/attachments/attachment_file_io.dart';
import 'package:kanban/organizer/presentation/backup/backup_file_io.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('jivie/private_file_io-test');
  const client = PrivateFileChannel(channel: channel);
  final calls = <MethodCall>[];
  Object? response;
  setUp(() {
    calls.clear();
    response = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return response;
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );

  test(
    'legacy picker roots are exact native-owned names, never arbitrary paths from caller',
    () async {
      response = {'iosTemporary': '/app/tmp', 'iosDocuments': '/app/Documents'};
      expect(await client.legacyPickerRoots(), response);
      expect(calls.single.method, 'legacyPickerRoots');
      expect(calls.single.arguments, isNull);
      for (final bad in [
        null,
        {},
        {'arbitrary': '/tmp'},
        {'androidPicker': ''},
        {'androidPicker': '/app/cache', 'extra': '/user'},
      ]) {
        response = bad;
        await expectLater(client.legacyPickerRoots(), throwsFormatException);
      }
    },
  );

  test(
    'pick contract preserves exact bytes and bounded request; cancel is null',
    () async {
      expect(await client.pick(extensions: ['json'], maxBytes: 17), isNull);
      expect(calls.single.method, 'pick');
      expect(calls.single.arguments, {
        'extensions': ['json'],
        'maxBytes': 17,
      });
      response = {
        'name': 'my.JSON',
        'bytes': Uint8List.fromList([0, 255, 1]),
      };
      final file = await client.pick(extensions: ['json'], maxBytes: 3);
      expect(file!.name, 'my.JSON');
      expect(file.bytes, [0, 255, 1]);
    },
  );
  test('invalid native responses never reach an importer', () async {
    for (final bad in [
      <String, Object>{},
      {
        'name': 'a.json',
        'bytes': [1],
      },
      {'name': '../a.json', 'bytes': Uint8List(1)},
      {'name': 'a.pdf', 'bytes': Uint8List(1)},
      {'name': 'a.json', 'bytes': Uint8List(4)},
      {'name': 'a.json', 'bytes': Uint8List(1), 'extra': 1},
      {'name': 'a\u0000.json', 'bytes': Uint8List(1)},
    ]) {
      response = bad;
      await expectLater(
        client.pick(extensions: ['json'], maxBytes: 3),
        throwsFormatException,
      );
    }
  });
  test('invalid requests are rejected before invoking native UI', () async {
    for (final extensions in [
      <String>[],
      ['../json'],
      ['JSON'],
    ]) {
      await expectLater(
        client.pick(extensions: extensions, maxBytes: 3),
        throwsFormatException,
      );
    }
    await expectLater(
      client.pick(extensions: ['json'], maxBytes: 0),
      throwsFormatException,
    );
    await expectLater(
      client.pick(extensions: ['json'], maxBytes: 192 * 1024 * 1024 + 1),
      throwsFormatException,
    );
    expect(calls, isEmpty);
  });
  test(
    'save distinguishes cancel and success and never treats unknown response as saved',
    () async {
      final bytes = Uint8List.fromList([1, 2]);
      response = 'cancelled';
      expect(
        await client.save(bytes: bytes, name: 'x.json', title: 'Export'),
        PrivateSaveStatus.cancelled,
      );
      expect(calls.single.arguments, {
        'bytes': bytes,
        'name': 'x.json',
        'title': 'Export',
      });
      response = 'saved';
      expect(
        await client.save(bytes: bytes, name: 'x.json', title: 'Export'),
        PrivateSaveStatus.saved,
      );
      response = 'downloadStarted';
      await expectLater(
        client.save(bytes: bytes, name: 'x.json', title: 'Export'),
        throwsFormatException,
      );
      await expectLater(
        client.save(bytes: bytes, name: '../x.json', title: 'Export'),
        throwsFormatException,
      );
    },
  );
  test(
    'recovery share is bounded and handoff or cancel is never reported as save',
    () async {
      final name = 'jivie-account-${'a' * 32}.jivie-recovery';
      final bytes = Uint8List.fromList([1, 2, 3]);
      for (final status in ['shareStarted', 'cancelled']) {
        response = status;
        await client.shareRecovery(
          bytes: bytes,
          name: name,
          title: 'Choose an app',
        );
        expect(calls.last.method, 'shareRecovery');
        expect(calls.last.arguments, {
          'bytes': bytes,
          'name': name,
          'title': 'Choose an app',
        });
      }
      response = 'saved';
      await expectLater(
        client.shareRecovery(bytes: bytes, name: name, title: ''),
        throwsFormatException,
      );
      calls.clear();
      for (final invalid in [Uint8List(0), Uint8List(65537)]) {
        await expectLater(
          client.shareRecovery(bytes: invalid, name: name, title: ''),
          throwsFormatException,
        );
      }
      await expectLater(
        client.shareRecovery(bytes: bytes, name: '../$name', title: ''),
        throwsFormatException,
      );
      expect(calls, isEmpty);
    },
  );
  test('cleanup requires acknowledged completion', () async {
    await expectLater(client.cleanup(), throwsFormatException);
    response = true;
    await client.cleanup();
    expect(calls.map((c) => c.method), ['cleanup', 'cleanup']);
  });
  test(
    'actual backup adapter uses native channel without FilePicker or file paths',
    () async {
      final io = BackupFileIo(mobileIo: client);
      response = {
        'name': 'copy.vsakdan',
        'bytes': Uint8List.fromList([9, 8]),
      };
      final picked = await io.pick(maxBytes: 2);
      expect(picked!.bytes, [9, 8]);
      expect(calls.single.arguments, {
        'extensions': ['vsakdan'],
        'maxBytes': 2,
      });
      response = 'cancelled';
      expect(
        await io.save(picked.bytes, name: picked.name, title: 'Backup'),
        BackupSaveStatus.cancelled,
      );
    },
  );
  test(
    'actual attachment adapter enforces extension and byte bounds before import',
    () async {
      final picker = AttachmentFilePicker(mobileIo: client);
      response = {
        'name': 'report.pdf',
        'bytes': Uint8List.fromList([1, 2, 3]),
      };
      expect((await picker.pick())!.bytes, [1, 2, 3]);
      response = {
        'name': 'report.exe',
        'bytes': Uint8List.fromList([1]),
      };
      await expectLater(picker.pick(), throwsFormatException);
      response = null;
      expect(await picker.pick(), isNull);
    },
  );
}
