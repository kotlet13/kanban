import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
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
import 'package:kanban/organizer/data/e2ee/crypto_codec.dart';
import 'package:kanban/organizer/data/e2ee/crypto_domain_router.dart';
import 'package:kanban/organizer/data/e2ee/crypto_identity_store.dart';
import 'package:kanban/organizer/data/e2ee/crypto_verified_dispatch_reads.dart';
import 'package:kanban/organizer/data/e2ee/scope_crypto_codec.dart';
import 'package:kanban/organizer/data/e2ee/session_crypto_access.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';

class _Secure implements AccountCryptoStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

class _Transport implements CollaborationTransport {
  _Transport(this.fixture);
  final _Fixture fixture;
  final calls = <String>[];
  bool forgedActivation = false;
  void Function()? beforeWrite;
  Map<String, dynamic> wire() => {
    'headHash': fixture.head.headHash,
    'proposal': fixture.proposal,
    'activation': forgedActivation
        ? {
            ...fixture.activation,
            'signatureBase64': base64Encode(Uint8List(64)),
          }
        : fixture.activation,
  };
  Map<String, dynamic> status() => {
    'generation': fixture.own.generation,
    'headHash': fixture.own.headHash,
    'snapshotHash': fixture.own.snapshotHash,
    'deviceSnapshotHash': fixture.own.deviceSnapshotHash,
  };
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
    calls.add(operation);
    if (operation == 'capabilities')
      return {
        'serverId': fixture.profile.serverId,
        'cryptoAuthoritySnapshotVersions': [1],
      };
    if (operation == 'crypto2.authority.snapshot')
      return {
        'version': 1,
        'serverId': fixture.profile.serverId,
        'accountId': fixture.profile.accountId,
        'deviceId': fixture.profile.deviceId,
        'entries': [
          {
            'operation': 'crypto2.scope.headGet',
            'params': {'scopeId': fixture.scope},
            'result': wire(),
          },
          {
            'operation': 'crypto2.account.status',
            'params': <String, dynamic>{},
            'result': {
              'serverId': fixture.profile.serverId,
              'accountId': fixture.profile.accountId,
              'initialized': true,
              ...status(),
            },
          },
          {
            'operation': 'crypto2.directory.status',
            'params': {
              'scopeId': fixture.scope,
              'headHash': fixture.head.headHash,
              'accountId': fixture.profile.accountId,
            },
            'result': status(),
          },
        ],
      };
    if (operation == 'crypto2.scope.activate') {
      beforeWrite?.call();
      expect(
        params,
        fixture.activation,
        reason: 'saved signed command stays exact',
      );
      return {'applied': true};
    }
    if (operation == 'crypto2.receipt.get') return {'outcome': 'unknown'};
    throw StateError('Unexpected synthetic transport $operation');
  }

  @override
  void close() {}
}

/// Actual signed directory + ScopeCryptoCodec proposal/activation verification
/// consume the real retained authority/transport engine. Descriptor/lifecycle
/// admission and the origin enum are an explicit seam: this is not a full native
/// origin, membership-server, migration or business-pull test.
class _ProofAccess extends SessionCryptoAccess {
  _ProofAccess(this.fixture) : super(account: fixture.account);
  final _Fixture fixture;
  @override
  Future<VerifiedScopeHead> currentHead(
    String scope, {
    bool online = false,
  }) async {
    expect(scope, fixture.scope);
    final wire = await account.directory.call('crypto2.scope.headGet', {
      'scopeId': scope,
    });
    final own = await account.directory.requireFresh();
    final status = await account.directory.call('crypto2.directory.status', {
      'scopeId': scope,
      'headHash': wire['headHash'],
      'accountId': own.accountId,
    });
    expect(status['headHash'], own.headHash);
    expect(status['deviceSnapshotHash'], own.deviceSnapshotHash);
    final codec = ScopeCryptoCodec(fixture.crypto);
    Future<VerifiedAccountDirectory> directoryAt(String id, String hash) async {
      if (id != own.accountId || hash != own.headHash)
        throw const FormatException('fixture_directory_binding');
      return own;
    }

    final pending = await codec.verifyProposal(
      serverId: own.serverId,
      authorization: Map<String, dynamic>.from(wire['proposal']),
      previous: null,
      authorDirectory: own,
      directoryAtHead: directoryAt,
      checkIdentity: (id, fingerprint) async {
        if (id != own.accountId || fingerprint != own.rootFingerprint)
          throw const FormatException('fixture_identity');
      },
    );
    final verified = await codec.verifyActivation(
      pending: pending,
      previous: null,
      authorization: Map<String, dynamic>.from(wire['activation']),
      authorDirectory: own,
      grantManifestHash: 'd' * 64,
      directoryAtHead: directoryAt,
    );
    expect(verified.headHash, wire['headHash']);
    fixture.proofChecks++;
    return verified;
  }
}

class _Fixture {
  _Fixture(this.crypto);
  final CryptoCodec crypto;
  late final db = CollaborationDatabase(NativeDatabase.memory());
  late final transport = _Transport(this);
  final secure = _Secure();
  late AccountSession profile;
  late DeviceSession session;
  late AccountCryptoV2Workflow account;
  late VerifiedAccountDirectory own;
  late VerifiedScopeHead head;
  late Map<String, dynamic> proposal, activation;
  late String scope;
  final keys = <KeyPair>[];
  var current = true, proofChecks = 0, resolutions = 0;
  Future<void> initialize() async {
    final root = crypto.sodium.crypto.sign.keyPair(),
        box = crypto.sodium.crypto.box.keyPair(),
        device = crypto.sodium.crypto.sign.keyPair();
    keys.addAll([root, box, device]);
    profile = AccountSession(
      serverUrl: 'https://synthetic.invalid/',
      serverId: crypto.randomId(),
      accountId: crypto.randomId(),
      deviceId: crypto.randomId(),
      userId: 1,
      username: 'synthetic',
      displayName: 'Synthetic',
      expiresAt: DateTime.utc(2030),
    );
    session = DeviceSession(profile, 'synthetic-token');
    scope = crypto.randomId();
    final epoch = crypto.randomId(), reducer = AccountDirectoryV2(crypto);
    final genesis = await reducer.prepare(
      previous: null,
      serverId: profile.serverId,
      accountId: profile.accountId,
      deviceId: profile.deviceId,
      identityEpochId: epoch,
      operation: 'crypto2.account.initialize',
      signer: 'root',
      signingKey: root.secretKey,
      pinnedRootFingerprint: crypto.fingerprint(root.publicKey, box.publicKey),
      payload: {
        'rootSigningKeyBase64': base64Encode(root.publicKey),
        'rootEncryptionKeyBase64': base64Encode(box.publicKey),
        'deviceSigningKeyBase64': base64Encode(device.publicKey),
        'deviceEncryptionKeyBase64': base64Encode(box.publicKey),
        'keyringCiphertextBase64': base64Encode(Uint8List(48)),
      },
    );
    own = genesis.result;
    final store = CryptoIdentityStore(db, secure, profile.partition);
    await store.append(profile.accountId, genesis.entry);
    await store.pinRoot(
      profile.accountId,
      profile.serverId,
      own.rootFingerprint,
      genesisFingerprint: own.genesisRootFingerprint,
    );
    await store.pinComparedIdentity(own, own.rootFingerprint);
    await store.remember(own, 'verified');
    account = AccountCryptoV2Workflow(
      AccountDirectoryRepository(
        reducer: reducer,
        session: session,
        transport: transport,
        store: store,
        isCurrent: () => current,
      ),
    );
    await account.directory.cachedVerifiedDirectory();
    Map<String, dynamic> command(String op, Map<String, dynamic> payload) => {
      'version': 2,
      'operation': op,
      'requestId': crypto.randomId(),
      'serverId': profile.serverId,
      'accountId': profile.accountId,
      'deviceId': profile.deviceId,
      'signer': 'device',
      'payload': payload,
    };
    final body = <String, dynamic>{
      'scopeId': scope,
      'epoch': 1,
      'previousHeadHash': cryptoZeroHash,
      'initialLifecycleHash': '1' * 64,
      'previousLifecycleHash': null,
      'accessRevision': 0,
      'expectedAccessRevision': 0,
      'accessBasis': [
        {'scopeToken': '2' * 64, 'accessRevision': 0},
      ],
      'authorDirectoryHeadHash': own.headHash,
      'members': [
        {
          'accountId': profile.accountId,
          'rootSigningKeyBase64': base64Encode(root.publicKey),
          'rootEncryptionKeyBase64': base64Encode(box.publicKey),
          'recoveryRootEpochId': epoch,
          'identityEpochId': epoch,
          'directoryHeadHash': own.headHash,
          'deviceSnapshotHash': own.deviceSnapshotHash,
          'role': 'owner',
          'financeRole': 'none',
          'manageKeys': true,
        },
      ],
      'membershipIntents': [],
      'closures': {'content': null, 'finance': null},
      'keyIds': {'content': crypto.randomId(), 'finance': null},
      'keyCommitments': {'content': '3' * 64, 'finance': null},
      'contentKeyProposalProof': null,
      'financeKeyProposalProof': null,
      'financePolicyIntentProof': null,
    };
    final codec = ScopeCryptoCodec(crypto);
    proposal = crypto.signDomain(
      command('crypto2.scope.headPut', body),
      device.secretKey,
      cryptoDirectoryDomain,
    );
    final pending = await codec.verifyProposal(
      serverId: profile.serverId,
      authorization: proposal,
      previous: null,
      authorDirectory: own,
      directoryAtHead: (_, __) async => own,
      checkIdentity: (_, __) async {},
    );
    activation = crypto.signDomain(
      command('crypto2.scope.activate', {
        'scopeId': scope,
        'headHash': pending.headHash,
        'grantManifestHash': 'd' * 64,
        'authorDirectoryHeadHash': own.headHash,
      }),
      device.secretKey,
      cryptoDirectoryDomain,
    );
    head = await codec.verifyActivation(
      pending: pending,
      previous: null,
      authorization: activation,
      authorDirectory: own,
      grantManifestHash: 'd' * 64,
      directoryAtHead: (_, __) async => own,
    );
  }

  CryptoVerifiedDispatchReads group(_ProofAccess access) =>
      CryptoVerifiedDispatchReads(
        session: session,
        accountFor: (_) async {
          resolutions++;
          return account;
        },
        createAccess: (_) => access,
      );
  Future<CryptoProjectionCursorOrigin> origin(SessionCryptoAccess? shared) {
    final access = shared ?? _ProofAccess(this);
    return access.withVerifiedOperation(() async {
      final verified = await access.currentHead(scope, online: true);
      expect(verified.active, isTrue);
      // Lifecycle/descriptor/native-origin admission is the seam stated above.
      expect(await access.recoveredMigrationGenesis(scope), isNull);
      return CryptoProjectionCursorOrigin.nativeOrigin;
    });
  }

  Future<void> close() async {
    await db.close();
    for (final key in keys) key.secretKey.dispose();
  }
}

void main() {
  late CryptoCodec crypto;
  setUpAll(() async => crypto = CryptoCodec(await SodiumInit.init()));
  Future<_Fixture> setup() async {
    final f = _Fixture(crypto);
    addTearDown(f.close);
    await f.initialize();
    return f;
  }

  test(
    'signed metadata then typed origin halves transport while both consumers verify proofs',
    () async {
      final f = await setup();
      await f.origin(null);
      await f.origin(null);
      expect(f.proofChecks, 2);
      expect(f.transport.calls, [
        'capabilities',
        'crypto2.authority.snapshot',
        'capabilities',
        'crypto2.authority.snapshot',
      ]);
      f.transport.calls.clear();
      f.proofChecks = 0;
      final group = f.group(_ProofAccess(f));
      addTearDown(group.close);
      await group.run('scopes.members', f.session, f.origin);
      expect(
        await group.runProjectionCursorOrigin(f.session, f.origin),
        CryptoProjectionCursorOrigin.nativeOrigin,
      );
      expect(f.proofChecks, 2, reason: 'signed proof checks are not skipped');
      expect(f.resolutions, 1);
      expect(f.transport.calls, ['capabilities', 'crypto2.authority.snapshot']);
    },
  );

  test(
    'typed preparation retains original deadline and cannot restart expired phase',
    () async {
      final f = await setup();
      final access = _ProofAccess(f), group = f.group(_ProofAccess(f));
      addTearDown(group.close);
      await group.run('scopes.members', f.session, f.origin);
      await Future<void>.delayed(const Duration(milliseconds: 5100));
      await group.runProjectionCursorOrigin(f.session, f.origin);
      await group.runProjectionCursorOrigin(f.session, (shared) async {
        expect(shared, isNull);
        return f.origin(access);
      });
      expect(
        f.transport.calls.where((op) => op == 'crypto2.authority.snapshot'),
        hasLength(3),
      );
      expect(group.matches(f.session), isFalse);
    },
  );

  test(
    'signed write closes prep before dispatch and receipts remain fresh',
    () async {
      final f = await setup();
      final access = _ProofAccess(f), group = f.group(_ProofAccess(f));
      addTearDown(group.close);
      final original = jsonEncode(f.activation);
      f.transport.beforeWrite = () => expect(group.matches(f.session), isFalse);
      await group.runProjectionCursorOrigin(f.session, (shared) async {
        await f.origin(shared);
        await shared!.account.directory.call(
          'crypto2.scope.activate',
          f.activation,
        );
        await shared.account.directory.call('crypto2.receipt.get', {
          'requestId': 'same',
        });
        await shared.account.directory.call('crypto2.receipt.get', {
          'requestId': 'same',
        });
      });
      expect(jsonEncode(f.activation), original);
      expect(
        f.transport.calls.where((op) => op == 'crypto2.receipt.get'),
        hasLength(2),
      );
      await group.runProjectionCursorOrigin(f.session, (shared) async {
        expect(shared, isNull);
        await f.origin(access);
      });
    },
  );

  test(
    'authority invalidation reads and rejects forged signed activation then closes prep',
    () async {
      final f = await setup();
      final group = f.group(_ProofAccess(f));
      addTearDown(group.close);
      await group.runProjectionCursorOrigin(f.session, f.origin);
      // The group's actual access must be invalidated, not an unrelated consumer.
      await group.runProjectionCursorOrigin(f.session, (shared) async {
        shared!.invalidateAuthorityOperation();
        f.transport.forgedActivation = true;
      });
      await expectLater(
        group.runProjectionCursorOrigin(f.session, f.origin),
        throwsA(isA<FormatException>()),
      );
      await group.runProjectionCursorOrigin(
        f.session,
        (shared) async => expect(shared, isNull),
      );
      expect(
        f.transport.calls.where((op) => op == 'crypto2.authority.snapshot'),
        hasLength(2),
      );
    },
  );

  test(
    'typed prep rejects changed identity public string overlap and failed phase reuse',
    () async {
      final f = await setup();
      final identity = f.group(_ProofAccess(f));
      addTearDown(identity.close);
      await identity.runProjectionCursorOrigin(f.session, f.origin);
      final changed = DeviceSession(f.profile, 'other-bearer');
      await identity.runProjectionCursorOrigin(
        changed,
        (shared) async => expect(shared, isNull),
      );
      await identity.runProjectionCursorOrigin(
        f.session,
        (shared) async => expect(shared, isNull),
      );
      final unknown = f.group(_ProofAccess(f));
      addTearDown(unknown.close);
      await unknown.runProjectionCursorOrigin(f.session, f.origin);
      await unknown.run(
        'projection.cursorOrigin',
        f.session,
        (shared) async => expect(shared, isNull),
      );
      await unknown.runProjectionCursorOrigin(
        f.session,
        (shared) async => expect(shared, isNull),
      );
      final overlap = f.group(_ProofAccess(f));
      addTearDown(overlap.close);
      final entered = Completer<void>(), release = Completer<void>();
      final a = overlap.runProjectionCursorOrigin(f.session, (shared) async {
        entered.complete();
        await release.future;
      });
      await entered.future;
      await overlap.runProjectionCursorOrigin(
        f.session,
        (shared) async => expect(shared, isNull),
      );
      release.complete();
      await a;
      await overlap.runProjectionCursorOrigin(
        f.session,
        (shared) async => expect(shared, isNull),
      );
      final failed = f.group(_ProofAccess(f));
      addTearDown(failed.close);
      await expectLater(
        failed.runProjectionCursorOrigin<void>(
          f.session,
          (_) async => throw const FormatException('failed-origin'),
        ),
        throwsFormatException,
      );
      await failed.runProjectionCursorOrigin(
        f.session,
        (shared) async => expect(shared, isNull),
      );
    },
  );
}
