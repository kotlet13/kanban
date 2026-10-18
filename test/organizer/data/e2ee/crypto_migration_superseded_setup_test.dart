import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:sodium/sodium.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_v2.dart';
import 'package:kanban/organizer/data/e2ee/crypto_capture_keys.dart';
import 'package:kanban/organizer/data/e2ee/crypto_codec.dart';
import 'package:kanban/organizer/data/e2ee/crypto_json.dart';
import 'package:kanban/organizer/data/e2ee/crypto_migration_commitments_v3.dart';
import 'package:kanban/organizer/data/e2ee/crypto_migration_superseded_setup.dart';

void main() {
  test(
    'only anchored acknowledged A retires the exact old setup classification',
    () async {
      final crypto = CryptoCodec(await SodiumInit.init()),
          reducer = AccountDirectoryV2(CryptoCodec(await SodiumInit.init()));
      final root = crypto.sodium.crypto.sign.keyPair(),
          box = crypto.sodium.crypto.box.keyPair(),
          device = crypto.sodium.crypto.sign.keyPair(),
          deviceBox = crypto.sodium.crypto.box.keyPair();
      try {
        final server = crypto.randomId(),
            account = crypto.randomId(),
            deviceId = crypto.randomId(),
            identity = crypto.randomId(),
            scope = crypto.randomId(),
            oldMigration = crypto.randomId(),
            generation = crypto.randomId(),
            component = crypto.randomId();
        final capture = CryptoCaptureKeyDescriptor(
          captureId: crypto.randomId(),
          migrationId: crypto.randomId(),
          keyId: crypto.randomId(),
          rootScopeId: scope,
          componentId: component,
          scopeIds: [scope],
          receiptSelections: [
            {'scopeId': scope, 'domain': 'content'},
          ],
        );
        final genesis = await reducer.prepare(
          previous: null,
          serverId: server,
          accountId: account,
          deviceId: deviceId,
          identityEpochId: identity,
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
            'deviceSigningKeyBase64': base64Encode(device.publicKey),
            'deviceEncryptionKeyBase64': base64Encode(deviceBox.publicKey),
            'keyringCiphertextBase64': base64Encode(Uint8List(48)),
          },
        );
        Map<String, dynamic> signed(String operation, Map payload) =>
            crypto.signDomain(
              {
                'version': 2,
                'signer': 'device',
                'serverId': server,
                'accountId': account,
                'deviceId': deviceId,
                'requestId': crypto.randomId(),
                'operation': operation,
                'payload': payload,
              },
              device.secretKey,
              cryptoDirectoryDomain,
            );
        final oldBody = {
          'scopeId': scope,
          'epoch': 1,
          'previousHeadHash': cryptoZeroHash,
          'authorDirectoryHeadHash': genesis.result.headHash,
          'members': [],
        };
        final oldHash = await cryptoSha256([
              ...utf8.encode('JivieScopeHead/v2\n'),
              ...CryptoJson.encode(oldBody),
            ]),
            oldProposal = signed('crypto2.scope.headPut', oldBody);
        final context = {
          'version': 3,
          'serverId': server,
          'migrationId': oldMigration,
          'generationId': generation,
          'mode': 'supersede',
          'componentId': component,
          'newMigrationId': capture.migrationId,
          'published': [],
          'scopes': [
            {
              'scopeToken': await CryptoMigrationCommitmentsV3.scopeToken(
                serverId: server,
                migrationId: oldMigration,
                scopeId: scope,
                domain: 'content',
              ),
              'headHash': oldHash,
              'candidateHeadHash': '3' * 64,
              'candidateProposalHash': '4' * 64,
            },
          ],
        };
        final contextHash = await cryptoSha256([
          ...utf8.encode('JivieMigrationGenerationContext/v3\n'),
          ...CryptoJson.encode(context),
        ]);
        final approval = crypto.signDomain(
          {
            'version': 3,
            'serverId': server,
            'accountId': account,
            'deviceId': deviceId,
            'migrationId': oldMigration,
            'generationId': generation,
            'mode': 'supersede',
            'contextHash': contextHash,
            'authorDirectoryHeadHash': genesis.result.headHash,
            'deviceSnapshotHash': genesis.result.deviceSnapshotHash,
          },
          device.secretKey,
          'JivieMigrationGenerationApproval/v3\n',
        );
        final token = await cryptoSha256([
          ...utf8.encode('JivieMigrationGenerationToken/v3\n'),
          ...CryptoJson.encode({
            'version': 3,
            'serverId': server,
            'migrationId': oldMigration,
            'generationId': generation,
          }),
        ]);
        final event = await reducer.prepare(
          previous: genesis.result,
          serverId: server,
          accountId: account,
          deviceId: deviceId,
          identityEpochId: identity,
          operation: 'crypto2.account.migrationAttest',
          signer: 'device',
          pinnedRootFingerprint: genesis.result.rootFingerprint,
          signingKey: device.secretKey,
          payload: {
            'migrationId': oldMigration,
            'scopeToken': token,
            'domain': 'content',
            'attestationHash': await cryptoSha256(CryptoJson.encode(approval)),
          },
        );
        final finish = signed('crypto2.migration.generation.finish', {
          'generationId': generation,
          'contextHash': contextHash,
        });
        final fb = CryptoMigrationSupersededSetup.body(finish);
        final receipt = {
          'status': 200,
          'requestId': fb['requestId'],
          'requestHash': await cryptoSha256(
            cryptoBase64(finish['commandBase64']),
          ),
          'authorization': finish,
          'response': {
            'generationId': generation,
            'state': 'superseded',
            'migrationId': capture.migrationId,
          },
        };
        final prepare = signed('crypto2.migration.capture.prepare', {
          ...capture.toJson(),
          'authorDirectoryHeadHash': event.result.headHash,
        });
        final draft = {'body': oldBody, 'headHash': oldHash};
        Future<bool> check({
          Map? changedReceipt,
          Map? changedDraft,
          Map? changedContext,
          CryptoCaptureKeyDescriptor? changedCapture,
          Map? changedEvent,
        }) => CryptoMigrationSupersededSetup.verifies(
          crypto: crypto,
          own: event.result,
          approvalDirectory: genesis.result,
          oldDirectory: genesis.result,
          prepareDirectory: event.result,
          capture: changedCapture ?? capture,
          scopeId: scope,
          draft: changedDraft ?? draft,
          context: changedContext ?? context,
          approval: approval,
          eventEntry: changedEvent ?? event.entry,
          oldProposal: oldProposal,
          finish: finish,
          receipt: changedReceipt ?? receipt,
          prepare: prepare,
        );
        expect(await check(), true);
        expect(
          await check(
            changedReceipt: {...receipt, 'authorization': oldProposal},
          ),
          false,
        );
        expect(
          await check(
            changedReceipt: {
              ...receipt,
              'response': {
                'generationId': generation,
                'state': 'review',
                'migrationId': capture.migrationId,
              },
            },
          ),
          false,
        );
        expect(
          await check(
            changedDraft: {
              ...draft,
              'body': {...oldBody, 'epoch': 2},
            },
          ),
          false,
        );
        expect(
          await check(
            changedContext: {...context, 'newMigrationId': crypto.randomId()},
          ),
          false,
        );
        expect(
          await check(
            changedEvent: {
              ...event.entry,
              'headHash': genesis.result.headHash,
              'generation': genesis.result.generation,
            },
          ),
          false,
        );
        final otherCapture = CryptoCaptureKeyDescriptor(
          captureId: crypto.randomId(),
          migrationId: capture.migrationId,
          keyId: capture.keyId,
          rootScopeId: scope,
          componentId: component,
          scopeIds: [scope],
          receiptSelections: capture.receiptSelections,
        );
        expect(await check(changedCapture: otherCapture), false);
      } finally {
        for (final pair in [root, box, device, deviceBox]) {
          pair.secretKey.dispose();
        }
      }
    },
  );
}
