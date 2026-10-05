import 'package:drift/wasm.dart';
import '../domain/collaboration_models.dart';
import 'collaboration_database.dart';

Future<CollaborationDatabase> openCollaborationDatabase() async {
  final result = await WasmDatabase.open(
    databaseName: 'organizer_shared_v1',
    sqlite3Uri: Uri.parse('sqlite3.wasm'),
    driftWorkerUri: Uri.parse('drift_worker.js'),
  );
  if (result.chosenImplementation ==
          WasmStorageImplementation.unsafeIndexedDb ||
      result.chosenImplementation == WasmStorageImplementation.inMemory) {
    await result.resolvedExecutor.close();
    throw const CollaborationException('durable_storage_unavailable');
  }
  return CollaborationDatabase(result.resolvedExecutor);
}
