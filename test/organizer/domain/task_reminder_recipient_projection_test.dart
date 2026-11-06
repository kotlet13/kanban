import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/reminder_snooze_store.dart';
import 'package:kanban/organizer/domain/notification_models.dart';

import '../data/reminder_snooze_store_test.dart' as snooze;
import '../ui/inbox_visibility_ui_test.dart' as fixture;

SharedInboxEntry peerReminder() {
  final original = fixture.entry();
  return SharedInboxEntry(
    id: original.id,
    scopeId: original.scopeId,
    kind: original.kind,
    category: original.category,
    audience: original.audience,
    targetType: original.targetType,
    targetId: original.targetId,
    groupKey: original.groupKey,
    createdAt: original.createdAt,
    actorAccountId: '10000000-0000-4000-8000-000000000099',
  );
}

void main() {
  test(
    'delivered recipient reminder is visible before the automatic deadline',
    () {
      final state = fixture.shared(
        reminderState: null,
        inbox: [peerReminder()],
      );
      final projection = fixture.project(
        state,
        plans: [fixture.alarm(future: true)],
      );
      expect(projection.shared, hasLength(1));
      expect(projection.shared.single.group.entries.single.id, 1);
      expect(projection.hasUnread({}), isTrue);
    },
  );

  test('peer reminder is independent of the recipient own schedule', () {
    for (final ownState in ['pending', 'cancelled']) {
      final state = fixture.shared(
        reminderState: ownState,
        inbox: [peerReminder()],
      );
      expect(fixture.project(state).shared, hasLength(1));
    }
    // The same account's old alarm still respects its explicit own change.
    expect(
      fixture.project(fixture.shared(reminderState: 'pending')).shared,
      isEmpty,
    );
    expect(
      fixture.project(fixture.shared(reminderState: 'cancelled')).shared,
      isEmpty,
    );
  });

  test('explicit device snooze still hides the peer alarm until its time', () {
    final state = fixture.shared(reminderState: null, inbox: [peerReminder()]);
    expect(
      fixture
          .project(state, plans: [fixture.alarm(future: true, snoozed: true)])
          .shared,
      isEmpty,
    );
    expect(
      fixture.project(state, plans: [fixture.alarm(snoozed: true)]).shared,
      hasLength(1),
    );
  });

  test('recipient alarm retains completion access and preference gates', () {
    for (final state in [
      fixture.shared(
        reminderState: null,
        inbox: [peerReminder()],
        completed: true,
      ),
      fixture.shared(
        reminderState: null,
        inbox: [peerReminder()],
        missing: true,
      ),
      fixture.shared(
        reminderState: null,
        inbox: [peerReminder()],
        revoked: true,
      ),
      fixture.shared(
        reminderState: null,
        inbox: [peerReminder()],
        disabled: true,
      ),
    ]) {
      expect(
        fixture.project(state, plans: [fixture.alarm(future: true)]).shared,
        isEmpty,
      );
    }
  });

  test(
    'validated SQL snooze marks effective plan and source change clears it',
    () async {
      final db = CollaborationDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = await snooze.seed(db);
      addTearDown(repo.close);
      final store = ReminderSnoozeStore(db, clock: () => snooze.now);
      final plan = snooze.plans(repo).single;
      expect(plan.isSnoozed, isFalse);
      await store.snooze(
        plan,
        snooze.now.add(const Duration(hours: 1)),
        stillCurrent: () => true,
      );
      final effective = (await store.resolve(snooze.plans(repo))).single;
      expect(effective.isSnoozed, isTrue);
      expect(effective.scheduledAt, snooze.now.add(const Duration(hours: 1)));
      await repo.updateTask(
        repo.snapshot.tasks.single.copyWith(title: 'Changed source'),
      );
      final cleared = (await store.resolve(snooze.plans(repo))).single;
      expect(cleared.isSnoozed, isFalse);
      expect(cleared.scheduledAt, plan.scheduledAt);
    },
  );
}
