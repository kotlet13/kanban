import 'crypto_consent_generation.dart';
import 'dart:convert';

import 'crypto_business_router.dart';
import 'crypto_business_finance.dart';
import 'crypto_capture_coordinator.dart';
import 'crypto_capture_keys.dart';
import 'crypto_capture_v3.dart';
import 'crypto_migration_witness.dart';
import 'crypto_migration_witness_transport.dart';
import 'crypto_migration_file_object.dart';
import 'crypto_migration_idea_files.dart';
import 'crypto_migration_idea_payload.dart';
import 'crypto_migration_task_resolution.dart';
import 'crypto_migration_captured_choices.dart';
import 'crypto_business_json.dart';
import 'crypto_json.dart';
import 'crypto_migration_record_source.dart';
import 'crypto_sync_repository.dart';
import 'crypto_migration_scope_baseline.dart';
import 'crypto_migration_task_dependency.dart';

/// Source-bound, durable ciphertext preparation. No normal business record,
/// cursor, notification or balance is installed by staging.
class CryptoMigrationCanonicalStage {
  CryptoMigrationCanonicalStage(this.context);
  final CryptoBusinessSession context;

  Future<void> stageCaptured({
    required CryptoCaptureKeyDescriptor capture,
    required String sourceInventoryRoot,
    required CryptoCaptureBinding binding,
    required Map<String, dynamic> witness,
    required CryptoMigrationRecordSource source,
  }) => _stage(
    migrationId: capture.migrationId,
    inventoryHash: sourceInventoryRoot,
    source: source,
    captured: (capture: capture, binding: binding, witness: witness),
  );

  Future<void> stageOne({
    required String migrationId,
    required String inventoryHash,
    required CryptoMigrationRecordSource source,
  }) => _stage(
    migrationId: migrationId,
    inventoryHash: inventoryHash,
    source: source,
  );

  Future<void> _stage({
    required String migrationId,
    required String inventoryHash,
    required CryptoMigrationRecordSource source,
    ({
      CryptoCaptureKeyDescriptor capture,
      CryptoCaptureBinding binding,
      Map<String, dynamic> witness,
    })?
    captured,
  }) async {
    if (captured != null && source.type == 'scopeMetadata') {
      source = source.withScopeBaseline(
        await CryptoMigrationScopeBaseline(
          database: context.database,
          partition: context.partition,
          captureId: captured.capture.captureId,
          accountId: context.account.directory.accountId,
        ).load(source.scopeId),
      );
    }
    final action =
        'migrationStage:$migrationId:${source.table}:${source.scopeId}:${source.sourceId}';
    final db = context.database, p = context.partition;
    final queue = captured == null
        ? context.queue
        : CryptoCaptureCoordinator(context.account).queue;
    final existing = await db.rows(
      'SELECT o.signed_body FROM crypto_command_keys k JOIN crypto_outbox o ON o.partition=k.partition AND o.request_id=k.request_id WHERE k.partition=? AND k.action_key=?',
      [p, action],
    );
    late Map<String, dynamic> payload;
    if (existing.isNotEmpty) {
      final signed =
          jsonDecode(existing.single['signed_body'] as String) as Map;
      final command =
          CryptoJson.decode(cryptoBase64(signed['commandBase64'])) as Map;
      payload = Map<String, dynamic>.from(command['payload'] as Map);
      final bindings = payload['sourceBindings'];
      if (command['operation'] != 'crypto2.migration.recordsStage' ||
          payload['migrationId'] != migrationId ||
          payload[captured == null ? 'inventoryHash' : 'sourceInventoryRoot'] !=
              inventoryHash ||
          bindings is! List ||
          bindings.length != 1 ||
          (captured == null
              ? (bindings.single as Map)['sourceRowHash'] != source.rowHash
              : (bindings.single as Map)['bindingId'] !=
                    captured.binding.bindingId)) {
        throw const FormatException('crypto_migration_stage_immutable');
      }
    } else {
      final candidate = await context.access.migrationCandidate(
        scopeId: source.scopeId,
        migrationId: migrationId,
        captureId: captured?.capture.captureId,
      );
      final head = candidate.head;
      final member = head.member(context.account.directory.accountId);
      if (source.domain == 'finance' && member['financeRole'] == 'none') {
        throw const CryptoAuthorityPending(
          'crypto_migration_contributor_pending',
        );
      }
      final key = await candidate.key(source.domain);
      final signing = await context.access.signingKey();
      try {
        var rawPayload = source.rawPayload;
        final objects = <Map<String, dynamic>>[];
        final batch = context.codec.crypto.randomId();
        final operation = await context.reservedRecordId(
          source.scopeId,
          action,
        );
        final address = context.address(
          source.scopeId,
          source.domain,
          source.type,
          source.canonicalId,
        );
        Map<String, dynamic>? choiceProof;
        Map<String, dynamic>? choiceReference;
        if (captured != null && CryptoMigrationCapturedChoices.needed(source)) {
          final choice = await CryptoMigrationCapturedChoices.prepareCompanion(
            context,
            migrationId: migrationId,
            captureId: captured.capture.captureId,
            bindingId: captured.binding.bindingId,
            batchId: batch,
            operationId: operation,
            migrationTag: {
              'version': 3,
              'migrationId': migrationId,
              'captureId': captured.capture.captureId,
              'bindingId': captured.binding.bindingId,
              'sourceInventoryRoot': inventoryHash,
            },
            head: head,
            financeKey: key.key,
            signingKey: signing.key,
          );
          choiceProof = choice.proof;
          final id = await context.reservedRecordId(
            source.scopeId,
            'financeAccountChoices',
          );
          choiceReference = {
            'scopeId': source.scopeId,
            'domain': 'finance',
            'id': context
                .address(source.scopeId, 'finance', 'financeAccountChoice', id)
                .wireId,
            'revision': 1,
            'recordProofHash': choice.hash,
          };
          rawPayload = CryptoMigrationCapturedChoices.decorate(
            source.rawPayload!,
            manifestId: id,
            proofHash: choice.hash,
            headHash: head.headHash,
            selectionHash: choice.raw['selectionHash'],
          );
        }
        if (captured != null &&
            source.type == 'financeEntry' &&
            !source.deleted &&
            source.rawPayload?['taskId'] is String) {
          await prepareCapturedTaskDependency(
            context: context,
            migrationId: migrationId,
            captureId: captured.capture.captureId,
            scopeId: source.scopeId,
            taskId: source.rawPayload!['taskId'],
          );
        }
        final refs = context.referencesFor(
          source.scopeId,
          source.type,
          rawPayload,
        );
        final stagedVersions = <Map<String, dynamic>>[];
        for (final ref in refs) {
          final rows = await db.rows(
            'SELECT domain,record_proof_hash FROM crypto_migration_staged_records WHERE partition=? AND migration_id=? AND scope_id=? AND record_id=?',
            [p, migrationId, ref['scopeId'], ref['id']],
          );
          if (rows.length == 1) {
            stagedVersions.add({
              ...ref,
              'domain': rows.single['domain'],
              'revision': 1,
              'recordProofHash': rows.single['record_proof_hash'],
            });
          }
        }
        if (choiceReference != null) {
          stagedVersions.removeWhere((r) => r['id'] == choiceReference!['id']);
          stagedVersions.add(choiceReference);
        }
        final metadata = await context.businessMetadata(
          scopeId: source.scopeId,
          domain: source.domain,
          type: source.type,
          canonicalId: source.canonicalId,
          expectedRevision: 0,
          rawPayload: rawPayload,
          uniqueRefs: source.domain == 'finance'
              ? await CryptoBusinessFinance(context).uniqueRefs(
                  source.scopeId,
                  source.type,
                  source.rawPayload,
                  migrationCandidate: candidate,
                )
              : <String>[],
          stagedReferenceVersions: stagedVersions,
        );
        // Encryption time is not the historical business modification time or
        // authorship. Exact legacy updated_at/updated_by remain in the captured
        // typed source, bound by the migration provenance, never replaced by now.
        metadata.remove('auditState');
        CryptoConsentGeneration.mintCanonical(
          metadata,
          context.codec.crypto.randomId,
        );
        if (captured != null) {
          metadata['migrationOrigin'] = {
            'version': 3,
            'migrationId': migrationId,
            'captureId': captured.capture.captureId,
            'bindingId': captured.binding.bindingId,
            'sourceInventoryRoot': inventoryHash,
          };
        }
        Map<String, dynamic>? sourceWitness;
        if (captured != null && source.type != 'scopeMetadata') {
          final sourceContext = CryptoCaptureSourceContext.fromJson(
            Map<String, dynamic>.from(captured.witness['context'] as Map),
          );
          if (sourceContext.sourceTable != source.table ||
              CryptoBusinessJson.canonical(captured.witness['typedRow']) !=
                  CryptoBusinessJson.canonical(source.typedRow)) {
            throw const FormatException('crypto_migration_witness_source');
          }
          final witnessContext = CryptoMigrationWitnessContext({
            'version': 3,
            'purpose': 'migrationWitness',
            'serverId': context.account.directory.session.profile.serverId,
            'accountId': context.account.directory.accountId,
            'captureId': captured.capture.captureId,
            'migrationId': migrationId,
            'bindingId': captured.binding.bindingId,
            'sourceInventoryRoot': inventoryHash,
            'sourceCommitment': captured.binding.sourceCommitment,
            'scopeId': source.scopeId,
            'domain': source.domain,
            'epoch': head.epoch,
            'accessRevision': head.accessRevision,
            'membershipHeadHash': head.headHash,
            'type': source.type,
            'sourceKind': address.sourceKind,
            'canonicalId': address.canonicalId,
            'wireId': address.wireId,
          });
          final producer = CryptoMigrationWitness(
            database: db,
            partition: p,
            crypto: context.codec.crypto,
          );
          sourceWitness = await producer.stage(
            context: witnessContext,
            witness: captured.witness,
            domainKey: key.key,
          );
          final transport = CryptoMigrationWitnessTransport(
            queue: queue,
            read: context.account.directory.call,
          );
          await transport.upload(
            producer: producer,
            context: witnessContext,
            descriptor: sourceWitness,
          );
          if (source.type == 'attachment' && !source.deleted) {
            final base = <String, dynamic>{
              'migrationId': migrationId,
              'captureId': captured.capture.captureId,
              'bindingId': captured.binding.bindingId,
            };
            final file = await context.account.directory.call(
              'crypto2.migration.capture.file',
              base,
            );
            final size = rawPayload!['size'] as int;
            if (file['captureVersion'] != 3 ||
                file['bindingId'] != captured.binding.bindingId ||
                file['kind'] != 'attachment' ||
                file['state'] != 'present' ||
                file['size'] != size ||
                file['stamp'] is! String) {
              throw const FormatException('crypto_migration_file_source');
            }
            Stream<List<int>> plaintext() async* {
              var offset = 0;
              while (offset < size) {
                final page = await context.account.directory
                    .call('crypto2.migration.capture.fileChunk', {
                      ...base,
                      'offset': offset,
                      'limit': 196608,
                      'stamp': file['stamp'],
                    });
                final bytes = cryptoBase64(page['dataBase64'], max: 196608);
                if (page['captureVersion'] != 3 ||
                    page['bindingId'] != captured.binding.bindingId ||
                    page['kind'] != 'attachment' ||
                    page['size'] != size ||
                    page['stamp'] != file['stamp'] ||
                    page['offset'] != offset ||
                    page['nextOffset'] != offset + bytes.length ||
                    bytes.length != (size - offset).clamp(0, 196608)) {
                  throw const FormatException('crypto_migration_file_source');
                }
                offset += bytes.length;
                yield bytes;
              }
            }

            final files = CryptoMigrationFileObject(
              database: db,
              partition: p,
              crypto: context.codec.crypto,
            );
            final object = await files.stage(
              context: witnessContext,
              plainSize: size,
              plainSha256: rawPayload['sha256'],
              plaintext: plaintext(),
              domainKey: key.key,
            );
            await files.upload(
              transport: transport,
              context: witnessContext,
              object: object,
            );
            objects.add(object);
            rawPayload = {...rawPayload, 'cryptoBlob': object['blob']};
          }
          if (source.type == 'idea' && rawPayload != null) {
            objects.addAll(
              await CryptoMigrationIdeaFiles(context).objectsForBoard(
                captureId: captured.capture.captureId,
                scopeId: source.scopeId,
                boardId: source.canonicalId,
                raw: rawPayload,
              ),
            );
            rawPayload = decorateCryptoMigrationIdea(
              rawPayload,
              objects,
              witnessContext,
            );
          }
          metadata['blobIds'] = <String>{
            ...(metadata['blobIds'] as List).cast<String>(),
            ...(sourceWitness['segments'] as List).map(
              (s) => s['id'] as String,
            ),
            ...objects.map((o) => o['blob']['id'] as String),
          }.toList()..sort();
        }
        var bytes = rawPayload == null
            ? null
            : CryptoBusinessJson.encode({
                'format': 2,
                'identity': address.identity,
                'payload': rawPayload,
                if (captured == null && source.table != 'familyhub_scopes')
                  'migrationSource': {
                    'version': 2,
                    'sourceTable': source.table,
                    'typedRow': source.typedRow,
                  },
              });
        late Map<String, dynamic> proof;
        try {
          if (bytes != null && bytes.length > 98304) {
            if (captured == null || sourceWitness == null) {
              throw const CryptoAuthorityPending(
                'crypto_migration_blob_stage_pending',
              );
            }
            bytes.fillRange(0, bytes.length, 0);
            bytes = CryptoBusinessJson.encode({
              'format': 2,
              'identity': address.identity,
              'payload': {
                'migrationPayload': 3,
                'bindingId': captured.binding.bindingId,
                if (rawPayload?['accountChoiceWitness'] != null)
                  'accountChoiceWitness': rawPayload!['accountChoiceWitness'],
              },
            });
          }
          proof = context.codec.sealRecord(
            serverId: context.account.directory.session.profile.serverId,
            accountId: context.account.directory.accountId,
            deviceId: context.account.deviceId,
            batchId: batch,
            scopeId: source.scopeId,
            id: address.wireId,
            type: source.type,
            expectedRevision: 0,
            epoch: head.epoch,
            accessRevision: head.accessRevision,
            membershipHeadHash: head.headHash,
            domain: source.domain,
            contentContract: source.domain == 'finance' ? 3 : 6,
            operationId: operation,
            previousRecordHash: '0' * 64,
            deleted: source.deleted,
            plaintext: bytes,
            metadata: metadata,
            contentKey: key.key,
            signingKey: signing.key,
          );
        } finally {
          bytes?.fillRange(0, bytes.length, 0);
        }
        final proofs = <Map<String, dynamic>>[proof], companions = <String>[];
        if (choiceProof != null) {
          proofs.add(choiceProof);
          companions.add(await context.codec.digest(choiceProof));
        }
        if (source.type == 'task') {
          final id = await context.reservedRecordId(
            source.scopeId,
            'taskDerivation:${source.canonicalId}',
          );
          final identity = context.address(
            source.scopeId,
            'content',
            'taskDerivationIntent',
            id,
          );
          final raw = source.rawPayload;
          final intent = {
            'version': 1,
            'taskId': source.canonicalId,
            'targetOperationId': operation,
            'targetCryptoRevision': 1,
            'deadlineEpoch': raw?['dueAt'] == null
                ? null
                : DateTime.parse(
                        raw!['dueAt'],
                      ).toUtc().millisecondsSinceEpoch ~/
                      1000,
            'completed': raw?['isCompleted'] ?? false,
            'deleted': source.deleted,
          };
          final bytes = CryptoBusinessJson.encode({
            'format': 2,
            'identity': identity.identity,
            'payload': intent,
            if (captured == null)
              'migrationSource': {
                'version': 2,
                'sourceTable': source.table,
                'typedRow': source.typedRow,
              },
          });
          try {
            final companion = context.codec.sealRecord(
              serverId: context.account.directory.session.profile.serverId,
              accountId: context.account.directory.accountId,
              deviceId: context.account.deviceId,
              batchId: batch,
              scopeId: source.scopeId,
              id: identity.wireId,
              type: 'taskDerivationIntent',
              expectedRevision: 0,
              epoch: head.epoch,
              accessRevision: head.accessRevision,
              membershipHeadHash: head.headHash,
              domain: 'content',
              contentContract: 6,
              operationId: operation,
              previousRecordHash: '0' * 64,
              deleted: false,
              plaintext: bytes,
              metadata: {
                if (captured != null)
                  'migrationOrigin': metadata['migrationOrigin'],
                'identity': identity.identity,
                'references': <Object>[],
                'referenceVersions': <Object>[],
                'uniqueRefs': <String>[],
                'blobIds':
                    sourceWitness == null
                          ? <String>[]
                          : (sourceWitness['segments'] as List)
                                .map((s) => s['id'] as String)
                                .toList()
                      ..sort(),
              },
              contentKey: key.key,
              signingKey: signing.key,
            );
            proofs.add(companion);
            companions.add(await context.codec.digest(companion));
          } finally {
            bytes.fillRange(0, bytes.length, 0);
          }
        }
        if (captured != null &&
            source.type == 'financeEntry' &&
            !source.deleted &&
            source.rawPayload?['taskId'] != null) {
          final companion = await sealCapturedTaskResolution(
            context: context,
            migrationId: migrationId,
            scopeId: source.scopeId,
            entryId: source.canonicalId,
            expense: source.rawPayload!,
            expenseProofHash: await context.codec.digest(proof),
            batchId: batch,
            operationId: operation,
            head: head,
            financeKey: key.key,
            signingKey: signing.key,
            witnessBlobIds: (metadata['blobIds'] as List).cast<String>(),
            migrationTag: Map<String, dynamic>.from(
              metadata['migrationOrigin'] as Map,
            ),
          );
          if (companion != null) {
            proofs.add(companion);
            companions.add(await context.codec.digest(companion));
          }
        }
        companions.sort();
        final commitment = await context.codec.commitBatch(
          serverId: context.account.directory.session.profile.serverId,
          accountId: context.account.directory.accountId,
          deviceId: context.account.deviceId,
          batchId: batch,
          records: proofs,
          signingKey: signing.key,
          projectionToken: (r) async =>
              context.codec.projectionGroupToken(r, key.key),
        );
        payload = {
          'migrationId': migrationId,
          if (captured == null) 'inventoryHash': inventoryHash,
          if (captured != null) ...{
            'captureVersion': 3,
            'captureId': captured.capture.captureId,
            'sourceInventoryRoot': inventoryHash,
          },
          'sourceBindings': [
            if (captured == null)
              source.binding(
                address,
                await context.codec.digest(proof),
                companionProofHashes: companions,
              )
            else
              {
                'bindingId': captured.binding.bindingId,
                'scopeId': source.scopeId,
                'sourceKind': address.sourceKind,
                'canonicalId': address.canonicalId,
                'wireId': address.wireId,
                'domain': source.domain,
                'type': source.type,
                'legacyRevision': source.legacyRevision,
                'recordProofHash': await context.codec.digest(proof),
                'companionProofHashes': companions,
                'witness': sourceWitness,
                'objects': objects,
              },
          ],
          'batch': {
            'batchId': batch,
            'records': proofs,
            'commitment': commitment,
          },
        };
      } finally {
        key.release();
        signing.release();
      }
    }
    final request = await queue.enqueueCommand(
      actionKey: action,
      operation: 'crypto2.migration.recordsStage',
      payload: payload,
    );
    await queue.resumeUnresolved(requestIds: {request});
    final result = await queue.commandResult(request);
    if (result['migrationId'] != migrationId ||
        result['active'] != false ||
        result['staged'] != 1) {
      throw const FormatException('crypto_migration_stage_ack');
    }
    final batch = payload['batch'] as Map;
    final binding = (payload['sourceBindings'] as List).single as Map;
    await db.transaction(() async {
      for (final proof in (batch['records'] as List).cast<Map>()) {
        final body =
            CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map;
        final hash = await context.codec.digest(
          Map<String, dynamic>.from(proof),
        );
        final key = [
          p,
          migrationId,
          body['scopeId'],
          body['domain'],
          body['id'],
        ];
        final old = await db.rows(
          'SELECT record_proof_hash FROM crypto_migration_staged_records WHERE partition=? AND migration_id=? AND scope_id=? AND domain=? AND record_id=?',
          key,
        );
        if (old.isNotEmpty && old.single['record_proof_hash'] != hash) {
          throw const FormatException('crypto_migration_stage_immutable');
        }
        await db.execute(
          'INSERT OR IGNORE INTO crypto_migration_staged_records VALUES(?,?,?,?,?,?,?,?,?)',
          [
            ...key,
            hash,
            jsonEncode(proof),
            jsonEncode(batch['commitment']),
            jsonEncode(binding),
          ],
        );
      }
    });
  }
}
