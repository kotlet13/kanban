import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_v2.dart';
import 'package:kanban/organizer/data/e2ee/crypto_codec.dart';
import 'package:kanban/organizer/data/e2ee/crypto_json.dart';
import 'package:kanban/organizer/data/e2ee/recovery_file_codec.dart';
import 'package:sodium/sodium.dart';

void main() {
  late CryptoCodec crypto;
  late AccountDirectoryV2 reducer;
  late KeyPair root, box, device, deviceBox;
  late String server, account, deviceId, epoch, pin;
  setUpAll(() async {
    crypto = CryptoCodec(await SodiumInit.init());
  });
  setUp(() {
    reducer = AccountDirectoryV2(crypto);
    root = crypto.sodium.crypto.sign.keyPair();
    box = crypto.sodium.crypto.box.keyPair();
    device = crypto.sodium.crypto.sign.keyPair();
    deviceBox = crypto.sodium.crypto.box.keyPair();
    server = crypto.randomId();
    account = crypto.randomId();
    deviceId = crypto.randomId();
    epoch = crypto.randomId();
    pin = crypto.fingerprint(root.publicKey, box.publicKey);
  });
  tearDown(() {
    for (final key in [root, box, device, deviceBox]) {
      key.secretKey.dispose();
    }
  });
  Future<PreparedDirectoryMutation> initialize() => reducer.prepare(
    previous: null,
    serverId: server,
    accountId: account,
    deviceId: deviceId,
    identityEpochId: epoch,
    operation: 'crypto2.account.initialize',
    signer: 'root',
    pinnedRootFingerprint: pin,
    signingKey: root.secretKey,
    payload: {
      'rootSigningKeyBase64': base64Encode(root.publicKey),
      'rootEncryptionKeyBase64': base64Encode(box.publicKey),
      'deviceSigningKeyBase64': base64Encode(device.publicKey),
      'deviceEncryptionKeyBase64': base64Encode(deviceBox.publicKey),
      'keyringCiphertextBase64': base64Encode(Uint8List(48)),
    },
  );
  Future<PreparedDirectoryMutation> mutate(
    VerifiedAccountDirectory previous,
    String operation,
    Map<String, dynamic> payload, {
    String? actor,
    SecureKey? key,
    String signer = 'device',
  }) => reducer.prepare(
    previous: previous,
    serverId: server,
    accountId: account,
    deviceId: actor ?? deviceId,
    identityEpochId: epoch,
    operation: operation,
    signer: signer,
    payload: payload,
    pinnedRootFingerprint: pin,
    signingKey: key ?? device.secretKey,
  );
  test(
    'project relocation companion is exact and snapshot preserving',
    () async {
      final genesis = await initialize();
      final action = crypto.randomId();
      final companion = await mutate(
        genesis.result,
        'crypto2.account.projectRelocation',
        {'actionId': action, 'publicationRoot': '7' * 64},
      );
      expect(companion.result.snapshotHash, genesis.result.snapshotHash);
      expect(
        companion.result.deviceSnapshotHash,
        genesis.result.deviceSnapshotHash,
      );
      expect(
        companion.result
            .verifiedHeadersFor('crypto2.account.projectRelocation')
            .single
            .generation,
        companion.result.generation,
      );
      await expectLater(
        mutate(genesis.result, 'crypto2.account.projectRelocation', {
          'actionId': action,
          'publicationRoot': '7' * 64,
          'scopeId': crypto.randomId(),
        }),
        throwsA(isA<CryptoDirectoryException>()),
      );
      await expectLater(
        mutate(
          genesis.result,
          'crypto2.account.projectRelocation',
          {'actionId': action, 'publicationRoot': '7' * 64},
          signer: 'root',
          key: root.secretKey,
        ),
        throwsA(isA<CryptoDirectoryException>()),
      );
    },
  );

  test(
    'scheduling consent companion is snapshot preserving and needs only approved device authority',
    () async {
      final genesis = await initialize();
      final actor = crypto.sodium.crypto.sign.keyPair(),
          actorBox = crypto.sodium.crypto.box.keyPair();
      final id = crypto.randomId();
      try {
        final admitted = await mutate(genesis.result, 'crypto2.device.add', {
          'deviceId': id,
          'signingKeyBase64': base64Encode(actor.publicKey),
          'encryptionKeyBase64': base64Encode(actorBox.publicKey),
          'keyringWrite': false,
          'manageDevices': false,
        });
        final payload = {
          'useToken': '1' * 64,
          'useProofHash': '2' * 64,
          'active': true,
        };
        final event = await mutate(
          admitted.result,
          'crypto2.account.scheduleUse',
          payload,
          actor: id,
          key: actor.secretKey,
        );
        expect(event.result.snapshotHash, admitted.result.snapshotHash);
        expect(
          event.result.deviceSnapshotHash,
          admitted.result.deviceSnapshotHash,
        );
        expect(event.result.generation, admitted.result.generation + 1);
        await expectLater(
          mutate(
            admitted.result,
            'crypto2.account.scheduleUse',
            payload,
            signer: 'root',
            key: root.secretKey,
          ),
          throwsA(isA<CryptoDirectoryException>()),
        );
        await expectLater(
          mutate(
            admitted.result,
            'crypto2.account.scheduleUse',
            {...payload, 'active': 'true'},
            actor: id,
            key: actor.secretKey,
          ),
          throwsA(isA<CryptoDirectoryException>()),
        );
      } finally {
        actor.secretKey.dispose();
        actorBox.secretKey.dispose();
      }
    },
  );
  test(
    'migration attestation is an immutable snapshot-preserving device log event',
    () async {
      final first = await initialize();
      final payload = {
        'migrationId': crypto.randomId(),
        'scopeToken': '1' * 64,
        'domain': 'finance',
        'attestationHash': '2' * 64,
      };
      final event = await mutate(
        first.result,
        'crypto2.account.migrationAttest',
        payload,
      );
      expect(event.result.snapshotHash, first.result.snapshotHash);
      expect(event.result.deviceSnapshotHash, first.result.deviceSnapshotHash);
      expect(event.result.generation, first.result.generation + 1);
      await expectLater(
        mutate(first.result, 'crypto2.account.migrationAttest', {
          ...payload,
          'domain': 'unknown',
        }),
        throwsA(anything),
      );
      await expectLater(
        mutate(
          first.result,
          'crypto2.account.migrationAttest',
          payload,
          key: root.secretKey,
          signer: 'root',
        ),
        throwsA(anything),
      );
    },
  );
  test(
    'rebind binds new session and key possession while retiring old authority',
    () async {
      final genesis = await initialize(),
          next = crypto.sodium.crypto.sign.keyPair(),
          nextBox = crypto.sodium.crypto.box.keyPair(),
          wrong = crypto.sodium.crypto.sign.keyPair(),
          nextId = crypto.randomId();
      try {
        Future<PreparedDirectoryMutation> rebind({
          SecureKey? possession,
          String? id,
          VerifiedAccountDirectory? previous,
        }) => reducer.prepare(
          previous: previous ?? genesis.result,
          serverId: server,
          accountId: account,
          deviceId: id ?? nextId,
          identityEpochId: epoch,
          operation: 'crypto2.device.rebind',
          signer: 'device',
          payload: {
            'approvingDeviceId': deviceId,
            'signingKeyBase64': base64Encode(next.publicKey),
            'encryptionKeyBase64': base64Encode(nextBox.publicKey),
            'keyringWrite': true,
            'manageDevices': true,
            'retireApprovingDevice': true,
          },
          pinnedRootFingerprint: pin,
          signingKey: device.secretKey,
          newDeviceSigningKey: possession ?? next.secretKey,
        );
        await expectLater(
          rebind(possession: wrong.secretKey),
          throwsA(isA<FormatException>()),
        );
        final transition = await rebind();
        transition.result.activeDevice(nextId);
        expect(
          () => transition.result.activeDevice(deviceId),
          throwsA(isA<CryptoDirectoryException>()),
        );
        await expectLater(
          rebind(id: crypto.randomId(), previous: transition.result),
          throwsA(isA<CryptoDirectoryException>()),
        );
        final raw =
            CryptoJson.decode(
                  cryptoBase64(transition.authorization['commandBase64']),
                )
                as Map<String, dynamic>;
        final originalProof = Map<String, dynamic>.from(
          raw['payload']['newDeviceProof'] as Map,
        );
        for (final field in [
          'newDeviceId',
          'accountId',
          'serverId',
          'requestId',
        ]) {
          final body = {...reducer.rebindBody(raw), field: crypto.randomId()};
          final forged = crypto.signDomain(
            body,
            next.secretKey,
            'JivieE2EE/deviceRebind/v2\n',
          );
          raw['payload']['newDeviceProof'] = forged;
          final signed = crypto.signDomain(
            raw,
            device.secretKey,
            cryptoDirectoryDomain,
          );
          await expectLater(
            reducer.apply(
              previous: genesis.result,
              entry: {...transition.entry, 'authorization': signed},
              serverId: server,
              accountId: account,
              pinnedRootFingerprint: pin,
            ),
            throwsA(isA<CryptoDirectoryException>()),
          );
        }
        raw['payload']['newDeviceProof'] = originalProof;
      } finally {
        next.secretKey.dispose();
        nextBox.secretKey.dispose();
        wrong.secretKey.dispose();
      }
    },
  );
  test(
    'contiguous exact signed chain rejects omissions, forks, root swap and device escalation',
    () async {
      final genesis = await initialize();
      expect(genesis.result.generation, 1);
      expect(
        () => genesis.result.snapshot['devices'] = [],
        throwsUnsupportedError,
      );
      final manager = crypto.sodium.crypto.sign.keyPair();
      final managerId = crypto.randomId();
      try {
        final added = await mutate(genesis.result, 'crypto2.device.add', {
          'deviceId': managerId,
          'signingKeyBase64': base64Encode(manager.publicKey),
          'encryptionKeyBase64': base64Encode(deviceBox.publicKey),
          'keyringWrite': false,
          'manageDevices': true,
        });
        final revoked = await mutate(added.result, 'crypto2.device.revoke', {
          'deviceId': managerId,
        });
        expect(revoked.result.devices.length, 2);
        expect(
          () => revoked.result.activeDevice(managerId),
          throwsA(isA<CryptoDirectoryException>()),
        );
        await expectLater(
          reducer.apply(
            previous: genesis.result,
            entry: revoked.entry,
            serverId: server,
            accountId: account,
            pinnedRootFingerprint: pin,
          ),
          throwsA(isA<CryptoDirectoryException>()),
        );
        await expectLater(
          mutate(
            added.result,
            'crypto2.device.add',
            {
              'deviceId': crypto.randomId(),
              'signingKeyBase64': base64Encode(device.publicKey),
              'encryptionKeyBase64': base64Encode(deviceBox.publicKey),
              'keyringWrite': true,
              'manageDevices': true,
            },
            actor: managerId,
            key: manager.secretKey,
          ),
          throwsA(isA<CryptoDirectoryException>()),
        );
        await expectLater(
          mutate(
            added.result,
            'crypto2.account.recoveryStart',
            {},
            actor: managerId,
            key: manager.secretKey,
          ),
          throwsA(isA<CryptoDirectoryException>()),
        );
        await expectLater(
          mutate(
            revoked.result,
            'crypto2.device.add',
            {
              'deviceId': crypto.randomId(),
              'signingKeyBase64': base64Encode(device.publicKey),
              'encryptionKeyBase64': base64Encode(deviceBox.publicKey),
              'keyringWrite': false,
              'manageDevices': false,
            },
            actor: managerId,
            key: manager.secretKey,
          ),
          throwsA(isA<CryptoDirectoryException>()),
        );
        await expectLater(
          reducer.apply(
            previous: null,
            entry: genesis.entry,
            serverId: server,
            accountId: account,
            pinnedRootFingerprint: 'swapped',
          ),
          throwsA(isA<CryptoDirectoryException>()),
        );
        await expectLater(
          reducer.apply(
            previous: genesis.result,
            entry: {...added.entry, 'headHash': '0' * 64},
            serverId: server,
            accountId: account,
            pinnedRootFingerprint: pin,
          ),
          throwsA(isA<CryptoDirectoryException>()),
        );
      } finally {
        manager.secretKey.dispose();
      }
    },
  );
  test(
    'keyring append requires current recovery and leaves device snapshot stable',
    () async {
      final genesis = await initialize();
      final keyId = crypto.randomId();
      Map<String, dynamic> entry(String recipient, String public) => {
        'id': keyId,
        'recipientId': recipient,
        'recipientKind': recipient == epoch ? 'recovery' : 'device',
        'recipientPublicKeyBase64': public,
        'sealedEnvelopeBase64': base64Encode(Uint8List(48)),
      };
      final own = entry(deviceId, base64Encode(deviceBox.publicKey));
      await expectLater(
        mutate(genesis.result, 'crypto2.account.keyringEntriesPut', {
          'entries': [own],
        }),
        throwsA(isA<CryptoDirectoryException>()),
      );
      final appended = await mutate(
        genesis.result,
        'crypto2.account.keyringEntriesPut',
        {
          'entries': [own, entry(epoch, base64Encode(box.publicKey))],
        },
      );
      expect(
        appended.result.deviceSnapshotHash,
        genesis.result.deviceSnapshotHash,
      );
      expect(appended.result.snapshotHash, isNot(genesis.result.snapshotHash));
      await expectLater(
        mutate(appended.result, 'crypto2.account.keyringEntriesPut', {
          'entries': [
            {
              ...own,
              'sealedEnvelopeBase64': base64Encode(
                Uint8List.fromList(List.filled(48, 1)),
              ),
            },
          ],
        }),
        throwsA(isA<CryptoDirectoryException>()),
      );
    },
  );
  test(
    'more than128 historical devices remain recoverable and old signing key loses authority',
    () async {
      var state = (await initialize()).result;
      for (var i = 0; i < 130; i++) {
        state = (await mutate(
          state,
          'crypto2.account.recoverEpoch',
          {
            'newIdentityEpochId': crypto.randomId(),
            'newDeviceSigningKeyBase64': base64Encode(device.publicKey),
            'newDeviceEncryptionKeyBase64': base64Encode(deviceBox.publicKey),
          },
          actor: crypto.randomId(),
          key: root.secretKey,
          signer: 'root',
        )).result;
      }
      expect(state.devices.length, 131);
      expect(
        state.devices.where((d) => d['revokedGeneration'] == null).length,
        1,
      );
      await expectLater(
        mutate(state, 'crypto2.account.keyringEntriesPut', {'entries': []}),
        throwsA(isA<CryptoDirectoryException>()),
      );
    },
  );
  test(
    'new verified root retains encryption history without old signing authority',
    () async {
      final files = RecoveryFileCodec(crypto);
      final original = files.create(serverId: server, accountId: account);
      final old = files.open(
        file: original.file,
        encryptedRoot: original.encryptedRoot,
        serverId: server,
        accountId: account,
        expectedFingerprint: original.fingerprint,
      );
      final replacement = files.replacement(
        serverId: server,
        accountId: account,
        previous: old,
      );
      final next = files.open(
        file: replacement.file,
        encryptedRoot: replacement.encryptedRoot,
        serverId: server,
        accountId: account,
        expectedFingerprint: replacement.fingerprint,
      );
      final dek = crypto.sodium.secureRandom(32);
      try {
        expect(next.historicalEncryption.length, 1);
        expect(next.signing.publicKey, isNot(old.signing.publicKey));
        final oldWrapper = crypto.sealKey(
          key: dek,
          recipientPublicKey: old.encryption.publicKey,
          context: {'recipientKind': 'recovery', 'recoveryRootEpochId': epoch},
        );
        final opened = crypto.openKey(
          sealed: oldWrapper,
          recipient: next.historicalEncryption.single,
          context: {'recipientKind': 'recovery', 'recoveryRootEpochId': epoch},
        );
        opened.dispose();
        final newEpoch = crypto.randomId(), newDevice = crypto.randomId();
        var state = (await reducer.prepare(
          previous: null,
          serverId: server,
          accountId: account,
          deviceId: deviceId,
          identityEpochId: epoch,
          operation: 'crypto2.account.initialize',
          signer: 'root',
          pinnedRootFingerprint: original.fingerprint,
          signingKey: old.signing.secretKey,
          payload: {
            'rootSigningKeyBase64': base64Encode(old.signing.publicKey),
            'rootEncryptionKeyBase64': base64Encode(old.encryption.publicKey),
            'deviceSigningKeyBase64': base64Encode(device.publicKey),
            'deviceEncryptionKeyBase64': base64Encode(deviceBox.publicKey),
            'keyringCiphertextBase64': base64Encode(
              CryptoJson.encode(original.encryptedRoot),
            ),
          },
        )).result;
        final keyId = crypto.randomId();
        state = (await reducer.prepare(
          previous: state,
          serverId: server,
          accountId: account,
          deviceId: deviceId,
          identityEpochId: epoch,
          operation: 'crypto2.account.keyringEntriesPut',
          signer: 'device',
          pinnedRootFingerprint: original.fingerprint,
          signingKey: device.secretKey,
          payload: {
            'entries': [
              {
                'id': keyId,
                'recipientKind': 'recovery',
                'recipientId': epoch,
                'recipientPublicKeyBase64': base64Encode(
                  old.encryption.publicKey,
                ),
                'sealedEnvelopeBase64': oldWrapper,
              },
            ],
          },
        )).result;
        final rotation = await reducer.prepare(
          previous: state,
          serverId: server,
          accountId: account,
          deviceId: newDevice,
          identityEpochId: epoch,
          operation: 'crypto2.account.rotateRoot',
          signer: 'root',
          pinnedRootFingerprint: original.fingerprint,
          signingKey: old.signing.secretKey,
          incomingRootSigningKey: next.signing.secretKey,
          payload: {
            'transitionId': crypto.randomId(),
            'newRootSigningKeyBase64': base64Encode(next.signing.publicKey),
            'newRootEncryptionKeyBase64': base64Encode(
              next.encryption.publicKey,
            ),
            'newIdentityEpochId': newEpoch,
            'newDeviceSigningKeyBase64': base64Encode(device.publicKey),
            'newDeviceEncryptionKeyBase64': base64Encode(deviceBox.publicKey),
            'keyringCiphertextBase64': base64Encode(
              CryptoJson.encode(replacement.encryptedRoot),
            ),
          },
        );
        final futureWrapper = crypto.sealKey(
          key: dek,
          recipientPublicKey: next.encryption.publicKey,
          context: {
            'recipientKind': 'recovery',
            'recoveryRootEpochId': newEpoch,
          },
        );
        expect(
          () => crypto.openKey(
            sealed: futureWrapper,
            recipient: old.encryption,
            context: {
              'recipientKind': 'recovery',
              'recoveryRootEpochId': newEpoch,
            },
          ),
          throwsFormatException,
        );
        expect(
          () => files.open(
            file: original.file,
            encryptedRoot: replacement.encryptedRoot,
            serverId: server,
            accountId: account,
            expectedFingerprint: original.fingerprint,
          ),
          throwsFormatException,
        );
        final rewrapped = await reducer.prepare(
          previous: rotation.result,
          serverId: server,
          accountId: account,
          deviceId: newDevice,
          identityEpochId: newEpoch,
          operation: 'crypto2.account.keyringEntriesPut',
          signer: 'device',
          pinnedRootFingerprint: original.fingerprint,
          signingKey: device.secretKey,
          payload: {
            'entries': [
              {
                'id': keyId,
                'recipientKind': 'recovery',
                'recipientId': newEpoch,
                'recipientPublicKeyBase64': base64Encode(
                  next.encryption.publicKey,
                ),
                'sealedEnvelopeBase64': futureWrapper,
              },
            ],
          },
        );
        expect(rewrapped.result.keyringEntries.length, 2);
        expect(
          rewrapped.result.keyringEntries.firstWhere(
            (e) => e['recipientId'] == epoch,
          )['envelopeHash'],
          state.keyringEntries.single['envelopeHash'],
        );
      } finally {
        old.dispose();
        next.dispose();
        original.dispose();
        replacement.dispose();
        dek.dispose();
      }
    },
  );
  test(
    'derived canonical state may exceed wire limit without weakening command parser',
    () {
      final large = {
        'entries': List.generate(2500, (i) => {'id': i, 'proof': 'x' * 256}),
      };
      expect(() => CryptoJson.encode(large), throwsFormatException);
      final encoded = CryptoJson.encodeDerivedState(large);
      expect(encoded.length, greaterThan(CryptoJson.maxBytes));
      expect(() => CryptoJson.decode(encoded), throwsFormatException);
      expect(CryptoJson.decode(encoded, limit: encoded.length), large);
    },
  );
}
