import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:kanban/organizer/domain/all_spaces_projection.dart';
import 'package:kanban/organizer/domain/local_space_models.dart';
import 'package:kanban/organizer/domain/organizer_projections.dart';
import 'package:kanban/organizer/domain/utrip_projection.dart';
import 'package:kanban/organizer/state/notification_local_spaces_provider.dart';

final now = DateTime.utc(2026, 10, 14, 12);
LocalProject project(String id, {bool archived = false}) => LocalProject(
  id: id,
  title: id,
  description: '',
  createdAt: now,
  updatedAt: now,
  archived: archived,
);
LocalTask task(String id, String projectId) => LocalTask(
  id: id,
  title: id,
  notes: '',
  projectId: projectId,
  dueAt: now,
  isCompleted: false,
  createdAt: now,
  updatedAt: now,
);
void main() {
  test(
    'active aggregate excludes archived project tasks/events but keeps archive access and posted finance facts',
    () {
      final money = FinanceEntry(
        id: 'money',
        title: 'Posted history',
        kind: FinanceEntryKind.expense,
        amountMinor: 400,
        currency: 'EUR',
        occurredAt: now,
        projectId: 'archived',
        notes: '',
        createdAt: now,
        updatedAt: now,
      );
      final snapshot = OrganizerSnapshot(
        projects: [project('active'), project('archived', archived: true)],
        tasks: [
          task('active-task', 'active'),
          task('archived-task', 'archived'),
        ],
        events: [
          LocalEvent(
            id: 'archived-event',
            title: 'Event',
            notes: '',
            startsAt: now,
            endsAt: null,
            projectId: 'archived',
            createdAt: now,
            updatedAt: now,
          ),
        ],
        financeEntries: [money],
      );
      final all = projectAllSpaces(
        personal: snapshot,
        shared: CollaborationState(),
      );
      expect(all.projects.map((p) => p.value.id), ['active']);
      expect(all.archivedProjects.single.value.id, 'archived');
      expect(all.tasks.single.value.id, 'active-task');
      expect(all.localEvents, isEmpty);
      expect(all.localFinanceEntries.single.value, money);
      expect(
        all.financeTotalsByCurrency['EUR']!.expenseMinor,
        BigInt.from(400),
      );
      final pulse = UtripProjection(all, now: now);
      expect(pulse.dueTasks.single.id, 'active-task');
      expect(pulse.ongoingProjects.single.id, 'active');
      final plans = desiredReminderPlans(
        personal: snapshot,
        shared: CollaborationState(),
      );
      expect(
        plans
            .where((p) => p.reason == 'task_due')
            .single
            .target
            .records
            .single
            .recordId,
        'active-task',
      );
      final projection = activeProjectNotificationSnapshot(snapshot);
      expect(projection.tasks.single.id, 'active-task');
      expect(projection.events, isEmpty);
      expect(projection.financeEntries.single, money);
      expect(snapshot.tasks, hasLength(2));
    },
  );
  test(
    'archived local space is absent from active All while stored source remains intact',
    () {
      final local = OrganizerSnapshot(
        workspaceKey: 'archived-home',
        tasks: [task('parked', 'project')],
      );
      final all = projectAllSpaces(
        personal: local,
        shared: CollaborationState(),
        localSpaces: LocalSpacesState(
          selectedSpaceId: 'archived-home',
          spaces: const [
            LocalSpace(
              id: 'archived-home',
              name: 'Archived home',
              kind: LocalSpaceKind.household,
              archived: true,
            ),
          ],
          snapshots: {'archived-home': local},
        ),
      );
      expect(all.sources, isEmpty);
      expect(local.tasks.single.id, 'parked');
    },
  );
  test(
    'shared calendar defaults exclude archived inline projects and their task/event rows',
    () {
      final data = SharedScopeData(
        projects: [project('active'), project('archived', archived: true)],
        tasks: [
          task('active-task', 'active'),
          task('archived-task', 'archived'),
        ],
      );
      expect(projectTimeline(data, scopeId: 'home').map((p) => p.id), [
        'active-task',
        'active',
      ]);
      expect(
        dailyAgenda(data, scopeId: 'home', day: now).single.id,
        'active-task',
      );
    },
  );
}
