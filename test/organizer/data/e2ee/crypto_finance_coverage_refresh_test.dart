import 'dart:convert';
import 'dart:async';

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
import 'package:kanban/organizer/data/e2ee/crypto_finance_policy_actions.dart';
import 'package:kanban/organizer/data/e2ee/crypto_finance_topology.dart';
import 'package:kanban/organizer/domain/linked_payment_models.dart';
import 'package:kanban/organizer/domain/organization_finance_projection.dart';
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
        'organizationFinanceContractVersions': [1],
        'features': {
          'recordSync': true,
          'finance': true,
          'organizationFinance': true,
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
  String headHash = 'a' * 64;
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
  }) async => {'kind': 'household', 'accessPolicyVersion': 3};
  @override
  Future<String> verifyInitialLifecycle(
    String scopeId,
    Map<String, dynamic> wire, {
    required String scopeHeadHash,
  }) async => wire['initialLifecycleHash'] as String;
}

// Identity/head and network receipt boundaries are synthetic. Actual coverage,
// checkpoint queries, policy dispatch and repository delivery run unchanged.
class _Runtime extends CryptoBusinessSession {
  _Runtime(super.account, super.access, super.db);
  Future<void> Function()? beforeDelivery;
  final financePullReplies = <Map<String, dynamic>>[];
  final pulls = <String>[];
  bool changeHeadDuringContent = false;
  bool failFinancePull = false;
  Map<String, dynamic> policyReplyOverrides = {};
  Future<void> Function()? onPolicyReply, beforeFinancePull;
  @override
  bool get financePolicyOnly =>
      Zone.current[_PolicyRouter.policyOnlyKey] is Map;
  @override
  Future<List<Map<String, dynamic>>> catalog() async => [
    {'id': _scope},
  ];
  @override
  Future<void> pullVerified(
    String scopeId,
    String domain, {
    bool attest = true,
  }) async {
    await access.readContext(scopeId, domain);
    pulls.add(domain);
    if (domain == 'finance') {
      await beforeFinancePull?.call();
      if (failFinancePull) throw const CollaborationException('network');
    }
    if (domain == 'content' && changeHeadDuringContent) {
      (access as _Access).head.headHash = 'd' * 64;
    }
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
    implements
        CryptoDomainRouter,
        CryptoProjectionCursorTransition,
        CryptoFinancePolicyReadContext {
  _PolicyRouter(this.runtime);
  final CryptoBusinessSession runtime;
  static final policyOnlyKey = Object();
  @override
  Future<CryptoFinancePolicyReadResult<T>> withFinancePolicyOnly<T>(
    Future<T> Function() read,
  ) async {
    final attempt = {'dispatched': false};
    final value = await runZoned(read, zoneValues: {policyOnlyKey: attempt});
    return CryptoFinancePolicyReadResult(
      value,
      policyOnly: attempt['dispatched']!,
    );
  }

  @override
  Future<CryptoProjectionCursorOrigin?> verifyProjectionCursorOrigin({
    required DeviceSession session,
    required String scopeId,
  }) async {
    await runtime.access.currentHead(scopeId, online: true);
    return CryptoProjectionCursorOrigin.nativeOrigin;
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
    if (operation == 'finance2.pull' || operation == 'finance4.pull') {
      final reply = await runtime.pull(_scope, 'finance', params);
      (runtime as _Runtime).financePullReplies.add(reply);
      return reply;
    }
    if (operation == 'finance4.policy' || operation == 'finance2.policy') {
      final attempt = Zone.current[policyOnlyKey];
      if (attempt is Map) attempt['dispatched'] = true;
      final reply = await CryptoFinancePolicyActions(
        runtime,
      ).dispatch(operation, params);
      final fixture = runtime as _Runtime;
      await fixture.onPolicyReply?.call();
      return {...reply, ...fixture.policyReplyOverrides};
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
    kind: SharedScopeKind.household,
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

const _bank = '60000000-0000-4000-8000-000000000001';
Future<void> _seed(dynamic f) async {
  final now = DateTime.utc(2026, 10, 18);
  final metadataId = await f.runtime.reservedRecordId(_scope, 'scopeMetadata');
  final topology = await CryptoFinanceTopology.create(
    serverId: f.runtime.account.directory.session.profile.serverId,
    scopeId: _scope,
    childTokens: [],
  );
  final metadata = {
    'name': 'Synthetic household',
    'archived': false,
    'financeTopology': topology,
  };
  final bank = SharedFinanceAccount(
    id: _bank,
    name: 'Synthetic bank',
    currency: 'EUR',
    openingBalanceMinor: 6789,
    createdAt: now,
    updatedAt: now,
  ).toPayload(contractVersion: 3);
  for (final item in [
    (
      domain: 'content',
      id: metadataId as String,
      type: 'scopeMetadata',
      payload: metadata,
    ),
    (domain: 'finance', id: _bank, type: 'financeAccount', payload: bank),
  ]) {
    final address = f.runtime.address(_scope, item.domain, item.type, item.id);
    await f.runtime.addresses.install(address);
    final canonical = {
      'id': item.id,
      'type': item.type,
      'revision': 1,
      'deleted': false,
      'payload': item.payload,
      'contractVersion': item.domain == 'finance' ? 3 : 6,
    };
    await f.db.execute(
      "INSERT INTO crypto_business_records VALUES(?,?,?,?,?,1,1,?,0,?,?,?,'legacy')",
      [
        f.runtime.partition,
        _scope,
        item.domain,
        address.wireId,
        item.type,
        'b' * 64,
        jsonEncode(item.payload),
        jsonEncode(canonical),
        'migrationCapturedSource',
      ],
    );
    await f.db.execute(
      "INSERT INTO crypto_received(partition,scope_id,domain,record_id,revision,sequence,wire,verdict) VALUES(?,?,?,?,1,1,'{}','verified')",
      [f.runtime.partition, _scope, item.domain, address.wireId],
    );
    await f.db.execute(
      "INSERT INTO crypto_scope_state(partition,scope_id,domain,state,epoch,access_revision,scope_sequence,complete,floor) VALUES(?,?,?,'committed',1,0,1,1,1)",
      [f.runtime.partition, _scope, item.domain],
    );
    if (item.domain == 'finance') {
      await f.db.execute(
        "INSERT INTO crypto_domain_checkpoints VALUES(?,?,? ,?,1,0,1,?,1,'synthetic-finance-snapshot','{}','migrationCapturedSource')",
        [f.runtime.partition, _scope, item.domain, 'a' * 64, 'c' * 64],
      );
      await f.db.execute(
        "INSERT INTO crypto_domain_inventory_rows VALUES(?,'synthetic-finance-snapshot',?,1,?,1,1)",
        [f.runtime.partition, address.wireId, 'b' * 64],
      );
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'policy-only background retains old coverage but a failed pull never claims fresh sync',
    () async {
      final f = await _fixture(headRevision: 0, policyRevision: 2);
      await _seed(f);
      await f.repository.syncNow();
      final success = f.repository.state.lastSuccessfulSyncAt;
      expect(success, isNotNull);
      var policyOnlyReads = 0;
      f.runtime.onPolicyReply = () async {
        expect(f.runtime.financePolicyOnly, isTrue);
        policyOnlyReads++;
      };
      f.runtime.beforeFinancePull = () async {
        final row = (await f.db.rows(
          'SELECT finance_policy FROM scopes WHERE id=?',
          [_scope],
        )).single;
        expect(
          (jsonDecode(row['finance_policy'] as String)
              as Map)['organizationFinanceComplete'],
          isTrue,
        );
      };
      f.runtime.failFinancePull = true;
      await f.repository.syncNow();
      expect(policyOnlyReads, 1);
      expect(f.repository.state.lastError?.code, 'network');
      expect(f.repository.state.lastSuccessfulSyncAt, success);
      // A default/manual refresh still performs full coverage work.
      f.runtime.onPolicyReply = null;
      await expectLater(
        f.repository.refreshFinancePolicy(_scope),
        throwsA(isA<CollaborationException>()),
      );
    },
  );

  for (final change in <String, Object>{
    'enabled': false,
    'grant': 'none',
    'revision': 3,
    'requiredContractVersion': 2,
    'managedByOrganizationPolicy': false,
    'readAccessFromMembership': false,
    'linkedPaymentsRequired': false,
  }.entries) {
    test(
      'policy-only change to ${change.key} invalidates prior aggregate immediately',
      () async {
        final f = await _fixture(headRevision: 0, policyRevision: 2);
        await _seed(f);
        await f.repository.syncNow();
        expect(
          f.repository.state
              .financePolicyForScope(_scope)
              .organizationFinanceComplete,
          isTrue,
        );
        f.runtime.policyReplyOverrides = {change.key: change.value};
        var sawFreshPolicy = false;
        f.runtime.beforeFinancePull = () async {
          final row = (await f.db.rows(
            'SELECT finance_policy FROM scopes WHERE id=?',
            [_scope],
          )).single;
          expect(
            (jsonDecode(row['finance_policy'] as String)
                as Map)['organizationFinanceComplete'],
            isFalse,
          );
          sawFreshPolicy = true;
        };
        f.runtime.failFinancePull = true;
        await f.repository.syncNow();
        expect(
          f.repository.state
              .financePolicyForScope(_scope)
              .organizationFinanceComplete,
          isFalse,
        );
        if (change.key == 'enabled' || change.key == 'grant') {
          expect(
            f.repository.state.financePolicyForScope(_scope).canRead,
            isFalse,
          );
          expect(sawFreshPolicy, isFalse);
        } else {
          expect(sawFreshPolicy, isTrue);
          expect(f.repository.state.lastError?.code, 'network');
        }
      },
    );
  }

  test(
    'policy-only generation race stays pending instead of returning cached write permission',
    () async {
      final f = await _fixture(headRevision: 0, policyRevision: 2);
      await _seed(f);
      await f.repository.syncNow();
      final success = f.repository.state.lastSuccessfulSyncAt;
      expect(f.repository.state.financePolicyForScope(_scope).canWrite, isTrue);
      f.runtime.onPolicyReply = () async {
        final key = 'finance_access_generation:${f.runtime.partition}:$_scope';
        await f.db.execute(
          "UPDATE local_meta SET value=CAST(CAST(value AS INTEGER)+1 AS TEXT) WHERE name=?",
          [key],
        );
      };
      f.runtime.financePullReplies.clear();
      await f.repository.syncNow();
      expect(f.runtime.financePullReplies, isEmpty);
      expect(
        f.repository.state.lastError?.code,
        'crypto_reconciliation_required',
      );
      expect(f.repository.state.lastSuccessfulSyncAt, success);
    },
  );

  test(
    'fresh empty-child household coverage survives linked-payment and policy refresh',
    () async {
      final f = await _fixture(headRevision: 0, policyRevision: 2);
      await _seed(f);
      expect(
        (await f.runtime.organizationFinanceCoverage(
          _scope,
        ))['organizationFinanceComplete'],
        true,
      );
      f.runtime.pulls.clear();
      await f.runtime.financePolicy(_scope);
      expect(
        f.runtime.pulls,
        isEmpty,
        reason: 'internal revision reads must not trigger coverage pulls',
      );
      await f.repository.syncNow();
      expect(f.repository.state.lastError, isNull);
      expect(
        f.runtime.financePullReplies.single['organizationFinanceComplete'],
        true,
      );
      expect(
        f.repository.state
            .financePolicyForScope(_scope)
            .organizationFinanceComplete,
        true,
      );
      final payments = await f.repository.fetchLinkedPayments(
        PaymentSpaceRef(_scope, partition: f.runtime.partition),
      );
      await f.repository.refreshFinancePolicy(_scope);
      final projection = projectOrganizationFinance(
        state: f.repository.state,
        scopeId: _scope,
        paymentsByScope: {_scope: payments},
      );
      expect(projection.complete, true);
      expect(projection.accounts, hasLength(1));
      final ledger = summarizeSharedFinance(
        accounts: projection.accounts,
        entries: projection.entries,
        transfers: projection.transfers,
        payments: projection.payments,
      );
      expect(ledger['EUR']!.balanceMinor, BigInt.from(6789));
    },
  );
  test(
    'new selected child invalidates old true coverage at unchanged policy revision',
    () async {
      final f = await _fixture(headRevision: 0, policyRevision: 2);
      await _seed(f);
      await f.repository.syncNow();
      expect(
        f.repository.state
            .financePolicyForScope(_scope)
            .organizationFinanceComplete,
        true,
      );
      final metadataId = await f.runtime.reservedRecordId(
        _scope,
        'scopeMetadata',
      );
      final row = (await f.runtime.record(
        _scope,
        'content',
        metadataId,
        type: 'scopeMetadata',
      ))!;
      final raw = Map<String, dynamic>.from(
        jsonDecode(row['raw_payload'] as String) as Map,
      );
      final server = f.runtime.account.directory.session.profile.serverId;
      raw['financeTopology'] = await CryptoFinanceTopology.create(
        serverId: server,
        scopeId: _scope,
        childTokens: [
          await CryptoFinanceTopology.childToken(
            server,
            _scope,
            '70000000-0000-4000-8000-000000000001',
          ),
        ],
        previous: Map<String, dynamic>.from(raw['financeTopology'] as Map),
      );
      await f.db.execute(
        "UPDATE crypto_business_records SET raw_payload=?,record_proof_hash=? WHERE partition=? AND scope_id=? AND type='scopeMetadata'",
        [jsonEncode(raw), 'e' * 64, f.runtime.partition, _scope],
      );
      final policy = await f.repository.refreshFinancePolicy(_scope);
      expect(policy.revision, 2);
      expect(policy.organizationFinanceComplete, false);
      expect(
        f.repository.state
            .financePolicyForScope(_scope)
            .organizationFinanceComplete,
        false,
      );
    },
  );
  test('incomplete root inventory cannot reuse prior true coverage', () async {
    final f = await _fixture(headRevision: 0, policyRevision: 2);
    await _seed(f);
    await f.repository.syncNow();
    expect(
      f.repository.state
          .financePolicyForScope(_scope)
          .organizationFinanceComplete,
      true,
    );
    await f.db.execute(
      "UPDATE crypto_scope_state SET complete=0 WHERE domain='finance'",
    );
    final policy = await f.repository.refreshFinancePolicy(_scope);
    expect(policy.organizationFinanceComplete, false);
    expect(
      f.repository.state
          .financePolicyForScope(_scope)
          .organizationFinanceComplete,
      false,
    );
  });
  test(
    'stale root checkpoint blocks coverage even with complete flag set',
    () async {
      final f = await _fixture(headRevision: 0, policyRevision: 2);
      await _seed(f);
      await f.repository.syncNow();
      expect(
        f.repository.state
            .financePolicyForScope(_scope)
            .organizationFinanceComplete,
        true,
      );
      await f.db.execute('UPDATE crypto_domain_checkpoints SET head_hash=?', [
        'd' * 64,
      ]);
      expect(
        (await f.db.rows(
          "SELECT complete FROM crypto_scope_state WHERE domain='finance'",
        )).single['complete'],
        1,
      );
      final policy = await f.repository.refreshFinancePolicy(_scope);
      expect(policy.organizationFinanceComplete, false);
    },
  );
  test(
    'root head change during coverage cannot publish a prior head result',
    () async {
      final f = await _fixture(headRevision: 0, policyRevision: 2);
      await _seed(f);
      await f.repository.syncNow();
      expect(
        f.repository.state
            .financePolicyForScope(_scope)
            .organizationFinanceComplete,
        true,
      );
      f.runtime.changeHeadDuringContent = true;
      final policy = await f.repository.refreshFinancePolicy(_scope);
      expect(policy.organizationFinanceComplete, false);
    },
  );
  test(
    'denied finance policy cannot retain coverage or pull finance data',
    () async {
      final f = await _fixture(headRevision: 0, policyRevision: 2);
      await _seed(f);
      await f.repository.syncNow();
      expect(
        f.repository.state
            .financePolicyForScope(_scope)
            .organizationFinanceComplete,
        true,
      );
      f.access.head.members.single['financeRole'] = 'none';
      f.runtime.pulls.clear();
      final policy = await f.repository.refreshFinancePolicy(_scope);
      expect(policy.canRead, false);
      expect(policy.organizationFinanceComplete, false);
      expect(f.runtime.pulls, isEmpty);
    },
  );
}
