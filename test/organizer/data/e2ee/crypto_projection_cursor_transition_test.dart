import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/data/collaboration_transport.dart';
import 'package:kanban/organizer/data/device_session_store.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_store.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_v2_workflow.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_repository.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_v2.dart';
import 'package:kanban/organizer/data/e2ee/crypto_business_payments.dart';
import 'package:kanban/organizer/data/e2ee/crypto_business_router.dart';
import 'package:kanban/organizer/data/e2ee/crypto_codec.dart';
import 'package:kanban/organizer/data/e2ee/crypto_domain_router.dart';
import 'package:kanban/organizer/data/e2ee/crypto_identity_store.dart';
import 'package:kanban/organizer/data/e2ee/crypto_json.dart';
import 'package:kanban/organizer/data/e2ee/crypto_sync_repository.dart';
import 'package:kanban/organizer/data/e2ee/scope_crypto_codec.dart';
import 'package:kanban/organizer/data/e2ee/session_crypto_access.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:sodium/sodium.dart';

import '../collaboration_repository_test.dart' show MemorySessionStore;

const _scope = '10000000-0000-4000-8000-000000000001';
const _account = '20000000-0000-4000-8000-000000000001';

class _Secure implements AccountCryptoStore {
  @override
  Future<String?> read(String key) async => null;
  @override
  Future<void> write(String key, String value) async {}
}

class _Transport implements CollaborationTransport {
  late _Runtime runtime;
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
    if (operation == 'capabilities') {
      return {
        'serverId': runtime.account.directory.session.profile.serverId,
        'api': 'familyhub_native',
        'version': 1,
        'enabled': true,
        'recordContractVersions': [1],
        'financeContractVersions': [1, 2, 3],
        'features': {
          'recordSync': true,
          'finance': true,
          'linkedPayments': true,
        },
      };
    }
    if (operation == 'finance4.policy' || operation == 'finance2.policy') {
      return runtime.financePolicy(_scope);
    }
    if (operation == 'crypto2.scope.lifecycle.baseline') {
      return {
        'initialLifecycleHash': 'b' * 64,
        'originAuthorization': {
          'commandBase64': base64Encode(
            CryptoJson.encode({
              'operation': 'crypto2.scope.origin',
              'accountId': _account,
            }),
          ),
        },
      };
    }
    throw StateError('Unexpected synthetic operation: $operation');
  }

  @override
  void close() {}
}

// Like the lifecycle recovery fixtures, this supplies an already authenticated
// head/origin boundary. The real policy mapper, payment snapshot and repository
// delivery guards are exercised; this is not a signature-verifier test.
class _Head implements VerifiedScopeHead {
  _Head({required this.accessRevision, required int policyRevision}) {
    body = {
      'scopeId': _scope,
      'epoch': 1,
      'previousHeadHash': cryptoZeroHash,
      'initialLifecycleHash': 'b' * 64,
      'members': [
        {'accountId': _account, 'financeRole': 'write'},
      ],
      if (policyRevision != 1)
        'financePolicyIntentProof': {
          'commandBase64': base64Encode(
            CryptoJson.encode({
              'payload': {
                'resultingFinancePolicyRevision': policyRevision,
                'resultingPolicyHash': 'c' * 64,
                'action': {'kind': 'grant'},
              },
            }),
          ),
        },
    };
  }
  @override
  late final Map<String, dynamic> body;
  @override
  final int accessRevision;
  @override
  String get headHash => 'a' * 64;
  @override
  Map<String, dynamic> get authorization => const {};
  @override
  bool get active => true;
  @override
  String get scopeId => _scope;
  @override
  int get epoch => 1;
  @override
  List<Map<String, dynamic>> get members => (body['members'] as List).cast();
  @override
  Map<String, dynamic> member(String id) =>
      members.singleWhere((m) => m['accountId'] == id);
  @override
  String? commitment(String domain) => null;
}

class _Access extends SessionCryptoAccess {
  _Access({required super.account, required this.head});
  final _Head head;
  bool denied = false;
  @override
  Future<T> withVerifiedOperation<T>(
    Future<T> Function() body, {
    bool freshBoundary = false,
  }) => body();
  @override
  Future<VerifiedScopeHead> currentHead(
    String scopeId, {
    bool online = false,
  }) async {
    if (denied) throw const CollaborationException('permission_revoked');
    return head;
  }

  @override
  Future<CryptoReadContext> readContext(String scopeId, String domain) async {
    await currentHead(scopeId);
    return CryptoReadContext(
      epoch: head.epoch,
      accessRevision: head.accessRevision,
      headHash: head.headHash,
    );
  }

  @override
  Future<Map<String, dynamic>> verifiedScopeDescriptor(
    String scopeId, {
    bool online = false,
  }) async => {'accessPolicyVersion': 3};
  @override
  Future<String> verifyInitialLifecycle(
    String scopeId,
    Map<String, dynamic> wire, {
    required String scopeHeadHash,
  }) async => wire['initialLifecycleHash'] as String;
}

class _Runtime extends CryptoBusinessSession {
  _Runtime(super.account, super.access, super.db);
  Future<void> Function()? beforeDelivery;
  final financePullReplies = <Map<String, dynamic>>[];
  CryptoProjectionCursorOrigin? origin =
      CryptoProjectionCursorOrigin.legacyMigration;
  int transitionChecks = 0;
  bool staleFinanceReply = false;
  bool interruptAfterCheckpoint = false;
  @override
  Future<Map<String, dynamic>> organizationFinanceCoverage(
    String scope, {
    bool refreshRootFinance = false,
    String? expectedHeadHash,
  }) async => {
    'organizationFinanceComplete': false,
    'organizationFinanceScopeIds': <String>[],
    'organizationFinanceSequences': <String, int>{},
  };
  @override
  Future<void> pullVerified(
    String scopeId,
    String domain, {
    bool attest = true,
  }) async {
    await access.readContext(scopeId, domain);
  }
}

class _Repository extends CollaborationRepository {
  _Repository(
    super.database,
    super.transport,
    super.sessionStore,
    this.payments,
  ) : super(cryptoRouter: _PolicyRouter(payments.context));
  final CryptoBusinessPayments payments;
  set beforeDelivery(Future<void> Function()? callback) =>
      (payments.context as _Runtime).beforeDelivery = callback;
}

class _PolicyRouter
    implements CryptoDomainRouter, CryptoProjectionCursorTransition {
  _PolicyRouter(this.runtime);
  final CryptoBusinessSession runtime;
  @override
  Future<CryptoProjectionCursorOrigin?> verifyProjectionCursorOrigin({
    required DeviceSession session,
    required String scopeId,
  }) async {
    final fixture = runtime as _Runtime;
    fixture.transitionChecks++;
    await runtime.access.currentHead(scopeId, online: true);
    return fixture.origin;
  }

  @override
  Future<Map<String, dynamic>> dispatch({
    required DeviceSession session,
    required String operation,
    required Map<String, Object?> params,
    required Set<String> protectedScopeIds,
  }) async {
    if (operation == 'scopes.list') {
      final row = (await runtime.db.rows('SELECT data FROM scopes WHERE id=?', [
        _scope,
      ])).single;
      return {
        'scopes': [jsonDecode(row['data'] as String)],
      };
    }
    if (operation == 'sync.pull') {
      return runtime.pull(_scope, 'content', params);
    }
    if (operation == 'finance2.pull') {
      final reply = await runtime.pull(_scope, 'finance', params);
      (runtime as _Runtime).financePullReplies.add(reply);
      return (runtime as _Runtime).staleFinanceReply
          ? {...reply, 'accessRevision': 0}
          : reply;
    }
    if (operation == 'finance4.policy' || operation == 'finance2.policy') {
      final fixture = runtime as _Runtime;
      if (fixture.interruptAfterCheckpoint) {
        fixture.interruptAfterCheckpoint = false;
        throw const CollaborationException('network');
      }
      return runtime.financePolicy(_scope);
    }
    if (operation == 'finance3.payments') {
      final result = await CryptoBusinessPayments(
        runtime,
      ).dispatch(operation, params);
      await (runtime as _Runtime).beforeDelivery?.call();
      return result;
    }
    throw StateError('Unexpected synthetic route: $operation');
  }
}

Future<
  ({
    CollaborationDatabase db,
    _Access access,
    _Runtime runtime,
    _Repository repository,
  })
>
_fixture({int headRevision = 0, int policyRevision = 1}) async {
  final db = CollaborationDatabase(NativeDatabase.memory());
  final session = DeviceSession(
    AccountSession(
      serverUrl: 'https://synthetic.invalid/',
      serverId: '30000000-0000-4000-8000-000000000001',
      accountId: _account,
      userId: 1,
      username: 'synthetic',
      displayName: 'Synthetic',
      deviceId: '40000000-0000-4000-8000-000000000001',
      expiresAt: DateTime.utc(2030),
    ),
    'synthetic',
  );
  final transport = _Transport();
  final account = AccountCryptoV2Workflow(
    AccountDirectoryRepository(
      reducer: AccountDirectoryV2(CryptoCodec(await SodiumInit.init())),
      session: session,
      transport: transport,
      store: CryptoIdentityStore(db, _Secure(), session.profile.partition),
      isCurrent: () => true,
    ),
  );
  final access = _Access(
    account: account,
    head: _Head(accessRevision: headRevision, policyRevision: policyRevision),
  );
  final runtime = transport.runtime = _Runtime(account, access, db);
  final repository = _Repository(
    db,
    transport,
    MemorySessionStore()..value = session,
    CryptoBusinessPayments(runtime),
  );
  addTearDown(repository.close);
  await repository.initialize();
  final scope = SharedScope(
    id: _scope,
    kind: SharedScopeKind.organization,
    name: 'Synthetic',
    role: SharedRole.owner,
    sequence: 0,
  );
  await db.execute('INSERT INTO scopes(partition,id,data) VALUES(?,?,?)', [
    session.profile.partition,
    _scope,
    jsonEncode(scope.toJson()),
  ]);
  return (db: db, access: access, runtime: runtime, repository: repository);
}

const _event = '50000000-0000-4000-8000-000000000001';
const _bank = '60000000-0000-4000-8000-000000000001';
Future<void> _retain(dynamic f, {int cursor = 99, bool pending = false}) async {
  final policy = await f.runtime.financePolicy(_scope);
  await f.db.execute(
    'UPDATE scopes SET cursor=?,finance_cursor=?,finance_access_revision=2,finance_policy=?,finance_complete=0 WHERE id=?',
    [cursor, cursor, jsonEncode(policy), _scope],
  );
  final now = DateTime.utc(2026, 10, 18);
  final event = <String, dynamic>{
    'title': 'Synthetic event',
    'notes': 'remote',
    'projectId': null,
    'startAt': now.toIso8601String(),
    'endAt': null,
    'assigneeAccountIds': <String>[],
    'createdAt': now.toIso8601String(),
    'updatedAt': now.toIso8601String(),
  };
  final bank = SharedFinanceAccount(
    id: _bank,
    name: 'Synthetic bank',
    currency: 'EUR',
    createdAt: now,
    updatedAt: now,
  ).toPayload(contractVersion: 3);
  for (final row in [
    (domain: 'content', id: _event, type: 'event', payload: event),
    (domain: 'finance', id: _bank, type: 'financeAccount', payload: bank),
  ]) {
    final canonical = {
      'id': row.id,
      'type': row.type,
      'revision': 1,
      'deleted': false,
      'payload': row.payload,
      'contractVersion': row.domain == 'finance' ? 3 : 6,
    };
    await f.db.execute(
      "INSERT INTO crypto_business_records VALUES(?,?,?,?,?,1,1,?,0,?,?,?, 'legacy')",
      [
        f.runtime.partition,
        _scope,
        row.domain,
        row.id,
        row.type,
        'a' * 64,
        jsonEncode(row.payload),
        jsonEncode(canonical),
        'currentEpoch',
      ],
    );
    await f.db.execute(
      "INSERT INTO crypto_received(partition,scope_id,domain,record_id,revision,sequence,wire,verdict) VALUES(?,?,?,?,1,1,'{}','verified')",
      [f.runtime.partition, _scope, row.domain, row.id],
    );
    await f.db.execute(
      "INSERT INTO crypto_scope_state(partition,scope_id,domain,state,complete,floor) VALUES(?,?,?,'committed',1,2)",
      [f.runtime.partition, _scope, row.domain],
    );
  }
  if (pending) {
    await f.db.execute(
      "INSERT INTO finance_records(partition,scope_id,id,type,local_revision,server_revision,payload,deleted) VALUES(?,?,?,'financeAccount',1,0,?,0)",
      [
        f.runtime.partition,
        _scope,
        _bank,
        jsonEncode({...bank, 'name': 'own pending bank'}),
      ],
    );
    await f.db.execute(
      'INSERT INTO records(partition,scope_id,id,type,local_revision,server_revision,payload,deleted) VALUES(?,?,?,\'event\',1,0,?,0)',
      [
        f.runtime.partition,
        _scope,
        _event,
        jsonEncode({...event, 'notes': 'own pending'}),
      ],
    );
    await f.db.execute(
      'INSERT INTO outbox(op_id,partition,scope_id,record_id,request) VALUES(?,?,?,?,?)',
      [
        '70000000-0000-4000-8000-000000000001',
        f.runtime.partition,
        _scope,
        _event,
        '{"immutable":"own-pending"}',
      ],
    );
    await f.db.execute(
      'INSERT INTO finance_outbox(op_id,partition,scope_id,record_id,request) VALUES(?,?,?,?,?)',
      [
        '80000000-0000-4000-8000-000000000001',
        f.runtime.partition,
        _scope,
        _bank,
        '{"type":"financeAccount","immutable":"own-pending"}',
      ],
    );
    await f.db.execute(
      'INSERT INTO conflicts(id,partition,scope_id,record_id,type,reason,remote) VALUES(?,?,?,?,?,?,?)',
      [
        '90000000-0000-4000-8000-000000000001',
        f.runtime.partition,
        _scope,
        _event,
        'event',
        'conflict',
        jsonEncode({
          'id': _event,
          'type': 'event',
          'revision': 1,
          'deleted': false,
          'payload': event,
          'contractVersion': 6,
        }),
      ],
    );
  }
}

Future<List<Map<String, Object?>>> _markers(dynamic f) => f.db.rows(
  "SELECT * FROM local_meta WHERE name LIKE 'crypto_projection_cursor_v1:%'",
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'retained legacy cursor1/access2 uses actual finance pull and policy2/head0',
    () async {
      final f = await _fixture(headRevision: 0, policyRevision: 2);
      await _retain(f, cursor: 1);
      await f.repository.syncNow();
      expect(f.runtime.financePullReplies, hasLength(1));
      expect(f.repository.state.lastError, isNull);
      expect(f.runtime.financePullReplies.single['accessRevision'], 2);
      expect((await f.access.readContext(_scope, 'finance')).accessRevision, 0);
      expect(
        (await f.db.rows(
          'SELECT finance_cursor,finance_access_revision FROM scopes',
        )).single,
        {'finance_cursor': 1, 'finance_access_revision': 2},
      );
    },
  );
  test(
    'high legacy cursors replay both domains once and retry never resets them',
    () async {
      final f = await _fixture(headRevision: 0, policyRevision: 2);
      await _retain(f);
      await f.repository.syncNow();
      expect(f.repository.state.lastError, isNull);
      expect(await f.db.rows('SELECT id FROM records'), [
        {'id': _event},
      ]);
      expect(await f.db.rows('SELECT id FROM finance_records'), [
        {'id': _bank},
      ]);
      expect(
        (await f.db.rows(
          'SELECT cursor,finance_cursor,finance_complete FROM scopes',
        )).single,
        {'cursor': 1, 'finance_cursor': 1, 'finance_complete': 1},
      );
      expect(await _markers(f), hasLength(2));
      await f.db.execute('UPDATE scopes SET cursor=9,finance_cursor=9');
      await f.repository.syncNow();
      expect(f.repository.state.lastError, isNull);
      expect(
        (await f.db.rows('SELECT cursor,finance_cursor FROM scopes')).single,
        {'cursor': 9, 'finance_cursor': 9},
      );
      expect(f.runtime.transitionChecks, 1);
    },
  );
  test(
    'migration rebase preserves own pending bytes, records and conflicts',
    () async {
      final f = await _fixture(headRevision: 0, policyRevision: 2);
      await _retain(f, pending: true);
      final before = [
        await f.db.rows('SELECT * FROM outbox'),
        await f.db.rows('SELECT * FROM finance_outbox'),
        await f.db.rows('SELECT * FROM conflicts'),
      ];
      await f.repository.syncNow();
      expect(f.repository.state.lastError?.code, 'moderation_upgrade_required');
      expect([
        await f.db.rows('SELECT * FROM outbox'),
        await f.db.rows('SELECT * FROM finance_outbox'),
      ], before.take(2).toList());
      final retained = (await f.db.rows(
        'SELECT payload,remote FROM records',
      )).single;
      expect(
        (jsonDecode(retained['payload'] as String) as Map)['notes'],
        'own pending',
      );
      expect((jsonDecode(retained['remote'] as String) as Map)['id'], _event);
      final conflict = (await f.db.rows('SELECT * FROM conflicts')).single;
      expect(conflict['id'], before[2].single['id']);
      expect(conflict['reason'], before[2].single['reason']);
    },
  );
  test(
    'interruption after atomic checkpoint leaves incomplete state and retry replays',
    () async {
      final f = await _fixture(headRevision: 0, policyRevision: 2);
      await _retain(f);
      f.runtime.interruptAfterCheckpoint = true;
      await f.repository.syncNow();
      expect(f.repository.state.lastError?.code, 'network');
      expect(await _markers(f), hasLength(2));
      expect(
        (await f.db.rows(
          'SELECT cursor,finance_cursor,finance_complete FROM scopes',
        )).single,
        {'cursor': 0, 'finance_cursor': 0, 'finance_complete': 0},
      );
      expect(await f.db.rows('SELECT * FROM records'), isEmpty);
      expect(await f.db.rows('SELECT * FROM finance_records'), isEmpty);
      await f.repository.syncNow();
      expect(f.repository.state.lastError, isNull);
      expect(f.runtime.transitionChecks, 1);
      expect(await f.db.rows('SELECT id FROM records'), [
        {'id': _event},
      ]);
      expect(await f.db.rows('SELECT id FROM finance_records'), [
        {'id': _bank},
      ]);
    },
  );
  test(
    'second-domain SQLite failure rolls back both cursor resets and markers',
    () async {
      final f = await _fixture(headRevision: 0, policyRevision: 2);
      await _retain(f);
      await f.db.execute(
        "CREATE TRIGGER fail_second_cursor_marker BEFORE INSERT ON local_meta WHEN NEW.name LIKE 'crypto_projection_cursor_v1:%:finance' BEGIN SELECT RAISE(ABORT, 'synthetic_second_domain_failure'); END",
      );
      await f.repository.syncNow();
      expect(f.repository.state.lastError?.code, 'invalid_response');
      expect(await _markers(f), isEmpty);
      expect(
        (await f.db.rows(
          'SELECT cursor,finance_cursor,finance_access_revision,finance_complete FROM scopes',
        )).single,
        {
          'cursor': 99,
          'finance_cursor': 99,
          'finance_access_revision': 2,
          'finance_complete': 0,
        },
      );
      expect(await f.db.rows('SELECT * FROM records'), isEmpty);
      expect(await f.db.rows('SELECT * FROM finance_records'), isEmpty);
      await f.db.execute('DROP TRIGGER fail_second_cursor_marker');
      await f.repository.syncNow();
      expect(f.repository.state.lastError, isNull);
      expect(await _markers(f), hasLength(2));
      expect(f.runtime.transitionChecks, 2);
      expect(
        (await f.db.rows(
          'SELECT cursor,finance_cursor,finance_complete FROM scopes',
        )).single,
        {'cursor': 1, 'finance_cursor': 1, 'finance_complete': 1},
      );
      expect(await f.db.rows('SELECT id FROM records'), [
        {'id': _event},
      ]);
      expect(await f.db.rows('SELECT id FROM finance_records'), [
        {'id': _bank},
      ]);
    },
  );
  test('authority failure leaves both cursors and markers untouched', () async {
    final f = await _fixture(headRevision: 0, policyRevision: 2);
    await _retain(f);
    f.access.denied = true;
    await f.repository.syncNow();
    expect(f.repository.state.lastError?.code, 'permission_revoked');
    expect(await _markers(f), isEmpty);
    expect(
      (await f.db.rows(
        'SELECT cursor,finance_cursor,finance_complete FROM scopes',
      )).single,
      {'cursor': 99, 'finance_cursor': 99, 'finance_complete': 0},
    );
    expect(await f.db.rows('SELECT * FROM records'), isEmpty);
    expect(await f.db.rows('SELECT * FROM finance_records'), isEmpty);
  });
  test(
    'verified native origins preserve cursors; unknown origins create no marker',
    () async {
      final f = await _fixture(headRevision: 0, policyRevision: 2);
      await _retain(f);
      f.runtime.origin = null;
      await f.repository.syncNow();
      expect(await _markers(f), isEmpty);
      expect(
        (await f.db.rows('SELECT cursor FROM scopes')).single['cursor'],
        99,
      );
      f.runtime.origin = CryptoProjectionCursorOrigin.nativeOrigin;
      await f.repository.syncNow();
      expect(await _markers(f), hasLength(2));
      expect(
        (await f.db.rows('SELECT cursor,finance_cursor FROM scopes')).single,
        {'cursor': 99, 'finance_cursor': 99},
      );
    },
  );
  test(
    'mismatched finance response remains rejected after the transition',
    () async {
      final f = await _fixture(headRevision: 0, policyRevision: 2);
      await _retain(f);
      await f.repository.syncNow();
      f.runtime.staleFinanceReply = true;
      await f.db.execute('UPDATE scopes SET finance_complete=0');
      await f.repository.syncNow();
      expect(f.repository.state.lastError?.code, 'invalid_response');
      expect(
        (await f.db.rows(
          'SELECT finance_complete FROM scopes',
        )).single['finance_complete'],
        0,
      );
    },
  );
}
