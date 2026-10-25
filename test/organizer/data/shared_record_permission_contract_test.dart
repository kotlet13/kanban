import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:kanban/organizer/domain/shared_record_permissions.dart';

void main() {
  test(
    'pre-activation viewer author or assignee retains historical read-only contract including checkbox',
    () {
      const scope = SharedScope(
        id: 'scope',
        name: 'Legacy',
        kind: SharedScopeKind.household,
        role: SharedRole.viewer,
      );
      expect(
        SharedRecordPermissions.canEdit(
          scope: scope,
          accountId: 'reader',
          creator: 'reader',
          type: 'task',
          assignees: ['reader'],
        ),
        false,
      );
      expect(
        SharedRecordPermissions.canDelete(
          scope: scope,
          accountId: 'reader',
          creator: 'reader',
        ),
        false,
      );
      expect(SharedRecordPermissions.canCheckShopping(scope), false);
      const activated = SharedScope(
        id: 'scope',
        name: 'Active',
        kind: SharedScopeKind.household,
        role: SharedRole.viewer,
        recordPolicyVersion: 1,
      );
      expect(
        SharedRecordPermissions.canEdit(
          scope: activated,
          accountId: 'reader',
          creator: 'other',
          type: 'task',
          assignees: ['reader'],
        ),
        true,
      );
      expect(
        SharedRecordPermissions.canDelete(
          scope: activated,
          accountId: 'reader',
          creator: 'other',
        ),
        false,
      );
      expect(
        SharedRecordPermissions.canAssign(
          scope: activated,
          accountId: 'reader',
          creator: 'other',
        ),
        false,
      );
      expect(SharedRecordPermissions.canCheckShopping(activated), true);
    },
  );
}
