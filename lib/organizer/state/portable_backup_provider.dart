import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/portable_backup_repository.dart';
import '../data/sqlite_organizer_storage.dart';
import '../data/organizer_storage.dart';
import 'local_database_provider.dart';
import 'collaboration_provider.dart';
export '../data/portable_backup_repository.dart' show BackupUiPreferencesStore;
export '../domain/private_sync_models.dart';

final backupUiPreferencesProvider = Provider<BackupUiPreferencesStore>(
  (ref) => MemoryBackupUiPreferencesStore(),
);
final portableBackupRepositoryProvider =
    FutureProvider<PortableBackupRepository>((ref) async {
      final db = await ref.watch(localDatabaseProvider.future);
      final storage = SqliteOrganizerStorage(
        db,
        legacyFactory: HiveOrganizerStorage.open,
      );
      await storage.initialize();
      final repository = PortableBackupRepository(
        db,
        storage,
        ref.watch(backupUiPreferencesProvider),
        collaboration: () =>
            ref.read(collaborationRepositoryProvider).asData?.value,
      );
      await repository.applyPendingUiPreferences();
      return repository;
    });
final portableBackupProvider =
    AsyncNotifierProvider<PortableBackupController, void>(
      PortableBackupController.new,
    );

class PortableBackupController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {
    await ref.watch(portableBackupRepositoryProvider.future);
  }

  Future<PortableBackupRepository> get _repo =>
      ref.read(portableBackupRepositoryProvider.future);
  Future<Uint8List> exportEncryptedBackup(String password) async =>
      (await _repo).exportEncryptedBackup(password);
  Future<BackupPreview> inspectEncryptedBackup(
    List<int> bytes,
    String password,
  ) async => (await _repo).inspectEncryptedBackup(bytes, password);
  Future<void> validatePreparedExport(String id) async =>
      (await _repo).validatePreparedExport(id);
  Future<BackupRestoreResult> restoreEncryptedBackup(
    List<int> bytes,
    String password, {
    required BackupRestoreMode mode,
    required int expectedPersonalRevision,
  }) async => (await _repo).restoreEncryptedBackup(
    bytes,
    password,
    mode: mode,
    expectedPersonalRevision: expectedPersonalRevision,
  );
  Future<List<BackupPreview>> listRestoredBackups() async =>
      (await _repo).listRestoredBackups();
  Future<BackupRecoveryReview> reviewRestoredWork(
    String id,
    String password,
  ) async => (await _repo).reviewRestoredWork(id, password);
  Future<void> resumeRestoredWork(
    String id, {
    required String password,
  }) async => (await _repo).resumeRestoredWork(id, password: password);
}
