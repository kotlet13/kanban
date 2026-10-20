import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_transport.dart';
import 'package:kanban/organizer/data/device_session_store.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_store.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_repository.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_v2.dart';
import 'package:kanban/organizer/data/e2ee/crypto_authority_snapshot.dart';
import 'package:kanban/organizer/data/e2ee/crypto_codec.dart';
import 'package:kanban/organizer/data/e2ee/crypto_identity_store.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:sodium/sodium.dart';

class _Secure implements AccountCryptoStore {
  final values = <String, String>{};
  Future<void> Function()? onRead;
  @override
  Future<String?> read(String key) async {
    await onRead?.call();
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

class _Transport implements CollaborationTransport {
  _Transport(this.profile);
  final AccountSession profile;
  final snapshots = <Map<String, Object?>>[];
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
        'serverId': profile.serverId,
        'cryptoAuthoritySnapshotVersions': [1],
      };
    }
    if (operation == 'crypto2.authority.snapshot') {
      snapshots.add(jsonDecode(jsonEncode(params)) as Map<String, dynamic>);
      return {
        'version': 1,
        'serverId': profile.serverId,
        'accountId': profile.accountId,
        'deviceId': profile.deviceId,
        'entries': [
          {
            'operation': 'crypto2.account.status',
            'params': <String, dynamic>{},
            'result': {'original': true},
          },
        ],
      };
    }
    return {'direct': operation};
  }

  @override
  void close() {}
}

void main() {
  late CryptoCodec crypto;
  late CollaborationDatabase db;
  late _Secure secure;
  late CryptoIdentityStore store;
  late AccountDirectoryRepository directory;
  late _Transport transport;
  late AccountSession profile;
  late String anchorKey;
  late String originalAnchor;
  late List<KeyPair> keys;
  var current = true;
  setUpAll(() async => crypto = CryptoCodec(await SodiumInit.init()));
  setUp(() async {
    db = CollaborationDatabase(NativeDatabase.memory());
    secure = _Secure();
    current = true;
    keys = [
      crypto.sodium.crypto.sign.keyPair(),
      crypto.sodium.crypto.sign.keyPair(),
      crypto.sodium.crypto.box.keyPair(),
    ];
    final root = keys[0], device = keys[1], box = keys[2];
    profile = AccountSession(
      serverUrl: 'https://synthetic.invalid',
      serverId: crypto.randomId(),
      accountId: crypto.randomId(),
      deviceId: crypto.randomId(),
      userId: 1,
      username: 'synthetic',
      displayName: 'Synthetic',
      expiresAt: DateTime.utc(2030),
    );
    transport = _Transport(profile);
    store = CryptoIdentityStore(db, secure, profile.partition);
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
    directory = AccountDirectoryRepository(
      reducer: reducer,
      session: DeviceSession(profile, 'synthetic-token'),
      transport: transport,
      store: store,
      isCurrent: () => current,
    );
    anchorKey = 'directory2:${profile.partition}:${profile.accountId}';
    originalAnchor = secure.values[anchorKey]!;
  });
  tearDown(() async {
    await db.close();
    for (final key in keys) {
      key.secretKey.dispose();
    }
  });

  Future<void> snapshot() => directory.withAuthoritySnapshot(
    () async {
      expect(await directory.call('crypto2.account.status'), {
        'original': true,
      });
    },
    isValid: () async => current,
    onMutation: () {},
  );

  test(
    'warm own prefix hints exactly one account without lifecycle cursor',
    () async {
      final verified = await directory.cachedVerifiedDirectory();
      await snapshot();
      expect(transport.snapshots.single['directoryAfterGenerations'], {
        profile.accountId: verified.generation,
      });
      expect(
        transport.snapshots.single.containsKey('lifecycleAfterRevisions'),
        false,
      );
      expect(secure.values[anchorKey], originalAnchor);
    },
  );

  test('cold repository omits hints despite persisted secure anchor', () async {
    await snapshot();
    expect(
      transport.snapshots.single.containsKey('directoryAfterGenerations'),
      false,
    );
  });

  for (final field in [
    'serverId',
    'accountId',
    'generation',
    'headHash',
    'snapshotHash',
    'fingerprint',
    'trustState',
  ]) {
    test('changed secure $field omits already reconstructed hint', () async {
      await directory.cachedVerifiedDirectory();
      final anchor = jsonDecode(originalAnchor) as Map<String, dynamic>;
      anchor[field] = field == 'generation' ? 999999 : 'changed';
      secure.values[anchorKey] = jsonEncode(anchor);
      await snapshot();
      expect(
        transport.snapshots.single.containsKey('directoryAfterGenerations'),
        false,
      );
      expect(secure.values[anchorKey], jsonEncode(anchor));
    });
  }

  test('pin change while async hint lookup is pending omits hint', () async {
    await directory.cachedVerifiedDirectory();
    final started = Completer<void>(), resume = Completer<void>();
    secure.onRead = () async {
      secure.onRead = null;
      started.complete();
      await resume.future;
    };
    final pending = snapshot();
    await started.future;
    final anchor = jsonDecode(originalAnchor) as Map<String, dynamic>;
    anchor['headHash'] = 'f' * 64;
    secure.values[anchorKey] = jsonEncode(anchor);
    resume.complete();
    await pending;
    expect(
      transport.snapshots.single.containsKey('directoryAfterGenerations'),
      false,
    );
  });

  test(
    'later operation starts fresh transport and reads current anchor again',
    () async {
      await directory.cachedVerifiedDirectory();
      await snapshot();
      secure.values.remove(anchorKey);
      await snapshot();
      expect(transport.snapshots, hasLength(2));
      expect(
        transport.snapshots.first.containsKey('directoryAfterGenerations'),
        true,
      );
      expect(
        transport.snapshots.last.containsKey('directoryAfterGenerations'),
        false,
      );
    },
  );

  test(
    'expired operation during async hint lookup sends no snapshot',
    () async {
      final started = Completer<void>(), resume = Completer<void>();
      var valid = true;
      final operations = <String>[];
      final batch = CryptoAuthoritySnapshot(
        read: (operation, params) async {
          operations.add(operation);
          return operation == 'capabilities'
              ? {
                  'serverId': 'server',
                  'cryptoAuthoritySnapshotVersions': [1],
                }
              : {'direct': operation};
        },
        serverId: 'server',
        accountId: 'account',
        deviceId: 'device',
        isValid: () async => valid,
        onMutation: () {},
        directoryAfterGenerations: () async {
          started.complete();
          await resume.future;
          return {'account': 7};
        },
      );
      final pending = batch.call('crypto2.account.status', {});
      await started.future;
      valid = false;
      resume.complete();
      expect(await pending, {'direct': 'crypto2.account.status'});
      expect(operations, ['capabilities', 'crypto2.account.status']);
    },
  );
}
