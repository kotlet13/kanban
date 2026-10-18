import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart' show Sha256;

import '../collaboration_database.dart';
import 'crypto_inventory_json.dart';

class CryptoArchiveColdRestoreResult {
  const CryptoArchiveColdRestoreResult({
    required this.inventoryHash,
    required this.rowCount,
    required this.fileCount,
    required this.fileBytes,
  });
  final String inventoryHash;
  final int rowCount, fileCount, fileBytes;
}

/// Restores typed raw source and files into a separate SQL database. This is
/// deliberately independent of business models/fromJson/toJson. It cannot
/// authorize live projections, erase source rows, or claim historical freshness.
class CryptoArchiveColdRestorer {
  CryptoArchiveColdRestorer(this.database);
  final CollaborationDatabase database;
  static const maxLineBytes = 32 * 1024 * 1024;
  Future<CryptoArchiveColdRestoreResult> restore({
    required Stream<List<int>> plaintext,
    required Map<String, dynamic> expectedHeader,
  }) async {
    final expectedInventory = Map<String, dynamic>.from(
      expectedHeader['inventory'] as Map,
    );
    final inventoryHash = await CryptoInventoryJson.hash(expectedInventory);
    if (expectedHeader['inventoryHash'] != inventoryHash) {
      throw const FormatException('crypto_archive_inventory');
    }
    await database.execute(
      'CREATE TABLE crypto_cold_rows(table_key TEXT NOT NULL,row_cursor INTEGER NOT NULL,raw TEXT NOT NULL,PRIMARY KEY(table_key,row_cursor))',
    );
    await database.execute(
      'CREATE TABLE crypto_cold_files(scope_id TEXT NOT NULL,file_index INTEGER NOT NULL,kind TEXT NOT NULL,id TEXT NOT NULL,descriptor TEXT NOT NULL,received INTEGER NOT NULL DEFAULT 0,PRIMARY KEY(scope_id,kind,id),UNIQUE(scope_id,file_index))',
    );
    await database.execute(
      'CREATE TABLE crypto_cold_file_chunks(scope_id TEXT NOT NULL,kind TEXT NOT NULL,id TEXT NOT NULL,chunk_offset INTEGER NOT NULL,bytes BLOB NOT NULL,PRIMARY KEY(scope_id,kind,id,chunk_offset))',
    );
    return database.transaction(() async {
      var headerSeen = false, footerSeen = false;
      await for (final line in _lines(plaintext)) {
        final value = jsonDecode(line);
        if (value is! Map<String, dynamic> ||
            value['kind'] is! String ||
            footerSeen) {
          throw const FormatException('crypto_archive_frame');
        }
        if (!headerSeen) {
          if (value['kind'] != 'header' ||
              CryptoInventoryJson.canonical(value) !=
                  CryptoInventoryJson.canonical(expectedHeader)) {
            throw const FormatException('crypto_archive_header');
          }
          headerSeen = true;
          continue;
        }
        switch (value['kind']) {
          case 'row':
            final key = '${value['table']}:${value['domain']}';
            final descriptor = (expectedInventory['tables'] as Map)[key];
            if (value.length != 5 ||
                descriptor is! Map ||
                value['index'] is! int ||
                value['index'] < 0 ||
                value['index'] >= descriptor['rows'] ||
                value['values'] is! Map) {
              throw const FormatException('crypto_archive_row');
            }
            final cells = value['values'] as Map;
            final columns = (descriptor['columns'] as List).cast<String>();
            if (cells.length != columns.length ||
                cells.keys.any((k) => !columns.contains(k))) {
              throw const FormatException('crypto_archive_columns');
            }
            for (final cell in cells.values) {
              if (cell is! Map ||
                  cell.length != 2 ||
                  cell['type'] is! String ||
                  !cell.containsKey('valueBase64') ||
                  (cell['valueBase64'] != null &&
                      !_base64(cell['valueBase64']))) {
                throw const FormatException('crypto_archive_cell');
              }
            }
            await database.execute(
              'INSERT INTO crypto_cold_rows VALUES(?,?,?)',
              [key, value['index'], CryptoInventoryJson.canonical(cells)],
            );
          case 'file':
            if (value.length != 4 ||
                value['scopeId'] is! String ||
                value['index'] is! int ||
                value['index'] < 0 ||
                value['descriptor'] is! Map ||
                !(expectedInventory['files'] as Map).containsKey(
                  value['scopeId'],
                )) {
              throw const FormatException('crypto_archive_file');
            }
            final descriptor = Map<String, dynamic>.from(
              value['descriptor'] as Map,
            );
            if (descriptor.length != 5 ||
                !['present', 'absent'].contains(descriptor['state']) ||
                descriptor['kind'] is! String ||
                descriptor['id'] is! String ||
                descriptor['size'] is! int ||
                descriptor['size'] < 0 ||
                (descriptor['state'] == 'present' &&
                    !_digest(descriptor['sha256'])) ||
                (descriptor['state'] == 'absent' &&
                    (descriptor['size'] != 0 ||
                        descriptor['sha256'] != null))) {
              throw const FormatException('crypto_archive_file');
            }
            await database.execute(
              'INSERT INTO crypto_cold_files(scope_id,file_index,kind,id,descriptor) VALUES(?,?,?,?,?)',
              [
                value['scopeId'],
                value['index'],
                descriptor['kind'],
                descriptor['id'],
                CryptoInventoryJson.canonical(descriptor),
              ],
            );
          case 'fileChunk':
            if (value.length != 6 ||
                value['scopeId'] is! String ||
                value['fileKind'] is! String ||
                value['id'] is! String ||
                value['offset'] is! int ||
                value['offset'] < 0 ||
                !_base64(value['dataBase64'])) {
              throw const FormatException('crypto_archive_file_chunk');
            }
            final key = [value['scopeId'], value['fileKind'], value['id']];
            final files = await database.rows(
              'SELECT * FROM crypto_cold_files WHERE scope_id=? AND kind=? AND id=?',
              key,
            );
            if (files.length != 1)
              throw const FormatException('crypto_archive_file_missing');
            final descriptor =
                jsonDecode(files.single['descriptor'] as String) as Map;
            final bytes = base64Decode(value['dataBase64'] as String);
            if (descriptor['state'] != 'present' ||
                value['offset'] != files.single['received'] ||
                bytes.isEmpty ||
                bytes.length > 196608 ||
                value['offset'] + bytes.length > descriptor['size']) {
              throw const FormatException('crypto_archive_file_chunk');
            }
            await database.execute(
              'INSERT INTO crypto_cold_file_chunks VALUES(?,?,?,?,?)',
              [...key, value['offset'], bytes],
            );
            await database.execute(
              'UPDATE crypto_cold_files SET received=? WHERE scope_id=? AND kind=? AND id=?',
              [value['offset'] + bytes.length, ...key],
            );
            bytes.fillRange(0, bytes.length, 0);
          case 'complete':
            if (value.length != 2 || value['inventoryHash'] != inventoryHash) {
              throw const FormatException('crypto_archive_footer');
            }
            footerSeen = true;
          default:
            throw const FormatException('crypto_archive_frame');
        }
      }
      if (!headerSeen || !footerSeen)
        throw const FormatException('crypto_archive_incomplete');
      var rowCount = 0, fileCount = 0, fileBytes = 0;
      for (final entry in (expectedInventory['tables'] as Map).entries) {
        final expected = entry.value as Map;
        final hash = Sha256().newHashSink();
        var count = 0, bytes = 0;
        while (true) {
          final page = await database.rows(
            'SELECT row_cursor,raw FROM crypto_cold_rows WHERE table_key=? AND row_cursor>=? ORDER BY row_cursor LIMIT 20',
            [entry.key, count],
          );
          if (page.isEmpty) break;
          for (final row in page) {
            if (row['row_cursor'] != count)
              throw const FormatException('crypto_archive_row_gap');
            final encoded = utf8.encode('${row['raw']}\n');
            hash.add(encoded);
            bytes += encoded.length;
            count++;
          }
        }
        hash.close();
        if (count != expected['rows'] ||
            bytes != expected['bytes'] ||
            _hex((await hash.hash()).bytes) != expected['sha256']) {
          throw const FormatException('crypto_archive_table_parity');
        }
        rowCount += count;
      }
      for (final entry in (expectedInventory['files'] as Map).entries) {
        final hash = Sha256().newHashSink();
        var index = 0, present = 0, absent = 0, bytes = 0;
        while (true) {
          final files = await database.rows(
            'SELECT * FROM crypto_cold_files WHERE scope_id=? AND file_index>=? ORDER BY file_index LIMIT 20',
            [entry.key, index],
          );
          if (files.isEmpty) break;
          for (final file in files) {
            if (file['file_index'] != index++)
              throw const FormatException('crypto_archive_file_gap');
            final descriptor = jsonDecode(file['descriptor'] as String) as Map;
            hash.add(utf8.encode('${file['descriptor']}\n'));
            if (descriptor['state'] == 'absent') {
              absent++;
              continue;
            }
            final fileHash = Sha256().newHashSink();
            var offset = 0;
            while (offset < descriptor['size']) {
              final chunk = await database.rows(
                'SELECT bytes FROM crypto_cold_file_chunks WHERE scope_id=? AND kind=? AND id=? AND chunk_offset=?',
                [entry.key, file['kind'], file['id'], offset],
              );
              if (chunk.length != 1)
                throw const FormatException('crypto_archive_file_gap');
              final data = chunk.single['bytes'] as List<int>;
              fileHash.add(data);
              offset += data.length;
            }
            fileHash.close();
            if (offset != descriptor['size'] ||
                file['received'] != offset ||
                _hex((await fileHash.hash()).bytes) != descriptor['sha256']) {
              throw const FormatException('crypto_archive_file_parity');
            }
            present++;
            bytes += offset;
          }
        }
        hash.close();
        final expected = entry.value as Map;
        if (present != expected['files'] ||
            absent != expected['absentRetired'] ||
            bytes != expected['bytes'] ||
            _hex((await hash.hash()).bytes) != expected['sha256']) {
          throw const FormatException('crypto_archive_files_parity');
        }
        fileCount += present;
        fileBytes += bytes;
      }
      return CryptoArchiveColdRestoreResult(
        inventoryHash: inventoryHash,
        rowCount: rowCount,
        fileCount: fileCount,
        fileBytes: fileBytes,
      );
    });
  }

  bool _base64(Object? value) {
    if (value is! String) return false;
    try {
      return base64Encode(base64Decode(value)) == value;
    } on FormatException {
      return false;
    }
  }

  bool _digest(Object? value) =>
      value is String && RegExp(r'^[a-f0-9]{64}$').hasMatch(value);
  String _hex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  Stream<String> _lines(Stream<List<int>> stream) async* {
    final buffer = BytesBuilder(copy: false);
    await for (final chunk in stream) {
      var start = 0;
      for (var i = 0; i < chunk.length; i++) {
        if (chunk[i] != 10) continue;
        if (buffer.length + i - start > maxLineBytes)
          throw const FormatException('crypto_archive_frame_size');
        buffer.add(chunk.sublist(start, i));
        final bytes = buffer.takeBytes();
        try {
          yield utf8.decode(bytes);
        } finally {
          bytes.fillRange(0, bytes.length, 0);
        }
        start = i + 1;
      }
      if (buffer.length + chunk.length - start > maxLineBytes)
        throw const FormatException('crypto_archive_frame_size');
      buffer.add(Uint8List.fromList(chunk.sublist(start)));
    }
    if (buffer.isNotEmpty)
      throw const FormatException('crypto_archive_frame_incomplete');
  }
}
