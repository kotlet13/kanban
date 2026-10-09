import 'dart:async';
import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'collaboration_repository_test.dart'
    show FakeServer, FakeTransport, MemorySessionStore, code;

void main() {
  Future<
    ({
      CollaborationRepository repo,
      FakeServer server,
      FakeTransport transport,
      String scope,
      String task,
      NotificationTarget target,
    })
  >
  fixture() async {
    final server = FakeServer(), transport = FakeTransport(server);
    final repo = CollaborationRepository(
      CollaborationDatabase(NativeDatabase.memory()),
      transport,
      MemorySessionStore(),
    );
    await repo.initialize();
    addTearDown(repo.close);
    await repo.login(
      serverUrl: 'https://test.invalid',
      username: 'alice',
      password: 'synthetic',
    );
    final scope = await repo.createScope('Test');
    final task = await repo.createTask(scopeId: scope, title: 'Visible');
    await repo.syncNow();
    final session = repo.state.session!;
    final target = NotificationTarget(
      serverUrl: session.serverUrl,
      serverId: session.serverId,
      accountId: session.accountId,
      scopeId: scope,
      records: [NotificationRecordTarget(type: 'task', recordId: task)],
    );
    server.calls.clear();
    return (
      repo: repo,
      server: server,
      transport: transport,
      scope: scope,
      task: task,
      target: target,
    );
  }

  test(
    'visible task refresh uses two reads, no negotiate or account sync',
    () async {
      final f = await fixture();
      final result = await f.repo.refreshVisibleTaskTarget(f.target);
      expect(result.status, NotificationOpenStatus.available);
      expect(f.server.calls.map((c) => c.operation), [
        'scopes.list',
        'sync.pull',
      ]);
      expect(f.server.calls.last.params['scopeId'], f.scope);
      expect(f.server.calls.last.params['limit'], 100);
    },
  );
  test('external target retains server validation before opening', () async {
    final f = await fixture();
    final result = await f.repo.openNotificationTarget(f.target);
    expect(result.status, NotificationOpenStatus.available);
    expect(
      f.server.calls.where((c) => c.operation == 'capabilities'),
      hasLength(2),
    );
    expect(
      f.server.calls.where((c) => c.operation == 'scopes.list'),
      hasLength(2),
    );
  });
  test(
    'targeted pull preserves an unsent draft, immutable outbox and full-sync cursor',
    () async {
      final f = await fixture();
      final partition = f.repo.state.session!.partition;
      final beforeCursor = await f.repo.database.rows(
        'SELECT cursor FROM scopes WHERE id=?',
        [f.scope],
      );
      f.transport.offline = true;
      await f.repo.updateTask(
        f.scope,
        f.repo.state
            .dataForScope(f.scope)
            .tasks
            .single
            .copyWith(title: 'Local draft'),
      );
      final beforeQueue = await f.repo.database.rows('SELECT * FROM outbox');
      final remote = f.server.records[f.scope]![f.task]!;
      f.server.records[f.scope]![f.task] = {
        ...remote,
        'revision': (remote['revision'] as int) + 1,
        'sequence': f.server.sequence[f.scope] =
            f.server.sequence[f.scope]! + 1,
        'payload': {...remote['payload'] as Map, 'title': 'Remote title'},
      };
      f.transport.offline = false;
      expect(
        (await f.repo.refreshVisibleTaskTarget(f.target)).status,
        NotificationOpenStatus.available,
      );
      expect(
        f.repo.state.dataForScope(f.scope).tasks.single.title,
        'Local draft',
      );
      expect(await f.repo.database.rows('SELECT * FROM outbox'), beforeQueue);
      expect(
        await f.repo.database.rows('SELECT cursor FROM scopes WHERE id=?', [
          f.scope,
        ]),
        beforeCursor,
      );
      final row = (await f.repo.database.rows(
        'SELECT remote FROM records WHERE partition=? AND scope_id=? AND id=?',
        [partition, f.scope, f.task],
      )).single;
      expect(
        (jsonDecode(row['remote'] as String)['payload'] as Map)['title'],
        'Remote title',
      );
      expect(f.server.calls.map((c) => c.operation), [
        'scopes.list',
        'sync.pull',
      ]);
    },
  );
  test('singleflight does not authorize another account target', () async {
    final f = await fixture(),
        entered = Completer<void>(),
        gate = Completer<void>();
    f.server.beforeCall = (op, _, _) async {
      if (op == 'scopes.list') {
        entered.complete();
        await gate.future;
      }
    };
    final first = f.repo.refreshVisibleTaskTarget(f.target);
    await entered.future;
    final second = f.repo.refreshVisibleTaskTarget(f.target);
    expect(identical(first, second), isTrue);
    final other = NotificationTarget(
      serverUrl: f.target.serverUrl,
      serverId: f.target.serverId,
      accountId: 'another-account',
      scopeId: f.scope,
      records: f.target.records,
    );
    expect(
      (await f.repo.refreshVisibleTaskTarget(other)).status,
      NotificationOpenStatus.wrongAccount,
    );
    gate.complete();
    expect((await first).status, NotificationOpenStatus.available);
    expect(f.server.calls.map((c) => c.operation), [
      'scopes.list',
      'sync.pull',
    ]);
  });
  test(
    'offline preserves visible unsent task without sending its outbox',
    () async {
      final f = await fixture();
      f.transport.offline = true;
      final task = await f.repo.createTask(scopeId: f.scope, title: 'Unsent');
      final target = NotificationTarget(
        serverUrl: f.target.serverUrl,
        serverId: f.target.serverId,
        accountId: f.target.accountId,
        scopeId: f.scope,
        records: [NotificationRecordTarget(type: 'task', recordId: task)],
      );
      expect(
        (await f.repo.refreshVisibleTaskTarget(target)).status,
        NotificationOpenStatus.offline,
      );
      expect(f.repo.state.pendingCount, 1);
      expect(
        f.repo.state.dataForScope(f.scope).tasks.any((t) => t.id == task),
        isTrue,
      );
      expect(f.server.calls, isEmpty);
    },
  );
  test('revoked membership blocks cache and returns denial', () async {
    final f = await fixture();
    f.server.members[f.scope]!.remove('alice');
    expect(
      (await f.repo.refreshVisibleTaskTarget(f.target)).status,
      NotificationOpenStatus.permissionDenied,
    );
    expect(f.repo.state.scopes.single.revoked, isTrue);
    expect(f.repo.state.dataForScope(f.scope).tasks, isEmpty);
    expect(f.server.calls.map((c) => c.operation), ['scopes.list']);
  });
  test(
    'late positive scope response cannot undo a database access block',
    () async {
      final f = await fixture(),
          entered = Completer<void>(),
          gate = Completer<void>();
      f.server.beforeCall = (op, _, _) async {
        if (op == 'scopes.list') {
          entered.complete();
          await gate.future;
        }
      };
      final opening = f.repo.refreshVisibleTaskTarget(f.target);
      await entered.future;
      await f.repo.database.execute('UPDATE scopes SET blocked=1 WHERE id=?', [
        f.scope,
      ]);
      gate.complete();
      expect((await opening).status, NotificationOpenStatus.permissionDenied);
      expect(f.repo.state.scopes.single.revoked, isTrue);
      expect(f.server.calls.map((c) => c.operation), ['scopes.list']);
    },
  );
  test(
    'late task response cannot apply after a persisted scope block',
    () async {
      final f = await fixture(),
          entered = Completer<void>(),
          gate = Completer<void>();
      final before = await f.repo.database.rows(
        'SELECT * FROM records WHERE id=?',
        [f.task],
      );
      f.server.beforeCall = (op, _, _) async {
        if (op == 'sync.pull') {
          entered.complete();
          await gate.future;
        }
      };
      final remote = f.server.records[f.scope]![f.task]!;
      f.server.records[f.scope]![f.task] = {
        ...remote,
        'revision': (remote['revision'] as int) + 1,
        'sequence': f.server.sequence[f.scope] =
            f.server.sequence[f.scope]! + 1,
        'payload': {
          ...remote['payload'] as Map,
          'title': 'Late forbidden content',
        },
      };
      final opening = f.repo.refreshVisibleTaskTarget(f.target);
      await entered.future;
      await f.repo.database.execute('UPDATE scopes SET blocked=1 WHERE id=?', [
        f.scope,
      ]);
      gate.complete();
      expect((await opening).status, NotificationOpenStatus.permissionDenied);
      expect(
        await f.repo.database.rows('SELECT * FROM records WHERE id=?', [
          f.task,
        ]),
        before,
      );
    },
  );
  test('late task response cannot apply after signing out', () async {
    final f = await fixture(),
        entered = Completer<void>(),
        gate = Completer<void>();
    f.server.beforeCall = (op, _, _) async {
      if (op == 'sync.pull') {
        entered.complete();
        await gate.future;
      }
    };
    final opening = f.repo.refreshVisibleTaskTarget(f.target);
    final expectation = expectLater(opening, throwsA(code('session_changed')));
    await entered.future;
    await f.repo.signOut();
    gate.complete();
    await expectation;
    expect(f.repo.state.session, isNull);
  });
  test(
    'financial or unknown targets cannot use visible task refresh',
    () async {
      final f = await fixture();
      final financial = NotificationTarget(
        serverUrl: f.target.serverUrl,
        serverId: f.target.serverId,
        accountId: f.target.accountId,
        scopeId: f.scope,
        records: [
          NotificationRecordTarget(type: 'financeEntry', recordId: f.task),
        ],
      );
      expect(
        () => f.repo.refreshVisibleTaskTarget(financial),
        throwsA(code('invalid_notification_target')),
      );
      final unknown = NotificationTarget(
        serverUrl: f.target.serverUrl,
        serverId: f.target.serverId,
        accountId: f.target.accountId,
        scopeId: f.scope,
        records: [
          const NotificationRecordTarget(type: 'task', recordId: 'unknown'),
        ],
      );
      expect(
        (await f.repo.refreshVisibleTaskTarget(unknown)).status,
        NotificationOpenStatus.requiresConnection,
      );
      expect(f.server.calls, isEmpty);
    },
  );
  test(
    'never completing server read returns offline within five seconds',
    () async {
      final f = await fixture();
      final gate = Completer<void>();
      f.server.beforeCall = (op, _, _) async {
        if (op == 'scopes.list') await gate.future;
      };
      final timer = Stopwatch()..start();
      expect(
        (await f.repo.refreshVisibleTaskTarget(f.target)).status,
        NotificationOpenStatus.offline,
      );
      expect(timer.elapsed, lessThan(const Duration(seconds: 7)));
      expect(f.repo.state.dataForScope(f.scope).tasks.single.title, 'Visible');
      gate.complete();
    },
  );
}
