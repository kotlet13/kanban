import 'dart:async';
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
import 'package:kanban/organizer/data/e2ee/crypto_access_coordinator.dart';
import 'package:kanban/organizer/data/e2ee/crypto_business_router.dart';
import 'package:kanban/organizer/data/e2ee/crypto_codec.dart';
import 'package:kanban/organizer/data/e2ee/crypto_identity_store.dart';
import 'package:kanban/organizer/data/e2ee/crypto_json.dart';
import 'package:kanban/organizer/data/e2ee/session_crypto_access.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:sodium/sodium.dart';

class _Secure implements AccountCryptoStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

class _NoNetwork implements CollaborationTransport {
  int calls = 0;
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
    calls++;
    throw StateError('Unexpected network call: $operation');
  }

  @override
  void close() {}
}

// Supplies the already independently verified current own directory. The
// coordinator still replays its signed historical prefix, checks its secure
// anchor, and verifies both the prepare and final device signatures itself.
class _Directory extends AccountDirectoryRepository {
  _Directory({
    required super.reducer,
    required super.session,
    required super.transport,
    required super.store,
    required super.isCurrent,
    required this.current,
  });
  final VerifiedAccountDirectory current;
  @override
  Future<VerifiedAccountDirectory> requireFresh() async => current;
}

void main() {
  late CryptoCodec crypto;
  late CollaborationDatabase db;
  late KeyPair root, device, box;
  late SessionCryptoAccess access;
  late CryptoAccessCoordinator coordinator;
  late _NoNetwork transport;
  late String scope, intent, request, partition;
  late Map<String, dynamic> prepared, finalProof, response;

  Future<void> save() async {
    await db.execute(
      'INSERT OR REPLACE INTO crypto_membership_intents VALUES(?,?,?,?,?,?)',
      [
        partition,
        scope,
        request,
        'confirmed',
        CryptoJson.encode({
          'receipt': {'response': response},
        }),
        CryptoJson.encode(finalProof),
      ],
    );
  }

  setUpAll(() async => crypto = CryptoCodec(await SodiumInit.init()));
  setUp(() async {
    db = CollaborationDatabase(NativeDatabase.memory());
    root = crypto.sodium.crypto.sign.keyPair();
    device = crypto.sodium.crypto.sign.keyPair();
    box = crypto.sodium.crypto.box.keyPair();
    transport = _NoNetwork();
    final profile = AccountSession(
      serverUrl: 'https://synthetic.invalid',
      serverId: crypto.randomId(),
      accountId: crypto.randomId(),
      userId: 1,
      username: 'owner',
      displayName: 'Owner',
      deviceId: crypto.randomId(),
      expiresAt: DateTime.utc(2030),
    );
    partition = profile.partition;
    final store = CryptoIdentityStore(db, _Secure(), partition);
    final reducer = AccountDirectoryV2(crypto);
    final genesis = await reducer.prepare(
      previous: null,
      serverId: profile.serverId,
      accountId: profile.accountId,
      deviceId: profile.deviceId,
      identityEpochId: crypto.randomId(),
      operation: 'crypto2.account.initialize',
      signer: 'root',
      pinnedRootFingerprint: crypto.fingerprint(root.publicKey, box.publicKey),
      signingKey: root.secretKey,
      payload: {
        'rootSigningKeyBase64': base64Encode(root.publicKey),
        'rootEncryptionKeyBase64': base64Encode(box.publicKey),
        'deviceSigningKeyBase64': base64Encode(device.publicKey),
        'deviceEncryptionKeyBase64': base64Encode(box.publicKey),
        'keyringCiphertextBase64': base64Encode(Uint8List(48)),
      },
    );
    await store.append(profile.accountId, genesis.entry);
    await store.pinComparedIdentity(
      genesis.result,
      genesis.result.rootFingerprint,
    );
    await store.remember(genesis.result, 'verified');
    final account = AccountCryptoV2Workflow(
      _Directory(
        reducer: reducer,
        session: DeviceSession(profile, 'synthetic'),
        transport: transport,
        store: store,
        isCurrent: () => true,
        current: genesis.result,
      ),
    );
    access = SessionCryptoAccess(account: account);
    coordinator = CryptoAccessCoordinator(
      CryptoBusinessSession(account, access, db),
    );
    scope = crypto.randomId();
    request = crypto.randomId();
    Map<String, dynamic> sign(
      String operation,
      String id,
      Map<String, dynamic> payload,
    ) => crypto.signDomain(
      {
        'version': 2,
        'operation': operation,
        'requestId': id,
        'serverId': profile.serverId,
        'accountId': profile.accountId,
        'deviceId': profile.deviceId,
        'signer': 'device',
        'payload': payload,
      },
      device.secretKey,
      cryptoDirectoryDomain,
    );
    final proof = sign('crypto2.access.prepare', crypto.randomId(), {
      'scopeId': scope,
      'authorDirectoryHeadHash': genesis.result.headHash,
    });
    intent = await cryptoSha256(CryptoJson.encode(proof));
    prepared = {
      'authorization': proof,
      'intentHash': intent,
      'affectedCount': 2,
      'affectedHash': 'a' * 64,
    };
    finalProof = sign('crypto2.access.activate', request, {
      'intentHash': intent,
      'affectedCount': 2,
      'affectedHash': 'a' * 64,
    });
    response = {'intentHash': intent, 'state': 'applied'};
    await db.execute(
      'INSERT INTO crypto_membership_action_keys VALUES(?,?,?,?)',
      [partition, scope, 'access:$intent:activate', request],
    );
    await save();
  });
  tearDown(() async {
    await db.close();
    for (final key in [root, device, box]) {
      key.secretKey.dispose();
    }
  });

  // The real immutable manager receipt replay performs no new activation.
  // Lower-level currentHead memo/fetch invalidation already has its own fixture;
  // this regression exercises the previously missing coordinator boundary.
  test(
    'verified applied receipt retires enclosing authority lease and cannot revive it',
    () async {
      await access.withVerifiedOperation(() async {
        final sourceLease = Zone.current;
        await access.withVerifiedOperation(
          () async => expect(Zone.current, same(sourceLease)),
        );
        final result = await coordinator.reconcile(scope, prepared);
        expect(result?['state'], 'applied');
        await access.withVerifiedOperation(
          () async => expect(Zone.current, isNot(same(sourceLease))),
        );
        // Returning from the fresh nested lease must not revive the old source.
        await access.withVerifiedOperation(
          () async => expect(Zone.current, isNot(same(sourceLease))),
        );
      });
      expect(transport.calls, 0);
      final rows = await db.rows(
        'SELECT authorization FROM crypto_membership_intents WHERE partition=? AND scope_id=? AND intent_id=?',
        [partition, scope, request],
      );
      expect(rows.single['authorization'], CryptoJson.encode(finalProof));
    },
  );

  test('verified cancellation does not claim new active heads', () async {
    final command = Map<String, dynamic>.from(
      CryptoJson.decode(cryptoBase64(finalProof['commandBase64'])) as Map,
    )..['operation'] = 'crypto2.access.cancel';
    finalProof = crypto.signDomain(
      command,
      device.secretKey,
      cryptoDirectoryDomain,
    );
    response = {'intentHash': intent, 'state': 'cancelled'};
    await db.execute(
      'UPDATE crypto_membership_action_keys SET action_key=? WHERE partition=? AND scope_id=? AND request_id=?',
      ['access:$intent:cancel', partition, scope, request],
    );
    await save();
    await access.withVerifiedOperation(() async {
      final sourceLease = Zone.current;
      final result = await coordinator.finish(
        scopeId: scope,
        prepared: prepared,
        cancel: true,
      );
      expect(result['state'], 'cancelled');
      await access.withVerifiedOperation(
        () async => expect(Zone.current, same(sourceLease)),
      );
    });
    expect(transport.calls, 0);
  });

  for (final invalid in ['signature', 'intent', 'state']) {
    test(
      'invalid $invalid receipt rejects without claiming an applied boundary',
      () async {
        if (invalid == 'signature') {
          finalProof = {
            ...finalProof,
            'signatureBase64': base64Encode(Uint8List(64)),
          };
        } else if (invalid == 'intent') {
          response = {...response, 'intentHash': 'b' * 64};
        } else {
          response = {...response, 'state': 'pending'};
        }
        await save();
        await access.withVerifiedOperation(() async {
          final sourceLease = Zone.current;
          await expectLater(
            coordinator.reconcile(scope, prepared),
            throwsA(isA<FormatException>()),
          );
          await access.withVerifiedOperation(
            () async => expect(Zone.current, same(sourceLease)),
          );
        });
        expect(transport.calls, 0);
      },
    );
  }
}
