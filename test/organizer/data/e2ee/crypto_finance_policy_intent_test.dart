import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:sodium/sodium.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_v2.dart';
import 'package:kanban/organizer/data/e2ee/crypto_codec.dart';
import 'package:kanban/organizer/data/e2ee/crypto_json.dart';
import 'package:kanban/organizer/data/e2ee/scope_crypto_codec.dart';

void main() {
  test(
    'finance policy intent binds exact signed before/after policy, previous manager and role',
    () async {
      final crypto = CryptoCodec(await SodiumInit.init()),
          codec = ScopeCryptoCodec(CryptoCodec(await SodiumInit.init()));
      final root = crypto.sodium.crypto.sign.keyPair(),
          box = crypto.sodium.crypto.box.keyPair(),
          device = crypto.sodium.crypto.sign.keyPair(),
          deviceBox = crypto.sodium.crypto.box.keyPair();
      try {
        final server = crypto.randomId(),
            id = crypto.randomId(),
            deviceId = crypto.randomId(),
            scope = crypto.randomId(),
            epoch = crypto.randomId();
        final directory = (await AccountDirectoryV2(crypto).prepare(
          previous: null,
          serverId: server,
          accountId: id,
          deviceId: deviceId,
          identityEpochId: epoch,
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
        )).result;
        final member = {
          'accountId': id,
          'rootSigningKeyBase64': base64Encode(root.publicKey),
          'rootEncryptionKeyBase64': base64Encode(box.publicKey),
          'recoveryRootEpochId': epoch,
          'identityEpochId': epoch,
          'directoryHeadHash': directory.headHash,
          'deviceSnapshotHash': directory.deviceSnapshotHash,
          'role': 'owner',
          'financeRole': 'none',
          'manageKeys': true,
        };
        final body = <String, dynamic>{
          'scopeId': scope,
          'epoch': 1,
          'previousHeadHash': cryptoZeroHash,
          'initialLifecycleHash': '1' * 64,
          'previousLifecycleHash': null,
          'accessRevision': 0,
          'expectedAccessRevision': 0,
          'accessBasis': [
            {'scopeToken': '2' * 64, 'accessRevision': 0},
          ],
          'authorDirectoryHeadHash': directory.headHash,
          'members': [member],
          'membershipIntents': [],
          'closures': {'content': null, 'finance': null},
          'keyIds': {'content': crypto.randomId(), 'finance': null},
          'keyCommitments': {'content': '3' * 64, 'finance': null},
          'contentKeyProposalProof': null,
          'financeKeyProposalProof': null,
          'financePolicyIntentProof': null,
        };
        Map<String, dynamic> command(
          String operation,
          Map<String, dynamic> payload,
        ) => {
          'version': 2,
          'operation': operation,
          'requestId': crypto.randomId(),
          'serverId': server,
          'accountId': id,
          'deviceId': deviceId,
          'signer': 'device',
          'payload': payload,
        };
        final previous = await codec.verifyProposal(
          serverId: server,
          authorization: crypto.signDomain(
            command('crypto2.scope.headPut', body),
            device.secretKey,
            cryptoDirectoryDomain,
          ),
          previous: null,
          authorDirectory: directory,
          directoryAtHead: (a, h) async => directory,
          checkIdentity: (a, f) async {},
        );
        final payload = <String, dynamic>{
          'scopeId': scope,
          'membershipHeadHash': previous.headHash,
          'expectedAccessRevision': 0,
          'authorDirectoryHeadHash': directory.headHash,
          'expectedFinancePolicyRevision': 0,
          'previousPolicyHash': '4' * 64,
          'resultingFinancePolicyRevision': 1,
          'resultingPolicyHash': '5' * 64,
          'action': {'kind': 'grant', 'accountId': id, 'grant': 'read'},
        };
        Future<Map<String, dynamic>?> verify(
          Map<String, dynamic> p, {
          String role = 'read',
          SecureKey? signer,
        }) => codec.verifyFinancePolicyIntent(
          body: {
            ...body,
            'members': [
              {...member, 'financeRole': role},
            ],
            'financePolicyIntentProof': crypto.signDomain(
              command('crypto2.scope.financePolicy.propose', p),
              signer ?? device.secretKey,
              cryptoDirectoryDomain,
            ),
          },
          previous: previous,
          directoryAtHead: (a, h) async => directory,
        );
        expect((await verify(payload))!['resultingPolicyHash'], '5' * 64);
        final nextBody = <String, dynamic>{
          ...body,
          'epoch': 2,
          'previousHeadHash': previous.headHash,
          'previousLifecycleHash': cryptoZeroHash,
          'accessRevision': 1,
          'keyIds': {'content': crypto.randomId(), 'finance': null},
          'keyCommitments': {'content': '6' * 64, 'finance': null},
          'closures': {'content': '7' * 64, 'finance': null},
        };
        final consent = <String, dynamic>{
          'version': 2,
          'operation': 'crypto2.access.scopeConsent',
          'serverId': server,
          'scopeId': scope,
          'intentHash': '8' * 64,
          'affectedCount': 2,
          'affectedHash': '9' * 64,
          'previousHeadHash': previous.headHash,
          'expectedAccessRevision': 0,
          'accessBasis': body['accessBasis'],
          'resultingAccessRevision': 1,
          'resultingDescriptor': {
            'kind': 'household',
            'accessPolicyVersion': 3,
            'parentScopeToken': null,
          },
          'membersHash': await cryptoSha256(CryptoJson.encode(body['members'])),
          'accountId': id,
          'deviceId': deviceId,
          'authorDirectoryHeadHash': directory.headHash,
        };
        Future<void> verifyConsent(
          Map<String, dynamic> value, {
          SecureKey? key,
        }) => codec.verifyAccessIntent(
          body: {
            ...nextBody,
            'accessIntentProof': crypto.signDomain(
              value,
              key ?? device.secretKey,
              'JivieE2EE/accessScopeConsent/v2\n',
            ),
          },
          previous: previous,
          authorDirectory: directory,
          proposalCommand: command('crypto2.scope.headPut', nextBody),
        );
        await verifyConsent(consent);
        // Legacy component revocation may bump its root access counter twice.
        // Only the exact typed signed consent admits that result; ordinary and
        // finance/null paths retain the one-step limit.
        final larger = <String, dynamic>{...nextBody, 'accessRevision': 2};
        expect(() => codec.validateBody(larger), throwsFormatException);
        final largerConsent = <String, dynamic>{
          ...consent,
          'resultingAccessRevision': 2,
        };
        larger['accessIntentProof'] = crypto.signDomain(
          largerConsent,
          device.secretKey,
          'JivieE2EE/accessScopeConsent/v2\n',
        );
        codec.validateBody(larger);
        await codec.verifyAccessIntent(
          body: larger,
          previous: previous,
          authorDirectory: directory,
          proposalCommand: command('crypto2.scope.headPut', larger),
        );
        await expectLater(
          codec.verifyAccessIntent(
            body: {...larger, 'accessRevision': 3},
            previous: previous,
            authorDirectory: directory,
            proposalCommand: command('crypto2.scope.headPut', larger),
          ),
          throwsFormatException,
        );
        expect(
          () => codec.validateBody({
            ...larger,
            'accessRevision': 9007199254740992,
          }),
          throwsFormatException,
        );
        expect(
          () => codec.validateBody({
            ...larger,
            'expectedAccessRevision': 9007199254740992,
          }),
          throwsFormatException,
        );
        for (final field in [
          'membersHash',
          'previousHeadHash',
          'affectedCount',
          'accountId',
          'resultingAccessRevision',
        ]) {
          await expectLater(
            verifyConsent({
              ...consent,
              field: field == 'affectedCount'
                  ? 0
                  : field == 'resultingAccessRevision'
                  ? 2
                  : '0' * 64,
            }),
            throwsFormatException,
            reason: field,
          );
        }
        await expectLater(
          verifyConsent(consent, key: root.secretKey),
          throwsFormatException,
        );
        nextBody['accessIntentProof'] = crypto.signDomain(
          consent,
          device.secretKey,
          'JivieE2EE/accessScopeConsent/v2\n',
        );
        final component = await codec.verifyProposal(
          serverId: server,
          authorization: crypto.signDomain(
            command('crypto2.scope.headPut', nextBody),
            device.secretKey,
            cryptoDirectoryDomain,
          ),
          previous: previous,
          authorDirectory: directory,
          directoryAtHead: (a, h) async => directory,
          checkIdentity: (a, f) async {},
        );
        final activation = <String, dynamic>{
          'scopeId': scope,
          'headHash': component.headHash,
          'grantManifestHash': 'a' * 64,
          'authorDirectoryHeadHash': directory.headHash,
          'accessIntentHash': consent['intentHash'],
          'affectedCount': 2,
          'affectedHash': '9' * 64,
        };
        Future<VerifiedScopeHead> activate(Map<String, dynamic> value) =>
            codec.verifyActivation(
              pending: component,
              previous: previous,
              authorization: crypto.signDomain(
                command('crypto2.scope.activate', value),
                device.secretKey,
                cryptoDirectoryDomain,
              ),
              authorDirectory: directory,
              grantManifestHash: 'a' * 64,
              directoryAtHead: (a, h) async => directory,
            );
        expect((await activate(activation)).active, true);
        await expectLater(
          activate({...activation, 'affectedHash': 'b' * 64}),
          throwsFormatException,
        );
        final omitted = Map<String, dynamic>.from(activation)
          ..remove('affectedCount');
        await expectLater(activate(omitted), throwsFormatException);

        await expectLater(
          verify({...payload, 'membershipHeadHash': '6' * 64}),
          throwsFormatException,
        );
        await expectLater(
          verify({...payload, 'resultingFinancePolicyRevision': 0}),
          throwsFormatException,
        );
        await expectLater(
          verify({...payload, 'resultingPolicyHash': '4' * 64}),
          throwsFormatException,
        );
        await expectLater(
          verify(payload, role: 'write'),
          throwsFormatException,
        );
        await expectLater(
          verify(payload, signer: root.secretKey),
          throwsFormatException,
        );
        await expectLater(
          verify({
            ...payload,
            'action': {
              'kind': 'grant',
              'accountId': id,
              'grant': 'read',
              'extra': true,
            },
          }),
          throwsFormatException,
        );
        expect(
          await codec.verifyFinancePolicyIntent(
            body: {...body, 'financePolicyIntentProof': null},
            previous: previous,
            directoryAtHead: (a, h) async => directory,
          ),
          isNull,
        );
      } finally {
        for (final pair in [root, box, device, deviceBox]) {
          pair.secretKey.dispose();
        }
      }
    },
  );
}
