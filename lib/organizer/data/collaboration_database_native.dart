import 'collaboration_database.dart';
import 'local_vault_native.dart';

Future<CollaborationDatabase> openCollaborationDatabase() async {
  return (await openLocalVaultService()).openDatabase();
}
