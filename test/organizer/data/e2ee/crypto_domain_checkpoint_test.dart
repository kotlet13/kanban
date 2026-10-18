import 'dart:typed_data';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/e2ee/crypto_codec.dart';
import 'package:kanban/organizer/data/e2ee/crypto_record_address.dart';
import 'package:kanban/organizer/data/e2ee/crypto_domain_checkpoint.dart';
import 'package:kanban/organizer/data/e2ee/crypto_json.dart';
import 'package:kanban/organizer/data/e2ee/crypto_record_proof_codec.dart';
import 'package:kanban/organizer/data/e2ee/crypto_sync_repository.dart';
import 'package:kanban/organizer/data/e2ee/crypto_sync_store.dart';
import 'package:cryptography/cryptography.dart' show Sha256;
import 'package:sodium/sodium.dart';

void main() {
  test(
    'signed empty inventory resets poisoned transport999 while preserving real floors and evidence',
    () async {
      final db = CollaborationDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final crypto = CryptoCodec(await SodiumInit.init());
      final codec = CryptoRecordProofCodec(crypto);
      final key = crypto.sodium.crypto.sign.keyPair();
      addTearDown(key.dispose);
      final scope = crypto.randomId(), partition = 'synthetic-partition';
      final store = CryptoSyncStore(db, partition);
      await store.checkpoint(
        scopeId: scope,
        domain: 'content',
        epoch: 1,
        accessRevision: 2,
        transportCursor: 999,
        projectionCursor: 999,
        scopeSequence: 999,
        complete: false,
      );
      final hash = (await Sha256().hash(
        [],
      )).bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      final payload = <String, dynamic>{
        'scopeId': scope,
        'domain': 'content',
        'epoch': 1,
        'membershipHeadHash': 'a' * 64,
        'accessRevision': 2,
        'expectedSequence': 0,
        'recordCount': 0,
        'manifestHash': hash,
        'historyBasis': 'verifiedCheckpoint',
        'authorDirectoryHeadHash': 'b' * 64,
      };
      final proof = codec.signCommand({
        'version': 2,
        'operation': 'crypto2.domain.checkpoint',
        'requestId': crypto.randomId(),
        'serverId': crypto.randomId(),
        'accountId': crypto.randomId(),
        'deviceId': crypto.randomId(),
        'signer': 'device',
        'payload': payload,
      }, key.secretKey);
      final reader = CryptoDomainCheckpointReader(
        database: db,
        partition: partition,
        codec: codec,
        call: (op, p) async => {
          'scopeId': scope,
          'domain': 'content',
          'epoch': 1,
          'membershipHeadHash': 'a' * 64,
          'scopeSequence': 0,
          'descriptors': [],
          'hasMore': false,
          'checkpoint': {
            'manifestHash': hash,
            'recordCount': 0,
            'membershipHeadHash': 'a' * 64,
            'domainSequence': 0,
            'attestations': [
              {'authorization': proof},
            ],
            'hasMore': false,
          },
        },
        verify: (p) async {
          crypto.verifyDomain(p, key.publicKey, 'JivieE2EE/v2\n');
          return 'verifiedCheckpoint';
        },
      );
      const context = CryptoReadContext(
        epoch: 1,
        accessRevision: 2,
        headHash:
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      );
      final retained = await reader.reconcile(scope, 'content', context);
      expect(retained, isNotNull);
      expect(await reader.reconcile(scope, 'content', context), retained);
      final observed = <String, dynamic>{
        'domain': 'content',
        'membershipHeadHash': context.headHash,
        'sequence': 0,
        'manifestHash': hash,
        'recordCount': 0,
        'proofHashes': [await codec.digest(proof)],
      };
      expect(
        await reader.retainsObservedInventory(
          scope,
          'content',
          context,
          observed,
        ),
        isTrue,
      );
      await expectLater(
        reader.reconcile(
          scope,
          'content',
          context,
          observedAnchors: [
            {...observed, 'recordCount': 1},
          ],
        ),
        throwsA(isA<CryptoAuthorityPending>()),
      );
      expect(
        await reader.reconcile(
          scope,
          'content',
          context,
          observedAnchors: [
            {
              ...observed,
              'proofHashes': ['f' * 64],
            },
          ],
        ),
        isNull,
      );
      expect(
        await db.rows('SELECT snapshot_id FROM crypto_domain_checkpoints'),
        [
          {'snapshot_id': retained},
        ],
      );
      expect(
        await db.rows('SELECT * FROM crypto_domain_inventory_rows'),
        isEmpty,
      );
      final state = (await store.scope(scope, 'content'))!;
      expect(state['transport_cursor'], 0);
      expect(state['projection_cursor'], 0);
      expect(state['floor'], 1);
      expect(state['access_revision'], 2);
      expect(state['complete'], 0);
      expect(
        await db.rows('SELECT * FROM crypto_domain_checkpoints'),
        hasLength(1),
      );
      // Local signed epoch/access authority cannot be reset by an older snapshot.
      await store.checkpoint(
        scopeId: scope,
        domain: 'content',
        epoch: 2,
        accessRevision: 3,
        transportCursor: 0,
        projectionCursor: 0,
        scopeSequence: 0,
        complete: false,
      );
      await expectLater(
        reader.reconcile(scope, 'content', context),
        throwsFormatException,
      );
      expect((await store.scope(scope, 'content'))!['floor'], 2);
    },
  );
  test(
    'same authenticated record inventory can reconcile attested ordering999 into fresh scan1',
    () async {
      final db = CollaborationDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final crypto = CryptoCodec(await SodiumInit.init()),
          codec = CryptoRecordProofCodec(crypto);
      final key = crypto.sodium.crypto.sign.keyPair(),
          content = crypto.sodium.secureRandom(32);
      addTearDown(key.dispose);
      addTearDown(content.dispose);
      final scope = crypto.randomId(),
          server = crypto.randomId(),
          account = crypto.randomId(),
          device = crypto.randomId();
      final address = CryptoRecordAddress.forType(
        serverId: server,
        scopeId: scope,
        type: 'scopeMetadata',
        canonicalId: crypto.randomId(),
      );
      final proof = codec.sealRecord(
        serverId: server,
        accountId: account,
        deviceId: device,
        batchId: crypto.randomId(),
        scopeId: scope,
        id: address.wireId,
        type: 'scopeMetadata',
        expectedRevision: 0,
        epoch: 1,
        accessRevision: 2,
        membershipHeadHash: 'a' * 64,
        domain: 'content',
        contentContract: 6,
        operationId: crypto.randomId(),
        previousRecordHash: '0' * 64,
        deleted: false,
        plaintext: Uint8List(0),
        metadata: {
          'identity': address.identity,
          'references': [],
          'uniqueRefs': [],
          'blobIds': [],
        },
        contentKey: content,
        signingKey: key.secretKey,
      );
      final record =
          CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map;
      final wire = <String, dynamic>{
        ...record.cast<String, dynamic>(),
        'revision': 1,
        'sequence': 999,
        'authorization': {'recordProof': proof},
      };
      final store = CryptoSyncStore(db, 'partition');
      await store.receive(
        scopeId: scope,
        domain: 'content',
        wire: wire,
        verdict: 'verified',
        batchKey: 'authenticated-batch',
      );
      await store.checkpoint(
        scopeId: scope,
        domain: 'content',
        epoch: 1,
        accessRevision: 2,
        transportCursor: 999,
        projectionCursor: 999,
        scopeSequence: 999,
        complete: false,
      );
      var sequence = 999;
      final reader = CryptoDomainCheckpointReader(
        database: db,
        partition: 'partition',
        codec: codec,
        verify: (p) async {
          crypto.verifyDomain(p, key.publicKey, 'JivieE2EE/v2\n');
          return 'verifiedCheckpoint';
        },
        call: (op, params) async {
          final descriptor = {
            'id': record['id'],
            'revision': 1,
            'recordProofHash': await codec.digest(proof),
            'sequence': sequence,
            'recordEpoch': 1,
          };
          final hash = (await Sha256().hash([
            ...CryptoJson.encode(descriptor),
            10,
          ])).bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
          final attestation = codec.signCommand({
            'version': 2,
            'operation': 'crypto2.domain.checkpoint',
            'requestId': crypto.randomId(),
            'serverId': server,
            'accountId': account,
            'deviceId': device,
            'signer': 'device',
            'payload': {
              'scopeId': scope,
              'domain': 'content',
              'epoch': 1,
              'membershipHeadHash': 'a' * 64,
              'accessRevision': 2,
              'expectedSequence': sequence,
              'recordCount': 1,
              'manifestHash': hash,
              'historyBasis': 'verifiedCheckpoint',
              'authorDirectoryHeadHash': 'b' * 64,
            },
          }, key.secretKey);
          return {
            'scopeId': scope,
            'domain': 'content',
            'epoch': 1,
            'membershipHeadHash': 'a' * 64,
            'scopeSequence': sequence,
            'descriptors': [descriptor],
            'hasMore': false,
            'checkpoint': {
              'membershipHeadHash': 'a' * 64,
              'domainSequence': sequence,
              'recordCount': 1,
              'manifestHash': hash,
              'attestations': [
                {'authorization': attestation},
              ],
              'hasMore': false,
            },
          };
        },
      );
      final context = CryptoReadContext(
        epoch: 1,
        accessRevision: 2,
        headHash: 'a' * 64,
      );
      await reader.reconcile(scope, 'content', context);
      sequence = 1;
      await reader.reconcile(scope, 'content', context);
      final state = (await store.scope(scope, 'content'))!;
      final retainedCheckpoint = (await db.rows(
        'SELECT * FROM crypto_domain_checkpoints WHERE sequence=1',
      )).single;
      final observed = <String, dynamic>{
        'domain': 'content',
        'membershipHeadHash': context.headHash,
        'sequence': 1,
        'manifestHash': retainedCheckpoint['manifest_hash'],
        'recordCount': 1,
        'proofHashes': [
          await codec.digest(
            Map<String, dynamic>.from(
              jsonDecode(retainedCheckpoint['authorization'] as String),
            ),
          ),
        ],
      };
      expect(
        await reader.retainsObservedInventory(
          scope,
          'content',
          context,
          observed,
        ),
        isTrue,
      );
      await db.execute(
        'DELETE FROM crypto_domain_inventory_rows WHERE snapshot_id=?',
        [retainedCheckpoint['snapshot_id']],
      );
      expect(
        await reader.retainsObservedInventory(
          scope,
          'content',
          context,
          observed,
        ),
        isFalse,
      );
      expect(state['transport_cursor'], 0);
      expect(state['scan_generation'], 1);
      expect(state['floor'], 1);
      expect(
        await db.rows('SELECT * FROM crypto_domain_checkpoints'),
        hasLength(2),
      );
      expect(
        await db.rows('SELECT * FROM crypto_received_candidates'),
        hasLength(1),
      );
      expect(
        (await db.rows('SELECT * FROM crypto_received')).single['verdict'],
        'verified',
      );
    },
  );
}
