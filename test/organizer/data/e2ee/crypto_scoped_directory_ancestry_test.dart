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
import 'package:kanban/organizer/data/e2ee/crypto_identity_store.dart';
import 'package:kanban/organizer/data/e2ee/crypto_sync_repository.dart';
import 'package:kanban/organizer/data/e2ee/session_crypto_access.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';

class _Secure implements AccountCryptoStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

class _Prefix implements CollaborationTransport {
  final prefixes = <String, List<Map<String, dynamic>>>{};
  int calls = 0;
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
    if (operation != 'crypto2.directory.read') throw StateError(operation);
    calls++;
    final entries = prefixes[params['directoryHeadHash']]!;
    final after = params['afterGeneration'] as int;
    return {
      'entries': entries
          .where((e) => (e['generation'] as int) > after)
          .toList(),
      'hasMore': false,
    };
  }

  @override
  void close() {}
}

void main() {
  test(
    'scoped old prefix must intersect secure anchor; genuine ancestor remains read-only',
    () async {
      final crypto = CryptoCodec(await SodiumInit.init()),
          reducer = AccountDirectoryV2(CryptoCodec(await SodiumInit.init()));
      final root = crypto.sodium.crypto.sign.keyPair(),
          box = crypto.sodium.crypto.box.keyPair(),
          device = crypto.sodium.crypto.sign.keyPair(),
          deviceBox = crypto.sodium.crypto.box.keyPair();
      addTearDown(() {
        for (final pair in [root, box, device, deviceBox]) {
          pair.secretKey.dispose();
        }
      });
      final server = crypto.randomId(),
          accountId = crypto.randomId(),
          deviceId = crypto.randomId(),
          epoch = crypto.randomId(),
          scope = crypto.randomId();
      final pin = crypto.fingerprint(root.publicKey, box.publicKey);
      final first = await reducer.prepare(
        previous: null,
        serverId: server,
        accountId: accountId,
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
      Future<PreparedDirectoryMutation> event(
        VerifiedAccountDirectory previous,
        String hash,
      ) => reducer.prepare(
        previous: previous,
        serverId: server,
        accountId: accountId,
        deviceId: deviceId,
        identityEpochId: epoch,
        operation: 'crypto2.account.projectRelocation',
        signer: 'device',
        pinnedRootFingerprint: pin,
        signingKey: device.secretKey,
        payload: {'actionId': crypto.randomId(), 'publicationRoot': hash},
      );
      final genuine = await event(first.result, '1' * 64),
          fork = await event(first.result, '2' * 64),
          known = await event(genuine.result, '3' * 64),
          newer = await event(known.result, '4' * 64);
      final session = DeviceSession(
        AccountSession(
          serverUrl: 'https://synthetic.invalid/',
          serverId: server,
          accountId: accountId,
          userId: 1,
          username: 'synthetic',
          displayName: 'Synthetic',
          deviceId: deviceId,
          expiresAt: DateTime.utc(2030),
        ),
        'synthetic',
      );
      final db = CollaborationDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final secure = _Secure(),
          store = CryptoIdentityStore(db, secure, session.profile.partition),
          transport = _Prefix();
      await store.remember(known.result, 'verified');
      transport.prefixes[genuine.result.headHash] = [
        first.entry,
        genuine.entry,
      ];
      transport.prefixes[fork.result.headHash] = [first.entry, fork.entry];
      transport.prefixes[known.result.headHash] = [
        first.entry,
        genuine.entry,
        known.entry,
      ];
      transport.prefixes[newer.result.headHash] = [
        first.entry,
        genuine.entry,
        known.entry,
        newer.entry,
      ];
      final workflow = AccountCryptoV2Workflow(
        AccountDirectoryRepository(
          reducer: reducer,
          session: session,
          transport: transport,
          store: store,
          isCurrent: () => true,
        ),
      );
      final access = SessionCryptoAccess(account: workflow);
      await expectLater(
        access.directoryAt(
          scopeId: scope,
          scopeHeadHash: '0' * 64,
          accountId: accountId,
          directoryHeadHash: fork.result.headHash,
          online: true,
          allowUnverifiedContact: true,
        ),
        throwsA(anyOf(isA<FormatException>(), isA<CryptoDirectoryException>())),
      );
      final secureBefore = Map.of(secure.values);
      final result = await access.directoryAt(
        scopeId: scope,
        scopeHeadHash: '0' * 64,
        accountId: accountId,
        directoryHeadHash: genuine.result.headHash,
        online: true,
        allowUnverifiedContact: true,
      );
      expect(result.headHash, genuine.result.headHash);
      expect(secure.values, secureBefore);
      expect(await store.entries(accountId), isEmpty);
      await store.remember(newer.result, 'verified');
      await expectLater(
        access.directoryAt(
          scopeId: scope,
          scopeHeadHash: '0' * 64,
          accountId: accountId,
          directoryHeadHash: genuine.result.headHash,
          online: false,
          allowUnverifiedContact: true,
        ),
        throwsA(isA<CryptoAuthorityPending>()),
      );
    },
  );
}
