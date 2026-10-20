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

class _HeadReached implements Exception {}

class _ProofTransport implements CollaborationTransport {
  final prefixes = <String, List<Map<String, dynamic>>>{};
  int directoryReads = 0, headReads = 0;
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
    if (operation == 'crypto2.account.scopeObservations') {
      return {'observations': <Object>[], 'hasMore': false};
    }
    if (operation == 'crypto2.directory.read') {
      directoryReads++;
      return {
        'entries': prefixes[params['directoryHeadHash']]!
            .where(
              (e) =>
                  (e['generation'] as int) > (params['afterGeneration'] as int),
            )
            .toList(),
        'hasMore': false,
      };
    }
    if (operation == 'crypto2.scope.headGet') {
      headReads++;
      throw _HeadReached();
    }
    throw StateError(operation);
  }

  @override
  void close() {}
}

void main() {
  for (final mode in ['online', 'offline', 'bad_signature', 'fork']) {
    test('retained invitation cold creator prefix $mode', () async {
      final crypto = CryptoCodec(await SodiumInit.init()),
          reducer = AccountDirectoryV2(crypto);
      final pairs = <KeyPair>[];
      KeyPair pair() {
        final p = crypto.sodium.crypto.sign.keyPair();
        pairs.add(p);
        return p;
      }

      final root = pair(),
          device = pair(),
          ownRoot = pair(),
          ownDevice = pair();
      final box = crypto.sodium.crypto.box.keyPair(),
          ownBox = crypto.sodium.crypto.box.keyPair();
      addTearDown(() {
        for (final p in [...pairs, box, ownBox]) {
          p.secretKey.dispose();
        }
      });
      final server = crypto.randomId(),
          inviter = crypto.randomId(),
          recipient = crypto.randomId(),
          deviceId = crypto.randomId(),
          ownDeviceId = crypto.randomId(),
          epoch = crypto.randomId(),
          scope = crypto.randomId();
      Future<PreparedDirectoryMutation> init(
        String id,
        String dev,
        KeyPair r,
        KeyPair b,
        KeyPair d,
      ) => reducer.prepare(
        previous: null,
        serverId: server,
        accountId: id,
        deviceId: dev,
        identityEpochId: epoch,
        operation: 'crypto2.account.initialize',
        signer: 'root',
        pinnedRootFingerprint: crypto.fingerprint(r.publicKey, b.publicKey),
        signingKey: r.secretKey,
        payload: {
          'rootSigningKeyBase64': base64Encode(r.publicKey),
          'rootEncryptionKeyBase64': base64Encode(b.publicKey),
          'deviceSigningKeyBase64': base64Encode(d.publicKey),
          'deviceEncryptionKeyBase64': base64Encode(b.publicKey),
          'keyringCiphertextBase64': base64Encode(Uint8List(48)),
        },
      );
      final first = await init(inviter, deviceId, root, box, device),
          own = await init(recipient, ownDeviceId, ownRoot, ownBox, ownDevice);
      Future<PreparedDirectoryMutation> event(String hash) => reducer.prepare(
        previous: first.result,
        serverId: server,
        accountId: inviter,
        deviceId: deviceId,
        identityEpochId: epoch,
        operation: 'crypto2.account.projectRelocation',
        signer: 'device',
        pinnedRootFingerprint: crypto.fingerprint(
          root.publicKey,
          box.publicKey,
        ),
        signingKey: device.secretKey,
        payload: {'actionId': crypto.randomId(), 'publicationRoot': hash},
      );
      final known = await event('1' * 64), fork = await event('2' * 64);
      final historical = mode == 'fork' ? fork : first;
      final session = DeviceSession(
        AccountSession(
          serverUrl: 'https://synthetic.invalid/',
          serverId: server,
          accountId: recipient,
          userId: 1,
          username: 'synthetic',
          displayName: 'Synthetic',
          deviceId: ownDeviceId,
          expiresAt: DateTime.utc(2030),
        ),
        'synthetic',
      );
      final db = CollaborationDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final secure = _Secure(),
          store = CryptoIdentityStore(db, secure, session.profile.partition),
          transport = _ProofTransport();
      await store.pinRoot(recipient, server, own.result.rootFingerprint);
      await store.append(recipient, own.entry);
      await store.remember(own.result, 'verified');
      // The independent secure floor survives, while this foreign immutable
      // prefix is not in the recipient's global SQL log after a cold restore.
      await store.pinRoot(inviter, server, known.result.rootFingerprint);
      await store.remember(known.result, 'verified');
      final secureBefore = Map.of(secure.values);
      transport.prefixes[first.result.headHash] = [first.entry];
      transport.prefixes[known.result.headHash] = [first.entry, known.entry];
      transport.prefixes[fork.result.headHash] = [first.entry, fork.entry];
      final proof = crypto.signDomain(
        {
          'version': 2,
          'serverId': server,
          'accountId': inviter,
          'deviceId': deviceId,
          'operation': 'crypto2.invitations.create',
          'payload': {
            'scopeId': scope,
            'invitationId': crypto.randomId(),
            'membershipHeadHash': 'a' * 64,
            'authorDirectoryHeadHash': historical.result.headHash,
          },
        },
        device.secretKey,
        cryptoDirectoryDomain,
      );
      if (mode == 'bad_signature') {
        proof['signatureBase64'] = base64Encode(Uint8List(64));
      }
      final account = AccountCryptoV2Workflow(
        AccountDirectoryRepository(
          reducer: reducer,
          session: session,
          transport: transport,
          store: store,
          isCurrent: () => true,
        ),
      );
      final access = SessionCryptoAccess(
        account: account,
        invitationAnchor: proof,
      );
      final run = access.currentHead(scope, online: mode != 'offline');
      if (mode == 'online') {
        await expectLater(run, throwsA(isA<_HeadReached>()));
        expect(transport.directoryReads, 2);
        expect(transport.headReads, 1);
      } else if (mode == 'offline') {
        await expectLater(
          run,
          throwsA(
            isA<CryptoAuthorityPending>().having(
              (e) => e.reason,
              'reason',
              'directory_proof_pending',
            ),
          ),
        );
        expect(transport.directoryReads, 0);
        expect(transport.headReads, 0);
      } else {
        await expectLater(
          run,
          throwsA(
            anyOf(isA<FormatException>(), isA<CryptoDirectoryException>()),
          ),
        );
        expect(transport.headReads, 0);
      }
      expect(secure.values, secureBefore);
      expect(await store.entries(inviter), isEmpty);
    });
  }
}
