import 'dart:convert';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/organizer_repository.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/data/sqlite_organizer_storage.dart';
import 'package:kanban/organizer/data/reminder_snooze_store.dart';
import 'package:kanban/organizer/data/finance_inbox_store.dart';
import 'package:kanban/organizer/domain/finance_reminder_plans.dart';
import 'package:kanban/organizer/data/portable_backup_repository.dart';
import 'package:kanban/organizer/data/portable_backup_crypto.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'package:kanban/organizer/domain/organizer_projections.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import '../ui/sharing_ui_fixture.dart';
import 'collaboration_repository_test.dart' show FakeServer, MemorySessionStore;
import 'private_sync_test_support.dart';

final now = DateTime.utc(2026, 10, 8, 12);
Future<OrganizerRepository> seed(CollaborationDatabase db) async {
  final storage = SqliteOrganizerStorage(db);
  await storage.initialize();
  final repo = OrganizerRepository(storage, clock: () => now);
  await repo.initialize();
  await repo.createProject(title: 'Real project');
  await repo.createTask(
    projectId: repo.snapshot.projects.single.id,
    title: 'Real task',
    dueAt: now,
  );
  return repo;
}

List<ReminderPlan> plans(OrganizerRepository repo) =>
    desiredReminderPlans(personal: repo.snapshot, shared: CollaborationState());
void main() {
  test(
    'SQLite restart keeps exact alarm, unchanged task/read state and no duplicates',
    () async {
      final directory = await Directory.systemTemp.createTemp('jivie-snooze-');
      final file = File('${directory.path}/data.sqlite');
      var db = CollaborationDatabase(NativeDatabase(file));
      var repo = await seed(db);
      final plan = plans(repo).single;
      final before = repo.snapshot.toJson();
      final until = now.add(const Duration(minutes: 15));
      await ReminderSnoozeStore(
        db,
        clock: () => now,
      ).snooze(plan, until, stillCurrent: () => true);
      expect(repo.snapshot.toJson(), before);
      await repo.markReminderRead(repo.snapshot.reminders.single.id);
      expect(
        (await ReminderSnoozeStore(db).resolve(plans(repo))).single.scheduledAt,
        until,
      );
      final rows = await db.rows(
        "SELECT value FROM local_meta WHERE name LIKE 'reminder_snooze:%'",
      );
      expect(rows, hasLength(1));
      expect(rows.single['value'], isNot(contains('Real task')));
      expect(
        (jsonDecode(rows.single['value'] as String) as Map)['source'],
        hasLength(44),
      );
      await repo.close();
      await db.close();
      db = CollaborationDatabase(NativeDatabase(file));
      repo = OrganizerRepository(SqliteOrganizerStorage(db), clock: () => now);
      await repo.initialize();
      final effective = await ReminderSnoozeStore(db).resolve(plans(repo));
      expect(effective, hasLength(1));
      expect(effective.single.stableKey, plan.stableKey);
      expect(effective.single.scheduledAt, until);
      expect(repo.snapshot.tasks.single.dueAt, now);
      expect(repo.snapshot.reminders.single.isRead, true);
      await repo.close();
      await db.close();
      await directory.delete(recursive: true);
    },
  );
  test(
    'changed source, completion and deletion permanently invalidate snooze',
    () async {
      final db = CollaborationDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = await seed(db);
      addTearDown(repo.close);
      final store = ReminderSnoozeStore(db, clock: () => now);
      var plan = plans(repo).single;
      await store.snooze(
        plan,
        now.add(const Duration(hours: 1)),
        stillCurrent: () => true,
      );
      await repo.updateTask(
        repo.snapshot.tasks.single.copyWith(title: 'Updated'),
      );
      expect((await store.resolve(plans(repo))).single.scheduledAt, now);
      expect(
        await db.rows(
          "SELECT * FROM local_meta WHERE name LIKE 'reminder_snooze:%'",
        ),
        isEmpty,
      );
      plan = plans(repo).single;
      await store.snooze(
        plan,
        now.add(const Duration(hours: 1)),
        stillCurrent: () => true,
      );
      await repo.setTaskCompleted(repo.snapshot.tasks.single.id, true);
      expect(await store.resolve(plans(repo)), isEmpty);
      expect(
        await db.rows(
          "SELECT * FROM local_meta WHERE name LIKE 'reminder_snooze:%'",
        ),
        isEmpty,
      );
      await repo.setTaskCompleted(repo.snapshot.tasks.single.id, false);
      plan = plans(repo).single;
      await store.snooze(
        plan,
        now.add(const Duration(hours: 1)),
        stillCurrent: () => true,
      );
      await repo.deleteTask(repo.snapshot.tasks.single.id);
      expect(await store.resolve(plans(repo)), isEmpty);
    },
  );
  test(
    'stale editor, past date and failed SQLite commit retain prior preference and source',
    () async {
      final db = CollaborationDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = await seed(db);
      addTearDown(repo.close);
      final store = ReminderSnoozeStore(db, clock: () => now);
      final plan = plans(repo).single;
      final until = now.add(const Duration(minutes: 15));
      await store.snooze(plan, until, stillCurrent: () => true);
      await expectLater(
        store.snooze(plan, until, stillCurrent: () => false),
        throwsA(isA<CollaborationException>()),
      );
      await expectLater(
        store.snooze(plan, now, stillCurrent: () => true),
        throwsA(isA<CollaborationException>()),
      );
      await db.execute(
        "CREATE TRIGGER fail_snooze BEFORE UPDATE ON local_meta WHEN NEW.name LIKE 'reminder_snooze:%' BEGIN SELECT RAISE(ABORT, 'injected failure'); END",
      );
      await expectLater(
        store.snooze(
          plan,
          now.add(const Duration(hours: 1)),
          stillCurrent: () => true,
        ),
        throwsA(anything),
      );
      expect((await store.resolve(plans(repo))).single.scheduledAt, until);
      expect(repo.snapshot.tasks.single.dueAt, now);
    },
  );
  test('device override is excluded from portable backup', () async {
    final db = CollaborationDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = await seed(db);
    addTearDown(repo.close);
    await ReminderSnoozeStore(db, clock: () => now).snooze(
      plans(repo).single,
      now.add(const Duration(hours: 1)),
      stillCurrent: () => true,
    );
    final backup = PortableBackupRepository(
      db,
      SqliteOrganizerStorage(db),
      MemoryBackupUiPreferencesStore(),
    );
    final doc = await PortableBackupCrypto().decrypt(
      await backup.exportEncryptedBackup('a long backup password'),
      'a long backup password',
    );
    expect(jsonEncode(doc), isNot(contains('reminder_snooze:')));
  });
  test(
    'Friday/Monday salary checks snooze separately; reading preserves and actual payment cancels both',
    () async {
      final db = CollaborationDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = await seed(db);
      addTearDown(repo.close);
      await repo.saveFinancePlan(
        accounts: [],
        rules: [
          FinanceRecurrenceRule(
            id: newLocalId(),
            title: 'Salary',
            kind: FinanceRecurrenceKind.salary,
            currency: 'EUR',
            estimatedAmountMinor: 120000,
            startYear: 2026,
            startMonth: 10,
            monthDay: 31,
            remindersEnabled: true,
            createdAt: now,
            updatedAt: now,
          ),
        ],
        expectedRevision: repo.snapshot.revision,
        expectedWorkspaceKey: 'local',
      );
      final entry = repo.snapshot.financeEntries.singleWhere(
        (e) => e.occurrenceKey == '2026-10',
      );
      final original = desiredFinanceReminderPlans(
        personal: repo.snapshot,
        shared: CollaborationState(),
      ).where((p) => p.target.records.single.recordId == entry.id).toList();
      expect(original, hasLength(2));
      final friday = original.first, monday = original.last;
      final store = ReminderSnoozeStore(db, clock: () => friday.scheduledAt);
      final until = monday.scheduledAt.add(const Duration(hours: 1));
      await store.snooze(friday, until, stillCurrent: () => true);
      await FinanceInboxStore(db).markRead(friday, stillVisible: () => true);
      var effective = await store.resolve(original);
      expect(
        effective
            .singleWhere((p) => p.stableKey == friday.stableKey)
            .scheduledAt,
        until,
      );
      expect(
        effective
            .singleWhere((p) => p.stableKey == monday.stableKey)
            .scheduledAt,
        monday.scheduledAt,
      );
      expect(
        repo.snapshot.financeEntries
            .singleWhere((e) => e.id == entry.id)
            .plannedAt,
        entry.plannedAt,
      );
      await store.snooze(
        monday,
        until.add(const Duration(hours: 1)),
        stillCurrent: () => true,
      );
      await repo.confirmFinanceOccurrence(
        entry: entry,
        amountMinor: 129950,
        paidAt: monday.scheduledAt,
        expectedWorkspaceKey: 'local',
      );
      effective = await store.resolve(
        desiredFinanceReminderPlans(
          personal: repo.snapshot,
          shared: CollaborationState(),
        ),
      );
      expect(
        effective.where((p) => p.target.records.single.recordId == entry.id),
        isEmpty,
      );
      expect(
        await db.rows(
          "SELECT * FROM local_meta WHERE name LIKE 'reminder_snooze:%'",
        ),
        isEmpty,
      );
      expect(
        repo.snapshot.financeEntries
            .singleWhere((e) => e.id == entry.id)
            .amountMinor,
        129950,
      );
      expect(
        repo.snapshot.financeEntries
            .singleWhere((e) => e.id == entry.id)
            .status,
        FinanceEntryStatus.posted,
      );
    },
  );
  test(
    'private SQLite mapping creates one remote alarm and snoozes without looking in local records',
    () async {
      final db = CollaborationDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = await seed(db);
      addTearDown(repo.close);
      final shared = CollaborationRepository(
        db,
        PersonalTransport(FakeServer()),
        MemorySessionStore(),
        ownsDatabase: false,
      );
      addTearDown(shared.close);
      await shared.initialize();
      await shared.login(
        serverUrl: 'https://test.invalid',
        username: 'alice',
        password: 'test',
      );
      final preview = await shared.previewPrivateSync();
      await shared.enablePrivateSync(expectedRevision: preview.revision);
      await shared.syncNow();
      await repo.reload();
      final remoteId = shared.state
          .dataForScope(shared.state.privateSync.scopeId!)
          .tasks
          .single
          .id;
      final localId = newLocalId();
      await db.execute(
        "UPDATE personal_record_map SET id=? WHERE workspace=? AND remote_id=? AND type='task'",
        [localId, repo.snapshot.workspaceKey, remoteId],
      );
      await shared.refreshLocal();
      await repo.reload();
      await repo.refreshReminders();
      expect(repo.snapshot.tasks.single.id, localId);
      expect(
        await db.rows(
          "SELECT * FROM personal_records WHERE workspace='local' AND type='task'",
        ),
        isEmpty,
      );
      final original = desiredReminderPlans(
        personal: repo.snapshot,
        shared: shared.state,
      );
      expect(
        original.where((p) => p.target.records.any((r) => r.type == 'task')),
        hasLength(1),
      );
      final plan = original.singleWhere(
        (p) => p.target.records.single.type == 'task',
      );
      expect(plan.target.isPersonal, false);
      expect(plan.target.scopeId, shared.state.privateSync.scopeId);
      expect(plan.target.records.single.recordId, remoteId);
      expect(
        (await shared.openNotificationTarget(plan.target)).status,
        NotificationOpenStatus.available,
      );
      final until = now.add(const Duration(minutes: 15));
      final store = ReminderSnoozeStore(db, clock: () => now);
      await store.snooze(plan, until, stillCurrent: () => true);
      expect((await store.resolve(original)).single.scheduledAt, until);
      expect(repo.snapshot.tasks.single.dueAt, now);
    },
  );
  test(
    'shared account/permission changes remove alarm and cannot reuse a retained editor',
    () async {
      final db = CollaborationDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final session = sharingSession();
      db.activatePersonal(session);
      await db.execute('INSERT INTO accounts(partition,profile) VALUES(?,?)', [
        session.partition,
        jsonEncode(session.toJson()),
      ]);
      final scope = sharingScope();
      final id = newLocalId();
      final payload = jsonEncode({
        'isCompleted': false,
        'dueAt': now.toIso8601String(),
      });
      await db.execute('INSERT INTO scopes(partition,id,data) VALUES(?,?,?)', [
        session.partition,
        scope.id,
        jsonEncode(scope.toJson()),
      ]);
      await db.execute(
        'INSERT INTO records(partition,scope_id,id,type,payload,local_revision,server_revision,deleted) VALUES(?,?,?,?,?,1,1,0)',
        [session.partition, scope.id, id, 'task', payload],
      );
      final plan = ReminderPlan(
        stableKey: '${session.partition}:${scope.id}:task:$id:due',
        scheduledAt: now,
        reason: 'task_due',
        target: NotificationTarget(
          serverUrl: session.serverUrl,
          serverId: session.serverId,
          accountId: session.accountId,
          scopeId: scope.id,
          records: [NotificationRecordTarget(type: 'task', recordId: id)],
        ),
      );
      final store = ReminderSnoozeStore(db, clock: () => now);
      await store.snooze(
        plan,
        now.add(const Duration(hours: 1)),
        stillCurrent: () => true,
      );
      db.activatePersonal(sharingSession(second: true));
      await expectLater(
        store.snooze(
          plan,
          now.add(const Duration(hours: 2)),
          stillCurrent: () => true,
        ),
        throwsA(isA<CollaborationException>()),
      );
      expect(await store.resolve([plan]), isEmpty);
      db.activatePersonal(session);
      expect((await store.resolve([plan])).single.scheduledAt, now);
      await store.snooze(
        plan,
        now.add(const Duration(hours: 1)),
        stillCurrent: () => true,
      );
      await db.execute(
        'UPDATE scopes SET blocked=1 WHERE partition=? AND id=?',
        [session.partition, scope.id],
      );
      expect(await store.resolve([plan]), isEmpty);
    },
  );
}
