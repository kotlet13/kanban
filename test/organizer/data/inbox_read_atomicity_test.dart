import '../support/synthetic_content_route_guard.dart';
import 'dart:convert';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/data/finance_inbox_store.dart';
import 'package:kanban/organizer/data/local_spaces_repository.dart';
import 'package:kanban/organizer/data/organizer_repository.dart';
import 'package:kanban/organizer/data/sqlite_organizer_storage.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import '../ui/sharing_ui_fixture.dart' show sharingSession;
import 'collaboration_repository_test.dart'
    show FakeServer, FakeTransport, MemorySessionStore;

class ReceiptDatabase extends CollaborationDatabase {
  ReceiptDatabase() : super(NativeDatabase.memory());
  void Function(String)? afterWrite;
  @override
  Future<void> execute(String sql, [List<Object?> args = const []]) async {
    await super.execute(sql, args);
    afterWrite?.call(sql);
  }
}

final now = DateTime.now().toUtc();
SharedInboxEntry entry(int id, String scope, {bool finance = false}) =>
    SharedInboxEntry(
      id: id,
      revision: 1,
      sequence: id,
      scopeId: scope,
      kind: finance ? 'finance.updated' : 'task.created',
      category: finance ? 'finance' : 'tasks',
      audience: InboxAudience.scope,
      actorAccountId: sharingSession().accountId,
      targetType: finance ? 'financeEntry' : 'task',
      targetId: 'task',
      targetRevision: 1,
      groupKey: 'group',
      createdAt: now,
    );
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  test(
    'local reminder receipt persists offline without completing task',
    () async {
      final db = ReceiptDatabase();
      final local = SqliteOrganizerStorage(db);
      await local.initialize();
      final repo = OrganizerRepository(local, clock: () => now);
      await repo.initialize();
      addTearDown(() async {
        await repo.close();
        await db.close();
      });
      await repo.createTask(
        title: 'Still unfinished',
        dueAt: now.subtract(const Duration(hours: 1)),
      );
      final alarm = repo.snapshot.reminders.single;
      await LocalSpacesRepository(db).markReminderRead(
        'local',
        alarm.id,
        expectedWorkspaceKey: 'local',
        stillVisible: () => true,
      );
      final fresh = await local.read();
      expect(fresh.reminders.single.isRead, isTrue);
      expect(fresh.tasks.single.isCompleted, isFalse);
    },
  );
  test(
    'identity change after local receipt SQL rolls back entire local write',
    () async {
      final db = ReceiptDatabase();
      final local = SqliteOrganizerStorage(db);
      await local.initialize();
      final repo = OrganizerRepository(local, clock: () => now);
      await repo.initialize();
      addTearDown(() async {
        await repo.close();
        await db.close();
      });
      await repo.createTask(
        title: 'Unfinished',
        dueAt: now.subtract(const Duration(hours: 1)),
      );
      final alarm = repo.snapshot.reminders.single;
      var changed = false;
      db.afterWrite = (sql) {
        if (!changed && sql.startsWith('INSERT INTO personal_records')) {
          changed = true;
          db.activatePersonal(sharingSession(second: true));
        }
      };
      await expectLater(
        LocalSpacesRepository(db).markReminderRead(
          'local',
          alarm.id,
          expectedWorkspaceKey: 'local',
          stillVisible: () => true,
        ),
        throwsA(isA<OrganizerConflictException>()),
      );
      expect(changed, isTrue);
      db.afterWrite = null;
      expect((await local.read()).reminders.single.isRead, isFalse);
      expect((await local.read()).tasks.single.isCompleted, isFalse);
    },
  );
  test(
    'financial receipt identity change after INSERT rolls back without changing amount or status',
    () async {
      final db = ReceiptDatabase();
      addTearDown(db.close);
      await db.execute(
        "INSERT INTO personal_workspaces(id,revision) VALUES('local',0)",
      );
      await db.execute(
        "INSERT INTO personal_records(workspace,id,type,payload) VALUES('local','money','financeEntry',?)",
        [
          jsonEncode({'status': 'planned', 'amountMinor': 1234}),
        ],
      );
      final plan = ReminderPlan(
        stableKey: 'salary',
        scheduledAt: now,
        reason: 'salary_check',
        target: NotificationTarget(
          records: const [
            NotificationRecordTarget(type: 'financeEntry', recordId: 'money'),
          ],
        ),
      );
      db.afterWrite = (sql) {
        if (sql.startsWith('INSERT INTO local_meta')) {
          db.activatePersonal(sharingSession(second: true));
        }
      };
      await expectLater(
        FinanceInboxStore(db).markRead(plan, stillVisible: () => true),
        throwsA(isA<CollaborationException>()),
      );
      db.afterWrite = null;
      expect(await FinanceInboxStore(db).readKeys([plan]), isEmpty);
      final record =
          jsonDecode(
                (await db.rows(
                      'SELECT payload FROM personal_records',
                    )).single['payload']
                    as String,
              )
              as Map;
      expect(record, {'status': 'planned', 'amountMinor': 1234});
    },
  );
  Future<(CollaborationRepository, ReceiptDatabase, String)>
  sharedFixture() async {
    final db = ReceiptDatabase();
    final repo = CollaborationRepository(
      db,
      FakeTransport(FakeServer()),
      MemorySessionStore(),
      contentRouteGuard: const SyntheticContentRouteGuard(),
    );
    await repo.initialize();
    await repo.login(
      serverUrl: 'https://synthetic.test',
      username: 'alice',
      password: 'synthetic',
    );
    final scope = await repo.createScope('Shared');
    addTearDown(repo.close);
    for (final id in [1, 2]) {
      await db.execute('INSERT INTO inbox(partition,id,data) VALUES(?,?,?)', [
        repo.state.session!.partition,
        id,
        jsonEncode(entry(id, scope).toJson()),
      ]);
    }
    await repo.refreshLocal();
    return (repo, db, scope);
  }

  test(
    'remote batch rolls back every receipt and command after access changes during SQL',
    () async {
      final (repo, db, _) = await sharedFixture();
      var eligible = true;
      db.afterWrite = (sql) {
        if (sql.startsWith('UPDATE inbox SET')) eligible = false;
      };
      await expectLater(
        repo.markInboxRead(
          [1, 2],
          expectedPartition: repo.state.session!.partition,
          stillEligible: (_) => eligible,
        ),
        throwsA(isA<CollaborationException>()),
      );
      db.afterWrite = null;
      final entries = await db.rows('SELECT data FROM inbox');
      expect(
        entries.every(
          (r) => !SharedInboxEntry.fromJson(
            jsonDecode(r['data'] as String) as Map<String, dynamic>,
          ).isRead,
        ),
        isTrue,
      );
      expect(
        await db.rows("SELECT id FROM commands WHERE operation='inbox.read'"),
        isEmpty,
      );
    },
  );
  test(
    'DB blocked financial scope rejects receipt despite stale eligible UI',
    () async {
      final (repo, db, scope) = await sharedFixture();
      await db.execute('UPDATE inbox SET data=? WHERE id=1', [
        jsonEncode(entry(1, scope, finance: true).toJson()),
      ]);
      await db.execute(
        'UPDATE scopes SET finance_policy=?,finance_blocked=1,finance_complete=1 WHERE id=?',
        [
          jsonEncode(
            const SharedFinancePolicy(
              enabled: true,
              grant: SharedFinanceGrant.read,
            ).toJson(),
          ),
          scope,
        ],
      );
      await expectLater(
        repo.markInboxRead([1], stillEligible: (_) => true),
        throwsA(
          isA<CollaborationException>().having(
            (e) => e.code,
            'code',
            'finance_forbidden',
          ),
        ),
      );
      expect(
        await db.rows("SELECT id FROM commands WHERE operation='inbox.read'"),
        isEmpty,
      );
    },
  );
}
