import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart';

import 'local_vault.dart';

/// Installation format 1. Raw random keys bypass passphrase derivation; the
/// explicit KDF setting is retained as part of the pinned file format.
abstract final class LocalVaultCipher {
  static const format = 'sqlite3mc-chacha20-poly1305-v1';
  static const kdfIterations = 64007;

  static void configure(Database db, Uint8List key) {
    try {
      _configure(db, key);
    } on LocalVaultException {
      rethrow;
    } catch (_) {
      // SQLite errors can contain the PRAGMA text and raw installation key.
      throw const LocalVaultException('vault_cipher_configuration');
    }
  }

  static void _configure(Database db, Uint8List key) {
    if (key.length != 32) throw const LocalVaultException('vault_key_invalid');
    if (db.select('PRAGMA cipher').isEmpty) {
      throw const LocalVaultException('vault_cipher_unavailable');
    }
    db.execute("PRAGMA cipher = 'chacha20'");
    db.execute('PRAGMA legacy = 0');
    db.execute('PRAGMA kdf_iter = $kdfIterations');
    db.execute('PRAGMA plaintext_header_size = 0');
    db.execute('PRAGMA hmac_check = 1');
    db.execute('PRAGMA mc_legacy_wal = 0');
    db.execute('PRAGMA memory_security = 1');
    final hex = key.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    // Only locally generated fixed-length hexadecimal enters this statement.
    // Never pass this SQL or its exception text to logging/reporting services.
    db.execute("PRAGMA key = 'raw:$hex'");
    if (db.select('PRAGMA cipher').single.values.single.toString() !=
            'chacha20' ||
        db.select('PRAGMA hmac_check').single.values.single.toString() != '1' ||
        db.select('PRAGMA legacy').single.values.single.toString() != '0' ||
        db
                .select('PRAGMA plaintext_header_size')
                .single
                .values
                .single
                .toString() !=
            '0') {
      throw const LocalVaultException('vault_cipher_parameters');
    }
    db.execute('PRAGMA temp_store = MEMORY');
    db.execute('PRAGMA synchronous = FULL');
    db.execute('PRAGMA busy_timeout = 5000');
  }
}
