import 'package:kanban/organizer/state/portable_backup_provider.dart';

/// Navigation tests use an empty archive catalog without opening a native DB.
/// Backup behavior has its own repository and wizard fixtures.
class EmptyBackupUiController extends PortableBackupController {
  @override
  Future<void> build() async {}

  @override
  Future<List<BackupPreview>> listRestoredBackups() async => [];
}
