import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_transport.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/data/device_session_store.dart';
import 'package:kanban/organizer/data/e2ee/crypto_domain_router.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:kanban/organizer/domain/organization_finance_projection.dart';
import 'package:kanban/organizer/domain/linked_payment_models.dart';

import '../support/synthetic_content_route_guard.dart';
import 'collaboration_repository_test.dart' show FakeServer, MemorySessionStore;
import 'organization_finance_client_test.dart'
    show OrganizationFinanceTransport, entry;

// The routing/authority boundary is synthetic. This exercises real SQLite,
// selective sync, ordinary finance materialization and the parent projection.
// It does not certify topology/signature verification or the Samsung's cause.
class _LegacyRouter implements CryptoDomainRouter {
  @override
  Future<Map<String, dynamic>> dispatch({
    required DeviceSession session,
    required String operation,
    required Map<String, Object?> params,
    required Set<String> protectedScopeIds,
  }) async => throw StateError('Unexpected protected synthetic operation');
}

class _Transport extends OrganizationFinanceTransport {
  _Transport(super.server, this.store);
  final MemorySessionStore store;
  final sibling = newSharedId();
  final financePulls = <String>[];
  final financePolicyReads = <String>[];
  Future<void> Function(String scope)? beforeFinancePolicy;
  Future<void> Function(Map<String, dynamic> reply)? afterLogin;
  bool emptyIncompleteCoverage = false;
  bool paymentsRequired = false;
  bool keepSiblingIncomplete = false;
  final paymentReads = <String>[];
  Map<String, List<String>> hints = {};

  void seedParent() {
    seed(parentAccess: true);
    server.scopes[sibling] = {
      ...server.scopes[project]!,
      'id': sibling,
      'name': 'Unchanged sibling',
    };
    server.members[sibling] = {'alice': 'member'};
    server.records[sibling] = {};
    server.sequence[sibling] = 0;
    requiredSequences.addAll({project: 1, sibling: 1});
    final now = DateTime.utc(2026, 10, 25);
    final movement = entry(
      newSharedId(),
      account,
      parent: parent,
    ).copyWith(amountMinor: 1234, title: 'Synthetic project expense');
    records[account] = {
      'id': account,
      'type': 'financeAccount',
      'revision': 1,
      'deleted': false,
      'contractVersion': 3,
      'payload': SharedFinanceAccount(
        id: account,
        name: 'Synthetic parent bank',
        currency: 'EUR',
        openingBalanceMinor: 100000,
        createdAt: now,
        updatedAt: now,
      ).toPayload(contractVersion: 3),
    };
    records[movement.id] = {
      'id': movement.id,
      'type': 'financeEntry',
      'revision': 1,
      'deleted': false,
      'contractVersion': 3,
      'payload': movement.toPayload(contractVersion: 3),
    };
    recordScopes.addAll({account: parent, movement.id: project});
  }

  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
    if (operation == 'account.changes') {
      final profile = store.value!.profile;
      final reset = params['cursor'] == null;
      return {
        'version': 1,
        'serverId': profile.serverId,
        'accountId': profile.accountId,
        'deviceId': profile.deviceId,
        'cursor': 'synthetic-parent-cursor',
        'changed': reset || hints.isNotEmpty,
        'resetRequired': reset,
        'hasMore': false,
        'accountDomains': <String>[],
        'scopes': [
          for (final hint in hints.entries)
            {'scopeId': hint.key, 'domains': hint.value},
        ],
      };
    }
    if (operation == 'finance3.payments') {
      paymentReads.add(params['scopeId'] as String);
      return {
        'accessRevision': revision,
        'scopeSequence': 1,
        'complete': true,
        'events': <Object>[],
        'cashMovements': <Object>[],
        'projections': <Object>[],
      };
    }
    if (operation.startsWith('finance') && operation.endsWith('.pull')) {
      financePulls.add(params['scopeId'] as String);
    }
    final result = await super.call(
      serverUrl: serverUrl,
      operation: operation,
      params: params,
      token: token,
      allowLocalHttp: allowLocalHttp,
    );
    if (operation == 'auth.login') await afterLogin?.call(result);
    if (operation.startsWith('finance') &&
        operation.endsWith('.pull') &&
        params['scopeId'] == sibling &&
        keepSiblingIncomplete) {
      return {...result, 'cryptoProjectionComplete': false};
    }
    if (operation.startsWith('finance') && operation.endsWith('.policy')) {
      financePolicyReads.add(params['scopeId'] as String);
      await beforeFinancePolicy?.call(params['scopeId'] as String);
      return {
        ...result,
        'linkedPaymentsRequired': paymentsRequired,
        if (emptyIncompleteCoverage && !organizationComplete) ...{
          'organizationFinanceScopeIds': <String>[],
          'organizationFinanceSequences': <String, int>{},
        },
      };
    }
    if (operation.startsWith('finance') &&
        operation.endsWith('.pull') &&
        emptyIncompleteCoverage &&
        !organizationComplete) {
      return {
        ...result,
        'organizationFinanceScopeIds': <String>[],
        'organizationFinanceSequences': <String, int>{},
      };
    }
    return operation == 'capabilities'
        ? {
            ...result,
            'accountChangeVersions': [1],
            'features': {
              ...result['features'] as Map,
              'linkedPayments': paymentsRequired,
            },
          }
        : result;
  }
}

Future<({CollaborationRepository repo, _Transport transport})> _open({
  bool savedCursor = true,
  bool paymentsRequired = false,
  bool withoutChildren = false,
}) async {
  final store = MemorySessionStore();
  final transport = _Transport(FakeServer(), store)
    ..paymentsRequired = paymentsRequired
    ..seedParent();
  if (withoutChildren) {
    transport.server.scopes.remove(transport.project);
    transport.server.scopes.remove(transport.sibling);
    transport.requiredSequences.clear();
  }
  final repo = CollaborationRepository(
    CollaborationDatabase(NativeDatabase.memory()),
    transport,
    store,
    contentRouteGuard: const SyntheticContentRouteGuard(),
    cryptoRouter: _LegacyRouter(),
  );
  addTearDown(repo.close);
  await repo.initialize();
  await repo.login(
    serverUrl: 'https://example.test/',
    username: 'alice',
    password: 'synthetic',
  );
  expect(repo.state.lastError, isNull);
  final profile = repo.state.session!;
  final p = profile.partition;
  if (savedCursor) {
    await repo.database.execute(
      'INSERT INTO local_meta(name,value) VALUES(?,?) ON CONFLICT(name) DO UPDATE SET value=excluded.value',
      ['account_changes_v1:$p:${profile.deviceId}', 'synthetic-prior-cursor'],
    );
  }
  transport.financePulls.clear();
  transport.financePolicyReads.clear();
  transport.paymentReads.clear();
  return (repo: repo, transport: transport);
}

Future<void> _cacheIncompleteCoverage(
  CollaborationRepository repo,
  _Transport transport,
) async {
  final policy = repo.state.financePolicyForScope(transport.parent);
  await repo.database.execute(
    'UPDATE scopes SET finance_policy=? WHERE partition=? AND id=?',
    [
      jsonEncode({
        ...policy.toJson(),
        'organizationFinanceComplete': false,
        'organizationFinanceScopeIds': <String>[],
        'organizationFinanceSequences': <String, int>{},
      }),
      repo.state.session!.partition,
      transport.parent,
    ],
  );
  await repo.refreshLocal();
}

void main() {
  test(
    'finance repair resilience: interrupted policy read retains debt and blocked intent',
    () async {
      final f = await _open();
      final repo = f.repo, t = f.transport;
      final p = repo.state.session!.partition;
      await repo.database.execute(
        'UPDATE scopes SET finance_policy=?,finance_complete=0,finance_blocked=1 WHERE id=?',
        [jsonEncode(const SharedFinancePolicy().toJson()), t.parent],
      );
      final op = newSharedId();
      const original =
          '{"type":"financeEntry","untouched":"signed intent placeholder"}';
      await repo.database.execute(
        'INSERT INTO finance_outbox(op_id,partition,scope_id,record_id,request,state) VALUES(?,?,?,?,?,?)',
        [op, p, t.parent, newSharedId(), original, 'blocked'],
      );
      final before = await repo.database.rows(
        'SELECT * FROM finance_outbox WHERE op_id=?',
        [op],
      );
      t.beforeFinancePolicy = (id) async {
        if (id == t.parent) throw const CollaborationApiException('network');
      };
      await repo.checkAllAccess();
      expect(repo.state.lastError, isNotNull);
      expect(
        await repo.database.rows('SELECT name FROM local_meta WHERE name=?', [
          'finance_access_review:$p:${t.parent}',
        ]),
        hasLength(1),
      );
      expect(repo.state.financePolicyForScope(t.parent).canRead, false);
      expect(
        await repo.database.rows('SELECT * FROM finance_outbox WHERE op_id=?', [
          op,
        ]),
        before,
      );
      t.beforeFinancePolicy = null;
      await repo.syncNow(manual: true);
      expect(repo.state.lastError, isNull);
      expect(repo.state.financePolicyForScope(t.parent).canRead, true);
      expect(
        await repo.database.rows('SELECT name FROM local_meta WHERE name=?', [
          'finance_access_review:$p:${t.parent}',
        ]),
        isEmpty,
      );
      expect(
        await repo.database.rows('SELECT * FROM finance_outbox WHERE op_id=?', [
          op,
        ]),
        before,
      );
    },
  );

  test(
    'finance access repair: restored space refreshes denied policy despite unchanged server cursor',
    () async {
      final f = await _open();
      final repo = f.repo, t = f.transport;
      final p = repo.state.session!.partition;
      final data = repo.state.scopes
          .singleWhere((s) => s.id == t.parent)
          .toJson();
      await repo.database.execute(
        'UPDATE scopes SET data=?,blocked=1,finance_policy=?,finance_complete=0,finance_blocked=1 WHERE partition=? AND id=?',
        [
          jsonEncode({...data, 'revoked': true}),
          jsonEncode(const SharedFinancePolicy().toJson()),
          p,
          t.parent,
        ],
      );
      await repo.refreshLocal();
      await repo.checkAllAccess();
      expect(repo.state.lastError, isNull);
      expect(
        repo.state.scopes.singleWhere((s) => s.id == t.parent).revoked,
        false,
      );
      expect(repo.state.financePolicyForScope(t.parent).canRead, true);
      expect(repo.state.financeSnapshotComplete[t.parent], true);
      expect(
        repo.state.data[t.parent]!.financeAccounts.map((a) => a.id),
        contains(t.account),
      );
      expect(t.financePolicyReads, contains(t.parent));
      expect(
        await repo.database.rows('SELECT name FROM local_meta WHERE name=?', [
          'finance_access_review:$p:${t.parent}',
        ]),
        isEmpty,
      );
      t.financePulls.clear();
      t.financePolicyReads.clear();
      await repo.syncNow();
      expect(t.financePulls, isEmpty);
      expect(t.financePolicyReads, isEmpty);
    },
  );

  test(
    'finance access repair: already restored space repairs old denial without UI permission dialog',
    () async {
      final f = await _open();
      final repo = f.repo, t = f.transport;
      await repo.database.execute(
        'UPDATE scopes SET finance_policy=?,finance_complete=0,finance_blocked=1 WHERE id=?',
        [jsonEncode(const SharedFinancePolicy().toJson()), t.parent],
      );
      await repo.refreshLocal();
      await repo.checkAllAccess();
      expect(repo.state.lastError, isNull);
      expect(repo.state.financePolicyForScope(t.parent).canWrite, true);
      expect(repo.state.financeSnapshotComplete[t.parent], true);
      expect(t.financePulls, contains(t.parent));
    },
  );

  test(
    'finance access repair: verified financial denial is consumed without granting or polling again',
    () async {
      final f = await _open();
      final repo = f.repo, t = f.transport;
      t.grant = 'none';
      await repo.database.execute(
        'UPDATE scopes SET finance_policy=?,finance_complete=0,finance_blocked=1 WHERE id=?',
        [jsonEncode(const SharedFinancePolicy().toJson()), t.parent],
      );
      await repo.refreshLocal();
      await repo.checkAllAccess();
      expect(repo.state.financePolicyForScope(t.parent).canRead, false);
      expect(t.financePolicyReads, contains(t.parent));
      expect(t.financePulls, isNot(contains(t.parent)));
      t.financePulls.clear();
      t.financePolicyReads.clear();
      await repo.syncNow();
      expect(t.financePolicyReads, isEmpty);
      expect(t.financePulls, isEmpty);
    },
  );

  test(
    'new cached coverage continuation: unchanged probe rechecks false parent after every child is complete',
    () async {
      final f = await _open();
      final repo = f.repo, transport = f.transport;
      final p = repo.state.session!.partition;
      final policy = repo.state.financePolicyForScope(transport.parent);
      await repo.database.execute(
        'UPDATE scopes SET finance_policy=? WHERE partition=? AND id=?',
        [
          jsonEncode({
            ...policy.toJson(),
            'organizationFinanceComplete': false,
            'organizationFinanceScopeIds': <String>[],
            'organizationFinanceSequences': <String, int>{},
          }),
          p,
          transport.parent,
        ],
      );
      await repo.refreshLocal();
      for (final scope in [
        transport.parent,
        transport.project,
        transport.sibling,
      ]) {
        expect(repo.state.financeSnapshotComplete[scope], isTrue);
        expect(
          repo.state.financeSnapshotSequences[scope],
          greaterThanOrEqualTo(1),
        );
        expect(repo.state.financePolicyForScope(scope).canRead, isTrue);
      }
      expect(transport.hints, isEmpty);
      expect(transport.organizationComplete, isTrue);
      transport.financePulls.clear();
      await repo.syncNow();
      expect(repo.state.lastError, isNull);
      final resumedAutomatically = repo.state
          .financePolicyForScope(transport.parent)
          .organizationFinanceComplete;

      // The same live policy can prove coverage without a new write, sequence,
      // journal hint or policy revision. This control makes a cached false flag
      // distinguishable from an authoritative, still-incomplete child set.
      final refreshed = await repo.refreshFinancePolicy(transport.parent);
      expect(refreshed.organizationFinanceComplete, isTrue);
      expect(refreshed.revision, policy.revision);
      expect(
        projectOrganizationFinance(
          state: repo.state,
          scopeId: transport.parent,
        ).complete,
        isTrue,
      );
      expect(transport.pushes, isEmpty);
      expect(
        resumedAutomatically,
        isTrue,
        reason:
            'An unchanged server cursor must not strand a cached false parent '
            'coverage after all readable child prerequisites are complete.',
      );
    },
  );
  test(
    'new cached coverage guard: unsuccessful verified recheck stays bounded on unchanged probes',
    () async {
      final f = await _open();
      await _cacheIncompleteCoverage(f.repo, f.transport);
      f.transport
        ..organizationComplete = false
        ..emptyIncompleteCoverage = true;
      await f.repo.syncNow();
      expect(f.transport.financePulls, [f.transport.parent]);
      expect(
        f.repo.state
            .financePolicyForScope(f.transport.parent)
            .organizationFinanceComplete,
        isFalse,
      );
      expect(
        projectOrganizationFinance(
          state: f.repo.state,
          scopeId: f.transport.parent,
        ).complete,
        isFalse,
      );
      f.transport.financePulls.clear();
      f.transport.financePolicyReads.clear();
      final completion = f.repo.lastSyncCompletion;
      for (var probe = 0; probe < 3; probe++) {
        await f.repo.syncNow();
      }
      expect(f.transport.financePulls, isEmpty);
      expect(f.transport.financePolicyReads, isEmpty);
      expect(identical(f.repo.lastSyncCompletion, completion), isTrue);
      expect(f.transport.pushes, isEmpty);
    },
  );
  test(
    'new cached coverage identity guard: signout during policy recheck cannot publish prior session coverage',
    () async {
      final f = await _open();
      await _cacheIncompleteCoverage(f.repo, f.transport);
      final partition = f.repo.state.session!.partition;
      f.transport.beforeFinancePolicy = (scope) async {
        if (scope != f.transport.parent) return;
        f.transport.beforeFinancePolicy = null;
        await f.repo.signOut();
      };
      await expectLater(
        f.repo.syncNow(),
        throwsA(isA<CollaborationException>()),
      );
      expect(f.repo.state.session, isNull);
      expect(f.transport.financePulls, isEmpty);
      final saved = await f.repo.database.rows(
        'SELECT finance_policy FROM scopes WHERE partition=? AND id=?',
        [partition, f.transport.parent],
      );
      expect(
        (jsonDecode(saved.single['finance_policy'] as String)
            as Map)['organizationFinanceComplete'],
        isFalse,
      );
      expect(f.transport.pushes, isEmpty);
    },
  );
  test(
    'new cached coverage epoch guard: authenticated reentry permits one new verification',
    () async {
      final f = await _open();
      await _cacheIncompleteCoverage(f.repo, f.transport);
      f.transport
        ..organizationComplete = false
        ..emptyIncompleteCoverage = true;
      await f.repo.syncNow();
      expect(f.transport.financePulls, [f.transport.parent]);
      f.transport.financePulls.clear();
      await f.repo.syncNow();
      expect(f.transport.financePulls, isEmpty);
      final identity = f.repo.backgroundSyncIdentity;
      final partition = f.repo.state.session!.partition;
      await f.repo.signOut();
      // FakeServer issues a new device per login. Seed its durable journal
      // cursor so this tests epoch reset rather than full-reset bootstrap.
      f.transport.afterLogin = (reply) async {
        await f.repo.database
            .execute('INSERT INTO local_meta(name,value) VALUES(?,?)', [
              'account_changes_v1:$partition:${reply['device']['id']}',
              'synthetic-prior-cursor',
            ]);
      };
      await f.repo.login(
        serverUrl: 'https://example.test/',
        username: 'alice',
        password: 'synthetic',
      );
      expect(f.repo.backgroundSyncIdentity, isNot(identity));
      expect(f.transport.financePulls, [f.transport.parent]);
      expect(
        f.repo.state
            .financePolicyForScope(f.transport.parent)
            .organizationFinanceComplete,
        isFalse,
      );
      f.transport.financePulls.clear();
      await f.repo.syncNow();
      expect(f.transport.financePulls, isEmpty);
      expect(f.transport.pushes, isEmpty);
    },
  );
  test(
    'new cached coverage payments guard: refreshed bookkeeping cannot repeat an authoritative false recheck',
    () async {
      final f = await _open(paymentsRequired: true);
      await _cacheIncompleteCoverage(f.repo, f.transport);
      f.transport
        ..organizationComplete = false
        ..emptyIncompleteCoverage = true;
      final p = f.repo.state.session!.partition;
      Future<void> bookkeep(String stamp) async {
        for (final scope in [
          f.transport.parent,
          f.transport.project,
          f.transport.sibling,
        ]) {
          final space = PaymentSpaceRef(scope, partition: p);
          final name = 'linked_payment_complete:${space.key}';
          final rows = await f.repo.database.rows(
            'SELECT value FROM local_meta WHERE name=?',
            [name],
          );
          final proof = jsonDecode(rows.single['value'] as String) as Map;
          await f.repo.database.execute(
            'UPDATE local_meta SET value=? WHERE name=?',
            [
              jsonEncode({...proof, 'checkedAt': stamp}),
              name,
            ],
          );
        }
      }

      await bookkeep('before-read');
      await f.repo.syncNow();
      expect(f.transport.financePulls, [f.transport.parent]);
      expect(f.transport.paymentReads, [f.transport.parent]);
      f.transport.financePulls.clear();
      f.transport.financePolicyReads.clear();
      f.transport.paymentReads.clear();
      await bookkeep('after-read');
      await f.repo.syncNow();
      expect(f.transport.financePulls, isEmpty);
      expect(f.transport.financePolicyReads, isEmpty);
      expect(f.transport.paymentReads, isEmpty);
      expect(
        f.repo.state
            .financePolicyForScope(f.transport.parent)
            .organizationFinanceComplete,
        isFalse,
      );
      expect(f.transport.pushes, isEmpty);
    },
  );
  test(
    'new cached coverage empty-child guard: parent verifies once and remains hidden when authority is incomplete',
    () async {
      final f = await _open(withoutChildren: true);
      expect(f.repo.state.scopes.map((s) => s.id), [f.transport.parent]);
      await _cacheIncompleteCoverage(f.repo, f.transport);
      f.transport
        ..organizationComplete = false
        ..emptyIncompleteCoverage = true;
      await f.repo.syncNow();
      expect(f.transport.financePulls, [f.transport.parent]);
      expect(
        f.repo.state
            .financePolicyForScope(f.transport.parent)
            .organizationFinanceComplete,
        isFalse,
      );
      f.transport.financePulls.clear();
      f.transport.financePolicyReads.clear();
      await f.repo.syncNow();
      expect(f.transport.financePulls, isEmpty);
      expect(f.transport.financePolicyReads, isEmpty);
      expect(f.transport.pushes, isEmpty);
    },
  );
  for (final savedCursor in [false, true]) {
    test(
      savedCursor
          ? 'changed-only parent finance repairs an unchanged missing sibling snapshot before publishing its balance'
          : 'full-reset finance repairs a missing sibling snapshot before publishing its balance',
      () async {
        final f = await _open(savedCursor: savedCursor);
        final repo = f.repo, transport = f.transport;
        final p = repo.state.session!.partition;
        await repo.database.execute(
          'UPDATE scopes SET finance_complete=0,finance_cursor=0 WHERE partition=? AND id=?',
          [p, transport.sibling],
        );
        await repo.refreshLocal();
        expect(
          projectOrganizationFinance(
            state: repo.state,
            scopeId: transport.parent,
          ).complete,
          isFalse,
        );
        transport.financePulls.clear();
        transport.hints = {
          transport.project: ['finance'],
        };
        await repo.syncNow();
        expect(repo.state.lastError, isNull);
        expect(transport.financePulls, contains(transport.sibling));
        final projection = projectOrganizationFinance(
          state: repo.state,
          scopeId: transport.parent,
        );
        expect(projection.complete, isTrue);
        expect(projection.entries, hasLength(1));
        final totals = summarizeSharedFinance(
          accounts: projection.accounts,
          entries: projection.entries,
          transfers: projection.transfers,
          payments: projection.payments,
        );
        expect(
          totals['EUR']!
              .accountBalances['${transport.parent}:${transport.account}'],
          BigInt.from(98766),
        );
      },
    );
  }
  test(
    'new dependency guard: complete sibling and unchanged probe stay idle',
    () async {
      final f = await _open();
      f.transport.hints = {
        f.transport.project: ['finance'],
      };
      await f.repo.syncNow();
      expect(f.transport.financePulls, isNot(contains(f.transport.sibling)));
      expect(f.transport.financePulls.toSet(), {
        f.transport.project,
        f.transport.parent,
      });
      f.transport.hints.clear();
      f.transport.financePulls.clear();
      final completion = f.repo.lastSyncCompletion;
      await f.repo.syncNow();
      expect(f.transport.financePulls, isEmpty);
      expect(identical(f.repo.lastSyncCompletion, completion), isTrue);
    },
  );

  test(
    'new dependency guard: complete but behind contributor is refreshed',
    () async {
      final f = await _open();
      await f.repo.database.execute(
        'UPDATE scopes SET finance_cursor=0 WHERE partition=? AND id=?',
        [f.repo.state.session!.partition, f.transport.sibling],
      );
      await f.repo.refreshLocal();
      expect(f.repo.state.financeSnapshotComplete[f.transport.sibling], isTrue);
      f.transport.hints = {
        f.transport.project: ['finance'],
      };
      await f.repo.syncNow();
      expect(
        f.transport.financePulls.where((s) => s == f.transport.sibling),
        hasLength(1),
      );
      expect(
        projectOrganizationFinance(
          state: f.repo.state,
          scopeId: f.transport.parent,
        ).complete,
        isTrue,
      );
    },
  );

  for (final denial in ['finance', 'revoked', 'deleted', 'unrelated']) {
    test(
      'new dependency guard: missing $denial sibling is not silently certified',
      () async {
        final f = await _open();
        final p = f.repo.state.session!.partition;
        await f.repo.database.execute(
          'UPDATE scopes SET finance_complete=0,finance_cursor=0 WHERE partition=? AND id=?',
          [p, f.transport.sibling],
        );
        if (denial == 'finance') {
          await f.repo.database.execute(
            'UPDATE scopes SET finance_policy=? WHERE partition=? AND id=?',
            [
              jsonEncode(const SharedFinancePolicy().toJson()),
              p,
              f.transport.sibling,
            ],
          );
        } else {
          final row = f.repo.state.scopes
              .singleWhere((scope) => scope.id == f.transport.sibling)
              .toJson();
          final data = {
            ...row,
            if (denial == 'unrelated') 'parentScopeId': newSharedId(),
            if (denial != 'unrelated') denial: true,
          };
          await f.repo.database.execute(
            'UPDATE scopes SET data=? WHERE partition=? AND id=?',
            [jsonEncode(data), p, f.transport.sibling],
          );
        }
        await f.repo.refreshLocal();
        f.transport.hints = {
          f.transport.project: ['finance'],
        };
        await f.repo.syncNow();
        expect(f.transport.financePulls, isNot(contains(f.transport.sibling)));
        expect(
          projectOrganizationFinance(
            state: f.repo.state,
            scopeId: f.transport.parent,
          ).complete,
          isFalse,
        );
      },
    );
  }

  test(
    'new dependency guard: missing required sidecar selects only that sibling',
    () async {
      final f = await _open(paymentsRequired: true);
      final space = PaymentSpaceRef(
        f.transport.sibling,
        partition: f.repo.state.session!.partition,
      );
      await f.repo.database.execute('DELETE FROM local_meta WHERE name=?', [
        'linked_payment_complete:${space.key}',
      ]);
      f.transport.hints = {
        f.transport.project: ['finance'],
      };
      await f.repo.syncNow();
      expect(f.repo.state.lastError, isNull);
      expect(
        f.transport.paymentReads.where((s) => s == f.transport.sibling),
        hasLength(1),
      );
      expect(
        await f.repo.database.rows(
          'SELECT value FROM local_meta WHERE name=?',
          ['linked_payment_complete:${space.key}'],
        ),
        hasLength(1),
      );
    },
  );
  test(
    'new coordinator debt: unchanged saved cursor repairs existing sibling without a Save',
    () async {
      final f = await _open();
      await f.repo.database.execute(
        'UPDATE scopes SET finance_complete=0 WHERE partition=? AND id=?',
        [f.repo.state.session!.partition, f.transport.sibling],
      );
      await f.repo.refreshLocal();
      expect(f.transport.hints, isEmpty);
      await f.repo.syncNow();
      expect(f.transport.financePulls, contains(f.transport.sibling));
      final projection = projectOrganizationFinance(
        state: f.repo.state,
        scopeId: f.transport.parent,
      );
      expect(projection.complete, isTrue);
      expect(projection.entries, hasLength(1));
      expect(
        summarizeSharedFinance(
              accounts: projection.accounts,
              entries: projection.entries,
              transfers: projection.transfers,
              payments: projection.payments,
            )['EUR']!
            .accountBalances['${f.transport.parent}:${f.transport.account}'],
        BigInt.from(98766),
      );
      expect(f.transport.pushes, isEmpty);
    },
  );

  test(
    'new coordinator debt: unchanged unresolved signature gets only one attempt',
    () async {
      final f = await _open();
      await f.repo.database.execute(
        'UPDATE scopes SET finance_complete=0 WHERE partition=? AND id=?',
        [f.repo.state.session!.partition, f.transport.sibling],
      );
      await f.repo.refreshLocal();
      f.transport.keepSiblingIncomplete = true;
      await f.repo.syncNow();
      expect(
        f.transport.financePulls.where((s) => s == f.transport.sibling),
        hasLength(1),
      );
      expect(
        projectOrganizationFinance(
          state: f.repo.state,
          scopeId: f.transport.parent,
        ).complete,
        isFalse,
      );
      f.transport.financePulls.clear();
      await f.repo.syncNow();
      expect(f.transport.financePulls, isEmpty);
      expect(
        projectOrganizationFinance(
          state: f.repo.state,
          scopeId: f.transport.parent,
        ).complete,
        isFalse,
      );
    },
  );
  for (final unavailable in ['denied', 'unrelated']) {
    test(
      'new coordinator guard: unchanged $unavailable debt cannot select finance work',
      () async {
        final f = await _open();
        final p = f.repo.state.session!.partition;
        await f.repo.database.execute(
          'UPDATE scopes SET finance_complete=0 WHERE partition=? AND id=?',
          [p, f.transport.sibling],
        );
        if (unavailable == 'denied') {
          await f.repo.database.execute(
            'UPDATE scopes SET finance_policy=? WHERE partition=? AND id=?',
            [
              jsonEncode(const SharedFinancePolicy().toJson()),
              p,
              f.transport.sibling,
            ],
          );
        } else {
          final child = f.repo.state.scopes.singleWhere(
            (s) => s.id == f.transport.sibling,
          );
          await f.repo.database.execute(
            'UPDATE scopes SET data=? WHERE partition=? AND id=?',
            [
              jsonEncode({...child.toJson(), 'parentScopeId': newSharedId()}),
              p,
              f.transport.sibling,
            ],
          );
        }
        await f.repo.refreshLocal();
        final completion = f.repo.lastSyncCompletion;
        await f.repo.syncNow();
        expect(f.transport.financePulls, isEmpty);
        expect(identical(f.repo.lastSyncCompletion, completion), isTrue);
        expect(
          projectOrganizationFinance(
            state: f.repo.state,
            scopeId: f.transport.parent,
          ).complete,
          isFalse,
        );
      },
    );
  }
  test(
    'new manual recovery: explicit demand retries identical debt after transient failure',
    () async {
      final f = await _open();
      await f.repo.database.execute(
        'UPDATE scopes SET finance_complete=0 WHERE partition=? AND id=?',
        [f.repo.state.session!.partition, f.transport.sibling],
      );
      await f.repo.refreshLocal();
      f.transport.keepSiblingIncomplete = true;
      await f.repo.syncNow();
      expect(
        projectOrganizationFinance(
          state: f.repo.state,
          scopeId: f.transport.parent,
        ).complete,
        isFalse,
      );
      f.transport.keepSiblingIncomplete = false;
      f.transport.financePulls.clear();
      await f.repo.syncNow(manual: true);
      expect(
        f.transport.financePulls.where((s) => s == f.transport.sibling),
        hasLength(1),
      );
      expect(
        projectOrganizationFinance(
          state: f.repo.state,
          scopeId: f.transport.parent,
        ).complete,
        isTrue,
      );
      expect(f.transport.pushes, isEmpty);
    },
  );
}
