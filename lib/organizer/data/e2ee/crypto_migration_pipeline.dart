import 'crypto_migration_choice_workflow.dart';
import 'crypto_migration_captured_choices.dart';
import 'dart:convert';
import 'dart:typed_data';

import '../collaboration_transport.dart';

import 'account_crypto_v2_workflow.dart';
import 'crypto_business_documents.dart';
import 'crypto_business_router.dart';
import 'crypto_archive_cold_database.dart';
import 'crypto_capture_archive.dart';
import 'crypto_capture_coordinator.dart';
import 'crypto_capture_keys.dart';
import 'crypto_capture_legacy_index.dart';
import 'crypto_capture_v3.dart';
import 'crypto_record_address.dart';
import 'crypto_migration_activation_producer.dart';
import 'crypto_migration_audit.dart';
import 'crypto_migration_idea_files.dart';
import 'crypto_migration_topology.dart';
import 'crypto_migration_structure_workflow.dart';
import 'crypto_migration_business_parity_v3.dart';
import 'crypto_migration_canonical_stage.dart';
import 'crypto_migration_cold_business.dart';
import 'crypto_migration_domain_contributions.dart';
import 'crypto_migration_invitation_producer.dart';
import 'crypto_migration_local_artifact.dart';
import 'crypto_migration_notification_producer.dart';
import 'crypto_migration_record_source.dart';
import 'crypto_migration_pending_work.dart';
import 'crypto_sync_repository.dart';
import 'scope_crypto_manager.dart';
import 'session_crypto_access.dart';

/// The same durable producers serve the public wizard and recovery retries.
/// Every restart redoes the independent FILE comparison; a saved progress label
/// never substitutes for a source, business, certificate or publication proof.
class CryptoMigrationPipeline {
  CryptoMigrationPipeline(
    this.account, {
    this.progress,
    this.coldDatabase,
    this.reviewStructure,
  });
  final Future<CryptoArchiveColdDatabase> Function()? coldDatabase;
  final AccountCryptoV2Workflow account;
  final Future<void> Function(String phase)? progress;
  final CryptoMigrationStructureReviewer? reviewStructure;

  Future<void> run({
    required CryptoCaptureKeyDescriptor capture,
    required Uint8List recoveryFile,
    required bool acceptedRemoteDateDisclosure,
  }) async {
    final coordinator = CryptoCaptureCoordinator(account);
    final status = await coordinator.verifiedStatus(capture);
    final root = status['inventoryRoot'] as String;
    final access = SessionCryptoAccess(account: account);
    final runtime = CryptoBusinessSession(
      account,
      access,
      account.store.database,
    );
    runtime.references = CryptoBusinessDocuments(runtime).references;
    await progress?.call('canonical');
    await _initialize(capture, access);
    await _stage(capture, root, runtime, metadataOnly: true);
    await progress?.call('archive');
    final archive = CryptoCaptureArchive(account, coldDatabase: coldDatabase);
    final manifest = await archive.stageAndUpload(capture);
    final cold = await archive.verifyFromFile(
      capture: capture,
      manifest: manifest,
      externalFile: recoveryFile,
    );
    final business = CryptoMigrationColdBusiness(
      account,
      coldDatabase: coldDatabase,
    );
    await progress?.call('structureReview');
    await CryptoMigrationStructureWorkflow(
      runtime,
      business,
      review: reviewStructure,
    ).run(
      capture: capture,
      manifest: manifest,
      archive: cold,
      recoveryFile: recoveryFile,
    );
    // A separate finance materializer may need these exact signed task proofs
    // while the owner waits for its sanitized child-account choice handoff.
    await _stage(capture, root, runtime, contentOnly: true);
    await CryptoMigrationChoiceWorkflow(
      runtime,
      review: reviewStructure,
      coldDatabase: coldDatabase,
    ).run(
      capture: capture,
      manifest: manifest,
      archive: cold,
      recoveryFile: recoveryFile,
    );
    await _stage(capture, root, runtime);
    for (final domain in ['content', 'finance']) {
      await CryptoCaptureLegacyIndex(
        account,
      ).certify(coldArchive: cold, domain: domain);
    }
    await CryptoMigrationPendingWork(runtime).drain(capture);
    final local = await CryptoMigrationLocalArtifact(
      account,
    ).stageAndUpload(capture: capture, sourceInventoryRoot: root);
    final notifications = CryptoMigrationNotificationProducer(runtime);
    await notifications.stageAll(
      capture,
      acceptedRemoteDateDisclosure: acceptedRemoteDateDisclosure,
    );
    await progress?.call('coldBusiness');
    final verified = await business.verifyProduction(
      capture: capture,
      manifest: manifest,
      recoveryFile: recoveryFile,
      localArtifact: local,
    );
    final accepted = await business.publishVerification(verified, local);
    await progress?.call('certificates');
    await notifications.certifyAndAnchor(verified);
    await CryptoMigrationInvitations(runtime).certifyAndAnchor(
      capture: capture,
      sourceInventoryRoot: root,
      archiveManifestHash: verified.header['archiveManifestHash'],
      coldParityProofHash: accepted['coldParityProofHash'],
    );
    final domains = CryptoMigrationDomainContributions(runtime);
    // Managers prepare the complete assignments. Other contributors can then
    // resume their own signed portion; missing peer contributions stay pending.
    for (final scope in capture.scopeIds) {
      for (final domain in ['content', 'finance']) {
        await domains.prepare(
          migrationId: capture.migrationId,
          scopeId: scope,
          domain: domain,
        );
      }
    }
    final selected = <String, Set<String>>{
      for (final scope in capture.scopeIds) scope: {'content', 'finance'},
    };
    for (final selection in capture.receiptSelections) {
      selected
          .putIfAbsent(selection['scopeId'], () => <String>{})
          .add(selection['domain']);
    }
    for (final scope in selected.keys.toList()..sort()) {
      for (final domain in selected[scope]!.toList()..sort()) {
        if (!await domains.isAssigned(
          verified: verified,
          scopeId: scope,
          domain: domain,
        )) {
          continue;
        }
        await domains.contribute(
          verified: verified,
          scopeId: scope,
          domain: domain,
        );
      }
    }
    for (final scope in capture.scopeIds) {
      for (final domain in ['content', 'finance']) {
        await domains.certify(
          verified: verified,
          scopeId: scope,
          domain: domain,
        );
      }
    }
    await progress?.call('publication');
    final activations = CryptoMigrationActivationProducer(runtime);
    final refs = <Map<String, dynamic>>[];
    for (final scope in capture.scopeIds) {
      refs.add(await activations.stage(verified: verified, scopeId: scope));
    }
    if (refs.isEmpty) {
      throw const CryptoAuthorityPending('crypto_migration_managers_pending');
    }
    final component = await coordinator.componentCandidate(capture);
    final complete = <Map<String, dynamic>>[];
    String? after;
    while (true) {
      final page = await account.directory
          .call('crypto2.migration.activation.refs', {
            'migrationId': capture.migrationId,
            'limit': 50,
            if (after != null) 'afterScopeToken': after,
          });
      if (page['version'] != 3 ||
          page['candidate'] != true ||
          page['migrationId'] != capture.migrationId ||
          page['componentCommitment'] != component['componentCommitment'] ||
          page['inventoryCommitment'] != component['inventoryCommitment'] ||
          page['scopeActivations'] is! List ||
          page['hasMore'] is! bool ||
          page['scopeActivations'].length > 50) {
        throw const FormatException('crypto_migration_activation_refs');
      }
      for (final raw in page['scopeActivations']) {
        final ref = Map<String, dynamic>.from(raw as Map);
        CryptoMigrationBusinessParityV3.exact(ref, {
          'scopeToken',
          'activationHash',
        });
        if (!CryptoMigrationBusinessParityV3.hash(ref['scopeToken']) ||
            !CryptoMigrationBusinessParityV3.hash(ref['activationHash']) ||
            after != null && after.compareTo(ref['scopeToken']) >= 0 ||
            complete.length >= 1000) {
          throw const FormatException('crypto_migration_activation_refs');
        }
        complete.add(ref);
        after = ref['scopeToken'];
      }
      if (page['hasMore'] == false) break;
      if (page['scopeActivations'].isEmpty ||
          page['nextAfterScopeToken'] != after) {
        throw const FormatException('crypto_migration_activation_refs');
      }
    }
    for (final own in refs) {
      if (!complete.any(
        (r) =>
            r['scopeToken'] == own['scopeToken'] &&
            r['activationHash'] == own['activationHash'],
      )) {
        throw const FormatException('crypto_migration_activation_refs');
      }
    }
    await activations.commit(verified: verified, scopeActivations: complete);
    await progress?.call('committed');
  }

  Future<void> _initialize(
    CryptoCaptureKeyDescriptor capture,
    SessionCryptoAccess access,
  ) async {
    final owned = capture.scopeIds.toSet();
    final needed = <String>{
      ...owned,
      ...capture.receiptSelections.map((selection) => selection['scopeId']!),
    };
    String? after;
    var seen = 0;
    do {
      final page = await account.directory.call('crypto2.scopes.catalog', {
        'limit': 50,
        if (after != null) 'afterId': after,
      });
      if (page['scopes'] is! List ||
          page['scopes'].length > 50 ||
          page['hasMore'] is! bool) {
        throw const FormatException('crypto_catalog_shape');
      }
      for (final raw in page['scopes']) {
        final row = Map<String, dynamic>.from(raw as Map);
        if (!isCryptoCanonicalUuid(row['id']) ||
            ++seen > 100000 ||
            after != null && after.compareTo(row['id']) >= 0) {
          throw const FormatException('crypto_catalog_cursor');
        }
        after = row['id'];
        if (!needed.remove(row['id'])) continue;
        if (!owned.contains(row['id'])) {
          // A receipt-only contributor consumes the existing exact candidate;
          // it never creates a genesis, installs a floor or gains WRITE.
          try {
            final candidate = await access.migrationCandidate(
              scopeId: row['id'],
              migrationId: capture.migrationId,
              captureId: capture.captureId,
            );
            await access.hydrateMigrationCandidateKeys(candidate);
          } on CollaborationApiException catch (error) {
            if (error.code != 'crypto_scope_head_missing') rethrow;
            throw const CryptoAuthorityPending(
              'crypto_migration_dependencies_pending',
            );
          }
          continue;
        }
        // This is preparatory input only. The cold structural module compares
        // the resulting signed genesis against the complete captured source.
        final supersession = await account.store.database.rows(
          'SELECT value FROM local_meta WHERE name=?',
          [
            'migration_generation_successor:${account.store.partition}:${capture.migrationId}',
          ],
        );
        if (supersession.isNotEmpty) {
          await ScopeCryptoManager(access).publishMigrationGenerationDraft(
            generationId: supersession.single['value'] as String,
            migrationId: capture.migrationId,
            captureId: capture.captureId,
            scopeId: row['id'],
          );
          continue;
        }
        await ScopeCryptoManager(access).initializeEmptyScope(
          migrationId: capture.migrationId,
          captureId: capture.captureId,
          scopeId: row['id'],
          accessRevision: row['accessRevision'],
          members: (row['members'] as List).cast<Map<String, dynamic>>(),
        );
      }
      if (page['hasMore'] == false) break;
      final next = page['nextAfterId'];
      if (!isCryptoCanonicalUuid(next) ||
          page['scopes'].isEmpty ||
          next != after) {
        throw const FormatException('crypto_catalog_cursor');
      }
      after = next;
    } while (true);
    if (needed.isNotEmpty) {
      throw const CryptoAuthorityPending('crypto_migration_scope_unavailable');
    }
  }

  Future<void> _stage(
    CryptoCaptureKeyDescriptor capture,
    String root,
    CryptoBusinessSession runtime, {
    bool metadataOnly = false,
    bool contentOnly = false,
  }) async {
    if (metadataOnly) {
      await CryptoMigrationTopology.stageAll(runtime, capture, root);
      await CryptoMigrationIdeaFiles(runtime).stageAll(capture, root);
    }
    // Dependencies precede their users without loading a whole capture. A row
    // (including a large typed value) is held only for its own immutable stage.
    for (final pass
        in metadataOnly
            ? [0]
            : contentOnly
            ? [2]
            : [1, 2, 9, 3, 4, 5, 6, 7, 8]) {
      var after = '';
      while (true) {
        final rows = await account.store.database.rows(
          'SELECT * FROM crypto_capture_sources WHERE partition=? AND capture_id=? AND binding_id>? ORDER BY binding_id LIMIT 1',
          [account.store.partition, capture.captureId, after],
        );
        if (rows.isEmpty) break;
        final row = rows.single;
        after = row['binding_id'] as String;
        final context = CryptoCaptureSourceContext.fromJson(
          Map<String, dynamic>.from(jsonDecode(row['context'] as String)),
        );
        final adapter = CryptoMigrationBusinessParityV3.sourceAdapter(
          context.sourceTable,
        );
        final typed = Map<String, dynamic>.from(
          jsonDecode(row['typed_row'] as String),
        );
        CryptoMigrationRecordSource? source;
        int rank;
        if (adapter == 'canonical') {
          source = await CryptoMigrationRecordSource.decode(
            table: context.sourceTable,
            domain: context.domain,
            row: typed,
            serverId: account.directory.session.profile.serverId,
            reservedId: runtime.reservedRecordId,
          );
          rank = source.type == 'scopeMetadata'
              ? 0
              : [
                  'financeAccount',
                  'personalFinanceAccount',
                ].contains(source.type)
              ? 1
              : source.domain == 'content'
              ? 2
              : source.type == 'paymentEvent'
              ? 4
              : source.type == 'paymentProjection'
              ? 5
              : source.type == 'cashMovement'
              ? 6
              : 3;
        } else if (adapter == 'auditHistory') {
          rank = 7;
        } else if (adapter == 'invitation') {
          rank = context.sourceTable == 'familyhub_invitations' ? 7 : 8;
        } else {
          // Other modules consume their complete frozen selection themselves.
          // Canonical files deliberately fail in the cold module until an
          // actual file object exists; archive retention cannot satisfy them.
          continue;
        }
        if (contentOnly && source?.domain != 'content') continue;
        if (!metadataOnly &&
            source != null &&
            CryptoMigrationCapturedChoices.needed(source)) {
          final handoffs = await runtime.db
              .rows('SELECT value FROM local_meta WHERE name=?', [
                CryptoMigrationCapturedChoices.name(
                  runtime.partition,
                  capture.captureId,
                  source.scopeId,
                ),
              ]);
          if (handoffs.length != 1) {
            throw const CryptoAuthorityPending(
              'crypto_account_choices_capture_review_pending',
            );
          }
          final handoff = jsonDecode(handoffs.single['value'] as String) as Map;
          if (handoff['capture3']['context']['childBinding']['bindingId'] ==
              row['binding_id']) {
            rank = 9;
          }
        }
        if (rank != pass) continue;
        final binding = CryptoCaptureBinding.fromJson(
          Map<String, dynamic>.from(jsonDecode(row['binding'] as String)),
        );
        final key = await CryptoCaptureKeyService(account).open(capture);
        final salt = await CryptoCaptureV3.salt(key.key, context);
        key.release();
        try {
          final witness = <String, dynamic>{
            'version': 3,
            'context': context.toJson(),
            'typedRow': typed,
            'saltBase64': base64Encode(salt),
          };
          if (source != null) {
            await CryptoMigrationCanonicalStage(runtime).stageCaptured(
              capture: capture,
              sourceInventoryRoot: root,
              binding: binding,
              witness: witness,
              source: source,
            );
          } else if (adapter == 'auditHistory') {
            await CryptoMigrationAudit(runtime).stageCaptured(
              capture: capture,
              sourceInventoryRoot: root,
              binding: binding,
              witness: witness,
            );
          } else {
            Map<String, dynamic>? bridge;
            if (pass == 8) {
              final id = utf8.decode(
                base64Decode((typed['invitation_id'] as Map)['valueBase64']),
              );
              final saved = await account.store.database.rows(
                "SELECT payload FROM crypto_export_drafts WHERE partition=? AND json_extract(payload,'\$.captureId')=? AND json_extract(payload,'\$.kind')='invitation' AND json_extract(payload,'\$.invitationId')=?",
                [account.store.partition, capture.captureId, id],
              );
              if (saved.length != 1) {
                throw const CryptoAuthorityPending(
                  'crypto_invitation_bridge_invitation_pending',
                );
              }
              bridge = Map<String, dynamic>.from(
                jsonDecode(saved.single['payload'] as String),
              );
            }
            await CryptoMigrationInvitations(runtime).stageCaptured(
              capture: capture,
              sourceInventoryRoot: root,
              binding: binding,
              witness: witness,
              invitationBridge: bridge,
            );
          }
        } finally {
          salt.fillRange(0, salt.length, 0);
        }
      }
    }
  }
}
