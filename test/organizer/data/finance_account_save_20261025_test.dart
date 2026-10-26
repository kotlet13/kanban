import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/data/collaboration_transport.dart';
import 'package:kanban/organizer/data/device_session_store.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import '../support/synthetic_content_route_guard.dart';
import 'collaboration_repository_test.dart' show MemorySessionStore;

const household = '10000000-0000-4000-8000-000000000001';
const project = '10000000-0000-4000-8000-000000000002';

class _NoNetwork implements CollaborationTransport {
  final calls = <String>[];
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
    calls.add(operation);
    throw StateError('Unexpected synthetic network call');
  }

  @override
  void close() {}
}

Future<
  ({
    CollaborationDatabase db,
    CollaborationRepository repo,
    _NoNetwork transport,
    AccountSession session,
  })
>
fixture() async {
  final session = AccountSession(
    serverUrl: 'https://synthetic.invalid/',
    serverId: '20000000-0000-4000-8000-000000000001',
    accountId: '30000000-0000-4000-8000-000000000001',
    deviceId: '40000000-0000-4000-8000-000000000001',
    username: 'synthetic',
    displayName: 'Synthetic',
    userId: 1,
    expiresAt: DateTime.utc(2099),
  );
  final db = CollaborationDatabase(NativeDatabase.memory());
  final sessions = MemorySessionStore()
    ..value = DeviceSession(session, 'synthetic');
  await db.execute('INSERT INTO accounts(partition,profile) VALUES(?,?)', [
    session.partition,
    jsonEncode(session.toJson()),
  ]);
  await db.execute('INSERT INTO local_meta(name,value) VALUES(?,?)', [
    'capabilities:${session.partition}',
    jsonEncode({
      'recordContractVersions': [1],
      'financeContractVersions': [1, 2, 3],
      'organizationFinanceContractVersions': [1],
      'features': {
        'recordSync': true,
        'finance': true,
        'organizationFinance': true,
      },
    }),
  ]);
  for (final scope in [
    const SharedScope(
      id: household,
      name: 'Synthetic household',
      kind: SharedScopeKind.household,
      role: SharedRole.owner,
    ),
    const SharedScope(
      id: project,
      name: 'Synthetic project',
      kind: SharedScopeKind.project,
      role: SharedRole.owner,
      parentScopeId: household,
    ),
  ]) {
    await db.execute(
      'INSERT INTO scopes(partition,id,data,finance_policy,finance_complete) VALUES(?,?,?,?,1)',
      [
        session.partition,
        scope.id,
        jsonEncode(scope.toJson()),
        jsonEncode(
          const SharedFinancePolicy(
            enabled: true,
            grant: SharedFinanceGrant.write,
            revision: 1,
          ).toJson(),
        ),
      ],
    );
  }
  final transport = _NoNetwork();
  final repo = CollaborationRepository(
    db,
    transport,
    sessions,
    ownsDatabase: false,
    contentRouteGuard: const SyntheticContentRouteGuard(),
  );
  addTearDown(() async {
    await repo.close();
    await db.close();
  });
  await repo.initialize();
  return (db: db, repo: repo, transport: transport, session: session);
}

Matcher code(String expected) =>
    isA<CollaborationException>().having((e) => e.code, 'code', expected);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'account create and edit commit locally with exact scope and stale guard',
    () async {
      final f = await fixture();
      final id = await f.repo.createFinanceAccount(
        scopeId: household,
        name: 'Synthetic balance',
        currency: 'EUR',
        openingBalanceMinor: 10000,
      );
      final original = f.repo.state
          .dataForScope(household)
          .financeAccounts
          .single;
      expect(original.id, id);
      await f.repo.updateFinanceAccount(
        household,
        original.copyWith(name: 'Renamed'),
      );
      final saved = f.repo.state.dataForScope(household).financeAccounts.single;
      expect(saved.name, 'Renamed');
      expect(saved.currency, 'EUR');
      expect(saved.openingBalanceMinor, 10000);
      expect(saved.revision, greaterThan(original.revision));
      await expectLater(
        f.repo.updateFinanceAccount(
          household,
          original.copyWith(name: 'Stale'),
        ),
        throwsA(code('stale_edit')),
      );
      expect(f.repo.state.dataForScope(project).financeAccounts, isEmpty);
      expect(f.transport.calls, isEmpty);
      expect(await f.db.rows('SELECT * FROM finance_outbox'), hasLength(2));
    },
  );

  test(
    'account create rejects child scope and denied policy without queued writes',
    () async {
      final f = await fixture();
      await expectLater(
        f.repo.createFinanceAccount(
          scopeId: project,
          name: 'Wrong scope',
          currency: 'EUR',
        ),
        throwsA(code('finance_account_parent_required')),
      );
      await f.db.execute(
        'UPDATE scopes SET finance_policy=? WHERE partition=? AND id=?',
        [
          jsonEncode(
            const SharedFinancePolicy(
              enabled: true,
              grant: SharedFinanceGrant.read,
              revision: 2,
            ).toJson(),
          ),
          f.session.partition,
          household,
        ],
      );
      await f.repo.refreshLocal();
      await expectLater(
        f.repo.createFinanceAccount(
          scopeId: household,
          name: 'Denied write',
          currency: 'EUR',
        ),
        throwsA(code('finance_forbidden')),
      );
      expect(await f.db.rows('SELECT * FROM finance_outbox'), isEmpty);
      expect(await f.db.rows('SELECT * FROM finance_records'), isEmpty);
      expect(f.transport.calls, isEmpty);
    },
  );
}
