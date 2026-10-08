import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/data/collaboration_transport.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';

import 'collaboration_repository_test.dart'
    show FakeServer, FakeTransport, MemorySessionStore;

class ReminderTransport extends FakeTransport {
  ReminderTransport(super.server);
  bool loseReply = false, wrongReply = false, financeEnabled = false;
  String financeGrant = 'write';
  int policyRevision = 1;
  Future<void> Function()? beforeCommands;
  String? reject;
  Completer<void>? entered, release;
  final reminders = <String, Map<String, dynamic>>{};
  final replay = <String, Map<String, dynamic>>{};
  final calls =
      <({String operation, Map<String, Object?> params, String? token})>[];

  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
    if (offline) throw const CollaborationException('network');
    if (operation == 'capabilities') {
      final caps = await super.call(serverUrl: serverUrl, operation: operation);
      return {
        ...caps,
        'recordContractVersions': [1, 2],
        'financeContractVersions': [1, 2],
        'features': {
          'recordSync': true,
          'inbox': true,
          'finance': financeEnabled,
        },
      };
    }
    if (operation == 'inbox.sync') {
      await beforeCommands?.call();
      return {
        'items': [],
        'cursor': 0,
        'visibilityRevision': 1,
        'hasMore': false,
      };
    }
    if (operation == 'scopes.members') return {'members': []};
    if (operation == 'finance2.policy') {
      return {
        'enabled': true,
        'grant': financeGrant,
        'revision': policyRevision,
      };
    }
    if (operation == 'finance2.pull') {
      return {
        'records': [],
        'cursor': 0,
        'hasMore': false,
        'accessRevision': policyRevision,
      };
    }
    if (operation == 'inbox.preferences.get') return {'preferences': {}};
    if (operation == 'reminders.list') {
      return {
        'reminders': reminders.values
            .where((r) => r['scopeId'] == params['scopeId'])
            .toList(),
        'hasMore': false,
      };
    }
    if (operation == 'reminders.put' || operation == 'reminders.cancel') {
      calls.add((operation: operation, params: Map.of(params), token: token));
      entered?.complete();
      await release?.future;
      if (reject != null) throw CollaborationApiException(reject!);
      final request = params['requestId'] as String;
      if (replay.containsKey(request)) return replay[request]!;
      final id = params['id'] as String, old = reminders[id];
      if (params['expectedRevision'] != (old?['revision'] ?? 0)) {
        throw const CollaborationApiException('reminder_conflict');
      }
      final item = operation == 'reminders.put'
          ? <String, dynamic>{
              'id': id,
              'scopeId': params['scopeId'],
              'targetId': params['targetId'],
              'targetType': params['targetType'],
              'remindAt': params['remindAt'],
              'revision': (params['expectedRevision'] as int) + 1,
              'state': 'pending',
            }
          : {
              ...old!,
              'state': 'cancelled',
              'revision': (old['revision'] as int) + 1,
            };
      reminders[id] = item;
      final reply = {'reminder': Map<String, dynamic>.of(item)};
      replay[request] = reply;
      if (loseReply) {
        loseReply = false;
        throw const CollaborationException('network');
      }
      if (wrongReply) {
        return {
          'reminder': {...item, 'scopeId': newSharedId()},
        };
      }
      return reply;
    }
    return super.call(
      serverUrl: serverUrl,
      operation: operation == 'sync2.push'
          ? 'sync.push'
          : operation == 'sync2.pull'
          ? 'sync.pull'
          : operation,
      params: params,
      token: token,
      allowLocalHttp: allowLocalHttp,
    );
  }
}

final now = DateTime.utc(2026, 10, 8, 12);
final later = now.add(const Duration(days: 1));
Matcher code(String name) =>
    isA<CollaborationException>().having((e) => e.code, 'code', name);

Future<
  ({
    CollaborationRepository repo,
    ReminderTransport transport,
    MemorySessionStore store,
    String scope,
    String task,
  })
>
fixture({CollaborationDatabase? database, bool finance = false}) async {
  final transport = ReminderTransport(FakeServer()),
      store = MemorySessionStore();
  final repo = CollaborationRepository(
    database ?? CollaborationDatabase(NativeDatabase.memory()),
    transport,
    store,
    clock: () => now,
  );
  transport.financeEnabled = finance;
  await repo.initialize();
  await repo.login(
    serverUrl: 'https://example.test/',
    username: 'alice',
    password: 'synthetic',
  );
  final scope = await repo.createScope('Reminders');
  final task = await repo.createTask(
    scopeId: scope,
    title: 'Task',
    dueAt: later,
  );
  await repo.syncNow();
  return (
    repo: repo,
    transport: transport,
    store: store,
    scope: scope,
    task: task,
  );
}

Future<String> put(
  ({
    CollaborationRepository repo,
    ReminderTransport transport,
    MemorySessionStore store,
    String scope,
    String task,
  })
  f, {
  DateTime? date,
}) => f.repo.putReminder(
  scopeId: f.scope,
  targetType: 'task',
  targetId: f.task,
  remindAt: date ?? later,
);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  test(
    'future date, UUID, revision and immutable target guards leave no commands',
    () async {
      final f = await fixture();
      addTearDown(f.repo.close);
      for (final date in [now, now.subtract(const Duration(seconds: 1))]) {
        await expectLater(
          put(f, date: date),
          throwsA(code('validation_error')),
        );
      }
      await expectLater(
        f.repo.putReminder(
          id: 'bad',
          scopeId: f.scope,
          targetType: 'task',
          targetId: f.task,
          remindAt: later,
        ),
        throwsA(code('validation_error')),
      );
      expect(await f.repo.database.rows('SELECT * FROM commands'), isEmpty);
      final id = await put(f);
      final second = await f.repo.createTask(scopeId: f.scope, title: 'Other');
      final secondScope = await f.repo.createScope('Other scope');
      await expectLater(
        f.repo.putReminder(
          id: id,
          scopeId: f.scope,
          targetType: 'task',
          targetId: second,
          remindAt: later,
          expectedRevision: 1,
        ),
        throwsA(code('reminder_target_immutable')),
      );
      await expectLater(
        f.repo.putReminder(
          id: id,
          scopeId: f.scope,
          targetType: 'task',
          targetId: f.task,
          remindAt: later,
        ),
        throwsA(code('stale_edit')),
      );
      // A scope move is denied even if a forged duplicate target exists there.
      await f.repo.database.execute(
        'INSERT INTO records SELECT partition,?,id,type,local_revision,server_revision,payload,deleted,remote FROM records WHERE partition=? AND scope_id=? AND id=?',
        [secondScope, f.repo.state.session!.partition, f.scope, f.task],
      );
      await expectLater(
        f.repo.putReminder(
          id: id,
          scopeId: secondScope,
          targetType: 'task',
          targetId: f.task,
          remindAt: later,
          expectedRevision: 1,
        ),
        throwsA(code('reminder_target_immutable')),
      );
    },
  );

  test(
    'offline put, edit and cancel survive restart with ordered immutable revisions',
    () async {
      final dir = await Directory.systemTemp.createTemp('reminder-durable-');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/db.sqlite');
      final f = await fixture(
        database: CollaborationDatabase(NativeDatabase(file)),
      );
      f.transport.offline = true;
      final id = await put(f);
      await f.repo.putReminder(
        id: id,
        scopeId: f.scope,
        targetType: 'task',
        targetId: f.task,
        remindAt: later.add(const Duration(hours: 1)),
        expectedRevision: 1,
      );
      await f.repo.cancelReminder(f.repo.state.scheduledReminders.single);
      final commands = await f.repo.database.rows(
        'SELECT params FROM commands ORDER BY sequence',
      );
      expect(
        commands.map(
          (r) => (jsonDecode(r['params'] as String) as Map)['expectedRevision'],
        ),
        [0, 1, 2],
      );
      expect(f.repo.state.scheduledReminders.single.syncState, 'queued');
      await f.repo.close();
      final reopened = CollaborationRepository(
        CollaborationDatabase(NativeDatabase(file)),
        f.transport,
        f.store,
        clock: () => now,
      );
      addTearDown(reopened.close);
      await reopened.initialize();
      expect(reopened.state.scheduledReminders.single.state, 'cancelled');
      expect(reopened.state.scheduledReminders.single.syncState, 'queued');
      f.transport.offline = false;
      await reopened.syncNow();
      expect(reopened.state.lastError, isNull);
      expect(reopened.state.scheduledReminders.single.state, 'cancelled');
      expect(reopened.state.scheduledReminders.single.syncState, 'synced');
      expect(await reopened.database.rows('SELECT * FROM commands'), isEmpty);
      expect(f.transport.calls.map((c) => c.operation), [
        'reminders.put',
        'reminders.put',
        'reminders.cancel',
      ]);
    },
  );

  test(
    'lost acknowledgment replays identical command without duplicate reminder',
    () async {
      final f = await fixture();
      addTearDown(f.repo.close);
      await put(f);
      f.transport.loseReply = true;
      await f.repo.syncNow();
      expect(f.repo.state.scheduledReminders.single.syncState, 'queued');
      final first = f.transport.calls.single.params;
      await f.repo.syncNow();
      expect(f.transport.calls.last.params, first);
      expect(f.transport.reminders.length, 1);
      expect(f.repo.state.scheduledReminders.single.syncState, 'synced');
    },
  );

  test(
    'terminal rejection is visible, retained and explicit retry uses server revision',
    () async {
      final f = await fixture();
      addTearDown(f.repo.close);
      final id = await put(f);
      f.transport.reject = 'reminder_conflict';
      await f.repo.syncNow();
      final draft = f.repo.state.scheduledReminders.single;
      expect(draft.syncState, 'blocked');
      expect(draft.syncError, 'reminder_conflict');
      expect(
        (await f.repo.database.rows(
          'SELECT state FROM commands',
        )).single['state'],
        'blocked',
      );
      f.transport.reject = null;
      await f.repo.putReminder(
        id: id,
        scopeId: f.scope,
        targetType: 'task',
        targetId: f.task,
        remindAt: later,
        expectedRevision: draft.revision,
      );
      await f.repo.syncNow();
      expect(f.transport.calls.last.params['expectedRevision'], 0);
      expect(f.repo.state.scheduledReminders.single.syncState, 'synced');
      expect(await f.repo.database.rows('SELECT * FROM commands'), isEmpty);
      expect(f.repo.state.blockedCount, 0);
    },
  );

  test(
    'conflicting canonical revision is retained for explicit retry without silently scheduling draft',
    () async {
      final f = await fixture();
      addTearDown(f.repo.close);
      final id = await put(f);
      await f.repo.syncNow();
      f.transport.reminders[id] = {
        ...f.transport.reminders[id]!,
        'revision': 3,
      };
      await f.repo.putReminder(
        id: id,
        scopeId: f.scope,
        targetType: 'task',
        targetId: f.task,
        remindAt: later.add(const Duration(hours: 2)),
        expectedRevision: 1,
      );
      await f.repo.syncNow();
      final blocked = f.repo.state.scheduledReminders.single;
      expect(blocked.syncState, 'blocked');
      expect(blocked.remindAt, later.add(const Duration(hours: 2)));
      await f.repo.putReminder(
        id: id,
        scopeId: f.scope,
        targetType: 'task',
        targetId: f.task,
        remindAt: blocked.remindAt,
        expectedRevision: blocked.revision,
      );
      await f.repo.syncNow();
      expect(f.transport.calls.last.params['expectedRevision'], 3);
      expect(f.repo.state.scheduledReminders.single.revision, 4);
      expect(f.repo.state.scheduledReminders.single.syncError, isNull);
    },
  );

  test(
    'cancel rejected create finishes locally and forged cancellation cannot change binding',
    () async {
      final f = await fixture();
      addTearDown(f.repo.close);
      await put(f);
      final original = f.repo.state.scheduledReminders.single;
      final forged = SharedScheduledReminder.fromJson({
        ...original.toJson(),
        'scopeId': newSharedId(),
      });
      await expectLater(
        f.repo.cancelReminder(forged),
        throwsA(code('reminder_target_immutable')),
      );
      f.transport.reject = 'reminder_target_unavailable';
      await f.repo.syncNow();
      await f.repo.cancelReminder(f.repo.state.scheduledReminders.single);
      expect(f.repo.state.scheduledReminders.single.state, 'cancelled');
      expect(f.repo.state.scheduledReminders.single.syncState, 'synced');
      expect(f.transport.calls, hasLength(1));
      expect(await f.repo.database.rows('SELECT * FROM commands'), isEmpty);
      expect(f.repo.state.blockedCount, 0);
    },
  );

  test(
    'completion and due date edits cancel old queued schedules atomically; title edits preserve them',
    () async {
      final f = await fixture();
      addTearDown(f.repo.close);
      await put(f);
      await f.repo.updateTask(
        f.scope,
        f.repo.state
            .dataForScope(f.scope)
            .tasks
            .single
            .copyWith(title: 'Updated title'),
      );
      expect(f.repo.state.scheduledReminders.single.state, 'pending');
      await f.repo.updateTask(
        f.scope,
        f.repo.state
            .dataForScope(f.scope)
            .tasks
            .single
            .copyWith(dueAt: later.add(const Duration(hours: 2))),
      );
      expect(f.repo.state.scheduledReminders.single.state, 'cancelled');
      expect(f.repo.state.scheduledReminders.single.syncState, 'blocked');
      await f.repo.syncNow();
      expect(f.transport.calls, isEmpty);
      await put(f);
      await f.repo.updateTask(
        f.scope,
        f.repo.state
            .dataForScope(f.scope)
            .tasks
            .single
            .copyWith(isCompleted: true),
      );
      expect(
        f.repo.state.scheduledReminders.every((r) => r.state == 'cancelled'),
        true,
      );
      await expectLater(put(f), throwsA(code('reminder_target_unavailable')));
    },
  );

  test(
    'archived scope blocks queued put before sending; viewer and revoked scope cannot create',
    () async {
      final f = await fixture();
      addTearDown(f.repo.close);
      final id = await put(f);
      f.transport.server.scopes[f.scope]!['archived'] = true;
      await f.repo.syncNow();
      expect(f.transport.calls, isEmpty);
      expect(f.repo.state.scheduledReminders, isEmpty);
      final stored = (await f.repo.database.rows(
        'SELECT data FROM scheduled_reminders WHERE id=?',
        [id],
      )).single;
      expect(
        (jsonDecode(stored['data'] as String) as Map)['syncError'],
        'scope_archived',
      );
      await expectLater(put(f), throwsA(isA<CollaborationException>()));
      f.transport.server.scopes[f.scope]!['archived'] = false;
      f.transport.server.members[f.scope]!['alice'] = 'viewer';
      await f.repo.syncNow();
      await expectLater(put(f), throwsA(isA<CollaborationException>()));
      f.transport.server.members[f.scope]!.remove('alice');
      await f.repo.syncNow();
      await expectLater(put(f), throwsA(isA<CollaborationException>()));
    },
  );

  test(
    'captured account prevents a dialog save or cancel under another identity',
    () async {
      final f = await fixture();
      addTearDown(f.repo.close);
      await put(f);
      final reminder = f.repo.state.scheduledReminders.single;
      final oldPartition = f.repo.state.session!.partition;
      await f.repo.signOut();
      await f.repo.login(
        serverUrl: 'https://example.test/',
        username: 'bob',
        password: 'synthetic',
      );
      await expectLater(
        f.repo.putReminder(
          scopeId: f.scope,
          targetType: 'task',
          targetId: f.task,
          remindAt: later,
          expectedPartition: oldPartition,
        ),
        throwsA(code('session_changed')),
      );
      await expectLater(
        f.repo.cancelReminder(reminder, expectedPartition: oldPartition),
        throwsA(code('session_changed')),
      );
      expect(f.transport.calls, isEmpty);
    },
  );

  test(
    'late acknowledgment after signout cannot clear old durable command',
    () async {
      final f = await fixture();
      addTearDown(f.repo.close);
      await put(f);
      f.transport.entered = Completer<void>();
      f.transport.release = Completer<void>();
      final syncing = f.repo.syncNow();
      await f.transport.entered!.future;
      await f.repo.signOut();
      f.transport.release!.complete();
      await syncing;
      expect(
        (await f.repo.database.rows(
          'SELECT state FROM commands',
        )).single['state'],
        'pending',
      );
      expect(f.repo.state.session, isNull);
    },
  );

  test(
    'wrong-scope acknowledgment rolls back and retains pending command',
    () async {
      final f = await fixture();
      addTearDown(f.repo.close);
      await put(f);
      f.transport.wrongReply = true;
      await f.repo.syncNow();
      expect(f.repo.state.lastError, code('invalid_response'));
      expect(f.repo.state.scheduledReminders.single.syncState, 'queued');
      expect(
        (await f.repo.database.rows(
          'SELECT state FROM commands',
        )).single['state'],
        'pending',
      );
    },
  );

  test(
    'event time changes and deletion cancel a queued schedule; title changes do not',
    () async {
      final f = await fixture();
      addTearDown(f.repo.close);
      final event = await f.repo.createEvent(
        scopeId: f.scope,
        title: 'Event',
        startAt: later,
      );
      await f.repo.putReminder(
        scopeId: f.scope,
        targetType: 'event',
        targetId: event,
        remindAt: later,
      );
      await f.repo.updateEvent(
        f.scope,
        f.repo.state
            .dataForScope(f.scope)
            .events
            .single
            .copyWith(title: 'New title'),
      );
      expect(f.repo.state.scheduledReminders.single.state, 'pending');
      await f.repo.updateEvent(
        f.scope,
        f.repo.state
            .dataForScope(f.scope)
            .events
            .single
            .copyWith(startAt: later.add(const Duration(hours: 1))),
      );
      expect(f.repo.state.scheduledReminders.single.state, 'cancelled');
      await f.repo.putReminder(
        scopeId: f.scope,
        targetType: 'event',
        targetId: event,
        remindAt: later,
      );
      await f.repo.deleteEvent(f.scope, event);
      expect(
        f.repo.state.scheduledReminders.every((r) => r.state == 'cancelled'),
        true,
      );
    },
  );

  test(
    'finance plannedAt reschedule and posting cancel pending schedule with read rights separate from write',
    () async {
      final f = await fixture(finance: true);
      addTearDown(f.repo.close);
      final account = await f.repo.createFinanceAccount(
        scopeId: f.scope,
        name: 'Ledger',
        currency: 'EUR',
      );
      final id = await f.repo.createFinanceEntry(
        scopeId: f.scope,
        accountId: account,
        kind: FinanceEntryKind.expense,
        status: SharedFinanceStatus.planned,
        amountMinor: 100,
        currency: 'EUR',
        title: 'Invoice',
        occurredAt: later,
      );
      await f.repo.putReminder(
        scopeId: f.scope,
        targetType: 'financeEntry',
        targetId: id,
        remindAt: later,
      );
      await f.repo.updateFinanceEntry(
        f.scope,
        f.repo.state
            .dataForScope(f.scope)
            .financeEntries
            .single
            .copyWith(plannedAt: later.add(const Duration(hours: 1))),
      );
      expect(f.repo.state.scheduledReminders.single.state, 'cancelled');
      await f.repo.putReminder(
        scopeId: f.scope,
        targetType: 'financeEntry',
        targetId: id,
        remindAt: later,
      );
      await f.repo.updateFinanceEntry(
        f.scope,
        f.repo.state
            .dataForScope(f.scope)
            .financeEntries
            .single
            .copyWith(status: SharedFinanceStatus.posted),
      );
      expect(
        f.repo.state.scheduledReminders.every((r) => r.state == 'cancelled'),
        true,
      );
      await expectLater(
        f.repo.putReminder(
          scopeId: f.scope,
          targetType: 'financeEntry',
          targetId: id,
          remindAt: later,
        ),
        throwsA(code('reminder_target_unavailable')),
      );
    },
  );

  test(
    'finance read-only grant may schedule; revoked finance access hides reminder and retains blocked command',
    () async {
      final f = await fixture(finance: true);
      addTearDown(f.repo.close);
      final account = await f.repo.createFinanceAccount(
        scopeId: f.scope,
        name: 'Ledger',
        currency: 'EUR',
      );
      final id = await f.repo.createFinanceEntry(
        scopeId: f.scope,
        accountId: account,
        kind: FinanceEntryKind.expense,
        status: SharedFinanceStatus.planned,
        amountMinor: 100,
        currency: 'EUR',
        title: 'Invoice',
        occurredAt: later,
      );
      f.transport.financeGrant = 'read';
      f.transport.policyRevision = 2;
      await f.repo.refreshFinancePolicy(f.scope);
      await f.repo.putReminder(
        scopeId: f.scope,
        targetType: 'financeEntry',
        targetId: id,
        remindAt: later,
      );
      final reminder = f.repo.state.scheduledReminders.single;
      f.transport.financeGrant = 'none';
      f.transport.policyRevision = 3;
      await f.repo.refreshFinancePolicy(f.scope);
      expect(f.repo.state.scheduledReminders, isEmpty);
      await expectLater(
        f.repo.cancelReminder(reminder),
        throwsA(code('finance_forbidden')),
      );
      await expectLater(
        f.repo.putReminder(
          scopeId: f.scope,
          targetType: 'financeEntry',
          targetId: id,
          remindAt: later,
        ),
        throwsA(code('finance_forbidden')),
      );
      expect(
        (await f.repo.database.rows(
          'SELECT state FROM commands',
        )).single['state'],
        'blocked',
      );
      await f.repo.syncNow();
      expect(f.transport.calls, isEmpty);
    },
  );

  test(
    'queue insertion failure rolls back reminder and cancellation marker changes',
    () async {
      final f = await fixture();
      addTearDown(f.repo.close);
      await f.repo.database.execute(
        "CREATE TRIGGER reminder_queue_fail BEFORE INSERT ON commands WHEN NEW.operation='reminders.put' BEGIN SELECT RAISE(ABORT, 'injected failure'); END",
      );
      await expectLater(put(f), throwsA(anything));
      expect(f.repo.state.scheduledReminders, isEmpty);
      expect(
        await f.repo.database.rows('SELECT * FROM scheduled_reminders'),
        isEmpty,
      );
      expect(await f.repo.database.rows('SELECT * FROM commands'), isEmpty);
    },
  );

  test(
    'missing local scope becomes terminal rejection instead of stopping the command queue',
    () async {
      final f = await fixture();
      addTearDown(f.repo.close);
      await put(f);
      f.transport.beforeCommands = () async {
        f.transport.beforeCommands = null;
        await f.repo.database.execute(
          'DELETE FROM records WHERE partition=? AND scope_id=?',
          [f.repo.state.session!.partition, f.scope],
        );
        await f.repo.database.execute(
          'DELETE FROM scopes WHERE partition=? AND id=?',
          [f.repo.state.session!.partition, f.scope],
        );
      };
      await f.repo.syncNow();
      expect(f.transport.calls, isEmpty);
      expect(
        (await f.repo.database.rows(
          'SELECT state FROM commands',
        )).single['state'],
        'blocked',
      );
      final json =
          jsonDecode(
                (await f.repo.database.rows(
                      'SELECT data FROM scheduled_reminders',
                    )).single['data']
                    as String,
              )
              as Map;
      expect(json['syncError'], 'permission_revoked');
    },
  );
  test(
    'delayed old ACK does not clear a newer rejected reminder edit',
    () async {
      final f = await fixture();
      addTearDown(f.repo.close);
      final id = await put(f);
      f.transport.entered = Completer<void>();
      f.transport.release = Completer<void>();
      final syncing = f.repo.syncNow();
      await f.transport.entered!.future;
      await f.repo.putReminder(
        id: id,
        scopeId: f.scope,
        targetType: 'task',
        targetId: f.task,
        remindAt: later.add(const Duration(hours: 1)),
        expectedRevision: 1,
      );
      await f.repo.updateTask(
        f.scope,
        f.repo.state
            .dataForScope(f.scope)
            .tasks
            .single
            .copyWith(dueAt: later.add(const Duration(days: 1))),
      );
      f.transport.release!.complete();
      await syncing;
      final commands = await f.repo.database.rows(
        'SELECT state,params FROM commands',
      );
      expect(commands, hasLength(1));
      expect(commands.single['state'], 'blocked');
      expect(
        (jsonDecode(commands.single['params'] as String)
            as Map)['expectedRevision'],
        1,
      );
      expect(f.repo.state.blockedCount, 1);
    },
  );
  test(
    'explicit confirmed cancellation clears older rejected edits of same reminder',
    () async {
      final f = await fixture();
      addTearDown(f.repo.close);
      final id = await put(f);
      await f.repo.syncNow();
      await f.repo.putReminder(
        id: id,
        scopeId: f.scope,
        targetType: 'task',
        targetId: f.task,
        remindAt: later.add(const Duration(hours: 1)),
        expectedRevision: 1,
      );
      f.transport.reject = 'reminder_conflict';
      await f.repo.syncNow();
      expect(f.repo.state.blockedCount, 1);
      f.transport.reject = null;
      await f.repo.cancelReminder(f.repo.state.scheduledReminders.single);
      await f.repo.syncNow();
      expect(f.repo.state.scheduledReminders.single.state, 'cancelled');
      expect(f.repo.state.scheduledReminders.single.syncState, 'synced');
      expect(f.repo.state.blockedCount, 0);
      expect(await f.repo.database.rows('SELECT * FROM commands'), isEmpty);
    },
  );
  test(
    'legacy reminder snapshots infer queued or blocked status from durable commands',
    () async {
      final f = await fixture();
      addTearDown(f.repo.close);
      await put(f);
      await f.repo.database.execute(
        r"UPDATE scheduled_reminders SET data=json_remove(data,'$.syncState')",
      );
      await f.repo.refreshLocal();
      expect(f.repo.state.scheduledReminders.single.syncState, 'queued');
      await f.repo.database.execute("UPDATE commands SET state='blocked'");
      await f.repo.refreshLocal();
      expect(f.repo.state.scheduledReminders.single.syncState, 'blocked');
    },
  );
}
