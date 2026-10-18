import '../support/synthetic_content_route_guard.dart';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/data/collaboration_transport.dart';
import 'package:kanban/organizer/data/finance_inbox_store.dart';
import 'package:kanban/organizer/data/local_spaces_repository.dart';
import 'package:kanban/organizer/data/organizer_repository.dart';
import 'package:kanban/organizer/data/organizer_storage.dart';
import 'package:kanban/organizer/data/sqlite_organizer_storage.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:kanban/organizer/domain/inbox_projection.dart';
import 'package:kanban/organizer/domain/inbox_retention.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'package:kanban/organizer/state/finance_inbox_provider.dart';
import 'package:kanban/organizer/state/inbox_projection_provider.dart';
import 'package:kanban/organizer/state/organizer_provider.dart';
import 'collaboration_repository_test.dart' show FakeServer, MemorySessionStore;
import 'scheduled_reminder_repository_test.dart' show ReminderTransport;
import 'organizer_repository_test.dart' show MemoryStorage;

final start = DateTime.utc(2026, 10, 11, 12);
ReminderPlan taskPlan(LocalReminder reminder) => ReminderPlan(
  stableKey: reminder.id,
  scheduledAt: reminder.dueAt,
  target: NotificationTarget(
    records: [
      NotificationRecordTarget(type: 'task', recordId: reminder.taskId),
    ],
  ),
  reason: 'task_due',
);
OrganizerInboxProjection localInbox(OrganizerSnapshot snapshot, DateTime now) =>
    projectOrganizerInbox(
      personal: snapshot,
      shared: CollaborationState(),
      effectivePlans: snapshot.reminders.map(taskPlan).toList(),
      now: now,
    );

class InboxTransport extends ReminderTransport {
  InboxTransport() : super(FakeServer());
  List<SharedInboxEntry> inbox = [];
  bool missingRead = false;
  DateTime serverReadAt = start;
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
    if (operation == 'inbox.read') {
      if (missingRead) {
        throw const CollaborationApiException('notification_missing');
      }
      final old = inbox.single;
      inbox = [
        SharedInboxEntry.fromJson({
          ...old.toJson(),
          'readAt': params['read'] == true
              ? serverReadAt.toIso8601String()
              : null,
          'revision': old.revision + 1,
          'sequence': old.sequence + 1,
        }),
      ];
      return {'item': inbox.single.toJson()};
    }
    if (operation == 'inbox.sync') {
      return {
        'items': inbox.map((e) => e.toJson()).toList(),
        'cursor': inbox
            .map((e) => e.sequence)
            .fold<int>(params['cursor'] as int, (a, b) => a > b ? a : b),
        'visibilityRevision': 1,
        'hasMore': false,
      };
    }
    return super.call(
      serverUrl: serverUrl,
      operation: operation,
      params: params,
      token: token,
      allowLocalHttp: allowLocalHttp,
    );
  }
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  test(
    'seven elapsed days include exact cutoff, preserve unread even if created years ago',
    () {
      expect(
        inboxReadExpired(
          start,
          start
              .add(inboxReadRetention)
              .subtract(const Duration(microseconds: 1)),
        ),
        isFalse,
      );
      expect(inboxReadExpired(start, start.add(inboxReadRetention)), isTrue);
      expect(
        inboxReadExpired(null, start.add(const Duration(days: 3650))),
        isFalse,
      );
    },
  );

  test(
    'SQLite receipt survives restart, maintenance and JSON backup without completing or resurfacing task',
    () async {
      final dir = await Directory.systemTemp.createTemp('inbox-retention-');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/local.sqlite');
      var now = start;
      var db = CollaborationDatabase(NativeDatabase(file));
      var storage = SqliteOrganizerStorage(db);
      await storage.initialize();
      var repo = OrganizerRepository(storage, clock: () => now);
      await repo.initialize();
      await repo.createTask(
        title: 'Unfinished',
        dueAt: start.subtract(const Duration(days: 100)),
      );
      final id = repo.snapshot.reminders.single.id;
      await repo.markReminderRead(id);
      now = start.add(const Duration(days: 6));
      await repo.markReminderRead(id);
      expect(repo.snapshot.reminders.single.readAt, start);
      expect(localInbox(repo.snapshot, now).local, hasLength(1));
      final backup = await repo.exportBackup();
      await repo.close();
      await db.close();
      now = start.add(inboxReadRetention);
      db = CollaborationDatabase(NativeDatabase(file));
      storage = SqliteOrganizerStorage(db);
      await storage.initialize();
      repo = OrganizerRepository(storage, clock: () => now);
      await repo.initialize();
      await repo.refreshReminders();
      expect(localInbox(repo.snapshot, now).local, isEmpty);
      expect(repo.snapshot.tasks.single.isCompleted, isFalse);
      expect(repo.snapshot.reminders.single.readAt, start);
      final restored = OrganizerRepository(MemoryStorage(), clock: () => now);
      await restored.initialize();
      await restored.importBackup(
        OrganizerBackupCodec.encode(OrganizerBackupCodec.decode(backup)),
      );
      await restored.refreshReminders();
      expect(localInbox(restored.snapshot, now).local, isEmpty);
      await restored.close();
      await repo.markReminderRead(id, read: false);
      expect(repo.snapshot.reminders.single.readAt, isNull);
      expect(localInbox(repo.snapshot, now).local.single.isRead, isFalse);
      await repo.markReminderRead(id);
      expect(repo.snapshot.reminders.single.readAt, now);
      await repo.close();
      await db.close();
    },
  );

  test(
    'legacy read reminder gets a durable full window on first encounter',
    () async {
      final memory = MemoryStorage();
      var now = start;
      final repo = OrganizerRepository(memory, clock: () => now);
      await repo.initialize();
      await repo.createTask(
        title: 'Old reminder',
        dueAt: start.subtract(const Duration(days: 100)),
      );
      final legacy = repo.snapshot.copyWith(
        reminders: [repo.snapshot.reminders.single.copyWith(isRead: true)],
      );
      await repo.close();
      memory.value = OrganizerSnapshot.fromJson(legacy.toJson());
      final reopened = OrganizerRepository(memory, clock: () => now);
      await reopened.initialize();
      expect(reopened.snapshot.reminders.single.readAt, start);
      now = start.add(const Duration(days: 3));
      await reopened.reload();
      expect(reopened.snapshot.reminders.single.readAt, start);
      expect(localInbox(reopened.snapshot, now).local, hasLength(1));
      await reopened.close();
    },
  );

  test(
    'catalog maintenance stamps unread timestamp-less receipts only for current partition',
    () async {
      final db = CollaborationDatabase(NativeDatabase.memory());
      final storage = SqliteOrganizerStorage(db);
      await storage.initialize();
      addTearDown(db.close);
      final repo = OrganizerRepository(storage, clock: () => start);
      await repo.initialize();
      await repo.createTask(title: 'Catalog task', dueAt: start);
      final reminder = repo.snapshot.reminders.single.copyWith(isRead: true);
      await repo.close();
      for (final workspace in ['local', 'private:other-account']) {
        await db.execute(
          'INSERT INTO personal_records(workspace,id,type,payload) VALUES(?,?,?,?) ON CONFLICT(workspace,id) DO UPDATE SET payload=excluded.payload',
          [workspace, reminder.id, 'reminder', jsonEncode(reminder.toJson())],
        );
      }
      await LocalSpacesRepository(db, clock: () => start).read();
      final rows = await db.rows(
        "SELECT workspace,payload FROM personal_records WHERE type='reminder'",
      );
      expect(
        LocalReminder.fromJson(
          jsonDecode(rows.first['payload'] as String) as Map<String, dynamic>,
        ).readAt,
        start,
      );
      expect(
        LocalReminder.fromJson(
          jsonDecode(rows.last['payload'] as String) as Map<String, dynamic>,
        ).readAt,
        isNull,
      );
    },
  );

  test(
    'finance receipt idempotency and projection expiry keep the unpaid record and new occurrences',
    () async {
      final db = CollaborationDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await SqliteOrganizerStorage(db).initialize();
      await db.execute(
        "INSERT INTO personal_records(workspace,id,type,payload) VALUES('local','money','financeEntry',?)",
        [
          jsonEncode({'status': 'planned', 'amountMinor': 1200}),
        ],
      );
      var now = start;
      final store = FinanceInboxStore(db, clock: () => now);
      final plan = ReminderPlan(
        stableKey: 'personal:local:salary:month:money',
        scheduledAt: start,
        target: NotificationTarget(
          records: const [
            NotificationRecordTarget(type: 'financeEntry', recordId: 'money'),
          ],
        ),
        reason: 'salary_check',
      );
      await store.markRead(plan, stillVisible: () => true);
      now = start.add(const Duration(days: 6));
      await store.markRead(plan, stillVisible: () => true);
      final receipts = await store.readKeys([plan]) as FinanceInboxReadKeys;
      expect(receipts.readAt[plan.stableKey], start);
      final container = ProviderContainer(
        overrides: [
          rawOrganizerInboxProjectionProvider.overrideWith((ref) {
            ref.watch(financeInboxClockProvider);
            return OrganizerInboxProjection(finance: [plan]);
          }),
          financeInboxStoreProvider.overrideWith((ref) async => store),
          organizerClockProvider.overrideWithValue(() => now),
          organizerReminderSchedulerProvider.overrideWithValue((_) => () {}),
        ],
      );
      addTearDown(container.dispose);
      container.listen(organizerInboxProjectionProvider, (_, _) {});
      await container.read(financeInboxReadKeysProvider.future);
      expect(
        container.read(organizerInboxProjectionProvider).finance,
        hasLength(1),
      );
      now = start.add(inboxReadRetention);
      container.invalidate(financeInboxClockProvider);
      expect(container.read(organizerInboxProjectionProvider).finance, isEmpty);
      await container.read(financeInboxClockProvider.future);
      expect(container.read(organizerInboxProjectionProvider).finance, isEmpty);
      expect(
        jsonDecode(
          (await db.rows(
                "SELECT payload FROM personal_records WHERE id='money'",
              )).single['payload']
              as String,
        ),
        {'status': 'planned', 'amountMinor': 1200},
      );
      final next = ReminderPlan(
        stableKey: '${plan.stableKey}:next',
        scheduledAt: now,
        target: plan.target,
        reason: plan.reason,
      );
      expect(await store.readKeys([next]), isEmpty);
    },
  );

  test(
    'shared expiry deletes cached rows but preserves unread/pending commands and rejects stale resurrection',
    () async {
      final db = CollaborationDatabase(NativeDatabase.memory());
      final transport = InboxTransport();
      final repo = CollaborationRepository(
        db,
        transport,
        MemorySessionStore(),
        clock: () => start,
        contentRouteGuard: const SyntheticContentRouteGuard(),
      );
      addTearDown(repo.close);
      await repo.initialize();
      await repo.login(
        serverUrl: 'https://example.test/',
        username: 'alice',
        password: 'synthetic',
      );
      final scope = await repo.createScope('Inbox');
      await repo.syncNow();
      SharedInboxEntry entry(int id, {DateTime? readAt, int revision = 1}) =>
          SharedInboxEntry(
            id: id,
            revision: revision,
            sequence: id,
            scopeId: scope,
            kind: 'task.created',
            category: 'tasks',
            audience: InboxAudience.scope,
            targetType: 'task',
            targetId: 'task',
            groupKey: '$id',
            createdAt: start.subtract(const Duration(days: 100)),
            readAt: readAt,
          );
      final expired = entry(1, readAt: start.subtract(inboxReadRetention));
      final unread = entry(2);
      final pending = entry(3, readAt: expired.readAt);
      final partition = repo.state.session!.partition;
      for (final e in [expired, unread, pending]) {
        await db.execute('INSERT INTO inbox(partition,id,data) VALUES(?,?,?)', [
          partition,
          e.id,
          jsonEncode(e.toJson()),
        ]);
      }
      await db.execute(
        'INSERT INTO commands(id,partition,operation,params,entity_key) VALUES(?,?,?,?,?)',
        ['pending-read', partition, 'inbox.read', '{}', 'inbox:3'],
      );
      await repo.refreshLocal();
      expect(repo.state.inbox.map((e) => e.id), [3, 2]);
      expect(
        projectOrganizerInbox(
          personal: null,
          shared: repo.state,
          effectivePlans: [],
          now: start,
        ).shared.single.group.ids,
        [2],
      );
      expect(
        await db.rows("SELECT id FROM commands WHERE id='pending-read'"),
        hasLength(1),
      );
      await db.execute("DELETE FROM commands WHERE id='pending-read'");
      transport.inbox = [expired.withReadAt(null)];
      await repo.syncNow();
      expect(repo.state.inbox.any((e) => e.id == 1), isFalse);
      transport.inbox = [entry(1, revision: 2)];
      await repo.syncNow();
      expect(repo.state.inbox.firstWhere((e) => e.id == 1).isRead, isFalse);
    },
  );

  test(
    'missed remote unread-read cycle uses the new canonical read timestamp',
    () async {
      final db = CollaborationDatabase(NativeDatabase.memory());
      final transport = InboxTransport();
      final repo = CollaborationRepository(
        db,
        transport,
        MemorySessionStore(),
        clock: () => start,
        contentRouteGuard: const SyntheticContentRouteGuard(),
      );
      addTearDown(repo.close);
      await repo.initialize();
      await repo.login(
        serverUrl: 'https://example.test/',
        username: 'alice',
        password: 'synthetic',
      );
      final scope = await repo.createScope('Cycle');
      await repo.syncNow();
      SharedInboxEntry entry(int revision, DateTime readAt) => SharedInboxEntry(
        id: 1,
        revision: revision,
        sequence: revision,
        scopeId: scope,
        kind: 'task.created',
        category: 'tasks',
        audience: InboxAudience.scope,
        targetType: 'task',
        targetId: 'task',
        groupKey: 'task',
        createdAt: start.subtract(const Duration(days: 100)),
        readAt: readAt,
      );
      transport.inbox = [entry(2, start.subtract(const Duration(days: 6)))];
      await repo.syncNow();
      transport.inbox = [entry(4, start)];
      await repo.syncNow();
      expect(repo.state.inbox.single.readAt, start);
    },
  );

  test(
    'offline shared receipt ACK preserves original timestamp; expired missing ACK clears notification only',
    () async {
      final db = CollaborationDatabase(NativeDatabase.memory());
      final transport = InboxTransport();
      var now = start;
      final repo = CollaborationRepository(
        db,
        transport,
        MemorySessionStore(),
        clock: () => now,
        contentRouteGuard: const SyntheticContentRouteGuard(),
      );
      addTearDown(repo.close);
      await repo.initialize();
      await repo.login(
        serverUrl: 'https://example.test/',
        username: 'alice',
        password: 'synthetic',
      );
      final scope = await repo.createScope('Offline ACK');
      await repo.syncNow();
      final entry = SharedInboxEntry(
        id: 1,
        revision: 1,
        sequence: 1,
        scopeId: scope,
        kind: 'task.created',
        category: 'tasks',
        audience: InboxAudience.scope,
        targetType: 'task',
        targetId: 'task',
        groupKey: 'task',
        createdAt: start,
      );
      transport.inbox = [entry];
      await repo.syncNow();
      await repo.markInboxRead([1]);
      now = start.add(const Duration(days: 6));
      await repo.markInboxRead([1]);
      expect(repo.state.inbox.single.readAt, start);
      transport.serverReadAt = now;
      await repo.syncNow();
      expect(repo.state.inbox.single.readAt, start);
      await repo.markInboxRead([1], read: false);
      expect(repo.state.inbox.single.readAt, isNull);
      now = start.add(inboxReadRetention);
      transport.missingRead = true;
      transport.inbox = [];
      await repo.syncNow();
      expect(repo.state.inbox, isEmpty);
      expect(
        await db.rows("SELECT id FROM commands WHERE operation='inbox.read'"),
        isEmpty,
      );
      expect(
        repo.state.scopes.singleWhere((s) => s.id == scope).blocked,
        isFalse,
      );
      expect(
        repo.state.scopes.singleWhere((s) => s.id == scope).revoked,
        isFalse,
      );
    },
  );
}
