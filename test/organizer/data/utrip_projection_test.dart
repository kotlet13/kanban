import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/domain/all_spaces_projection.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'package:kanban/organizer/domain/utrip_projection.dart';

final now = DateTime(2026, 10, 12, 12);
LocalEvent event(String id, DateTime start, [DateTime? end]) => LocalEvent(
  id: id,
  title: id,
  notes: '',
  startsAt: start,
  endsAt: end,
  projectId: null,
  createdAt: now,
  updatedAt: now,
);
LocalProject project(String id, {DateTime? start, DateTime? end}) =>
    LocalProject(
      id: id,
      title: id,
      description: '',
      startAt: start,
      endAt: end,
      createdAt: now,
      updatedAt: now,
    );
AllSpacesSource local(OrganizerSnapshot snapshot) => AllSpacesSource(
  key: snapshot.workspaceKey,
  personal: snapshot,
  canReadFinance: true,
  financeComplete: true,
);

void main() {
  test(
    'today keeps finished today and overlaps but excludes midnight ends',
    () {
      final data = OrganizerSnapshot(
        events: [
          event(
            'morning',
            DateTime(2026, 10, 12, 8),
            DateTime(2026, 10, 12, 9),
          ),
          event(
            'overlap',
            DateTime(2026, 10, 11, 20),
            DateTime(2026, 10, 13, 2),
          ),
          event(
            'midnight end',
            DateTime(2026, 10, 11, 20),
            DateTime(2026, 10, 12),
          ),
          event('yesterday no end', DateTime(2026, 10, 11, 20)),
          event('today UTC', DateTime(2026, 10, 12, 18).toUtc()),
          event('tomorrow', DateTime(2026, 10, 13)),
        ],
      );
      final overview = UtripProjection(
        AllSpacesSnapshot([local(data)]),
        now: now,
      );
      expect(overview.todayEvents.map((e) => e.id), [
        'overlap',
        'morning',
        'today UTC',
      ]);
      expect(overview.upcomingEvents.map((e) => e.id), ['tomorrow']);
    },
  );

  test('next seven civil dates are bounded without duplicating today', () {
    final overview = UtripProjection(
      AllSpacesSnapshot([
        local(
          OrganizerSnapshot(
            events: [
              event('today', DateTime(2026, 10, 12, 19)),
              event('day1', DateTime(2026, 10, 13)),
              event('day7', DateTime(2026, 10, 19, 23, 59)),
              event('day8', DateTime(2026, 10, 20)),
            ],
          ),
        ),
      ]),
      now: now,
    );
    expect(overview.upcomingEvents.map((e) => e.id), ['day1', 'day7']);
  });

  test(
    'ongoing projects include undated and end-today but omit past/future',
    () {
      final overview = UtripProjection(
        AllSpacesSnapshot([
          local(
            OrganizerSnapshot(
              projects: [
                project('undated'),
                project('started', start: DateTime(2026, 10, 1)),
                project('ends today', end: DateTime(2026, 10, 12)),
                project('future', start: DateTime(2026, 10, 13)),
                project('past', end: DateTime(2026, 10, 11)),
              ],
            ),
          ),
        ]),
        now: now,
      );
      expect(overview.ongoingProjects.map((e) => e.id).toSet(), {
        'undated',
        'started',
        'ends today',
      });
      expect(overview.ongoingProjects.first.id, 'ends today');
    },
  );

  test(
    'today tasks are actionable due/ongoing work with completed omitted',
    () {
      LocalTask task(
        String id, {
        DateTime? due,
        DateTime? start,
        DateTime? end,
        bool completed = false,
      }) => LocalTask(
        id: id,
        title: id,
        notes: '',
        projectId: null,
        dueAt: due,
        startAt: start,
        endAt: end,
        isCompleted: completed,
        createdAt: now,
        updatedAt: now,
      );
      final overview = UtripProjection(
        AllSpacesSnapshot([
          local(
            OrganizerSnapshot(
              tasks: [
                task('overdue', due: DateTime(2026, 10, 11)),
                task('today', due: DateTime(2026, 10, 12, 18)),
                task(
                  'ongoing',
                  start: DateTime(2026, 10, 11),
                  end: DateTime(2026, 10, 13),
                ),
                task('complete', due: now, completed: true),
                task('future', due: DateTime(2026, 10, 13)),
                task('unscheduled'),
              ],
            ),
          ),
        ]),
        now: now,
      );
      expect(overview.dueTasks.map((e) => e.id).toSet(), {
        'overdue',
        'today',
        'ongoing',
      });
    },
  );

  test(
    'permission projection retains collision-safe origins and blocks revoked rows',
    () {
      final session = AccountSession(
        serverUrl: 'https://synthetic.invalid',
        serverId: 'server',
        accountId: 'account',
        userId: 1,
        username: 'account',
        displayName: 'Account',
        deviceId: 'device',
        expiresAt: now.add(const Duration(days: 1)),
      );
      final snapshot = projectAllSpaces(
        personal: OrganizerSnapshot(events: [event('same-id', now)]),
        shared: CollaborationState(
          session: session,
          scopes: [
            const SharedScope(
              id: 'allowed',
              name: 'Home',
              kind: SharedScopeKind.household,
              role: SharedRole.viewer,
            ),
            const SharedScope(
              id: 'revoked',
              name: 'Old',
              kind: SharedScopeKind.household,
              role: SharedRole.owner,
              revoked: true,
            ),
            const SharedScope(
              id: 'blocked',
              name: 'Blocked',
              kind: SharedScopeKind.household,
              role: SharedRole.owner,
              blocked: true,
            ),
          ],
          data: {
            for (final id in ['allowed', 'revoked', 'blocked'])
              id: SharedScopeData(
                events: [
                  SharedEvent(
                    id: 'same-id',
                    title: id,
                    startAt: now,
                    createdAt: now,
                    updatedAt: now,
                  ),
                ],
              ),
          },
        ),
      );
      final overview = UtripProjection(snapshot, now: now);
      expect(overview.todayEvents.length, 2);
      expect(overview.todayEvents.map((e) => e.source.scopeId).toSet(), {
        null,
        'allowed',
      });
      final remote = overview.todayEvents.firstWhere(
        (e) => e.source.scopeId != null,
      );
      final target = remote.source.target(remote.type, remote.id);
      expect(target.scopeId, 'allowed');
      expect(target.records.single.recordId, 'same-id');
      expect(target.accountId, 'account');
    },
  );
}
