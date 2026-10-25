import '../domain/collaboration_models.dart';
import '../domain/shared_record_permissions.dart';

/// UI projection only; repository and signed protocol independently authorize.
bool canEditSharedRecord(
  CollaborationState? state,
  String? scopeId,
  String type,
  String id, {
  String domain = 'content',
}) {
  if (state?.localAccessAllowed != true || state?.session == null) return false;
  final scope = state!.scopes.where((s) => s.id == scopeId).firstOrNull;
  if (scope == null) return false;
  final data = state.dataForScope(scope.id);
  return SharedRecordPermissions.canEdit(
    scope: scope,
    accountId: state.session!.accountId,
    creator: data.recordCreators['$domain:$id'],
    type: type,
    assignees: type == 'task'
        ? data.tasks.where((t) => t.id == id).firstOrNull?.assigneeAccountIds ??
              const []
        : const [],
  );
}
