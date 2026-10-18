import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_transport.dart';
import 'package:kanban/organizer/data/device_session_store.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_store.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_v2_workflow.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_repository.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_v2.dart';
import 'package:kanban/organizer/data/e2ee/crypto_archive_cold_database.dart';
import 'package:kanban/organizer/data/e2ee/crypto_codec.dart';
import 'package:kanban/organizer/data/e2ee/crypto_json.dart';
import 'package:kanban/organizer/data/e2ee/crypto_identity_store.dart';
import 'package:kanban/organizer/data/e2ee/crypto_migration_archive.dart';
import 'package:kanban/organizer/data/e2ee/crypto_business_router.dart';
import 'package:kanban/organizer/data/e2ee/crypto_migration_canonical_stage.dart';
import 'package:kanban/organizer/data/e2ee/crypto_migration_record_source.dart';
import 'package:kanban/organizer/data/e2ee/crypto_migration_stage_verifier.dart';
import 'package:kanban/organizer/data/e2ee/scope_crypto_manager.dart';
import 'package:kanban/organizer/data/e2ee/crypto_migration_coordinator.dart';
import 'package:kanban/organizer/data/e2ee/crypto_sync_repository.dart';
import 'package:kanban/organizer/data/e2ee/crypto_sync_store.dart';
import 'package:kanban/organizer/data/e2ee/session_crypto_access.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:sodium/sodium.dart';

class _Secure implements AccountCryptoStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

class _SyntheticHttp implements CollaborationTransport {
  final _http = HttpCollaborationTransport();
  int _rateRetries = 0;
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
    try {
      return await _http.call(
        serverUrl: serverUrl,
        operation: operation,
        params: params,
        token: token,
        allowLocalHttp: allowLocalHttp,
      );
    } on CollaborationApiException catch (error) {
      final retry = error.details['retryAfter'];
      if (Platform.environment['JIVIE_TEST_RETRY_RATE_LIMITS'] != '1' ||
          error.code != 'rate_limited' ||
          retry is! int ||
          retry < 1 ||
          retry > 60 ||
          _rateRetries++ >= 3) {
        rethrow;
      }
      // Loopback synthetic fixture only; the original request stays byte-exact.
      await Future<void>.delayed(Duration(seconds: retry));
      return call(
        serverUrl: serverUrl,
        operation: operation,
        params: params,
        token: token,
        allowLocalHttp: allowLocalHttp,
      );
    }
  }

  @override
  void close() => _http.close();
}

void main() {
  final path = Platform.environment['JIVIE_MIGRATION_HTTP_FIXTURE'];
  test(
    'real signed migration exports raw source, uploads private archive, downloads into fresh encrypted SQLite and verifies FILE-only cold parity',
    () async {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      final fixture = jsonDecode(await File(path!).readAsString()) as Map;
      if (fixture['synthetic'] != true ||
          Uri.parse(fixture['serverUrl']).host != '127.0.0.1')
        throw StateError('Synthetic loopback only');
      final wire = fixture['session'] as Map,
          user = wire['user'] as Map,
          device = wire['device'] as Map;
      final session = DeviceSession(
        AccountSession(
          serverUrl: fixture['serverUrl'],
          serverId: wire['serverId'],
          accountId: user['accountId'],
          userId: user['id'],
          username: user['username'],
          displayName: user['displayName'],
          deviceId: device['id'],
          expiresAt: DateTime.fromMillisecondsSinceEpoch(
            device['expiresAt'] * 1000,
          ),
          allowLocalHttp: true,
        ),
        wire['token'],
      );
      final db = CollaborationDatabase(NativeDatabase.memory()),
          http = _SyntheticHttp();
      final crypto = CryptoCodec(await SodiumInit.init());
      final account = AccountCryptoV2Workflow(
        AccountDirectoryRepository(
          reducer: AccountDirectoryV2(crypto),
          session: session,
          transport: http,
          store: CryptoIdentityStore(db, _Secure(), session.profile.partition),
          isCurrent: () => true,
        ),
      );
      final coordinator = CryptoMigrationCoordinator(account: account);
      final root = await Directory.systemTemp.createTemp(
        'synthetic-archive-cold-',
      );
      addTearDown(() async {
        await coordinator.close();
        await db.close();
        http.close();
        await root.delete(recursive: true);
      });
      final file = await account.prepareRecoveryFile();
      try {
        await account.verifyAndInitialize(file);
        final prepared = await coordinator.prepare(fixture['scopeId']);
        final id = prepared.migrationId!;
        final review = await coordinator.review(id);
        expect(review.rowCount, greaterThan(2));
        expect(review.fileCount, 1);
        final fenced = await coordinator.fence(
          id,
          reviewedInventoryHash: review.inventoryHash,
        );
        expect(fenced.phase, CryptoMigrationPhase.archiving);
        final access = SessionCryptoAccess(account: account);
        final catalog = await account.directory.call('crypto2.scopes.catalog', {
          'limit': 50,
        });
        final descriptor = (catalog['scopes'] as List).cast<Map>().singleWhere(
          (s) => s['id'] == fixture['scopeId'],
        );
        await ScopeCryptoManager(access).initializeEmptyScope(
          scopeId: fixture['scopeId'],
          accessRevision: descriptor['accessRevision'],
          members: (descriptor['members'] as List).cast<Map<String, dynamic>>(),
        );
        final business = CryptoBusinessSession(account, access, db);
        final stage = CryptoMigrationCanonicalStage(business);
        for (final sourcePair in [
          ('familyhub_scopes', 'content'),
          ('familyhub_records', 'content'),
          ('familyhub_finance_records', 'finance'),
        ]) {
          final (sourceTable, domain) = sourcePair;
          final sourcePage = await account.directory
              .call('crypto2.migration.exportPage', {
                'migrationId': id,
                'table': sourceTable,
                'domain': domain,
                'cursor': 0,
                'limit': 20,
              });
          final sources = <CryptoMigrationRecordSource>[];
          for (final row
              in (sourcePage['rows'] as List).cast<Map<String, dynamic>>()) {
            sources.add(
              await CryptoMigrationRecordSource.decode(
                table: sourceTable,
                domain: domain,
                row: row,
                serverId: session.profile.serverId,
                reservedId: business.reservedRecordId,
              ),
            );
          }
          sources.sort(
            (a, b) => (a.type == 'financeAccount' ? 0 : 1).compareTo(
              b.type == 'financeAccount' ? 0 : 1,
            ),
          );
          for (final source in sources) {
            await stage.stageOne(
              migrationId: id,
              inventoryHash: review.inventoryHash,
              source: source,
            );
            // Same source retries must retain exact ciphertext, even after ACK.
            await stage.stageOne(
              migrationId: id,
              inventoryHash: review.inventoryHash,
              source: source,
            );
          }
        }
        expect(
          await db.rows('SELECT * FROM crypto_migration_staged_records'),
          hasLength(7),
        );
        expect(await db.rows('SELECT * FROM crypto_business_records'), isEmpty);
        final read = await access.readContext(fixture['scopeId'], 'content');
        final active = await account.directory.call('crypto2.records.pull', {
          'scopeId': fixture['scopeId'],
          'domain': 'content',
          'accessRevision': read.accessRevision,
          'cursor': 0,
        });
        expect(active['records'], isEmpty);
        final queue = CryptoSyncRepository(
          crypto: crypto,
          session: session,
          transport: http,
          store: CryptoSyncStore(db, session.profile.partition),
          signingKey: access.signingKey,
          authorKey: access.recordAuthority,
          contentKey: access.recordKey,
          readContext: access.readContext,
          beforeDelivery: access.beforeDelivery,
          project: (_) async => throw const CryptoProjectionPending(),
          isCurrent: () => true,
        );
        var isolatedCount = 0;
        final archive = CryptoMigrationArchive(
          account: account,
          queue: queue,
          verifyColdBusiness: (cold, coldAccount, header) async {
            // Scope DEKs come only from the external file and signed server
            // wrappers in this blank SQL database, never from live/staging keys.
            expect(
              await cold.database.rows('SELECT * FROM crypto_scope_keys'),
              isEmpty,
            );
            final coldAccess = SessionCryptoAccess(account: coldAccount);
            await coldAccess.recoverScopeCandidateKeys(
              fixture['scopeId'],
              file,
            );
            final runtime = CryptoBusinessSession(
              coldAccount,
              coldAccess,
              cold.database,
            );
            final verifier = CryptoMigrationStageVerifier(runtime);
            var count = 0;
            for (final domain in ['content', 'finance']) {
              final stages = await coldAccount.directory
                  .call('crypto2.migration.stagedRecords', {
                    'migrationId': id,
                    'scopeId': fixture['scopeId'],
                    'domain': domain,
                    'limit': 20,
                  });
              expect(stages['hasMore'], isFalse);
              final ordered = (stages['stages'] as List).cast<Map>().toList();
              int rank(Map stage) {
                final proof = stage['authorization'] as Map;
                final command =
                    CryptoJson.decode(cryptoBase64(proof['commandBase64']))
                        as Map;
                final binding =
                    (command['payload']['sourceBindings'] as List).first as Map;
                return binding['type'] == 'scopeMetadata'
                    ? -1
                    : binding['type'] == 'financeAccount'
                    ? 0
                    : 1;
              }

              ordered.sort((a, b) => rank(a).compareTo(rank(b)));
              for (final stage in ordered) {
                final bindings = <String, CryptoMigrationRecordSource>{};
                final verified = await verifier.verify(
                  migrationId: id,
                  authorization: Map<String, dynamic>.from(
                    stage['authorization'] as Map,
                  ),
                  source: (binding) async {
                    final scopeColumn =
                        binding['sourceTable'] == 'familyhub_scopes'
                        ? 'id'
                        : 'scope_id';
                    final rows = await cold.database.rows(
                      "SELECT raw FROM crypto_cold_rows WHERE table_key=? AND json_extract(raw,'\$.id.valueBase64')=? AND json_extract(raw,'\$.$scopeColumn.valueBase64')=?",
                      [
                        '${binding['sourceTable']}:${binding['domain']}',
                        base64Encode(utf8.encode(binding['sourceId'])),
                        base64Encode(utf8.encode(binding['scopeId'])),
                      ],
                    );
                    expect(rows, hasLength(1));
                    final source = await CryptoMigrationRecordSource.decode(
                      table: binding['sourceTable'],
                      domain: binding['domain'],
                      row: Map<String, dynamic>.from(
                        jsonDecode(rows.single['raw'] as String) as Map,
                      ),
                      serverId: session.profile.serverId,
                      reservedId: runtime.reservedRecordId,
                    );
                    bindings[binding['wireId']] = source;
                    return source;
                  },
                );
                try {
                  await cold.database.transaction(() async {
                    await runtime.project(verified);
                  });
                  count += verified.length;
                } finally {
                  for (final record in verified) {
                    record.plaintext?.fillRange(0, record.plaintext!.length, 0);
                  }
                }
              }
            }
            expect(count, 7);
            final metadataId = await runtime.reservedRecordId(
              fixture['scopeId'],
              'scopeMetadata',
            );
            final metadata = (await runtime.record(
              fixture['scopeId'],
              'content',
              metadataId,
              type: 'scopeMetadata',
            ))!;
            expect(metadata['legacy_revision'], 0);
            expect(metadata['revision_namespace'], 'legacy');
            expect(jsonDecode(metadata['projection'] as String)['revision'], 0);
            final task = (await runtime.record(
              fixture['scopeId'],
              'content',
              fixture['taskId'],
              type: 'task',
            ))!;
            expect(task['crypto_revision'], 1);
            expect(task['legacy_revision'], 50);
            expect(
              jsonDecode(task['raw_payload'] as String),
              jsonDecode(fixture['payload']),
            );
            final deleted = (await runtime.record(
              fixture['scopeId'],
              'content',
              fixture['deletedId'],
              type: 'task',
            ))!;
            expect(deleted['deleted'], 1);
            expect(deleted['legacy_revision'], 7);
            final expense = (await runtime.record(
              fixture['scopeId'],
              'finance',
              fixture['expenseId'],
              type: 'financeEntry',
            ))!;
            expect(expense['crypto_revision'], 1);
            expect(expense['legacy_revision'], 31);
            expect(
              jsonDecode(expense['raw_payload'] as String),
              jsonDecode(fixture['entryPayload']),
            );
            expect(jsonDecode(expense['projection'] as String)['revision'], 31);
            expect(
              (await cold.database.rows(
                "SELECT COUNT(*) AS n FROM crypto_business_records WHERE domain='finance' AND type='financeEntry'",
              )).single['n'],
              1,
            );

            expect(
              await cold.database.rows('SELECT * FROM crypto_identity_secrets'),
              isEmpty,
            );
            expect(
              await cold.database.rows('SELECT * FROM crypto_outbox'),
              isEmpty,
            );
          },
          coldDatabase: () async {
            isolatedCount++;
            final cold = await CryptoArchiveColdDatabase.create(parent: root);
            expect(
              await cold.database.rows('SELECT * FROM crypto_identity_secrets'),
              isEmpty,
            );
            expect(
              await cold.database.rows('SELECT * FROM crypto_archive_secrets'),
              isEmpty,
            );
            return cold;
          },
        );
        final result = await archive.archiveAndVerify(id, file);
        expect(result['state'], 'verified');
        expect(result['ownState'], 'verified');
        expect(isolatedCount, 1);
        expect(await root.list().toList(), isEmpty);
        expect(
          (await db.rows(
            'SELECT * FROM crypto_archive_secrets',
          )).single['key_bytes'],
          isNull,
        );
        expect(
          (await db.rows('SELECT * FROM crypto_archive_jobs')).single['state'],
          'verified',
        );
        final receipt = await account.directory.call('crypto2.legacy.lookup', {
          'scopeId': fixture['scopeId'],
          'legacyId': fixture['legacyId'],
          'finance': false,
          'requestHash': 'a' * 64,
        });
        expect(receipt['outcome'], 'applied');
        final newLogin = await http.call(
          serverUrl: fixture['serverUrl'],
          operation: 'auth.login',
          params: {
            'username': fixture['username'],
            'password': fixture['password'],
            'deviceName': 'Synthetic NEW recovery device',
          },
          allowLocalHttp: true,
        );
        final newUser = newLogin['user'] as Map,
            newDevice = newLogin['device'] as Map;
        final newSession = DeviceSession(
          AccountSession(
            serverUrl: fixture['serverUrl'],
            serverId: newLogin['serverId'],
            accountId: newUser['accountId'],
            userId: newUser['id'],
            username: newUser['username'],
            displayName: newUser['displayName'],
            deviceId: newDevice['id'],
            expiresAt: DateTime.fromMillisecondsSinceEpoch(
              newDevice['expiresAt'] * 1000,
            ),
            allowLocalHttp: true,
          ),
          newLogin['token'],
        );
        final recoveredAccount = AccountCryptoV2Workflow(
          AccountDirectoryRepository(
            reducer: account.directory.reducer,
            session: newSession,
            transport: http,
            store: CryptoIdentityStore(
              db,
              account.store.secure,
              newSession.profile.partition,
            ),
            isCurrent: () => true,
          ),
        );
        final nextFile = await recoveredAccount.prepareRootReplacement(file);
        final newAccess = SessionCryptoAccess(account: recoveredAccount);
        final recoveredQueue = CryptoSyncRepository(
          crypto: crypto,
          session: newSession,
          transport: http,
          store: CryptoSyncStore(db, newSession.profile.partition),
          signingKey: newAccess.signingKey,
          authorKey: newAccess.recordAuthority,
          contentKey: newAccess.recordKey,
          readContext: newAccess.readContext,
          beforeDelivery: newAccess.beforeDelivery,
          project: (_) async => throw const CryptoProjectionPending(),
          isCurrent: () => true,
        );
        try {
          await recoveredAccount.verifyAndRotateRoot(
            oldExternalFile: file,
            newExternalFile: nextFile,
          );
          final afterRootReplacement = await CryptoMigrationArchive(
            account: recoveredAccount,
            queue: recoveredQueue,
            coldDatabase: () async {
              isolatedCount++;
              return CryptoArchiveColdDatabase.create(parent: root);
            },
          ).archiveAndVerify(id, nextFile);
          expect(afterRootReplacement['state'], 'verified');
          expect(isolatedCount, 2);
          expect(await root.list().toList(), isEmpty);
        } finally {
          nextFile.fillRange(0, nextFile.length, 0);
        }
        // No destructive cutover is claimed until actual business projection parity.
        final current = await recoveredAccount.directory.call(
          'crypto2.migration.inventory',
          {'migrationId': id},
        );
        final commit = await recoveredQueue.enqueueCommand(
          actionKey: 'commit-gap',
          operation: 'crypto2.migration.commit',
          payload: {
            'migrationId': id,
            'inventoryHash': review.inventoryHash,
            'expectedComponentHash':
                (current['inventory'] as Map)['componentHash'],
          },
        );
        await recoveredQueue.deliver();
        final rejected = (await db.rows(
          'SELECT state,response FROM crypto_outbox WHERE request_id=?',
          [commit],
        )).single;
        expect(rejected['state'], 'rejected');
        expect(rejected['response'], contains('crypto_cutover_not_supported'));
      } finally {
        file.fillRange(0, file.length, 0);
      }
    },
    skip: path == null,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
