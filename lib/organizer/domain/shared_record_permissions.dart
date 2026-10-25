import 'collaboration_models.dart';

/// Record authority is separate from access to its scope and to finance.
abstract final class SharedRecordPermissions {
  static bool canEdit({
    required SharedScope scope,
    required String accountId,
    required String? creator,
    required String type,
    Iterable<String> assignees = const [],
  }) => scope.recordPolicyVersion == 0
      ? scope.canEdit
      : _access(scope) &&
            (scope.isOwner ||
                scope.verifiedParentOwner ||
                creator == accountId ||
                type == 'task' && assignees.contains(accountId));

  static bool canDelete({
    required SharedScope scope,
    required String accountId,
    required String? creator,
  }) => scope.recordPolicyVersion == 0
      ? scope.canEdit
      : _access(scope) &&
            (scope.isOwner ||
                scope.verifiedParentOwner ||
                creator == accountId);

  static bool canAssign({
    required SharedScope scope,
    required String accountId,
    required String? creator,
  }) => canDelete(scope: scope, accountId: accountId, creator: creator);

  static bool _access(SharedScope scope) =>
      scope.canRead && !scope.blocked && !scope.archived && !scope.deleted;

  static bool canCheckShopping(SharedScope scope) =>
      scope.recordPolicyVersion == 0 ? scope.canEdit : _access(scope);

  /// Unknown/future fields are protected too. A checkbox command may change
  /// only the boolean and its update timestamp, never list/title/quantity.
  static bool onlyShoppingCheck(
    Map<String, dynamic> before,
    Map<String, dynamic> after,
  ) {
    Map<String, dynamic> content(Map<String, dynamic> value) =>
        Map<String, dynamic>.from(value)
          ..remove('isChecked')
          ..remove('updatedAt');
    return after['isChecked'] is bool && _same(content(before), content(after));
  }

  static bool sameAssignments(Object? before, Object? after) {
    if (before is! List ||
        after is! List ||
        before.any((v) => v is! String) ||
        after.any((v) => v is! String))
      return false;
    return before.length == after.length &&
        before.toSet().length == before.length &&
        after.toSet().length == after.length &&
        before.toSet().containsAll(after);
  }

  static bool _same(Object? a, Object? b) {
    if (a is Map && b is Map)
      return a.length == b.length &&
          a.entries.every(
            (e) => b.containsKey(e.key) && _same(e.value, b[e.key]),
          );
    if (a is List && b is List)
      return a.length == b.length &&
          List.generate(a.length, (i) => _same(a[i], b[i])).every((v) => v);
    return a == b;
  }
}
