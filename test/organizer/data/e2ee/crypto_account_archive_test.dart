import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart' show Sha256;
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/e2ee/crypto_account_archive.dart';
import 'package:kanban/organizer/data/e2ee/crypto_backup_evidence.dart';
import 'package:kanban/organizer/data/e2ee/crypto_codec.dart';
import 'package:sodium/sodium.dart';

void main() {
  late CryptoCodec crypto;
  setUpAll(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    crypto = CryptoCodec(await SodiumInit.init());
  });
  late CollaborationDatabase db;
  late CryptoArchiveStagingStore store;
  late String partition, migration;
  setUp(() {
    db = CollaborationDatabase(NativeDatabase.memory());
    partition = 'synthetic archive partition';
    migration = crypto.randomId();
    store = CryptoArchiveStagingStore(
      database: db,
      partition: partition,
      crypto: crypto,
    );
  });
  tearDown(() => db.close());

  test(
    'durable multi-segment stream reopens through recovery envelope with fresh reader and bounded SQL chunks',
    () async {
      final recovery = crypto.sodium.crypto.box.keyPair();
      addTearDown(recovery.secretKey.dispose);
      final message = Uint8List.fromList(List.generate(65536, (i) => i % 251));
      final expected = Sha256().newHashSink();
      Stream<List<int>> input() async* {
        for (var i = 0; i < 321; i++) {
          expected.add(message);
          yield message;
        }
        expected.close();
      }

      final manifest = await store.stage(
        migrationId: migration,
        plaintext: input(),
      );
      expect(manifest.segments, hasLength(2));
      expect(
        manifest.segments.every((s) => s.size <= 22 * 1024 * 1024),
        isTrue,
      );
      final draft =
          (await db.rows(
                'SELECT key_bytes FROM crypto_archive_secrets',
              )).single['key_bytes']
              as List;
      final raw = Uint8List.fromList(draft.cast<int>());
      final key = crypto.sodium.secureCopy(raw);
      raw.fillRange(0, raw.length, 0);
      final context = <String, dynamic>{
        'version': 2,
        'kind': 'accountArchiveKey',
        'migrationId': migration,
        'keyId': manifest.keyId,
        'cipherManifestHash': manifest.cipherManifestHash,
      };
      final sealed = crypto.sealKey(
        key: key,
        recipientPublicKey: recovery.publicKey,
        context: context,
      );
      key.dispose();
      await db.execute(
        "UPDATE crypto_archive_secrets SET key_bytes=NULL,state='wrapped'",
      );
      final evidence = await exportCryptoEvidence(db, partition);
      expect(jsonEncode(evidence), isNot(contains('key_bytes')));
      final reopened = crypto.openKey(
        sealed: sealed,
        recipient: recovery,
        context: context,
      );
      try {
        final fresh = CryptoArchiveStagingStore(
          database: db,
          partition: partition,
          crypto: crypto,
        );
        final observed = Sha256().newHashSink();
        var bytes = 0, largest = 0;
        await for (final chunk in fresh.open(manifest, reopened)) {
          bytes += chunk.length;
          if (chunk.length > largest) largest = chunk.length;
          observed.add(chunk);
        }
        observed.close();
        expect(bytes, 321 * 65536);
        expect(largest, lessThanOrEqualTo(65536));
        expect((await observed.hash()).bytes, (await expected.hash()).bytes);
        final max = (await db.rows(
          'SELECT MAX(length(bytes)) AS n FROM crypto_archive_chunks',
        )).single['n'];
        expect(max as int, lessThanOrEqualTo(192 * 1024));
      } finally {
        reopened.dispose();
      }
    },
  );

  test(
    'real corrupted secretstream remains evidence and cannot finish cold restore',
    () async {
      final manifest = await store.stage(
        migrationId: migration,
        plaintext: Stream.value(utf8.encode('PRIVATE archive exact bytes')),
      );
      final raw =
          (await db.rows(
                'SELECT key_bytes FROM crypto_archive_secrets',
              )).single['key_bytes']
              as List;
      final key = crypto.sodium.secureCopy(Uint8List.fromList(raw.cast<int>()));
      addTearDown(key.dispose);
      final chunks = await db.rows(
        'SELECT * FROM crypto_archive_chunks ORDER BY chunk_offset',
      );
      final last = chunks.last;
      final changed = Uint8List.fromList((last['bytes'] as List).cast<int>());
      changed[changed.length - 1] ^= 1;
      await db.execute(
        'UPDATE crypto_archive_chunks SET bytes=? WHERE segment_id=? AND chunk_offset=?',
        [changed, last['segment_id'], last['chunk_offset']],
      );
      await expectLater(
        store.open(manifest, key).drain<void>(),
        throwsA(isA<FormatException>()),
      );
      expect(
        await db.rows('SELECT * FROM crypto_archive_chunks'),
        hasLength(chunks.length),
      );
    },
  );

  test(
    'cancelled unpublished draft preserves source and encrypted partial evidence',
    () async {
      var cancelled = false;
      Stream<List<int>> input() async* {
        yield Uint8List(65536);
        cancelled = true;
        yield Uint8List(65536);
      }

      await expectLater(
        store.stage(
          migrationId: migration,
          plaintext: input(),
          cancelled: () => cancelled,
        ),
        throwsA(anything),
      );
      expect(
        await db.rows('SELECT * FROM crypto_archive_secrets'),
        hasLength(1),
      );
      expect(
        (await db.rows(
          'SELECT * FROM crypto_archive_segments',
        )).single['state'],
        'writing',
      );
    },
  );
}
