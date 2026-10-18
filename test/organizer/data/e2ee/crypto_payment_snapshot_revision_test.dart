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
import 'package:kanban/organizer/domain/linked_payment_models.dart';
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
    CollaborationDatabase database,
    CollaborationTransport transport,
    DeviceSessionStore sessionStore,
    this.payments,
  ) : super(
        database,
        transport,
        sessionStore,
        cryptoRouter: _PolicyRouter(payments.context),
      );
  final CryptoBusinessPayments payments;
  set beforeDelivery(Future<void> Function()? callback) =>
      (payments.context as _Runtime).beforeDelivery = callback;
}

class _PolicyRouter implements CryptoDomainRouter {
  _PolicyRouter(this.runtime);
  final CryptoBusinessSession runtime;
  @override
  Future<Map<String, dynamic>> dispatch({
    required DeviceSession session,
    required String operation,
    required Map<String, Object?> params,
    required Set<String> protectedScopeIds,
  }) async {
    if (operation == 'finance4.policy' || operation == 'finance2.policy') {
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final entry in [
    (head: 0, policy: 1, expected: 1),
    (head: 4, policy: 3, expected: 7),
  ]) {
    test(
      'payment snapshot uses effective policy revision ${entry.policy} with raw head ${entry.head}',
      () async {
        final f = await _fixture(
          headRevision: entry.head,
          policyRevision: entry.policy,
        );
        final policy = await f.runtime.financePolicy(_scope);
        final snapshot = await CryptoBusinessPayments(
          f.runtime,
        ).dispatch('finance3.payments', {'scopeId': _scope});
        expect(policy['revision'], entry.expected);
        expect(snapshot['accessRevision'], policy['revision']);
        expect(
          (await f.access.readContext(_scope, 'finance')).accessRevision,
          entry.head,
        );
        final result = await f.repository.fetchLinkedPayments(
          PaymentSpaceRef(_scope, partition: f.runtime.partition),
        );
        expect(result.fresh, true);
        expect(result.events, isEmpty);
      },
    );
  }
  test('permission denial keeps payment snapshot uninstalled', () async {
    final f = await _fixture();
    f.access.denied = true;
    await expectLater(
      f.repository.fetchLinkedPayments(
        PaymentSpaceRef(_scope, partition: f.runtime.partition),
      ),
      throwsA(
        isA<CollaborationException>().having(
          (e) => e.code,
          'code',
          'permission_revoked',
        ),
      ),
    );
    expect(await f.db.rows('SELECT * FROM linked_payment_events'), isEmpty);
    expect(
      await f.db.rows(
        "SELECT * FROM local_meta WHERE name LIKE 'linked_payment_complete:%'",
      ),
      isEmpty,
    );
  });
  test('local access generation change still rejects delivery', () async {
    final f = await _fixture();
    f.repository.beforeDelivery = () => f.db.execute(
      'INSERT INTO local_meta(name,value) VALUES(?,?) ON CONFLICT(name) DO UPDATE SET value=excluded.value',
      ['finance_access_generation:${f.runtime.partition}:$_scope', '999'],
    );
    await expectLater(
      f.repository.fetchLinkedPayments(
        PaymentSpaceRef(_scope, partition: f.runtime.partition),
      ),
      throwsA(
        isA<CollaborationException>().having(
          (e) => e.code,
          'code',
          'finance_access_changed',
        ),
      ),
    );
    expect(await f.db.rows('SELECT * FROM linked_payment_events'), isEmpty);
    expect(
      await f.db.rows(
        "SELECT * FROM local_meta WHERE name LIKE 'linked_payment_complete:%'",
      ),
      isEmpty,
    );
  });
}
