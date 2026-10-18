import 'dart:convert';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_transport.dart';
import 'package:kanban/organizer/data/device_session_store.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_store.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_v2_workflow.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_repository.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_v2.dart';
import 'package:kanban/organizer/data/e2ee/crypto_codec.dart';
import 'package:kanban/organizer/data/e2ee/crypto_identity_store.dart';
import 'package:kanban/organizer/data/e2ee/crypto_sync_repository.dart';
import 'package:kanban/organizer/data/e2ee/session_crypto_access.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:sodium/sodium.dart' show SodiumInit;

import 'package:kanban/organizer/data/e2ee/crypto_archive_cold_database.dart';
import 'package:kanban/organizer/data/e2ee/crypto_capture_archive.dart';
import 'package:kanban/organizer/data/e2ee/crypto_capture_coordinator.dart';
import 'package:kanban/organizer/data/e2ee/crypto_capture_v3.dart';
import 'package:kanban/organizer/data/e2ee/crypto_business_router.dart';
import 'package:kanban/organizer/data/e2ee/crypto_migration_cold_business.dart';
import 'package:kanban/organizer/data/e2ee/crypto_migration_cold_controls.dart';
import 'package:kanban/organizer/data/e2ee/crypto_migration_invitation_control.dart';
import 'package:kanban/organizer/data/e2ee/crypto_migration_invitation_producer.dart';
import 'package:kanban/organizer/data/e2ee/crypto_migration_invitations.dart';
import 'package:kanban/organizer/data/e2ee/crypto_json.dart';
import 'package:kanban/organizer/data/e2ee/scope_crypto_manager.dart';

class _Secure implements AccountCryptoStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

void main() {
  final path = Platform.environment['JIVIE_MIGRATION_INVITATION_HTTP_FIXTURE'];
  test(
    'whole native invitation capture stages exact cipher and FILE-only blank SQL compares all old states and mail',
    () async {
      final f = jsonDecode(await File(path!).readAsString()) as Map;
      if (f['synthetic'] != true ||
          Uri.parse(f['serverUrl']).host != '127.0.0.1')
        throw StateError('Synthetic only');
      final wire = f['session'] as Map,
          u = wire['user'] as Map,
          d = wire['device'] as Map;
      final session = DeviceSession(
        AccountSession(
          serverUrl: f['serverUrl'],
          serverId: wire['serverId'],
          accountId: u['accountId'],
          userId: u['id'],
          username: u['username'],
          displayName: u['displayName'],
          deviceId: d['id'],
          expiresAt: DateTime.fromMillisecondsSinceEpoch(d['expiresAt'] * 1000),
          allowLocalHttp: true,
        ),
        wire['token'],
      );
      final db = CollaborationDatabase(NativeDatabase.memory()),
          http = HttpCollaborationTransport(),
          crypto = CryptoCodec(await SodiumInit.init());
      addTearDown(db.close);
      addTearDown(http.close);
      final account = AccountCryptoV2Workflow(
        AccountDirectoryRepository(
          reducer: AccountDirectoryV2(crypto),
          session: session,
          transport: http,
          store: CryptoIdentityStore(db, _Secure(), session.profile.partition),
          isCurrent: () => true,
        ),
      );
      final file = await account.prepareRecoveryFile();
      final temp = await Directory.systemTemp.createTemp(
        'synthetic-invitation-cold-',
      );
      try {
        await account.verifyAndInitialize(file);
        final coordinator = CryptoCaptureCoordinator(account),
            capture = await coordinator.prepare(f['scopeId']);
        final sealed = await coordinator.captureSources(capture);
        await coordinator.fence(capture,reviewedInventoryRoot:sealed['inventoryRoot'] as String);
        final archive = CryptoCaptureArchive(
          account,
          coldDatabase: () => CryptoArchiveColdDatabase.create(parent: temp),
        );
        final manifest = await archive.stageAndUpload(capture);
        final verified = await archive.verifyFromFile(
          capture: capture,
          manifest: manifest,
          externalFile: file,
        );
        final access = SessionCryptoAccess(account: account);
        final catalog = await account.directory.call('crypto2.scopes.catalog', {
          'limit': 50,
        });
        final scope = (catalog['scopes'] as List).cast<Map>().singleWhere(
          (s) => s['id'] == f['scopeId'],
        );
        await ScopeCryptoManager(access).initializeEmptyScope(
          scopeId: scope['id'],
          accessRevision: scope['accessRevision'],
          members: (scope['members'] as List).cast<Map<String, dynamic>>(),
        );
        final runtime = CryptoBusinessSession(account, access, db),
            producer = CryptoMigrationInvitations(
              CryptoBusinessSession(account, access, db),
            );
        final all = await db.rows(
          'SELECT * FROM crypto_capture_sources WHERE partition=? AND capture_id=? ORDER BY binding_id',
          [runtime.partition, capture.captureId],
        );
        final selected = all
            .where(
              (r) =>
                  const {
                    'familyhub_invitations',
                    'familyhub_invitation_mail',
                  }.contains(
                    (jsonDecode(r['context'] as String) as Map)['sourceTable'],
                  ),
            )
            .toList();
        expect(selected.length, 5);
        final relations = <String, Map<String, dynamic>>{};
        for (final table in [
          'familyhub_invitations',
          'familyhub_invitation_mail',
        ]) {
          for (final row in selected.where(
            (r) =>
                (jsonDecode(r['context'] as String) as Map)['sourceTable'] ==
                table,
          )) {
            final context = CryptoCaptureSourceContext.fromJson(
                  jsonDecode(row['context'] as String),
                ),
                binding = CryptoCaptureBinding.fromJson(
                  jsonDecode(row['binding'] as String),
                );
            final raw = Map<String, dynamic>.from(
              jsonDecode(row['typed_row'] as String) as Map,
            );
            final decoded = decodeCryptoMigrationInvitationSource(
              context: context,
              row: raw,
            );
            final key = await coordinator.keys.open(capture);
            final salt = await CryptoCaptureV3.salt(key.key, context);
            key.release();
            final witness = {
              'version': 3,
              'context': context.toJson(),
              'typedRow': raw,
              'saltBase64': base64Encode(salt),
            };
            salt.fillRange(0, salt.length, 0);
            final descriptor = await producer.stageCaptured(
              capture: capture,
              sourceInventoryRoot: verified.sourceInventoryRoot,
              binding: binding,
              witness: witness,
              invitationBridge: relations[decoded.id],
            );
            if (!decoded.isMail) relations[decoded.id] = descriptor;
            final before = (await db.rows(
              'SELECT payload FROM crypto_export_drafts WHERE action_id=?',
              ['legacyInvitation:${capture.captureId}:${binding.bindingId}'],
            )).single;
            expect(
              await producer.stageCaptured(
                capture: capture,
                sourceInventoryRoot: verified.sourceInventoryRoot,
                binding: binding,
                witness: witness,
                invitationBridge: relations[decoded.id],
              ),
              descriptor,
            );
            expect(
              (await db.rows(
                'SELECT payload FROM crypto_export_drafts WHERE action_id=?',
                ['legacyInvitation:${capture.captureId}:${binding.bindingId}'],
              )).single,
              before,
            );
          }
        }
        final head = await access.currentHead(f['scopeId']);
        await archive.withVerifiedSourceFromFile(
          capture: capture,
          manifest: manifest,
          externalFile: file,
          use: (cold, coldAccount, coldArchive) async {
            final coldRuntime = CryptoBusinessSession(
              coldAccount,
              SessionCryptoAccess(account: coldAccount),
              cold.database,
            );
            final rows = await cold.database.rows(
              'SELECT binding_id,context FROM crypto_capture_sources WHERE partition=? AND capture_id=? ORDER BY binding_id',
              [runtime.partition, capture.captureId],
            );
            final relevant = rows
                .where(
                  (r) =>
                      const {
                        'familyhub_invitations',
                        'familyhub_invitation_mail',
                      }.contains(
                        (jsonDecode(r['context'] as String)
                            as Map)['sourceTable'],
                      ),
                )
                .toList();
            // The head context comes from an exact own signed bridge already verified
            // against the FILE-rooted prefix, never an unsigned catalog selector.
            final page = await coldAccount.directory
                .call('crypto2.migration.invitations.bridges', {
                  'migrationId': capture.migrationId,
                  'captureId': capture.captureId,
                  'sourceInventoryRoot': verified.sourceInventoryRoot,
                  'limit': 20,
                });
            final first = Map<String, dynamic>.from(
                  page['bridges'][0]['authorization'] as Map,
                ),
                cmd =
                    CryptoJson.decode(cryptoBase64(first['commandBase64']))
                        as Map;
            await CryptoMigrationColdEvidence(
              coldRuntime,
              coldArchive,
            ).verifyOwn(
              first,
              cmd['payload']['authorDirectoryHeadHash'],
              cmd['deviceId'],
              cryptoDirectoryDomain,
            );
            expect(
              cmd['payload']['context']['membershipHeadHash'],
              head.headHash,
            );
            await coldRuntime.access.withReadOnlyFrozenScope(
              scopeId: head.scopeId,
              candidateHeadHash: head.headHash,
              recoveryFile: file,
              body: () async {
                await coldRuntime.access.currentHead(head.scopeId);
                final control = CryptoMigrationInvitationControl(
                  coldRuntime,
                  coldArchive,
                  recoveryFile: file,
                );
                for (final row in relevant.reversed) {
                  await control.verify(
                    await CryptoMigrationColdSource.load(
                      coldRuntime,
                      coldArchive,
                      row['binding_id'] as String,
                    ),
                  );
                }
                final section = await control.finish();
                expect(section['kind'], 'invitations');
                expect(section['count'], 5);
                expect(section['root'], isA<String>());
                await expectLater(
                  coldRuntime.access.writeContext(head.scopeId, 'content'),
                  throwsA(isA<CryptoAuthorityPending>()),
                );
              },
            );
            expect(
              await cold.database.rows('SELECT 1 FROM crypto_outbox'),
              isEmpty,
            );
            expect(
              await cold.database.rows('SELECT 1 FROM crypto_identity_secrets'),
              isEmpty,
            );
            expect(
              await cold.database.rows(
                'SELECT 1 FROM crypto_scope_keys WHERE write_ready=1',
              ),
              isEmpty,
            );
          },
        );
        expect(sealed['captureState'], 'sealed');
      } catch (_) {
        for(final row in await db.rows("SELECT operation,state,response FROM crypto_outbox WHERE state<>'applied'")){
          final response=row['response']==null?null:jsonDecode(row['response'] as String);
          debugPrint('synthetic bridge op=${row['operation']} state=${row['state']} code=${response is Map?response['errorCode']:null}');
        }
        for(final row in await db.rows('SELECT event,details FROM crypto_outbox_attempts ORDER BY sequence DESC LIMIT 3')){debugPrint('synthetic bridge ${row['event']} ${row['details']}');}
        rethrow;
      } finally {
        file.fillRange(0, file.length, 0);
        await temp.delete(recursive: true);
      }
    },
    skip: path == null,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
