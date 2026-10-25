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
  Future<void> archiveProject(LocalProject project, {bool archived = true});
  Future<void> deleteProject(LocalProject project);
  Future<void> task({LocalTask? task, String? projectId});
  Future<void> shoppingList([LocalShoppingList? list]);
  Future<void> shoppingItem(String listId, [LocalShoppingItem? item]);
  Future<void> createShoppingItem({
    required String listId,
    required String title,
    String quantity = '1',
  });
  Future<void> setShoppingItemChecked(String id, bool value);
  Future<void> setTaskCompleted(String id, bool value);
}

/// Optional record-specific capability view; local collections keep their
/// existing behavior while shared collections use verified provenance.
abstract interface class OrganizerRecordPermissionActions {
  bool get canCreateRecords;
  bool canEditRecord(String type, String id);
  bool canDeleteRecord(String type, String id);
  bool get canCheckShoppingItems;
  Future<void> openTask(LocalTask task);
}

extension OrganizerCollectionPermissions on OrganizerCollectionActions {
  Future<void> openTask(LocalTask task) =>
      this is OrganizerRecordPermissionActions
      ? (this as OrganizerRecordPermissionActions).openTask(task)
      : this.task(task: task);
  bool get canCreateRecords =>
      this is! OrganizerRecordPermissionActions ||
      (this as OrganizerRecordPermissionActions).canCreateRecords;
  bool canEditRecord(String type, String id) =>
      this is! OrganizerRecordPermissionActions ||
      (this as OrganizerRecordPermissionActions).canEditRecord(type, id);
  bool canDeleteRecord(String type, String id) =>
      this is! OrganizerRecordPermissionActions ||
      (this as OrganizerRecordPermissionActions).canDeleteRecord(type, id);
  bool get canCheckShoppingItems =>
      this is! OrganizerRecordPermissionActions ||
      (this as OrganizerRecordPermissionActions).canCheckShoppingItems;
}
