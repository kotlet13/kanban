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
import 'package:kanban/organizer/data/e2ee/crypto_lifecycle_evidence.dart';
import 'package:kanban/organizer/data/e2ee/crypto_record_address.dart';
import 'package:kanban/organizer/data/e2ee/crypto_sync_repository.dart';
import 'package:kanban/organizer/data/e2ee/scope_crypto_codec.dart';
import 'package:kanban/organizer/data/e2ee/session_crypto_access.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';

// Handcrafted already-verified authority/projection seams. Real BusinessSession
// scope projection, lifecycle traversal, SQL, policy rollback and parent-token
// binding run unchanged. This is not a new signature/server verification test.
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

class _Access extends SessionCryptoAccess {
  _Access(this.f) : super(account: f.account);
  final _Fixture f;
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

class _Fixture {
  _Fixture(this.crypto);
  final CryptoCodec crypto;
  final db = CollaborationDatabase(NativeDatabase.memory());
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

void main() {
  late CryptoCodec crypto;
  setUpAll(() async {
    crypto = CryptoCodec(await SodiumInit.init());
  });
  Future<_Fixture> setup() async {
    final f = _Fixture(crypto);
    addTearDown(f.db.close);
    await f.initialize();
    return f;
  }

  test(
    'preview projection: scoped helper matches full projector without unrelated reads',
    () async {
      final f = await setup();
      final scoped = await f.read();
      expect(scoped, isNotNull);
      expect(
        f.transport.calls.where((x) => x.op == 'crypto2.scopes.catalog'),
        isEmpty,
      );
      expect(
        f.transport.calls
            .where((x) => x.params.containsKey('scopeId'))
            .every((x) => x.params['scopeId'] == f.target),
        isTrue,
      );
      expect(f.access.heads.toSet(), {f.target});
      expect(f.access.descriptorReads.toSet(), {f.target});
      final scope = (scoped!['scopes'] as List).single as Map;
      expect(scope['name'], 'Verified ${f.target}');
      expect(scope['role'], 'member');
      expect(scope['verifiedParentOwner'], isFalse);
      final full = await f.business.scopes();
      expect(
        (full['scopes'] as List).cast<Map>().singleWhere(
          (x) => x['id'] == f.target,
        ),
        scope,
      );
      expect(f.access.descriptorReads.toSet(), {f.target, f.other, f.parent});
    },
  );
  test(
    'preview projection: signed parent binding resolves or safely falls back',
    () async {
      for (final mode in ['current', 'stale', 'revokedParent']) {
        final f = await setup();
        f.descriptors[f.target] = {
          'kind': 'project',
          'accessPolicyVersion': 3,
          'parentScopeToken': await CryptoLifecycleEvidence(f.access)
              .parentToken(
                f.target,
                mode == 'stale' ? crypto.randomId() : f.parent,
              ),
        };
        await f.cache({
          'kind': 'project',
          'parentScopeId': f.parent,
          'parentScopeKind': 'household',
          'verifiedParentOwner': true,
        });
        if (mode == 'revokedParent') {
          final row = (await f.db.rows('SELECT data FROM scopes WHERE id=?', [
            f.parent,
          ])).single;
          await f.db.execute('UPDATE scopes SET data=? WHERE id=?', [
            jsonEncode({
              ...jsonDecode(row['data'] as String) as Map,
              'revoked': true,
            }),
            f.parent,
          ]);
        }
        final result = await f.read();
        if (mode == 'stale') {
          expect(result, isNull);
          continue;
        }
        final scope = (result!['scopes'] as List).single as Map;
        expect(scope['parentScopeId'], f.parent);
        expect(scope['verifiedParentOwner'], isFalse);
        expect(
          scope['parentScopeKind'],
          mode == 'current' ? 'household' : null,
        );
        expect(f.access.descriptorReads.contains(f.parent), mode == 'current');
        expect(f.access.ownerChecks.last, f.parent);
      }
    },
  );
  test(
    'preview projection: missing evidence rollback and target revocation stay guarded',
    () async {
      for (final mode in ['missing', 'rollback', 'revoked']) {
        final f = await setup();
        if (mode == 'missing') {
          await f.db.execute(
            "DELETE FROM crypto_business_records WHERE scope_id=? AND type='scopeMetadata'",
            [f.target],
          );
          expect(await f.read(), isNull);
          expect(f.transport.calls, isEmpty);
          expect(f.access.heads, isEmpty);
        } else if (mode == 'rollback') {
          await f.cache({'recordPolicyVersion': 1});
          await expectLater(
            f.read(),
            throwsA(
              isA<CryptoAuthorityPending>().having(
                (x) => x.reason,
                'reason',
                'crypto_record_policy_activation_rollback',
              ),
            ),
          );
        } else {
          f.revoked.add(f.target);
          await expectLater(
            f.read(),
            throwsA(
              isA<CollaborationApiException>().having(
                (x) => x.code,
                'code',
                'permission_revoked',
              ),
            ),
          );
        }
        expect(
          (await f.db.rows('SELECT blocked FROM scopes WHERE id=?', [
            f.target,
          ])).single['blocked'],
          0,
        );
        expect(
          f.transport.calls.where((x) => x.op == 'crypto2.records.pull'),
          isEmpty,
        );
      }
    },
  );
}
