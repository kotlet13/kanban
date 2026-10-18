import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/e2ee/crypto_account_archive.dart';
import 'package:kanban/organizer/data/e2ee/crypto_capture_v3.dart';
import 'package:kanban/organizer/data/e2ee/crypto_codec.dart';
import 'package:kanban/organizer/data/e2ee/crypto_migration_witness.dart';
import 'package:kanban/organizer/data/e2ee/crypto_record_address.dart';
import 'package:sodium/sodium.dart';

void main() {
  late CryptoCodec crypto;
  setUpAll(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    crypto = CryptoCodec(await SodiumInit.init());
  });

  test(
    'source tombstone and large unknown bytes reopen in blank SQL without capture key; retry is exact',
    () async {
      final db = CollaborationDatabase(NativeDatabase.memory());
      final cold = CollaborationDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      addTearDown(cold.close);
      final captureKey = crypto.sodium.crypto.secretStream.keygen();
      final domainKey = crypto.sodium.crypto.secretStream.keygen();
      addTearDown(domainKey.dispose);
      final server = crypto.randomId(),
          scope = crypto.randomId(),
          canonical = crypto.randomId();
      final source = CryptoCaptureSourceContext(
        serverId: server,
        captureId: crypto.randomId(),
        migrationId: crypto.randomId(),
        accountId: crypto.randomId(),
        scopeId: scope,
        domain: 'content',
        sourceTable: 'familyhub_records',
        sourceId: 'row:17',
      );
      final salt = await CryptoCaptureV3.salt(captureKey, source);
      final bindingId = await CryptoCaptureV3.bindingId(captureKey, source);
      // The old payload remains exact evidence even though the new record itself
      // is a tombstone and is forbidden from carrying plaintext by the codec.
      final row = <String, dynamic>{
        'deleted': {
          'type': 'integer',
          'valueBase64': base64Encode(utf8.encode('1')),
        },
        'revision': {
          'type': 'integer',
          'valueBase64': base64Encode(utf8.encode('50')),
        },
        'payload': {
          'type': 'text',
          'valueBase64': base64Encode(
            utf8.encode(
              '{"unknown":{"fraction":0.1,"negativeZero":-0.0,"bytes":"${'z' * (2 * 1024 * 1024)}"}}',
            ),
          ),
        },
      };
      final commitment = await CryptoCaptureV3.sourceCommitment(
        context: source,
        salt: salt,
        typedRow: row,
      );
      final context = CryptoMigrationWitnessContext({
        'version': 3,
        'purpose': 'migrationWitness',
        ...{
          'serverId': server,
          'accountId': source.accountId,
          'captureId': source.captureId,
          'migrationId': source.migrationId,
          'bindingId': bindingId,
          'sourceInventoryRoot': 'a' * 64,
          'sourceCommitment': commitment,
          'scopeId': scope,
          'domain': 'content',
          'epoch': 1,
          'accessRevision': 0,
          'membershipHeadHash': 'b' * 64,
          'type': 'task',
          'sourceKind': 'records',
          'canonicalId': canonical,
          'wireId': cryptoWireRecordId(server, scope, 'task', canonical),
        },
      });
      final witness = <String, dynamic>{
        'version': 3,
        'context': source.toJson(),
        'typedRow': row,
        'saltBase64': base64Encode(salt),
      };
      salt.fillRange(0, salt.length, 0);
      captureKey.dispose();
      String? interruptAt = 'witness_streaming';
      final producer = CryptoMigrationWitness(
        database: db,
        partition: 'test',
        crypto: crypto,
        checkpoint: (phase) async {
          if (phase == interruptAt) {
            throw StateError('synthetic process loss at $phase');
          }
        },
      );
      for (final phase in [
        'witness_streaming',
        'witness_staged',
        'witness_wrapped',
      ]) {
        interruptAt = phase;
        await expectLater(
          producer.stage(
            context: context,
            witness: witness,
            domainKey: domainKey,
          ),
          throwsStateError,
        );
        final job = (await db.rows(
          'SELECT state,manifest FROM crypto_archive_jobs',
        )).single;
        expect(job['state'], phase == 'witness_streaming' ? 'draft' : 'staged');
        if (phase == 'witness_staged') {
          expect(job['manifest'], isNotNull);
          expect(
            (await db.rows(
              'SELECT key_bytes FROM crypto_archive_secrets',
            )).single['key_bytes'],
            isNotNull,
          );
        }
        if (phase == 'witness_wrapped') {
          expect(
            (await db.rows(
              'SELECT key_bytes FROM crypto_archive_secrets',
            )).single['key_bytes'],
            isNull,
          );
        }
      }
      interruptAt = null;
      final descriptor = await producer.stage(
        context: context,
        witness: witness,
        domainKey: domainKey,
      );
      expect(jsonEncode(descriptor), isNot(contains('familyhub_records')));
      expect(jsonEncode(descriptor), isNot(contains('negativeZero')));
      expect(jsonEncode(descriptor), isNot(contains(witness['saltBase64'])));
      expect(
        (await db.rows(
          'SELECT key_bytes FROM crypto_archive_secrets',
        )).single['key_bytes'],
        isNull,
      );
      expect(
        await producer.stage(
          context: context,
          witness: witness,
          domainKey: domainKey,
        ),
        descriptor,
      );
      // The producer and the transport importer use distinct LOCAL archive
      // namespaces for the same authenticated bytes. Reuse must not rewrite it.
      final originalJobs = await db.rows('SELECT * FROM crypto_archive_jobs');
      final originalSegments = await db.rows(
        'SELECT * FROM crypto_archive_segments',
      );
      expect(
        await producer.openProduced(
          context: context,
          descriptor: descriptor,
          domainKey: domainKey,
        ),
        witness,
      );
      expect(await db.rows('SELECT * FROM crypto_archive_jobs'), originalJobs);
      expect(
        await db.rows('SELECT * FROM crypto_archive_segments'),
        originalSegments,
      );
      final wrongLocalKey = crypto.sodium.crypto.secretStream.keygen();
      try {
        await expectLater(
          producer.openProduced(
            context: context,
            descriptor: descriptor,
            domainKey: wrongLocalKey,
          ),
          throwsFormatException,
        );
      } finally {
        wrongLocalKey.dispose();
      }
      await expectLater(
        producer.openProduced(
          context: CryptoMigrationWitnessContext({
            ...context.value,
            'epoch': 2,
          }),
          descriptor: descriptor,
          domainKey: domainKey,
        ),
        throwsFormatException,
      );
      final jobManifest =
          jsonDecode(originalJobs.single['manifest'] as String) as Map;
      await db.execute('UPDATE crypto_archive_jobs SET manifest=?', [
        jsonEncode({...jobManifest, 'keyId': crypto.randomId()}),
      ]);
      await expectLater(
        producer.openProduced(
          context: context,
          descriptor: descriptor,
          domainKey: domainKey,
        ),
        throwsFormatException,
      );
      await db.execute('UPDATE crypto_archive_jobs SET manifest=?', [
        originalJobs.single['manifest'],
      ]);
      final chunk = (await db.rows(
        'SELECT segment_id,chunk_offset,bytes FROM crypto_archive_chunks ORDER BY chunk_offset LIMIT 1',
      )).single;
      final broken = Uint8List.fromList((chunk['bytes'] as List).cast<int>());
      broken[broken.length - 1] ^= 1;
      await db.execute(
        'UPDATE crypto_archive_chunks SET bytes=? WHERE segment_id=? AND chunk_offset=?',
        [broken, chunk['segment_id'], chunk['chunk_offset']],
      );
      await expectLater(
        producer.openProduced(
          context: context,
          descriptor: descriptor,
          domainKey: domainKey,
        ),
        throwsFormatException,
      );
      await db.execute(
        'UPDATE crypto_archive_chunks SET bytes=? WHERE segment_id=? AND chunk_offset=?',
        [chunk['bytes'], chunk['segment_id'], chunk['chunk_offset']],
      );
      expect(
        await producer.openProduced(
          context: context,
          descriptor: descriptor,
          domainKey: domainKey,
        ),
        witness,
      );
      final manifest = CryptoArchiveManifest(
        migrationId: source.migrationId,
        keyId: 'irrelevant',
        cipherManifestHash: descriptor['cipherManifestHash'],
        segments: (descriptor['segments'] as List)
            .map(
              (s) => CryptoArchiveSegment(
                id: s['id'],
                index: s['index'],
                size: s['size'],
                sha256: s['sha256'],
              ),
            )
            .toList(),
      );
      final consumer = CryptoMigrationWitness(
        database: cold,
        partition: 'cold',
        crypto: crypto,
      );
      expect(
        await consumer.openProduced(
          context: context,
          descriptor: descriptor,
          domainKey: domainKey,
        ),
        isNull,
      );
      await expectLater(
        producer.staging.importSegment(
          manifest: manifest,
          segment: manifest.segments.first,
          ciphertext: producer.staging.cipher(manifest.segments.first),
        ),
        throwsFormatException,
      );
      for (final segment in manifest.segments) {
        await consumer.staging.importSegment(
          manifest: manifest,
          segment: segment,
          ciphertext: producer.staging.cipher(segment),
        );
      }
      expect(await cold.rows('SELECT * FROM crypto_archive_secrets'), isEmpty);
      expect(
        await consumer.open(
          context: context,
          descriptor: descriptor,
          domainKey: domainKey,
        ),
        witness,
      );
      final wrongKey = crypto.sodium.crypto.secretStream.keygen();
      try {
        await expectLater(
          consumer.open(
            context: context,
            descriptor: descriptor,
            domainKey: wrongKey,
          ),
          throwsFormatException,
        );
      } finally {
        wrongKey.dispose();
      }
      final changed = CryptoMigrationWitnessContext({
        ...context.value,
        'epoch': 2,
      });
      await expectLater(
        consumer.open(
          context: changed,
          descriptor: descriptor,
          domainKey: domainKey,
        ),
        throwsFormatException,
      );
      await expectLater(
        producer.stage(
          context: changed,
          witness: witness,
          domainKey: domainKey,
        ),
        throwsFormatException,
      );
      final first = (await cold.rows(
        'SELECT segment_id,chunk_offset,bytes FROM crypto_archive_chunks ORDER BY chunk_offset LIMIT 1',
      )).single;
      final corrupt = Uint8List.fromList((first['bytes'] as List).cast<int>());
      corrupt[corrupt.length - 1] ^= 1;
      await cold.execute(
        'UPDATE crypto_archive_chunks SET bytes=? WHERE segment_id=? AND chunk_offset=?',
        [corrupt, first['segment_id'], first['chunk_offset']],
      );
      await expectLater(
        consumer.open(
          context: context,
          descriptor: descriptor,
          domainKey: domainKey,
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'public context rejects private scope witness and unrelated address',
    () async {
      final server = crypto.randomId(),
          scope = crypto.randomId(),
          id = crypto.randomId();
      final base = <String, dynamic>{
        'version': 3,
        'purpose': 'migrationWitness',
        'serverId': server,
        'accountId': crypto.randomId(),
        'captureId': crypto.randomId(),
        'migrationId': crypto.randomId(),
        'bindingId': crypto.randomId(),
        'sourceInventoryRoot': 'a' * 64,
        'sourceCommitment': 'b' * 64,
        'scopeId': scope,
        'domain': 'content',
        'epoch': 1,
        'accessRevision': 0,
        'membershipHeadHash': 'c' * 64,
        'type': 'task',
        'sourceKind': 'records',
        'canonicalId': id,
        'wireId': cryptoWireRecordId(server, scope, 'task', id),
      };
      expect(
        () => CryptoMigrationWitnessContext({
          ...base,
          'wireId': crypto.randomId(),
        }),
        throwsFormatException,
      );
      expect(
        () => CryptoMigrationWitnessContext({
          ...base,
          'recordProofHash': 'd' * 64,
        }),
        throwsFormatException,
      );
      final context = CryptoMigrationWitnessContext(base);
      expect(
        () => context.requireSource(
          CryptoCaptureSourceContext(
            serverId: server,
            captureId: base['captureId'],
            migrationId: base['migrationId'],
            accountId: base['accountId'],
            scopeId: scope,
            domain: 'content',
            sourceTable: 'familyhub_scopes',
            sourceId: 'row:0',
          ),
        ),
        throwsFormatException,
      );
    },
  );
}
