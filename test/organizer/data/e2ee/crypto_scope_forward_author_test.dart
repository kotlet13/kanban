import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_store.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_v2.dart';
import 'package:kanban/organizer/data/e2ee/crypto_codec.dart';
import 'package:kanban/organizer/data/e2ee/crypto_identity_store.dart';
import 'package:kanban/organizer/data/e2ee/crypto_scope_anchor.dart';
import 'package:sodium/sodium.dart';

class _Secure implements AccountCryptoStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

void main() {
  late CryptoCodec crypto;
  late AccountDirectoryV2 reducer;
  late KeyPair root, box, oldDevice, newDevice, newBox;
  late String server, account, deviceId, epoch, fingerprint;
  late CollaborationDatabase db;
  late _Secure secure;
  late CryptoIdentityStore store;
  late VerifiedAccountDirectory old, recovered;
  late Map<String, dynamic> known;
  setUpAll(() async => crypto = CryptoCodec(await SodiumInit.init()));
  setUp(() async {
    reducer = AccountDirectoryV2(crypto);
    root = crypto.sodium.crypto.sign.keyPair();
    box = crypto.sodium.crypto.box.keyPair();
    oldDevice = crypto.sodium.crypto.sign.keyPair();
    newDevice = crypto.sodium.crypto.sign.keyPair();
    newBox = crypto.sodium.crypto.box.keyPair();
    server = crypto.randomId();
    account = crypto.randomId();
    deviceId = crypto.randomId();
    epoch = crypto.randomId();
    fingerprint = crypto.fingerprint(root.publicKey, box.publicKey);
    old = (await reducer.prepare(
      previous: null,
      serverId: server,
      accountId: account,
      deviceId: crypto.randomId(),
      identityEpochId: epoch,
      operation: 'crypto2.account.initialize',
      signer: 'root',
      signingKey: root.secretKey,
      pinnedRootFingerprint: fingerprint,
      payload: {
        'rootSigningKeyBase64': base64Encode(root.publicKey),
        'rootEncryptionKeyBase64': base64Encode(box.publicKey),
        'deviceSigningKeyBase64': base64Encode(oldDevice.publicKey),
        'deviceEncryptionKeyBase64': base64Encode(box.publicKey),
        'keyringCiphertextBase64': base64Encode(Uint8List(48)),
      },
    )).result;
    recovered = (await reducer.prepare(
      previous: old,
      serverId: server,
      accountId: account,
      deviceId: deviceId,
      identityEpochId: old.identityEpochId,
      operation: 'crypto2.account.recoverEpoch',
      signer: 'root',
      signingKey: root.secretKey,
      pinnedRootFingerprint: fingerprint,
      payload: {
        'newIdentityEpochId': crypto.randomId(),
        'newDeviceSigningKeyBase64': base64Encode(newDevice.publicKey),
        'newDeviceEncryptionKeyBase64': base64Encode(newBox.publicKey),
      },
    )).result;
    recovered = (await reducer.prepare(
      previous: recovered,
      serverId: server,
      accountId: account,
      deviceId: deviceId,
      identityEpochId: recovered.identityEpochId,
      operation: 'crypto2.account.migrationAttest',
      signer: 'device',
      signingKey: newDevice.secretKey,
      pinnedRootFingerprint: fingerprint,
      payload: {
        'migrationId': crypto.randomId(),
        'scopeToken': '1' * 64,
        'domain': 'content',
        'attestationHash': '2' * 64,
      },
    )).result;
    db = CollaborationDatabase(NativeDatabase.memory());
    secure = _Secure();
    store = CryptoIdentityStore(db, secure, 'forward-author-test');
    await store.pinRoot(
      account,
      server,
      fingerprint,
      genesisFingerprint: fingerprint,
    );
    await store.remember(old, 'verified');
    known = (await store.anchor(account))!;
    await secure.write('scope', jsonEncode({'epoch': 1, 'headHash': 'known'}));
  });
  tearDown(() async {
    await db.close();
    for (final pair in [root, box, oldDevice, newDevice, newBox]) {
      pair.secretKey.dispose();
    }
  });

  // This is the same secure scope commit used by currentHead; an invalid
  // forward exception must leave its known scope floor and contact pin intact.
  Future<void> commit(
    VerifiedAccountDirectory reference,
    VerifiedAccountDirectory current, {
    bool isCurrent = true,
    Future<void> Function()? beforeCommit,
  }) async {
    final contactBefore = Map<String, String>.from(secure.values)
      ..remove('scope');
    final knownBefore = jsonEncode(known);
    final forward = cryptoScopeForwardDirectoryReference(
      known: known,
      referenced: reference,
      current: current,
    );
    await beforeCommit?.call();
    await commitCryptoScopeAnchor(
      partition: store.partition,
      key: 'scope',
      secure: secure,
      epoch: 2,
      headHash: 'successor',
      verifiedPrefix: {1: 'known', 2: 'successor'},
      isCurrent: () => isCurrent,
      validateCurrent: (_) async {
        if (!forward ||
            jsonEncode(await store.anchor(account)) != knownBefore) {
          throw StateError('history pending');
        }
      },
    );
    for (final entry in contactBefore.entries) {
      expect(secure.values[entry.key], entry.value);
    }
  }

  test(
    'signed same-root recovery advances scope without promoting contact',
    () async {
      expect(recovered.identityEpochId, isNot(old.identityEpochId));
      expect(recovered.deviceSnapshotHash, isNot(old.deviceSnapshotHash));
      await commit(recovered, recovered);
      expect(jsonDecode(secure.values['scope']!)['headHash'], 'successor');
      expect((await store.anchor(account))!['headHash'], old.headHash);
    },
  );

  test('a newer known pin cannot approve an older author reference', () async {
    await store.remember(recovered, 'verified');
    known = (await store.anchor(account))!;
    await expectLater(commit(old, recovered), throwsStateError);
    expect(jsonDecode(secure.values['scope']!), {
      'epoch': 1,
      'headHash': 'known',
    });
  });

  test(
    'forward reference cannot hide a newer current device revocation',
    () async {
      final revoked = (await reducer.prepare(
        previous: recovered,
        serverId: server,
        accountId: account,
        deviceId: crypto.randomId(),
        identityEpochId: recovered.identityEpochId,
        operation: 'crypto2.device.revoke',
        signer: 'root',
        signingKey: root.secretKey,
        pinnedRootFingerprint: fingerprint,
        payload: {'deviceId': deviceId},
      )).result;
      await expectLater(commit(recovered, revoked), throwsStateError);
      expect(jsonDecode(secure.values['scope']!), {
        'epoch': 1,
        'headHash': 'known',
      });
    },
  );

  test('signed alternate lineage cannot replace the exact known pin', () async {
    final fork = (await reducer.prepare(
      previous: old,
      serverId: server,
      accountId: account,
      deviceId: crypto.randomId(),
      identityEpochId: old.identityEpochId,
      operation: 'crypto2.account.recoveryStart',
      signer: 'root',
      signingKey: root.secretKey,
      pinnedRootFingerprint: fingerprint,
      payload: {},
    )).result;
    await store.remember(fork, 'verified');
    known = (await store.anchor(account))!;
    await expectLater(commit(recovered, recovered), throwsStateError);
    expect(jsonDecode(secure.values['scope']!), {
      'epoch': 1,
      'headHash': 'known',
    });
  });

  test(
    'valid root handoff cannot use the same-root forward exception',
    () async {
      final nextRoot = crypto.sodium.crypto.sign.keyPair();
      final nextBox = crypto.sodium.crypto.box.keyPair();
      try {
        final handoff = (await reducer.prepare(
          previous: recovered,
          serverId: server,
          accountId: account,
          deviceId: crypto.randomId(),
          identityEpochId: recovered.identityEpochId,
          operation: 'crypto2.account.rotateRoot',
          signer: 'root',
          signingKey: root.secretKey,
          incomingRootSigningKey: nextRoot.secretKey,
          pinnedRootFingerprint: fingerprint,
          payload: {
            'transitionId': crypto.randomId(),
            'newRootSigningKeyBase64': base64Encode(nextRoot.publicKey),
            'newRootEncryptionKeyBase64': base64Encode(nextBox.publicKey),
            'newIdentityEpochId': crypto.randomId(),
            'newDeviceSigningKeyBase64': base64Encode(newDevice.publicKey),
            'newDeviceEncryptionKeyBase64': base64Encode(newBox.publicKey),
            'keyringCiphertextBase64': base64Encode(Uint8List(48)),
          },
        )).result;
        await expectLater(commit(handoff, handoff), throwsStateError);
        expect(jsonDecode(secure.values['scope']!), {
          'epoch': 1,
          'headHash': 'known',
        });
      } finally {
        nextRoot.secretKey.dispose();
        nextBox.secretKey.dispose();
      }
    },
  );

  test(
    'pin advancement between forward preparation and scope commit rejects',
    () async {
      await expectLater(
        commit(
          recovered,
          recovered,
          beforeCommit: () => store.remember(recovered, 'verified'),
        ),
        throwsStateError,
      );
      expect(jsonDecode(secure.values['scope']!), {
        'epoch': 1,
        'headHash': 'known',
      });
      expect((await store.anchor(account))!['headHash'], recovered.headHash);
    },
  );

  test('unknown pin and expired session cannot advance scope', () async {
    known.remove('fingerprint');
    await expectLater(commit(recovered, recovered), throwsStateError);
    known = (await store.anchor(account))!;
    await expectLater(
      commit(recovered, recovered, isCurrent: false),
      throwsFormatException,
    );
    expect(jsonDecode(secure.values['scope']!), {
      'epoch': 1,
      'headHash': 'known',
    });
  });
}
