import 'collaboration_database.dart';
import '../domain/collaboration_models.dart';
import 'organizer_repository.dart' show OrganizerConflictException;

/// The storage binding, not a possibly loading UI provider, determines whether
/// a local-looking entry belongs to connected private sync.
Future<void> authorizeConnectedPersonalEntry(
  CollaborationDatabase database,
  Future<void> Function(AccountSession profile) authorize,
) async {
  final generation=database.personalIdentityGeneration;
  final workspace=database.selectedLocalWorkspaceId;
  final profile=database.personalProfile;
  if(workspace!='local' || profile==null)return;
  final rows=await database.rows('SELECT scope_id,paused FROM personal_workspaces WHERE id=? AND partition=? AND enabled=1',['private:${profile.partition}',profile.partition]);
  if(rows.isEmpty)return;
  await authorize(profile);
  final current=database.personalProfile;
  if(generation!=database.personalIdentityGeneration || workspace!=database.selectedLocalWorkspaceId ||
    current==null || current.partition!=profile.partition || current.deviceId!=profile.deviceId) {
    throw const OrganizerConflictException('Connected workspace changed');
  }
  final after=await database.rows('SELECT scope_id,paused FROM personal_workspaces WHERE id=? AND partition=? AND enabled=1',['private:${profile.partition}',profile.partition]);
  if(after.length!=1 || after.single['scope_id']!=rows.single['scope_id'] || after.single['paused']!=rows.single['paused'])throw const OrganizerConflictException('Connected workspace changed');
}
