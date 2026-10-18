import 'dart:convert';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/e2ee/crypto_account_archive.dart';
import 'package:kanban/organizer/data/e2ee/crypto_capture_keys.dart';
import 'package:kanban/organizer/data/e2ee/crypto_codec.dart';
import 'package:kanban/organizer/data/e2ee/crypto_json.dart';
import 'package:kanban/organizer/data/e2ee/crypto_migration_local_intents.dart';
import 'package:sodium/sodium.dart';

void main() {
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });
  test(
    'current account snapshot keeps exact paired requests and excludes foreign/accountless secrets',
    () async {
      final db = CollaborationDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final crypto = CryptoCodec(await SodiumInit.init());
      const own = 'own-account', foreign = 'foreign-account';
      final scope = crypto.randomId();
      for (final p in [own, foreign]) {
        await db.execute('INSERT INTO accounts VALUES(?,?)', [p, '{}']);
        await db.execute(
          'INSERT INTO scopes(partition,id,data) VALUES(?,?,?)',
          [p, scope, '{}'],
        );
        await db.execute('INSERT INTO records VALUES(?,?,?,?,?,?,?,?,?)', [
          p,
          scope,
          scope,
          'task',
          1,
          0,
          '{}',
          0,
          null,
        ]);
        await db.execute(
          'INSERT INTO outbox(op_id,partition,scope_id,record_id,request) VALUES(?,?,?,?,?)',
          [
            crypto.randomId(),
            p,
            scope,
            scope,
            p == own
                ? ' {"opId":"original", "unknown":0.1} '
                : 'FOREIGN REQUEST SECRET',
          ],
        );
        await db.execute(
          'INSERT INTO finance_outbox(op_id,partition,scope_id,record_id,request) VALUES(?,?,?,?,?)',
          [
            crypto.randomId(),
            p,
            scope,
            scope,
            p == own
                ? ' {"opId":"paired-original"} '
                : 'FOREIGN FINANCE SECRET',
          ],
        );
        await db.execute('INSERT INTO crypto_export_drafts VALUES(?,?,?,?)', [
          p,
          scope,
          crypto.randomId(),
          jsonEncode({
            'private': p == own ? 'OWN PRIVATE DRAFT' : 'FOREIGN EXPORT SECRET',
          }),
        ]);
        await db.execute('INSERT INTO local_meta VALUES(?,?)', [
          'task_cost_pair:$p:original',
          p == own ? 'paired-original' : 'FOREIGN PAIR SECRET',
        ]);
        await db.execute('INSERT INTO linked_payment_intents VALUES(?,?,?)', [
          crypto.randomId(),
          jsonEncode({'partition': p, 'unknown': 'original'}),
          'pending',
        ]);
      }
      for (final p in [own, foreign]) {
        final id = crypto.randomId();
        await db.execute(
          'INSERT INTO crypto_outbox(partition,request_id,operation,signed_body,request_hash,state,response) VALUES(?,?,?,?,?,?,?)',
          [
            p,
            id,
            'crypto2.records.batch',
            jsonEncode({
              'commandBase64': base64Encode(
                CryptoJson.encode({
                  'requestId': id,
                  'operation': 'crypto2.records.batch',
                  'serverId': 'server',
                  'accountId': p,
                }),
              ),
            }),
            'a' * 64,
            'applied',
            p == own
                ? ' EXACT ORIGINAL CRYPTO ACK '
                : 'FOREIGN CRYPTO RECEIPT SECRET',
          ],
        );
        await db.execute('INSERT INTO crypto_command_keys VALUES(?,?,?,?)', [
          p,
          'original-business-action',
          id,
          'b' * 64,
        ]);
      }
      await db.execute(
        'INSERT INTO crypto_outbox(partition,request_id,operation,signed_body,request_hash) VALUES(?,?,?,?,?)',
        [
          own,
          crypto.randomId(),
          'crypto2.migration.verify3',
          'THIS WORKFLOW MUST NOT SELF-ARCHIVE',
          'c' * 64,
        ],
      );
      await db.execute('INSERT INTO local_meta VALUES(?,?)', [
        'session:$own',
        'SESSION TOKEN SECRET',
      ]);
      await db.execute('INSERT INTO local_meta VALUES(?,?)', [
        'installation_key',
        'INSTALLATION SECRET',
      ]);
      await db.execute('INSERT INTO linked_payment_intents VALUES(?,?,?)', [
        crypto.randomId(),
        jsonEncode({'partition': null, 'unknown': 'ACCOUNTLESS SECRET'}),
        'pending',
      ]);
      await db.execute('INSERT INTO linked_payment_intents VALUES(?,?,?)', [
        crypto.randomId(),
        'FOREIGN MALFORMED NO ACCOUNT BINDING',
        'pending',
      ]);
      final capture = CryptoCaptureKeyDescriptor(
        captureId: crypto.randomId(),
        migrationId: crypto.randomId(),
        keyId: crypto.randomId(),
        rootScopeId: scope,
        componentId: scope,
        scopeIds: [scope],
        receiptSelections: [],
      );
      final restoredOwn = crypto.randomId(),
          restoredForeign = crypto.randomId();
      await db.execute('INSERT INTO restored_backups VALUES(?,?,?,?)', [
        restoredOwn,
        'now',
        own,
        jsonEncode({
          'cryptoPrivateDrafts': {
            'version': 1,
            'partition': own,
            'tables': {
              'crypto_export_drafts': [
                {
                  'partition': own,
                  'scope_id': scope,
                  'action_id': crypto.randomId(),
                  'payload': '{"private":"OWN RESTORED DRAFT"}',
                },
              ],
            },
            'restoredCandidates': [
              {
                'backupId': restoredForeign,
                'partition': foreign,
                'tables': {
                  'crypto_export_drafts': [
                    {
                      'partition': foreign,
                      'scope_id': scope,
                      'action_id': crypto.randomId(),
                      'payload': '{"private":"FOREIGN NESTED SECRET"}',
                    },
                  ],
                },
              },
            ],
          },
        }),
      ]);
      await db.execute('INSERT INTO restored_backups VALUES(?,?,?,?)', [
        crypto.randomId(),
        'now',
        foreign,
        'FOREIGN MALFORMED BACKUP',
      ]);
      final snapshot = CryptoMigrationLocalIntentSnapshot(
        database: db,
        partition: own,
        capture: capture,
        sourceInventoryRoot: 'a' * 64,
      );
      final bytes = <int>[];
      await for (final part in snapshot.frames(artifactId: crypto.randomId())) {
        bytes.addAll(part);
      }
      final text = utf8.decode(bytes);
      final frames = text
          .trim()
          .split('\n')
          .map((l) => jsonDecode(l) as Map)
          .toList();
      expect(
        frames.where((f) => f['table'] == 'outbox').single['row']['request'],
        ' {"opId":"original", "unknown":0.1} ',
      );
      expect(text, contains('paired-original'));
      expect(text, contains(' EXACT ORIGINAL CRYPTO ACK '));
      expect(text, isNot(contains('FOREIGN CRYPTO RECEIPT SECRET')));
      expect(text, isNot(contains('THIS WORKFLOW MUST NOT SELF-ARCHIVE')));
      expect(frames.where((f) => f['kind'] == 'cryptoReceiptRow').length, 2);
      expect(text, contains('OWN PRIVATE DRAFT'));
      expect(text, contains('OWN RESTORED DRAFT'));
      expect(text, isNot(contains('FOREIGN NESTED SECRET')));
      expect(
        await db.rows('SELECT 1 FROM crypto_local_intent_candidates'),
        isEmpty,
      );
      for (final value in [
        'FOREIGN REQUEST SECRET',
        'FOREIGN FINANCE SECRET',
        'FOREIGN EXPORT SECRET',
        'FOREIGN PAIR SECRET',
        'SESSION TOKEN SECRET',
        'INSTALLATION SECRET',
        'ACCOUNTLESS SECRET',
      ]) {
        expect(text, isNot(contains(value)));
      }
      expect(frames.last['intentCount'], frames.length - 2);
      expect((await db.rows('SELECT COUNT(*) n FROM outbox')).single['n'], 2);
      final store = CryptoArchiveStagingStore(
        database: db,
        partition: own,
        crypto: crypto,
      );
      final artifactId = crypto.randomId();
      final context = {
        'version': 3,
        'serverId': crypto.randomId(),
        'migrationId': capture.migrationId,
        'captureId': capture.captureId,
        'accountId': crypto.randomId(),
        'sourceInventoryRoot': 'a' * 64,
        'artifactId': artifactId,
        'purpose': 'migrationLocalIntents',
      };
      final manifest = await store.stage(
        migrationId: capture.migrationId,
        artifactId: artifactId,
        artifactKind: 'migrationLocalIntentsV3',
        artifactContext: context,
        plaintext: Stream.value(bytes),
      );
      expect(
        CryptoArchiveManifest.fromJson(manifest.toJson()).artifactContext,
        context,
      );
      await expectLater(
        store.stage(
          migrationId: capture.migrationId,
          artifactId: artifactId,
          artifactKind: 'migrationLocalIntentsV3',
          artifactContext: {...context, 'sourceInventoryRoot': 'b' * 64},
          plaintext: const Stream.empty(),
        ),
        throwsFormatException,
      );
    },
  );
}
