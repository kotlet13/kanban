import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/e2ee/crypto_codec.dart';
import 'package:kanban/organizer/data/e2ee/crypto_json.dart';
import 'package:kanban/organizer/data/e2ee/crypto_record_proof_codec.dart';
import 'package:sodium/sodium.dart';
import 'package:kanban/organizer/data/e2ee/crypto_record_address.dart';

void main() {
  late CryptoCodec crypto;
  late CryptoRecordProofCodec records;
  late KeyPair signer;
  late SecureKey dek;
  late String server, account, device, batch, scope, id, canonicalId;
  setUpAll(() async {
    crypto = CryptoCodec(await SodiumInit.init());
    records = CryptoRecordProofCodec(crypto);
  });
  setUp(() {
    signer = crypto.sodium.crypto.sign.keyPair();
    dek = crypto.sodium.secureRandom(32);
    server = crypto.randomId();
    account = crypto.randomId();
    device = crypto.randomId();
    batch = crypto.randomId();
    scope = crypto.randomId();
    canonicalId = crypto.randomId();
    id = cryptoWireRecordId(server, scope, 'task', canonicalId);
  });
  tearDown(() {
    signer.secretKey.dispose();
    dek.dispose();
  });
  Map<String, dynamic> seal({
    int revision = 0,
    String? previous,
    Map<String, dynamic> metadata = const {},
    int contract = 6,
  }) => records.sealRecord(
    serverId: server,
    accountId: account,
    deviceId: device,
    batchId: batch,
    scopeId: scope,
    id: id,
    type: 'task',
    expectedRevision: revision,
    epoch: 1,
    accessRevision: 1,
    membershipHeadHash: '1' * 64,
    domain: 'content',
    contentContract: contract,
    operationId: crypto.randomId(),
    previousRecordHash: previous ?? '0' * 64,
    deleted: false,
    plaintext: Uint8List.fromList(utf8.encode('private title')),
    metadata: {
      'identity': {'sourceKind': 'records', 'canonicalId': canonicalId},
      'references': <dynamic>[],
      'uniqueRefs': <dynamic>[],
      'blobIds': <dynamic>[],
      'notificationState': {
        'version': 1,
        'kind': 'updated',
        'assigneeAccountIds': [],
        'groupTargetId': null,
      },
      'reminderState': {
        'version': 1,
        'dueAtEpoch': null,
        'closed': false,
        'scheduleRevision': crypto.randomId(),
      },
      ...metadata,
    },
    contentKey: dek,
    signingKey: signer.secretKey,
  );
  Future<Map<String, dynamic>> wire(Map<String, dynamic> proof) async {
    final body =
        CryptoJson.decode(cryptoBase64(proof['commandBase64']))
            as Map<String, dynamic>;
    return {
      ...body,
      'revision': (body['expectedRevision'] as int) + 1,
      'authorization': {
        'recordProof': proof,
        'batchCommitment': await records.commitBatch(
          serverId: server,
          accountId: account,
          deviceId: device,
          batchId: batch,
          records: [proof],
          signingKey: signer.secretKey,
          projectionToken: (record) async =>
              records.projectionGroupToken(record, dek),
        ),
      },
    };
  }

  test(
    'canonical identities reject wire versions and invalid UUID variants',
    () {
      final proof = seal();
      final body = Map<String, dynamic>.from(
        CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map,
      );
      for (final invalid in [
        '00000000-0000-0000-8000-000000000000',
        '00000000-0000-4000-7000-000000000000',
        '00000000-0000-8000-8000-000000000000',
      ]) {
        expect(
          () => records.validateUntrustedRecord({...body, 'scopeId': invalid}),
          throwsFormatException,
        );
      }
      expect(
        () => records.validateUntrustedRecord({
          ...body,
          'id': '00000000-0000-8000-7000-000000000000',
        }),
        throwsFormatException,
      );
      expect(() => records.validateUntrustedRecord(body), returnsNormally);
    },
  );
  test(
    'record validates exact context and batch proof reveals no sibling identifiers',
    () async {
      final proof = seal();
      final row = await wire(proof);
      final verified = await records.verifyWire(
        serverId: server,
        wire: row,
        trustedSigningKey: signer.publicKey,
        currentEpoch: true,
      );
      expect(
        utf8.decode(records.openVerified(verified, dek)!),
        'private title',
      );
      final batchProof = (row['authorization'] as Map)['batchCommitment'];
      final commitment =
          CryptoJson.decode(cryptoBase64(batchProof['commandBase64'])) as Map;
      expect(commitment['recordDigests'], hasLength(1));
      expect(commitment, isNot(contains('scopeId')));
      await expectLater(
        records.verifyWire(
          serverId: server,
          wire: {...row, 'scopeId': crypto.randomId()},
          trustedSigningKey: signer.publicKey,
          currentEpoch: true,
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'post-revocation old key cannot mint new current record outside exact closure',
    () async {
      final old = seal();
      final oldHash = await records.digest(old);
      final forgedAfterRevoke = seal(revision: 1, previous: oldHash);
      await expectLater(
        records.verifyWire(
          serverId: server,
          wire: await wire(forgedAfterRevoke),
          trustedSigningKey: signer.publicKey,
          currentEpoch: false,
          closedRecordProofHash: oldHash,
        ),
        throwsFormatException,
      );
      expect(
        await records.verifyWire(
          serverId: server,
          wire: await wire(old),
          trustedSigningKey: signer.publicKey,
          currentEpoch: false,
          closedRecordProofHash: oldHash,
        ),
        isA<Map>(),
      );
    },
  );
  test(
    'validly signed malicious AEAD is a sanitized quarantinable failure',
    () async {
      final proof = seal();
      final body =
          CryptoJson.decode(cryptoBase64(proof['commandBase64']))
              as Map<String, dynamic>;
      final envelope =
          CryptoJson.decode(cryptoBase64(body['envelopeBase64']))
              as Map<String, dynamic>;
      final bytes = cryptoBase64(envelope['ciphertextBase64']);
      bytes[0] ^= 1;
      envelope['ciphertextBase64'] = base64Encode(bytes);
      body['envelopeBase64'] = base64Encode(CryptoJson.encode(envelope));
      final malicious = crypto.signDomain(
        body,
        signer.secretKey,
        'JivieE2EE/record/v2\n',
      );
      final verified = await records.verifyWire(
        serverId: server,
        wire: await wire(malicious),
        trustedSigningKey: signer.publicKey,
        currentEpoch: true,
      );
      expect(() => records.openVerified(verified, dek), throwsFormatException);
    },
  );
  test('repair binds the exact invalid revision and preceding proof', () async {
    final oldHash = await records.digest(seal());
    expect(
      () => seal(
        revision: 1,
        previous: oldHash,
        metadata: {
          'repairOf': {'revision': 1, 'recordProofHash': '2' * 64},
        },
      ),
      throwsFormatException,
    );
    final repair = seal(
      revision: 1,
      previous: oldHash,
      metadata: {
        'repairOf': {'revision': 1, 'recordProofHash': oldHash},
      },
    );
    expect(
      await records.verifyWire(
        serverId: server,
        wire: await wire(repair),
        trustedSigningKey: signer.publicKey,
        currentEpoch: true,
      ),
      isA<Map>(),
    );
    expect(() => seal(contract: 999), throwsFormatException);
  });
  test('signed scheduling and notification metadata has exact safe shape', () {
    expect(
      () => seal(metadata: {'reminderState': null}),
      throwsFormatException,
    );
    expect(
      () => seal(metadata: {'notificationState': null}),
      throwsFormatException,
    );
    expect(
      () => seal(
        metadata: {
          'reminderState': {
            'version': 1,
            'dueAtEpoch': -1,
            'closed': false,
            'scheduleRevision': crypto.randomId(),
          },
        },
      ),
      throwsFormatException,
    );
    expect(
      () => seal(
        metadata: {
          'notificationState': {
            'version': 1,
            'kind': 'updated',
            'assigneeAccountIds': [account, account],
            'groupTargetId': null,
          },
        },
      ),
      throwsFormatException,
    );
    expect(
      () => seal(
        metadata: {
          'projectState': {'version': 1, 'archived': false},
        },
      ),
      throwsFormatException,
    );
  });
  test('wrong sealed key cannot leak a native exception into sync', () {
    final recipient = crypto.sodium.crypto.box.keyPair();
    try {
      expect(
        () => crypto.openKey(
          sealed: base64Encode(Uint8List(80)),
          recipient: recipient,
          context: {},
        ),
        throwsFormatException,
      );
    } finally {
      recipient.secretKey.dispose();
    }
  });
  test(
    'opaque projection token is keyed and exact partition cannot overlap',
    () async {
      final proof = seal();
      final w = await wire(proof);
      final r = await records.verifyWire(
        serverId: server,
        wire: w,
        trustedSigningKey: signer.publicKey,
        currentEpoch: true,
      );
      final commitment = Map<String, dynamic>.from(
        w['authorization']['batchCommitment'] as Map,
      );
      expect(
        records.expectedProjectionDigests(
          record: r,
          commitment: commitment,
          contentKey: dek,
        ),
        [await records.digest(proof)],
      );
      final wrong = crypto.sodium.secureRandom(32);
      try {
        expect(
          () => records.expectedProjectionDigests(
            record: r,
            commitment: commitment,
            contentKey: wrong,
          ),
          throwsFormatException,
        );
      } finally {
        wrong.dispose();
      }
      final body =
          CryptoJson.decode(cryptoBase64(commitment['commandBase64']))
              as Map<String, dynamic>;
      final groups = body['projectionGroups'] as List;
      groups.add({'token': 'f' * 64, 'recordDigests': body['recordDigests']});
      groups.sort((a, b) => (a['token'] as String).compareTo(b['token']));
      final forged = crypto.signDomain(
        body,
        signer.secretKey,
        'JivieE2EE/batch/v2\n',
      );
      w['authorization']['batchCommitment'] = forged;
      await expectLater(
        records.verifyWire(
          serverId: server,
          wire: w,
          trustedSigningKey: signer.publicKey,
          currentEpoch: true,
        ),
        throwsFormatException,
      );
    },
  );
  test('untrusted malformed record is sanitized before authority lookup', () {
    expect(
      () => records.validateUntrustedRecord({'version': 2, 'metadata': null}),
      throwsFormatException,
    );
  });
}
