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
import 'package:kanban/organizer/data/e2ee/crypto_migration_invitation_codec.dart';
import 'package:kanban/organizer/data/e2ee/crypto_migration_own_attestation.dart';
import 'package:kanban/organizer/data/e2ee/session_crypto_access.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:sodium/sodium.dart';

class _Secure implements AccountCryptoStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

class _Transport implements CollaborationTransport {
  late Map<String, dynamic> response;
  Map<String, Object?>? requested;
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
    if (operation == 'crypto2.account.scopeObservations')
      return {
        'observations': <Object>[],
        'hasMore': false,
        'nextAfterGeneration': null,
      };
    expect(operation, 'crypto2.migration.ownAttestation');
    requested = params;
    return response;
  }

  @override
  void close() {}
}

void main() {
  late CryptoCodec crypto;
  setUpAll(() async {
    crypto = CryptoCodec(await SodiumInit.init());
  });
  test(
    'own closed control classifies only its exact included historical proof',
    () async {
      final db = CollaborationDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final root = crypto.sodium.crypto.sign.keyPair(),
          box = crypto.sodium.crypto.box.keyPair(),
          device = crypto.sodium.crypto.sign.keyPair(),
          deviceBox = crypto.sodium.crypto.box.keyPair();
      addTearDown(() {
        for (final key in [root, box, device, deviceBox]) {
          key.secretKey.dispose();
        }
      });
      final server = crypto.randomId(),
          accountId = crypto.randomId(),
          deviceId = crypto.randomId(),
          epoch = crypto.randomId(),
          migration = crypto.randomId(),
          capture = crypto.randomId();
      final transport = _Transport();
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
      final reducer = AccountDirectoryV2(crypto),
          store = CryptoIdentityStore(db, _Secure(), session.profile.partition);
      final workflow = AccountCryptoV2Workflow(
        AccountDirectoryRepository(
          reducer: reducer,
          session: session,
          transport: transport,
          store: store,
          isCurrent: () => true,
        ),
      );
      final pin = crypto.fingerprint(root.publicKey, box.publicKey);
      final genesis = await reducer.prepare(
        previous: null,
        serverId: server,
        accountId: accountId,
        deviceId: deviceId,
        identityEpochId: epoch,
        operation: 'crypto2.account.initialize',
        signer: 'root',
        payload: {
          'rootSigningKeyBase64': base64Encode(root.publicKey),
          'rootEncryptionKeyBase64': base64Encode(box.publicKey),
          'deviceSigningKeyBase64': base64Encode(device.publicKey),
          'deviceEncryptionKeyBase64': base64Encode(deviceBox.publicKey),
          'keyringCiphertextBase64': base64Encode(Uint8List(48)),
        },
        pinnedRootFingerprint: pin,
        signingKey: root.secretKey,
      );
      final header = <String, dynamic>{
        'version': 3,
        'serverId': server,
        'migrationId': migration,
        'captureId': capture,
        'accountId': accountId,
        'sourceInventoryRoot': '1' * 64,
        'archiveManifestHash': '2' * 64,
        'coldParityProofHash': '3' * 64,
        'authorDirectoryHeadHash': genesis.result.headHash,
        'bridgeCount': 0,
        'sourceCounts': {'invitation': 0, 'mail': 0},
        'bridgeRoot': '4' * 64,
      };
      Map<String, dynamic> sign(Map<String, dynamic> value) =>
          crypto.signDomain(value, device.secretKey, cryptoDirectoryDomain);
      final body = <String, dynamic>{
        'version': 2,
        'operation': 'crypto2.migration.invitations.certify',
        'serverId': server,
        'accountId': accountId,
        'deviceId': deviceId,
        'requestId': crypto.randomId(),
        'signer': 'device',
        'payload': {'header': header},
      };
      final proof = sign(body);
      final event = await reducer.prepare(
        previous: genesis.result,
        serverId: server,
        accountId: accountId,
        deviceId: deviceId,
        identityEpochId: epoch,
        operation: 'crypto2.account.migrationAttest',
        signer: 'device',
        payload: {
          'migrationId': migration,
          'domain': 'content',
          'scopeToken': await CryptoMigrationInvitationCodec.scopeToken(header),
          'attestationHash': await cryptoSha256(CryptoJson.encode(proof)),
        },
        pinnedRootFingerprint: pin,
        signingKey: device.secretKey,
      );
      await store.pinRoot(accountId, server, pin);
      await store.append(accountId, genesis.entry);
      await store.append(accountId, event.entry);
      await store.remember(event.result, 'verified');
      await db.execute(
        'UPDATE crypto_directory_event_index SET operation=? WHERE partition=? AND account_id=? AND generation=?',
        [
          'crypto2.account.protectionReady',
          store.partition,
          accountId,
          event.result.generation,
        ],
      );
      final exact = await store
          .verifiedOperationEntries(
            event.result,
            'crypto2.account.migrationAttest',
          )
          .toList();
      expect(exact.length, 1);
      expect(exact.single['headHash'], event.result.headHash);

      transport.response = {
        'eventAuthorization': event.authorization,
        'authorizations': [proof],
      };
      final classifier = CryptoMigrationOwnAttestation(workflow, event.result);
      final result = await classifier.classify(event.entry);
      expect(result.privateControl, isTrue);
      expect(result.privateArtifact, isFalse);
      expect(
        transport.requested!['eventCommandHash'],
        await cryptoSha256(cryptoBase64(event.authorization['commandBase64'])),
      );
      final wrong = sign({
        ...body,
        'payload': {
          'header': {...header, 'bridgeRoot': '5' * 64},
        },
      });
      transport.response = {
        'eventAuthorization': event.authorization,
        'authorizations': [wrong],
      };
      await expectLater(
        classifier.classify(event.entry),
        throwsA(isA<FormatException>()),
      );
      transport.response = {
        'eventAuthorization': event.authorization,
        'authorizations': [proof],
        'kind': 'private',
      };
      await expectLater(
        classifier.classify(event.entry),
        throwsA(isA<FormatException>()),
      );
      transport.response = {
        'eventAuthorization': event.authorization,
        'authorizations': [proof, proof],
      };
      await expectLater(
        classifier.classify(event.entry),
        throwsA(
          predicate(
            (e) => e.toString().contains('crypto_own_attestation_pending'),
          ),
        ),
      );
      final changedEntry = {...event.entry, 'headHash': 'f' * 64};
      await expectLater(
        classifier.classify(changedEntry),
        throwsA(isA<FormatException>()),
      );
      final scope = crypto.randomId();
      for (var i = 0; i < 2; i++) {
        await db.execute(
          'INSERT INTO crypto_membership_intents VALUES(?,?,?,?,?,?)',
          [
            store.partition,
            scope,
            crypto.randomId(),
            'invitationScopeAnchor',
            CryptoJson.encode({}),
            CryptoJson.encode(proof),
          ],
        );
      }
      await expectLater(
        SessionCryptoAccess(account: workflow).currentHead(scope),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            'invitation_scope_anchor_conflict',
          ),
        ),
      );
      await db.execute(
        'DELETE FROM crypto_directory_entries WHERE partition=? AND account_id=? AND generation=?',
        [store.partition, accountId, event.result.generation],
      );
      await expectLater(
        store
            .verifiedOperationEntries(
              event.result,
              'crypto2.account.migrationAttest',
            )
            .toList(),
        throwsA(
          isA<CryptoDirectoryException>().having(
            (e) => e.code,
            'code',
            'directory_operation_bytes_pending',
          ),
        ),
      );
    },
  );
}
