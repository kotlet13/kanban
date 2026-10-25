import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'package:kanban/organizer/state/shared_record_access.dart';
import 'sharing_ui_fixture.dart';

CollaborationState fixture({
  SharedRole role = SharedRole.member,
  bool revoked = false,
  int version = 1,
}) => CollaborationState(
  session: sharingSession(),
  scopes: [
    SharedScope(
      id: sharingScopeId,
      name: 'Space',
      kind: SharedScopeKind.household,
      role: role,
      revoked: revoked,
      recordPolicyVersion: version,
    ),
  ],
  data: {
    sharingScopeId: SharedScopeData(
      recordCreators: {
        'content:own': sharingSession().accountId,
        'content:other': sharingSession(second: true).accountId,
        'finance:own-finance': sharingSession().accountId,
      },
      tasks: [
        LocalTask(
          id: 'assigned',
          title: 'Assigned task',
          notes: '',
          projectId: null,
          dueAt: null,
          isCompleted: false,
          createdAt: sharingTestNow,
          updatedAt: sharingTestNow,
          assigneeAccountIds: [sharingSession().accountId],
        ),
      ],
    ),
  },
);
void main() {
  test(
    'all module edit projections distinguish existing creator and assignee',
    () {
      final member = fixture();
      for (final type in ['project', 'event', 'idea', 'garden', 'task']) {
        expect(
          canEditSharedRecord(member, sharingScopeId, type, 'own'),
          isTrue,
          reason: type,
        );
        expect(
          canEditSharedRecord(member, sharingScopeId, type, 'other'),
          isFalse,
          reason: type,
        );
      }
      expect(
        canEditSharedRecord(member, sharingScopeId, 'task', 'assigned'),
        isTrue,
      );
      expect(
        canEditSharedRecord(member, sharingScopeId, 'garden', 'assigned'),
        isFalse,
      );
      expect(
        canEditSharedRecord(
          member,
          sharingScopeId,
          'financeEntry',
          'own-finance',
          domain: 'finance',
        ),
        isTrue,
      );
      expect(
        canEditSharedRecord(member, sharingScopeId, 'task', 'own-finance'),
        isFalse,
      );
    },
  );
  test(
    'viewer author and assigned task remain editable but revoked owner does not',
    () {
      final viewer = fixture(role: SharedRole.viewer);
      expect(
        canEditSharedRecord(viewer, sharingScopeId, 'idea', 'own'),
        isTrue,
      );
      expect(
        canEditSharedRecord(viewer, sharingScopeId, 'task', 'assigned'),
        isTrue,
      );
      expect(
        canEditSharedRecord(viewer, sharingScopeId, 'idea', 'other'),
        isFalse,
      );
      expect(
        canEditSharedRecord(
          fixture(role: SharedRole.owner, revoked: true),
          sharingScopeId,
          'idea',
          'own',
        ),
        isFalse,
      );
      expect(
        canEditSharedRecord(
          fixture(role: SharedRole.owner),
          sharingScopeId,
          'idea',
          'other',
        ),
        isTrue,
      );
    },
  );
  test(
    'historical preactivation display keeps prior permissions without fabricating authors',
    () {
      expect(
        canEditSharedRecord(
          fixture(version: 0),
          sharingScopeId,
          'idea',
          'unknown',
        ),
        isTrue,
      );
      expect(
        canEditSharedRecord(fixture(), sharingScopeId, 'idea', 'unknown'),
        isFalse,
      );
      expect(
        canEditSharedRecord(
          fixture(version: 0, role: SharedRole.viewer),
          sharingScopeId,
          'idea',
          'unknown',
        ),
        isFalse,
      );
    },
  );
}
