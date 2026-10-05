import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../state/portable_backup_provider.dart';

/// Replay a committed preferences journal after a crash. This opens only the
/// local database; unavailable credentials never block personal startup.
final backupPreferencesReplayProvider = FutureProvider<Map<String, Object?>>((
  ref,
) async {
  await ref.watch(portableBackupRepositoryProvider.future);
  return ref.read(backupUiPreferencesProvider).read();
});
