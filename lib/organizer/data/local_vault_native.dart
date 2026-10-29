import '../platform/private_file_io.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:drift/native.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:sqlite3/sqlite3.dart';

import 'collaboration_database.dart';
import 'local_vault.dart';
import 'local_vault_cipher.dart';
import 'local_vault_files.dart';
import 'local_vault_keys.dart';
import 'local_vault_preferences.dart';
import 'local_vault_snapshot.dart';
import 'local_vault_legacy_cache.dart';
import 'preserved_installation_files.dart';
import 'package:path/path.dart' as path;
import 'local_vault_secure_storage.dart';
import 'organizer_storage.dart' show OrganizerBackupCodec;

Future<NativeLocalVaultService>? _defaultService;
Future<NativeLocalVaultService> openLocalVaultService() => _defaultService ??=
    () async {
      if (Platform.isIOS || Platform.isMacOS) {
        try {
          final protected = await const MethodChannel(
            'jivie/local_vault',
          ).invokeMethod<bool>('protectLocalStorage');
          if (protected != true) throw const FormatException();
        } catch (_) {
          throw const LocalVaultException('vault_backup_policy');
        }
      }
      await cleanPrivateFileStaging();
      final documents = await getApplicationDocumentsDirectory();
      final service = NativeLocalVaultService(
        documents,
        const SecureLocalVaultKeyStore(),
        preferences: await SharedPreferences.getInstance(),
        pickerRoots: await _nativeLegacyPickerRoots(),
        legacySecretProtection: Platform.isIOS || Platform.isMacOS
            ? protectExistingLocalVaultSecrets
            : null,
        hasRetainedSecrets: () async =>
            (await localVaultSecureStorage.readAll()).keys.any(
              (key) => key != SecureLocalVaultKeyStore.key,
            ),
      );
      await service.protectSecretsAtStartup();
      await service.preserveLegacyPickerCaches();
      return service;
    }().catchError((Object error, StackTrace stack) {
      _defaultService = null;
      Error.throwWithStackTrace(error, stack);
    });

Future<List<LegacyPickerCacheRoot>> _nativeLegacyPickerRoots() async {
  if (!Platform.isAndroid && !Platform.isIOS) return [];
  final roots = await const PrivateFileChannel().legacyPickerRoots();
  final expected = Platform.isAndroid
      ? {'androidPicker'}
      : {'iosTemporary', 'iosDocuments'};
  if (roots.length != expected.length ||
      !roots.keys.every(expected.contains) ||
      roots.values.any((p) => !path.isAbsolute(p))) {
    throw const LocalVaultException('vault_unsafe_path');
  }
  return [
    for (final entry in roots.entries)
      LegacyPickerCacheRoot(Directory(entry.value), entry.key),
  ];
}

Future<LocalVaultPreferences> openLocalVaultPreferences() async =>
    (await openLocalVaultService()).openPreferences();

/// All public mutations are serialized by an OS lease that also covers other
/// isolates/processes. Open database handles retain a shared lease until close.
class NativeLocalVaultService
    implements LocalVaultService, LocalVaultFreshSetup {
  NativeLocalVaultService(
    this.directory,
    this.keyStore, {
    required this.preferences,
    LocalVaultFiles? files,
    this.checkpoint,
    this.pickerRoots = const [],
    this.legacySecretProtection,
    this.hasRetainedSecrets,
  }) : files = files ?? LocalVaultFiles();
  final Directory directory;
  final LocalVaultKeyStore keyStore;
  final SharedPreferences preferences;
  final LocalVaultFiles files;
  final List<LegacyPickerCacheRoot> pickerRoots;
  final Future<void> Function()? legacySecretProtection;
  final Future<bool> Function()? hasRetainedSecrets;

  /// Every cold bootstrap, including an already-complete journal, protects old
  /// Apple credentials before inspect/session consumers can open. The same
  /// installation lease serializes migration and retry across processes.
  Future<void> protectSecretsAtStartup() async {
    final protection = legacySecretProtection;
    if (protection != null) await _exclusive(protection);
  }

  final void Function(String stage)? checkpoint;
  EncryptedLocalVaultPreferences? _privatePreferences;
  Directory get vaultDirectory => Directory('${directory.path}/jivie_vault_v1');
  File get _journal => File('${vaultDirectory.path}/state.json');
  File get _lock => File('${vaultDirectory.path}/installation.lock');
  File get sourceFile => File('${directory.path}/organizer_shared_v1.sqlite');
  File get databaseFile => File('${vaultDirectory.path}/data.sqlite');
  File get _candidate => File('${vaultDirectory.path}/candidate.sqlite');
  File get archiveFile => File('${vaultDirectory.path}/legacy.sqlite');
  File get _archiveCandidate =>
      File('${vaultDirectory.path}/legacy.next.sqlite');
  static const _phases = {
    'keyPrepared',
    'recoveryVerified',
    'candidateVerified',
    'switched',
    'complete',
    'freshPrepared',
    'freshKeyIntent',
  };

  Future<T> _exclusive<T>(Future<T> Function() action) async {
    await files.privateDirectory(vaultDirectory);
    final lease = await files.lock(_lock);
    try {
      return await action();
    } on LocalVaultException {
      rethrow;
    } catch (_) {
      // Raw SQLite exceptions may contain secret bound parameters.
      throw const LocalVaultException('vault_io');
    } finally {
      await lease.close();
    }
  }

  Future<Map<String, dynamic>?> _state() async {
    await files.rejectLink(_journal.path);
    if (!await _journal.exists()) return null;
    try {
      if (await _journal.length() > 16384) throw const FormatException();
      final state =
          jsonDecode(await _journal.readAsString()) as Map<String, dynamic>;
      if (state['format'] != 'jivie-local-vault' ||
          state['version'] != 1 ||
          state['cipher'] != LocalVaultCipher.format ||
          !_phases.contains(state['phase']) ||
          (const {'freshPrepared', 'freshKeyIntent'}.contains(state['phase']) &&
              state['setupMode'] != 'fresh') ||
          state['vaultId'] is! String ||
          state['probe'] is! Map) {
        throw const FormatException();
      }
      return state;
    } catch (_) {
      throw const LocalVaultException('vault_journal_invalid');
    }
  }

  Future<void> _save(Map<String, dynamic> state, String phase) async {
    state['phase'] = phase;
    await files.writeJournal(_journal, state);
    checkpoint?.call(phase);
  }

  Future<LocalVaultKey> _key(Map<String, dynamic> state) async {
    final encoded = await keyStore.read();
    if (encoded == null) {
      throw const LocalVaultException('vault_recovery_required');
    }
    final key = LocalVaultKey.decode(encoded);
    if (key.id != state['vaultId']) {
      throw const LocalVaultException('vault_recovery_required');
    }
    await key.verifyProbe(Map<String, dynamic>.from(state['probe'] as Map));
    return key;
  }

  /// Fail closed for every retained file or preference. Empty directories may
  /// be platform-created, but their contents never qualify as a fresh install.
  Future<bool> _emptyDirectory(
    Directory root, {
    bool vault = false,
    bool freshIntent = false,
  }) async {
    await files.rejectLink(root.path);
    if (!await root.exists()) return true;
    await for (final entity in root.list(followLinks: false)) {
      await files.rejectLink(entity.path);
      if (path.normalize(entity.absolute.path) ==
          path.normalize(vaultDirectory.absolute.path)) {
        continue;
      }
      if (vault && entity.absolute.path == _lock.absolute.path) continue;
      if (vault &&
          freshIntent &&
          entity.absolute.path == _journal.absolute.path) {
        continue;
      }
      if (entity is! Directory || !await _emptyDirectory(entity)) return false;
    }
    return true;
  }

  bool _hasFreshPreferences() => preferences.getKeys().every((name) {
    if (const {'app_locale_code', 'app_theme_mode'}.contains(name)) return true;
    if (name != 'window_width' && name != 'window_height') return false;
    final value = preferences.get(name);
    return value is double && value.isFinite && value > 0;
  });

  Future<bool> _hasFreshSources({bool freshIntent = false}) async =>
      _hasFreshPreferences() &&
      await _emptyDirectory(directory) &&
      await _emptyDirectory(
        vaultDirectory,
        vault: true,
        freshIntent: freshIntent,
      ) &&
      await _emptyPickerRoots();

  Future<bool> _emptyPickerRoots() async {
    for (final root in pickerRoots) {
      if (!await _emptyDirectory(root.directory)) return false;
    }
    return true;
  }

  Future<Map<String, dynamic>> _prepareFreshKey() async {
    final key = LocalVaultKey.generate();
    try {
      final state = <String, dynamic>{
        'format': 'jivie-local-vault',
        'version': 1,
        'vaultId': key.id,
        'cipher': LocalVaultCipher.format,
        'probe': await key.makeProbe(),
        'setupMode': 'fresh',
      };
      // Bind the later OS key to this empty installation before writing it.
      await _save(state, 'freshKeyIntent');
      await keyStore.write(key.encode());
      checkpoint?.call('freshKeyStored');
      await _save(state, 'freshPrepared');
      return state;
    } finally {
      key.bytes.fillRange(0, key.bytes.length, 0);
    }
  }

  @override
  Future<LocalVaultStatus> initializeFreshInstallation() =>
      _exclusive(() async {
        var state = await _state();
        if (state == null) {
          if (await keyStore.read() != null ||
              await hasRetainedSecrets?.call() == true ||
              !await _hasFreshSources()) {
            return inspect();
          }
          state = await _prepareFreshKey();
        }
        if (state['setupMode'] != 'fresh') return inspect();
        if (state['phase'] == 'freshKeyIntent') {
          if (await hasRetainedSecrets?.call() == true ||
              !await _hasFreshSources(freshIntent: true)) {
            throw const LocalVaultException('vault_source_changed');
          }
          if (await keyStore.read() == null) {
            // No encrypted candidate has ever existed in this phase. Replace
            // a stopped pre-store intent only after proving empty again.
            state = await _prepareFreshKey();
          } else {
            final key = await _key(state);
            try {
              await _save(state, 'freshPrepared');
            } finally {
              key.bytes.fillRange(0, key.bytes.length, 0);
            }
          }
        }
        final status = await inspect();
        if (status.phase == LocalVaultPhase.recoveryRequired ||
            status.phase == LocalVaultPhase.ready) {
          return status;
        }
        return _migrateUnlocked();
      });

  @override
  Future<LocalVaultStatus> inspect() async {
    final state = await _state();
    if (state == null) {
      if (await databaseFile.exists() || await archiveFile.exists()) {
        throw const LocalVaultException('vault_journal_missing');
      }
      return const LocalVaultStatus(LocalVaultPhase.needsSetup);
    }
    try {
      final key = await _key(state);
      if (state['phase'] == 'switched' || state['phase'] == 'complete') {
        final db = _openExisting(databaseFile, key.bytes);
        try {
          LocalVaultSnapshot.check(db);
        } finally {
          db.close();
        }
        final installationComplete =
            state['phase'] == 'complete' &&
            (await _legacyFiles()).isEmpty &&
            state['pickerCleanupPending'] == false &&
            state['pickerResidualFiles'] is int &&
            (state['pickerResidualFiles'] as int) >= 0 &&
            !EncryptedLocalVaultPreferences.keys.any(preferences.containsKey);
        final residual = state['pickerResidualFiles'] as int? ?? 0;
        return LocalVaultStatus(
          installationComplete && residual == 0
              ? LocalVaultPhase.ready
              : LocalVaultPhase.cleanupPending,
          vaultId: key.id,
          errorCode: residual > 0 ? 'vault_historical_exports_retained' : null,
          retainedCopiesOnly: installationComplete && residual > 0,
        );
      }
    } on LocalVaultException catch (error) {
      if (!{
        'vault_recovery_required',
        'vault_secure_storage',
        'vault_recovery_mismatch',
        'vault_recovery_invalid',
      }.contains(error.code)) {
        rethrow;
      }
      return LocalVaultStatus(
        LocalVaultPhase.recoveryRequired,
        vaultId: state['vaultId'] as String,
        errorCode: error.code,
      );
    }
    return LocalVaultStatus(
      state['phase'] == 'keyPrepared'
          ? LocalVaultPhase.recoveryUnverified
          : LocalVaultPhase.migrationPending,
      vaultId: state['vaultId'] as String,
    );
  }

  @override
  Future<Uint8List> prepareRecoveryFile() async {
    // An active database holds a shared installation lease. Exporting its
    // existing key is read-only and must coexist with that lease, while still
    // excluding recovery/migration that could replace the key or journal.
    await files.privateDirectory(vaultDirectory);
    final lease = await files.lock(_lock, shared: true);
    try {
      final state = await _state();
      if (state != null) {
        final key = await _key(state);
        return Uint8List.fromList(utf8.encode(key.encode()));
      }
    } on LocalVaultException {
      rethrow;
    } catch (_) {
      throw const LocalVaultException('vault_io');
    } finally {
      await lease.close();
    }
    // Initial key preparation still mutates storage. Re-read under exclusive
    // ownership: another caller may have prepared it after our shared read.
    return _exclusive(() async {
      var state = await _state();
      LocalVaultKey key;
      if (state == null) {
        if (await databaseFile.exists() || await archiveFile.exists()) {
          throw const LocalVaultException('vault_journal_missing');
        }
        final existing = await keyStore.read();
        key = existing == null
            ? LocalVaultKey.generate()
            : LocalVaultKey.decode(existing);
        await keyStore.write(key.encode());
        checkpoint?.call('keyStored');
        state = {
          'format': 'jivie-local-vault',
          'version': 1,
          'vaultId': key.id,
          'cipher': LocalVaultCipher.format,
          'probe': await key.makeProbe(),
        };
        await _save(state, 'keyPrepared');
      } else {
        key = await _key(state);
      }
      return Uint8List.fromList(utf8.encode(key.encode()));
    });
  }

  Future<LocalVaultKey> _verifyBytes(
    Uint8List bytes,
    Map<String, dynamic> state,
  ) async {
    if (bytes.length > 64 * 1024) {
      throw const LocalVaultException('vault_recovery_invalid');
    }
    final key = LocalVaultKey.decode(utf8.decode(bytes));
    if (key.id != state['vaultId']) {
      throw const LocalVaultException('vault_recovery_mismatch');
    }
    await key.verifyProbe(Map<String, dynamic>.from(state['probe'] as Map));
    return key;
  }

  @override
  Future<LocalVaultStatus> verifyRecoveryFile(
    Uint8List bytes,
  ) => _exclusive(() async {
    final state = await _state();
    if (state == null) throw const LocalVaultException('vault_setup_required');
    final key = await _verifyBytes(bytes, state);
    final stored = await _key(state);
    if (base64Encode(stored.bytes) != base64Encode(key.bytes)) {
      throw const LocalVaultException('vault_recovery_mismatch');
    }
    if (state['phase'] == 'keyPrepared') await _save(state, 'recoveryVerified');
    return inspect();
  });

  @override
  Future<LocalVaultStatus> recover(Uint8List bytes) => _exclusive(() async {
    final state = await _state();
    if (state == null) throw const LocalVaultException('vault_journal_missing');
    final key = await _verifyBytes(bytes, state);
    if (state['phase'] == 'switched' || state['phase'] == 'complete') {
      final db = _openExisting(databaseFile, key.bytes);
      try {
        LocalVaultSnapshot.check(db);
      } finally {
        db.close();
      }
    }
    await keyStore.write(key.encode());
    if (state['phase'] == 'keyPrepared') await _save(state, 'recoveryVerified');
    if ({'switched', 'complete'}.contains(state['phase'])) {
      await _preservePickerCaches(state, key);
      await _save(state, state['phase'] as String);
    }
    return inspect();
  });

  Database _openExisting(File file, Uint8List key) {
    if (!file.existsSync() || file.lengthSync() == 0) {
      throw const LocalVaultException('vault_database_missing');
    }
    final db = sqlite3.open(file.path, mode: OpenMode.readWrite, uri: true);
    try {
      LocalVaultCipher.configure(db, key);
      db.select('SELECT count(*) FROM sqlite_schema');
      return db;
    } catch (_) {
      db.close();
      throw const LocalVaultException('vault_unlock_failed');
    }
  }

  Future<List<File>> _legacyFiles() async {
    final paths = [
      sourceFile.path,
      '${sourceFile.path}-wal',
      '${sourceFile.path}-shm',
      '${sourceFile.path}-journal',
      for (final ext in ['hive', 'hivec', 'lock'])
        '${directory.path}/organizer_personal_v1.$ext',
    ];
    final found = <File>[];
    for (final path in paths) {
      await files.rejectLink(path);
      final file = File(path);
      if (await file.exists()) found.add(file);
    }
    return found;
  }

  Future<void> _validateHive(List<File> originals) async {
    final hive =
        originals.where((f) => f.path.endsWith('.hive')).firstOrNull ??
        originals.where((f) => f.path.endsWith('.hivec')).firstOrNull;
    if (hive == null) return;
    if (await hive.length() > 128 * 1024 * 1024) {
      throw const LocalVaultException('vault_legacy_too_large');
    }
    final box = await Hive.openBox<String>(
      'vault_validate_${DateTime.now().microsecondsSinceEpoch}',
      bytes: await hive.readAsBytes(),
      crashRecovery: false,
    );
    try {
      final value = box.get('committed_snapshot');
      if (value != null) OrganizerBackupCodec.decodeDocument(value);
    } catch (_) {
      throw const LocalVaultException('vault_legacy_invalid');
    } finally {
      await box.close();
    }
  }

  Future<void> _archive(List<File> originals, LocalVaultKey key) async {
    await files.delete(_archiveCandidate);
    final db = await _openArchive(key, candidate: _archiveCandidate);
    try {
      db.execute(
        'CREATE TABLE files(name TEXT PRIMARY KEY,size INTEGER NOT NULL,hash TEXT NOT NULL)',
      );
      db.execute(
        'CREATE TABLE chunks(name TEXT NOT NULL,sequence INTEGER NOT NULL,bytes BLOB NOT NULL,PRIMARY KEY(name,sequence))',
      );
      for (final file in originals) {
        final name = file.uri.pathSegments.last;
        var count = 0, sequence = 0;
        final sink = Sha256().newHashSink();
        await for (final bytes in file.openRead()) {
          count += bytes.length;
          sink.add(bytes);
          db.execute('INSERT INTO chunks VALUES(?,?,?)', [
            name,
            sequence++,
            Uint8List.fromList(bytes),
          ]);
        }
        sink.close();
        final hash = base64Encode((await sink.hash()).bytes);
        db.execute('INSERT INTO files VALUES(?,?,?)', [name, count, hash]);
        if (count != await file.length() ||
            !file.path.endsWith('-shm') &&
                hash !=
                    base64Encode(
                      (await localVaultHashStream(file.openRead())).bytes,
                    )) {
          throw const LocalVaultException('vault_source_changed');
        }
      }
      final values = {
        for (final name in EncryptedLocalVaultPreferences.keys)
          if (preferences.containsKey(name)) name: preferences.get(name),
      };
      final bytes = utf8.encode(jsonEncode(values));
      db.execute('INSERT INTO files VALUES(?,?,?)', [
        'private_preferences.json',
        bytes.length,
        base64Encode((await Sha256().hash(bytes)).bytes),
      ]);
      db.execute('INSERT INTO chunks VALUES(?,?,?)', [
        'private_preferences.json',
        0,
        Uint8List.fromList(bytes),
      ]);
      LocalVaultSnapshot.check(db);
      // Read back every encrypted chunk, rather than trusting successful writes.
      for (final row in db.select('SELECT * FROM files')) {
        final chunks = db.prepare(
          'SELECT bytes FROM chunks WHERE name=? ORDER BY sequence',
        );
        final sink = Sha256().newHashSink();
        var count = 0;
        try {
          final cursor = chunks.selectCursor([row['name']]);
          while (cursor.moveNext()) {
            final bytes = cursor.current['bytes'] as Uint8List;
            count += bytes.length;
            sink.add(bytes);
          }
          sink.close();
          if (count != row['size'] ||
              base64Encode((await sink.hash()).bytes) != row['hash']) {
            throw const LocalVaultException('vault_archive_invalid');
          }
        } finally {
          chunks.close();
        }
      }
    } finally {
      db.close();
    }
    await files.flush(_archiveCandidate);
    await files.move(_archiveCandidate, archiveFile);
    checkpoint?.call('archiveVerified');
  }

  Future<void> _validateArchive(LocalVaultKey key) async {
    final db = await _openArchive(key);
    try {
      LocalVaultSnapshot.check(db);
      for (final row in db.select('SELECT * FROM files')) {
        final statement = db.prepare(
          'SELECT sequence,bytes FROM chunks WHERE name=? ORDER BY sequence',
        );
        final sink = Sha256().newHashSink();
        var length = 0, sequence = 0;
        try {
          final cursor = statement.selectCursor([row['name']]);
          while (cursor.moveNext()) {
            if (cursor.current['sequence'] != sequence++) {
              throw const LocalVaultException('vault_archive_invalid');
            }
            final bytes = cursor.current['bytes'] as Uint8List;
            length += bytes.length;
            sink.add(bytes);
          }
          sink.close();
          if (length != row['size'] ||
              base64Encode((await sink.hash()).bytes) != row['hash']) {
            throw const LocalVaultException('vault_archive_invalid');
          }
        } finally {
          statement.close();
        }
      }
      for (final file in await _legacyFiles()) {
        if (!file.path.endsWith('.hive') && !file.path.endsWith('.hivec')) {
          continue;
        }
        final manifest = db.select('SELECT size,hash FROM files WHERE name=?', [
          file.uri.pathSegments.last,
        ]).firstOrNull;
        if (manifest == null ||
            manifest['size'] != await file.length() ||
            manifest['hash'] !=
                base64Encode(
                  (await localVaultHashStream(file.openRead())).bytes,
                )) {
          throw const LocalVaultException('vault_source_changed');
        }
      }
    } finally {
      db.close();
    }
  }

  Future<Database> _openArchive(LocalVaultKey key, {File? candidate}) async {
    final derived = await key.derive('legacy-archive');
    final bytes = Uint8List.fromList(await derived.extractBytes());
    try {
      if (candidate == null) return _openExisting(archiveFile, bytes);
      final db = sqlite3.open(candidate.path);
      try {
        LocalVaultCipher.configure(db, bytes);
        return db;
      } catch (_) {
        db.close();
        rethrow;
      }
    } finally {
      bytes.fillRange(0, bytes.length, 0);
      derived.destroy();
    }
  }

  @override
  Future<LocalVaultStatus> migrate() => _exclusive(_migrateUnlocked);

  Future<LocalVaultStatus> _migrateUnlocked() async {
    final state = await _state();
    if (state == null ||
        const {'keyPrepared', 'freshKeyIntent'}.contains(state['phase'])) {
      throw const LocalVaultException('vault_recovery_unverified');
    }
    final key = await _key(state);
    if (state['setupMode'] == 'fresh' &&
        !{'switched', 'complete'}.contains(state['phase']) &&
        (!await _emptyDirectory(directory) ||
            !await _emptyPickerRoots() ||
            !_hasFreshPreferences())) {
      throw const LocalVaultException('vault_source_changed');
    }
    if (state['phase'] == 'complete') {
      if ((await inspect()).phase == LocalVaultPhase.ready) return inspect();
      // A stale/old runtime may have recreated an original. Never silently
      // delete a changed source or advertise complete protection in that case.
      state['phase'] = 'switched';
    }
    if (await databaseFile.exists() &&
        !{'candidateVerified', 'switched'}.contains(state['phase'])) {
      throw const LocalVaultException('vault_state_conflict');
    }
    Database? guard, source;
    try {
      if (state['phase'] != 'switched') {
        if (await sourceFile.exists()) {
          guard = sqlite3.open(
            sourceFile.path,
            mode: OpenMode.readWrite,
            uri: true,
          );
          guard.execute('PRAGMA busy_timeout = 1000');
          guard.execute('BEGIN IMMEDIATE');
          source = sqlite3.open(
            sourceFile.path,
            mode: OpenMode.readOnly,
            uri: true,
          );
        } else {
          source = sqlite3.open('file::memory:', uri: true);
        }
        source.execute('PRAGMA temp_store = MEMORY');
        LocalVaultSnapshot.check(source);
        final originals = await _legacyFiles();
        await _validateHive(originals);
        final fingerprint = await LocalVaultSnapshot.fingerprint(source);
        if (state['phase'] == 'candidateVerified' &&
            await databaseFile.exists()) {
          final target = _openExisting(databaseFile, key.bytes);
          try {
            if (state['fingerprint'] != fingerprint ||
                await LocalVaultSnapshot.fingerprint(target) != fingerprint) {
              throw const LocalVaultException('vault_source_changed');
            }
          } finally {
            target.close();
          }
        } else {
          await files.delete(_candidate);
          LocalVaultSnapshot.export(source, _candidate, key.bytes);
          final target = _openExisting(_candidate, key.bytes);
          try {
            // VACUUM may advance the internal schema cookie; restore it before
            // comparing. This is not a domain/schema upgrade.
            target.execute(
              'PRAGMA schema_version = ${source.select('PRAGMA schema_version').single.values.single}',
            );
            LocalVaultSnapshot.check(target);
            if (await LocalVaultSnapshot.fingerprint(target) != fingerprint) {
              throw const LocalVaultException('vault_copy_mismatch');
            }
          } finally {
            target.close();
          }
          await files.flush(_candidate);
          checkpoint?.call('encryptedCandidate');
          await _archive(originals, key);
          state['fingerprint'] = fingerprint;
          await _save(state, 'candidateVerified');
          await files.move(_candidate, databaseFile);
          checkpoint?.call('targetMoved');
        }
        await _save(state, 'switched');
      }
      // No plaintext SQLite handle may outlive cleanup (notably on Windows).
      // The installation OS lease remains exclusive throughout this step.
      source?.close();
      source = null;
      if (guard != null) {
        guard.execute('ROLLBACK');
        guard.close();
        guard = null;
      }
      // After switched is durable, this source can never become authoritative
      // again, even if new writes precede a later cleanup retry.
      final target = _openExisting(databaseFile, key.bytes);
      try {
        LocalVaultSnapshot.check(target);
      } finally {
        target.close();
      }
      if (!await archiveFile.exists()) {
        throw const LocalVaultException('vault_archive_missing');
      }
      await _validateArchive(key);
      if (keyStore is SecureLocalVaultKeyStore &&
          !Platform.isIOS &&
          !Platform.isMacOS) {
        await protectExistingLocalVaultSecrets();
      }
      if (await sourceFile.exists()) {
        final remainingSource = sqlite3.open(
          sourceFile.path,
          mode: OpenMode.readOnly,
          uri: true,
        );
        try {
          remainingSource.execute('PRAGMA temp_store = MEMORY');
          if (await LocalVaultSnapshot.fingerprint(remainingSource) !=
              state['fingerprint']) {
            throw const LocalVaultException('vault_source_changed');
          }
        } finally {
          remainingSource.close();
        }
      }
      _privatePreferences = await EncryptedLocalVaultPreferences.open(
        preferences,
        key,
        migrateLegacy: true,
      );
      checkpoint?.call('preferencesProtected');
      for (final original in await _legacyFiles()) {
        await files.delete(original);
        checkpoint?.call('legacyDeleted');
      }
      await _preservePickerCaches(state, key);
      await _save(state, 'complete');
      return await inspect();
    } finally {
      source?.close();
      if (guard != null) {
        guard.execute('ROLLBACK');
        guard.close();
      }
    }
  }

  /// Called before application data opens, under the same installation lease.
  Future<void> preserveLegacyPickerCaches() => _exclusive(() async {
    final state = await _state();
    if (state == null || !{'switched', 'complete'}.contains(state['phase']))
      return;
    LocalVaultKey key;
    try {
      key = await _key(state);
    } on LocalVaultException catch (error) {
      if (const {
        'vault_recovery_required',
        'vault_secure_storage',
        'vault_recovery_mismatch',
        'vault_recovery_invalid',
      }.contains(error.code))
        return;
      rethrow;
    }
    await _preservePickerCaches(state, key);
    await _save(state, state['phase'] as String);
  });

  Future<void> _preservePickerCaches(
    Map<String, dynamic> state,
    LocalVaultKey key,
  ) async {
    state['pickerCleanupPending'] = true;
    await files.writeJournal(_journal, state);
    final report =
        await LegacyPickerCacheArchive(
          vaultDirectory,
          files,
          checkpoint: checkpoint,
        ).preserve(
          key,
          roots: pickerRoots,
          dedicatedStoragePaths: {
            // These are independently retained/verified by the legacy database and
            // Hive migration. inspect() still refuses ready while any remain.
            for (final original in await _legacyFiles()) original.absolute.path,
          },
        );
    state['pickerResidualFiles'] = report.retainedFiles;
    state['pickerCleanupPending'] = false;
  }

  Future<T> _readPreserved<T>(Future<T> Function() read) async {
    final lease = await files.lock(_lock, shared: true);
    try {
      return await read();
    } finally {
      await lease.close();
    }
  }

  Future<List<PreservedInstallationFile>> listPreservedFiles({
    String? afterId,
  }) => _readPreserved(() async {
    final state = await _state();
    if (state == null || !{'switched', 'complete'}.contains(state['phase'])) {
      throw const LocalVaultException('vault_setup_required');
    }
    return [
      for (final object in await LegacyPickerCacheArchive(
        vaultDirectory,
        files,
      ).listObjects(await _key(state), afterId: afterId))
        PreservedInstallationFile(
          object.id,
          path.basename(object.relativePath),
          object.size,
        ),
    ];
  });

  Future<Uint8List> readPreservedFile(String id) => _readPreserved(() async {
    final state = await _state();
    if (state == null || !{'switched', 'complete'}.contains(state['phase'])) {
      throw const LocalVaultException('vault_setup_required');
    }
    final archive = LegacyPickerCacheArchive(vaultDirectory, files);
    final key = await _key(state);
    // Export one reviewed file at a time, within the native private file transfer bound.
    final result = BytesBuilder(copy: false);
    var total = 0;
    await for (final chunk in archive.openObject(key, id)) {
      total += chunk.length;
      if (total > 64 * 1024 * 1024) throw const BackupFileBound();
      result.add(chunk);
    }
    return result.takeBytes();
  });

  Future<LocalVaultPreferences> openPreferences() async {
    if (_privatePreferences != null) return _privatePreferences!;
    final status = await inspect();
    if (!status.canOpenDatabase) {
      throw const LocalVaultException('vault_setup_required');
    }
    return _privatePreferences = await EncryptedLocalVaultPreferences.open(
      preferences,
      await _key((await _state())!),
    );
  }

  Future<Uint8List?> readLegacyHiveBytes() async {
    final state = await _state();
    if (state == null || !{'switched', 'complete'}.contains(state['phase'])) {
      throw const LocalVaultException('vault_setup_required');
    }
    final key = await _key(state);
    final db = await _openArchive(key);
    try {
      for (final name in [
        'organizer_personal_v1.hive',
        'organizer_personal_v1.hivec',
      ]) {
        final row = db.select('SELECT size,hash FROM files WHERE name=?', [
          name,
        ]).firstOrNull;
        if (row == null) continue;
        if ((row['size'] as int) > 128 * 1024 * 1024) {
          throw const LocalVaultException('vault_legacy_too_large');
        }
        final builder = BytesBuilder(copy: false);
        for (final chunk in db.select(
          'SELECT bytes FROM chunks WHERE name=? ORDER BY sequence',
          [name],
        )) {
          builder.add(chunk['bytes'] as Uint8List);
        }
        final bytes = builder.takeBytes();
        if (bytes.length != row['size'] ||
            base64Encode((await Sha256().hash(bytes)).bytes) != row['hash']) {
          throw const LocalVaultException('vault_archive_invalid');
        }
        return bytes;
      }
      return null;
    } finally {
      db.close();
    }
  }

  Future<CollaborationDatabase> openDatabase() async {
    await files.privateDirectory(vaultDirectory);
    final lease = await files.lock(_lock, shared: true);
    try {
      final status = await inspect();
      if (!status.canOpenDatabase) {
        throw LocalVaultException(
          status.phase == LocalVaultPhase.recoveryRequired
              ? 'vault_recovery_required'
              : 'vault_setup_required',
        );
      }
      final key = await _key((await _state())!);
      final bytes = Uint8List.fromList(key.bytes);
      return _VaultDatabase(
        NativeDatabase.createInBackground(
          databaseFile,
          setup: (db) {
            try {
              LocalVaultCipher.configure(db, bytes);
              db.select('SELECT count(*) FROM sqlite_schema');
            } catch (_) {
              throw const LocalVaultException('vault_unlock_failed');
            }
          },
        ),
        lease,
      );
    } catch (_) {
      await lease.close();
      rethrow;
    }
  }
}

class _VaultDatabase extends CollaborationDatabase {
  _VaultDatabase(super.executor, this.lease);
  final LocalVaultFileLease lease;
  @override
  Future<void> close() async {
    try {
      await super.close();
    } finally {
      await lease.close();
    }
  }
}

class _NativePreservedInstallationFiles implements PreservedInstallationFiles {
  _NativePreservedInstallationFiles(this.service);
  final NativeLocalVaultService service;
  @override
  Future<List<PreservedInstallationFile>> list({String? afterId}) =>
      service.listPreservedFiles(afterId: afterId);
  @override
  Future<Uint8List> read(String id) => service.readPreservedFile(id);
}

Future<PreservedInstallationFiles> openPreservedInstallationFiles() async =>
    _NativePreservedInstallationFiles(await openLocalVaultService());
