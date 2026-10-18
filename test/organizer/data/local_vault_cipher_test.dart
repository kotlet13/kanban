import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/local_vault_cipher.dart';
import 'package:kanban/organizer/data/local_vault.dart';
import 'package:sqlite3/sqlite3.dart';

class _FailingKeyDatabase implements Database {
  _FailingKeyDatabase(this.delegate);
  final Database delegate;
  @override
  void execute(String sql, [List<Object?> parameters = const []]) {
    if (sql.startsWith('PRAGMA key')) throw StateError('SQLITE failure: $sql');
    delegate.execute(sql, parameters);
  }

  @override
  ResultSet select(String sql, [List<Object?> parameters = const []]) =>
      delegate.select(sql, parameters);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('cipher configuration failures never expose key-bearing SQL', () {
    final database = sqlite3.openInMemory();
    addTearDown(database.close);
    final key = Uint8List.fromList(List.generate(32, (i) => i + 1));
    final hex = key.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    try {
      LocalVaultCipher.configure(_FailingKeyDatabase(database), key);
      fail('Expected sanitized failure');
    } catch (error) {
      expect(
        error.toString(),
        'LocalVaultException(vault_cipher_configuration)',
      );
      expect(error.toString(), isNot(contains(hex)));
      expect(error.toString(), isNot(contains('PRAGMA')));
    }
  });
  test(
    'real cipher directly backs up plaintext into authenticated target',
    () async {
      final directory = await Directory.systemTemp.createTemp('jivie-cipher-');
      addTearDown(() => directory.delete(recursive: true));
      final plain = sqlite3.open('${directory.path}/source.sqlite', uri: true);
      plain.execute(
        'CREATE TABLE unknown(id INTEGER PRIMARY KEY, payload TEXT, bytes BLOB)',
      );
      plain.execute('INSERT INTO unknown VALUES(1,?,?)', [
        'private sentinel 784c68',
        Uint8List.fromList([0, 1, 255]),
      ]);
      plain.execute('CREATE TABLE implicit(payload)');
      plain.execute(
        "INSERT INTO implicit(rowid,payload) VALUES(1,'first'),(900,'last')",
      );
      final target = File('${directory.path}/encrypted.sqlite');
      final key = Uint8List.fromList(List.generate(32, (i) => i + 1));
      final hex = key.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      final uri = target.uri.replace(
        queryParameters: {
          'cipher': 'chacha20',
          'legacy': '0',
          'kdf_iter': '64007',
          'plaintext_header_size': '0',
          'key': 'raw:$hex',
        },
      );
      plain.execute('VACUUM INTO ?', [uri.toString()]);
      plain.close();
      expect(
        String.fromCharCodes(await target.readAsBytes()),
        isNot(contains('private sentinel')),
      );
      final reopened = sqlite3.open(target.path);
      LocalVaultCipher.configure(reopened, key);
      expect(
        reopened.select('SELECT payload FROM unknown').single['payload'],
        'private sentinel 784c68',
      );
      expect(
        reopened.select('PRAGMA integrity_check').single.values.single,
        'ok',
      );
      expect(
        reopened
            .select('SELECT rowid,payload FROM implicit')
            .map((r) => r['rowid'])
            .toList(),
        [1, 900],
      );
      reopened.close();
      final wrong = sqlite3.open(target.path);
      expect(
        () {
          LocalVaultCipher.configure(wrong, Uint8List(32));
          wrong.select('SELECT * FROM sqlite_schema');
        },
        throwsA(
          isA<LocalVaultException>().having(
            (e) => e.code,
            'code',
            'vault_cipher_configuration',
          ),
        ),
      );
      wrong.close();
    },
  );
}
