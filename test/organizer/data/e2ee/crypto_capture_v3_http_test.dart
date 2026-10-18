import 'package:kanban/organizer/data/e2ee/crypto_migration_idea_draft_recovery.dart';
import 'crypto_migration_combined_choices.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
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
import 'package:kanban/organizer/data/e2ee/crypto_archive_cold_database.dart';
import 'package:kanban/organizer/data/e2ee/crypto_codec.dart';
import 'package:kanban/organizer/data/e2ee/crypto_json.dart';
import 'package:kanban/organizer/data/e2ee/crypto_identity_store.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:sodium/sodium.dart' show SodiumInit, KeyPair;
import 'package:kanban/organizer/data/e2ee/crypto_capture_coordinator.dart';
import 'package:kanban/organizer/data/e2ee/crypto_migration_coordinator.dart'
    as public_migration;
import 'package:kanban/organizer/data/e2ee/crypto_scope_observations.dart';
import 'package:kanban/organizer/data/e2ee/crypto_business_router.dart';
import 'package:kanban/organizer/data/e2ee/crypto_business_documents.dart';
import 'package:kanban/organizer/data/e2ee/crypto_business_finance.dart';
import 'package:kanban/organizer/data/e2ee/crypto_inventory_json.dart';
import 'package:kanban/organizer/data/e2ee/crypto_migration_canonical_stage.dart';
import 'package:kanban/organizer/data/e2ee/crypto_migration_audit.dart';
import 'package:kanban/organizer/data/e2ee/crypto_migration_local_artifact.dart';
import 'package:kanban/organizer/data/e2ee/crypto_migration_local_artifact_cold.dart';
import 'package:kanban/organizer/data/e2ee/crypto_migration_receipt_control.dart';
import 'package:kanban/organizer/data/e2ee/crypto_migration_cold_business.dart';
import 'package:kanban/organizer/data/e2ee/crypto_migration_domain_contributions.dart';
import 'package:kanban/organizer/data/e2ee/crypto_migration_activation_producer.dart';
import 'package:kanban/organizer/data/e2ee/crypto_migration_invitation_producer.dart';
import 'package:kanban/organizer/data/e2ee/crypto_migration_notification_producer.dart';
import 'package:kanban/organizer/data/e2ee/crypto_migration_record_source.dart';
import 'package:kanban/organizer/data/e2ee/crypto_migration_stage_verifier.dart';
import 'package:kanban/organizer/data/e2ee/crypto_migration_witness.dart';
import 'package:kanban/organizer/data/e2ee/crypto_migration_witness_transport.dart';
import 'package:kanban/organizer/data/e2ee/session_crypto_access.dart';
import 'package:kanban/organizer/data/e2ee/scope_crypto_manager.dart';
import 'package:kanban/organizer/data/e2ee/crypto_capture_keys.dart';
import 'package:kanban/organizer/data/e2ee/crypto_capture_archive.dart';
import 'package:kanban/organizer/data/e2ee/crypto_capture_legacy.dart';
import 'package:kanban/organizer/data/e2ee/crypto_capture_legacy_index.dart';
import 'package:kanban/organizer/data/e2ee/crypto_capture_v3.dart';
import 'package:kanban/organizer/data/e2ee/crypto_sync_repository.dart';

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
  late final _http = HttpCollaborationTransport(
    onAttempt: (operation) {
      attempts[operation] = (attempts[operation] ?? 0) + 1;
    },
  );
  final attempts = <String, int>{};
  int _rateRetries = 0;
  String? alteredComponentId;
  List<String>? alteredOwnedScopeIds;
  String? dropAcceptedOperation;
  final counts = <String, int>{};
  // Diagnostic labels only; opaque event hashes stay in memory and are never logged.
  final recoveryAttestationKinds = <String, String>{};
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
    try {
      counts[operation] = (counts[operation] ?? 0) + 1;
      final response = await _http.call(
        serverUrl: serverUrl,
        operation: operation,
        params: params,
        token: token,
        allowLocalHttp: allowLocalHttp,
      );
      if (operation == 'crypto2.migration.ownAttestation') {
        const kinds = {
          'crypto2.migration.domains.contribute': 'domainContribution',
          'crypto2.migration.domains.certify': 'domainCertificate',
          'crypto2.migration.structure.sourceCertificate': 'structureSource',
          'crypto2.migration.invitations.certify': 'invitationControl',
          'crypto2.migration.notifications.certify': 'notificationControl',
          'crypto2.migration.legacy.certify': 'receiptControl',
          'crypto2.migration.verify3': 'privateArtifact',
        };
        final proofs = response['authorizations'];
        var kind = 'unrecognized';
        if (proofs is List && proofs.length == 1 && proofs.single is Map) {
          final body =
              CryptoJson.decode(
                    cryptoBase64((proofs.single as Map)['commandBase64']),
                  )
                  as Map;
          kind = kinds[body['operation']] ?? 'unrecognized';
        }
        final hash = params['eventCommandHash'];
        if (hash is String) recoveryAttestationKinds[hash] = kind;
      }
      if (operation == dropAcceptedOperation) {
        dropAcceptedOperation = null;
        throw const CollaborationApiException('synthetic_lost_ack');
      }
      if (operation == 'crypto2.migration.capture.discover') {
        return {
          ...response,
          if (alteredComponentId != null) 'componentId': alteredComponentId,
          if (alteredOwnedScopeIds != null)
            'ownedScopeIds': alteredOwnedScopeIds,
        };
      }
      return response;
    } on CollaborationApiException catch (error) {
      // Synthetic diagnostics deliberately exclude payloads and sidecar secrets.
      debugPrint('synthetic capture operation=$operation error=${error.code}');
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
  final interrupt = Platform.environment['JIVIE_CAPTURE_TEST_INTERRUPT'] == '1';
  if (Platform.environment['JIVIE_CAPTURE_TEST_PUBLIC_COORDINATOR'] == '1') {
    test(
      'public Capture3 coordinator commits and FILE-only blank SQL verifies ordinary readiness',
      () => _publicCoordinator(path!),
      skip: path == null ? 'synthetic loopback fixture required' : false,
      timeout: Timeout(
        Duration(
          minutes:
              Platform.environment['JIVIE_CAPTURE_TEST_EXTRA_RECORDS'] == null
              ? 5
              : 40,
        ),
      ),
    );
    return;
  }

  test(
    'capture3 actual blinded source root reopens through public coordinator using FILE only and blank encrypted SQL',
    () async {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      final fixture = jsonDecode(await File(path!).readAsString()) as Map;
      if (fixture['synthetic'] != true ||
          Uri.parse(fixture['serverUrl']).host != '127.0.0.1') {
        throw StateError('Synthetic loopback only');
      }
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
      final http = _SyntheticHttp(),
          db = CollaborationDatabase(NativeDatabase.memory());
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
      addTearDown(http.close);
      var originalClosed = false, migrationCommitted = false;
      addTearDown(() async {
        if (!originalClosed) await db.close();
      });
      final externalFile = await account.prepareRecoveryFile();
      try {
        await account.verifyAndInitialize(externalFile);
        final wrapInterrupted = CryptoCaptureCoordinator(
          account,
          checkpoint: (phase) async {
            if (phase == 'capture_key_wrapped') {
              throw StateError('synthetic loss after key wrap');
            }
          },
        );
        await expectLater(
          wrapInterrupted.prepare(fixture['scopeId'] as String),
          throwsStateError,
        );
        final wrapped = (await db.rows(
          'SELECT capture_id,key_id,context,key_bytes FROM crypto_capture_keys',
        )).single;
        final prepareCalls =
            http.counts['crypto2.migration.capture.prepare'] ?? 0;
        http.alteredOwnedScopeIds = fixture['sharedReadContributor'] == true
            ? [crypto.randomId()]
            : <String>[];
        await expectLater(
          CryptoCaptureCoordinator(
            account,
          ).prepare(fixture['scopeId'] as String),
          throwsA(
            isA<CryptoAuthorityPending>().having(
              (e) => e.reason,
              'reason',
              'crypto_capture_context_changed',
            ),
          ),
        );
        expect(
          http.counts['crypto2.migration.capture.prepare'] ?? 0,
          prepareCalls,
        );
        expect(
          (await db.rows(
            'SELECT capture_id,key_id,context,key_bytes FROM crypto_capture_keys',
          )).single,
          wrapped,
        );
        http.alteredOwnedScopeIds = null;
        var counterRevision = 1;
        var counterRead = false;
        Future<void> advanceUnrelatedInbox() async {
          counterRead = !counterRead;
          final response = await http.call(
            serverUrl: session.profile.serverUrl,
            token: session.token,
            allowLocalHttp: true,
            operation: 'inbox.read',
            params: {
              'id': fixture['otherInboxId'] as int,
              'read': counterRead,
              'expectedRevision': counterRevision,
              'requestId': crypto.randomId(),
            },
          );
          counterRevision = (response['item'] as Map)['revision'] as int;
        }

        var advancedAfterBind = false;
        final coordinator = CryptoCaptureCoordinator(
          account,
          checkpoint: (phase) async {
            if (fixture['counterFixture'] == true &&
                phase == 'capture_bind_ack' &&
                !advancedAfterBind) {
              advancedAfterBind = true;
              await advanceUnrelatedInbox();
            }
            if (interrupt && phase == 'capture_bind_ack') {
              throw StateError('synthetic capture process loss');
            }
          },
        );
        final descriptor = await coordinator.prepare(
          fixture['scopeId'] as String,
        );
        expect(descriptor.captureId, wrapped['capture_id']);
        expect(descriptor.keyId, wrapped['key_id']);
        if (fixture['sharedReadContributor'] == true) {
          expect(descriptor.scopeIds, isEmpty);
          expect(descriptor.receiptSelections, [
            {'scopeId': fixture['scopeId'], 'domain': 'content'},
            {'scopeId': fixture['scopeId'], 'domain': 'finance'},
          ]);
        }
        if (fixture['counterFixture'] == true) {
          // Ordinary unrelated legacy activity after capture.prepare, before
          // source retrieval/first successful binding, remains independent.
          await advanceUnrelatedInbox();
        }
        Map<String, dynamic>? sealed;
        if (interrupt) {
          await expectLater(
            coordinator.captureSources(descriptor),
            throwsStateError,
          );
        } else {
          sealed = await coordinator.captureSources(descriptor);
          expect(sealed['captureVersion'], 3);
          expect(sealed['captureState'], 'sealed');
          if (fixture['counterFixture'] == true) {
            expect(advancedAfterBind, true);
            final snapshot = (await db.rows(
              "SELECT typed_row FROM crypto_capture_sources WHERE context LIKE '%familyhub_inbox_state%'",
            )).single;
            final capturedState =
                jsonDecode(snapshot['typed_row'] as String) as Map;
            expect(
              utf8.decode(
                cryptoBase64(capturedState['sequence']['valueBase64']),
              ),
              '17',
            );
            await advanceUnrelatedInbox();
            final retried = await coordinator.captureSources(descriptor);
            expect(retried['inventoryRoot'], sealed['inventoryRoot']);
            final live = await http.call(
              serverUrl: session.profile.serverUrl,
              token: session.token,
              allowLocalHttp: true,
              operation: 'inbox.sync',
              params: {'cursor': 0},
            );
            expect(live['cursor'], 20);
            expect(
              (await db.rows(
                "SELECT typed_row FROM crypto_capture_sources WHERE context LIKE '%familyhub_inbox_state%'",
              )).single,
              snapshot,
            );
          }
          expect(
            sealed['sourceCount'],
            greaterThan(fixture['sharedReadContributor'] == true ? 3 : 8),
          );
          expect(sealed.containsKey('inventoryHash'), false);
          expect(sealed.containsKey('componentHash'), false);
          if (Platform.environment['JIVIE_CAPTURE_TEST_LEGACY_INDEX'] == '1') {
            expect(fixture['sharedReadContributor'], false);
            await coordinator.fence(
              descriptor,
              reviewedInventoryRoot: sealed['inventoryRoot'] as String,
            );
            final componentCandidate = await coordinator.componentCandidate(
              descriptor,
            );
            expect(componentCandidate['portionCount'], 1);
            expect(
              (componentCandidate['portions'] as List)
                  .single['sourceInventoryRoot'],
              sealed['inventoryRoot'],
            );
            expect(componentCandidate.containsKey('componentHash'), false);
            expect(
              jsonEncode(componentCandidate),
              isNot(contains('sourceRowHash')),
            );
            final receiptRoot = await Directory.systemTemp.createTemp(
              'synthetic-capture3-receipts-',
            );
            try {
              final archive = CryptoCaptureArchive(
                account,
                coldDatabase: () =>
                    CryptoArchiveColdDatabase.create(parent: receiptRoot),
              );
              final manifest = await archive.stageAndUpload(descriptor);
              final cold = await archive.verifyFromFile(
                capture: descriptor,
                manifest: manifest,
                externalFile: externalFile,
              );
              if (Platform.environment['JIVIE_CAPTURE_TEST_RECORDS'] == '1') {
                final access = SessionCryptoAccess(account: account);
                final catalog = await account.directory.call(
                  'crypto2.scopes.catalog',
                  {'limit': 50},
                );
                final scope = (catalog['scopes'] as List)
                    .cast<Map>()
                    .singleWhere((s) => s['id'] == fixture['scopeId']);
                await ScopeCryptoManager(access).initializeEmptyScope(
                  migrationId: descriptor.migrationId,
                  captureId: descriptor.captureId,
                  scopeId: scope['id'],
                  accessRevision: scope['accessRevision'],
                  members: (scope['members'] as List)
                      .cast<Map<String, dynamic>>(),
                );
                final business = CryptoBusinessSession(account, access, db);
                business.references = CryptoBusinessDocuments(
                  business,
                ).references;
                final stage = CryptoMigrationCanonicalStage(business);
                final capturedRows = await db.rows(
                  "SELECT * FROM crypto_capture_sources WHERE partition=? AND capture_id=? ORDER BY binding_id",
                  [account.store.partition, descriptor.captureId],
                );
                var staged = 0;
                for (final table in [
                  'familyhub_scopes',
                  'familyhub_records',
                  'familyhub_finance_records',
                  'familyhub_attachments',
                ]) {
                  final selected = capturedRows
                      .where(
                        (row) =>
                            (jsonDecode(row['context'] as String)
                                as Map)['sourceTable'] ==
                            table,
                      )
                      .toList();
                  selected.sort((a, b) {
                    String type(Map row) {
                      final typed =
                          jsonDecode(row['typed_row'] as String) as Map;
                      return typed['type'] == null
                          ? 'scopeMetadata'
                          : utf8.decode(
                              base64Decode(typed['type']['valueBase64']),
                            );
                    }

                    return (type(a) == 'financeAccount' ? 0 : 1).compareTo(
                      type(b) == 'financeAccount' ? 0 : 1,
                    );
                  });
                  for (final row in selected) {
                    final sourceContext = CryptoCaptureSourceContext.fromJson(
                      jsonDecode(row['context'] as String),
                    );
                    final binding = CryptoCaptureBinding.fromJson(
                      jsonDecode(row['binding'] as String),
                    );
                    final source = await CryptoMigrationRecordSource.decode(
                      table: table,
                      domain: sourceContext.domain,
                      row: jsonDecode(row['typed_row'] as String),
                      serverId: session.profile.serverId,
                      reservedId: business.reservedRecordId,
                    );
                    final key = await coordinator.keys.open(descriptor);
                    final salt = await CryptoCaptureV3.salt(
                      key.key,
                      sourceContext,
                    );
                    key.release();
                    final witness = <String, dynamic>{
                      'version': 3,
                      'context': sourceContext.toJson(),
                      'typedRow': source.typedRow,
                      'saltBase64': base64Encode(salt),
                    };
                    salt.fillRange(0, salt.length, 0);
                    await stage.stageCaptured(
                      capture: descriptor,
                      sourceInventoryRoot: cold.sourceInventoryRoot,
                      binding: binding,
                      witness: witness,
                      source: source,
                    );
                    // Public saved command contains no raw source hashes/salts.
                    final command = (await db.rows(
                      "SELECT signed_body FROM crypto_outbox WHERE operation='crypto2.migration.recordsStage' ORDER BY sequence DESC LIMIT 1",
                    )).single;
                    final decoded =
                        CryptoJson.decode(
                              cryptoBase64(
                                (jsonDecode(command['signed_body'] as String)
                                    as Map)['commandBase64'],
                              ),
                            )
                            as Map;
                    final publicBinding =
                        (decoded['payload']['sourceBindings'] as List).single
                            as Map;
                    expect(
                      CryptoInventoryJson.canonical(decoded),
                      isNot(contains(source.rowHash)),
                    );
                    expect(
                      CryptoInventoryJson.canonical(decoded),
                      isNot(contains(witness['saltBase64'])),
                    );
                    if (source.type == 'scopeMetadata') {
                      expect(publicBinding['witness'], isNull);
                      staged++;
                      continue;
                    }
                    expect(publicBinding['witness'], isNotNull);
                    final witnessDescriptor = Map<String, dynamic>.from(
                      publicBinding['witness'],
                    );
                    final witnessContext = CryptoMigrationWitnessContext(
                      Map<String, dynamic>.from(witnessDescriptor['context']),
                    );
                    final isolated = CollaborationDatabase(
                      NativeDatabase.memory(),
                    );
                    try {
                      final consumer = CryptoMigrationWitness(
                        database: isolated,
                        partition: 'isolated',
                        crypto: crypto,
                      );
                      await CryptoMigrationWitnessTransport(
                        queue: coordinator.queue,
                        read: account.directory.call,
                      ).download(
                        consumer: consumer,
                        context: witnessContext,
                        descriptor: witnessDescriptor,
                      );
                      final domainKey = await (await access.migrationCandidate(
                        scopeId: source.scopeId,
                        migrationId: descriptor.migrationId,
                        captureId: descriptor.captureId,
                        headHash: witnessContext.value['membershipHeadHash'],
                      )).key(source.domain);
                      try {
                        expect(
                          await consumer.open(
                            context: witnessContext,
                            descriptor: witnessDescriptor,
                            domainKey: domainKey.key,
                          ),
                          witness,
                        );
                      } finally {
                        domainKey.release();
                      }
                    } finally {
                      await isolated.close();
                    }
                    staged++;
                  }
                }
                expect(staged, 6);
                if (fixture['auditFixture'] == true) {
                  for (final row in capturedRows.where(
                    (r) =>
                        (jsonDecode(r['context'] as String)
                            as Map)['sourceTable'] ==
                        'familyhub_finance_audit',
                  )) {
                    final c = CryptoCaptureSourceContext.fromJson(
                      jsonDecode(row['context'] as String),
                    );
                    final binding = CryptoCaptureBinding.fromJson(
                      jsonDecode(row['binding'] as String),
                    );
                    final key = await coordinator.keys.open(descriptor);
                    final salt = await CryptoCaptureV3.salt(key.key, c);
                    key.release();
                    final witness = <String, dynamic>{
                      'version': 3,
                      'context': c.toJson(),
                      'typedRow': jsonDecode(row['typed_row'] as String),
                      'saltBase64': base64Encode(salt),
                    };
                    salt.fillRange(0, salt.length, 0);
                    final result = await CryptoMigrationAudit(business)
                        .stageCaptured(
                          capture: descriptor,
                          sourceInventoryRoot: cold.sourceInventoryRoot,
                          binding: binding,
                          witness: witness,
                        );
                    expect(result['active'], false);
                    final saved = (await db.rows(
                      "SELECT signed_body,request_hash FROM crypto_outbox WHERE operation='crypto2.migration.audit.stage'",
                    )).single;
                    expect(
                      await CryptoMigrationAudit(business).stageCaptured(
                        capture: descriptor,
                        sourceInventoryRoot: cold.sourceInventoryRoot,
                        binding: binding,
                        witness: witness,
                      ),
                      result,
                    );
                    expect(
                      (await db.rows(
                        "SELECT signed_body,request_hash FROM crypto_outbox WHERE operation='crypto2.migration.audit.stage'",
                      )).single,
                      saved,
                    );
                  }
                }
                await archive.withVerifiedSourceFromFile<void>(
                  capture: descriptor,
                  manifest: manifest,
                  externalFile: externalFile,
                  use: (isolated, coldAccount, coldSource) async {
                    expect(
                      await isolated.database.rows(
                        'SELECT * FROM crypto_scope_keys',
                      ),
                      isEmpty,
                    );
                    final coldAccess = SessionCryptoAccess(
                      account: coldAccount,
                    );
                    final candidatePage = await coldAccount.directory
                        .call('crypto2.migration.stagedRecords', {
                          'migrationId': descriptor.migrationId,
                          'scopeId': fixture['scopeId'],
                          'domain': 'content',
                          'limit': 20,
                        });
                    final runtime = CryptoBusinessSession(
                      coldAccount,
                      coldAccess,
                      isolated.database,
                    );
                    runtime.coldScopeDescriptor = (scope) async {
                      await coldAccess.requireReadOnlyFrozenScope(scope);
                      final rows = await isolated.database.rows(
                        'SELECT descriptor FROM crypto_business_scope_descriptors WHERE partition=? AND scope_id=?',
                        [runtime.partition, scope],
                      );
                      if (rows.length != 1) {
                        throw const CryptoAuthorityPending(
                          'scope_descriptor_migration_pending',
                        );
                      }
                      return Map<String, dynamic>.from(
                        jsonDecode(rows.single['descriptor'] as String),
                      );
                    };
                    final documents = CryptoBusinessDocuments(runtime);
                    runtime.prepareRecords = documents.prepareRecords;
                    runtime.blobIds = documents.blobIds;
                    runtime.references = documents.references;
                    runtime.validateRaw = documents.validateRaw;
                    runtime.projectExtension = documents.projectRecord;
                    runtime.expandPayload = documents.expandPayload;
                    final verifier = CryptoMigrationStageVerifier(runtime);
                    final fileInfo = coldAccount.files.inspect(
                      externalFile,
                      serverId: session.profile.serverId,
                      accountId: session.profile.accountId,
                    );
                    final ownPrefix = await coldAccount.directory
                        .replayFileAnchoredCandidate(fileInfo['fingerprint']);
                    final candidate = await verifier.frozenCandidate(
                      authorization: Map<String, dynamic>.from(
                        candidatePage['stages'][0]['authorization'],
                      ),
                      coldArchive: coldSource,
                      contributor: ownPrefix,
                    );
                    final ownBefore = await coldAccount.store.anchor(
                      coldAccount.directory.accountId,
                    );
                    await coldAccess.withReadOnlyFrozenScope<void>(
                      scopeId: fixture['scopeId'],
                      candidateHeadHash: candidate.headHash,
                      recoveryFile: externalFile,
                      body: () async {
                        await expectLater(
                          coldAccess.writeContext(
                            fixture['scopeId'],
                            'content',
                          ),
                          throwsA(
                            isA<CryptoAuthorityPending>().having(
                              (e) => e.reason,
                              'reason',
                              'crypto_frozen_source_read_only',
                            ),
                          ),
                        );
                        await expectLater(
                          coldAccess.beforeDelivery(const {}),
                          throwsA(
                            isA<CryptoAuthorityPending>().having(
                              (e) => e.reason,
                              'reason',
                              'crypto_frozen_source_read_only',
                            ),
                          ),
                        );
                        await coldAccess.recoverScopeCandidateKeys(
                          fixture['scopeId'],
                          externalFile,
                        );
                        var count = 0;
                        for (final domain in ['content', 'finance']) {
                          final page = await coldAccount.directory
                              .call('crypto2.migration.stagedRecords', {
                                'migrationId': descriptor.migrationId,
                                'scopeId': fixture['scopeId'],
                                'domain': domain,
                                'limit': 20,
                              });
                          final stages = (page['stages'] as List)
                              .cast<Map>()
                              .toList();
                          int rank(Map stage) {
                            final command =
                                CryptoJson.decode(
                                      cryptoBase64(
                                        stage['authorization']['commandBase64'],
                                      ),
                                    )
                                    as Map;
                            final binding =
                                (command['payload']['sourceBindings'] as List)
                                        .first
                                    as Map;
                            return binding['type'] == 'scopeMetadata'
                                ? -1
                                : binding['type'] == 'financeAccount'
                                ? 0
                                : 1;
                          }

                          stages.sort((a, b) => rank(a).compareTo(rank(b)));
                          for (final stage in stages) {
                            Future<Map<String, dynamic>> sourceRow(
                              Map binding,
                            ) async {
                              return (await isolated.database.rows(
                                'SELECT * FROM crypto_capture_sources WHERE partition=? AND capture_id=? AND binding_id=?',
                                [
                                  account.store.partition,
                                  descriptor.captureId,
                                  binding['bindingId'],
                                ],
                              )).single;
                            }

                            final verified = await verifier.verify(
                              migrationId: descriptor.migrationId,
                              authorization: Map<String, dynamic>.from(
                                stage['authorization'],
                              ),
                              coldArchive: coldSource,
                              frozenCandidate: await verifier.frozenCandidate(
                                authorization: Map<String, dynamic>.from(
                                  stage['authorization'],
                                ),
                                coldArchive: coldSource,
                                contributor: ownPrefix,
                              ),
                              capturedBinding: (binding) async =>
                                  CryptoCaptureBinding.fromJson(
                                    jsonDecode(
                                      (await sourceRow(binding))['binding']
                                          as String,
                                    ),
                                  ),
                              source: (binding) async {
                                final row = await sourceRow(binding);
                                final sourceContext =
                                    CryptoCaptureSourceContext.fromJson(
                                      jsonDecode(row['context'] as String),
                                    );
                                return CryptoMigrationRecordSource.decode(
                                  table: sourceContext.sourceTable,
                                  domain: sourceContext.domain,
                                  row: jsonDecode(row['typed_row'] as String),
                                  serverId: session.profile.serverId,
                                  reservedId: runtime.reservedRecordId,
                                );
                              },
                              openWitness: (binding) async {
                                final d = Map<String, dynamic>.from(
                                  binding['witness'],
                                );
                                final c = CryptoMigrationWitnessContext(
                                  Map<String, dynamic>.from(d['context']),
                                );
                                final consumer = CryptoMigrationWitness(
                                  database: isolated.database,
                                  partition: account.store.partition,
                                  crypto: crypto,
                                );
                                await CryptoMigrationWitnessTransport(
                                  queue: coordinator.queue,
                                  read: coldAccount.directory.call,
                                ).download(
                                  consumer: consumer,
                                  context: c,
                                  descriptor: d,
                                );
                                final key = await coldAccess.getScopeKey(
                                  c.value['scopeId'],
                                  c.value['domain'],
                                  c.value['epoch'],
                                );
                                try {
                                  return await consumer.open(
                                    context: c,
                                    descriptor: d,
                                    domainKey: key.key,
                                  );
                                } finally {
                                  key.release();
                                }
                              },
                            );
                            try {
                              await isolated.database.transaction(
                                () => runtime.project(verified),
                              );
                              count += verified.length;
                            } finally {
                              for (final record in verified) {
                                record.plaintext?.fillRange(
                                  0,
                                  record.plaintext!.length,
                                  0,
                                );
                              }
                            }
                          }
                        }
                        expect(count, 9);
                        final attachment = (await runtime.record(
                          fixture['scopeId'],
                          'content',
                          fixture['attachmentId'],
                          type: 'attachment',
                        ))!;
                        final attachmentRaw =
                            jsonDecode(attachment['raw_payload'] as String)
                                as Map;
                        final fileBytes = await documents.blobs.open(
                          Map<String, dynamic>.from(
                            attachmentRaw['cryptoBlob'] as Map,
                          ),
                          online: false,
                        );
                        try {
                          expect(fileBytes.length, fixture['fileBytes']);
                          expect(
                            await cryptoSha256(fileBytes),
                            fixture['fileSha256'],
                          );
                        } finally {
                          fileBytes.fillRange(0, fileBytes.length, 0);
                        }
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
                        final expense = (await runtime.record(
                          fixture['scopeId'],
                          'finance',
                          fixture['expenseId'],
                          type: 'financeEntry',
                        ))!;
                        expect(expense['legacy_revision'], 31);
                        expect(
                          jsonDecode(expense['raw_payload'] as String),
                          jsonDecode(fixture['entryPayload']),
                        );
                        expect(
                          (await isolated.database.rows(
                            "SELECT COUNT(*) AS n FROM crypto_business_records WHERE type='financeEntry'",
                          )).single['n'],
                          1,
                        );
                        final resolutions = await isolated.database.rows(
                          "SELECT raw_payload FROM crypto_business_records WHERE type='taskDerivationResolution' AND deleted=0",
                        );
                        expect(resolutions.length, 1);
                        final resolutionRaw = Map<String, dynamic>.from(
                          jsonDecode(
                                resolutions.single['raw_payload'] as String,
                              )
                              as Map,
                        );
                        expect(
                          resolutionRaw['financeEntryId'],
                          fixture['expenseId'],
                        );
                        expect(
                          resolutionRaw['state'],
                          fixture['legacyTaskMismatch'] == true
                              ? 'legacyPending'
                              : 'derived',
                        );
                        final forgedPending = {
                          ...resolutionRaw,
                          'state': 'legacyPending',
                        };
                        final finance = CryptoBusinessFinance(runtime);
                        await expectLater(
                          finance.validate([
                            CryptoBusinessProjection(
                              record: {
                                'scopeId': fixture['scopeId'],
                                'domain': 'finance',
                                'type': 'taskDerivationResolution',
                                'id': await runtime.reservedRecordId(
                                  fixture['scopeId'],
                                  'taskResolution:${fixture['taskId']}',
                                ),
                                'metadata': {
                                  'uniqueRefs': await finance.uniqueRefs(
                                    fixture['scopeId'],
                                    'taskDerivationResolution',
                                    forgedPending,
                                  ),
                                },
                              },
                              raw: forgedPending,
                              previousRaw: null,
                            ),
                          ], forWrite: true),
                          throwsFormatException,
                        );
                        // Encryption must not cause a first-sync re-derivation
                        // of the already posted legacy fact, including repeats.
                        await runtime.reconcileTaskDerivations(
                          fixture['scopeId'],
                        );
                        await runtime.reconcileTaskDerivations(
                          fixture['scopeId'],
                        );
                        expect(
                          await isolated.database.rows(
                            'SELECT * FROM crypto_outbox',
                          ),
                          isEmpty,
                        );
                        expect(
                          await isolated.database.rows(
                            'SELECT * FROM crypto_identity_secrets',
                          ),
                          isEmpty,
                        );
                        expect(
                          await isolated.database.rows(
                            'SELECT 1 FROM crypto_scope_keys WHERE write_ready<>0',
                          ),
                          isEmpty,
                        );
                      },
                    );
                    if (fixture['auditFixture'] == true) {
                      final audit = CryptoMigrationAuditColdControl(
                        runtime,
                        coldSource,
                        externalFile,
                      );
                      final auditRows = await isolated.database.rows(
                        "SELECT binding_id FROM crypto_capture_sources WHERE json_extract(context,'\$.sourceTable')='familyhub_finance_audit'",
                      );
                      expect(auditRows.length, 1);
                      for (final row in auditRows) {
                        await audit.verify(
                          await CryptoMigrationColdSource.load(
                            runtime,
                            coldSource,
                            row['binding_id'] as String,
                          ),
                        );
                      }
                      final section = await audit.finish();
                      expect(section['kind'], 'audit');
                      expect(section['count'], 1);
                    }
                    expect(
                      (await coldAccount.store.anchor(
                        coldAccount.directory.accountId,
                      ))?['trustState'],
                      ownBefore?['trustState'],
                    );
                    expect(
                      await coldAccount.store.secure.read(
                        'scope2:${account.store.partition}:${fixture['scopeId']}',
                      ),
                      isNull,
                    );
                    await expectLater(
                      coldAccount.directory.requireFresh(),
                      throwsA(anything),
                    );
                  },
                );
              }
              final index = CryptoCaptureLegacyIndex(account);
              final verified = await index.certify(
                coldArchive: cold,
                domain: 'content',
              );
              if (Platform.environment['JIVIE_CAPTURE_TEST_LOCAL_INTENTS'] ==
                  '1') {
                await index.certify(coldArchive: cold, domain: 'finance');
                final originalIntent = crypto.randomId();
                await db.execute(
                  'INSERT INTO commands(id,partition,operation,params,entity_key) VALUES(?,?,?,?,?)',
                  [
                    originalIntent,
                    account.store.partition,
                    'inbox.read',
                    ' {"id":17,"read":true} ',
                    'preserved-original',
                  ],
                );
                final artifact = await CryptoMigrationLocalArtifact(account)
                    .stageAndUpload(
                      capture: descriptor,
                      sourceInventoryRoot: cold.sourceInventoryRoot,
                    );
                expect(artifact.result['intentCount'], 1);
                final retry = await CryptoMigrationLocalArtifact(account)
                    .stageAndUpload(
                      capture: descriptor,
                      sourceInventoryRoot: cold.sourceInventoryRoot,
                    );
                expect(retry.descriptor, artifact.descriptor);
                expect(retry.event, artifact.event);
                await archive.withVerifiedSourceFromFile<void>(
                  capture: descriptor,
                  manifest: manifest,
                  externalFile: externalFile,
                  use: (isolated, coldAccount, verifiedSource) async {
                    final runtime = CryptoBusinessSession(
                      coldAccount,
                      SessionCryptoAccess(account: coldAccount),
                      isolated.database,
                    );
                    final local = await verifyCryptoMigrationLocalArtifact(
                      runtime: runtime,
                      source: verifiedSource,
                      recoveryFile: externalFile,
                      descriptor: artifact.descriptor,
                      ownEvent: artifact.event,
                    );
                    expect(local.result, artifact.result);
                    final rows = await isolated.database.rows(
                      'SELECT frame FROM cold_local_intents',
                    );
                    expect(rows.length, 1);
                    expect(
                      (jsonDecode(rows.single['frame'] as String)
                          as Map)['row']['params'],
                      ' {"id":17,"read":true} ',
                    );
                    expect(
                      await isolated.database.rows('SELECT 1 FROM commands'),
                      isEmpty,
                    );
                    final receipts = CryptoMigrationReceiptControl(
                      runtime,
                      verifiedSource,
                      local,
                    );
                    final sources = await isolated.database.rows(
                      "SELECT binding_id FROM crypto_capture_sources WHERE json_extract(context,'\$.sourceTable') IN ('familyhub_operations','familyhub_finance_operations','familyhub_document_requests') ORDER BY binding_id",
                    );
                    for (final row in sources) {
                      await receipts.verify(
                        await CryptoMigrationColdSource.load(
                          runtime,
                          verifiedSource,
                          row['binding_id'] as String,
                        ),
                      );
                    }
                    final section = await receipts.finish();
                    expect(section['kind'], 'receipts');
                    expect(section['count'], sources.length + 1);
                  },
                );
                if (Platform.environment['JIVIE_CAPTURE_TEST_FULL_PARITY'] ==
                    '1') {
                  await CryptoMigrationNotificationProducer(
                    CryptoBusinessSession(
                      account,
                      SessionCryptoAccess(account: account),
                      db,
                    ),
                  ).stageAll(descriptor, acceptedRemoteDateDisclosure: false);
                  final business = CryptoMigrationColdBusiness(
                    account,
                    coldDatabase: () =>
                        CryptoArchiveColdDatabase.create(parent: receiptRoot),
                  );
                  final compared = await business.verifyProduction(
                    capture: descriptor,
                    manifest: manifest,
                    recoveryFile: externalFile,
                    localArtifact: artifact,
                  );
                  final accepted = await business.publishVerification(
                    compared,
                    artifact,
                  );
                  expect(accepted['version'], 3);
                  expect(accepted['summary'], compared.summary);
                  final domainRuntime = CryptoBusinessSession(
                    account,
                    SessionCryptoAccess(account: account),
                    db,
                  );
                  final notification =
                      await CryptoMigrationNotificationProducer(
                        domainRuntime,
                      ).certifyAndAnchor(compared);
                  expect(notification['state'], 'anchored');
                  final invitations =
                      await CryptoMigrationInvitations(
                        domainRuntime,
                      ).certifyAndAnchor(
                        capture: descriptor,
                        sourceInventoryRoot:
                            compared.header['sourceInventoryRoot'],
                        archiveManifestHash:
                            compared.header['archiveManifestHash'],
                        coldParityProofHash: accepted['coldParityProofHash'],
                      );
                  expect(invitations['state'], 'anchored');
                  if (Platform.environment['JIVIE_CAPTURE_TEST_DOMAINS'] ==
                      '1') {
                    final domains = CryptoMigrationDomainContributions(
                      domainRuntime,
                    );
                    for (final domain in ['content', 'finance']) {
                      await domains.prepare(
                        migrationId: descriptor.migrationId,
                        scopeId: fixture['scopeId'],
                        domain: domain,
                      );
                      if (domain == 'content') {
                        http.dropAcceptedOperation =
                            'crypto2.migration.domains.contribute';
                        await domains.contribute(
                          verified: compared,
                          scopeId: fixture['scopeId'],
                          domain: domain,
                        );
                        expect(http.dropAcceptedOperation, isNull);
                        await account.attestMigration(
                          migrationId: descriptor.migrationId,
                          scopeToken: '9' * 64,
                          domain: 'content',
                          attestationHash: '7' * 64,
                        );
                      }
                      final contribution = await domains.contribute(
                        verified: compared,
                        scopeId: fixture['scopeId'],
                        domain: domain,
                      );
                      expect(contribution['state'], 'staged');
                      if (domain == 'content') {
                        http.dropAcceptedOperation =
                            'crypto2.migration.domains.certify';
                        await domains.certify(
                          verified: compared,
                          scopeId: fixture['scopeId'],
                          domain: domain,
                        );
                        expect(http.dropAcceptedOperation, isNull);
                        await account.attestMigration(
                          migrationId: descriptor.migrationId,
                          scopeToken: '8' * 64,
                          domain: 'content',
                          attestationHash: '6' * 64,
                        );
                      }
                      final certificate = await domains.certify(
                        verified: compared,
                        scopeId: fixture['scopeId'],
                        domain: domain,
                      );
                      expect(certificate['state'], 'anchored');
                      final originalBodies = await db.rows(
                        'SELECT action_key,signed_body FROM crypto_command_keys k JOIN crypto_outbox o ON o.partition=k.partition AND o.request_id=k.request_id WHERE k.partition=? AND (k.action_key=? OR k.action_key=?) ORDER BY action_key',
                        [
                          session.profile.partition,
                          'domainContribution3:${descriptor.captureId}:${fixture['scopeId']}:$domain',
                          'domainCertify3:${descriptor.migrationId}:${fixture['scopeId']}:$domain',
                        ],
                      );
                      await account.attestMigration(
                        migrationId: descriptor.migrationId,
                        scopeToken: '5' * 64,
                        domain: 'content',
                        attestationHash: domain == 'content'
                            ? '4' * 64
                            : '3' * 64,
                      );
                      final restarted = CryptoMigrationDomainContributions(
                        CryptoBusinessSession(
                          account,
                          SessionCryptoAccess(account: account),
                          db,
                        ),
                      );
                      expect(
                        (await restarted.contribute(
                          verified: compared,
                          scopeId: fixture['scopeId'],
                          domain: domain,
                        ))['contributionHash'],
                        contribution['contributionHash'],
                      );
                      expect(
                        (await restarted.certify(
                          verified: compared,
                          scopeId: fixture['scopeId'],
                          domain: domain,
                        ))['certificateHash'],
                        certificate['certificateHash'],
                      );
                      final replayedBodies = await db.rows(
                        'SELECT action_key,signed_body FROM crypto_command_keys k JOIN crypto_outbox o ON o.partition=k.partition AND o.request_id=k.request_id WHERE k.partition=? AND (k.action_key=? OR k.action_key=?) ORDER BY action_key',
                        [
                          session.profile.partition,
                          'domainContribution3:${descriptor.captureId}:${fixture['scopeId']}:$domain',
                          'domainCertify3:${descriptor.migrationId}:${fixture['scopeId']}:$domain',
                        ],
                      );
                      expect(replayedBodies, originalBodies);
                    }
                    if (Platform.environment['JIVIE_CAPTURE_TEST_COMMIT'] ==
                        '1') {
                      final activations = CryptoMigrationActivationProducer(
                        domainRuntime,
                      );
                      final ref = await activations.stage(
                        verified: compared,
                        scopeId: fixture['scopeId'],
                      );
                      http.dropAcceptedOperation = 'crypto2.migration.commit3';
                      final committed = await activations.commit(
                        verified: compared,
                        scopeActivations: [ref],
                      );
                      expect(http.dropAcceptedOperation, isNull);
                      expect(committed['state'], 'committed');
                      migrationCommitted = true;
                      final restarted = CryptoMigrationActivationProducer(
                        CryptoBusinessSession(
                          account,
                          SessionCryptoAccess(account: account),
                          db,
                        ),
                      );
                      expect(
                        await restarted.stage(
                          verified: compared,
                          scopeId: fixture['scopeId'],
                        ),
                        ref,
                      );
                      expect(
                        await restarted.commit(
                          verified: compared,
                          scopeActivations: [ref],
                        ),
                        committed,
                      );
                    }
                  }
                }
              }
              final tuple = CryptoLegacyReceiptTuple(
                scopeId: fixture['scopeId'],
                kind: 'records',
                legacyId: fixture['legacyId'],
              );
              final captured = await verified.descriptor(tuple);
              expect(captured, isNotNull);
              final receipt = await archive.readReceiptFromFile(
                capture: descriptor,
                manifest: manifest,
                externalFile: externalFile,
                receipt: captured!,
              );
              try {
                receipt.requireOriginalRequestHash('a' * 64);
                expect(receipt.outcome, 'applied');
                expect(
                  utf8.decode(receipt.responseBytes),
                  '{"status":"accepted-before-lost-ack"}',
                );
              } finally {
                receipt.responseBytes.fillRange(
                  0,
                  receipt.responseBytes.length,
                  0,
                );
              }
              final absent = CryptoLegacyReceiptTuple(
                scopeId: fixture['scopeId'],
                kind: 'records',
                legacyId: crypto.randomId(),
              );
              expect(await verified.descriptor(absent), isNull);
              await expectLater(
                verified.descriptor(
                  CryptoLegacyReceiptTuple(
                    scopeId: crypto.randomId(),
                    kind: 'records',
                    legacyId: crypto.randomId(),
                  ),
                ),
                throwsA(isA<CryptoAuthorityPending>()),
              );
              // A complete flag surviving partial cache deletion must never
              // turn the accepted original request into proven absence.
              await db.execute(
                'DELETE FROM crypto_legacy_inventory_rows WHERE partition=? AND certificate_hash=? AND binding_id=?',
                [
                  session.profile.partition,
                  verified.certificateHash,
                  captured.bindingId,
                ],
              );
              await expectLater(
                verified.descriptor(tuple),
                throwsFormatException,
              );
              await expectLater(
                index.verify(
                  capture: descriptor,
                  domain: 'content',
                  sourceInventoryRoot: cold.sourceInventoryRoot,
                ),
                throwsFormatException,
              );
            } finally {
              await receiptRoot.delete(recursive: true);
            }
          }
        }
        final originalBindings = await db.rows(
          'SELECT binding_id,binding FROM crypto_capture_sources ORDER BY binding_id',
        );
        final expectedRoot = await CryptoCaptureV3.inventoryRoot(
          serverId: session.profile.serverId,
          captureId: descriptor.captureId,
          migrationId: descriptor.migrationId,
          accountId: session.profile.accountId,
          sourceCount: originalBindings.length,
          bindings: Stream.fromIterable(
            originalBindings.map(
              (r) => CryptoCaptureBinding.fromJson(
                jsonDecode(r['binding'] as String) as Map<String, dynamic>,
              ),
            ),
          ),
        );
        final commands = await db.rows('SELECT signed_body FROM crypto_outbox');
        for (final raw in commands) {
          final proof = jsonDecode(raw['signed_body'] as String) as Map;
          final command =
              CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map;
          final text = jsonEncode(command);
          expect(text, isNot(contains('sourceRowHash')));
          expect(text, isNot(contains('saltBase64')));
          expect(text, isNot(contains('CAPTURE_PRIVATE_SENTINEL')));
          expect(text, isNot(contains('storedRequestHash')));
        }
        expect(
          (await db.rows(
            'SELECT key_bytes FROM crypto_capture_keys',
          )).single['key_bytes'],
          isNull,
        );
        final substituted = CryptoCaptureKeyDescriptor.fromJson({
          ...descriptor.toJson(),
          'componentId': crypto.randomId(),
        });
        await expectLater(
          CryptoCaptureKeyService(account).open(substituted),
          throwsFormatException,
        );
        await db.close();
        originalClosed = true;
        // Neither old device secrets nor OS anchor store are copied. Only the
        // original external file is used to independently anchor the account.
        var coldSession = session;
        if (interrupt || migrationCommitted) {
          final login = await http.call(
            serverUrl: session.profile.serverUrl,
            operation: 'auth.login',
            params: {
              'username': fixture['username'],
              'password': fixture['password'],
              'deviceName': 'Synthetic capture3 lost all devices',
            },
            allowLocalHttp: true,
          );
          final u = login['user'] as Map, d = login['device'] as Map;
          coldSession = DeviceSession(
            AccountSession(
              serverUrl: session.profile.serverUrl,
              serverId: login['serverId'],
              accountId: u['accountId'],
              userId: u['id'],
              username: u['username'],
              displayName: u['displayName'],
              deviceId: d['id'],
              expiresAt: DateTime.fromMillisecondsSinceEpoch(
                d['expiresAt'] * 1000,
              ),
              allowLocalHttp: true,
            ),
            login['token'],
          );
          expect(coldSession.profile.deviceId, isNot(session.profile.deviceId));
        }
        final coldRoot = await Directory.systemTemp.createTemp(
          'synthetic-capture3-cold-',
        );
        final cold = await CryptoArchiveColdDatabase.create(parent: coldRoot);
        try {
          final coldAccount = AccountCryptoV2Workflow(
            AccountDirectoryRepository(
              reducer: AccountDirectoryV2(crypto),
              session: coldSession,
              transport: http,
              store: CryptoIdentityStore(
                cold.database,
                _Secure(),
                session.profile.partition,
              ),
              isCurrent: () => true,
            ),
          );
          if (migrationCommitted) {
            await coldAccount.recover(externalFile);
            var recoveryIncomplete = false;
            try {
              await CryptoScopeObservations(
                coldAccount,
              ).hydrateObservedScopes(externalFile);
            } on CryptoScopeRecoveryIncomplete catch (error) {
              recoveryIncomplete = true;
              debugPrint(
                'synthetic FILE recovery pending scopes=${error.pendingScopes} ownAnchors=${error.unmatchedOwnAnchors} discovery=${error.discoveryPending}',
              );
              // Diagnose independently verified scoped reads even while the
              // account-wide completeness classifier remains explicitly pending.
            }
            expect(
              await cold.database.rows('SELECT * FROM crypto_capture_runs'),
              isEmpty,
            );
            final publicCoordinator =
                public_migration.CryptoMigrationCoordinator(
                  account: coldAccount,
                );
            try {
              expect(
                (await publicCoordinator.inspect(fixture['scopeId'])).phase,
                public_migration.CryptoMigrationPhase.committed,
              );
            } finally {
              await publicCoordinator.close();
            }
            final normal = CryptoBusinessRouter(
              database: cold.database,
              accountFor: (_) async => coldAccount,
            );
            final sourceBlobReads =
                http.counts['crypto2.migration.blob.get'] ?? 0;
            final ordinaryBlobReads = http.counts['crypto2.blob.get'] ?? 0;
            for (var pass = 0; pass < 4; pass++) {
              await normal.dispatch(
                session: coldSession,
                operation: 'sync6.pull',
                params: {'scopeId': fixture['scopeId'], 'cursor': 0},
                protectedScopeIds: {fixture['scopeId']},
              );
              await normal.dispatch(
                session: coldSession,
                operation: 'finance4.pull',
                params: {'scopeId': fixture['scopeId'], 'cursor': 0},
                protectedScopeIds: {fixture['scopeId']},
              );
            }
            final restored = await cold.database.rows(
              "SELECT type,json_extract(projection,'\$.id') AS canonical_id,crypto_revision,legacy_revision,raw_payload FROM crypto_business_records WHERE partition=? AND scope_id=?",
              [coldSession.profile.partition, fixture['scopeId']],
            );
            debugPrint(
              'synthetic committed cold types=${restored.map((r) => r['type']).toList()}',
            );
            final pending = await cold.database.rows(
              "SELECT json_extract(wire,'\$.type') AS type,verdict,error FROM crypto_received WHERE verdict<>'verified'",
            );
            debugPrint('synthetic committed cold pending=$pending');
            final task = restored.singleWhere(
              (r) =>
                  r['type'] == 'task' && r['canonical_id'] == fixture['taskId'],
            );
            expect(
              jsonDecode(task['raw_payload'] as String),
              jsonDecode(fixture['payload'] as String),
            );
            expect(task['crypto_revision'], 1);
            expect(task['legacy_revision'], 50);
            expect(
              restored.any((r) => r['canonical_id'] == fixture['expenseId']),
              true,
            );
            final audit = await normal.dispatch(
              session: coldSession,
              operation: 'finance4.audit',
              params: {
                'scopeId': fixture['scopeId'],
                'recordId': fixture['expenseId'],
                'limit': 50,
              },
              protectedScopeIds: {fixture['scopeId']},
            );
            final entries = audit['entries'] as List;
            expect(entries.length, 1);
            expect(entries.single['revision'], 31);
            expect(entries.single['revisionNamespace'], 'legacy');
            expect(
              entries.single['changedAt'],
              '2020-01-02T03:04:05.123+01:00',
            );
            expect(
              entries.single['beforeJson'],
              '{"unknown":{"fraction":0.1,"negativeZero":-0.0}}',
            );
            expect(
              jsonDecode(entries.single['afterJson']),
              jsonDecode(fixture['entryPayload']),
            );
            await cold.database.execute('DELETE FROM crypto_document_cache');
            final downloaded = BytesBuilder(copy: false);
            final total = fixture['fileBytes'] as int;
            while (downloaded.length < total) {
              final offset = downloaded.length;
              final file = await normal.dispatch(
                session: coldSession,
                operation: 'attachments.get',
                params: {
                  'scopeId': fixture['scopeId'],
                  'id': fixture['attachmentId'],
                  'targetType': 'scope',
                  'targetId': fixture['scopeId'],
                  'offset': offset,
                  'limit': 196608,
                },
                protectedScopeIds: {fixture['scopeId']},
              );
              final bytes = cryptoBase64(file['dataBase64']);
              expect(file['offset'], offset);
              expect(file['total'], total);
              expect(bytes.length, (total - offset).clamp(0, 196608));
              downloaded.add(bytes);
            }
            expect(
              await cryptoSha256(downloaded.takeBytes()),
              fixture['fileSha256'],
            );
            expect(
              http.counts['crypto2.migration.blob.get'] ?? 0,
              sourceBlobReads,
            );
            expect(
              http.counts['crypto2.blob.get'] ?? 0,
              greaterThan(ordinaryBlobReads),
            );
            expect(
              await cold.database.rows(
                "SELECT 1 FROM crypto_outbox WHERE operation='crypto2.records.batch'",
              ),
              isEmpty,
            );
            expect(
              await cold.database.rows('SELECT * FROM crypto_capture_runs'),
              isEmpty,
            );
            expect(
              recoveryIncomplete,
              false,
              reason:
                  'FILE recovery must classify every included own publication/control anchor',
            );
            return;
          }
          final coldCoordinator = CryptoCaptureCoordinator(coldAccount);
          http.alteredComponentId = crypto.randomId();
          await expectLater(
            coldCoordinator.resumeFromFile(
              fixture['scopeId'] as String,
              externalFile,
            ),
            throwsFormatException,
          );
          expect(
            await cold.database.rows('SELECT * FROM crypto_capture_runs'),
            isEmpty,
          );
          http.alteredComponentId = null;
          // No test-supplied descriptor or privileged local freshness promotion.
          late Map<String, dynamic> resealed;
          if (interrupt) {
            await expectLater(
              coldCoordinator.resumeFromFile(
                fixture['scopeId'] as String,
                externalFile,
              ),
              throwsA(
                isA<CryptoAuthorityPending>().having(
                  (e) => e.reason,
                  'reason',
                  'crypto_capture_resume_approval_required',
                ),
              ),
            );
            expect(
              await cold.database.rows('SELECT * FROM crypto_outbox'),
              isEmpty,
            );
            // The production P7 recovery operation establishes future authority;
            // no test-only secure pin/phase is promoted to bypass this step.
            await coldAccount.recover(externalFile);
            expect(
              (await coldAccount.store.anchor(
                session.profile.accountId,
              ))?['trustState'],
              'verified',
            );
            final rootStatus = await coldAccount.status();
            final inspected = coldAccount.files.inspect(
              externalFile,
              serverId: session.profile.serverId,
              accountId: session.profile.accountId,
            );
            final recovered = coldAccount.files.open(
              file: externalFile,
              encryptedRoot:
                  CryptoJson.decode(
                        cryptoBase64(rootStatus['keyringCiphertextBase64']),
                      )
                      as Map<String, dynamic>,
              serverId: session.profile.serverId,
              accountId: session.profile.accountId,
              expectedFingerprint: inspected['fingerprint'] as String,
            );
            try {
              Future<KeyPair?> recoveryKey(String public) async {
                for (final pair in [
                  recovered.encryption,
                  ...recovered.historicalEncryption,
                ]) {
                  if (base64Encode(pair.publicKey) == public) {
                    final raw = pair.secretKey.extractBytes();
                    try {
                      return KeyPair(
                        publicKey: Uint8List.fromList(pair.publicKey),
                        secretKey: crypto.sodium.secureCopy(raw),
                      );
                    } finally {
                      raw.fillRange(0, raw.length, 0);
                    }
                  }
                }
                return null;
              }

              final reopened = await coldCoordinator.prepare(
                fixture['scopeId'] as String,
                recoveryKey: recoveryKey,
                recoveryOnly: true,
              );
              expect(reopened.toJson(), descriptor.toJson());
              resealed = await coldCoordinator.captureSources(
                reopened,
                recoveryKey: recoveryKey,
                recoveryOnly: true,
              );
            } finally {
              recovered.dispose();
            }
          } else {
            resealed = await coldCoordinator.resumeFromFile(
              fixture['scopeId'] as String,
              externalFile,
            );
            expect(
              resealed['historicalFreshness'],
              'unconfirmedCapturedSource',
            );
          }
          expect(resealed['captureId'], descriptor.captureId);
          expect(resealed['keyId'], descriptor.keyId);
          expect(resealed['inventoryRoot'], expectedRoot);
          expect(
            await cold.database.rows(
              'SELECT binding_id,binding FROM crypto_capture_sources ORDER BY binding_id',
            ),
            originalBindings,
          );
          expect(
            await cold.database.rows('SELECT * FROM crypto_identity_secrets'),
            interrupt ? isNotEmpty : isEmpty,
          );
          expect(
            await cold.database.rows('SELECT * FROM crypto_outbox'),
            interrupt ? isNotEmpty : isEmpty,
          );
          expect(
            (await coldAccount.store.anchor(
              session.profile.accountId,
            ))?['trustState'],
            interrupt ? 'verified' : 'freshnessPending',
          );
          await expectLater(
            CryptoCaptureKeyService(coldAccount).ensure(
              captureId: descriptor.captureId,
              migrationId: descriptor.migrationId,
            ),
            throwsA(isA<Exception>()),
          );
        } finally {
          await cold.close();
          await coldRoot.delete(recursive: true);
        }
      } finally {
        externalFile.fillRange(0, externalFile.length, 0);
      }
    },
    skip: path == null,
    timeout: const Timeout(Duration(minutes: 4)),
  );
}

/// Opt-in, synthetic-loopback-only checkpoint for the unchanged postcommit
/// tail. Private snapshots are never imported into production or a live queue.
Future<Directory?> _publicCheckpointDirectory() async {
  final path =
      Platform.environment['JIVIE_CAPTURE_POSTCOMMIT_DIAGNOSTIC_DIRECTORY'];
  if (path == null) return null;
  final target = Directory(path);
  if (!target.isAbsolute) throw StateError('Checkpoint path must be absolute');
  final parent = await target.parent.resolveSymbolicLinks(),
      repository = await Directory.current.resolveSymbolicLinks();
  if (parent == repository ||
      parent.startsWith('$repository/') ||
      (await Directory(parent).stat()).mode & 0x3f != 0) {
    throw StateError(
      'Checkpoint requires a private directory outside the repository',
    );
  }
  final output = Directory(
    '$parent/${target.uri.pathSegments.where((s) => s.isNotEmpty).last}',
  );
  // mkdir is exclusive; protect the new directory before any secret is written.
  final created = await Process.run('/bin/mkdir', ['-m', '700', output.path]);
  if (created.exitCode != 0) {
    throw StateError('Cannot create private checkpoint');
  }
  return output;
}

Future<void> _savePublicCheckpoint(
  Directory? directory,
  String role,
  AccountCryptoV2Workflow account,
  Uint8List recoveryFile, {
  Map<String, Object?>? references,
}) async {
  if (directory == null) return;
  Future<File> privateFile(String suffix) async {
    final output = File('${directory.path}/$role.$suffix');
    await output.create(exclusive: true);
    final permissions = await Process.run('/bin/chmod', ['600', output.path]);
    if (permissions.exitCode != 0) {
      throw StateError('Cannot protect checkpoint');
    }
    return output;
  }

  final secure = account.store.secure;
  if (secure is! _Secure) throw StateError('Synthetic secure store required');
  final database = await privateFile('sqlite');
  final quotedPath = database.path.replaceAll("'", "''");
  await account.store.database.execute("VACUUM INTO '$quotedPath'");
  final session = account.directory.session;
  await (await privateFile('session.json')).writeAsString(
    jsonEncode({'profile': session.profile.toJson(), 'token': session.token}),
    flush: true,
  );
  await (await privateFile(
    'secure.json',
  )).writeAsString(jsonEncode(secure.values), flush: true);
  await (await privateFile(
    'recovery.file',
  )).writeAsBytes(recoveryFile, flush: true);
  if (references != null) {
    await (await privateFile(
      'references.json',
    )).writeAsString(jsonEncode(references), flush: true);
  }
}

Future<void> _publicCoordinator(String path) async {
  final root = await Directory.systemTemp.createTemp(
    'synthetic-public-coordinator-',
  );
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final fixture = Map<String, dynamic>.from(
    jsonDecode(await File(path).readAsString()),
  );
  if (fixture['synthetic'] != true ||
      Uri.parse(fixture['serverUrl']).host != '127.0.0.1') {
    throw StateError('Synthetic loopback only');
  }
  DeviceSession session(Map wire) {
    final u = wire['user'] as Map, d = wire['device'] as Map;
    return DeviceSession(
      AccountSession(
        serverUrl: fixture['serverUrl'],
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
  }

  final http = _SyntheticHttp();
  final crypto = CryptoCodec(await SodiumInit.init());
  AccountCryptoV2Workflow workflow(
    CollaborationDatabase db,
    DeviceSession login,
  ) => AccountCryptoV2Workflow(
    AccountDirectoryRepository(
      reducer: AccountDirectoryV2(crypto),
      session: login,
      transport: http,
      store: CryptoIdentityStore(db, _Secure(), login.profile.partition),
      isCurrent: () => true,
    ),
  );
  var liveDb = CollaborationDatabase(NativeDatabase.memory());
  final login = session(fixture['session'] as Map);
  final account = workflow(liveDb, login);
  final file = await account.prepareRecoveryFile();
  final coordinator = public_migration.CryptoMigrationCoordinator(
    account: account,
    coldDatabase: () => CryptoArchiveColdDatabase.create(parent: root),
  );
  final events = <public_migration.CryptoMigrationPhase>[];
  final elapsed = Stopwatch()..start();
  var pauses = 0;
  final phaseCalls = <String, int>{};
  final subscription = coordinator.changes.listen((s) {
    events.add(s.phase);
    if (s.retryAfterSeconds != null) pauses++;
    phaseCalls.putIfAbsent(
      s.phase.name,
      () => http.attempts.values.fold<int>(0, (a, b) => a + b),
    );
  });
  var closed = false;
  CombinedCaptureChoices? combined;
  try {
    await account.verifyAndInitialize(file);
    if (fixture['combinedChoiceFixture'] == true) {
      combined = await CombinedCaptureChoices.create(
        fixture: fixture,
        coldParent: root,
        session: session,
        workflow: workflow,
        reader: account,
      );
    }
    final localIntentId = crypto.randomId();
    await liveDb.execute(
      'INSERT INTO commands(id,partition,operation,params,entity_key) VALUES(?,?,?,?,?)',
      [
        localIntentId,
        account.store.partition,
        'inbox.read',
        ' {"id":17,"read":true} ',
        'original-local-intent',
      ],
    );

    var paused = 0;
    if (fixture['ideaFixture'] == true) {
      final workspace =
          'shared:${account.store.partition}:${fixture['scopeId']}';
      await liveDb.execute('INSERT INTO idea_drafts VALUES(?,?,?,NULL)', [
        workspace,
        fixture['orphanIdeaBoardId'],
        jsonEncode(fixture['orphanIdeaDraft']),
      ]);
      await liveDb.execute('INSERT INTO idea_assets VALUES(?,?,?,?)', [
        workspace,
        fixture['ideaSha256'],
        jsonEncode({
          'sha256': fixture['ideaSha256'],
          'mime': 'image/png',
          'size': fixture['ideaBytes'],
          'width': 1,
          'height': 1,
        }),
        cryptoBase64(fixture['ideaDataBase64']),
      ]);
    }
    Future<T> resume<T>(Future<T> Function() action) async {
      while (true) {
        try {
          return await action();
        } on CollaborationApiException catch (error) {
          final retry = error.details['retryAfter'];
          if (error.code != 'rate_limited' ||
              retry is! int ||
              retry < 1 ||
              retry > 60 ||
              ++paused > 4) {
            rethrow;
          }
          final rows = await liveDb.rows(
            "SELECT journal FROM crypto_migrations WHERE partition=?",
            [account.store.partition],
          );
          expect(
            rows.any(
              (r) =>
                  (jsonDecode(r['journal'] as String) as Map)['retryNotBefore']
                      is int,
            ),
            true,
          );
          // The real coordinator returns a durable pause. The synthetic driver
          // acts as a user returning after that deadline; it does not replace
          // the production transport or modify the original signed command.
          await Future<void>.delayed(Duration(seconds: retry + 1));
        }
      }
    }

    final prepared = await resume(
      () => coordinator.prepare(fixture['scopeId']),
    );
    final migration = prepared.migrationId!;
    final review = await resume(() => coordinator.review(migration));
    expect(
      review.rowCount,
      greaterThan(
        combined == null ? 8 + (fixture['extraRecords'] as int? ?? 0) : 1,
      ),
    );
    debugPrint('public coordinator source rows=${review.rowCount}');
    await combined?.prepareOwner(migration);
    await resume(
      () => coordinator.fence(
        migration,
        reviewedInventoryHash: review.inventoryHash,
      ),
    );
    await combined?.fenceOwner(migration);
    http.dropAcceptedOperation = 'crypto2.migration.commit3';
    final complete = combined == null
        ? await resume(
            () => coordinator.archiveAndVerify(migration, recoveryFile: file),
          )
        : await combined.finish(
            migration: migration,
            readerCoordinator: coordinator,
            reader: account,
            readerFile: file,
          );
    expect(complete.phase, public_migration.CryptoMigrationPhase.committed);
    expect(http.dropAcceptedOperation, isNull);
    expect(http.counts['crypto2.migration.commit'] ?? 0, 0);
    expect(http.counts['crypto2.migration.archive.begin'] ?? 0, 0);
    await Future<void>.delayed(Duration.zero);
    expect(events.last, public_migration.CryptoMigrationPhase.committed);
    final commitDatabase = combined?.ownerDb ?? liveDb;
    final original = await commitDatabase.rows(
      "SELECT signed_body,request_hash FROM crypto_outbox WHERE operation='crypto2.migration.commit3'",
    );
    expect(original, hasLength(1));
    expect(
      (await coordinator.inspect(fixture['scopeId'])).phase,
      public_migration.CryptoMigrationPhase.committed,
    );
    expect(
      await commitDatabase.rows(
        "SELECT signed_body,request_hash FROM crypto_outbox WHERE operation='crypto2.migration.commit3'",
      ),
      original,
    );
    final checkpoint = await _publicCheckpointDirectory();
    await _savePublicCheckpoint(checkpoint, 'readerOriginal', account, file);
    if (combined != null) {
      await _savePublicCheckpoint(
        checkpoint,
        'owner',
        combined.owner,
        combined.ownerFile,
      );
    }
    await liveDb.close();
    closed = true;
    final freshWire = await http.call(
      serverUrl: login.profile.serverUrl,
      operation: 'auth.login',
      allowLocalHttp: true,
      params: {
        'username': fixture['username'],
        'password': fixture['password'],
        'deviceName': 'Synthetic public coordinator FILE only',
      },
    );
    final fresh = session(freshWire);
    final coldDb = CollaborationDatabase(NativeDatabase.memory());
    final cold = workflow(coldDb, fresh);
    final continuationReferences = <String, Object?>{
      'synthetic': true,
      'fixturePath': path,
      'scopeId': fixture['scopeId'],
      'childScopeId': fixture['childScopeId'],
      'ledgerId': fixture['ledgerId'],
      'childEntryId': fixture['childEntryId'],
      'phase': 'coldRecoveryStarted',
    };
    Future<void> saveTail(String phase) async {
      final references = {...continuationReferences, 'snapshotPhase': phase};
      if (combined != null) {
        await _savePublicCheckpoint(
          checkpoint,
          '${phase}Owner',
          combined.owner,
          combined.ownerFile,
          references: references,
        );
      }
      await _savePublicCheckpoint(
        checkpoint,
        '${phase}Reader',
        cold,
        file,
        references: references,
      );
    }

    try {
      await cold.recover(file);
      final diagnosticFilePath =
          Platform.environment['JIVIE_CAPTURE_RECOVERY_DIAGNOSTIC_FILE'];
      if (diagnosticFilePath != null) {
        // Synthetic-loopback guard above is mandatory. This opt-in output is
        // only for the already-created FILE, never a repository/test artifact.
        final target = File(diagnosticFilePath);
        if (!target.isAbsolute) {
          throw StateError('Diagnostic FILE path must be absolute');
        }
        final parent = await target.parent.resolveSymbolicLinks(),
            repository = await Directory.current.resolveSymbolicLinks();
        if (parent == repository || parent.startsWith('$repository/')) {
          throw StateError(
            'Diagnostic FILE must remain outside the repository',
          );
        }
        if ((await Directory(parent).stat()).mode & 0x3f != 0) {
          throw StateError('Diagnostic FILE requires a private directory');
        }
        final output = File('$parent/${target.uri.pathSegments.last}');
        await output.create(exclusive: true);
        try {
          final permissions = await Process.run('/bin/chmod', [
            '600',
            output.path,
          ]);
          if (permissions.exitCode != 0) {
            throw StateError('Cannot protect diagnostic FILE');
          }
          await output.writeAsBytes(file, flush: true);
        } catch (_) {
          await output.delete();
          rethrow;
        }
      }
      try {
        await CryptoScopeObservations(cold).hydrateObservedScopes(file);
      } on CryptoScopeRecoveryIncomplete catch (error) {
        const allowedReasons = {
          'scope_authority_history_pending',
          'scope_key_recovery_required',
          'scope_history_keys_pending',
          'grant_recipients_pending',
          'scope_key_pending',
          'scope_key_provenance_pending',
          'scope_grants_changed',
          'grant_manifest_inventory_pending',
          'scope_read_forbidden',
          'scope_rotation_required',
          'crypto_migration_provenance_pending',
          'crypto_own_attestation_pending',
          'crypto_own_attestation_scoped_pending',
          'scope_recovery_publication_changed',
          'scope_recovery_identity_changed',
          'scope_descriptor_migration_pending',
          'crypto_observed_inventory_pending',
          'directory_known_ancestry_pending',
        };
        final pending = await coldDb.rows(
          "SELECT payload FROM crypto_membership_intents WHERE partition=? AND intent_id='fileScopeRecovery' AND state='scopeRecoveryPending'",
          [cold.store.partition],
        );
        final reasons = <String, int>{};
        for (final row in pending) {
          final payload =
              CryptoJson.decode(
                    Uint8List.fromList((row['payload'] as List).cast<int>()),
                  )
                  as Map;
          final raw = payload['reason'];
          final reason = allowedReasons.contains(raw)
              ? raw as String
              : 'otherPending';
          reasons[reason] = (reasons[reason] ?? 0) + 1;
        }
        final unmatched = await coldDb.rows(
          "SELECT e.payload FROM crypto_membership_intents e WHERE e.partition=? AND e.scope_id=? AND e.state='scopeRecoveryExpected' AND NOT EXISTS (SELECT 1 FROM crypto_membership_intents c WHERE c.partition=e.partition AND c.scope_id=e.scope_id AND c.intent_id='scopeRecoveryCovered:'||json_extract(CAST(e.payload AS TEXT),'\$.commandHash') AND json_extract(CAST(c.payload AS TEXT),'\$.runId')=json_extract(CAST(e.payload AS TEXT),'\$.runId'))",
          [cold.store.partition, cold.directory.accountId],
        );
        final kinds = <String, int>{};
        for (final row in unmatched) {
          final payload =
              CryptoJson.decode(
                    Uint8List.fromList((row['payload'] as List).cast<int>()),
                  )
                  as Map;
          final kind =
              http.recoveryAttestationKinds[payload['commandHash']] ??
              'notClassified';
          kinds[kind] = (kinds[kind] ?? 0) + 1;
        }
        debugPrint(
          'FILE recovery incomplete diagnostic=${jsonEncode({'pendingScopes': error.pendingScopes, 'unmatchedOwnAnchors': error.unmatchedOwnAnchors, 'discoveryPending': error.discoveryPending, 'scopePendingReasons': reasons, 'unmatchedAttestationKinds': kinds})}',
        );
        rethrow;
      }
      expect(await coldDb.rows('SELECT * FROM crypto_migrations'), isEmpty);
      expect(await coldDb.rows('SELECT * FROM crypto_capture_runs'), isEmpty);
      final reconstructed = public_migration.CryptoMigrationCoordinator(
        account: cold,
      );
      try {
        expect(
          (await reconstructed.inspect(fixture['scopeId'])).phase,
          public_migration.CryptoMigrationPhase.committed,
        );
      } finally {
        await reconstructed.close();
      }
      expect(await cold.hasIncompleteScopeRecovery(), false);
      await _savePublicCheckpoint(checkpoint, 'readerRecovered', cold, file);
      final quarantined = await coldDb.rows(
        'SELECT frame FROM cold_local_intents',
      );
      final expectedTables = <String>{
        'commands',
        if (fixture['ideaFixture'] == true) ...['idea_drafts', 'idea_assets'],
        if (combined != null) ...[
          'crypto_account_choice_selections',
          'crypto_export_drafts',
        ],
      };
      expect(quarantined, hasLength(expectedTables.length));
      expect(
        quarantined.map(
          (row) => (jsonDecode(row['frame'] as String) as Map)['table'],
        ),
        unorderedEquals(expectedTables),
      );
      expect(
        (jsonDecode(
              quarantined.singleWhere(
                    (v) =>
                        (jsonDecode(v['frame'] as String) as Map)['kind'] ==
                        'legacyRow',
                  )['frame']
                  as String,
            )
            as Map)['row']['params'],
        ' {"id":17,"read":true} ',
      );
      expect(await coldDb.rows('SELECT * FROM commands'), isEmpty);
      if (fixture['ideaFixture'] == true) {
        final workspace =
            'shared:${cold.store.partition}:${fixture['scopeId']}';
        final drafts = await CryptoMigrationIdeaDraftRecovery.rows(
          coldDb,
          workspace,
          'idea_drafts',
          id: fixture['orphanIdeaBoardId'],
        );
        expect(
          jsonDecode(drafts.single['payload']),
          fixture['orphanIdeaDraft'],
        );
        expect(await coldDb.rows('SELECT * FROM idea_drafts'), isEmpty);
        expect(await coldDb.rows('SELECT * FROM idea_assets'), isEmpty);
      }

      final normal = CryptoBusinessRouter(
        database: coldDb,
        accountFor: (_) async => cold,
      );
      for (var pass = 0; pass < 80; pass++) {
        for (final op in ['sync6.pull', 'finance4.pull']) {
          await normal.dispatch(
            session: fresh,
            operation: op,
            params: {'scopeId': fixture['scopeId'], 'cursor': 0},
            protectedScopeIds: {fixture['scopeId']},
          );
        }
        final count =
            (await coldDb.rows(
                  'SELECT COUNT(*) AS n FROM crypto_business_records',
                )).single['n']
                as int;
        if (count ==
            9 +
                (fixture['extraRecords'] as int? ?? 0) +
                (fixture['ideaFixture'] == true ? 1 : 0)) {
          break;
        }
      }
      expect(
        (await coldDb.rows(
          'SELECT COUNT(*) AS n FROM crypto_business_records',
        )).single['n'],
        9 +
            (fixture['extraRecords'] as int? ?? 0) +
            (fixture['ideaFixture'] == true ? 1 : 0),
      );
      if ((fixture['extraRecords'] as int? ?? 0) > 0) {
        final sample = (await coldDb.rows(
          "SELECT raw_payload FROM crypto_business_records WHERE json_extract(projection,'\$.id')=?",
          [fixture['extraSampleId']],
        )).single;
        expect(
          jsonDecode(sample['raw_payload'] as String),
          jsonDecode(fixture['extraSamplePayload'] as String),
        );
      }
      final records = await coldDb.rows(
        'SELECT type,projection,raw_payload,legacy_revision FROM crypto_business_records',
      );
      final task = records.singleWhere(
        (r) =>
            r['type'] == 'task' &&
            (jsonDecode(r['projection'] as String) as Map)['id'] ==
                fixture['taskId'],
      );
      expect(
        jsonDecode(task['raw_payload'] as String),
        jsonDecode(fixture['payload'] as String),
      );
      expect(task['legacy_revision'], 50);
      final expense = records.singleWhere((r) => r['type'] == 'financeEntry');
      expect(
        jsonDecode(expense['raw_payload'] as String),
        jsonDecode(fixture['entryPayload'] as String),
      );
      final audit = await normal.dispatch(
        session: fresh,
        operation: 'finance4.audit',
        params: {
          'scopeId': fixture['scopeId'],
          'recordId': fixture['expenseId'],
          'limit': 50,
        },
        protectedScopeIds: {fixture['scopeId']},
      );
      final auditEntries = audit['entries'] as List;
      expect(auditEntries.length, 1);
      expect(auditEntries.single['revision'], 31);
      expect(auditEntries.single['revisionNamespace'], 'legacy');
      expect(
        auditEntries.single['actorAccountId'],
        fixture['sourceActorAccountId'] ??
            fixture['session']['user']['accountId'],
      );
      expect(auditEntries.single['changedAt'], '2020-01-02T03:04:05.123+01:00');
      expect(
        auditEntries.single['beforeJson'],
        '{"unknown":{"fraction":0.1,"negativeZero":-0.0}}',
      );
      expect(
        jsonDecode(auditEntries.single['afterJson']),
        jsonDecode(fixture['entryPayload']),
      );
      await coldDb.execute('DELETE FROM crypto_document_cache');
      final sourceReads = http.counts['crypto2.migration.blob.get'] ?? 0;
      final blobReads = http.counts['crypto2.blob.get'] ?? 0;
      final downloaded = BytesBuilder(copy: false);
      final total = fixture['fileBytes'] as int;
      while (downloaded.length < total) {
        final offset = downloaded.length;
        final chunk = await normal.dispatch(
          session: fresh,
          operation: 'attachments.get',
          params: {
            'scopeId': fixture['scopeId'],
            'id': fixture['attachmentId'],
            'targetType': 'scope',
            'targetId': fixture['scopeId'],
            'offset': offset,
            'limit': 196608,
          },
          protectedScopeIds: {fixture['scopeId']},
        );
        final bytes = cryptoBase64(chunk['dataBase64']);
        expect(chunk['offset'], offset);
        expect(chunk['total'], total);
        expect(bytes.length, (total - offset).clamp(0, 196608));
        downloaded.add(bytes);
      }
      expect(await cryptoSha256(downloaded.takeBytes()), fixture['fileSha256']);
      if (fixture['ideaFixture'] == true) {
        final image = await normal.dispatch(
          session: fresh,
          operation: 'ideas.asset.get',
          params: {
            'scopeId': fixture['scopeId'],
            'boardId': fixture['ideaBoardId'],
            'sha256': fixture['ideaSha256'],
            'offset': 0,
            'limit': 262144,
          },
          protectedScopeIds: {fixture['scopeId']},
        );
        final imageBytes = cryptoBase64(image['data']);
        expect(imageBytes.length, fixture['ideaBytes']);
        expect(await cryptoSha256(imageBytes), fixture['ideaSha256']);
        imageBytes.fillRange(0, imageBytes.length, 0);
      }
      expect(http.counts['crypto2.migration.blob.get'] ?? 0, sourceReads);
      expect(http.counts['crypto2.blob.get'] ?? 0, greaterThan(blobReads));
      final types = (await coldDb.rows(
        'SELECT type FROM crypto_business_records',
      )).map((r) => r['type']).toSet();
      expect(
        types,
        containsAll([
          'task',
          'scopeMetadata',
          'financeAccount',
          'financeEntry',
          'attachment',
        ]),
      );
      expect(
        await coldDb.rows(
          "SELECT verdict,error FROM crypto_received WHERE verdict<>'verified'",
        ),
        isEmpty,
      );
      await combined?.finalRemoval(
        recoveredReader: cold,
        readerRouter: normal,
        loseAcceptedReply: (operation) =>
            http.dropAcceptedOperation = operation,
        checkpointBeforeDelete: (references) async {
          continuationReferences.addAll(references);
          await saveTail(references['phase'] as String);
        },
      );
      expect(http.dropAcceptedOperation, isNull);
    } finally {
      try {
        await saveTail('tailFinally');
      } finally {
        await coldDb.close();
      }
    }
  } finally {
    debugPrint(
      'public coordinator profile=${jsonEncode({
        'elapsedMs': elapsed.elapsedMilliseconds,
        'migrationRatePauses': pauses,
        'phaseFirstAttempt': phaseCalls,
        'attempts': {for (final op in http.attempts.keys.toList()..sort()) op: http.attempts[op]},
      })}',
    );
    await subscription.cancel();
    await combined?.close();
    await coordinator.close();
    if (!closed) await liveDb.close();
    file.fillRange(0, file.length, 0);
    http.close();
    await root.delete(recursive: true);
  }
}
