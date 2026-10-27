import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_transport.dart';
import 'package:kanban/organizer/data/device_session_store.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_store.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_v2_workflow.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_repository.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_v2.dart';
import 'package:kanban/organizer/data/e2ee/crypto_codec.dart';
import 'package:kanban/organizer/data/e2ee/crypto_identity_store.dart';
import 'package:kanban/organizer/data/e2ee/crypto_json.dart';
import 'package:kanban/organizer/data/e2ee/invite_crypto_repository.dart';
import 'package:kanban/organizer/data/e2ee/scope_crypto_manager.dart';
import 'package:kanban/organizer/data/e2ee/session_crypto_access.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:sodium/sodium.dart';

class _ProjectionBoundary implements Exception {}

class _Secure implements AccountCryptoStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

class _Wire implements CollaborationTransport {
  _Wire(this.session, this.own, this.recipient);
  final DeviceSession session;
  final PreparedDirectoryMutation own, recipient;
  final calls = <String>[];
  bool denyOwn = false, tamperRecipient = false;
  Map<String, dynamic> get status => {
    'serverId': own.result.serverId,
    'accountId': own.result.accountId,
    'initialized': true,
    'generation': own.result.generation,
    'headHash': own.result.headHash,
    'snapshotHash': own.result.snapshotHash,
    'deviceSnapshotHash': own.result.deviceSnapshotHash,
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
    if (operation == 'capabilities') {
      return {
        'serverId': session.profile.serverId,
        'invitationPreauthorizationVersions': [1],
        'cryptoAuthoritySnapshotVersions': [1],
      };
    }
    if (operation == 'crypto2.invitations.resolvePreauthorization') {
      final entry = Map<String, dynamic>.from(
        jsonDecode(jsonEncode(recipient.entry)) as Map,
      );
      if (tamperRecipient) {
        (entry['authorization'] as Map)['signatureBase64'] = base64Encode(
          Uint8List(64),
        );
      }
      return {
        'recipient': {
          'kind': 'email',
          'value': 'peer@synthetic.invalid',
          'accountId': recipient.result.accountId,
        },
        'preauthorization': {
          'policyVersion': 1,
          'member': {
            'accountId': recipient.result.accountId,
            'directoryHeadHash': recipient.result.headHash,
            'deviceSnapshotHash': recipient.result.deviceSnapshotHash,
            'role': 'member',
          },
        },
        'recipientDirectory': {
          'entries': [entry],
          'headHash': recipient.result.headHash,
          'generation': recipient.result.generation,
          'snapshotHash': recipient.result.snapshotHash,
          'hasMore': false,
        },
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
            if (!denyOwn) 'result': status,
            if (denyOwn)
              'error': {
                'code': 'device_revoked',
                'details': <String, dynamic>{},
                'status': 403,
              },
          },
        ],
      };
    }
    if (operation == 'crypto2.account.status') {
      if (denyOwn) throw const CollaborationApiException('device_revoked');
      return status;
    }
    if (operation == 'crypto2.invitations.publishPreauthorization') {
      denyOwn = true;
      return {'syntheticMutation': true};
    }
    throw StateError('Unexpected synthetic operation: $operation');
  }

  @override
  void close() {}
}

class _Access extends SessionCryptoAccess {
  _Access({required super.account, required this.wire, this.boundaries = true});
  final _Wire wire;
  final bool boundaries;
  bool mutateAtProjection = false;
  int projectionReads = 0;
  @override
  Future<T> withVerifiedOperation<T>(
    Future<T> Function() body, {
    bool freshBoundary = false,
  }) => boundaries
      ? super.withVerifiedOperation(body, freshBoundary: freshBoundary)
      : body();

  // Stop before policy/lifecycle projection. The actual invitation dispatch,
  // recipient directory signature replay and own-directory refresh execute.
  // Four consumers at this seam expose request reuse without claiming an entire
  // rotation, grant publication, finance policy or native end-to-end result.
  @override
  Future<Map<String, dynamic>> verifiedScopeDescriptor(
    Object? scopeId, {
    bool online = false,
  }) async {
    for (var i = 0; i < 4; i++) {
      await account.directory.requireFresh();
      projectionReads++;
      if (i == 0 && mutateAtProjection) {
        await account.directory.call(
          'crypto2.invitations.publishPreauthorization',
          {'commandBase64': 'synthetic-signed-mutation-barrier'},
        );
      }
    }
    throw _ProjectionBoundary();
  }
}

class _Manager extends ScopeCryptoManager {
  _Manager(super.access, this.authorization);
  final Map<String, dynamic> authorization;
  int creates = 0;
  @override
  Future<Map<String, dynamic>> invitationCommand(
    String operation,
    String scopeId,
    Map<String, dynamic> payload, {
    required String actionKey,
    String? deliveryToken,
  }) async {
    expect(operation, 'crypto2.invitations.create');
    creates++;
    return {'authorization': authorization};
  }
}

class _Invites extends InviteCryptoRepository {
  _Invites(super.access, this.fixtureManager);
  final _Manager fixtureManager;
  @override
  ScopeCryptoManager get manager => fixtureManager;
}

class _Fixture {
  _Fixture(this.db, this.access, this.invites, this.wire, this.params);
  final CollaborationDatabase db;
  final _Access access;
  final _Invites invites;
  final _Wire wire;
  final Map<String, Object?> params;
  Future<Map<String, dynamic>> send() =>
      invites.dispatch('invitations.create', params);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Future<_Fixture> fixture({bool boundaries = true}) async {
    final crypto = CryptoCodec(await SodiumInit.init());
    final reducer = AccountDirectoryV2(crypto);
    final server = crypto.randomId(),
        own = crypto.randomId(),
        peer = crypto.randomId(),
        device = crypto.randomId(),
        scope = crypto.randomId(),
        action = crypto.randomId();
    final prepared = <String, PreparedDirectoryMutation>{};
    for (final id in [own, peer]) {
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
        deviceId: id == own ? device : crypto.randomId(),
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
    final session = DeviceSession(
      AccountSession(
        serverUrl: 'https://synthetic.invalid/',
        serverId: server,
        accountId: own,
        deviceId: device,
        userId: 1,
        username: 'synthetic',
        displayName: 'Synthetic',
        expiresAt: DateTime.utc(2030),
      ),
      'synthetic',
    );
    final db = CollaborationDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final store = CryptoIdentityStore(db, _Secure(), session.profile.partition);
    final directoryState = prepared[own]!.result;
    await store.pinRoot(
      own,
      server,
      directoryState.rootFingerprint,
      genesisFingerprint: directoryState.rootFingerprint,
    );
    await store.append(own, prepared[own]!.entry);
    await store.remember(directoryState, 'verified');
    final wire = _Wire(session, prepared[own]!, prepared[peer]!);
    final directory = AccountDirectoryRepository(
      reducer: reducer,
      session: session,
      transport: wire,
      store: store,
      isCurrent: () => true,
    );
    final access = _Access(
      account: AccountCryptoV2Workflow(directory),
      wire: wire,
      boundaries: boundaries,
    );
    final params = <String, Object?>{
      'scopeId': scope,
      'requestId': action,
      'recipient': 'peer@synthetic.invalid',
    };
    final payload = <String, dynamic>{
      'scopeId': scope,
      'invitationId': crypto.randomId(),
      'role': 'member',
      'recipient': {'kind': 'email', 'value': 'peer@synthetic.invalid'},
      'preauthorization': {
        'member': {'accountId': peer},
      },
    };
    final authorization = <String, dynamic>{
      'commandBase64': base64Encode(CryptoJson.encode({'payload': payload})),
    };
    await db.execute('INSERT INTO crypto_invitation_drafts VALUES(?,?,?,?)', [
      store.partition,
      action,
      jsonEncode({
        'callerHash': await cryptoSha256(
          CryptoJson.encode({
            'operation': 'invitations.create',
            'params': params,
          }),
        ),
        'payload': payload,
      }),
      'synthetic-retained-token',
    ]);
    return _Fixture(
      db,
      access,
      _Invites(access, _Manager(access, authorization)),
      wire,
      params,
    );
  }

  test(
    'send27 same preparation reuses own signed prefix inside one fresh operation',
    () async {
      final counts = <String, int>{};
      for (final enabled in [false, true]) {
        final f = await fixture(boundaries: enabled);
        await expectLater(f.send(), throwsA(isA<_ProjectionBoundary>()));
        expect(f.access.projectionReads, 4);
        expect(
          f.wire.calls.where((op) => op == 'crypto2.account.status').length,
          enabled ? 0 : 4,
        );
        expect(
          f.wire.calls.where((op) => op == 'crypto2.authority.snapshot').length,
          enabled ? 1 : 0,
        );
        counts[enabled ? 'operation' : 'boundaryDisabledBaseline'] =
            f.wire.calls.length;
        expect(f.wire.calls.length, enabled ? 4 : 6);
      }
      // ignore: avoid_print
      print(jsonEncode({'sendPreparationSeamRequestCounts': counts}));
    },
  );

  test(
    'send27 fresh preparation rejects revocation despite ambient cached own authority',
    () async {
      final f = await fixture();
      await f.access.withVerifiedOperation(() async {
        await f.access.account.directory.requireFresh();
        f.wire.denyOwn = true;
        await expectLater(
          f.send(),
          throwsA(
            isA<CollaborationApiException>().having(
              (e) => e.code,
              'code',
              'device_revoked',
            ),
          ),
        );
      });
      expect(f.access.projectionReads, 0);
      expect(
        f.wire.calls.where((op) => op == 'crypto2.authority.snapshot').length,
        2,
      );
    },
  );

  test(
    'send27 signed delivery retires preparation snapshot before next freshness read',
    () async {
      final f = await fixture();
      f.access.mutateAtProjection = true;
      await expectLater(
        f.send(),
        throwsA(
          isA<CollaborationApiException>().having(
            (e) => e.code,
            'code',
            'device_revoked',
          ),
        ),
      );
      expect(f.access.projectionReads, 1);
      expect(
        f.wire.calls.where((op) => op == 'crypto2.account.status').length,
        1,
      );
      expect(
        (await f.db.rows(
          'SELECT token FROM crypto_invitation_drafts',
        )).single['token'],
        'synthetic-retained-token',
      );
    },
  );

  test(
    'send27 tampered recipient signature cannot reach rights or own freshness consumers',
    () async {
      final f = await fixture();
      f.wire.tamperRecipient = true;
      await expectLater(
        f.send(),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            'crypto_signature',
          ),
        ),
      );
      expect(f.access.projectionReads, 0);
      expect(
        f.wire.calls.where((op) => op == 'crypto2.authority.snapshot'),
        isEmpty,
      );
      expect(
        (await f.db.rows(
          'SELECT token FROM crypto_invitation_drafts',
        )).single['token'],
        'synthetic-retained-token',
      );
    },
  );
  test(
    'send27 confirmation child and publication fresh-boundary mechanism never inherits prior status',
    () async {
      // Mechanism control only: production callsites for these private phases are
      // reviewed separately; this does not execute rotations or child admission.
      for (final phase in ['confirmation', 'child', 'publication']) {
        final f = await fixture();
        await f.access.withVerifiedOperation(() async {
          await f.access.account.directory.requireFresh();
          await f.access.account.directory.requireFresh();
          expect(
            f.wire.calls
                .where((op) => op == 'crypto2.authority.snapshot')
                .length,
            1,
          );
          f.wire.denyOwn = true;
          await expectLater(
            f.access.withVerifiedOperation(() async {
              await f.access.account.directory.requireFresh();
            }, freshBoundary: true),
            throwsA(
              isA<CollaborationApiException>().having(
                (e) => e.code,
                phase,
                'device_revoked',
              ),
            ),
          );
          expect(
            f.wire.calls
                .where((op) => op == 'crypto2.authority.snapshot')
                .length,
            2,
          );
        });
      }
    },
  );
}
