import '../domain/organizer_models.dart';

/// UI action contract shared by personal and collaboration views. Implementors
/// choose the controller; widgets never switch persistence or account identity.
abstract interface class OrganizerCollectionActions {
  String errorMessage(Object error);
  Future<void> run(Future<void> Function() action);
  Future<void> project([
    LocalProject? project,
    ProjectArea area = ProjectArea.personal,
  ]);
  Future<void> task({LocalTask? task, String? projectId});
  Future<void> shoppingList([LocalShoppingList? list]);
  Future<void> shoppingItem(String listId, [LocalShoppingItem? item]);
  Future<void> createShoppingItem({
    required String listId,
    required String title,
  });
  Future<void> setShoppingItemChecked(String id, bool value);
  Future<void> setTaskCompleted(String id, bool value);
}
