import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:sodium/sodium.dart';
import 'package:kanban/organizer/data/e2ee/crypto_codec.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_v2.dart';
import 'package:kanban/organizer/data/e2ee/crypto_json.dart';
import 'package:kanban/organizer/data/e2ee/crypto_record_address.dart';
import 'package:kanban/organizer/data/e2ee/crypto_record_proof_codec.dart';
import 'package:kanban/organizer/data/e2ee/crypto_record_conflict.dart';

Map<String, dynamic> _copy(Map value) =>
    Map<String, dynamic>.from(jsonDecode(jsonEncode(value)) as Map);
void main() {
  Future<
    Future<bool> Function({
      Map<String, dynamic>? out,
      Map<String, dynamic>? business,
      List<Map<String, dynamic>>? claims,
    })
  >
  fixture() async {
    final crypto = CryptoCodec(await SodiumInit.init()),
        codec = CryptoRecordProofCodec(CryptoCodec(await SodiumInit.init()));
    final pair = crypto.sodium.crypto.sign.keyPair(),
        key = crypto.sodium.crypto.aeadXChaCha20Poly1305IETF.keygen();
    addTearDown(pair.secretKey.dispose);
    addTearDown(key.dispose);
    final server = crypto.randomId(),
        account = crypto.randomId(),
        device = crypto.randomId(),
        scope = crypto.randomId(),
        id = crypto.randomId(),
        operation = crypto.randomId(),
        batch = crypto.randomId(),
        request = crypto.randomId();
    final address = CryptoRecordAddress.forType(
      serverId: server,
      scopeId: scope,
      domain: 'content',
      type: 'shoppingList',
      canonicalId: id,
    );
    final proof = codec.sealRecord(
      serverId: server,
      accountId: account,
      deviceId: device,
      batchId: batch,
      scopeId: scope,
      id: address.wireId,
      type: 'shoppingList',
      expectedRevision: 1,
      epoch: 2,
      accessRevision: 2,
      membershipHeadHash: '1' * 64,
      domain: 'content',
      contentContract: 6,
      operationId: operation,
      previousRecordHash: '2' * 64,
      deleted: false,
      plaintext: Uint8List.fromList(utf8.encode('{}')),
      metadata: {
        'identity': address.identity,
        'references': <Object>[],
        'referenceVersions': <Object>[],
        'uniqueRefs': <String>[],
        'blobIds': <String>[],
        'notificationState': {
          'version': 1,
          'kind': 'updated',
          'assigneeAccountIds': <String>[],
          'groupTargetId': null,
        },
      },
      contentKey: key,
      signingKey: pair.secretKey,
    );
    final commitment = await codec.commitBatch(
      serverId: server,
      accountId: account,
      deviceId: device,
      batchId: batch,
      records: [proof],
      signingKey: pair.secretKey,
      projectionToken: (r) async => codec.projectionGroupToken(r, key),
    );
    final signed = codec.signCommand({
      'version': 2,
      'operation': 'crypto2.records.batch',
      'serverId': server,
      'accountId': account,
      'deviceId': device,
      'signer': 'device',
      'requestId': request,
      'payload': {
        'batchId': batch,
        'records': [proof],
        'commitment': commitment,
      },
    }, pair.secretKey);
    final hash = await cryptoSha256(cryptoBase64(signed['commandBase64']));
    final retained = <String, dynamic>{
      'request_id': request,
      'request_hash': hash,
      'operation': 'crypto2.records.batch',
      'signed_body': jsonEncode(signed),
      'state': 'rejected',
      'response': jsonEncode({
        'requestId': request,
        'requestHash': hash,
        'authorization': signed,
        'status': 409,
        'response': {'errorCode': 'conflict'},
      }),
    };
    final journal = <String, dynamic>{
      'scope_id': scope,
      'domain': 'content',
      'record_id': id,
      'operation_id': operation,
      'request_hash': 'local-hash',
      'request_id': request,
    };
    final recordClaims = <Map<String, dynamic>>[
      {
        'partition': 'p',
        'scope_id': scope,
        'domain': 'content',
        'record_id': address.wireId,
        'expected_revision': 1,
        'request_id': request,
      },
    ];
    return ({out, business, claims}) => isBoundOrdinaryRecordConflict(
      codec: codec,
      signingPublicKey: pair.publicKey,
      partition: 'p',
      serverId: server,
      accountId: account,
      deviceId: device,
      scopeId: scope,
      recordId: id,
      recordType: 'shoppingList',
      operationId: operation,
      localHash: 'local-hash',
      business: business ?? journal,
      outgoing: out ?? retained,
      claims: claims ?? recordClaims,
    );
  }

  test(
    'signed ordinary definitive rejection is classified without trusting raw remote',
    () async {
      final inspect = await fixture();
      expect(await inspect(), isTrue);
    },
  );
  test('pending signed outcome cannot authorize fresh successor', () async {
    final inspect = await fixture();
    expect(await inspect(out: {'state': 'pending'}), isFalse);
  });
  test(
    'foreign local intent binding cannot classify signed conflict',
    () async {
      final inspect = await fixture();
      await expectLater(
        inspect(business: {'scope_id': 'foreign'}),
        throwsA(isA<FormatException>()),
      );
    },
  );
  test(
    'missing exact revision claim cannot classify signed conflict',
    () async {
      final inspect = await fixture();
      await expectLater(inspect(claims: []), throwsA(isA<FormatException>()));
    },
  );
  test(
    'malformed rejected response is not treated as conflict proof',
    () async {
      final inspect = await fixture();
      expect(
        await inspect(
          out: {
            'state': 'rejected',
            'response': jsonEncode({
              'status': 403,
              'response': {'errorCode': 'permission_revoked'},
            }),
          },
        ),
        isFalse,
      );
    },
  );
  test(
    'forged response body without original signed authorization fails closed',
    () async {
      final inspect = await fixture();
      final out = _copy({
        'state': 'rejected',
        'operation': 'crypto2.records.batch',
        'request_id': 'forged',
        'request_hash': 'forged',
        'signed_body': '{}',
        'response': jsonEncode({
          'status': 409,
          'response': {'errorCode': 'conflict'},
        }),
      });
      await expectLater(inspect(out: out), throwsA(isA<FormatException>()));
    },
  );
}
