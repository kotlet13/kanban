import 'dart:async';
import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/data/device_session_store.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import '../support/synthetic_content_route_guard.dart';
import 'collaboration_repository_test.dart'
    show FakeServer, FakeTransport, MemorySessionStore;

class AccessReviewTransport extends FakeTransport {
  AccessReviewTransport(super.server, this.profile);
  final AccountSession profile;
  final calls = <String>[];
  Future<void> Function()? gate;
  Object? fail;
  List<String> pending = [], omitted = [];
  bool cyclic = false;
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
    calls.add(operation);
    if (operation == 'account.changes')
      return {
        'version': 1,
        'serverId': profile.serverId,
        'accountId': profile.accountId,
        'deviceId': profile.deviceId,
        'cursor': 'unchanged',
        'changed': false,
        'resetRequired': false,
        'hasMore': false,
        'directoryHintsVersion': 1,
        'accountDomains': <String>[],
        'scopes': <Object>[],
      };
    if (operation == 'scopes.list') {
      await gate?.call();
      if (fail != null) throw fail!;
    }
    final result = await super.call(
      serverUrl: serverUrl,
      operation: operation,
      params: params,
      token: token,
      allowLocalHttp: allowLocalHttp,
    );
    if (operation == 'capabilities')
      return {
        ...result,
        'accountChangeVersions': [1],
      };
    if (operation == 'scopes.list') {
      final scopes = (result['scopes'] as List)
          .where((s) => !omitted.contains(s['id']))
          .toList();
      if (cyclic) scopes.first['parentScopeId'] = scopes.first['id'];
      return {
        ...result,
        'scopes': scopes.reversed.toList(),
        'pendingCryptoScopeIds': pending,
      };
    }
    return result;
  }
}

class AccessReviewFixture {
  AccessReviewFixture(
    this.repo,
    this.transport,
    this.server,
    this.store,
    this.parent,
    this.child,
  );
  final CollaborationRepository repo;
  final AccessReviewTransport transport;
  final FakeServer server;
  final MemorySessionStore store;
  final String parent, child;
  String get p => store.value!.profile.partition;
  Future<void> block(String id) async {
    final rows = await repo.database.rows(
      'SELECT data FROM scopes WHERE partition=? AND id=?',
      [p, id],
    );
    final data =
        jsonDecode(rows.single['data'] as String) as Map<String, dynamic>;
    await repo.database.execute(
      'UPDATE scopes SET data=?,blocked=1 WHERE partition=? AND id=?',
      [
        jsonEncode({...data, 'revoked': true}),
        p,
        id,
      ],
    );
    await repo.refreshLocal();
  }
}

Future<AccessReviewFixture> setup({int count = 2}) async {
  final server = FakeServer()..moderationSupported = false;
  final profile = AccountSession(
    serverUrl: 'https://example.test/',
    serverId: server.serverId,
    accountId: server.accountIds['alice']!,
    userId: 1,
    username: 'alice',
    displayName: 'A',
    deviceId: newSharedId(),
    expiresAt: DateTime.utc(2030),
  );
  final store = MemorySessionStore()..value = DeviceSession(profile, 'token');
  server.tokens['token'] = 'alice';
  final db = CollaborationDatabase(NativeDatabase.memory());
  await db.rows('SELECT name FROM local_meta LIMIT 1');
  await db.execute('INSERT INTO accounts(partition,profile) VALUES(?,?)', [
    profile.partition,
    jsonEncode(profile.toJson()),
  ]);
  final parent = newSharedId(), child = newSharedId();
  for (var i = 0; i < count; i++) {
    final id = i == 0
        ? parent
        : i == 1
        ? child
        : newSharedId();
    final scope = SharedScope(
      id: id,
      name: 'Scope $i',
      kind: i == 0 ? SharedScopeKind.organization : SharedScopeKind.project,
      role: SharedRole.owner,
      parentScopeId: i == 0 ? null : parent,
      accessPolicyVersion: 1,
      sequence: 3,
    );
    server.scopes[id] = scope.toJson();
    server.members[id] = {'alice': 'owner'};
    server.records[id] = {};
    server.sequence[id] = 3;
    await db.execute(
      'INSERT INTO scopes(partition,id,data,blocked) VALUES(?,?,?,?)',
      [profile.partition, id, jsonEncode(scope.toJson()), 0],
    );
  }
  await db.execute('INSERT INTO local_meta(name,value) VALUES(?,?)', [
    'capabilities:${profile.partition}',
    jsonEncode({
      'features': {'recordSync': true, 'scopeAccessChanges': true},
      'accountChangeVersions': [1],
    }),
  ]);
  await db.execute('INSERT INTO local_meta(name,value) VALUES(?,?)', [
    'account_changes_v1:${profile.partition}:${profile.deviceId}',
    'unchanged',
  ]);
  final t = AccessReviewTransport(server, profile);
  final repo = CollaborationRepository(
    db,
    t,
    store,
    contentRouteGuard: const SyntheticContentRouteGuard(),
  );
  addTearDown(repo.close);
  await repo.initialize();
  return AccessReviewFixture(repo, t, server, store, parent, child);
}

void main() {
  test(
    'cold start repairs cached revocation despite unchanged cursor, next polls stay lightweight',
    () async {
      final f = await setup();
      await f.block(f.parent);
      await f.repo.syncNow();
      final parent = f.repo.state.scopes.singleWhere((s) => s.id == f.parent);
      expect(parent.revoked, false);
      expect(parent.blocked, false);
      expect(
        f.repo.state.scopes.singleWhere((s) => s.id == f.child).canRead,
        true,
      );
      expect(f.transport.calls.where((s) => s == 'scopes.list').length, 1);
      expect(
        f.transport.calls.any((s) => s.contains('pull') || s.contains('batch')),
        false,
      );
      f.transport.calls.clear();
      await f.repo.syncNow();
      await f.repo.syncNow();
      expect(f.transport.calls, ['account.changes', 'account.changes']);
    },
  );
  test(
    '14 spaces use one logical access list, concurrent manual checks coalesce',
    () async {
      final f = await setup(count: 14);
      final gate = Completer<void>();
      final entered = Completer<void>();
      f.transport.gate = () async {
        if (!entered.isCompleted) entered.complete();
        await gate.future;
      };
      final start = f.repo.syncNow();
      await entered.future;
      final a = f.repo.checkAllAccess(), b = f.repo.checkAllAccess();
      gate.complete();
      await start;
      final result = await a;
      expect(identical(await b, result), true);
      expect(result.available, 14);
      expect(result.unresolved, 0);
      expect(f.transport.calls.where((s) => s == 'scopes.list').length, 1);
    },
  );
  test(
    'confirmed revocation remains blocked; omission is unresolved and not revoked',
    () async {
      final f = await setup();
      f.server.confirmRevocation(f.parent, 'alice');
      f.transport.omitted = [f.child];
      final result = await f.repo.checkAllAccess();
      expect(result.revoked, 1);
      expect(result.unresolved, 1);
      expect(
        f.repo.state.scopes.singleWhere((s) => s.id == f.parent).revoked,
        true,
      );
      final child = f.repo.state.scopes.singleWhere((s) => s.id == f.child);
      expect(child.revoked, false);
      expect(child.blocked, true);
    },
  );
  test(
    'offline failure leaves scopes byte identical, later same coordinator retries',
    () async {
      final f = await setup();
      await f.block(f.parent);
      final before = await f.repo.database.rows(
        'SELECT * FROM scopes ORDER BY id',
      );
      f.transport.fail = const CollaborationException('network');
      await expectLater(
        f.repo.syncNow(),
        throwsA(isA<CollaborationException>()),
      );
      expect(
        await f.repo.database.rows('SELECT * FROM scopes ORDER BY id'),
        before,
      );
      f.transport.fail = null;
      await f.repo.syncNow();
      expect(
        f.repo.state.scopes.singleWhere((s) => s.id == f.parent).revoked,
        false,
      );
    },
  );
  test(
    'pending proof cannot clear old block; manual check can finish after proof arrives',
    () async {
      final f = await setup();
      await f.block(f.parent);
      f.transport.pending = [f.parent];
      final first = await f.repo.checkAllAccess();
      expect(first.unresolved, 1);
      expect(first.restored, 0);
      expect(
        f.repo.state.scopes.singleWhere((s) => s.id == f.parent).revoked,
        true,
      );
      f.transport.pending = [];
      final next = await f.repo.checkAllAccess();
      expect(next.restored, 1);
      expect(
        f.repo.state.scopes.singleWhere((s) => s.id == f.parent).blocked,
        false,
      );
    },
  );
  test('cyclic access response changes no local scope', () async {
    final f = await setup();
    await f.block(f.parent);
    final before = await f.repo.database.rows(
      'SELECT * FROM scopes ORDER BY id',
    );
    f.transport.cyclic = true;
    await expectLater(
      f.repo.checkAllAccess(),
      throwsA(isA<CollaborationException>()),
    );
    expect(
      await f.repo.database.rows('SELECT * FROM scopes ORDER BY id'),
      before,
    );
  });
  test(
    'stale scope sequence does not resurrect or overwrite newer metadata',
    () async {
      final f = await setup();
      await f.block(f.parent);
      f.server.scopes[f.parent]!['sequence'] = 2;
      final r = await f.repo.checkAllAccess();
      expect(r.unresolved, 1);
      expect(r.restored, 0);
      expect(
        f.repo.state.scopes.singleWhere((s) => s.id == f.parent).revoked,
        true,
      );
    },
  );
}
