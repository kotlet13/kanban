import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/data/collaboration_transport.dart';
import 'package:kanban/organizer/data/device_session_store.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';

class MemorySessionStore implements DeviceSessionStore {
  DeviceSession? value;
  bool failWrite = false;
  Future<void> Function()? beforeWrite;
  @override
  Future<DeviceSession?> read() async => value;
  @override
  Future<void> write(DeviceSession session) async {
    await beforeWrite?.call();
    if (failWrite) throw const CollaborationException('secure_storage');
    value = session;
  }

  @override
  Future<void> clear() async {
    value = null;
  }
}

class FakeServer {
  String serverId = newSharedId();
  final accountIds = {'alice': newSharedId(), 'bob': newSharedId()};
  final tokens = <String, String>{};
  final scopes = <String, Map<String, dynamic>>{};
  final members = <String, Map<String, String>>{};
  final records = <String, Map<String, Map<String, dynamic>>>{};
  final sequence = <String, int>{};
  final replay = <String, ({String request, Map<String, dynamic> reply})>{};
  final calls =
      <({String operation, String? token, Map<String, Object?> params})>[];
  bool loseNextPushReply = false;
  Future<void> Function(
    String operation,
    String? token,
    Map<String, Object?> params,
  )?
  beforeCall;
  Object? _clone(Object? value) => jsonDecode(jsonEncode(value));
  Future<Map<String, dynamic>> call(
    String operation,
    Map<String, Object?> params,
    String? token,
  ) async {
    calls.add((operation: operation, token: token, params: params));
    await beforeCall?.call(operation, token, params);
    if (operation == 'capabilities') {
      return {
        'serverId': serverId,
        'recordContractVersions': [1],
        'api': 'familyhub_native',
        'version': 1,
        'enabled': true,
        'features': {'recordSync': true, 'inbox': false, 'finance': false},
      };
    }
    if (operation == 'auth.login') {
      final user = params['username'] as String;
      final device = newSharedId(), deviceToken = newSharedId();
      tokens[deviceToken] = user;
      return {
        'serverId': serverId,
        'user': {
          'id': user == 'alice' ? 1 : 2,
          'accountId': accountIds[user],
          'username': user,
          'displayName': user,
        },
        'device': {'id': device, 'name': 'Test', 'expiresAt': 4102444800},
        'token': deviceToken,
      };
    }
    final user = tokens[token];
    if (user == null) throw const CollaborationApiException('device_revoked');
    if (operation == 'auth.revoke') {
      tokens.remove(token);
      return {'revoked': true};
    }
    if (operation == 'scopes.list') {
      return {
        'scopes': scopes.entries
            .where((r) => members[r.key]!.containsKey(user))
            .map((r) => {...r.value, 'role': members[r.key]![user]})
            .toList(),
      };
    }
    final scope = params['scopeId'] as String?;
    if (operation == 'scopes.create') {
      final id = params['id'] as String;
      scopes[id] = {
        'id': id,
        'name': params['name'],
        'kind': params['kind'],
        'sequence': 0,
      };
      members[id] = {user: 'owner'};
      records[id] = {};
      sequence[id] = 0;
      return {
        'scope': {...scopes[id]!, 'role': 'owner'},
      };
    }
    final role = members[scope]?[user];
    if (role == null) {
      throw const CollaborationApiException('permission_revoked');
    }
    if (operation == 'sync.pull') {
      final cursor = params['cursor'] as int,
          limit = params['limit'] as int? ?? 100;
      final found =
          records[scope]!.values
              .where((r) => (r['sequence'] as int) > cursor)
              .toList()
            ..sort(
              (a, b) => (a['sequence'] as int).compareTo(b['sequence'] as int),
            );
      final page = found.take(limit).toList();
      final more = found.length > limit;
      return {
        'records': _clone(page),
        'cursor': more ? page.last['sequence'] : sequence[scope],
        'hasMore': more,
        'scopeSequence': sequence[scope],
      };
    }
    if (operation == 'sync.push') {
      if (role == 'viewer') {
        throw const CollaborationApiException('permission_revoked');
      }
      final op = params['operation'] as Map<String, dynamic>,
          opId = op['opId'] as String;
      final serialized = jsonEncode(params), prior = replay[opId];
      if (prior != null) {
        if (prior.request != serialized) {
          throw const CollaborationApiException('idempotency_mismatch');
        }
        return Map<String, dynamic>.from(_clone(prior.reply) as Map);
      }
      final id = op['recordId'] as String, current = records[scope]![id];
      if ((current?['revision'] ?? 0) != op['expectedRevision'] ||
          current?['deleted'] == true) {
        throw CollaborationApiException(
          'conflict',
          details: {'serverRecord': _clone(current)},
        );
      }
      if (op['deleted'] == true) {
        final childType = op['type'] == 'project' ? 'task' : 'shoppingItem',
            field = op['type'] == 'project' ? 'projectId' : 'listId';
        if (['project', 'shoppingList'].contains(op['type']) &&
            records[scope]!.values.any(
              (r) =>
                  r['type'] == childType &&
                  r['deleted'] == false &&
                  (r['payload'] as Map)[field] == id,
            )) {
          throw CollaborationApiException(
            'live_children',
            details: {'serverRecord': _clone(current)},
          );
        }
      } else {
        final payload = op['payload'] as Map;
        final parent = op['type'] == 'task'
            ? payload['projectId']
            : op['type'] == 'shoppingItem'
            ? payload['listId']
            : null;
        if (parent != null &&
            (records[scope]![parent] == null ||
                records[scope]![parent]!['deleted'] == true)) {
          throw CollaborationApiException(
            'parent_missing',
            details: {'serverRecord': _clone(current)},
          );
        }
      }
      final canonical = {
        'id': id,
        'type': op['type'],
        'revision': (current?['revision'] as int? ?? 0) + 1,
        'deleted': op['deleted'],
        'payload': _clone(op['payload']),
        'sequence': sequence[scope!] = sequence[scope]! + 1,
        'updatedAt': '2026-10-04T12:00:00.000Z',
      };
      records[scope]![id] = canonical;
      final reply = {
        'status': 'applied',
        'record': canonical,
        'cursor': sequence[scope],
        'replayed': false,
      };
      replay[opId] = (
        request: serialized,
        reply: Map<String, dynamic>.from(_clone(reply) as Map),
      );
      if (loseNextPushReply) {
        loseNextPushReply = false;
        throw const CollaborationException('network');
      }
      return Map<String, dynamic>.from(_clone(reply) as Map);
    }
    throw const CollaborationApiException('unsupported_operation');
  }
}

class FakeTransport implements CollaborationTransport {
  FakeTransport(this.server);
  final FakeServer server;
  bool offline = false;
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
    if (offline) throw const CollaborationException('network');
    return server.call(operation, params, token);
  }

  @override
  void close() {}
}

Matcher code(String value) =>
    isA<CollaborationException>().having((e) => e.code, 'code', value);

class PausingDatabase extends CollaborationDatabase {
  PausingDatabase(super.executor);
  Future<void> Function(String sql)? beforeRead;
  @override
  Future<List<Map<String, dynamic>>> rows(
    String sql, [
    List<Object?> args = const [],
  ]) async {
    await beforeRead?.call(sql);
    return super.rows(sql, args);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Separate files/executors are intentional; the debug heuristic only counts classes.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late Directory directory;
  late FakeServer server;
  final repositories = <CollaborationRepository>[];
  Future<CollaborationRepository> open(
    String file,
    MemorySessionStore store, {
    FakeTransport? transport,
  }) async {
    final repo = CollaborationRepository(
      CollaborationDatabase(
        NativeDatabase(File('${directory.path}/$file.sqlite')),
      ),
      transport ?? FakeTransport(server),
      store,
    );
    await repo.initialize();
    repositories.add(repo);
    return repo;
  }

  Future<void> login(CollaborationRepository repo, String user) => repo.login(
    serverUrl: 'https://synthetic.invalid/kanboard',
    username: user,
    password: 'synthetic-password',
  );
  Future<String> shared(
    CollaborationRepository a,
    CollaborationRepository b,
  ) async {
    final scope = await a.createScope('Test');
    server.members[scope]!['bob'] = 'member';
    await b.syncNow();
    return scope;
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('shared-tests-');
    server = FakeServer();
  });
  tearDown(() async {
    for (final repo in repositories) {
      await repo.close();
    }
    repositories.clear();
    await directory.delete(recursive: true);
  });

  test(
    'offline record and immutable outbox survive real SQLite close/reopen',
    () async {
      final store = MemorySessionStore(), transport = FakeTransport(server);
      var a = await open('a', store, transport: transport);
      await login(a, 'alice');
      final scope = await a.createScope('Test');
      transport.offline = true;
      final list = await a.createShoppingList(scopeId: scope, title: 'Milk');
      final item = await a.createShoppingItem(
        scopeId: scope,
        listId: list,
        title: 'Bread',
        quantity: '2',
      );
      await a.setShoppingItemChecked(scope, item, true);
      final before = await a.exportUnsentWork();
      expect(a.state.pendingCount, 3);
      await a.close();
      repositories.remove(a);
      a = await open('a', store, transport: transport);
      expect(a.state.dataForScope(scope).shoppingItems.single.isChecked, true);
      expect(await a.exportUnsentWork(), before);
      transport.offline = false;
      await a.syncNow();
      expect(a.state.pendingCount, 0);
      expect(server.records[scope]!.length, 2);
      expect(server.records[scope]![item]!['revision'], 2);
    },
  );
  test(
    'ambiguous successful push retries exact op before newer edit',
    () async {
      final a = await open('a', MemorySessionStore());
      await login(a, 'alice');
      final scope = await a.createScope('Test');
      final list = await a.createShoppingList(scopeId: scope, title: 'First');
      server.loseNextPushReply = true;
      await a.syncNow();
      expect(a.state.pendingCount, 1);
      final draft = a.state.dataForScope(scope).shoppingLists.single;
      await a.updateShoppingList(scope, draft.copyWith(title: 'Second'));
      await a.syncNow();
      final pushes = server.calls
          .where((r) => r.operation == 'sync.push')
          .toList();
      expect(pushes.length, 3);
      expect(jsonEncode(pushes[0].params), jsonEncode(pushes[1].params));
      expect(server.records[scope]![list]!['revision'], 2);
      expect(a.state.dataForScope(scope).shoppingLists.single.title, 'Second');
    },
  );
  test(
    'two clients conflict preserves candidate and newest remote resolution',
    () async {
      final a = await open('a', MemorySessionStore()),
          b = await open('b', MemorySessionStore());
      await login(a, 'alice');
      await login(b, 'bob');
      final scope = await shared(a, b);
      final list = await a.createShoppingList(
        scopeId: scope,
        title: 'Original',
      );
      await a.syncNow();
      await b.syncNow();
      await a.updateShoppingList(
        scope,
        a.state.dataForScope(scope).shoppingLists.single.copyWith(title: 'A2'),
      );
      await a.syncNow();
      await b.updateShoppingList(
        scope,
        b.state
            .dataForScope(scope)
            .shoppingLists
            .single
            .copyWith(title: 'B draft'),
      );
      final gate = Completer<void>(), entered = Completer<void>();
      server.beforeCall = (op, token, params) async {
        if (op == 'sync.pull' &&
            token == server.calls.last.token &&
            !entered.isCompleted) {
          entered.complete();
          await gate.future;
        }
      };
      final syncing = b.syncNow();
      await entered.future;
      await a.updateShoppingList(
        scope,
        a.state.dataForScope(scope).shoppingLists.single.copyWith(title: 'A3'),
      );
      server.beforeCall = null;
      await a.syncNow();
      gate.complete();
      await syncing;
      expect(b.state.dataForScope(scope).shoppingLists.single.title, 'B draft');
      expect(b.state.conflicts.single.remotePayload!['title'], 'A3');
      await b.resolveConflict(
        conflictId: b.state.conflicts.single.id,
        keepLocal: false,
      );
      expect(b.state.dataForScope(scope).shoppingLists.single.title, 'A3');
      expect(server.records[scope]![list]!['revision'], 3);
    },
  );
  test(
    'revocation blocks pending work, regain does not send without consent',
    () async {
      final a = await open('a', MemorySessionStore()),
          bt = FakeTransport(server),
          b = await open('b', MemorySessionStore(), transport: bt);
      await login(a, 'alice');
      await login(b, 'bob');
      final scope = await shared(a, b);
      bt.offline = true;
      await b.createShoppingList(scopeId: scope, title: 'My unsent');
      server.members[scope]!.remove('bob');
      bt.offline = false;
      await b.syncNow();
      expect(b.state.blockedCount, 1);
      expect(b.state.scopes.single.revoked, true);
      expect(b.state.dataForScope(scope).shoppingLists, isEmpty);
      expect(await b.exportUnsentWork(), contains('My unsent'));
      server.members[scope]!['bob'] = 'member';
      await b.syncNow();
      expect(b.state.blockedCount, 1);
      expect(server.records[scope], isEmpty);
      await b.resumeBlockedChanges(scope);
      expect(b.state.pendingCount, 0);
      expect(server.records[scope]!.length, 1);
    },
  );
  test('viewer downgrade blocks writes without losing drafts', () async {
    final a = await open('a', MemorySessionStore()),
        b = await open('b', MemorySessionStore());
    await login(a, 'alice');
    await login(b, 'bob');
    final scope = await shared(a, b);
    await b.createShoppingList(scopeId: scope, title: 'Draft');
    server.members[scope]!['bob'] = 'viewer';
    await b.syncNow();
    expect(b.state.blockedCount, 1);
    expect(b.state.scopes.single.role, SharedRole.viewer);
    await expectLater(
      b.createShoppingList(scopeId: scope, title: 'Denied'),
      throwsA(code('changes_blocked')),
    );
  });
  test(
    'signed out and different account cannot export previous drafts',
    () async {
      final a = await open('a', MemorySessionStore());
      await login(a, 'alice');
      final scope = await a.createScope('Test');
      await a.createShoppingList(scopeId: scope, title: 'Alice private');
      await a.signOut();
      await expectLater(a.exportUnsentWork(), throwsA(code('auth_required')));
      expect(a.state.data, isEmpty);
      await login(a, 'bob');
      expect(await a.exportUnsentWork(), isNot(contains('Alice private')));
      expect(a.state.data, isEmpty);
    },
  );
  test(
    'late login A cannot erase already successful login B across restart',
    () async {
      final store = MemorySessionStore();
      var a = await open('a', store);
      final gate = Completer<void>(), entered = Completer<void>();
      server.beforeCall = (op, token, params) async {
        if (op == 'auth.login' && params['username'] == 'alice') {
          entered.complete();
          await gate.future;
        }
      };
      final first = login(a, 'alice');
      final firstError = expectLater(first, throwsA(code('session_changed')));
      await entered.future;
      await login(a, 'bob');
      gate.complete();
      await firstError;
      expect(store.value!.profile.username, 'bob');
      await a.close();
      repositories.remove(a);
      a = await open('a', store);
      expect(a.state.session!.username, 'bob');
    },
  );
  test(
    'signout during pending secure write removes that device and hides account',
    () async {
      final store = MemorySessionStore(),
          a = await open('a', store),
          gate = Completer<void>(),
          entered = Completer<void>();
      store.beforeWrite = () async {
        entered.complete();
        await gate.future;
      };
      final auth = login(a, 'alice');
      final authError = expectLater(auth, throwsA(code('session_changed')));
      await entered.future;
      final logout = a.signOut();
      gate.complete();
      await logout;
      await authError;
      expect(store.value, isNull);
      expect(a.state.session, isNull);
    },
  );
  test(
    'failed secure write never activates login and revokes issued token',
    () async {
      final store = MemorySessionStore()..failWrite = true,
          a = await open('a', store);
      await expectLater(login(a, 'alice'), throwsA(code('secure_storage')));
      expect(a.state.session, isNull);
      expect(store.value, isNull);
      expect(server.tokens, isEmpty);
    },
  );
  test(
    'server or account lifetime identity isolates reused numeric ID',
    () async {
      final a = await open('a', MemorySessionStore());
      await login(a, 'alice');
      final old = a.state.session!.partition,
          scope = await a.createScope('Test');
      await a.createShoppingList(scopeId: scope, title: 'Old lifetime');
      await a.signOut();
      server.serverId = newSharedId();
      server.accountIds['alice'] = newSharedId();
      server.scopes.clear();
      server.members.clear();
      await login(a, 'alice');
      expect(a.state.session!.partition, isNot(old));
      expect(a.state.data, isEmpty);
      expect(await a.exportUnsentWork(), isNot(contains('Old lifetime')));
    },
  );
  test(
    'copy parent and children rollback together on actual SQL write failure',
    () async {
      final a = await open('a', MemorySessionStore());
      await login(a, 'alice');
      final scope = await a.createScope('Test'), now = DateTime.now().toUtc();
      final list = LocalShoppingList(
            id: newSharedId(),
            title: 'Personal',
            createdAt: now,
            updatedAt: now,
          ),
          items = <LocalShoppingItem>[];
      for (var i = 0; i < 2; i++) {
        items.add(
          LocalShoppingItem(
            id: newSharedId(),
            listId: list.id,
            title: 'Item$i',
            quantity: '',
            isChecked: false,
            createdAt: now,
            updatedAt: now,
          ),
        );
      }
      await a.database.execute(
        "CREATE TRIGGER fail_child BEFORE INSERT ON outbox WHEN json_extract(NEW.request,'\$.type')='shoppingItem' BEGIN SELECT RAISE(ABORT,'synthetic failure'); END",
      );
      await expectLater(
        a.publishShoppingList(scopeId: scope, list: list, items: items),
        throwsA(anything),
      );
      await a.refreshLocal();
      expect(a.state.pendingCount, 0);
      expect(a.state.dataForScope(scope).shoppingLists, isEmpty);
      await a.database.execute('DROP TRIGGER fail_child');
      final copied = await a.publishShoppingList(
        scopeId: scope,
        list: list,
        items: items,
      );
      expect(copied, isNot(list.id));
      expect(a.state.pendingCount, 3);
      expect(
        a.state
            .dataForScope(scope)
            .shoppingItems
            .every((r) => r.listId == copied),
        true,
      );
      expect(list.title, 'Personal');
    },
  );
  test(
    'oversized UTF8 personal copy rejects before any half-copy survives',
    () async {
      final a = await open('a', MemorySessionStore());
      await login(a, 'alice');
      final scope = await a.createScope('Test'), now = DateTime.now().toUtc();
      final project = LocalProject(
        id: newSharedId(),
        title: 'Project',
        description: List.filled(2200, 'č').join(),
        createdAt: now,
        updatedAt: now,
      );
      await expectLater(
        a.publishProject(scopeId: scope, project: project, tasks: []),
        throwsA(code('validation_error')),
      );
      await a.refreshLocal();
      expect(a.state.pendingCount, 0);
      expect(a.state.dataForScope(scope).projects, isEmpty);
    },
  );
  test(
    'unseen child refuses parent delete without stalling unrelated changes',
    () async {
      final a = await open('a', MemorySessionStore()),
          b = await open('b', MemorySessionStore());
      await login(a, 'alice');
      await login(b, 'bob');
      final scope = await shared(a, b);
      final list = await a.createShoppingList(scopeId: scope, title: 'List');
      await a.syncNow();
      await b.syncNow();
      await b.createShoppingItem(scopeId: scope, listId: list, title: 'Unseen');
      await b.syncNow();
      await a.deleteShoppingList(scope, list);
      await a.createShoppingList(scopeId: scope, title: 'Unrelated');
      await a.syncNow();
      expect(a.state.conflicts.single.reason, 'live_children');
      expect(a.state.pendingCount, 1);
      expect(
        server.records[scope]!.values.any(
          (r) => (r['payload'] as Map?)?['title'] == 'Unrelated',
        ),
        true,
      );
      await a.resolveConflict(
        conflictId: a.state.conflicts.single.id,
        keepLocal: false,
      );
      expect(
        a.state.dataForScope(scope).shoppingLists.any((r) => r.id == list),
        true,
      );
    },
  );
  test(
    'offline item under remotely deleted parent becomes recoverable conflict',
    () async {
      final a = await open('a', MemorySessionStore()),
          b = await open('b', MemorySessionStore());
      await login(a, 'alice');
      await login(b, 'bob');
      final scope = await shared(a, b);
      final list = await a.createShoppingList(scopeId: scope, title: 'List');
      await a.syncNow();
      await b.syncNow();
      await b.createShoppingItem(
        scopeId: scope,
        listId: list,
        title: 'Unsent item',
      );
      await a.deleteShoppingList(scope, list);
      await a.syncNow();
      await b.syncNow();
      expect(b.state.conflicts.single.reason, 'parent_missing');
      expect(await b.exportUnsentWork(), contains('Unsent item'));
      await b.resolveConflict(
        conflictId: b.state.conflicts.single.id,
        keepLocal: false,
      );
      expect(b.state.pendingCount, 0);
    },
  );
  test(
    'concurrent sync calls claim one lease and send one operation',
    () async {
      final a = await open('a', MemorySessionStore());
      await login(a, 'alice');
      final scope = await a.createScope('Test');
      await a.createShoppingList(scopeId: scope, title: 'Only once');
      await Future.wait([a.syncNow(), a.syncNow()]);
      expect(server.calls.where((r) => r.operation == 'sync.push').length, 1);
    },
  );
  test(
    'old sync paused in DB cannot send account A payload with account B token',
    () async {
      final db = PausingDatabase(
            NativeDatabase(File('${directory.path}/paused.sqlite')),
          ),
          store = MemorySessionStore();
      final a = CollaborationRepository(db, FakeTransport(server), store);
      repositories.add(a);
      await a.initialize();
      await login(a, 'alice');
      final scope = await a.createScope('A scope');
      await a.createShoppingList(scopeId: scope, title: 'A draft');
      final entered = Completer<void>(), gate = Completer<void>();
      db.beforeRead = (sql) async {
        if (sql.contains("state='pending'") && !entered.isCompleted) {
          entered.complete();
          await gate.future;
        }
      };
      final syncing = a.syncNow();
      await entered.future;
      await login(a, 'bob');
      gate.complete();
      await syncing;
      expect(server.calls.where((r) => r.operation == 'sync.push'), isEmpty);
      expect(await a.exportUnsentWork(), isNot(contains('A draft')));
    },
  );
  test(
    'lease takeover before response commit leaves immutable op pending for retry',
    () async {
      final a = await open('a', MemorySessionStore());
      await login(a, 'alice');
      final scope = await a.createScope('Test');
      await a.createShoppingList(scopeId: scope, title: 'Draft');
      server.beforeCall = (operation, token, params) async {
        if (operation == 'sync.push') {
          await a.database.execute(
            "UPDATE sync_leases SET owner='other-client' WHERE partition=?",
            [a.state.session!.partition],
          );
          server.beforeCall = null;
        }
      };
      await a.syncNow();
      expect(a.state.pendingCount, 1);
      expect(a.state.lastError!.code, 'sync_lease_lost');
      await a.database.execute('DELETE FROM sync_leases');
      await a.syncNow();
      expect(a.state.pendingCount, 0);
      expect(server.records[scope]!.length, 1);
    },
  );
  test(
    'replayed old ACK materializes newer canonical already pulled while blocked',
    () async {
      final a = await open('a', MemorySessionStore()),
          b = await open('b', MemorySessionStore());
      await login(a, 'alice');
      await login(b, 'bob');
      final scope = await shared(a, b);
      await a.createShoppingList(scopeId: scope, title: 'Initial');
      await a.syncNow();
      await b.syncNow();
      await a.updateShoppingList(
        scope,
        a.state
            .dataForScope(scope)
            .shoppingLists
            .single
            .copyWith(title: 'Lost ACK candidate'),
      );
      server.loseNextPushReply = true;
      await a.syncNow();
      expect(a.state.pendingCount, 1);
      await b.syncNow();
      await b.updateShoppingList(
        scope,
        b.state
            .dataForScope(scope)
            .shoppingLists
            .single
            .copyWith(title: 'Newer canonical'),
      );
      await b.syncNow();
      server.members[scope]!['alice'] = 'viewer';
      await a.syncNow();
      expect(a.state.blockedCount, 1);
      expect(
        a.state.dataForScope(scope).shoppingLists.single.title,
        'Lost ACK candidate',
      );
      server.members[scope]!['alice'] = 'owner';
      await a.syncNow();
      await a.resumeBlockedChanges(scope);
      expect(a.state.pendingCount, 0);
      expect(
        a.state.dataForScope(scope).shoppingLists.single.title,
        'Newer canonical',
      );
      final row = (await a.database.rows(
        'SELECT server_revision FROM records WHERE partition=?',
        [a.state.session!.partition],
      )).single;
      expect(row['server_revision'], 3);
    },
  );
}
