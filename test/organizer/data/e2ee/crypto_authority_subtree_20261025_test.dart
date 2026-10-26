import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_transport.dart';
import 'package:kanban/organizer/data/device_session_store.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_store.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_v2_workflow.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_repository.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_v2.dart';
import 'package:kanban/organizer/data/e2ee/crypto_authority_snapshot.dart';
import 'package:kanban/organizer/data/e2ee/crypto_codec.dart';
import 'package:kanban/organizer/data/e2ee/crypto_identity_store.dart';
import 'package:kanban/organizer/data/e2ee/session_crypto_access.dart';
import 'package:kanban/organizer/data/e2ee/scope_crypto_codec.dart';
import 'package:kanban/organizer/data/e2ee/crypto_json.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:sodium/sodium.dart';

// The production currentHead/read-directory preparation and real account-prefix
// signatures execute. Stop at the lifecycle seam before head signature/descriptor
// admission; this is a request-count/lifetime test, not complete head authority.
class _Prepared extends Error {}

class _Secure implements AccountCryptoStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

class _Access extends SessionCryptoAccess {
  _Access({required super.account, this.boundaries = true});
  final bool boundaries;
  int prepared = 0;
  @override
  Future<T> withVerifiedOperation<T>(
    Future<T> Function() body, {
    bool freshBoundary = false,
  }) => boundaries
      ? super.withVerifiedOperation(body, freshBoundary: freshBoundary)
      : body();
  @override
  Future<String> verifyInitialLifecycle(
    String scopeId,
    Map<String, dynamic> wire, {
    required String scopeHeadHash,
  }) async {
    prepared++;
    throw _Prepared();
  }
}

class _Wire implements CollaborationTransport {
  _Wire(this.session, this.directories, this.head);
  final DeviceSession session;
  final List<VerifiedAccountDirectory> directories;
  final Map<String, dynamic> head;
  final calls = <String>[];
  bool deny = false;
  Map<String, dynamic> status(VerifiedAccountDirectory d) => {
    'serverId': d.serverId,
    'accountId': d.accountId,
    'initialized': true,
    'generation': d.generation,
    'headHash': d.headHash,
    'snapshotHash': d.snapshotHash,
    'deviceSnapshotHash': d.deviceSnapshotHash,
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
    if (deny) throw const CollaborationApiException('permission_revoked');
    if (operation == 'capabilities') {
      return {
        'serverId': session.profile.serverId,
        'cryptoAuthoritySnapshotVersions': [1],
      };
    }
    if (operation == 'crypto2.authority.snapshot') {
      return {
        'version': 1,
        'serverId': session.profile.serverId,
        'accountId': session.profile.accountId,
        'deviceId': session.profile.deviceId,
        'entries': [
          {
            'operation': 'crypto2.account.status',
            'params': <String, dynamic>{},
            'result': status(directories.first),
          },
          {
            'operation': 'crypto2.scope.headGet',
            'params': {'scopeId': head['payload']['scopeId']},
            'result': head,
          },
          for (final d in directories)
            {
              'operation': 'crypto2.directory.status',
              'params': {
                'scopeId': head['payload']['scopeId'],
                'headHash': head['headHash'],
                'accountId': d.accountId,
              },
              'result': status(d),
            },
        ],
      };
    }
    if (operation == 'crypto2.account.scopeObservations') {
      return {'observations': <Object>[], 'hasMore': false};
    }
    if (operation == 'crypto2.scope.headGet') return head;
    if (operation == 'crypto2.account.status') return status(directories.first);
    if (operation == 'crypto2.directory.status') {
      return status(
        directories.singleWhere((d) => d.accountId == params['accountId']),
      );
    }
    if (operation == 'crypto2.scope.activate') {
      return {'syntheticMutationBarrier': true};
    }
    throw StateError('Unexpected synthetic request: $operation');
  }

  @override
  void close() {}
}

class _Fixture {
  _Fixture(
    this.db,
    this.secure,
    this.directory,
    this.wire,
    this.access,
    this.scope,
    this.headHash,
    this.own,
  );
  final CollaborationDatabase db;
  final _Secure secure;
  final AccountDirectoryRepository directory;
  final _Wire wire;
  final _Access access;
  final String scope, headHash, own;
  bool current = true;
  Future<void> prepare() => expectLater(
    access.currentHead(scope, online: true),
    throwsA(isA<_Prepared>()),
  );
  Future<VerifiedAccountDirectory> member() =>
      access.currentMemberDirectory(scope, headHash, own);
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  Future<_Fixture> fixture({bool boundaries = true}) async {
    final crypto = CryptoCodec(await SodiumInit.init());
    final reducer = AccountDirectoryV2(crypto);
    final server = crypto.randomId(),
        scope = crypto.randomId(),
        own = crypto.randomId(),
        peer = crypto.randomId(),
        deviceId = crypto.randomId();
    final ids = [own, peer]..sort();
    final prepared = <String, PreparedDirectoryMutation>{};
    for (final id in ids) {
      final root = crypto.sodium.crypto.sign.keyPair(),
          box = crypto.sodium.crypto.box.keyPair(),
          signer = crypto.sodium.crypto.sign.keyPair();
      addTearDown(() {
        root.dispose();
        box.dispose();
        signer.dispose();
      });
      prepared[id] = await reducer.prepare(
        previous: null,
        serverId: server,
        accountId: id,
        deviceId: id == own ? deviceId : crypto.randomId(),
        identityEpochId: crypto.randomId(),
        operation: 'crypto2.account.initialize',
        signer: 'root',
        pinnedRootFingerprint: crypto.fingerprint(
          root.publicKey,
          box.publicKey,
        ),
        signingKey: root.secretKey,
        payload: {
          'rootSigningKeyBase64': base64Encode(root.publicKey),
          'rootEncryptionKeyBase64': base64Encode(box.publicKey),
          'deviceSigningKeyBase64': base64Encode(signer.publicKey),
          'deviceEncryptionKeyBase64': base64Encode(box.publicKey),
          'keyringCiphertextBase64': base64Encode(Uint8List(48)),
        },
      );
    }
    final ownPrefix = prepared[own]!.result;
    final members = [
      for (final id in ids)
        {
          'accountId': id,
          'rootSigningKeyBase64':
              prepared[id]!.result.snapshot['rootSigningKeyBase64'],
          'rootEncryptionKeyBase64':
              prepared[id]!.result.snapshot['rootEncryptionKeyBase64'],
          'recoveryRootEpochId':
              prepared[id]!.result.snapshot['recoveryRootEpochId'],
          'identityEpochId': prepared[id]!.result.identityEpochId,
          'directoryHeadHash': prepared[id]!.result.headHash,
          'deviceSnapshotHash': prepared[id]!.result.deviceSnapshotHash,
          'role': id == own ? 'owner' : 'member',
          'financeRole': 'none',
          'manageKeys': id == own,
        },
    ];
    final body = <String, dynamic>{
      'scopeId': scope,
      'epoch': 1,
      'previousHeadHash': cryptoZeroHash,
      'accessRevision': 0,
      'expectedAccessRevision': 0,
      'accessBasis': [
        {'scopeToken': 'a' * 64, 'accessRevision': 0},
      ],
      'members': members,
      'membershipIntents': <Object>[],
      'initialLifecycleHash': 'b' * 64,
      'previousLifecycleHash': null,
      'closures': {'content': null, 'finance': null},
      'keyCommitments': {'content': 'c' * 64, 'finance': null},
      'keyIds': {'content': crypto.randomId(), 'finance': null},
      'authorDirectoryHeadHash': ownPrefix.headHash,
      'financeKeyProposalProof': null,
      'contentKeyProposalProof': null,
    };
    final session = DeviceSession(
      AccountSession(
        serverUrl: 'https://synthetic.invalid/',
        serverId: server,
        accountId: own,
        deviceId: deviceId,
        userId: 1,
        username: 'synthetic',
        displayName: 'Synthetic',
        expiresAt: DateTime.utc(2030),
      ),
      'synthetic',
    );
    final db = CollaborationDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final secure = _Secure(),
        store = CryptoIdentityStore(db, secure, session.profile.partition);
    for (final id in ids) {
      final d = prepared[id]!.result;
      await store.pinRoot(
        id,
        server,
        d.rootFingerprint,
        genesisFingerprint: d.rootFingerprint,
      );
      await store.append(id, prepared[id]!.entry);
      await store.remember(d, 'verified');
    }
    // Same canonical head hash checked by the production preparation path.
    final head = <String, dynamic>{
      'headHash': await ScopeCryptoCodec(crypto).headHash(body),
      'payload': body,
    };
    late _Fixture f;
    final wire = _Wire(session, [ownPrefix, prepared[peer]!.result], head);
    final actualDirectory = AccountDirectoryRepository(
      reducer: reducer,
      session: session,
      transport: wire,
      store: store,
      isCurrent: () => f.current,
    );
    final actualAccess = _Access(
      account: AccountCryptoV2Workflow(actualDirectory),
      boundaries: boundaries,
    );
    f = _Fixture(
      db,
      secure,
      actualDirectory,
      wire,
      actualAccess,
      scope,
      head['headHash'],
      own,
    );
    // Startup has already discovered capability metadata in the native case.
    // Warm this non-authority metadata identically for baseline/fixed fixtures.
    await actualDirectory.call('capabilities');
    wire.calls.clear();
    return f;
  }

  test(
    'actual head preparation baseline4 becomes3 requests including all metadata; sparse directory remains1',
    () async {
      final counts = <String, Map<String, int>>{};
      for (final enabled in [false, true]) {
        final f = await fixture(boundaries: enabled);
        await f.prepare();
        expect(f.access.prepared, 1);
        expect(
          f.wire.calls.length,
          enabled ? 3 : 4,
          reason: f.wire.calls.join(','),
        );
        expect(
          f.wire.calls.where((op) => op == 'crypto2.directory.status'),
          enabled ? isEmpty : hasLength(2),
        );
        counts[enabled ? 'fixed' : 'boundaryDisabledBaseline'] = {
          for (final op in f.wire.calls.toSet())
            op: f.wire.calls.where((value) => value == op).length,
          'total': f.wire.calls.length,
        };
        f.wire.calls.clear();
        await f.member();
        expect(f.wire.calls, ['crypto2.directory.status']);
      }
      // ignore: avoid_print
      print(
        jsonEncode({
          'headPreparationRequestCounts': counts,
          'scopeProof':
              'lifecycle stop seam; real account directory signatures and SQLite',
        }),
      );
    },
  );

  test(
    'same outer job after write gets fresh subtree without reviving caller authority',
    () async {
      final f = await fixture();
      await f.access.withVerifiedOperation(() async {
        await f.prepare();
        expect(
          f.wire.calls.where((op) => op == 'crypto2.authority.snapshot'),
          hasLength(1),
        );
        await f.directory.call('crypto2.scope.activate', {
          'commandBase64': 'synthetic',
        });
        await f.prepare();
        expect(
          f.wire.calls.where((op) => op == 'crypto2.authority.snapshot'),
          hasLength(2),
        );
        final before = f.wire.calls.length;
        await f.directory.call('crypto2.account.status');
        expect(
          f.wire.calls.length,
          before + 1,
        ); // Parent stays invalid after child.
      });
    },
  );

  test(
    'active nesting shares member proof; pin lifecycle expiry and identity remain boundaries',
    () async {
      final f = await fixture();
      await f.access.withVerifiedOperation(() async {
        await f.member();
        await f.member();
        expect(f.wire.calls, ['crypto2.directory.status']);
        final key = 'directory2:${f.directory.store.partition}:${f.own}';
        f.secure.values[key] = utf8.decode(
          CryptoJson.encode({
            ...jsonDecode(f.secure.values[key]!) as Map,
            'verificationMethod': 'syntheticChangedPin',
          }),
        );
        await f.member();
        expect(f.wire.calls, [
          'crypto2.directory.status',
          'crypto2.directory.status',
        ]);
        f.current = false;
        final before = f.wire.calls.length;
        await expectLater(f.member(), throwsA(isA<CryptoDirectoryException>()));
        expect(f.wire.calls.length, before);
        f.current = true;
      });
      await f.access.withVerifiedOperation(() async {
        await f.member();
        final before = f.wire.calls.length;
        binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await f.member();
        expect(f.wire.calls.length, before + 1);
        binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      });
      await f.access.withVerifiedOperation(() async {
        await f.member();
        final before = f.wire.calls.length;
        await Future<void>.delayed(const Duration(milliseconds: 5100));
        await f.member();
        expect(f.wire.calls.length, before + 1);
        await f.directory.call('crypto2.account.status');
        expect(
          f.wire.calls.last,
          'crypto2.account.status',
        ); // Original clock not renewed.
      });
    },
  );

  test(
    'proof denial propagates once and subsequent independent preparation rechecks',
    () async {
      final f = await fixture();
      f.wire.deny = true;
      await expectLater(
        f.access.currentHead(f.scope, online: true),
        throwsA(isA<CollaborationApiException>()),
      );
      final before = f.wire.calls.length;
      f.wire.deny = false;
      await f.prepare();
      expect(f.wire.calls.length, greaterThan(before));
      expect(f.access.prepared, 1);
      expect(before, 1); // One rejected request, no automatic retry.
      expect(
        f.wire.calls.where((op) => op == 'crypto2.authority.snapshot'),
        hasLength(1),
      );
    },
  );

  test(
    'capability and preauthorization reads preserve exact lease while unknown and signed writes retire it',
    () async {
      var mutations = 0;
      final requests = <String>[];
      final memo = CryptoAuthoritySnapshot(
        read: (operation, params) async {
          requests.add(operation);
          if (operation == 'capabilities') {
            return {
              'serverId': 'server',
              'cryptoAuthoritySnapshotVersions': [1],
            };
          }
          if (operation == 'crypto2.authority.snapshot') {
            return {
              'version': 1,
              'serverId': 'server',
              'accountId': 'account',
              'deviceId': 'device',
              'entries': [
                {
                  'operation': 'crypto2.account.status',
                  'params': <String, dynamic>{},
                  'result': {'valid': true},
                },
              ],
            };
          }
          return {'direct': operation};
        },
        serverId: 'server',
        accountId: 'account',
        deviceId: 'device',
        isValid: () async => true,
        onMutation: () => mutations++,
      );
      await memo.call('crypto2.account.status', {});
      await memo.call('capabilities', {});
      await memo.call('crypto2.invitations.resolvePreauthorization', {
        'scopeId': 'same',
        'afterGeneration': 0,
      });
      expect(await memo.call('crypto2.account.status', {}), {'valid': true});
      expect(mutations, 0);
      await memo.call('unknown.operation', {});
      expect(await memo.call('crypto2.account.status', {}), {
        'direct': 'crypto2.account.status',
      });
      expect(mutations, 1);
      await memo.call('crypto2.invitations.resolvePreauthorization', {
        'commandBase64': 'synthetic',
      });
      expect(mutations, 2);
      expect(
        requests.where((op) => op == 'crypto2.authority.snapshot'),
        hasLength(1),
      );
    },
  );
}
