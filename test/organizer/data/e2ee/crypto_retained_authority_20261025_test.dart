import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:sodium/sodium.dart';
import 'package:kanban/organizer/data/e2ee/crypto_codec.dart';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/authority_reuse_controller.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_transport.dart';
import 'package:kanban/organizer/data/device_session_store.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_store.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_repository.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_v2.dart';
import 'package:kanban/organizer/data/e2ee/crypto_identity_store.dart';
import 'package:kanban/organizer/data/e2ee/crypto_json.dart';
import 'package:kanban/organizer/data/e2ee/crypto_retained_authority.dart';
import 'package:kanban/organizer/data/e2ee/session_crypto_access.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_v2_workflow.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';

const scope = 'scope-A',
    other = 'scope-B',
    own = 'own',
    head = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
String encoded(Map<String, dynamic> value) =>
    utf8.decode(CryptoJson.encode(value));

class _Secure implements AccountCryptoStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

class _Reducer implements AccountDirectoryV2 {
  @override
  dynamic noSuchMethod(Invocation i) =>
      throw StateError('No signature seam in helper-only guard target');
}

class _Wire implements CollaborationTransport {
  int caps = 0, snapshots = 0, otherCalls = 0;
  bool failCaps = false, deny = false;
  Completer<Map<String, dynamic>>? pendingStatus;
  Map<String, dynamic>? ownStatus;
  Completer<Map<String, dynamic>>? pending;
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
    if (operation == 'capabilities') {
      caps++;
      if (failCaps) throw const CollaborationApiException('network');
      return {
        'serverId': 'server',
        'cryptoAuthoritySnapshotVersions': [1],
        'nested': {'version': 1},
      };
    }
    if (deny)
      throw const CollaborationApiException('crypto_scope_rotation_required');
    if (operation == 'crypto2.account.status' && ownStatus != null) {
      otherCalls++;
      final pending = pendingStatus;
      pendingStatus = null;
      return pending == null ? ownStatus! : pending.future;
    }
    if (operation == 'crypto2.authority.snapshot') {
      snapshots++;
      if (pending != null) {
        final p = pending!;
        pending = null;
        return p.future;
      }
      return envelope();
    }
    otherCalls++;
    return {'direct': operation};
  }

  Map<String, dynamic> envelope() => {
    'version': 1,
    'serverId': 'server',
    'accountId': own,
    'deviceId': 'device',
    'entries': [
      {
        'operation': 'crypto2.scope.headGet',
        'params': {'scopeId': scope},
        'result': {
          'headHash': head,
          'nested': {'safe': true},
        },
      },
    ],
  };
  @override
  void close() {}
}

class _F {
  _F() {
    controller.allowIfCurrent(controller.generation);
    secure.values['scope2:p:$scope'] = encoded({'epoch': 1, 'headHash': head});
    secure.values['scope2:p:$other'] = encoded({'epoch': 1, 'headHash': head});
    secure.values['directory2:p:$own'] = encoded({
      'generation': 1,
      'headHash': 'b' * 64,
      'snapshotHash': 'c' * 64,
      'deviceSnapshotHash': 'd' * 64,
      'identityEpochId': 'epoch',
      'fingerprint': 'fingerprint',
      'trustState': 'verified',
    });
    cache = CryptoRetainedAuthority(
      controller: controller,
      ownAccountId: own,
      readSecure: secure.read,
      partition: 'p',
    );
  }
  final controller = AuthorityReuseController(), secure = _Secure();
  late final CryptoRetainedAuthority cache;
  CryptoAuthorityWireRead read(
    String target, {
    Object? token,
    Map<String, dynamic>? result,
  }) => CryptoAuthorityWireRead(
    'crypto2.scope.headGet',
    {'scopeId': target},
    result ??
        {
          'headHash': head,
          'nested': {'safe': true},
        },
    token ?? controller.tokenForScope(target),
  );
  Future<void> admit(
    String target, {
    List<CryptoAuthorityWireRead>? reads,
    Future<bool> Function()? valid,
  }) => cache.admit(
    scope: target,
    headHash: head,
    accounts: [own],
    reads: reads ?? [read(target)],
    isValid: valid ?? () async => true,
  );
  Future<Map<String, dynamic>?> get(String target) =>
      cache.read('crypto2.scope.headGet', {'scopeId': target});
}

void main() {
  test(
    'admitted exact scope evidence clones maps and preserves unrelated scope generation',
    () async {
      final f = _F();
      await f.admit(scope);
      await f.admit(other);
      final value = await f.get(scope);
      (value!['nested'] as Map)['safe'] = false;
      expect((await f.get(scope))!['nested'], {'safe': true});
      f.controller.invalidateScopes({other});
      expect(await f.get(scope), isNotNull);
      expect(await f.get(other), isNull);
      f.controller.invalidate(disable: false);
      expect(await f.get(scope), isNull);
    },
  );
  test(
    'own journal-only pin movement preserves evidence but latest status cannot regress local floor',
    () async {
      final f = _F();
      await f.admit(
        scope,
        reads: [
          f.read(scope),
          CryptoAuthorityWireRead(
            'crypto2.directory.status',
            {'scopeId': scope, 'headHash': head, 'accountId': own},
            {'generation': 1},
            f.controller.tokenForScope(scope),
          ),
        ],
      );
      final pin =
          jsonDecode(f.secure.values['directory2:p:$own']!)
              as Map<String, dynamic>;
      f.secure.values['directory2:p:$own'] = encoded({
        ...pin,
        'generation': 2,
        'headHash': 'e' * 64,
      });
      expect(await f.get(scope), isNotNull);
      expect(
        await f.cache.read('crypto2.directory.status', {
          'scopeId': scope,
          'headHash': head,
          'accountId': own,
        }),
        isNull,
      );
      f.secure.values['directory2:p:$own'] = encoded({
        ...pin,
        'deviceSnapshotHash': 'f' * 64,
      });
      expect(await f.get(scope), isNull);
    },
  );
  test(
    'scope floor key trust changes and late-generation admission fail closed',
    () async {
      final f = _F();
      await f.admit(scope);
      f.secure.values['scope2:p:$scope'] = encoded({
        'epoch': 2,
        'headHash': 'e' * 64,
      });
      expect(await f.get(scope), isNull);
      f.secure.values['scope2:p:$scope'] = encoded({
        'epoch': 1,
        'headHash': head,
      });
      final stale = f.read(scope);
      f.controller.invalidateScopes({scope});
      await f.admit(scope, reads: [stale]);
      expect(await f.get(scope), isNull);
      await f.admit(scope, valid: () async => false);
      expect(await f.get(scope), isNull);
      await f.admit(scope);
      final pin =
          jsonDecode(f.secure.values['directory2:p:$own']!)
              as Map<String, dynamic>;
      f.secure.values['directory2:p:$own'] = encoded({
        ...pin,
        'pendingRootTransition': {'newFingerprint': 'changed'},
      });
      expect(await f.get(scope), isNull);
    },
  );
  test(
    'unverified mutable and over-budget wire replies are never retained',
    () async {
      final f = _F();
      await f.admit(
        scope,
        reads: [
          CryptoAuthorityWireRead(
            'crypto2.records.pull',
            {'scopeId': scope},
            {'headHash': head},
            f.controller.tokenForScope(scope),
          ),
        ],
      );
      expect(await f.get(scope), isNull);
      await f.admit(
        scope,
        reads: [
          f.read(
            scope,
            result: {
              'headHash': head,
              'body': 'x' * CryptoRetainedAuthority.maxBytes,
            },
          ),
        ],
      );
      expect(await f.get(scope), isNull);
      await f.admit(scope);
      expect(
        await f.cache.read('crypto2.scope.headGet', {
          'scopeId': scope,
          'pendingCapability': 'private',
        }),
        isNull,
      );
    },
  );
  Future<(AccountDirectoryRepository, _Wire, AuthorityReuseController)>
  directory() async {
    final db = CollaborationDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final controller = AuthorityReuseController()..allowIfCurrent(0),
        wire = _Wire();
    final session = DeviceSession(
      AccountSession(
        serverUrl: 'https://synthetic.invalid/',
        serverId: 'server',
        accountId: own,
        deviceId: 'device',
        userId: 1,
        username: 'synthetic',
        displayName: 'Synthetic',
        expiresAt: DateTime.utc(2030),
      ),
      'synthetic',
    );
    final repo = AccountDirectoryRepository(
      reducer: _Reducer(),
      session: session,
      transport: wire,
      store: CryptoIdentityStore(db, _Secure(), session.profile.partition),
      isCurrent: () => true,
      authorityReuse: controller,
    );
    return (repo, wire, controller);
  }

  test(
    'capability future is identity generation bounded copied and never retains errors',
    () async {
      final (repo, wire, controller) = await directory();
      final first = await repo.call('capabilities');
      (first['nested'] as Map)['version'] = 99;
      expect((await repo.call('capabilities'))['nested'], {'version': 1});
      expect(wire.caps, 1);
      controller.invalidate(disable: false);
      wire.failCaps = true;
      await expectLater(
        repo.call('capabilities'),
        throwsA(isA<CollaborationApiException>()),
      );
      wire.failCaps = false;
      await repo.call('capabilities');
      expect(wire.caps, 3);
    },
  );
  test(
    'unknown authority writes retire before send while content journal and table lease writes retain rights',
    () async {
      final (repo, wire, controller) = await directory();
      final before = controller.generation;
      for (final op in [
        'crypto2.records.batch',
        'crypto2.domain.checkpoint',
        'crypto2.account.scopeObserve',
        'crypto2.account.scopeObservation.put',
        'crypto2.inbox.sync',
        'crypto2.table.lease',
        'crypto2.table.acquire',
        'crypto2.table.renew',
        'crypto2.table.release',
      ]) {
        await repo.call(op, {'commandBase64': 'synthetic'});
      }
      expect(controller.generation, before);
      await repo.call('crypto2.future.authorityWrite', {
        'commandBase64': 'synthetic',
      });
      expect(controller.generation, before + 1);
      wire.deny = true;
      await expectLater(
        repo.call('crypto2.scope.headGet', {'scopeId': scope}),
        throwsA(isA<CollaborationApiException>()),
      );
      expect(controller.generation, before + 2);
    },
  );
  test(
    'scope snapshot captures token before an in-flight response and fresh bypass does not admit it',
    () async {
      final (repo, wire, controller) = await directory();
      final gate = Completer<Map<String, dynamic>>();
      wire.pending = gate;
      final pending = repo.withRetainedAuthorityReads(
        () => repo.withAuthoritySnapshot(
          () async {
            await repo.call('crypto2.scope.headGet', {'scopeId': scope});
            await repo.admitVerifiedScopeAuthority(scope, head, [own]);
          },
          isValid: () async => true,
          onMutation: () {},
        ),
      );
      await pumpEventQueue();
      controller.invalidateScopes({scope});
      gate.complete(wire.envelope());
      await pending;
      await repo.withoutRetainedAuthority(
        () => repo.withRetainedAuthorityReads(
          () => repo.withAuthoritySnapshot(
            () async {
              await repo.call('crypto2.scope.headGet', {'scopeId': scope});
              await repo.admitVerifiedScopeAuthority(scope, head, [own]);
            },
            isValid: () async => true,
            onMutation: () {},
          ),
        ),
      );
      expect(wire.snapshots, 2);
    },
  );
  test(
    'seeded scope rejects late generation and fresh-mode publication before ordinary reuse',
    () async {
      final (repo, wire, controller) = await directory();
      final secure = repo.store.secure as _Secure;
      final partition = repo.store.partition;
      secure.values['scope2:$partition:$scope'] = encoded({
        'epoch': 1,
        'headHash': head,
      });
      secure.values['directory2:$partition:$own'] = encoded({
        'generation': 1,
        'headHash': 'b' * 64,
        'snapshotHash': 'c' * 64,
        'deviceSnapshotHash': 'd' * 64,
        'trustState': 'verified',
      });
      Future<void> ordinary({bool admit = true}) =>
          repo.withRetainedAuthorityReads(
            () => repo.withAuthoritySnapshot(
              () async {
                await repo.call('crypto2.scope.headGet', {'scopeId': scope});
                if (admit)
                  await repo.admitVerifiedScopeAuthority(scope, head, [own]);
              },
              isValid: () async => true,
              onMutation: () {},
            ),
          );
      final gate = Completer<Map<String, dynamic>>();
      wire.pending = gate;
      final late = ordinary();
      await pumpEventQueue();
      controller.invalidateScopes({scope});
      gate.complete(wire.envelope());
      await late;
      // Matching secure floors allow admission; this must still fetch because
      // the only previous reply belongs to the retired generation.
      await ordinary();
      expect(wire.snapshots, 2);
      await ordinary(admit: false);
      expect(wire.snapshots, 2);
      controller.invalidateScopes({scope});
      await repo.withoutRetainedAuthority(ordinary);
      expect(wire.snapshots, 3);
      await ordinary();
      expect(wire.snapshots, 4); // Fresh mode did not admit.
      await ordinary(admit: false);
      expect(wire.snapshots, 4);
    },
  );
  test(
    'own refresh CAS cannot bless an old response after global generation moved',
    () async {
      final crypto = CryptoCodec(await SodiumInit.init());
      final reducer = AccountDirectoryV2(crypto);
      final root = crypto.sodium.crypto.sign.keyPair(),
          box = crypto.sodium.crypto.box.keyPair(),
          device = crypto.sodium.crypto.sign.keyPair();
      addTearDown(() {
        root.dispose();
        box.dispose();
        device.dispose();
      });
      final server = crypto.randomId(),
          account = crypto.randomId(),
          deviceId = crypto.randomId();
      final fingerprint = crypto.fingerprint(root.publicKey, box.publicKey);
      final init = await reducer.prepare(
        previous: null,
        serverId: server,
        accountId: account,
        deviceId: deviceId,
        identityEpochId: crypto.randomId(),
        operation: 'crypto2.account.initialize',
        signer: 'root',
        pinnedRootFingerprint: fingerprint,
        signingKey: root.secretKey,
        payload: {
          'rootSigningKeyBase64': base64Encode(root.publicKey),
          'rootEncryptionKeyBase64': base64Encode(box.publicKey),
          'deviceSigningKeyBase64': base64Encode(device.publicKey),
          'deviceEncryptionKeyBase64': base64Encode(box.publicKey),
          'keyringCiphertextBase64': base64Encode(Uint8List(48)),
        },
      );
      final db = CollaborationDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final session = DeviceSession(
        AccountSession(
          serverUrl: 'https://synthetic.invalid/',
          serverId: server,
          accountId: account,
          deviceId: deviceId,
          userId: 1,
          username: 'synthetic',
          displayName: 'Synthetic',
          expiresAt: DateTime.utc(2030),
        ),
        'synthetic',
      );
      final store = CryptoIdentityStore(
        db,
        _Secure(),
        session.profile.partition,
      );
      await store.pinRoot(
        account,
        server,
        fingerprint,
        genesisFingerprint: fingerprint,
      );
      await store.append(account, init.entry);
      await store.remember(init.result, 'verified');
      final status = <String, dynamic>{
        'serverId': server,
        'accountId': account,
        'initialized': true,
        'generation': init.result.generation,
        'headHash': init.result.headHash,
        'snapshotHash': init.result.snapshotHash,
        'deviceSnapshotHash': init.result.deviceSnapshotHash,
      };
      final wire = _Wire()..ownStatus = status;
      final controller = AuthorityReuseController()..allowIfCurrent(0);
      final repo = AccountDirectoryRepository(
        reducer: reducer,
        session: session,
        transport: wire,
        store: store,
        isCurrent: () => true,
        authorityReuse: controller,
      );
      final gate = Completer<Map<String, dynamic>>();
      wire.pendingStatus = gate;
      final pending = repo.refresh();
      await pumpEventQueue();
      controller.invalidate(disable: false);
      gate.complete(status);
      await pending;
      expect(wire.otherCalls, 1);
      await repo.withRetainedAuthorityReads(repo.currentReadDirectory);
      expect(
        wire.otherCalls,
        2,
      ); // The late old reply did not make reuse current.
      await repo.withRetainedAuthorityReads(repo.currentReadDirectory);
      expect(
        wire.otherCalls,
        2,
      ); // A new verified replay did admit this generation.
    },
  );
  test(
    'preloaded short snapshot and active operation cannot survive access generation change',
    () async {
      final (repo, wire, controller) = await directory();
      final access = SessionCryptoAccess(
        account: AccountCryptoV2Workflow(repo),
      );
      await access.withVerifiedOperation(() async {
        expect(
          (await repo.call('crypto2.scope.headGet', {
            'scopeId': scope,
          }))['headHash'],
          head,
        );
        expect(wire.snapshots, 1);
        controller.invalidateScopes({scope});
        await access.withVerifiedOperation(() async {
          expect(
            (await repo.call('crypto2.scope.headGet', {
              'scopeId': scope,
            }))['headHash'],
            head,
          );
        });
        expect(
          wire.snapshots,
          2,
        ); // A fresh operation, not old wire relabeled new.
        expect(await repo.call('crypto2.scope.headGet', {'scopeId': scope}), {
          'direct': 'crypto2.scope.headGet',
        }); // The old parent remains retired.
        expect(wire.otherCalls, 1);
      });
    },
  );
}
