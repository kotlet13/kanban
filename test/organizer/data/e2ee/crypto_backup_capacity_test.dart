import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:sodium/sodium.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/sqlite_organizer_storage.dart';
import 'package:kanban/organizer/data/portable_backup_repository.dart';
import 'package:kanban/organizer/data/portable_backup_crypto.dart';
import 'package:kanban/organizer/data/portable_backup_document.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:kanban/organizer/data/e2ee/crypto_codec.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_v2.dart';
import 'package:kanban/organizer/data/e2ee/crypto_record_proof_codec.dart';
import 'package:kanban/organizer/data/e2ee/crypto_record_address.dart';
import 'package:kanban/organizer/data/e2ee/crypto_document_blob.dart';
import 'package:kanban/organizer/data/e2ee/crypto_document_backup_drafts.dart';
import 'package:kanban/organizer/data/e2ee/crypto_document_backup_recovery.dart';
import 'package:kanban/organizer/data/e2ee/crypto_backup_command_codec.dart';
import 'package:kanban/organizer/data/e2ee/crypto_inventory_json.dart';
import 'package:kanban/organizer/data/e2ee/crypto_json.dart';

void main() {
  test(
    'three current/pending file objects use one cipher each through encrypted portable restore',
    () async {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      final crypto = CryptoCodec(await SodiumInit.init()),
          codec = CryptoRecordProofCodec(crypto);
      final signer = crypto.sodium.crypto.sign.keyPair(),
          dek = crypto.sodium.crypto.secretStream.keygen();
      addTearDown(signer.dispose);
      addTearDown(dek.dispose);
      final db = CollaborationDatabase(NativeDatabase.memory()),
          restored = CollaborationDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      addTearDown(restored.close);
      final storage = SqliteOrganizerStorage(db),
          target = SqliteOrganizerStorage(restored);
      await storage.initialize();
      await target.initialize();
      final server = crypto.randomId(),
          actor = crypto.randomId(),
          device = crypto.randomId(),
          scope = crypto.randomId();
      final profile = AccountSession(
        serverUrl: 'https://synthetic.invalid/',
        serverId: server,
        accountId: actor,
        userId: 1,
        username: 'synthetic',
        displayName: 'Synthetic',
        deviceId: device,
        expiresAt: DateTime.utc(2030),
      );
      db.activatePersonal(profile);
      final p = profile.partition;
      final size = Platform.environment['JIVIE_BACKUP_FULL_CAPACITY'] == '1'
          ? 20 * 1024 * 1024
          : 64 * 1024;
      final original = Uint8List.fromList(
        List.generate(size, (i) => (i * 31 + 7) & 255),
      );
      final plainHash = await cryptoSha256(original);
      final descriptors = <Map<String, dynamic>>[],
          jobs = <String>[],
          records = <String>[],
          originals = <String, ({String hash, String body})>{};
      for (var n = 0; n < 3; n++) {
        print('Capacity object ${n + 1}/3: $size plaintext bytes');
        final id = crypto.randomId(),
            record = crypto.randomId(),
            key = crypto.sodium.crypto.secretStream.keygen();
        jobs.add(id);
        records.add(record);
        final builder = BytesBuilder(copy: false);
        await for (final chunk in crypto.sodium.crypto.secretStream.pushChunked(
          messageStream: (() async* {
            yield utf8.encode('JivieObject/v2\n');
            yield original;
          })().cast<List<int>>(),
          key: key,
          chunkSize: 65536,
        )) {
          builder.add(chunk);
        }
        final cipher = builder.takeBytes(), rawKey = key.extractBytes();
        key.dispose();
        final manifestPlain = CryptoJson.encode({
          'version': 2,
          'objectKeyBase64': base64Encode(rawKey),
          'plainSize': size,
          'plainSha256': plainHash,
          'streamChunkBytes': 65536,
        });
        rawKey.fillRange(0, rawKey.length, 0);
        final binding = {
          'version': 2,
          'purpose': 'documentObject',
          'serverId': server,
          'scopeId': scope,
          'id': id,
          'domain': 'content',
          'epoch': 1,
          'membershipHeadHash': 'a' * 64,
        };
        final descriptor = <String, dynamic>{
          'version': 2,
          'id': id,
          'scopeId': scope,
          'domain': 'content',
          'epoch': 1,
          'accessRevision': 0,
          'membershipHeadHash': 'a' * 64,
          'cipherSize': cipher.length,
          'cipherSha256': await cryptoSha256(cipher),
          'manifestBase64': base64Encode(
            CryptoJson.encode(
              crypto.encrypt(
                plaintext: manifestPlain,
                key: dek,
                context: binding,
              ),
            ),
          ),
        };
        manifestPlain.fillRange(0, manifestPlain.length, 0);
        descriptors.add(descriptor);
        final sourceHash = await CryptoInventoryJson.hash({
          'scopeId': scope,
          'recordId': record,
          'operationId': record,
          'kind': 'attachment',
          'domain': 'content',
          'plainSha256': plainHash,
        });
        await db.execute(
          'INSERT INTO crypto_document_jobs VALUES(?,?,?,?,?,?,?,?,?)',
          [
            p,
            scope,
            id,
            record,
            record,
            'attachment',
            jsonEncode(descriptor),
            n == 2 ? 'staged' : 'complete',
            sourceHash,
          ],
        );
        for (var offset = 0; offset < cipher.length; offset += 196608) {
          final chunk = Uint8List.sublistView(
            cipher,
            offset,
            (offset + 196608).clamp(0, cipher.length),
          );
          await db.execute(
            'INSERT INTO crypto_document_chunks VALUES(?,?,?,?)',
            [p, id, offset, chunk],
          );
          final request = crypto.randomId();
          final command = {
            'version': 2,
            'operation': 'crypto2.blob.chunk',
            'requestId': request,
            'serverId': server,
            'accountId': actor,
            'deviceId': device,
            'signer': 'device',
            'payload': {
              'scopeId': scope,
              'id': id,
              'domain': 'content',
              'epoch': 1,
              'accessRevision': 0,
              'membershipHeadHash': 'a' * 64,
              'offset': offset,
              'dataBase64': base64Encode(chunk),
            },
          };
          final signed = codec.signCommand(command, signer.secretKey),
              hash = await cryptoSha256(
                cryptoBase64(
                  codec.signCommand(command, signer.secretKey)['commandBase64'],
                ),
              );
          final body = utf8.decode(CryptoJson.encode(signed));
          final receipt = n == 0
              ? utf8.decode(
                  CryptoJson.encode({
                    'requestId': request,
                    'requestHash': hash,
                    'authorization': signed,
                    'status': 200,
                    'response': {'received': offset + chunk.length},
                  }),
                )
              : null;
          await db.execute(
            'INSERT INTO crypto_outbox(partition,request_id,operation,signed_body,request_hash,state,response) VALUES(?,?,?,?,?,?,?)',
            [
              p,
              request,
              'crypto2.blob.chunk',
              body,
              hash,
              n == 0 ? 'applied' : 'pending',
              receipt,
            ],
          );
          if (offset == 0) originals[request] = (hash: hash, body: body);
        }
        if (n == 0) {
          final address = CryptoRecordAddress.forType(
            serverId: server,
            scopeId: scope,
            type: 'attachment',
            canonicalId: record,
          );
          final proof = codec.sealRecord(
            serverId: server,
            accountId: actor,
            deviceId: device,
            batchId: crypto.randomId(),
            scopeId: scope,
            id: address.wireId,
            type: 'attachment',
            expectedRevision: 0,
            epoch: 1,
            accessRevision: 0,
            membershipHeadHash: 'a' * 64,
            domain: 'content',
            contentContract: 6,
            operationId: record,
            previousRecordHash: '0' * 64,
            deleted: false,
            plaintext: Uint8List.fromList(
              utf8.encode(
                jsonEncode({
                  'format': 2,
                  'identity': address.identity,
                  'payload': {'cryptoBlob': descriptor},
                }),
              ),
            ),
            metadata: {
              'identity': address.identity,
              'references': [],
              'uniqueRefs': [],
              'blobIds': [id],
            },
            contentKey: dek,
            signingKey: signer.secretKey,
          );
          final wire = {
            'id': address.wireId,
            'revision': 1,
            'authorization': {'recordProof': proof},
          };
          final hash = await codec.digest(proof);
          await db.execute(
            "INSERT INTO crypto_received(partition,scope_id,domain,record_id,revision,sequence,wire,verdict) VALUES(?,?,'content',?,1,1,?,'verified')",
            [p, scope, address.wireId, jsonEncode(wire)],
          );
          await db.execute(
            "INSERT INTO crypto_business_records(partition,scope_id,domain,id,type,crypto_revision,record_proof_hash,deleted,raw_payload,projection,history_basis) VALUES(?,?,'content',?,'attachment',1,?,0,'{}','{}','verifiedCheckpoint')",
            [p, scope, address.wireId, hash],
          );
        }
      }
      // Complete plaintext remains after record ACK loss, and must be represented
      // exactly once only after actual cipher decryption succeeds.
      final upload = records.last;
      await db.execute(
        'INSERT INTO crypto_document_uploads VALUES(?,?,?,?,?,?)',
        [
          p,
          scope,
          upload,
          jsonEncode({
            'name': 'pending-private.pdf',
            'size': size,
            'sha256': plainHash,
          }),
          size,
          'receiving',
        ],
      );
      for (var offset = 0; offset < size; offset += 262144) {
        await db.execute(
          'INSERT INTO crypto_document_upload_chunks VALUES(?,?,?,?)',
          [
            p,
            upload,
            offset,
            Uint8List.sublistView(
              original,
              offset,
              (offset + 262144).clamp(0, size),
            ),
          ],
        );
      }
      Future<Uint8List> decrypt(
        Map<String, dynamic> descriptor,
        Uint8List cipher,
      ) => decryptCryptoDocumentCipher(
        crypto,
        descriptor,
        dek,
        cipher,
        serverId: server,
      );
      final pendingJob = jobs.last;
      final sourceRow = (await db.rows(
        'SELECT source_hash FROM crypto_document_jobs WHERE partition=? AND id=?',
        [p, pendingJob],
      )).single;
      await db.execute(
        'UPDATE crypto_document_jobs SET source_hash=? WHERE partition=? AND id=?',
        ['0' * 64, p, pendingJob],
      );
      expect(await verifyCryptoUploadRecoveries(db, p, decrypt), isEmpty);
      expect(
        (await db.rows(
          'SELECT COUNT(*) n FROM crypto_document_upload_chunks',
        )).single['n'],
        greaterThan(0),
      );
      await db.execute(
        'UPDATE crypto_document_jobs SET source_hash=? WHERE partition=? AND id=?',
        [sourceRow['source_hash'], p, pendingJob],
      );
      final originalChunk =
          (await db.rows(
                'SELECT cipher FROM crypto_document_chunks WHERE partition=? AND id=? AND offset=0',
                [p, pendingJob],
              )).single['cipher']
              as Uint8List;
      final changed = Uint8List.fromList(originalChunk)..[0] ^= 1;
      await db.execute(
        'UPDATE crypto_document_chunks SET cipher=? WHERE partition=? AND id=? AND offset=0',
        [changed, p, pendingJob],
      );
      expect(await verifyCryptoUploadRecoveries(db, p, decrypt), isEmpty);
      await db.execute(
        'UPDATE crypto_document_chunks SET cipher=? WHERE partition=? AND id=? AND offset=0',
        [originalChunk, p, pendingJob],
      );
      expect(
        await verifyCryptoUploadRecoveries(
          db,
          p,
          (d, c) async => throw const FormatException('key missing'),
        ),
        isEmpty,
      );
      expect(
        (await db.rows(
          'SELECT COUNT(*) n FROM crypto_document_upload_chunks',
        )).single['n'],
        greaterThan(0),
      );
      final backup = PortableBackupRepository(
        db,
        storage,
        MemoryBackupUiPreferencesStore(),
        documentDraftDecryptor: decrypt,
      );
      const password = 'synthetic capacity backup password';
      if (size == 20 * 1024 * 1024) {
        final offline = PortableBackupRepository(
          db,
          storage,
          MemoryBackupUiPreferencesStore(),
          documentDraftDecryptor: (d, c) async =>
              throw const FormatException('no fresh keys'),
        );
        await expectLater(
          offline.exportEncryptedBackup(password),
          throwsA(
            isA<CollaborationException>().having(
              (e) => e.code,
              'code',
              'backup_pending_files_need_access',
            ),
          ),
        );
        // Accountless local backup still works and does not pull another account's drafts.
        db.activatePersonal(null);
        final local = await offline.exportEncryptedBackup(password);
        final localDoc = await offline.crypto.decrypt(local, password);
        expect(
          localDoc['cryptoPrivateDrafts']['tables']['crypto_document_jobs'],
          isEmpty,
        );
        db.activatePersonal(profile);
      }
      print('Capacity: encoding verified deduplicated snapshot');
      final encrypted = await backup.exportEncryptedBackup(password);
      print('Capacity: encrypted container ${encrypted.length} bytes');
      expect(
        encrypted.length,
        lessThanOrEqualTo(PortableBackupCrypto.maxBytes),
      );
      final doc = await backup.crypto.decrypt(encrypted, password);
      validateBackupDocument(doc);
      expect(
        utf8.encode(jsonEncode(doc)).length,
        lessThanOrEqualTo(PortableBackupCrypto.maxPlainBytes),
      );
      final drafts = doc['cryptoPrivateDrafts'] as Map;
      expect((drafts['tables']['crypto_document_jobs'] as List), hasLength(3));
      expect(drafts['tables']['crypto_document_upload_chunks'], isEmpty);
      expect(drafts['tables'][cryptoDocumentRecoverySourceTable], hasLength(1));
      final commandCodec = CryptoBackupCommandCodec(
        Map<String, dynamic>.from(drafts),
        p,
      );
      final outbox = doc['cryptoEvidence']['tables']['crypto_outbox'] as List;
      for (final entry in originals.entries) {
        final row = outbox.singleWhere((r) => r['request_id'] == entry.key);
        expect(
          await commandCodec.expandSigned(
            row['signed_body'],
            requestHash: entry.value.hash,
          ),
          entry.value.body,
        );
      }
      final destination = PortableBackupRepository(
        restored,
        target,
        MemoryBackupUiPreferencesStore(),
      );
      await destination.restoreEncryptedBackup(
        encrypted,
        password,
        mode: BackupRestoreMode.replace,
        expectedPersonalRevision: (await target.read()).revision,
      );
      print('Capacity: restored encrypted SQL quarantine');
      expect(await restored.rows('SELECT * FROM crypto_outbox'), isEmpty);
      expect(
        await restored.rows('SELECT * FROM crypto_document_jobs'),
        isEmpty,
      );
      final retained =
          jsonDecode(
                (await restored.rows(
                      'SELECT data FROM restored_backups',
                    )).single['data']
                    as String,
              )
              as Map;
      final private = retained['cryptoPrivateDrafts'] as Map;
      for (final rawJob in private['tables']['crypto_document_jobs'] as List) {
        final job = rawJob as Map,
            descriptor = Map<String, dynamic>.from(
              jsonDecode(job['descriptor']) as Map,
            );
        final chunks =
            (private['tables']['crypto_document_chunks'] as List)
                .where((r) => r['id'] == job['id'])
                .toList()
              ..sort(
                (a, b) => (a['offset'] as int).compareTo(b['offset'] as int),
              );
        final builder = BytesBuilder(copy: false);
        for (final c in chunks) {
          builder.add(decodeCryptoDocumentDraftBlob(c['cipher']));
        }
        final bytes = await decrypt(descriptor, builder.takeBytes());
        await validateRecoveredCryptoUploadSources(
          private['tables'] as Map,
          job,
          bytes,
        );
        expect(bytes.length, size);
        expect(await cryptoSha256(bytes), plainHash);
        bytes.fillRange(0, bytes.length, 0);
      }
      // Export never deletes originals or turns an unresolved operation into ACK.
      expect(
        (await db.rows(
          'SELECT COUNT(*) n FROM crypto_document_upload_chunks',
        )).single['n'],
        greaterThan(0),
      );
      expect(
        (await db.rows(
          "SELECT COUNT(*) n FROM crypto_outbox WHERE state='pending'",
        )).single['n'],
        greaterThan(0),
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
