// Standalone synthetic AOT probe; never opens application or user paths.
import 'dart:io';
import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart';

import 'package:kanban/organizer/data/local_vault_cipher.dart';
import 'package:kanban/organizer/data/local_vault.dart';

void require(bool condition, String code) {
  if (!condition) throw StateError(code);
}

void main(List<String> arguments) {
  if (arguments.contains('--expect-unavailable')) {
    final database = sqlite3.openInMemory();
    try {
      LocalVaultCipher.configure(database, Uint8List(32));
      throw StateError('mismatched_engine_accepted');
    } on LocalVaultException catch (error) {
      require(
        error.code == 'vault_cipher_unavailable',
        'unexpected_engine_failure',
      );
      stdout.writeln('PASS mismatched engine rejected without asserts');
    } finally {
      database.close();
    }
    return;
  }
  final directory = Directory.systemTemp.createTempSync('jivie-cipher-aot-');
  try {
    final key = Uint8List.fromList(List.generate(32, (i) => i + 1));
    final file = File('${directory.path}/encrypted.sqlite');
    final db = sqlite3.open(file.path);
    LocalVaultCipher.configure(db, key);
    final settings = <String, Object?>{};
    for (final name in [
      'cipher',
      'legacy',
      'kdf_iter',
      'plaintext_header_size',
      'hmac_check',
      'mc_legacy_wal',
      'memory_security',
      'temp_store',
      'synchronous',
    ]) {
      final rows = db.select('PRAGMA $name');
      settings[name] = rows.isEmpty ? 'unavailable' : rows.single.values.single;
    }
    for (final expected in <String, String>{
      'cipher': 'chacha20',
      'legacy': '0',
      'kdf_iter': '64007',
      'plaintext_header_size': '0',
      'hmac_check': '1',
      'mc_legacy_wal': '0',
      'temp_store': '2',
      'synchronous': '2',
    }.entries) {
      require(
        settings[expected.key].toString() == expected.value,
        'parameter_mismatch',
      );
    }
    db.execute(
      'CREATE TABLE proof(id INTEGER PRIMARY KEY, value TEXT, bytes BLOB)',
    );
    db.execute('INSERT INTO proof VALUES(900,?,?)', [
      'synthetic-aot-secret-3915',
      Uint8List.fromList([0, 255, 1]),
    ]);
    db.close();
    require(
      !String.fromCharCodes(
        file.readAsBytesSync(),
      ).contains('synthetic-aot-secret-3915'),
      'plaintext_sentinel',
    );
    final reopened = sqlite3.open(file.path);
    LocalVaultCipher.configure(reopened, key);
    require(
      reopened.select('SELECT id FROM proof').single['id'] == 900,
      'data_mismatch',
    );
    require(
      reopened.select('PRAGMA integrity_check').single.values.single == 'ok',
      'integrity',
    );
    reopened.close();
    final wrong = sqlite3.open(file.path);
    var rejected = false;
    try {
      LocalVaultCipher.configure(wrong, Uint8List(32));
      wrong.select('SELECT * FROM proof');
    } catch (_) {
      rejected = true;
    } finally {
      wrong.close();
    }
    require(rejected, 'wrong_key_accepted');
    final plainEngine = Process.runSync('/usr/bin/sqlite3', [
      file.path,
      'SELECT * FROM proof',
    ]);
    require(plainEngine.exitCode != 0, 'ordinary_sqlite_accepted');
    stdout.writeln(
      'PASS encrypted reopen, sentinel absent, wrong key rejected, ordinary SQLite rejected; settings=$settings',
    );
  } finally {
    directory.deleteSync(recursive: true);
  }
}
