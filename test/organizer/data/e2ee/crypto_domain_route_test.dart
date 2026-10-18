import '../../support/synthetic_content_route_guard.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/data/e2ee/crypto_domain_router.dart';
import 'package:kanban/organizer/data/e2ee/crypto_business_router.dart';
import 'package:kanban/organizer/data/e2ee/crypto_sync_repository.dart';
import 'package:kanban/organizer/data/e2ee/crypto_sync_store.dart';
import 'package:kanban/organizer/data/device_session_store.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart'
    show CollaborationException;

import '../collaboration_repository_test.dart'
    show FakeServer, FakeTransport, MemorySessionStore, code;

class _Router implements CryptoDomainRouter {
  final calls = <String>[];
  Future<void> Function()? beforeReply;
  @override
  Future<Map<String, dynamic>> dispatch({
    required DeviceSession session,
    required String operation,
    required Map<String, Object?> params,
    required Set<String> protectedScopeIds,
  }) async {
    calls.add(operation);
    await beforeReply?.call();
    return {'members': <Object>[]};
  }
}

class _EmailServer extends FakeServer {
  bool verified = false;
  @override
  Future<Map<String, dynamic>> call(
    String operation,
    Map<String, Object?> params,
    String? token,
  ) async {
    if (operation == 'account.status')
      return {
        'email': 'synthetic@example.invalid',
        'pendingEmail': null,
        'emailVerified': verified,
        'resetAvailable': true,
      };
    return super.call(operation, params, token);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('only exact projected proof releases an applied business receipt', () {
    final staged = <String, dynamic>{
      'scopeId': 'scope',
      'domain': 'content',
      'id': 'record',
      'type': 'task',
      'operationId': 'immutable-operation',
      'expectedRevision': 50,
      'deleted': false,
    };
    final current = <String, Object?>{
      'scope_id': 'scope',
      'domain': 'content',
      'id': 'record',
      'type': 'task',
      'crypto_revision': 50,
      'record_proof_hash': 'old-proof',
      'deleted': 0,
    };
    void verify(Map<String, Object?>? row) => requireExactBusinessProjection(
      record: row,
      stagedRecord: staged,
      stagedProofHash: 'staged-proof',
    );
    expect(() => verify(current), throwsA(isA<CryptoAuthorityPending>()));
    expect(() => verify(null), throwsA(isA<CryptoAuthorityPending>()));
    final exact = {
      ...current,
      'crypto_revision': 51,
      'record_proof_hash': 'staged-proof',
    };
    verify(exact);
    for (final changed in <Map<String, Object?>>[
      {...exact, 'record_proof_hash': 'another-intent'},
      {...exact, 'crypto_revision': 52},
      {...exact, 'type': 'event'},
      {...exact, 'deleted': 1},
    ]) {
      expect(() => verify(changed), throwsA(isA<CryptoAuthorityPending>()));
    }
  });
  for (final scenario in ['revoked', 'deletion', 'policy']) {
    test(
      'production request wrapper preserves $scenario gate on encrypted dispatch',
      () async {
        final server = FakeServer(), router = _Router();
        final db = CollaborationDatabase(NativeDatabase.memory());
        final repository = CollaborationRepository(
          db,
          FakeTransport(server),
          MemorySessionStore(),
          cryptoRouter: router,
          contentRouteGuard: const SyntheticContentRouteGuard(),
        );
        addTearDown(repository.close);
        await repository.initialize();
        await repository.login(
          serverUrl: 'https://synthetic.invalid/kanboard',
          username: 'alice',
          password: 'synthetic-password',
        );
        final scope = await repository.createScope('fixture');
        final partition = repository.state.session!.partition;
        await db.execute(
          "INSERT INTO crypto_scope_state(partition,scope_id,domain,state,epoch,floor) VALUES(?,?,?,'active',1,1)",
          [partition, scope, 'content'],
        );
        if (scenario == 'policy') {
          server.moderationAccepted = false;
          // Force fresh policy state; existing accepted local state is not authority
          // for a newly rejected server policy in this synthetic request.
          await repository.signOut();
          await repository.login(
            serverUrl: 'https://synthetic.invalid/kanboard',
            username: 'alice',
            password: 'synthetic-password',
          );
          router.calls.clear();
          await expectLater(
            repository.createScope('must not dispatch'),
            throwsA(code('policy_acceptance_required')),
          );
          expect(router.calls, isEmpty);
        } else {
          router.beforeReply = () async {
            if (scenario == 'revoked')
              throw const CollaborationException('device_revoked');
            await db.execute('INSERT INTO local_meta(name,value) VALUES(?,?)', [
              'deletion_pending:$partition',
              'true',
            ]);
          };
          await expectLater(
            repository.members(scope),
            throwsA(
              code(
                scenario == 'revoked' ? 'device_revoked' : 'deletion_pending',
              ),
            ),
          );
          if (scenario == 'revoked') {
            expect(
              await db.rows('SELECT value FROM local_meta WHERE name=?', [
                'invalid_session:$partition:${repository.state.session!.deviceId}',
              ]),
              isNotEmpty,
            );
          }
        }
      },
    );
  }
  test(
    'actual connected edit checks email before local commit; verified offline intent remains durable',
    () async {
      final db = CollaborationDatabase(NativeDatabase.memory()),
          server = _EmailServer(),
          sessions = MemorySessionStore();
      final prior = CollaborationRepository(
        db,
        FakeTransport(server),
        sessions,
        ownsDatabase: false,
        contentRouteGuard: const SyntheticContentRouteGuard(),
      );
      await prior.initialize();
      await prior.login(
        serverUrl: 'https://synthetic.invalid/kanboard',
        username: 'alice',
        password: 'synthetic-password',
      );
      final scope = await prior.createScope('existing local data');
      await prior.close();
      final transport = FakeTransport(server);
      final repository = CollaborationRepository(
        db,
        transport,
        sessions,
        cryptoRouter: _Router(),
      );
      addTearDown(repository.close);
      await repository.initialize();
      await expectLater(
        repository.createTask(scopeId: scope, title: 'must remain uncreated'),
        throwsA(code('email_verification_required')),
      );
      expect(await db.rows('SELECT * FROM outbox'), isEmpty);
      expect(await db.rows('SELECT * FROM records'), isEmpty);
      server.verified = true;
      await repository.accountStatus();
      transport.offline = true;
      final id = await repository.createTask(
        scopeId: scope,
        title: 'verified offline intent',
      );
      expect(
        await db.rows('SELECT * FROM outbox WHERE record_id=?', [id]),
        hasLength(1),
      );
    },
  );
  test(
    'checkpoint-created floor suppresses plaintext even an explicit legacy guard cannot downgrade it',
    () async {
      final server = FakeServer(),
          db = CollaborationDatabase(NativeDatabase.memory()),
          sessions = MemorySessionStore();
      final repository = CollaborationRepository(
        db,
        FakeTransport(server),
        sessions,
        contentRouteGuard: const SyntheticContentRouteGuard(),
      );
      addTearDown(repository.close);
      await repository.initialize();
      await repository.login(
        serverUrl: 'https://synthetic.invalid/kanboard',
        username: 'alice',
        password: 'synthetic-password',
      );
      final scope = await repository.createScope('fixture');
      await CryptoSyncStore(db, repository.state.session!.partition).checkpoint(
        scopeId: scope,
        domain: 'content',
        epoch: 2,
        accessRevision: 3,
        transportCursor: 0,
        projectionCursor: 0,
        scopeSequence: 0,
        complete: false,
      );
      server.calls.clear();
      await expectLater(
        repository.members(scope),
        throwsA(
          isA<CollaborationException>().having(
            (e) => e.code,
            'code',
            'crypto_reconciliation_required',
          ),
        ),
      );
      expect(
        server.calls.where((c) => c.operation == 'scopes.members'),
        isEmpty,
      );
    },
  );
  test(
    'actual existing task/sync path retains original queue and never downgrades after protected activation',
    () async {
      final server = FakeServer(),
          db = CollaborationDatabase(NativeDatabase.memory());
      final repository = CollaborationRepository(
        db,
        FakeTransport(server),
        MemorySessionStore(),
        contentRouteGuard: const SyntheticContentRouteGuard(),
      );
      addTearDown(repository.close);
      await repository.initialize();
      await repository.login(
        serverUrl: 'https://synthetic.invalid/kanboard',
        username: 'alice',
        password: 'synthetic-password',
      );
      final scope = await repository.createScope('fixture');
      final partition = repository.state.session!.partition;
      await db.execute(
        "INSERT INTO crypto_scope_state(partition,scope_id,domain,state,epoch,floor) VALUES(?,?,?,'active',1,1)",
        [partition, scope, 'content'],
      );
      server.calls.clear();
      final id = await repository.createTask(
        scopeId: scope,
        title: 'Secret remains local until crypto adapter ready',
      );
      await repository.syncNow();
      expect(
        server.calls.where(
          (c) => c.operation.startsWith('sync') || c.operation == 'scopes.list',
        ),
        isEmpty,
      );
      final row = (await db.rows('SELECT * FROM outbox WHERE record_id=?', [
        id,
      ])).single;
      expect(row['request'], contains('Secret remains local'));
      expect(row['state'], 'pending');
      expect(
        repository.state.lastError,
        code('crypto_reconciliation_required'),
      );
    },
  );
  test(
    'actual legacy member action dispatches to crypto router and never sends plaintext endpoint',
    () async {
      final server = FakeServer(),
          router = _Router(),
          db = CollaborationDatabase(NativeDatabase.memory());
      final repository = CollaborationRepository(
        db,
        FakeTransport(server),
        MemorySessionStore(),
        cryptoRouter: router,
        contentRouteGuard: const SyntheticContentRouteGuard(),
      );
      addTearDown(repository.close);
      await repository.initialize();
      await repository.login(
        serverUrl: 'https://synthetic.invalid/kanboard',
        username: 'alice',
        password: 'synthetic-password',
      );
      final scope = await repository.createScope('fixture');
      final partition = repository.state.session!.partition;
      await db.execute(
        "INSERT INTO crypto_scope_state(partition,scope_id,domain,state,epoch,floor) VALUES(?,?,?,'active',1,1)",
        [partition, scope, 'content'],
      );
      server.calls.clear();
      expect(await repository.members(scope), isEmpty);
      expect(router.calls, ['scopes.members']);
      expect(
        server.calls.where((c) => c.operation == 'scopes.members'),
        isEmpty,
      );
    },
  );
  test(
    'actual offline-phone repository restart discovers no local floor yet still holds plaintext outbox before startup sync',
    () async {
      final server = FakeServer(),
          db = CollaborationDatabase(NativeDatabase.memory()),
          sessions = MemorySessionStore();
      final transport = FakeTransport(server);
      final previous = CollaborationRepository(
        db,
        transport,
        sessions,
        ownsDatabase: false,
        contentRouteGuard: const SyntheticContentRouteGuard(),
      );
      await previous.initialize();
      await previous.login(
        serverUrl: 'https://synthetic.invalid/kanboard',
        username: 'alice',
        password: 'synthetic-password',
      );
      final scope = await previous.createScope('cached legacy scope');
      transport.offline = true;
      final id = await previous.createTask(
        scopeId: scope,
        title: 'Offline immutable legacy intent',
      );
      final original = (await db.rows(
        'SELECT request FROM outbox WHERE record_id=?',
        [id],
      )).single['request'];
      await previous.close();
      expect(await db.rows('SELECT * FROM crypto_scope_state'), isEmpty);
      server.calls.clear();
      final updated = CollaborationRepository(
        db,
        FakeTransport(server),
        sessions,
      );
      addTearDown(updated.close);
      await updated.initialize();
      await updated.syncNow();
      expect(
        server.calls.where(
          (c) =>
              c.operation.startsWith('sync') ||
              c.operation == 'personal.ensure' ||
              c.operation == 'scopes.list',
        ),
        isEmpty,
      );
      expect(
        (await db.rows('SELECT request,state FROM outbox WHERE record_id=?', [
          id,
        ])).single,
        {'request': original, 'state': 'pending'},
      );
      expect(updated.state.lastError, code('crypto_reconciliation_required'));
      // The synthetic old installation had already verified its account email;
      // crypto discovery pending does not erase that independent local evidence.
      await db.execute('INSERT INTO local_meta(name,value) VALUES(?,?)', [
        'verified_email:${updated.state.session!.partition}',
        'true',
      ]);
      // Existing local edits remain possible and queued, without a plaintext send.
      await updated.createTask(
        scopeId: scope,
        title: 'New encrypted-local pending intent',
      );
      expect(await db.rows('SELECT * FROM outbox'), hasLength(2));
    },
  );
}
