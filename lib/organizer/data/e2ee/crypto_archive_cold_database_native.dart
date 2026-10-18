import 'dart:io';

import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sodium/sodium.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

import '../collaboration_database.dart';
import '../local_vault_cipher.dart';
import '../local_vault_files.dart';

/// A newly encrypted isolated restore database, with a transient random key.
/// Closing removes only this factory's private random directory. Authoritative
/// source/ciphertext journals remain in the installation vault throughout.
class CryptoArchiveColdDatabase {
  CryptoArchiveColdDatabase._(this.database, this._directory);
  final CollaborationDatabase database;
  final Directory _directory;
  static Future<CryptoArchiveColdDatabase> create({Directory? parent}) async {
    final files = LocalVaultFiles();
    final root =
        parent ??
        Directory(
          '${(await getApplicationSupportDirectory()).path}/jivie_cold_restore',
        );
    await files.privateDirectory(root);
    final directory = await root.createTemp('restore-');
    await files.privateDirectory(directory);
    final sodium = await SodiumInit.init();
    final key = sodium.secureRandom(32);
    final raw = key.extractBytes();
    sql.Database? native;
    CollaborationDatabase? managed;
    try {
      native = sql.sqlite3.open('${directory.path}/restore.sqlite');
      LocalVaultCipher.configure(native, raw);
      native.execute('PRAGMA journal_mode=DELETE');
      final database = CollaborationDatabase(NativeDatabase.opened(native));
      managed = database;
      native = null;
      await database.rows('SELECT 1');
      await files.flush(File('${directory.path}/restore.sqlite'));
      return CryptoArchiveColdDatabase._(database, directory);
    } catch (_) {
      // Cleanup must not obscure the actual storage/cipher failure. Close the
      // managed handle too if schema initialization failed after ownership moved.
      try {
        await managed?.close();
      } catch (_) {}
      try {
        native?.close();
      } catch (_) {}
      try {
        await directory.delete(recursive: true);
      } catch (_) {}
      rethrow;
    } finally {
      raw.fillRange(0, raw.length, 0);
      key.dispose();
    }
  }

  Future<void> close() async {
    await database.close();
    await _directory.delete(recursive: true);
    await LocalVaultFiles().syncDirectory(_directory.parent);
  }
}
