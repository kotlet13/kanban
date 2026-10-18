import 'dart:convert';

import 'package:cryptography/cryptography.dart' show Sha256;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/e2ee/crypto_json.dart';
import 'package:kanban/organizer/data/e2ee/crypto_sync_store.dart';

void main() {
  late CollaborationDatabase db;
  late CryptoSyncStore store;
  setUp(() {
    db = CollaborationDatabase(NativeDatabase.memory());
    store = CryptoSyncStore(db, 'synthetic-partition');
  });
  tearDown(() => db.close());
  test(
    'genesis access revision zero is exact; known positive access cannot roll back',
    () async {
      Future<void> save(int revision) => store.checkpoint(
        scopeId: 'genesis',
        domain: 'content',
        epoch: 1,
        accessRevision: revision,
        transportCursor: 0,
        projectionCursor: 0,
        scopeSequence: 0,
        complete: false,
      );
      await save(0);
      expect((await store.scope('genesis', 'content'))!['access_revision'], 0);
      await save(4);
      await expectLater(save(0), throwsFormatException);
      expect((await store.scope('genesis', 'content'))!['access_revision'], 4);
    },
  );
  test(
    'schema11 is additive; local write and immutable ciphertext queue commit or rollback together',
    () async {
      expect((await db.rows('PRAGMA user_version')).single['user_version'], 11);
      await expectLater(
        store.transaction(() async {
          await db.execute(
            "INSERT INTO local_meta VALUES('business','candidate')",
          );
          await store.stage(
            requestId: 'id',
            operation: 'crypto2.records.batch',
            signed: {'commandBase64': 'AAAA', 'signatureBase64': 'BBBB'},
            requestHash: 'a' * 64,
          );
          throw StateError('crash before commit');
        }),
        throwsStateError,
      );
      expect(
        await db.rows("SELECT * FROM local_meta WHERE name='business'"),
        isEmpty,
      );
      expect(await store.pending(), isEmpty);
      await store.transaction(() async {
        await db.execute(
          "INSERT INTO local_meta VALUES('business','committed')",
        );
        await store.stage(
          requestId: 'id',
          operation: 'crypto2.records.batch',
          signed: {'commandBase64': 'AAAA', 'signatureBase64': 'BBBB'},
          requestHash: 'a' * 64,
        );
      });
      await expectLater(
        store.stage(
          requestId: 'id',
          operation: 'crypto2.records.batch',
          signed: {'commandBase64': 'CHANGED', 'signatureBase64': 'BBBB'},
          requestHash: 'b' * 64,
        ),
        throwsFormatException,
      );
      expect((await store.pending()).single['signed_body'], contains('AAAA'));
      await store.stage(
        requestId: 'id',
        operation: 'crypto2.records.batch',
        signed: {'signatureBase64': 'BBBB', 'commandBase64': 'AAAA'},
        requestHash: 'a' * 64,
      );
      expect(await store.pending(), hasLength(1));
    },
  );
  test(
    'raw candidates preserve corrupt first response and corrected unsigned sequence',
    () async {
      final good = <String, dynamic>{
        'id': 'record',
        'revision': 1,
        'sequence': 1,
        'authorization': {
          'recordProof': {'commandBase64': 'valid', 'signatureBase64': 'sig'},
        },
      };
      final bad = {
        ...good,
        'authorization': {
          'recordProof': {
            'commandBase64': 'corrupted',
            'signatureBase64': 'sig',
          },
        },
      };
      await store.receive(
        scopeId: 'scope',
        domain: 'content',
        wire: bad,
        verdict: 'quarantined',
      );
      await store.receive(
        scopeId: 'scope',
        domain: 'content',
        wire: good,
        verdict: 'received',
      );
      expect(
        await db.rows('SELECT * FROM crypto_received_candidates'),
        hasLength(2),
      );
      // Signature verification, not mere receipt, selects the canonical candidate.
      await store.receive(
        scopeId: 'scope',
        domain: 'content',
        wire: good,
        verdict: 'verified',
        batchKey: 'verified-batch',
      );
      expect(
        jsonDecode(
          (await db.rows('SELECT wire FROM crypto_received')).single['wire']
              as String,
        ),
        good,
      );
      await store.receive(
        scopeId: 'scope',
        domain: 'content',
        wire: {...good, 'sequence': 999},
        verdict: 'received',
      );
      await store.receive(
        scopeId: 'scope',
        domain: 'content',
        wire: {...good, 'sequence': 999},
        verdict: 'received',
        batchKey: 'verified-batch',
      );
      await store.receive(
        scopeId: 'scope',
        domain: 'content',
        wire: good,
        verdict: 'received',
        batchKey: 'verified-batch',
      );
      final current = (await db.rows('SELECT * FROM crypto_received')).single;
      expect(current['verdict'], 'verified');
      expect(current['sequence'], 1);
      expect(
        await db.rows('SELECT * FROM crypto_received_candidates'),
        hasLength(3),
      );
      // Two different authenticated proofs at the same business revision remain
      // genuine equivocation, with both original observations preserved.
      await expectLater(
        store.receive(
          scopeId: 'scope',
          domain: 'content',
          wire: bad,
          verdict: 'received',
          batchKey: 'different-valid-batch',
        ),
        throwsFormatException,
      );
      expect(
        (await db.rows('SELECT * FROM crypto_received')).single['error'],
        'crypto_revision_equivocation',
      );
    },
  );
  test(
    'equivalent receipt key order preserves terminal applied result',
    () async {
      await store.stage(
        requestId: 'same',
        operation: 'crypto2.records.batch',
        signed: {'commandBase64': 'AAAA', 'signatureBase64': 'BBBB'},
        requestHash: 'a' * 64,
      );
      await store.outcome('same', 'applied', {
        'status': 200,
        'response': {'a': 1, 'b': 2},
      });
      await store.outcome('same', 'applied', {
        'response': {'b': 2, 'a': 1},
        'status': 200,
      });
      await expectLater(
        store.outcome('same', 'applied', {
          'response': {'b': 3, 'a': 1},
          'status': 200,
        }),
        throwsFormatException,
      );
      expect((await store.outgoing('same'))!['state'], 'applied');
    },
  );
  test(
    'all checkpoint coordinates are monotone and no known tail can disappear',
    () async {
      Future<void> save({
        int epoch = 3,
        int access = 4,
        int transport = 20,
        int projection = 10,
        int sequence = 100,
      }) => store.checkpoint(
        scopeId: 'scope',
        domain: 'finance',
        epoch: epoch,
        accessRevision: access,
        transportCursor: transport,
        projectionCursor: projection,
        scopeSequence: sequence,
        complete: false,
      );
      await save();
      for (final action in [
        () => save(epoch: 2),
        () => save(access: 3),
        () => save(transport: 19),
        () => save(projection: 9),
        () => save(sequence: 50),
      ]) {
        await expectLater(action(), throwsFormatException);
      }
      expect((await store.scope('scope', 'finance'))!['scope_sequence'], 100);
    },
  );
  test(
    'signed exact predecessor repair preserves rejected raw evidence',
    () async {
      final proof = {
        'commandBase64': 'invalid-but-retained',
        'signatureBase64': 'bad',
      };
      final hash = (await Sha256().hash(
        CryptoJson.encode(proof),
      )).bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      final wire = {
        'id': 'record',
        'revision': 5,
        'sequence': 8,
        'authorization': {'recordProof': proof},
      };
      await store.receive(
        scopeId: 'scope',
        domain: 'finance',
        wire: wire,
        verdict: 'quarantined',
        error: 'crypto_record_verification',
      );
      await expectLater(
        store.supersede(
          scopeId: 'scope',
          domain: 'finance',
          recordId: 'record',
          revision: 5,
          proofHash: '0' * 64,
          replacementRevision: 6,
        ),
        throwsFormatException,
      );
      await store.supersede(
        scopeId: 'scope',
        domain: 'finance',
        recordId: 'record',
        revision: 5,
        proofHash: hash,
        replacementRevision: 6,
      );
      final row = (await db.rows('SELECT * FROM crypto_received')).single;
      expect(row['verdict'], 'superseded');
      expect(row['superseded_by_revision'], 6);
      expect(jsonDecode(row['wire'] as String), wire);
      expect(row['error'], 'crypto_record_verification');
    },
  );
}
