import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/collaboration_database.dart';
import '../data/collaboration_database_open.dart';

final collaborationDatabaseFactoryProvider =
    Provider<Future<CollaborationDatabase> Function()>(
      (ref) => openCollaborationDatabase,
    );

/// Database opening never depends on credentials, an account or the network.
final localDatabaseProvider = FutureProvider<CollaborationDatabase>((
  ref,
) async {
  final opening = ref.watch(collaborationDatabaseFactoryProvider)();
  ref.onDispose(
    () =>
        opening.then((db) => db.close(), onError: (Object _, StackTrace __) {}),
  );
  return opening;
});
