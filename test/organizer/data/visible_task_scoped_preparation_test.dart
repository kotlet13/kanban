import 'dart:async';
import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/data/device_session_store.dart';
import 'package:kanban/organizer/data/e2ee/crypto_domain_router.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import '../support/synthetic_content_route_guard.dart';
import 'collaboration_repository_test.dart'
    show FakeServer, FakeTransport, MemorySessionStore, code;

// Repository/fence/deadline integration only. This reader is an explicit crypto
// seam; signed authority/projection verification is exercised in separate tests.
class _Reader implements CryptoDomainRouter, CryptoVisibleTaskMetadataReader {
  _Reader(this.server);
  final FakeServer server;
  final targets = <CryptoVisibleTaskMetadataTarget>[];
  final dispatched = <(String, Map<String, Object?>, Set<String>)>[];
  Completer<void>? entered, gate;
  bool missingEvidence = false, pending = false;
  Map<String, dynamic> scope(String id) => {
    ...server.scopes[id]!,
    'role': 'owner',
  };
  @override
  Future<Map<String, dynamic>?> prepareVisibleTaskMetadata({
    required DeviceSession session,
    required CryptoVisibleTaskMetadataTarget target,
  }) async {
    targets.add(target);
    if (entered?.isCompleted == false) {
      entered!.complete();
    }
    await gate?.future;
    if (missingEvidence) return null;
    return {
      'scopes': pending ? <Map<String, dynamic>>[] : [scope(target.scopeId)],
      'pendingCryptoScopeIds': pending ? [target.scopeId] : <String>[],
    };
  }

  @override
  Future<Map<String, dynamic>> dispatch({
    required DeviceSession session,
    required String operation,
    required Map<String, Object?> params,
    required Set<String> protectedScopeIds,
  }) async {
    dispatched.add((operation, Map.of(params), Set.of(protectedScopeIds)));
    if (operation == 'scopes.list') {
      return {
        'scopes': [for (final id in server.scopes.keys) scope(id)],
        'pendingCryptoScopeIds': <String>[],
      };
    }
    if (operation == 'sync.pull') {
      final id = params['scopeId'] as String, cursor = params['cursor'] as int;
      final records = server.records[id]!.values
          .where((r) => (r['sequence'] as int) > cursor)
          .toList();
      return Map<String, dynamic>.from(
        jsonDecode(
              jsonEncode({
                'records': records,
                'cursor': server.sequence[id],
                'hasMore': false,
                'scopeSequence': server.sequence[id],
              }),
            )
            as Map,
      );
    }
    throw StateError('Unexpected synthetic encrypted dispatch $operation');
  }
}

class _Fixture {
  _Fixture(
    this.repo,
    this.server,
    this.reader,
    this.scope,
    this.task,
    this.other,
    this.target,
  );
  final CollaborationRepository repo;
  final FakeServer server;
  final _Reader reader;
  final String scope, task, other;
  final NotificationTarget target;
  late String storedPartition;
}

Future<_Fixture> _fixture() async {
  final server = FakeServer();
  // One server for the real repository's legacy setup; no HTTP or platform keys.
  final actualTransport = FakeTransport(server), reader = _Reader(server);
  final repo = CollaborationRepository(
    CollaborationDatabase(NativeDatabase.memory()),
    actualTransport,
    MemorySessionStore(),
    contentRouteGuard: const SyntheticContentRouteGuard(),
    cryptoRouter: reader,
  );
  addTearDown(repo.close);
  await repo.initialize();
  await repo.login(
    serverUrl: 'https://test.invalid',
    username: 'alice',
    password: 'synthetic',
  );
  final scope = await repo.createScope('Selected');
  final task = await repo.createTask(scopeId: scope, title: 'Visible selected');
  final other = await repo.createScope('Unrelated');
  await repo.createTask(scopeId: other, title: 'Unrelated retained');
  await repo.syncNow();
  final session = repo.state.session!;
  await repo.database.execute(
    "INSERT INTO crypto_scope_state(partition,scope_id,domain,state,floor) VALUES(?,?,'content','active',2)",
    [session.partition, scope],
  );
  final target = NotificationTarget(
    serverUrl: session.serverUrl,
    serverId: session.serverId,
    accountId: session.accountId,
    scopeId: scope,
    records: [NotificationRecordTarget(type: 'task', recordId: task)],
  );
  final f = _Fixture(repo, server, reader, scope, task, other, target)
    ..storedPartition = session.partition;
  server.calls.clear();
  reader.targets.clear();
  reader.dispatched.clear();
  return f;
}

void _remoteEdit(_Fixture f, String title) {
  final original = f.server.records[f.scope]![f.task]!;
  f.server.records[f.scope]![f.task] = {
    ...original,
    'revision': (original['revision'] as int) + 1,
    'sequence': f.server.sequence[f.scope] = f.server.sequence[f.scope]! + 1,
    'payload': {...original['payload'] as Map, 'title': title},
  };
}

void main() {
  test(
    'typed protected preview coalesces exact target and never broadens foreign identity or unrelated scopes',
    () async {
      final f = await _fixture();
      _remoteEdit(f, 'Scoped remote edit');
      final untouched = await f.repo.database.rows(
        'SELECT * FROM scopes WHERE id=?',
        [f.other],
      );
      final cursor = await f.repo.database.rows(
        'SELECT cursor FROM scopes WHERE id=?',
        [f.scope],
      );
      f.reader.entered = Completer<void>();
      f.reader.gate = Completer<void>();
      final first = f.repo.refreshVisibleTaskTarget(f.target);
      await f.reader.entered!.future;
      final second = f.repo.refreshVisibleTaskTarget(f.target);
      expect(identical(first, second), isTrue);
      final foreign = NotificationTarget(
        serverUrl: f.target.serverUrl,
        serverId: f.target.serverId,
        accountId: newSharedId(),
        scopeId: f.scope,
        records: f.target.records,
      );
      expect(
        (await f.repo.refreshVisibleTaskTarget(foreign)).status,
        NotificationOpenStatus.wrongAccount,
      );
      expect(f.reader.targets, hasLength(1));
      expect(f.reader.targets.single.scopeId, f.scope);
      expect(f.reader.targets.single.recordId, f.task);
      f.reader.gate!.complete();
      expect((await first).status, NotificationOpenStatus.available);
      expect(f.reader.dispatched.map((e) => e.$1), ['sync.pull']);
      expect(f.reader.dispatched.single.$2['scopeId'], f.scope);
      expect(f.reader.dispatched.single.$3, {f.scope});
      expect(
        f.server.calls,
        isEmpty,
        reason:
            'Protected preview must not reach plain scopes or content transport',
      );
      expect(
        f.repo.state.dataForScope(f.scope).tasks.single.title,
        'Scoped remote edit',
      );
      expect(
        await f.repo.database.rows('SELECT * FROM scopes WHERE id=?', [
          f.other,
        ]),
        untouched,
      );
      expect(
        await f.repo.database.rows('SELECT cursor FROM scopes WHERE id=?', [
          f.scope,
        ]),
        cursor,
      );
    },
  );
  test(
    'typed missing evidence falls back encrypted while restore fence precedes target reader',
    () async {
      final f = await _fixture();
      f.reader.missingEvidence = true;
      expect(
        (await f.repo.refreshVisibleTaskTarget(f.target)).status,
        NotificationOpenStatus.available,
      );
      expect(f.reader.targets, hasLength(1));
      expect(f.reader.dispatched.map((e) => e.$1), [
        'scopes.list',
        'sync.pull',
      ]);
      expect(f.server.calls, isEmpty);
      await f.repo.database.execute(
        "INSERT INTO crypto_restore_fences(partition,minimum_transport,backup_id,state) VALUES(?,2,?,'requires_reconciliation')",
        [f.storedPartition, newSharedId()],
      );
      final before = await f.repo.database.rows(
        'SELECT * FROM records WHERE scope_id=?',
        [f.scope],
      );
      await expectLater(
        f.repo.refreshVisibleTaskTarget(f.target),
        throwsA(code('crypto_reconciliation_required')),
      );
      expect(f.reader.targets, hasLength(1));
      expect(f.reader.dispatched, hasLength(2));
      expect(f.server.calls, isEmpty);
      expect(
        await f.repo.database.rows('SELECT * FROM records WHERE scope_id=?', [
          f.scope,
        ]),
        before,
      );
    },
  );
  test(
    'typed pending target preserves visible cache without blocking or revoking scope',
    () async {
      final f = await _fixture();
      f.reader.pending = true;
      final before = await f.repo.database.rows(
        'SELECT * FROM scopes WHERE id=?',
        [f.scope],
      );
      final records = await f.repo.database.rows(
        'SELECT * FROM records WHERE scope_id=?',
        [f.scope],
      );
      expect(
        (await f.repo.refreshVisibleTaskTarget(f.target)).status,
        NotificationOpenStatus.requiresConnection,
      );
      expect(f.reader.targets, hasLength(1));
      expect(f.reader.dispatched, isEmpty);
      expect(f.server.calls, isEmpty);
      expect(
        await f.repo.database.rows('SELECT * FROM scopes WHERE id=?', [
          f.scope,
        ]),
        before,
      );
      expect(
        await f.repo.database.rows('SELECT * FROM records WHERE scope_id=?', [
          f.scope,
        ]),
        records,
      );
      expect(
        f.repo.state.scopes.singleWhere((s) => s.id == f.scope).revoked,
        isFalse,
      );
    },
  );
  test(
    'typed late preparation respects persisted block session deletion and original five second deadline',
    () async {
      for (final scenario in ['block', 'session', 'deletion', 'deadline']) {
        final f = await _fixture();
        _remoteEdit(f, 'Must not apply $scenario');
        final before = await f.repo.database.rows(
          'SELECT * FROM records WHERE scope_id=?',
          [f.scope],
        );
        f.reader.entered = Completer<void>();
        f.reader.gate = Completer<void>();
        final timer = Stopwatch()..start();
        final opening = f.repo.refreshVisibleTaskTarget(f.target);
        Future<void>? rejection;
        if (scenario == 'session') {
          rejection = expectLater(opening, throwsA(code('session_changed')));
        }
        if (scenario == 'deletion') {
          rejection = expectLater(opening, throwsA(code('deletion_pending')));
        }
        await f.reader.entered!.future;
        if (scenario == 'block') {
          await f.repo.database.execute(
            'UPDATE scopes SET blocked=1 WHERE id=?',
            [f.scope],
          );
        }
        if (scenario == 'session') await f.repo.signOut();
        if (scenario == 'deletion') {
          await f.repo.database.execute(
            'INSERT INTO local_meta(name,value) VALUES(?,?)',
            ['deletion_pending:${f.storedPartition}', '1'],
          );
        }
        if (scenario == 'deadline') {
          expect((await opening).status, NotificationOpenStatus.offline);
          expect(timer.elapsed, lessThan(const Duration(seconds: 7)));
          f.reader.gate!.complete();
          await Future<void>.delayed(Duration.zero);
        } else {
          f.reader.gate!.complete();
          if (rejection != null) {
            await rejection;
          } else {
            expect(
              (await opening).status,
              NotificationOpenStatus.permissionDenied,
            );
          }
        }
        expect(
          f.reader.dispatched,
          isEmpty,
          reason: '$scenario must stop before content pull',
        );
        expect(
          await f.repo.database.rows('SELECT * FROM records WHERE scope_id=?', [
            f.scope,
          ]),
          before,
          reason: scenario,
        );
        expect(
          f.server.calls.where(
            (c) =>
                c.operation != 'auth.revoke' && c.operation != 'capabilities',
          ),
          isEmpty,
          reason:
              '$scenario no plain fallback (logout may discover cleanup capabilities)',
        );
        await f.repo.close();
      }
    },
  );
}
