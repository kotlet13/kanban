import 'dart:typed_data';
import 'crypto_migration_superseded_setup.dart';
import 'crypto_finance_topology_creation.dart';
import 'dart:convert';
import 'account_directory_v2.dart'
    show cryptoZeroHash, cryptoSha256, VerifiedAccountDirectory;

import 'crypto_business_router.dart';
import 'crypto_business_settlement.dart';
import 'crypto_migration_review_binding.dart';
import 'crypto_capture_keys.dart';
import 'crypto_inventory_json.dart';
import 'crypto_migration_commitments_v3.dart';
import 'crypto_json.dart';
import 'crypto_sync_repository.dart';

/// Before freezing another component, settle exact existing ordinary requests.
/// This does not import quarantined work or invent a replacement operation.
/// Anything requiring an unfinished upload/review remains actionable and intact.
class CryptoMigrationPendingWork {
  CryptoMigrationPendingWork(this.runtime);
  final CryptoBusinessSession runtime;

  Future<void> drain(CryptoCaptureKeyDescriptor capture) async {
    CryptoBusinessRouter.configurePayloads(runtime);
    var after = 0;
    while (true) {
      final rows = await runtime.db.rows(
        "SELECT o.sequence,o.request_id,o.operation,o.signed_body,k.action_key FROM crypto_outbox o LEFT JOIN crypto_command_keys k ON k.partition=o.partition AND k.request_id=o.request_id WHERE o.partition=? AND o.sequence>? AND o.state IN ('pending','blocked') ORDER BY o.sequence LIMIT 8",
        [runtime.partition, after],
      );
      if (rows.isEmpty) break;
      for (final row in rows) {
        after = row['sequence'] as int;
        final signed = Map<String, dynamic>.from(
          jsonDecode(row['signed_body'] as String),
        );
        final body = Map<String, dynamic>.from(
          CryptoJson.decode(cryptoBase64(signed['commandBase64'])) as Map,
        );
        if (body['accountId'] != runtime.account.directory.accountId ||
            body['serverId'] !=
                runtime.account.directory.session.profile.serverId ||
            body['operation'] != row['operation'] ||
            body['requestId'] != row['request_id']) {
          throw const FormatException('crypto_migration_pending_request');
        }
        if (await _sameCapture(body, capture, row['action_key'] as String?)) {
          continue;
        }
        if (await _abandonedWorkflow(body, row['action_key'] as String?)) {
          continue;
        }
        if (row['operation'] != 'crypto2.records.batch') {
          throw const CryptoAuthorityPending(
            'crypto_migration_pending_crypto_intents',
          );
        }
        await runtime.reconcileOriginalRecordRequest(
          row['request_id'] as String,
        );
      }
    }
    // A lost ACK may already be recorded as applied while one semantic leg is
    // pending. Check the normal complete-group projection/ancestry before an
    // omitted crypto queue can be described as drained.
    String? request;
    while (true) {
      final rows = await runtime.db.rows(
        "SELECT b.request_id,o.operation,o.state FROM crypto_business_requests b LEFT JOIN crypto_outbox o ON o.partition=b.partition AND o.request_id=b.request_id WHERE b.partition=? ${request == null ? '' : 'AND b.request_id>?'} ORDER BY b.request_id LIMIT 8",
        [runtime.partition, if (request != null) request],
      );
      if (rows.isEmpty) break;
      for (final row in rows) {
        request = row['request_id'] as String;
        if (row['state'] == 'rejected') {
          continue; // Definitive failure; never replay/re-sign.
        }
        if (row['operation'] != 'crypto2.records.batch') {
          throw const CryptoAuthorityPending(
            'crypto_migration_pending_crypto_intents',
          );
        }
        if (await CryptoBusinessSettlement.contains(
          database: runtime.db,
          partition: runtime.partition,
          requestId: request,
        )) {
          continue;
        }
        await runtime.reconcileOriginalRecordRequest(request);
      }
    }
    if ((await runtime.db.rows(
      'SELECT 1 FROM crypto_outbox_records r LEFT JOIN crypto_outbox o ON o.partition=r.partition AND o.request_id=r.request_id WHERE r.partition=? AND o.request_id IS NULL LIMIT 1',
      [runtime.partition],
    )).isNotEmpty) {
      throw const CryptoAuthorityPending(
        'crypto_migration_pending_crypto_intents',
      );
    }
    await _reviews(capture);
  }

  Future<bool> _abandonedWorkflow(
    Map<String, dynamic> command,
    String? action,
  ) async {
    // Safe replan retains old transport requests, but an exact acknowledged
    // abort makes their generation inert. They never become ordinary work.
    const prefix = 'migration_aborted_generation:';
    final exact = '$prefix${runtime.partition}:';
    String? after;
    while (true) {
      final rows = await runtime.db.rows(
        'SELECT name,value FROM local_meta WHERE substr(name,1,?)=?${after == null ? '' : ' AND name>?'} ORDER BY name LIMIT 8',
        [exact.length, exact, if (after != null) after],
      );
      if (rows.isEmpty) return false;
      for (final row in rows) {
        after = row['name'] as String;
        final saved = jsonDecode(row['value'] as String) as Map;
        final journal = saved['journal'], run = saved['captureRun'];
        if (journal is! Map ||
            run is! Map ||
            journal['aborted'] != true ||
            journal['abortReceipt'] is! Map ||
            journal['abortReceipt']['state'] != 'aborted' ||
            journal['abortReceipt']['legacyPreserved'] != true ||
            journal['abortReceipt']['migrationId'] != journal['migrationId'] ||
            run['partition'] != runtime.partition ||
            run['migration_id'] != journal['migrationId']) {
          continue;
        }
        final capture = CryptoCaptureKeyDescriptor.fromJson(
          jsonDecode(run['journal'] as String) as Map,
        );
        if (capture.migrationId == journal['migrationId'] &&
            await _sameCapture(command, capture, action)) {
          return true;
        }
      }
    }
  }

  Future<bool> _sameCapture(
    Map<String, dynamic> command,
    CryptoCaptureKeyDescriptor capture,
    String? action,
  ) async {
    // No broad crypto*/migration* exclusion. These exact generation-scoped
    // producers own their receipt-first retry and required private sidecars.
    const operations = {
      'crypto2.migration.capture.prepare',
      'crypto2.migration.capture.bind',
      'crypto2.migration.capture.seal',
      'crypto2.migration.capture.fence',
      'crypto2.migration.recordsStage',
      'crypto2.migration.audit.stage',
      'crypto2.migration.notifications.stage',
      'crypto2.migration.notifications.certify',
      'crypto2.migration.notifications.anchor',
      'crypto2.migration.invitations.stage',
      'crypto2.migration.invitations.certify',
      'crypto2.migration.invitations.anchor',
      'crypto2.migration.verify3',
      'crypto2.migration.structure.source',
      'crypto2.migration.structure.sourceAnchor',
      'crypto2.migration.structure.context',
      'crypto2.migration.structure.contextApprove',
    };
    final operation = command['operation'];
    final p = command['payload'];
    if (p is! Map || action == null) return false;
    if (const {
      'crypto2.migration.archiveBegin',
      'crypto2.migration.archiveChunk',
      'crypto2.migration.archiveComplete',
    }.contains(operation)) {
      return _archiveCommand(command, capture, action);
    }
    if (operation == 'crypto2.migration.legacy.certify' ||
        operation == 'crypto2.migration.legacy.anchor') {
      for (final domain in ['content', 'finance']) {
        final base = 'capture3:legacy:${capture.captureId}:$domain';
        if (action != base && action != '$base:anchor') continue;
        Map h;
        if (operation == 'crypto2.migration.legacy.certify') {
          if (action != base || p['header'] is! Map) return false;
          h = p['header'] as Map;
        } else {
          if (action != '$base:anchor' ||
              p['migrationId'] != capture.migrationId ||
              p['domain'] != domain ||
              p['eventAuthorization'] is! Map) {
            return false;
          }
          final prior = await runtime.db.rows(
            'SELECT o.signed_body FROM crypto_command_keys k JOIN crypto_outbox o ON o.partition=k.partition AND o.request_id=k.request_id WHERE k.partition=? AND k.action_key=?',
            [runtime.partition, base],
          );
          if (prior.length != 1) return false;
          final cert = jsonDecode(prior.single['signed_body'] as String) as Map;
          final body =
              CryptoJson.decode(cryptoBase64(cert['commandBase64'])) as Map;
          if (body['operation'] != 'crypto2.migration.legacy.certify' ||
              (body['payload'] as Map)['header'] is! Map) {
            return false;
          }
          h = (body['payload'] as Map)['header'] as Map;
          final event =
              CryptoJson.decode(
                    cryptoBase64(
                      (p['eventAuthorization'] as Map)['commandBase64'],
                    ),
                  )
                  as Map;
          final ep = event['payload'];
          if (event['operation'] != 'crypto2.account.migrationAttest' ||
              event['accountId'] != command['accountId'] ||
              event['serverId'] != command['serverId'] ||
              ep is! Map ||
              ep['migrationId'] != capture.migrationId ||
              ep['domain'] != domain ||
              ep['attestationHash'] !=
                  await cryptoSha256(CryptoJson.encode(cert))) {
            return false;
          }
        }
        return h['migrationId'] == capture.migrationId &&
            h['captureId'] == capture.captureId &&
            h['domain'] == domain &&
            h['accountId'] == command['accountId'] &&
            h['serverId'] == command['serverId'];
      }
      return false;
    }
    if (operation == 'crypto2.migration.activation.stage') {
      final signed = p['authorization'];
      if (signed is! Map || signed['commandBase64'] is! String) return false;
      final h = CryptoJson.decode(cryptoBase64(signed['commandBase64']));
      return h is Map &&
          h['version'] == 3 &&
          h['migrationId'] == capture.migrationId &&
          h['componentId'] == capture.componentId &&
          capture.scopeIds.contains(h['scopeId']) &&
          h['managerAccountId'] == command['accountId'] &&
          action == 'activation3:${capture.migrationId}:${h['scopeId']}';
    }
    if (operation == 'crypto2.migration.commit3') {
      if (p['migrationId'] != capture.migrationId ||
          action != 'commit3:${capture.migrationId}') {
        return false;
      }
      final roots = await runtime.db.rows(
        "SELECT payload FROM crypto_membership_intents WHERE partition=? AND scope_id=? AND state='migrationActivation' LIMIT 1001",
        [runtime.partition, capture.migrationId],
      );
      if (roots.isEmpty || roots.length > 1000) return false;
      return roots.every((r) {
        final v = r['payload'];
        final h =
            jsonDecode(v is String ? v : utf8.decode((v as List).cast<int>()))
                as Map;
        return h['migrationId'] == capture.migrationId &&
            h['componentId'] == capture.componentId &&
            h['componentCommitment'] == p['componentCommitment'] &&
            h['inventoryCommitment'] == p['inventoryCommitment'];
      });
    }
    const domainOperations = {
      'crypto2.migration.domains.prepare': 'domainPrepare3',
      'crypto2.migration.domains.contribute': 'domainContribution3',
      'crypto2.migration.domains.anchorContribution':
          'domainContributionAnchor3',
      'crypto2.migration.domains.certify': 'domainCertify3',
      'crypto2.migration.domains.anchor': 'domainAnchor3',
    };
    if (domainOperations.containsKey(operation)) {
      final contribution =
          operation == 'crypto2.migration.domains.contribute' ||
          operation == 'crypto2.migration.domains.anchorContribution';
      final prefix =
          '${domainOperations[operation]}:${contribution ? capture.captureId : capture.migrationId}:';
      if (!action.startsWith(prefix)) return false;
      final suffix = action.substring(prefix.length).split(':');
      if (suffix.length != 2 ||
          !['content', 'finance'].contains(suffix[1]) ||
          !(capture.scopeIds.contains(suffix[0]) ||
              capture.receiptSelections.any(
                (s) => s['scopeId'] == suffix[0] && s['domain'] == suffix[1],
              ))) {
        return false;
      }
      final h = p['header'] is Map ? p['header'] as Map : p;
      if (h['migrationId'] != capture.migrationId || h['domain'] != suffix[1]) {
        return false;
      }
      if (h['captureId'] != null && h['captureId'] != capture.captureId) {
        return false;
      }
      if (h['componentId'] != null && h['componentId'] != capture.componentId) {
        return false;
      }
      if (h['scopeId'] != null && h['scopeId'] != suffix[0]) return false;
      if (h['scopeToken'] != null &&
          h['scopeToken'] !=
              await CryptoMigrationCommitmentsV3.scopeToken(
                serverId: runtime.account.directory.session.profile.serverId,
                migrationId: capture.migrationId,
                scopeId: suffix[0],
                domain: suffix[1],
              )) {
        return false;
      }
      return true;
    }
    if (!operations.contains(operation)) return false;
    final payload = command['payload'];
    if (payload is! Map) return false;
    final common = payload['header'] is Map
        ? payload['header'] as Map
        : payload;
    return common['migrationId'] == capture.migrationId &&
        common['captureId'] == capture.captureId;
  }

  Future<bool> _archiveCommand(
    Map<String, dynamic> command,
    CryptoCaptureKeyDescriptor capture,
    String action,
  ) async {
    final p = command['payload'] as Map;
    if (p['migrationId'] != capture.migrationId) return false;
    String artifactId = capture.captureId;
    String prefix = 'capture3:archive:${capture.captureId}:';
    String kind = 'capture3SourceWitness';
    if (!action.startsWith(prefix)) {
      final saved = await runtime.db.rows(
        'SELECT value FROM local_meta WHERE name=?',
        ['migration_local_artifact:${runtime.partition}:${capture.captureId}'],
      );
      if (saved.length != 1) return false;
      final data = jsonDecode(saved.single['value'] as String) as Map;
      final context = data['context'];
      if (context is! Map ||
          context['migrationId'] != capture.migrationId ||
          context['captureId'] != capture.captureId ||
          context['accountId'] != command['accountId'] ||
          context['serverId'] != command['serverId'] ||
          data['artifactId'] is! String) {
        return false;
      }
      artifactId = data['artifactId'];
      prefix = 'localArtifact:$artifactId:';
      kind = 'migrationLocalIntentsV3';
      if (!action.startsWith(prefix)) return false;
    }
    final rows = await runtime.db.rows(
      'SELECT manifest FROM crypto_archive_jobs WHERE partition=? AND migration_id=?',
      [runtime.partition, artifactId],
    );
    if (rows.length != 1 || rows.single['manifest'] is! String) return false;
    final manifest = jsonDecode(rows.single['manifest'] as String) as Map;
    if (manifest['migrationId'] != capture.migrationId ||
        manifest['artifactId'] != artifactId ||
        manifest['artifactKind'] != kind ||
        manifest['segments'] is! List) {
      return false;
    }
    final segments = manifest['segments'] as List;
    if (segments.length > 16) return false;
    final matches = segments
        .where((s) => s is Map && s['id'] == p['id'])
        .toList();
    if (matches.length != 1) return false;
    final segment = matches.single as Map;
    final suffix = action.substring(prefix.length);
    switch (command['operation']) {
      case 'crypto2.migration.archiveBegin':
        if (suffix != '${p['id']}:begin' ||
            p['size'] != segment['size'] ||
            p['sha256'] != segment['sha256']) {
          return false;
        }
        final header = CryptoJson.decode(cryptoBase64(p['manifestBase64']));
        return header is Map &&
            header['version'] == 3 &&
            header['keyId'] == manifest['keyId'] &&
            header['index'] == segment['index'] &&
            header['cipherManifestHash'] == manifest['cipherManifestHash'];
      case 'crypto2.migration.archiveChunk':
        final offset = p['offset'];
        return offset is int &&
            offset >= 0 &&
            offset < segment['size'] &&
            suffix == '${p['id']}:$offset' &&
            cryptoBase64(p['dataBase64']).length + offset <= segment['size'];
      case 'crypto2.migration.archiveComplete':
        return suffix == '${p['id']}:complete';
    }
    return false;
  }

  Future<bool> _supersededSetup(
    CryptoCaptureKeyDescriptor capture,
    String scope,
    Map<String, dynamic> draft,
  ) async {
    final mappings = await runtime.db.rows(
      'SELECT value FROM local_meta WHERE name=?',
      [
        'migration_generation_successor:${runtime.partition}:${capture.migrationId}',
      ],
    );
    if (mappings.length != 1) return false;
    final generation = mappings.single['value'] as String;
    final retained = await runtime.db.rows(
      'SELECT value FROM local_meta WHERE name=?',
      [
        'migration_superseded_generation:${runtime.partition}:$generation:$scope',
      ],
    );
    if (retained.length != 1) return false;
    final saved = jsonDecode(retained.single['value'] as String) as Map;
    final run = saved['captureRun'];
    if (run is! Map || run['partition'] != runtime.partition) return false;
    final oldCapture = CryptoCaptureKeyDescriptor.fromJson(
      jsonDecode(run['journal'] as String) as Map,
    );
    if (oldCapture.migrationId == capture.migrationId ||
        oldCapture.componentId != capture.componentId ||
        !CryptoMigrationSupersededSetup.same(
          oldCapture.scopeIds,
          capture.scopeIds,
        ) ||
        !oldCapture.scopeIds.contains(scope))
      return false;
    final state = await runtime.account.directory.call(
      'crypto2.migration.generation.status',
      {'generationId': generation},
    );
    final context = state['context'];
    if (context is! Map ||
        state['state'] != 'superseded' ||
        context['migrationId'] != oldCapture.migrationId ||
        context['generationId'] != generation)
      return false;
    Future<Map<String, dynamic>?> command(String action) async {
      final rows = await runtime.db.rows(
        'SELECT o.* FROM crypto_command_keys k JOIN crypto_outbox o ON o.partition=k.partition AND o.request_id=k.request_id WHERE k.partition=? AND k.action_key=?',
        [runtime.partition, action],
      );
      return rows.length == 1 && rows.single['state'] == 'applied'
          ? rows.single
          : null;
    }

    final finished = await command('generationFinish:$generation'),
        prepared = await command('capture:${capture.captureId}:prepare');
    if (finished == null || prepared == null) return false;
    final finish = jsonDecode(finished['signed_body'] as String) as Map;
    final prepare = jsonDecode(prepared['signed_body'] as String) as Map;
    final approvals = await runtime.db.rows(
      "SELECT payload FROM crypto_membership_intents WHERE partition=? AND scope_id=? AND intent_id=? AND state='migrationGenerationApproval'",
      [runtime.partition, oldCapture.migrationId, generation],
    );
    if (approvals.length != 1) return false;
    final approval =
        CryptoJson.decode(
              Uint8List.fromList(
                (approvals.single['payload'] as List).cast<int>(),
              ),
            )
            as Map;
    final proposalAction = await cryptoSha256(
      CryptoJson.encode({
        'operation': 'crypto2.scope.headPut',
        'payload': draft['body'],
      }),
    );
    final proposals = await runtime.db.rows(
      "SELECT i.authorization FROM crypto_membership_action_keys k JOIN crypto_membership_intents i ON i.partition=k.partition AND i.scope_id=k.scope_id AND i.intent_id=k.request_id WHERE k.partition=? AND k.scope_id=? AND k.action_key=? AND i.state='confirmed'",
      [runtime.partition, scope, proposalAction],
    );
    if (proposals.length != 1) return false;
    final oldProposal =
        CryptoJson.decode(
              Uint8List.fromList(
                (proposals.single['authorization'] as List).cast<int>(),
              ),
            )
            as Map;
    final own = await runtime.account.directory.requireFresh();
    final approvalHash = await cryptoSha256(CryptoJson.encode(approval));
    Map<String, dynamic>? included;
    await for (final entry in runtime.account.store.verifiedOperationEntries(
      own,
      'crypto2.account.migrationAttest',
    )) {
      final b = CryptoMigrationSupersededSetup.body(
        entry['authorization'] as Map,
      );
      if (b['payload']['attestationHash'] == approvalHash) {
        if (included != null) return false;
        included = entry;
      }
    }
    if (included == null) return false;
    Future<VerifiedAccountDirectory> prefix(String hash) =>
        runtime.access.directoryAt(
          scopeId: scope,
          scopeHeadHash: cryptoZeroHash,
          accountId: own.accountId,
          directoryHeadHash: hash,
          online: true,
        );
    final a = CryptoMigrationSupersededSetup.body(approval),
        o = CryptoMigrationSupersededSetup.body(oldProposal),
        p = CryptoMigrationSupersededSetup.body(prepare);
    final approvalDirectory = await prefix(a['authorDirectoryHeadHash']),
        oldDirectory = await prefix(o['payload']['authorDirectoryHeadHash']),
        prepareDirectory = await prefix(
          p['payload']['authorDirectoryHeadHash'],
        );
    // Receipt lookup only: never enqueue/resend or infer acknowledgement from
    // an imported SQL state/label. The signed decision is independently anchored.
    final receipt = await runtime.account.directory.call(
      'crypto2.receipt.get',
      {
        'requestId': finished['request_id'],
        'requestHash': finished['request_hash'],
      },
    );
    return CryptoMigrationSupersededSetup.verifies(
      crypto: runtime.account.directory.reducer.crypto,
      own: own,
      approvalDirectory: approvalDirectory,
      oldDirectory: oldDirectory,
      prepareDirectory: prepareDirectory,
      capture: capture,
      scopeId: scope,
      draft: draft,
      context: context,
      approval: approval,
      eventEntry: included,
      oldProposal: oldProposal,
      finish: finish,
      receipt: receipt,
      prepare: prepare,
    );
  }

  Future<void> _reviews(CryptoCaptureKeyDescriptor capture) async {
    var cursor = 0;
    const pending = {
      'pending',
      'scopeSetupDraft',
      'scopeSuccessorDraft',
      'scopeRotationDraft',
      'scopeRotationReview',
      'scopeAccessReview',
      'financeContributionDraft',
      'financePolicyWorkflow',
      'scopeTopologyCreation',
    };
    while (true) {
      final rows = await runtime.db.rows(
        'SELECT rowid AS ordinal,* FROM crypto_membership_intents WHERE partition=? AND rowid>? ORDER BY rowid LIMIT 8',
        [runtime.partition, cursor],
      );
      if (rows.isEmpty) break;
      for (final row in rows) {
        cursor = row['ordinal'] as int;
        if (!pending.contains(row['state'])) continue;
        final value = row['payload'];
        final raw = value is String
            ? value
            : utf8.decode((value as List).cast<int>());
        final data = Map<String, dynamic>.from(jsonDecode(raw) as Map);
        final scope = row['scope_id'] as String;
        if (row['state'] == 'scopeTopologyCreation') {
          await CryptoFinanceTopologyCreation.finish(runtime, data);
          continue;
        }
        if (row['state'] == 'scopeSetupDraft' &&
            capture.scopeIds.contains(scope)) {
          if (await _supersededSetup(capture, scope, data)) continue;
          final candidate = await runtime.access.migrationCandidate(
            scopeId: scope,
            migrationId: capture.migrationId,
            captureId: capture.captureId,
          );
          if (data['headHash'] == candidate.head.headHash &&
              CryptoInventoryJson.canonical(data['body']) ==
                  CryptoInventoryJson.canonical(candidate.head.body)) {
            continue;
          }
        }
        if (row['state'] == 'financeContributionDraft' &&
            capture.receiptSelections.any(
              (selection) =>
                  selection['scopeId'] == scope &&
                  selection['domain'] == 'finance',
            )) {
          final candidate = await runtime.access.migrationCandidate(
            scopeId: scope,
            migrationId: capture.migrationId,
            captureId: capture.captureId,
          );
          if (data['headHash'] == candidate.head.headHash &&
              CryptoInventoryJson.canonical(data['body']) ==
                  CryptoInventoryJson.canonical(candidate.head.body)) {
            final proof = candidate.head.body['financeKeyProposalProof'];
            if (proof is! Map ||
                (CryptoJson.decode(cryptoBase64(proof['commandBase64']))
                        as Map)['accountId'] !=
                    runtime.account.directory.accountId) {
              throw const FormatException(
                'crypto_migration_finance_draft_author',
              );
            }
            await runtime.access.codec.verifyFinanceKeyProposal(
              body: candidate.head.body,
              previous: null,
              directoryAtHead: (id, head) => runtime.access.directoryAt(
                scopeId: scope,
                scopeHeadHash: candidate.head.headHash,
                accountId: id,
                directoryHeadHash: head,
              ),
            );
            continue;
          }
        }
        String? expected = data['headHash'] as String?;
        if (expected != null &&
            data['body'] is Map &&
            await runtime.access.codec.headHash(
                  Map<String, dynamic>.from(data['body'] as Map),
                ) !=
                expected) {
          throw const FormatException(
            'crypto_migration_structural_draft_binding',
          );
        }
        final intentId = row['intent_id'] as String;
        final reviewId = CryptoMigrationReviewBinding.reviewId(
          row['state'] as String,
          intentId,
          data,
        );
        if (expected == null && reviewId is String) {
          final published = await runtime.db.rows(
            "SELECT payload FROM crypto_membership_intents WHERE partition=? AND scope_id=? AND intent_id=? AND state='scopeRotationPublished'",
            [runtime.partition, scope, '$reviewId:published'],
          );
          if (published.length == 1) {
            final p = published.single['payload'];
            final publication =
                (jsonDecode(
                      p is String ? p : utf8.decode((p as List).cast<int>()),
                    )
                    as Map);
            if (!CryptoMigrationReviewBinding.matches(
                  state: row['state'] as String,
                  scopeId: scope,
                  intentId: intentId,
                  draft: data,
                  publication: publication,
                ) ||
                publication['body'] is! Map ||
                await runtime.access.codec.headHash(
                      Map<String, dynamic>.from(publication['body'] as Map),
                    ) !=
                    publication['headHash']) {
              throw const FormatException(
                'crypto_migration_structural_draft_binding',
              );
            }
            expected = publication['headHash'] as String?;
          }
        }
        if (expected == null || !await _ancestor(scope, expected)) {
          throw const CryptoAuthorityPending(
            'crypto_migration_structural_review_pending',
          );
        }
      }
    }
  }

  Future<bool> _ancestor(String scope, String expected) async {
    var head = await runtime.access.currentHead(scope, online: true);
    for (var i = 0; i < 128; i++) {
      if (head.headHash == expected) return true;
      final previous = head.body['previousHeadHash'];
      if (previous is! String || previous == cryptoZeroHash) return false;
      head = await runtime.access.headAt(scope, previous, online: true);
    }
    throw const CryptoAuthorityPending(
      'crypto_migration_structural_history_pending',
    );
  }
}
