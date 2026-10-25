import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/data/device_session_store.dart';
import 'package:kanban/organizer/data/e2ee/crypto_domain_router.dart';
import 'package:kanban/organizer/data/e2ee/crypto_task_resolution.dart';
import '../support/synthetic_content_route_guard.dart';
import 'collaboration_repository_test.dart' show FakeServer, MemorySessionStore;
import 'organization_finance_client_test.dart'
    show OrganizationFinanceTransport;

class _Router implements CryptoDomainRouter, CryptoTaskDerivationDependencies {
  bool needed = false;
  final checked = <String>[];
  @override
  Future<bool> needsFinanceForTaskDerivations({
    required DeviceSession session,
    required String scopeId,
  }) async {
    checked.add(scopeId);
    return needed;
  }

  @override
  Future<Map<String, dynamic>> dispatch({
    required DeviceSession session,
    required String operation,
    required Map<String, Object?> params,
    required Set<String> protectedScopeIds,
  }) async =>
      throw StateError('Protected crypto dispatch is not a legacy fixture');
}

class _Transport extends OrganizationFinanceTransport {
  _Transport(super.server, this.store);
  final MemorySessionStore store;
  bool changed = false;
  final calls = <({String operation, String? scope})>[];
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
    calls.add((operation: operation, scope: params['scopeId'] as String?));
    if (operation == 'account.changes') {
      final p = store.value!.profile, reset = params['cursor'] == null;
      return {
        'version': 1,
        'serverId': p.serverId,
        'accountId': p.accountId,
        'deviceId': p.deviceId,
        'cursor': changed ? 'next' : 'initial',
        'changed': reset || changed,
        'resetRequired': reset,
        'hasMore': false,
        'accountDomains': <String>[],
        'scopes': changed
            ? [
                {
                  'scopeId': project,
                  'domains': ['content'],
                },
              ]
            : <Object>[],
      };
    }
    final result = await super.call(
      serverUrl: serverUrl,
      operation: operation,
      params: params,
      token: token,
      allowLocalHttp: allowLocalHttp,
    );
    return operation == 'capabilities'
        ? {
            ...result,
            'accountChangeVersions': [1],
          }
        : result;
  }
}

void main() {
  Future<
    ({
      CollaborationDatabase db,
      Future<void> Function(
        String,
        String,
        Map<String, dynamic>, {
        String hash,
        int deleted,
      })
      add,
    })
  >
  database() async {
    final db = CollaborationDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.rows('SELECT name FROM local_meta LIMIT 1');
    Future<void> add(
      String id,
      String type,
      Map<String, dynamic> raw, {
      String hash = 'intent-hash',
      int deleted = 0,
    }) => db.execute(
      'INSERT INTO crypto_business_records(partition,scope_id,domain,id,type,crypto_revision,record_proof_hash,deleted,raw_payload,projection,history_basis) VALUES(?,?,?,?,?,?,?,?,?,?,?)',
      [
        'p',
        'scope',
        type == 'taskDerivationIntent' ? 'content' : 'finance',
        id,
        type,
        1,
        hash,
        deleted,
        jsonEncode(raw),
        '{}',
        'verifiedCheckpoint',
      ],
    );
    return (db: db, add: add);
  }

  test(
    'dependency selected only for finance writer with unresolved linked intent',
    () async {
      final f = await database();
      await f.add('i', 'taskDerivationIntent', {'taskId': 'task'});
      await f.add('f', 'financeEntry', {'taskId': 'task'});
      expect(
        await cryptoNeedsTaskDerivationFinanceRefresh(
          f.db,
          'p',
          'scope',
          financeRole: 'write',
        ),
        isTrue,
      );
      expect(
        await cryptoNeedsTaskDerivationFinanceRefresh(
          f.db,
          'p',
          'scope',
          financeRole: 'read',
        ),
        isFalse,
      );
      expect(
        await cryptoNeedsTaskDerivationFinanceRefresh(
          f.db,
          'p',
          'scope',
          financeRole: 'none',
        ),
        isFalse,
      );
    },
  );
  test(
    'exact resolution hash drains dependency but stale resolution does not',
    () async {
      final f = await database();
      await f.add('i', 'taskDerivationIntent', {
        'taskId': 'task',
      }, hash: 'current');
      await f.add('f', 'financeEntry', {'taskId': 'task'});
      await f.add('r', 'taskDerivationResolution', {
        'intentProofHash': 'current',
        'state': 'derived',
      });
      expect(
        await cryptoNeedsTaskDerivationFinanceRefresh(
          f.db,
          'p',
          'scope',
          financeRole: 'write',
        ),
        isFalse,
      );
      await f.db.execute(
        'UPDATE crypto_business_records SET record_proof_hash=? WHERE id=?',
        ['new-current', 'i'],
      );
      expect(
        await cryptoNeedsTaskDerivationFinanceRefresh(
          f.db,
          'p',
          'scope',
          financeRole: 'write',
        ),
        isTrue,
      );
    },
  );
  test(
    'unrelated expense and deleted expense do not select finance work',
    () async {
      final f = await database();
      await f.add('i', 'taskDerivationIntent', {'taskId': 'task'});
      await f.add('unrelated', 'financeEntry', {'taskId': 'other'});
      expect(
        await cryptoNeedsTaskDerivationFinanceRefresh(
          f.db,
          'p',
          'scope',
          financeRole: 'write',
        ),
        isFalse,
      );
      await f.add('deleted', 'financeEntry', {'taskId': 'task'}, deleted: 1);
      expect(
        await cryptoNeedsTaskDerivationFinanceRefresh(
          f.db,
          'p',
          'scope',
          financeRole: 'write',
        ),
        isFalse,
      );
    },
  );
  test('expense without live intent cannot create dependency', () async {
    final f = await database();
    await f.add('f', 'personalFinanceEntry', {'taskId': 'task'});
    await f.add('i', 'taskDerivationIntent', {'taskId': 'task'}, deleted: 1);
    expect(
      await cryptoNeedsTaskDerivationFinanceRefresh(
        f.db,
        'p',
        'scope',
        financeRole: 'write',
      ),
      isFalse,
    );
  });
  Future<({CollaborationRepository repo, _Router router, _Transport transport})>
  setup() async {
    final store = MemorySessionStore(), router = _Router();
    final transport = _Transport(FakeServer(), store)..seed(parentAccess: true);
    final repo = CollaborationRepository(
      CollaborationDatabase(NativeDatabase.memory()),
      transport,
      store,
      contentRouteGuard: const SyntheticContentRouteGuard(),
      cryptoRouter: router,
    );
    addTearDown(repo.close);
    await repo.initialize();
    await repo.login(
      serverUrl: 'https://example.test/',
      username: 'alice',
      password: 'synthetic',
    );
    await repo.syncNow();
    expect(repo.state.lastError, isNull);
    transport.calls.clear();
    router.checked.clear();
    transport.changed = true;
    return (repo: repo, router: router, transport: transport);
  }

  test(
    'content only sync adds affected finance scope only when dependency requires it',
    () async {
      final f = await setup();
      f.router.needed = true;
      await f.repo.syncNow();
      expect(f.repo.state.lastError, isNull);
      expect(f.router.checked, [f.transport.project]);
      final policies = f.transport.calls
          .where((c) => c.operation.endsWith('.policy'))
          .map((c) => c.scope)
          .toList();
      expect(policies, contains(f.transport.project));
      expect(policies, isNot(contains(f.transport.parent)));
    },
  );
  test(
    'content only sync with no pending derivation keeps all finance untouched',
    () async {
      final f = await setup();
      await f.repo.syncNow();
      expect(f.repo.state.lastError, isNull);
      expect(f.router.checked, [f.transport.project]);
      expect(
        f.transport.calls.where((c) => c.operation.startsWith('finance')),
        isEmpty,
      );
    },
  );
}
