import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sodium/sodium.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_transport.dart';
import 'package:kanban/organizer/data/device_session_store.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_store.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_v2_workflow.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_repository.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_v2.dart';
import 'package:kanban/organizer/data/e2ee/crypto_business_router.dart';
import 'package:kanban/organizer/data/e2ee/crypto_codec.dart';
import 'package:kanban/organizer/data/e2ee/crypto_domain_router.dart';
import 'package:kanban/organizer/data/e2ee/crypto_identity_store.dart';
import 'package:kanban/organizer/data/e2ee/crypto_record_address.dart';
import 'package:kanban/organizer/data/e2ee/crypto_sync_repository.dart';
import 'package:kanban/organizer/data/e2ee/scope_crypto_codec.dart';
import 'package:kanban/organizer/data/e2ee/session_crypto_access.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';

// Already-verified authority/pull seams. The production accepted-scope helper,
// scope projection, lifecycle, complete/current checkpoint checks and SQL paging
// run here. This is not a signature, native-device or HTTP verification test.
class _Secure implements AccountCryptoStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

class _Own implements VerifiedAccountDirectory {
  _Own(this.accountId, this.serverId);
  @override
  final String accountId;
  @override
  final String serverId;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Head implements VerifiedScopeHead {
  _Head(this.scopeId, this.account, this.role);
  @override
  final String scopeId;
  final String account, role;
  @override
  String get headHash => 'a' * 64;
  @override
  int get epoch => 1;
  @override
  int get accessRevision => 2;
  @override
  Map<String, dynamic> get body => {
    'initialLifecycleHash': '1' * 64,
    'previousHeadHash': '0' * 64,
    'previousLifecycleHash': null,
  };
  @override
  Map<String, dynamic> member(String id) {
    if (id != account) throw const FormatException('fixture_member');
    return {'accountId': id, 'role': role, 'financeRole': 'none'};
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Transport implements CollaborationTransport {
  _Transport(this.f);
  final _Fixture f;
  final calls = <({String op, Map<String, Object?> params})>[];
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
    calls.add((op: operation, params: params));
    if (operation == 'capabilities') {
      return {
        'serverId': f.session.profile.serverId,
        'recordPolicyVersions': <int>[],
      };
    }
    if (operation == 'crypto2.scopes.catalog') {
      final ids = f.descriptors.keys.toList()..sort();
      return {
        'scopes': [
          for (final id in ids) {'id': id},
        ],
        'hasMore': false,
      };
    }
    if (operation == 'crypto2.scope.lifecycle.baseline') {
      return {
        'initialLifecycleBaseline': {
          'ownArchived': false,
          'inheritedArchived': false,
        },
      };
    }
    if (operation == 'crypto2.scope.lifecycle.list') {
      return {'states': <Object>[], 'hasMore': false, 'currentRevision': 0};
    }
    throw StateError('Unexpected fixture transport $operation');
  }

  @override
  void close() {}
}

class _Directory implements AccountDirectoryRepository {
  _Directory(this.session, this.reducer, this.store, this.transport, this.own);
  @override
  final DeviceSession session;
  @override
  final AccountDirectoryV2 reducer;
  @override
  final CryptoIdentityStore store;
  @override
  final CollaborationTransport transport;
  final VerifiedAccountDirectory own;
  @override
  String get accountId => session.profile.accountId;
  @override
  bool Function() get isCurrent =>
      () => true;
  @override
  Future<VerifiedAccountDirectory> requireFresh() async => own;
  @override
  Future<Map<String, dynamic>> call(
    String op, [
    Map<String, dynamic> params = const {},
  ]) => transport.call(
    serverUrl: session.profile.serverUrl,
    operation: op,
    params: params,
    token: session.token,
  );
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Lease implements CryptoVerifiedReadLease {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Access extends SessionCryptoAccess {
  _Access(this.f) : super(account: f.account);
  final _Fixture f;
  bool authorityCurrent = true;
  @override
  Future<T> withVerifiedOperation<T>(
    Future<T> Function() body, {
    bool freshBoundary = false,
  }) => body();
  @override
  Future<CryptoVerifiedReadLease?> verifiedReadLease() async => _Lease();
  @override
  Future<bool> isVerifiedReadLeaseCurrent(
    CryptoVerifiedReadLease lease,
  ) async => authorityCurrent;
  @override
  Future<CryptoReadContext> readContext(String scope, String domain) async =>
      CryptoReadContext(epoch: 1, accessRevision: 2, headHash: 'a' * 64);
  final heads = <String>[],
      descriptorReads = <String>[],
      ownerChecks = <String?>[];
  @override
  Future<VerifiedScopeHead> currentHead(
    String scope, {
    bool online = false,
  }) async {
    heads.add(scope);
    if (f.revoked.contains(scope)) {
      throw const CollaborationApiException('permission_revoked');
    }
    return _Head(scope, f.session.profile.accountId, f.roles[scope] ?? 'owner');
  }

  @override
  Future<Map<String, dynamic>> verifiedScopeDescriptor(
    String scope, {
    bool online = false,
  }) async {
    descriptorReads.add(scope);
    return f.descriptors[scope]!;
  }

  @override
  Future<String> verifyInitialLifecycle(
    String scope,
    Map<String, dynamic> wire, {
    required String scopeHeadHash,
  }) async => '1' * 64;
  @override
  Set<String> observedLifecycleHashes(String scope) => {};
  @override
  Future<bool> isRecordOwner(
    String scope,
    String account, {
    VerifiedScopeHead? head,
    String? parentScopeId,
    bool requireParentEvidence = false,
  }) async {
    ownerChecks.add(parentScopeId);
    return false;
  }
}

class _RaceDatabase extends CollaborationDatabase {
  _RaceDatabase() : super(NativeDatabase.memory());
  Future<void> Function()? afterFirstPage;
  @override
  Future<List<Map<String, dynamic>>> rows(
    String sql, [
    List<Object?> arguments = const [],
  ]) async {
    final result = await super.rows(sql, arguments);
    if (sql.startsWith('SELECT b.type,b.projection,r.sequence') &&
        sql.endsWith('LIMIT 100') &&
        afterFirstPage != null) {
      final mutate = afterFirstPage!;
      afterFirstPage = null;
      await mutate();
    }
    return result;
  }
}

class _Fixture {
  _Fixture(this.crypto);
  final CryptoCodec crypto;
  final db = _RaceDatabase();
  late final target = crypto.randomId(),
      other = crypto.randomId(),
      parent = crypto.randomId(),
      task = crypto.randomId();
  final descriptors = <String, Map<String, dynamic>>{};
  final roles = <String, String>{};
  final revoked = <String>{};
  late DeviceSession session;
  late AccountCryptoV2Workflow account;
  late _Transport transport;
  late _Access access;
  late CryptoBusinessSession business;
  String get p => session.profile.partition;
  Future<void> initialize() async {
    final profile = AccountSession(
      serverUrl: 'https://fixture.invalid/',
      serverId: crypto.randomId(),
      accountId: crypto.randomId(),
      deviceId: crypto.randomId(),
      userId: 1,
      username: 'fixture',
      displayName: 'Fixture',
      expiresAt: DateTime.utc(2030),
    );
    session = DeviceSession(profile, 'synthetic');
    await db.execute('INSERT INTO accounts(partition,profile) VALUES(?,?)', [
      p,
      jsonEncode(profile.toJson()),
    ]);
    transport = _Transport(this);
    account = AccountCryptoV2Workflow(
      _Directory(
        session,
        AccountDirectoryV2(crypto),
        CryptoIdentityStore(db, _Secure(), p),
        transport,
        _Own(profile.accountId, profile.serverId),
      ),
    );
    access = _Access(this);
    business = CryptoBusinessSession(account, access, db);
    for (final id in [target, other, parent]) {
      descriptors[id] = {'kind': 'household', 'accessPolicyVersion': 3};
      await db.execute('INSERT INTO scopes(partition,id,data) VALUES(?,?,?)', [
        p,
        id,
        jsonEncode(
          SharedScope(
            id: id,
            name: 'Cached',
            kind: SharedScopeKind.household,
            role: SharedRole.viewer,
          ).toJson(),
        ),
      ]);
      final metadata = await business.reservedRecordId(id, 'scopeMetadata');
      final wire = cryptoWireRecordId(
        profile.serverId,
        id,
        'scopeMetadata',
        metadata,
      );
      await db.execute(
        "INSERT INTO crypto_business_records(partition,scope_id,domain,id,type,crypto_revision,record_proof_hash,deleted,raw_payload,projection,history_basis) VALUES(?,?,'content',?,'scopeMetadata',1,?,0,?,?,'currentEpoch')",
        [
          p,
          id,
          wire,
          'b' * 64,
          jsonEncode({'name': 'Verified $id', 'address': null}),
          jsonEncode({'id': metadata}),
        ],
      );
    }
    await db.execute(
      "INSERT INTO records(partition,scope_id,id,type,local_revision,server_revision,payload,deleted) VALUES(?,?,?,'task',1,1,'{}',0)",
      [p, target, task],
    );
    roles[target] = 'member';
  }

  Future<void> cache(Map<String, Object?> changes) async {
    final row = (await db.rows('SELECT data FROM scopes WHERE id=?', [
      target,
    ])).single;
    await db.execute('UPDATE scopes SET data=? WHERE id=?', [
      jsonEncode({...jsonDecode(row['data'] as String) as Map, ...changes}),
      target,
    ]);
  }

  Future<Map<String, dynamic>?> read() =>
      business.visibleTaskScope(CryptoVisibleTaskMetadataTarget(target, task));
}

class _AcceptedBusiness extends CryptoBusinessSession {
  _AcceptedBusiness(super.account, super.access, super.db);
  final pulled = <(String, String)>[];
  bool completeAuthority = true;
  Object? pullError;
  @override
  Future<void> pullVerified(
    String scopeId,
    String domain, {
    bool attest = true,
  }) async {
    pulled.add((scopeId, domain));
    if (pullError != null) throw pullError!;
  }

  @override
  Future<bool> hasReusableCheckpoint(
    String scope,
    String domain,
    CryptoReadContext read,
  ) async => completeAuthority;
}

void main() {
  late CryptoCodec crypto;
  setUpAll(() async {
    crypto = CryptoCodec(await SodiumInit.init());
  });
  Future<(_Fixture, _AcceptedBusiness)> setup() async {
    final f = _Fixture(crypto);
    addTearDown(f.db.close);
    await f.initialize();
    final business = _AcceptedBusiness(f.account, f.access, f.db);
    await f.db.execute(
      "INSERT INTO crypto_scope_state(partition,scope_id,domain,complete) VALUES(?,?,'content',1)",
      [f.p, f.target],
    );
    return (f, business);
  }

  test(
    'acceptproject27 real target projector pages105 records and skips unrelated discovery',
    () async {
      final (f, b) = await setup();
      for (var i = 1; i <= 105; i++) {
        final id = crypto.randomId();
        await f.db.execute(
          "INSERT INTO crypto_business_records(partition,scope_id,domain,id,type,crypto_revision,record_proof_hash,deleted,raw_payload,projection,history_basis) VALUES(?,?,'content',?,'task',1,?,0,'{}',?,'currentEpoch')",
          [
            f.p,
            f.target,
            id,
            'b' * 64,
            jsonEncode({'id': id, 'type': 'task', 'revision': 1}),
          ],
        );
        await f.db.execute(
          "INSERT INTO crypto_received(partition,scope_id,domain,record_id,revision,sequence,wire,verdict) VALUES(?,?,'content',?,1,?,'{}','verified')",
          [f.p, f.target, id, i],
        );
      }
      final result = await b.acceptedScope(f.target, 0);
      expect(result.records, hasLength(105));
      expect(result.cursor, 105);
      expect(result.scope['name'], 'Verified ${f.target}');
      expect(result.scope['role'], 'member');
      expect(b.pulled, [(f.target, 'content')]);
      expect(f.access.heads.toSet(), {f.target});
      expect(f.access.descriptorReads.toSet(), {f.target});
      expect(
        f.transport.calls.where((r) => r.op == 'crypto2.scopes.catalog'),
        isEmpty,
      );
      expect(await result.isCurrent(), true);
      await f.db.execute(
        "UPDATE crypto_scope_state SET complete=0 WHERE scope_id=?",
        [f.target],
      );
      expect(await result.isCurrent(), false);
    },
  );
  test(
    'acceptproject27 incomplete content refuses target despite signed metadata',
    () async {
      final (f, b) = await setup();
      await f.db.execute(
        'UPDATE crypto_scope_state SET complete=0 WHERE scope_id=?',
        [f.target],
      );
      await expectLater(
        b.acceptedScope(f.target, 0),
        throwsA(isA<CryptoAuthorityPending>()),
      );
    },
  );
  test(
    'acceptproject27 missing signed scope metadata never fabricates ready empty target',
    () async {
      final (f, b) = await setup();
      await f.db.execute(
        "DELETE FROM crypto_business_records WHERE scope_id=? AND type='scopeMetadata'",
        [f.target],
      );
      await expectLater(
        b.acceptedScope(f.target, 0),
        throwsA(isA<CryptoAuthorityPending>()),
      );
    },
  );
  test('acceptproject27 revoked membership stops before target pull', () async {
    final (f, b) = await setup();
    f.revoked.add(f.target);
    await expectLater(
      b.acceptedScope(f.target, 0),
      throwsA(isA<CollaborationApiException>()),
    );
    expect(b.pulled, isEmpty);
  });
  test(
    'acceptproject27 stale checkpoint and missing keys remain pending',
    () async {
      final (f, b) = await setup();
      b.completeAuthority = false;
      await expectLater(
        b.acceptedScope(f.target, 0),
        throwsA(isA<CryptoAuthorityPending>()),
      );
      b.completeAuthority = true;
      b.pullError = const CryptoAuthorityPending('crypto_device_keys_pending');
      await expectLater(
        b.acceptedScope(f.target, 0),
        throwsA(isA<CryptoAuthorityPending>()),
      );
    },
  );
  test(
    'acceptproject27 final authority generation remains required after materialization',
    () async {
      final (f, b) = await setup();
      final result = await b.acceptedScope(f.target, 0);
      f.access.authorityCurrent = false;
      expect(await result.isCurrent(), false);
    },
  );
  test(
    'acceptmaterializationrace27 content advancement between page and final capture cannot bless mixed snapshot',
    () async {
      final (f, b) = await setup();
      f.db.afterFirstPage = () async {
        await f.db.execute(
          'UPDATE crypto_scope_state SET transport_cursor=1,projection_cursor=1,scope_sequence=1 WHERE scope_id=?',
          [f.target],
        );
      };
      await expectLater(
        b.acceptedScope(f.target, 0),
        throwsA(isA<CryptoAuthorityPending>()),
      );
    },
  );
}
