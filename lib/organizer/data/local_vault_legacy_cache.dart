import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'local_vault.dart';
import 'local_vault_cipher.dart';
import 'local_vault_files.dart';
import 'local_vault_keys.dart';
import 'local_vault_snapshot.dart';
import 'organizer_storage.dart' show OrganizerBackupCodec;

class LegacyPickerCacheReport {
  const LegacyPickerCacheReport(
    this.archivedFiles,
    this.removedFiles,
    this.retainedFiles,
  );
  final int archivedFiles, removedFiles, retainedFiles;
  bool get hasResidualCopies => retainedFiles > 0;
  bool get containsRetainedPlaintext => hasResidualCopies;
}

class LegacyPickerArchivedObject {
  const LegacyPickerArchivedObject({
    required this.id,
    required this.sourceKind,
    required this.relativePath,
    required this.size,
    required this.sha256Base64,
  });
  final String id, sourceKind, relativePath, sha256Base64;
  final int size;
}

/// Roots must come from the native app sandbox, never a user selected folder.
/// iOS unknown exports are intentionally retained and reported.
class LegacyPickerCacheRoot {
  const LegacyPickerCacheRoot(this.directory, this.kind);
  final Directory directory;
  final String kind; // androidPicker | iosTemporary | iosDocuments
}

/// Append-only encrypted preservation of old plugin staging copies. File names
/// and paths exist only inside this encrypted archive. Call under the existing
/// installation OS lease, before declaring startup migration complete.
class LegacyPickerCacheArchive {
  LegacyPickerCacheArchive(
    this.vaultDirectory,
    this.files, {
    this.checkpoint,
    this.maxFileBytes = 64 * 1024 * 1024,
  });
  final Directory vaultDirectory;
  final LocalVaultFiles files;
  final void Function(String stage)? checkpoint;
  // Matches the reachable per-file encrypted export consumer. Larger originals
  // remain untouched and explicitly keep installation cleanup pending.
  final int maxFileBytes;
  File get archiveFile =>
      File(p.join(vaultDirectory.path, 'picker-legacy.sqlite'));

  /// Bounded read-only consumer for installation recovery/export. The source
  /// names remain app-relative; exporting never recreates their old plaintext
  /// paths or installs a command/draft automatically.
  Future<List<LegacyPickerArchivedObject>> listObjects(
    LocalVaultKey key, {
    String? afterId,
    int limit = 50,
  }) async {
    if (limit < 1 || limit > 50)
      throw const LocalVaultException('vault_archive_limit');
    await files.rejectLink(archiveFile.path);
    if (!await archiveFile.exists()) return [];
    final derived = await key.derive('legacy-picker-cache-archive');
    final bytes = Uint8List.fromList(await derived.extractBytes());
    Database? db;
    try {
      db = _open(bytes, readOnly: true);
      return [
        for (final row in db.select(
          'SELECT * FROM objects WHERE id>? ORDER BY id LIMIT ?',
          [afterId ?? '', limit],
        ))
          LegacyPickerArchivedObject(
            id: row['id'] as String,
            sourceKind: row['source_kind'] as String,
            relativePath: row['relative_path'] as String,
            size: row['size'] as int,
            sha256Base64: row['hash'] as String,
          ),
      ];
    } finally {
      db?.close();
      bytes.fillRange(0, bytes.length, 0);
      derived.destroy();
    }
  }

  /// Verifies the complete authenticated object before releasing any plaintext.
  /// The caller owns yielded chunks and must put exports in its protected
  /// container or explicit user destination, never an automatic temp copy.
  Stream<Uint8List> openObject(LocalVaultKey key, String id) async* {
    await files.rejectLink(archiveFile.path);
    if (!await archiveFile.exists())
      throw const LocalVaultException('vault_archive_missing');
    final derived = await key.derive('legacy-picker-cache-archive');
    final bytes = Uint8List.fromList(await derived.extractBytes());
    Database? db;
    try {
      db = _open(bytes, readOnly: true);
      final rows = db.select('SELECT size,hash FROM objects WHERE id=?', [id]);
      if (rows.length != 1)
        throw const LocalVaultException('vault_archive_missing');
      await _verify(
        db,
        id,
        rows.single['size'] as int,
        rows.single['hash'] as String,
      );
      var sequence = 0;
      while (true) {
        final chunks = db.select(
          'SELECT bytes FROM chunks WHERE id=? AND sequence=?',
          [id, sequence++],
        );
        if (chunks.isEmpty) break;
        final chunk = chunks.single['bytes'] as Uint8List;
        if (chunk.length > 128 * 1024)
          throw const LocalVaultException('vault_archive_invalid');
        yield Uint8List.fromList(chunk);
      }
    } finally {
      db?.close();
      bytes.fillRange(0, bytes.length, 0);
      derived.destroy();
    }
  }

  Future<LegacyPickerCacheReport> preserve(
    LocalVaultKey key, {
    required List<LegacyPickerCacheRoot> roots,
    Set<String> knownContentHashes = const {},
    Set<String> dedicatedStoragePaths = const {},
  }) async {
    await files.privateDirectory(vaultDirectory);
    await files.rejectLink(archiveFile.path);
    final derived = await key.derive('legacy-picker-cache-archive');
    final bytes = Uint8List.fromList(await derived.extractBytes());
    var archived = 0, removed = 0, retained = 0;
    try {
      final dedicated = <String>{};
      for (final path in dedicatedStoragePaths) {
        await files.rejectLink(path);
        final file = File(path);
        if (await file.exists()) {
          dedicated.add(p.normalize(await file.resolveSymbolicLinks()));
        }
      }
      for (final source in roots) {
        if (!const {
          'androidPicker',
          'iosTemporary',
          'iosDocuments',
        }.contains(source.kind))
          throw const LocalVaultException('vault_unsafe_path');
        await files.rejectLink(source.directory.path);
        if (!await source.directory.exists()) continue;
        final root = p.normalize(await source.directory.resolveSymbolicLinks());
        // Android plugin owns only millis/name. iOS arbitrary subdirectories
        // are not assumed to belong to the picker and are never traversed.
        await for (final entity in Directory(root).list(followLinks: false)) {
          if (entity is Link)
            throw const LocalVaultException('vault_unsafe_path');
          if (p.normalize(entity.path) ==
              p.normalize(vaultDirectory.absolute.path))
            continue;
          // These exact files remain subject to the separate vault database /
          // Hive archive and cleanup checks. Never infer ownership by extension
          // or ignore a plugin directory merely because its name looks known.
          if (dedicated.contains(p.normalize(p.absolute(entity.path)))) {
            await files.rejectLink(entity.path);
            continue;
          }
          if (entity is Directory &&
              await entity.list(followLinks: false).isEmpty) {
            continue;
          }
          if (source.kind == 'androidPicker' &&
              entity is Directory &&
              RegExp(r'^\d+$').hasMatch(p.basename(entity.path))) {
            await for (final nested in entity.list(followLinks: false)) {
              if (nested is Link)
                throw const LocalVaultException('vault_unsafe_path');
              if (nested is! File) {
                retained++;
                continue;
              }
              await _safeFile(root, nested);
              if (await nested.length() > maxFileBytes) {
                retained++;
                continue;
              }
              final result = await _preserveOne(
                bytes,
                source.kind,
                root,
                nested,
              );
              archived += result.$1;
              removed += result.$2;
            }
          } else if (source.kind != 'androidPicker' && entity is File) {
            await _safeFile(root, entity);
            if (await entity.length() > maxFileBytes) {
              retained++;
              continue;
            }
            final identifiedExport = await _knownExport(entity);
            String? digest;
            if (!identifiedExport &&
                knownContentHashes.isNotEmpty &&
                await entity.length() <= maxFileBytes) {
              digest = base64Encode(
                (await localVaultHashStream(entity.openRead())).bytes,
              );
            }
            if (!identifiedExport && !knownContentHashes.contains(digest)) {
              retained++;
              continue;
            }
            final result = await _preserveOne(
              bytes,
              source.kind,
              root,
              entity,
              expectedHash: digest,
            );
            archived += result.$1;
            removed += result.$2;
          } else {
            retained++;
          }
        }
      }
      return LegacyPickerCacheReport(archived, removed, retained);
    } finally {
      bytes.fillRange(0, bytes.length, 0);
      derived.destroy();
    }
  }

  Future<void> _safeFile(String root, File file) async {
    final path = p.normalize(p.absolute(file.path));
    if (!p.isWithin(root, path))
      throw const LocalVaultException('vault_unsafe_path');
    var cursor = path;
    while (cursor != root) {
      await files.rejectLink(cursor);
      final parent = p.dirname(cursor);
      if (parent == cursor)
        throw const LocalVaultException('vault_unsafe_path');
      cursor = parent;
    }
    if (p.normalize(await file.resolveSymbolicLinks()) != path)
      throw const LocalVaultException('vault_unsafe_path');
  }

  Future<bool> _knownExport(File file) async {
    final name = p.basename(file.path);
    final personal = RegExp(
      r'^jivie-personal-\d{4}-\d{2}-\d{2}\.json$',
    ).hasMatch(name);
    final unsent = RegExp(
      r'^jivie-unsynced-\d{4}-\d{2}-\d{2}\.json$',
    ).hasMatch(name);
    if ((!personal && !unsent) ||
        await file.length() > OrganizerBackupCodec.maxBytes)
      return false;
    try {
      final text = await file.readAsString();
      if (personal) {
        OrganizerBackupCodec.decodeDocument(text);
        return true;
      }
      final value = jsonDecode(text);
      if (value is! Map ||
          value['format'] != 'vsakdan-unsent-work' ||
          !const [1, 2].contains(value['schemaVersion']) ||
          value['account'] is! Map)
        return false;
      final fields = {
        'format',
        'schemaVersion',
        'account',
        'operations',
        'conflicts',
        'commands',
        'financeOperations',
        if (value['schemaVersion'] == 2) ...{'ideaDrafts', 'ideaAssets'},
      };
      return value.length == fields.length &&
          value.keys.every(fields.contains) &&
          fields
              .difference({'format', 'schemaVersion', 'account'})
              .every((name) => value[name] is List);
    } on FormatException {
      return false;
    } on TypeError {
      return false;
    }
  }

  Database _open(Uint8List key, {bool readOnly = false}) {
    final db = sqlite3.open(
      archiveFile.path,
      mode: readOnly ? OpenMode.readOnly : OpenMode.readWriteCreate,
    );
    try {
      LocalVaultCipher.configure(db, key);
      if (readOnly) {
        final expected = <String, List<String>>{
          'objects': ['id', 'source_kind', 'relative_path', 'size', 'hash'],
          'chunks': ['id', 'sequence', 'bytes'],
        };
        for (final table in expected.entries) {
          final columns = db.select('PRAGMA table_info(${table.key})');
          if (columns.length != table.value.length ||
              columns.asMap().entries.any(
                (e) => e.value['name'] != table.value[e.key],
              ))
            throw const LocalVaultException('vault_archive_invalid');
        }
        return db;
      }
      db.execute('PRAGMA journal_mode=DELETE');
      db.execute('''CREATE TABLE IF NOT EXISTS objects(
        id TEXT PRIMARY KEY,source_kind TEXT NOT NULL,relative_path TEXT NOT NULL,
        size INTEGER NOT NULL,hash TEXT NOT NULL)''');
      db.execute('''CREATE TABLE IF NOT EXISTS chunks(
        id TEXT NOT NULL,sequence INTEGER NOT NULL,bytes BLOB NOT NULL,
        PRIMARY KEY(id,sequence))''');
      return db;
    } catch (_) {
      db.close();
      rethrow;
    }
  }

  Future<(int, int)> _preserveOne(
    Uint8List key,
    String kind,
    String root,
    File file, {
    String? expectedHash,
  }) async {
    await _safeFile(root, file);
    final before = await file.stat();

    final hash =
        expectedHash ??
        base64Encode((await localVaultHashStream(file.openRead())).bytes);
    final relative = p
        .relative(file.path, from: root)
        .split(p.separator)
        .join('/');
    final id = base64Encode(
      (await Sha256().hash(utf8.encode('$kind\n$relative\n$hash'))).bytes,
    );
    var fresh = false;
    final db = _open(key);
    try {
      final old = db.select('SELECT * FROM objects WHERE id=?', [id]);
      if (old.isEmpty) {
        db.execute('BEGIN IMMEDIATE');
        try {
          final handle = await file.open();
          final sink = Sha256().newHashSink();
          var size = 0, sequence = 0;
          try {
            while (true) {
              final chunk = await handle.read(128 * 1024);
              if (chunk.isEmpty) break;
              sink.add(chunk);
              size += chunk.length;
              db.execute('INSERT INTO chunks VALUES(?,?,?)', [
                id,
                sequence++,
                chunk,
              ]);
            }
          } finally {
            await handle.close();
          }
          sink.close();
          if (size != before.size ||
              base64Encode((await sink.hash()).bytes) != hash)
            throw const LocalVaultException('vault_source_changed');
          db.execute('INSERT INTO objects VALUES(?,?,?,?,?)', [
            id,
            kind,
            relative,
            size,
            hash,
          ]);
          await _verify(db, id, size, hash);
          db.execute('COMMIT');
          fresh = true;
        } catch (_) {
          db.execute('ROLLBACK');
          rethrow;
        }
      } else {
        if (old.single['source_kind'] != kind ||
            old.single['relative_path'] != relative ||
            old.single['size'] != before.size ||
            old.single['hash'] != hash)
          throw const LocalVaultException('vault_archive_invalid');
        await _verify(db, id, before.size, hash);
      }
    } finally {
      db.close();
    }
    await files.flush(archiveFile);
    await files.syncDirectory(vaultDirectory);
    checkpoint?.call('pickerArchiveDurable');
    // Read durable ciphertext after close+fsync, not just the write connection.
    final check = _open(key, readOnly: true);
    try {
      await _verify(check, id, before.size, hash);
    } finally {
      check.close();
    }
    await _safeFile(root, file);
    final after = await file.stat();
    if (before.size != after.size ||
        before.modified != after.modified ||
        hash !=
            base64Encode((await localVaultHashStream(file.openRead())).bytes))
      throw const LocalVaultException('vault_source_changed');
    checkpoint?.call('pickerBeforeUnlink');
    await files.delete(file);
    return (fresh ? 1 : 0, 1);
  }

  Future<void> _verify(
    Database db,
    String id,
    int expectedSize,
    String expectedHash,
  ) async {
    final statement = db.prepare(
      'SELECT sequence,bytes FROM chunks WHERE id=? ORDER BY sequence',
    );
    final sink = Sha256().newHashSink();
    var size = 0, sequence = 0;
    try {
      final cursor = statement.selectCursor([id]);
      while (cursor.moveNext()) {
        if (cursor.current['sequence'] != sequence++)
          throw const LocalVaultException('vault_archive_invalid');
        final bytes = cursor.current['bytes'] as Uint8List;
        size += bytes.length;
        sink.add(bytes);
      }
      sink.close();
      if (size != expectedSize ||
          base64Encode((await sink.hash()).bytes) != expectedHash)
        throw const LocalVaultException('vault_archive_invalid');
    } finally {
      statement.close();
    }
  }
}
