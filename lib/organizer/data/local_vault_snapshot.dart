import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:sqlite3/sqlite3.dart';

import 'local_vault.dart';
import 'local_vault_cipher.dart';

/// Logical proof deliberately avoids model round-trips. Unknown tables, raw
/// UTF-8 bytes, SQLite storage classes, implicit rowids and sqlite_sequence are
/// included. Physical page addresses/freelist layout are not logical data.
abstract final class LocalVaultSnapshot {
  static const _pragmas = [
    'user_version',
    'application_id',
    'schema_version',
    'encoding',
    'page_size',
    'auto_vacuum',
  ];
  static String quote(String value) => '"${value.replaceAll('"', '""')}"';

  static Future<String> fingerprint(Database db) async {
    final hash = await localVaultHashStream(_content(db));
    return base64Encode(hash.bytes);
  }

  static Stream<List<int>> _content(Database db) async* {
    for (final name in _pragmas) {
      yield utf8.encode(
        '$name:${db.select('PRAGMA $name').single.values.single}\n',
      );
    }
    final schema = db.select(
      'SELECT type,name,tbl_name,sql FROM sqlite_schema ORDER BY type,name',
    );
    for (final row in schema) {
      yield utf8.encode('${jsonEncode(row.values.toList())}\n');
    }
    final tableInfo = db.select('PRAGMA table_list');
    for (final table in schema.where((r) => r['type'] == 'table')) {
      final name = table['name'] as String;
      final sql = table['sql'] as String? ?? '';
      if (RegExp(
        r'^CREATE\s+VIRTUAL\s+TABLE',
        caseSensitive: false,
      ).hasMatch(sql)) {
        throw const LocalVaultException('vault_schema_unsupported');
      }
      final columns = db.select('PRAGMA table_xinfo(${quote(name)})');
      final names = columns.map((r) => r['name'] as String).toList();
      final withoutRowid = tableInfo.any(
        (r) => r['name'] == name && r['wr'] == 1,
      );
      final aliases = [
        '_rowid_',
        'rowid',
        'oid',
      ].where((a) => !names.any((n) => n.toLowerCase() == a));
      if (!withoutRowid && aliases.isEmpty) {
        throw const LocalVaultException('vault_schema_unsupported');
      }
      final rowid = withoutRowid ? null : aliases.first;
      final fields = [
        if (rowid != null) rowid,
        for (final col in names) ...[
          'typeof(${quote(col)})',
          // Cast TEXT to BLOB to preserve invalid/unknown UTF-8 byte sequences.
          'CASE WHEN typeof(${quote(col)})=\'text\' THEN CAST(${quote(col)} AS BLOB) ELSE ${quote(col)} END',
        ],
      ];
      final order = rowid ?? names.map(quote).join(',');
      final statement = db.prepare(
        'SELECT ${fields.join(',')} FROM ${quote(name)} ORDER BY $order',
      );
      yield utf8.encode('table:${jsonEncode(name)}:${jsonEncode(names)}\n');
      try {
        final cursor = statement.selectCursor();
        while (cursor.moveNext()) {
          for (final value in cursor.current.values) {
            if (value == null) {
              yield [0];
            } else if (value is Uint8List) {
              yield utf8.encode('b${value.length}:');
              yield value;
            } else if (value is double) {
              yield [2];
              yield (ByteData(
                8,
              )..setFloat64(0, value, Endian.big)).buffer.asUint8List();
            } else {
              final bytes = utf8.encode(value.toString());
              yield utf8.encode('s${bytes.length}:');
              yield bytes;
            }
          }
          yield [10];
        }
      } finally {
        statement.close();
      }
    }
  }

  static void check(Database db) {
    final result = db.select('PRAGMA integrity_check');
    if (result.length != 1 || result.single.values.single != 'ok') {
      throw const LocalVaultException('vault_integrity');
    }
    if ((db.select('PRAGMA user_version').single.values.single as int) > 11) {
      throw const LocalVaultException('vault_schema_unsupported');
    }
  }

  /// VACUUM INTO is the cipher maintainer's supported direct encrypted export.
  /// An outer writer fence must remain held from fingerprint through switch.
  /// No plaintext temporary database or rekey is used.
  static void export(Database source, File target, Uint8List key) {
    if (target.existsSync()) {
      throw const LocalVaultException('vault_candidate_exists');
    }
    if (source.select('PRAGMA cipher').isEmpty) {
      throw const LocalVaultException('vault_cipher_unavailable');
    }
    source.execute('PRAGMA temp_store = MEMORY');
    final hex = key.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    final uri = target.uri.replace(
      queryParameters: {
        'cipher': 'chacha20',
        'legacy': '0',
        'kdf_iter': '${LocalVaultCipher.kdfIterations}',
        'plaintext_header_size': '0',
        'hmac_check': '1',
        'mc_legacy_wal': '0',
        'key': 'raw:$hex',
      },
    );
    try {
      source.execute('VACUUM INTO ?', [uri.toString()]);
    } catch (_) {
      // SQLite exceptions can contain the bound secret URI. Never expose them.
      throw const LocalVaultException('vault_export_failed');
    }
  }
}

Future<Hash> localVaultHashStream(Stream<List<int>> stream) async {
  final sink = Sha256().newHashSink();
  await for (final bytes in stream) {
    sink.add(bytes);
  }
  sink.close();
  return sink.hash();
}
