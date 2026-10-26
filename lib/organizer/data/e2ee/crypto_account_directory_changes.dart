import 'account_directory_repository.dart';

/// Replays only a signed directory prefix. It never delivers pending account
/// commands, creates observations or completes a setup/recovery workflow.
Future<bool> refreshVerifiedAccountDirectoryJournal(
  AccountDirectoryRepository directory,
) async {
  final before = await directory.cachedVerifiedDirectory();
  final after = await directory.withoutRetainedAuthority(
    directory.requireFresh,
  );
  // snapshotHash includes the full verified state (including keyring entries),
  // while journal-only events change generation/headHash without changing it.
  return before.snapshotHash != after.snapshotHash ||
      before.deviceSnapshotHash != after.deviceSnapshotHash ||
      before.identityEpochId != after.identityEpochId;
}
