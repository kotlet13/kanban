import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:kanban/organizer/data/local_vault.dart';
import 'package:kanban/organizer/data/local_vault_cipher.dart';
import 'package:kanban/organizer/data/local_vault_files.dart';
import 'package:kanban/organizer/data/local_vault_keys.dart';
import 'package:kanban/organizer/data/local_vault_legacy_cache.dart';

void main() {
  late Directory root, vault, picker;
  late LocalVaultKey key;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('jivie-legacy-cache-');
    vault = Directory('${root.path}/vault');
    picker = Directory('${root.path}/cache/file_picker');
    await picker.create(recursive: true);
    key = LocalVaultKey.generate();
  });
  tearDown(() async {
    key.bytes.fillRange(0, key.bytes.length, 0);
    await root.delete(recursive: true);
  });
  Future<File> source(String path, List<int> bytes) async {
    final file = File('${picker.path}/$path');
    await file.parent.create(recursive: true);
    return file.writeAsBytes(bytes, flush: true);
  }

  Future<List<Map<String, Object?>>> archived(
    LegacyPickerCacheArchive archive,
  ) async {
    final derived = await key.derive('legacy-picker-cache-archive');
    final bytes = Uint8List.fromList(await derived.extractBytes());
    final db = sqlite3.open(archive.archiveFile.path);
    try {
      LocalVaultCipher.configure(db, bytes);
      return db
          .select('SELECT * FROM objects ORDER BY relative_path')
          .map((r) => Map<String, Object?>.from(r))
          .toList();
    } finally {
      db.close();
      derived.destroy();
      bytes.fillRange(0, bytes.length, 0);
    }
  }

  test(
    'iOS parent path alias excludes only its own vault across cleanup retries',
    () async {
      final actualParent = Directory('${root.path}/actual-parent');
      await actualParent.create();
      final alias = Link('${root.path}/parent-alias');
      await alias.create(actualParent.path);
      final documents = Directory('${alias.path}/Documents');
      await documents.create();
      vault = Directory('${documents.path}/jivie_vault_v1');
      await vault.create();
      final own = File('${vault.path}/data.sqlite');
      const ownBytes = [11, 22, 33, 44];
      await own.writeAsBytes(ownBytes, flush: true);
      final unknown = File('${documents.path}/unknown-user-export.bin');
      const unknownBytes = [9, 8, 7, 6];
      await unknown.writeAsBytes(unknownBytes, flush: true);
      final archive = LegacyPickerCacheArchive(vault, LocalVaultFiles());

      Future<LegacyPickerCacheReport> preserve() => archive.preserve(
        key,
        roots: [LegacyPickerCacheRoot(documents, 'iosDocuments')],
      );

      for (var attempt = 0; attempt < 2; attempt++) {
        final report = await preserve();
        expect(report.retainedFiles, 1);
        expect(report.archivedFiles, 0);
        expect(report.removedFiles, 0);
        expect(await own.readAsBytes(), ownBytes);
        expect(await unknown.readAsBytes(), unknownBytes);
      }
      await unknown.delete(); // Remove only this test's unrelated fixture.
      for (var attempt = 0; attempt < 2; attempt++) {
        final report = await preserve();
        expect(report.hasResidualCopies, false);
        expect(report.archivedFiles, 0);
        expect(report.removedFiles, 0);
        expect(await own.readAsBytes(), ownBytes);
      }
    },
  );
  test(
    'normal iOS roots exclude only dedicated storage and empty directories',
    () async {
      final documents = Directory('${root.path}/Documents');
      final temporary = Directory('${root.path}/tmp');
      await documents.create();
      await temporary.create();
      final own = File('${documents.path}/organizer_shared_v1.sqlite-wal');
      await own.writeAsBytes([1, 2, 3]);
      final unknown = File('${documents.path}/user-export.pdf');
      await unknown.writeAsBytes([4, 5]);
      await Directory('${temporary.path}/empty-plugin-work').create();
      final opaque = Directory('${temporary.path}/unrelated-plugin-work');
      await opaque.create();
      await File('${opaque.path}/possible-user-content').writeAsBytes([6]);
      final archive = LegacyPickerCacheArchive(vault, LocalVaultFiles());
      final report = await archive.preserve(
        key,
        roots: [
          LegacyPickerCacheRoot(documents, 'iosDocuments'),
          LegacyPickerCacheRoot(temporary, 'iosTemporary'),
        ],
        dedicatedStoragePaths: {own.absolute.path},
      );
      expect(report.retainedFiles, 2);
      expect(report.archivedFiles, 0);
      expect(await own.readAsBytes(), [1, 2, 3]);
      expect(await unknown.readAsBytes(), [4, 5]);
      expect(await File('${opaque.path}/possible-user-content').exists(), true);
      await unknown.delete();
      await opaque.delete(recursive: true);
      final safe = await archive.preserve(
        key,
        roots: [
          LegacyPickerCacheRoot(documents, 'iosDocuments'),
          LegacyPickerCacheRoot(temporary, 'iosTemporary'),
        ],
        dedicatedStoragePaths: {own.absolute.path},
      );
      expect(safe.hasResidualCopies, false);
      expect(await own.exists(), true);
    },
  );

  test(
    'file beyond reachable encrypted export limit remains untouched and reported',
    () async {
      final safe = await source('100/supported.pdf', List.filled(16, 1));
      final large = await source('200/over-limit.pdf', List.filled(17, 2));
      final archive = LegacyPickerCacheArchive(
        vault,
        LocalVaultFiles(),
        maxFileBytes: 16,
      );
      final report = await archive.preserve(
        key,
        roots: [LegacyPickerCacheRoot(picker, 'androidPicker')],
      );
      expect(report.removedFiles, 1);
      expect(report.containsRetainedPlaintext, true);
      expect(report.retainedFiles, 1);
      expect(await safe.exists(), false);
      expect(await large.readAsBytes(), List.filled(17, 2));
      final preserved = await archive.listObjects(key);
      expect(preserved.single.size, 16);
      expect(
        await archive
            .openObject(key, preserved.single.id)
            .expand((c) => c)
            .toList(),
        List.filled(16, 1),
      );
    },
  );

  test(
    'duplicate basenames retain exact app-relative identities and bounded encrypted chunks before unlink',
    () async {
      final a = await source(
        '100/file.pdf',
        utf8.encode('PRIVATE_PICKER_SENTINEL'),
      );
      final data = Uint8List.fromList(List.generate(400000, (i) => i % 251));
      final b = await source('200/file.pdf', data);
      final archive = LegacyPickerCacheArchive(vault, LocalVaultFiles());
      final result = await archive.preserve(
        key,
        roots: [LegacyPickerCacheRoot(picker, 'androidPicker')],
      );
      expect(result.removedFiles, 2);
      expect(result.archivedFiles, 2);
      expect(await a.exists(), false);
      expect(await b.exists(), false);
      final rows = await archived(archive);
      expect(rows.map((r) => r['relative_path']), [
        '100/file.pdf',
        '200/file.pdf',
      ]);
      expect(rows.map((r) => r['id']).toSet().length, 2);
      expect(rows.last['size'], data.length);
      final manifest = await archive.listObjects(key, limit: 1);
      expect(manifest, hasLength(1));
      final rest = await archive.listObjects(key, afterId: manifest.single.id);
      expect(rest, hasLength(1));
      for (final object in [...manifest, ...rest]) {
        final chunks = await archive.openObject(key, object.id).toList();
        expect(chunks.every((c) => c.length <= 128 * 1024), true);
        final restored = BytesBuilder(copy: false);
        for (final chunk in chunks) {
          restored.add(chunk);
        }
        final value = restored.takeBytes();
        expect(value.length, object.size);
        expect(
          base64Encode((await Sha256().hash(value)).bytes),
          object.sha256Base64,
        );
        expect(
          value,
          object.relativePath == '100/file.pdf'
              ? utf8.encode('PRIVATE_PICKER_SENTINEL')
              : data,
        );
      }

      expect(
        rows.last['hash'],
        base64Encode((await Sha256().hash(data)).bytes),
      );
      final raw = await archive.archiveFile.readAsBytes();
      expect(
        utf8.decode(raw, allowMalformed: true),
        isNot(contains('PRIVATE_PICKER_SENTINEL')),
      );
    },
  );
  test(
    'crash after durable archive preserves source and restart verifies same object without replacement',
    () async {
      final file = await source('300/file.bin', Uint8List(300000));
      final interrupted = LegacyPickerCacheArchive(
        vault,
        LocalVaultFiles(),
        checkpoint: (stage) {
          if (stage == 'pickerBeforeUnlink')
            throw StateError('Synthetic interruption');
        },
      );
      await expectLater(
        interrupted.preserve(
          key,
          roots: [LegacyPickerCacheRoot(picker, 'androidPicker')],
        ),
        throwsStateError,
      );
      expect(await file.exists(), true);
      expect(await archived(interrupted), hasLength(1));
      final resumed = LegacyPickerCacheArchive(vault, LocalVaultFiles());
      final report = await resumed.preserve(
        key,
        roots: [LegacyPickerCacheRoot(picker, 'androidPicker')],
      );
      expect(report.archivedFiles, 0);
      expect(report.removedFiles, 1);
      expect(await archived(resumed), hasLength(1));
      expect(await file.exists(), false);
    },
  );
  test(
    'changed source remains and old archive version survives retry',
    () async {
      final file = await source('400/file.txt', utf8.encode('old'));
      final archive = LegacyPickerCacheArchive(
        vault,
        LocalVaultFiles(),
        checkpoint: (stage) {
          if (stage == 'pickerArchiveDurable')
            file.writeAsStringSync('NEW_CONTENT', flush: true);
        },
      );
      await expectLater(
        archive.preserve(
          key,
          roots: [LegacyPickerCacheRoot(picker, 'androidPicker')],
        ),
        throwsA(isA<LocalVaultException>()),
      );
      expect(await file.readAsString(), 'NEW_CONTENT');
      final retry = LegacyPickerCacheArchive(vault, LocalVaultFiles());
      await retry.preserve(
        key,
        roots: [LegacyPickerCacheRoot(picker, 'androidPicker')],
      );
      expect(await archived(retry), hasLength(2));
    },
  );
  test(
    'unknown iOS exports remain explicit residual; exact known hash staging is protected',
    () async {
      final docs = Directory('${root.path}/Documents');
      await docs.create();
      final unknown = File('${docs.path}/user-export.pdf');
      await unknown.writeAsString('USER_EXPORT');
      final known = File('${docs.path}/original-name.txt');
      await known.writeAsString('KNOWN_IMPORT');
      final hash = base64Encode(
        (await Sha256().hash(utf8.encode('KNOWN_IMPORT'))).bytes,
      );
      final archive = LegacyPickerCacheArchive(vault, LocalVaultFiles());
      final report = await archive.preserve(
        key,
        roots: [LegacyPickerCacheRoot(docs, 'iosDocuments')],
        knownContentHashes: {hash},
      );
      expect(await unknown.exists(), true);
      expect(await known.exists(), false);
      expect(report.retainedFiles, 1);
      expect(report.containsRetainedPlaintext, true);
    },
  );
  test(
    'read consumers never initialize a missing or malformed archive',
    () async {
      final archive = LegacyPickerCacheArchive(vault, LocalVaultFiles());
      expect(await archive.listObjects(key), isEmpty);
      expect(await archive.archiveFile.exists(), false);
      await vault.create();
      final derived = await key.derive('legacy-picker-cache-archive');
      final bytes = Uint8List.fromList(await derived.extractBytes());
      final db = sqlite3.open(archive.archiveFile.path);
      try {
        LocalVaultCipher.configure(db, bytes);
        db.execute('CREATE TABLE unrelated(value TEXT)');
      } finally {
        db.close();
        bytes.fillRange(0, bytes.length, 0);
        derived.destroy();
      }
      final before = await archive.archiveFile.readAsBytes();
      await expectLater(
        archive.listObjects(key),
        throwsA(isA<LocalVaultException>()),
      );
      expect(await archive.archiveFile.readAsBytes(), before);
    },
  );
  test(
    'symlink escape never deletes the external original or follows linked tree',
    () async {
      final outside = File('${root.path}/outside.txt');
      await outside.writeAsString('KEEP');
      final folder = Directory('${picker.path}/500');
      await folder.create();
      await Link('${folder.path}/escape.txt').create(outside.path);
      final archive = LegacyPickerCacheArchive(vault, LocalVaultFiles());
      await expectLater(
        archive.preserve(
          key,
          roots: [LegacyPickerCacheRoot(picker, 'androidPicker')],
        ),
        throwsA(isA<LocalVaultException>()),
      );
      expect(await outside.readAsString(), 'KEEP');
    },
  );
}
