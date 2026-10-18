import 'crypto_consent_generation.dart';
import 'crypto_scheduling_use.dart';
import 'crypto_finance_topology_creation.dart';
import 'crypto_finance_topology.dart';
import 'crypto_project_relocation_lineage.dart';
import 'crypto_finance_account_choices.dart';
import 'crypto_business_project_relocation.dart';
import 'dart:convert';
import 'dart:typed_data';

import '../collaboration_database.dart';
import '../device_session_store.dart';
import '../../domain/collaboration_models.dart';
import '../../domain/shared_payload_validation.dart';
import 'account_crypto_v2_workflow.dart';
import 'crypto_business_payload.dart';
import 'crypto_business_settlement.dart';
import 'crypto_record_address.dart';
import 'crypto_business_addresses.dart';
import 'crypto_business_documents.dart';
import 'crypto_business_payments.dart';
import 'crypto_business_history.dart';
import 'crypto_business_group_history.dart';
import 'crypto_business_finance.dart';
import 'crypto_task_resolution.dart';
import 'crypto_business_references.dart';
import 'crypto_business_notifications.dart';
import 'crypto_business_lifecycle.dart';
import 'crypto_business_structure.dart';
import 'crypto_business_access_actions.dart';
import 'crypto_business_deletion.dart';
import 'crypto_business_moderation.dart';
import 'crypto_finance_policy_actions.dart';
import 'crypto_finance_audit_evidence.dart';
import 'crypto_lifecycle_evidence.dart';
import 'crypto_scope_observations.dart';
import 'invite_crypto_repository.dart';
import 'crypto_domain_checkpoint.dart';
import 'crypto_domain_checkpoint_publisher.dart';
import 'crypto_domain_router.dart';
import 'crypto_business_json.dart';
import 'crypto_read_retry.dart';
import 'crypto_inventory_json.dart';
import 'crypto_migration_record_source.dart';
import 'account_directory_v2.dart' show cryptoSha256;
import 'crypto_record_proof_codec.dart';
import 'crypto_business_ack_history.dart';
import 'crypto_json.dart';
import 'crypto_sync_repository.dart';
import 'crypto_sync_store.dart';
import 'scope_crypto_manager.dart';
import 'session_crypto_access.dart';

/// Existing UI actions enter this adapter through CollaborationRepository's
/// authenticated request path. Unsupported operations retain their local queue;
/// no original plaintext operation is forwarded to a legacy content endpoint.
class CryptoBusinessRouter
    implements CryptoDomainRouter, CryptoProjectionCursorTransition {
  CryptoBusinessRouter({required this.database, required this.accountFor});
  final CollaborationDatabase database;
  final Future<AccountCryptoV2Workflow> Function(DeviceSession) accountFor;

  @override
  Future<CryptoProjectionCursorOrigin?> verifyProjectionCursorOrigin({
    required DeviceSession session,
    required String scopeId,
  }) async {
    final account = await accountFor(session);
    final access = SessionCryptoAccess(account: account);
    return access.withVerifiedOperation(() async {
      try {
        await access.currentHead(scopeId, online: true);
      } on CollaborationException catch (error) {
        if (const {
          'crypto_scope_head_missing',
          'crypto_migration_required',
        }.contains(error.code)) {
          return null;
        }
        rethrow;
      }
      await access.verifiedScopeDescriptor(scopeId);
      final migration = await access.recoveredMigrationGenesis(scopeId);
      return migration == null
          ? CryptoProjectionCursorOrigin.nativeOrigin
          : CryptoProjectionCursorOrigin.legacyMigration;
    });
  }

  /// Shared production semantics for ordinary delivery and pre-fence exact
  /// request reconciliation. This installs no authority or restored rows.
  static ({CryptoBusinessDocuments documents, CryptoBusinessPayments payments})
  configurePayloads(CryptoBusinessSession runtime) {
    final documents = CryptoBusinessDocuments(runtime);
    final payments = CryptoBusinessPayments(runtime);
    final choices = CryptoFinanceAccountChoices(runtime);
    runtime.prepareRecords = (values) async {
      await documents.prepareRecords(values);
      await payments.prepareRecords(values);
    };
    runtime.prepareHistoricalPayload = documents.prepareRecords;
    runtime.validateHistoricalPayload = payments.validateHistoryPayload;
    runtime.expandPayload = documents.expandPayload;
    runtime.validateRaw = (domain, type, raw) =>
        documents.validateRaw(domain, type, raw) ??
        payments.validateRaw(domain, type, raw) ??
        choices.validateRaw(domain, type, raw);
    runtime.projectExtension = (value, raw) async =>
        await documents.projectRecord(value, raw) ??
        await payments.projectRecord(value, raw) ??
        await choices.projectRecord(value, raw);
    runtime.blobIds = documents.blobIds;
    runtime.prepareOutgoing = (scope, type, id, raw, operation) async {
      final prepared = await documents.prepareOutgoing(
        scope,
        type,
        id,
        raw,
        operation,
      );
      return type == 'financeEntry'
          ? choices.prepareFinancialRecord(scope, prepared)
          : prepared;
    };
    runtime.encodePayload = documents.encodePayload;
    runtime.references = (type, raw) => type == CryptoFinanceAccountChoices.type
        ? <Map<String, dynamic>>[]
        : documents.references(type, raw) ?? payments.references(type, raw);
    runtime.supportsFinanceExtension = (type) =>
        payments.supportsType(type) || type == CryptoFinanceAccountChoices.type;
    runtime.validateFinanceExtension =
        (values, {required bool forWrite}) async {
          await payments.validateFinanceGroup(values, forWrite: forWrite);
          await choices.validateFinanceGroup(values, forWrite: forWrite);
        };
    return (documents: documents, payments: payments);
  }

  @override
  Future<Map<String, dynamic>> dispatch({
    required DeviceSession session,
    required String operation,
    required Map<String, Object?> params,
    required Set<String> protectedScopeIds,
  }) async {
    final account = await accountFor(session);
    final access = SessionCryptoAccess(account: account);
    final runtime = CryptoBusinessSession(account, access, database);
    return access.withVerifiedOperation(() async {
      final adapters = configurePayloads(runtime);
      final documents = adapters.documents, payments = adapters.payments;
      final invitations = InviteCryptoRepository(access);
      if (invitations.supports(operation)) {
        return invitations.dispatch(operation, params);
      }
      final notifications = CryptoBusinessNotifications(runtime);
      if (notifications.supports(operation)) {
        return notifications.dispatch(operation, params);
      }
      final lifecycle = CryptoBusinessLifecycle(runtime);
      if (lifecycle.supports(operation)) {
        return lifecycle.dispatch(operation, params);
      }
      final structure = CryptoBusinessStructure(runtime);
      if (structure.supports(operation)) {
        return structure.dispatch(operation, params);
      }
      final accessActions = CryptoBusinessAccessActions(runtime);
      if (accessActions.supports(operation)) {
        return accessActions.dispatch(operation, params);
      }
      final relocation = CryptoBusinessProjectRelocation(runtime);
      if (relocation.supports(operation)) {
        return relocation.dispatch(operation, params);
      }
      if (RegExp(r'^finance[24]?\.accountChoices$').hasMatch(operation)) {
        final scope = params['scopeId'];
        if (!isSharedUuid(scope)) {
          throw const FormatException('crypto_finance_scope');
        }
        return runtime.rateLimitedRead(
          scope as String,
          'finance',
          () => CryptoFinanceAccountChoices(runtime).ensure(scope),
        );
      }
      final deletion = CryptoBusinessDeletion(runtime);
      if (deletion.supports(operation)) {
        return deletion.dispatch(operation, params);
      }
      final moderation = CryptoBusinessModeration(runtime);
      if (moderation.supports(operation)) {
        return moderation.dispatch(operation, params);
      }
      final financePolicy = CryptoFinancePolicyActions(runtime);
      if (financePolicy.supports(operation)) {
        return financePolicy.dispatch(operation, params);
      }
      if (documents.supports(operation)) {
        if (const {
              'attachments.get',
              'attachments.list',
              'ideas.asset.get',
              'tables.get',
              'tables.list',
            }.contains(operation) &&
            isSharedUuid(params['scopeId'])) {
          return runtime.rateLimitedRead(
            params['scopeId'] as String,
            'content',
            () => documents.dispatch(operation, params),
          );
        }
        return documents.dispatch(operation, params);
      }
      if (payments.supports(operation)) {
        return payments.dispatch(operation, params);
      }
      if (RegExp(r'^finance[24]?\.audit$').hasMatch(operation)) {
        final scope = params['scopeId'], record = params['recordId'];
        if (!isSharedUuid(scope) || !isSharedUuid(record)) {
          throw const FormatException('crypto_finance_audit_identity');
        }
        final audit = CryptoFinanceAuditEvidence(runtime);
        try {
          return await runtime.rateLimitedRead(
            scope as String,
            'finance',
            () async => {
              'entries': await audit.history(
                scopeId: scope,
                recordId: record as String,
                beforeRevision: params['beforeRevision'] as int?,
                limit: params['limit'] as int? ?? 50,
              ),
            },
          );
        } finally {
          await audit.close();
        }
      }
      if (operation == 'scopes.list') return runtime.scopes();
      if (operation == 'scopes.create') return runtime.createScope(params);
      if (operation == 'scopes.updateMetadata') {
        return runtime.updateMetadata(params);
      }
      if (operation == 'personal.ensure') return runtime.ensurePersonal(params);
      if (RegExp(r'^finance[24]?\.policy$').hasMatch(operation) &&
          params['scopeId'] is String) {
        return runtime.financePolicy(params['scopeId'] as String);
      }
      if (operation == 'scopes.members' && params['scopeId'] is String) {
        return runtime.members(params['scopeId'] as String);
      }
      final scope = params['scopeId'];
      if (!isSharedUuid(scope)) {
        throw const CryptoAuthorityPending('crypto_operation_requires_scope');
      }
      if (RegExp(r'^sync[3-6]\.pushTaskWithCost$').hasMatch(operation)) {
        return runtime.pushTaskWithCost(
          scope as String,
          params,
          route: operation,
        );
      }
      if (RegExp(r'^sync[2-6]?\.push$').hasMatch(operation)) {
        return runtime.push(scope as String, 'content', params);
      }
      if (RegExp(r'^sync[2-6]?\.pull$').hasMatch(operation)) {
        return runtime.pull(scope as String, 'content', params);
      }
      if (RegExp(r'^finance[24]?\.push$').hasMatch(operation)) {
        return runtime.push(scope as String, 'finance', params);
      }
      if (RegExp(r'^finance[24]?\.pull$').hasMatch(operation)) {
        return runtime.pull(scope as String, 'finance', params);
      }
      throw const CryptoAuthorityPending('crypto_domain_operation_pending');
    });
  }
}

class CryptoBusinessSession {
  CryptoBusinessSession(this.account, this.access, this.db);
  CollaborationDatabase get database => db;
  String get partition => p;
  Future<void> Function(List<CryptoProjectionRecord>)? prepareRecords;

  /// Hydration after exact historical chain authority. It must not populate
  /// current financial manifests, issuer witnesses or balance authority memos.
  Future<void> Function(List<CryptoProjectionRecord>)? prepareHistoricalPayload;
  Future<void> Function(CryptoProjectionRecord, Map<String, dynamic>)?
  validateHistoricalPayload;
  List<String> Function(Map<String, dynamic>)? blobIds;
  Future<Map<String, dynamic>> Function(
    String,
    String,
    String,
    String,
    Map<String, dynamic>,
    String,
  )?
  encodePayload;
  Future<Map<String, dynamic>> Function(
    String,
    String,
    String,
    Map<String, dynamic>,
    String,
  )?
  prepareOutgoing;
  List<Map<String, dynamic>>? Function(String, Map<String, dynamic>)?
  references;
  Future<Map<String, dynamic>> Function(
    CryptoProjectionRecord,
    Map<String, dynamic>,
  )?
  expandPayload;
  Map<String, dynamic>? Function(
    String domain,
    String type,
    Map<String, dynamic> raw,
  )?
  validateRaw;
  Future<Map<String, dynamic>?> Function(
    CryptoProjectionRecord,
    Map<String, dynamic>,
  )?
  projectExtension;
  bool Function(String type)? supportsFinanceExtension;
  Future<void> Function(
    List<CryptoBusinessProjection> batch, {
    required bool forWrite,
  })?
  validateFinanceExtension;
  final AccountCryptoV2Workflow account;
  final SessionCryptoAccess access;
  final CollaborationDatabase db;

  /// Set only by the fresh FILE-only migration verifier. Ordinary sessions
  /// never derive descriptor authority from imported projection/cache rows.
  Future<Map<String, dynamic>> Function(String scopeId)? coldScopeDescriptor;
  final financeAuthorityMembers = <String, Set<String>>{};
  bool _resolvingTaskCosts = false;
  String get p => account.store.partition;
  CryptoBusinessAddresses get addresses => CryptoBusinessAddresses(
    db,
    p,
    account.directory.session.profile.serverId,
  );
  CryptoRecordAddress address(
    String scope,
    String domain,
    String type,
    String canonicalId,
  ) => CryptoRecordAddress.forType(
    serverId: account.directory.session.profile.serverId,
    scopeId: scope,
    domain: domain,
    type: type,
    canonicalId: canonicalId,
  );
  CryptoRecordProofCodec get codec =>
      CryptoRecordProofCodec(account.directory.reducer.crypto);
  CryptoSyncRepository get queue => CryptoSyncRepository(
    crypto: account.directory.reducer.crypto,
    session: account.directory.session,
    transport: account.directory.transport,
    store: CryptoSyncStore(db, p),
    signingKey: access.signingKey,
    authorKey: access.recordAuthority,
    contentKey: access.recordKey,
    readContext: (scope, domain) async {
      final context = await access.readContext(scope, domain);
      final observed = access.observedDomainCheckpointAnchors(
        scope,
        domain,
        context.headHash,
      );
      if (observed.length > 1 &&
          observed.any(
            (a) =>
                CryptoInventoryJson.canonical(a) !=
                CryptoInventoryJson.canonical(observed.first),
          )) {
        throw const CryptoAuthorityPending(
          'crypto_observed_inventory_conflict',
        );
      }
      if (observed.isNotEmpty &&
          !await checkpoints.retainsObservedInventory(
            scope,
            domain,
            context,
            observed.first,
          )) {
        await checkpoints.reconcile(
          scope,
          domain,
          context,
          observedAnchors: observed,
        );
      }
      // Normal ACK pulls do not rescan the full domain. Only an impossible
      // locally observed transport position needs signed inventory reconciliation
      // before the scan; new authoritative floors are always verified in pull.
      final positions = await db.rows(
        '''SELECT s.transport_cursor,
        (SELECT COALESCE(MAX(r.sequence),0) FROM crypto_received r WHERE r.partition=s.partition
          AND r.scope_id=s.scope_id AND r.domain=s.domain) AS known_sequence
        FROM crypto_scope_state s WHERE s.partition=? AND s.scope_id=? AND s.domain=?''',
        [p, scope, domain],
      );
      if (positions.isNotEmpty &&
          (positions.single['transport_cursor'] as int) >
              (positions.single['known_sequence'] as int)) {
        await checkpoints.reconcile(scope, domain, context);
      }
      return context;
    },
    beforeDelivery: access.beforeDelivery,
    project: project,
    resolveHistoricalSiblings: CryptoBusinessGroupHistory(this).resolve,
    prepareProjection: (batch) async {
      for (final record in batch.where(
        (r) => r.record['domain'] == 'finance',
      )) {
        final head = await access.headAt(
          record.record['scopeId'],
          record.record['membershipHeadHash'],
        );
        financeAuthorityMembers[head.headHash] = {
          for (final m in head.members) m['accountId'] as String,
        };
      }
      await CryptoBusinessHistory(this).prepare(batch);
      final historical = batch.where((v) => v.historicalOnly).toList();
      await prepareHistoricalPayload?.call(historical);
      await prepareRecords?.call(batch);
    },
    isCurrent: account.directory.isCurrent,
  );

  Future<bool> hasReusableCheckpoint(
    String scope,
    String domain,
    CryptoReadContext read,
  ) async {
    final snapshots = await db.rows(
      '''SELECT c.snapshot_id,c.record_count FROM crypto_domain_checkpoints c
      JOIN crypto_scope_state s ON s.partition=c.partition AND s.scope_id=c.scope_id AND s.domain=c.domain
      WHERE c.partition=? AND c.scope_id=? AND c.domain=? AND c.head_hash=?
        AND c.epoch=? AND c.access_revision=? AND c.sequence=s.scope_sequence
        AND s.floor=? AND s.access_revision=? AND s.complete=1
        AND s.projection_cursor>=s.transport_cursor''',
      [
        p,
        scope,
        domain,
        read.headHash,
        read.epoch,
        read.accessRevision,
        read.epoch,
        read.accessRevision,
      ],
    );
    if (snapshots.length != 1) return false;
    final snapshot = snapshots.single;
    final changed = await db.rows(
      '''SELECT 1 FROM crypto_business_records b
      WHERE b.partition=? AND b.scope_id=? AND b.domain=? AND NOT EXISTS(
        SELECT 1 FROM crypto_domain_inventory_rows i WHERE i.partition=b.partition AND i.snapshot_id=?
          AND i.record_id=b.id AND i.revision=b.crypto_revision AND i.proof_hash=b.record_proof_hash) LIMIT 1''',
      [p, scope, domain, snapshot['snapshot_id']],
    );
    if (changed.isNotEmpty) return false;
    final restored = await db.rows(
      '''SELECT 1 FROM crypto_restore_record_anchors a
      WHERE a.partition=? AND a.scope_id=? AND a.domain=? AND NOT EXISTS(
        SELECT 1 FROM crypto_domain_inventory_rows i WHERE i.partition=a.partition AND i.snapshot_id=?
          AND i.record_id=a.record_id AND i.revision=a.revision AND i.proof_hash=a.proof_hash) LIMIT 1''',
      [p, scope, domain, snapshot['snapshot_id']],
    );
    if (restored.isNotEmpty) return false;
    final pending = await db.rows(
      '''SELECT 1 FROM crypto_received r WHERE r.partition=? AND r.scope_id=? AND r.domain=?
      AND r.batch_key IS NOT NULL AND (r.verdict NOT IN ('verified','superseded') OR NOT EXISTS(
        SELECT 1 FROM crypto_business_records b WHERE b.partition=r.partition AND b.scope_id=r.scope_id
          AND b.domain=r.domain AND b.id=r.record_id AND b.crypto_revision>=r.revision)) LIMIT 1''',
      [p, scope, domain],
    );
    if (pending.isNotEmpty) return false;
    return (await db.rows(
          'SELECT COUNT(*) AS n FROM crypto_business_records WHERE partition=? AND scope_id=? AND domain=?',
          [p, scope, domain],
        )).single['n'] ==
        snapshot['record_count'];
  }

  CryptoDomainCheckpointReader get checkpoints => CryptoDomainCheckpointReader(
    database: db,
    partition: p,
    codec: codec,
    call: (operation, params) => account.directory.call(operation, params),
    verify: (proof) async =>
        (await access.verifyDomainCheckpoint(proof)).historyBasis,
  );

  Future<List<Map<String, dynamic>>> catalog() async {
    final out = <Map<String, dynamic>>[];
    String? after;
    while (true) {
      final page = await account.directory.call('crypto2.scopes.catalog', {
        if (after != null) 'afterId': after,
        'limit': 50,
      });
      if (page['scopes'] is! List || (page['scopes'] as List).length > 50) {
        throw const FormatException('crypto_scope_catalog');
      }
      String? previous = after;
      for (final item in page['scopes'] as List) {
        if (item is! Map ||
            !isSharedUuid(item['id']) ||
            previous != null &&
                (item['id'] as String).compareTo(previous) <= 0) {
          throw const FormatException('crypto_scope_catalog_cursor');
        }
        previous = item['id'] as String;
      }
      if (out.length + (page['scopes'] as List).length > 1000) {
        throw const CryptoAuthorityPending('crypto_scope_catalog_capacity');
      }
      out.addAll(
        (page['scopes'] as List).map(
          (r) => Map<String, dynamic>.from(r as Map),
        ),
      );
      if (page['hasMore'] != true) return out;
      final next = page['nextAfterId'];
      if (next is! String ||
          next != previous ||
          next == after ||
          (page['scopes'] as List).isEmpty) {
        throw const FormatException('crypto_scope_catalog_cursor');
      }
      after = next;
    }
  }

  Future<Map<String, dynamic>> scopes() async {
    await account.directory.requireFresh();
    final result = <Map<String, dynamic>>[];
    final pending = <String>[];
    for (final scope in await catalog()) {
      final cached = await db.rows(
        'SELECT data FROM scopes WHERE partition=? AND id=?',
        [p, scope['id']],
      );
      final local = cached.isEmpty
          ? <String, dynamic>{}
          : Map<String, dynamic>.from(
              jsonDecode(cached.single['data'] as String) as Map,
            );
      var metadata = await _row(
        scope['id'] as String,
        'content',
        await _reservedId(scope['id'] as String, 'scopeMetadata'),
        type: 'scopeMetadata',
      );
      if (metadata == null) {
        try {
          await access.currentHead(scope['id'] as String, online: true);
        } on CollaborationException catch (error) {
          if (error.code != 'crypto_scope_head_missing') rethrow;
          // Catalog absence of a head is discovery, not authority to synthesize
          // a policy/name or revoke retained local records. P7 handles the
          // explicit legacy migration; an unrelated new origin can proceed.
          pending.add(scope['id'] as String);
          if (local.isNotEmpty) result.add({...local, 'blocked': true});
          continue;
        }
        await pullVerified(scope['id'] as String, 'content');
        metadata = await _row(
          scope['id'] as String,
          'content',
          await _reservedId(scope['id'] as String, 'scopeMetadata'),
          type: 'scopeMetadata',
        );
      }
      final source = metadata == null
          ? local
          : jsonDecode(metadata['raw_payload'] as String) as Map;
      final lifecycle = await CryptoLifecycleEvidence(
        access,
      ).current(scope['id'] as String);
      final descriptor = await _verifiedScopeDescriptor(scope['id'] as String);
      final head = await access.currentHead(scope['id'] as String);
      final member = head.member(account.directory.accountId);
      // Catalog titles are never accepted; only already local or authenticated
      // encrypted scope metadata supplies the visible name/address.
      result.add({
        ...local,
        'id': scope['id'],
        'kind': descriptor['kind'],
        'role': member['role'],
        'accessRevision': head.accessRevision,
        'name': source['name'] ?? 'Jivie',
        'address': source['address'],
        'sequence': local['sequence'] ?? 0,
        'archived':
            lifecycle['ownArchived'] == true ||
            lifecycle['inheritedArchived'] == true,
        'requiredRecordContractVersion': 6,
        'accessPolicyVersion': descriptor['accessPolicyVersion'],
        'metadataRevision': metadata == null ? 0 : _localRevision(metadata),
      });
    }
    return {
      'scopes': result,
      'revocations': <Object>[],
      'revokedScopeIds': <String>[],
      'deletedScopeIds': <String>[],
      'pendingCryptoScopeIds': pending,
    };
  }

  Future<Map<String, dynamic>> financePolicy(String scope) async {
    return CryptoFinancePolicyActions(this).policy(scope);
  }

  Future<Map<String, dynamic>> members(String scope) async {
    final head = await access.currentHead(scope, online: true);
    final descriptor = await access.verifiedScopeDescriptor(scope);
    final organization = descriptor['kind'] == 'organization';
    final leaders = descriptor['leaderAccountIds'];
    if (organization &&
        descriptor['accessPolicyVersion'] != 3 &&
        leaders is! List) {
      throw const CryptoAuthorityPending('crypto_scope_leadership_pending');
    }
    final cached = await db.rows(
      'SELECT data FROM members WHERE partition=? AND scope_id=?',
      [p, scope],
    );
    final labels = <String, Map>{
      for (final row in cached)
        (jsonDecode(row['data'] as String) as Map)['accountId'] as String:
            jsonDecode(row['data'] as String) as Map,
    };
    return {
      'members': [
        for (final member in head.members)
          {
            'accountId': member['accountId'],
            'role': member['role'],
            'active': true,
            'organizationLeader':
                organization &&
                (member['role'] == 'owner' ||
                    (leaders is List && leaders.contains(member['accountId']))),
            'userId': member['accountId'] == account.directory.accountId
                ? account.directory.session.profile.userId
                : labels[member['accountId']]?['userId'] ?? 0,
            'username': member['accountId'] == account.directory.accountId
                ? account.directory.session.profile.username
                : labels[member['accountId']]?['username'] ?? 'Jivie',
            'displayName': member['accountId'] == account.directory.accountId
                ? account.directory.session.profile.displayName
                : labels[member['accountId']]?['displayName'] ?? 'Jivie',
          },
      ],
    };
  }

  Future<Map<String, dynamic>> updateMetadata(
    Map<String, Object?> params,
  ) async {
    final scope = params['scopeId'];
    if (!isSharedUuid(scope) ||
        params['name'] is! String ||
        params['expectedRevision'] is! int ||
        !isSharedUuid(params['requestId'])) {
      throw const FormatException('crypto_scope_metadata');
    }
    validateSharedText(params['name'], 200);
    if (params['address'] != null) {
      validateSharedText(params['address'], 2000, empty: true);
    }
    final head = await access.currentHead(scope as String, online: true);
    if (head.member(account.directory.accountId)['manageKeys'] != true) {
      throw const CryptoAuthorityPending('scope_management_required');
    }
    final id = await _reservedId(scope, 'scopeMetadata');
    final previous = await _row(scope, 'content', id, type: 'scopeMetadata');
    if (previous == null) throw const CryptoProjectionPending();
    final raw = Map<String, dynamic>.from(
      jsonDecode(previous['raw_payload'] as String) as Map,
    );
    final operation = params['requestId'] as String;
    final staged = await db.rows(
      'SELECT request_id FROM crypto_business_requests WHERE partition=? AND operation_id=?',
      [p, operation],
    );
    if (params['expectedRevision'] != _localRevision(previous) &&
        staged.isEmpty) {
      throw const CryptoAuthorityPending(
        'crypto_legacy_receipt_reconciliation_required',
      );
    }
    await _writeRaw(
      scopeId: scope,
      domain: 'content',
      id: id,
      type: 'scopeMetadata',
      operationId: operation,
      expectedRevision: previous['crypto_revision'] as int,
      previousHash: previous['record_proof_hash'] as String,
      raw: {...raw, 'name': params['name'], 'address': params['address']},
      localHash: await cryptoSha256(CryptoBusinessJson.encode(params)),
    );
    final updated = (await scopes())['scopes'] as List;
    return {'scope': updated.cast<Map>().singleWhere((s) => s['id'] == scope)};
  }

  Future<Map<String, dynamic>> createScope(Map<String, Object?> params) async {
    final id = params['id'], kind = params['kind'], name = params['name'];
    if (!isSharedUuid(id) ||
        !['household', 'organization', 'project'].contains(kind) ||
        name is! String) {
      throw const FormatException('crypto_scope_create');
    }
    validateSharedText(name, 300);
    final manager = ScopeCryptoManager(access);
    final parent = params['parentScopeId'] ?? params['organizationId'];
    Map<String, dynamic>? basis;
    if (parent != null) {
      basis = (await catalog()).where((s) => s['id'] == parent).firstOrNull;
    }
    if (parent != null && basis == null) {
      throw const CryptoAuthorityPending('crypto_parent_scope_pending');
    }
    final parentTopologyBatch = parent == null
        ? null
        : await CryptoFinanceTopologyCreation.prepare(
            runtime: this,
            parentScopeId: parent as String,
            childScopeId: id as String,
          );
    final allocated = await manager.createScope(
      id: id as String,
      kind: kind as String,
      parentScopeId: parent as String?,
      expectedParentAccessRevision: basis?['accessRevision'] as int?,
      expectedParentAccessBasis: (basis?['accessBasis'] as List?)
          ?.cast<Map<String, dynamic>>(),
    );
    final scope = Map<String, dynamic>.from(allocated['scope'] as Map);
    await manager.initializeEmptyScope(
      scopeId: id,
      accessRevision: scope['accessRevision'] as int,
      members: (scope['members'] as List).cast<Map<String, dynamic>>(),
      parentTopologyBatch: parentTopologyBatch,
    );
    if (parentTopologyBatch != null) {
      await CryptoFinanceTopologyCreation.finish(this, parentTopologyBatch);
    }
    await _writeRaw(
      scopeId: id,
      domain: 'content',
      id: await _reservedId(id, 'scopeMetadata'),
      type: 'scopeMetadata',
      operationId:
          params['requestId'] as String? ??
          account.directory.reducer.crypto.randomId(),
      expectedRevision: 0,
      raw: {
        'name': name,
        'address': params['address'],
        'archived': false,
        'kind': kind,
        'scopeId': id,
        'namespaceVersion': 1,
        if (const ['household', 'organization'].contains(kind))
          'financeTopology': await CryptoFinanceTopology.create(
            serverId: account.directory.session.profile.serverId,
            scopeId: id,
            childTokens: const [],
          ),
      },
      localHash: await CryptoBusinessJson.hash(params),
    );
    return {
      'scope': (await scopes())['scopes'].firstWhere((s) => s['id'] == id),
    };
  }

  Future<Map<String, dynamic>> ensurePersonal(
    Map<String, Object?> params,
  ) async {
    final actionName = 'crypto_personal_origin:$p';
    late String requestedId;
    await db.transaction(() async {
      final existing = await db.rows(
        'SELECT value FROM local_meta WHERE name=?',
        [actionName],
      );
      if (existing.isNotEmpty) {
        requestedId = existing.single['value'] as String;
      } else {
        final supplied = params['id'];
        if (supplied != null && !isSharedUuid(supplied)) {
          throw const FormatException('crypto_personal_scope_id');
        }
        requestedId =
            supplied as String? ?? account.directory.reducer.crypto.randomId();
        await db.execute('INSERT INTO local_meta(name,value) VALUES(?,?)', [
          actionName,
          requestedId,
        ]);
      }
    });
    final manager = ScopeCryptoManager(access);
    final allocated = await manager.ensurePersonal(requestedId);
    final scope = Map<String, dynamic>.from(allocated['scope'] as Map);
    final id = scope['id'];
    if (!isSharedUuid(id) || scope['kind'] != 'personal') {
      throw const FormatException('crypto_personal_scope_identity');
    }
    await manager.initializeEmptyScope(
      scopeId: id as String,
      accessRevision: scope['accessRevision'] as int,
      members: (scope['members'] as List).cast<Map<String, dynamic>>(),
    );
    final verified = await access.verifiedScopeDescriptor(id);
    final head = await access.currentHead(id);
    if (verified['kind'] != 'personal' ||
        head.members.length != 1 ||
        head.member(account.directory.accountId)['role'] != 'owner') {
      throw const FormatException('crypto_personal_scope_identity');
    }
    return {
      'scope': {
        'id': id,
        'name': 'Jivie',
        'kind': verified['kind'],
        'role': 'owner',
        'accessPolicyVersion': verified['accessPolicyVersion'],
        'accessRevision': head.accessRevision,
        'requiredRecordContractVersion': 6,
        'sequence': 0,
        'archived': false,
      },
    };
  }

  Future<Map<String, dynamic>> managerEnsure(String id) =>
      ScopeCryptoManager(access).ensurePersonal(id);

  Future<String> reservedRecordId(String scope, String namespace) =>
      _reservedId(scope, namespace);

  Future<Map<String, Object?>?> record(
    String scopeId,
    String domain,
    String id, {
    String? type,
  }) => _row(scopeId, domain, id, type: type);
  Future<Map<String, Object?>?> wireRecord(
    String scope,
    String domain,
    String wireId,
  ) => _wireRow(scope, domain, wireId);
  Future<void> pullVerified(
    String scopeId,
    String domain, {
    bool attest = true,
  }) => access.withVerifiedOperation(
    () => _pullVerified(scopeId, domain, attest: attest),
  );

  Future<T> rateLimitedRead<T>(
    String scopeId,
    String domain,
    Future<T> Function() read,
  ) => cryptoReadWithRatePause(
    database: db,
    partition: p,
    scopeId: scopeId,
    domain: domain,
    isCurrent: account.directory.isCurrent,
    invalidateOperation: access.invalidateAuthorityOperation,
    read: read,
  );

  Future<void> _pullVerified(
    String scopeId,
    String domain, {
    required bool attest,
  }) async {
    await rateLimitedRead(scopeId, domain, () async {
      await queue.pull(
        scopeId: scopeId,
        domain: domain,
        accessRevision: (await access.readContext(
          scopeId,
          domain,
        )).accessRevision,
      );
      if (attest) {
        await CryptoDomainCheckpointPublisher(this).publish(scopeId, domain);
        final read = await access.readContext(scopeId, domain);
        if (await hasReusableCheckpoint(scopeId, domain, read)) {
          // Outside the projection/checkpoint SQL transaction: the included own
          // account event anchors only the fully verified observed snapshot.
          await CryptoScopeObservations(account).observe(access, scopeId);
        }
      }
    });
    if (domain == 'finance' && !_resolvingTaskCosts) {
      await access.withVerifiedOperation(
        () => reconcileTaskDerivations(scopeId),
        freshBoundary: true,
      );
    }
  }

  Future<void> reconcileTaskDerivations(String scope) async {
    final head = await access.currentHead(scope);
    if (head.member(account.directory.accountId)['financeRole'] != 'write') {
      return;
    }
    _resolvingTaskCosts = true;
    try {
      await for (final rows in cryptoTaskDerivationPages(db, p, scope)) {
        for (final entry in rows) {
          final raw = Map<String, dynamic>.from(
            jsonDecode(entry['raw_payload'] as String) as Map,
          );
          final canonicalEntryId =
              (jsonDecode(entry['projection'] as String) as Map)['id']
                  as String;
          final taskId = raw['taskId'] as String;
          final task = await _row(scope, 'content', taskId, type: 'task');
          final intent = await _row(
            scope,
            'content',
            await _reservedId(scope, 'taskDerivation:$taskId'),
            type: 'taskDerivationIntent',
          );
          if (task == null || intent == null) continue;
          final target = Map<String, dynamic>.from(
            jsonDecode(intent['raw_payload'] as String) as Map,
          );
          if (target['targetCryptoRevision'] != task['crypto_revision']) {
            continue;
          }
          final resolution = await _row(
            scope,
            'finance',
            await _reservedId(scope, 'taskResolution:$taskId'),
            type: 'taskDerivationResolution',
          );
          if (resolution?['raw_payload'] != null &&
              (jsonDecode(resolution!['raw_payload'] as String)
                      as Map)['intentProofHash'] ==
                  intent['record_proof_hash']) {
            continue;
          }
          final localPending = await db.rows(
            'SELECT 1 FROM finance_outbox WHERE partition=? AND scope_id=? AND record_id=? LIMIT 1',
            [p, scope, canonicalEntryId],
          );
          if (localPending.isNotEmpty) continue;
          final deleted = task['deleted'] == 1;
          if (target['deleted'] != deleted) continue;
          final taskRaw = deleted
              ? null
              : Map<String, dynamic>.from(
                  jsonDecode(task['raw_payload'] as String) as Map,
                );
          final derived = {
            ...raw,
            if (deleted) 'taskId': null,
            'plannedAt': taskRaw?['dueAt'],
            // Deletion has no timestamp payload. Preserve the financial time;
            // the signed auditState records this new contributor's claim.
            'updatedAt': taskRaw?['updatedAt'] ?? raw['updatedAt'],
          };
          final operation = await _reservedId(
            scope,
            'resolve:${intent['record_proof_hash']}:${entry['record_proof_hash']}',
          );
          await _writeRaw(
            scopeId: scope,
            domain: 'finance',
            id: canonicalEntryId,
            type: entry['type'] as String,
            operationId: operation,
            expectedRevision: entry['crypto_revision'] as int,
            previousHash: entry['record_proof_hash'] as String,
            raw: derived,
            localHash: await cryptoSha256(CryptoBusinessJson.encode(derived)),
            derivationTaskId: deleted ? taskId : null,
          );
        }
      }
    } finally {
      _resolvingTaskCosts = false;
    }
  }

  /// Resolve an original queue request without creating a new business
  /// operation, signature or projection. All legs must independently match the
  /// current projection or its authenticated retained ancestry before release.
  Future<void> reconcileOriginalRecordRequest(String requestId) async {
    final rows = await db.rows(
      'SELECT operation,signed_body,state FROM crypto_outbox WHERE partition=? AND request_id=?',
      [p, requestId],
    );
    if (rows.length != 1 ||
        rows.single['operation'] != 'crypto2.records.batch') {
      throw const CryptoAuthorityPending(
        'crypto_migration_pending_crypto_intents',
      );
    }
    final signed = Map<String, dynamic>.from(
      jsonDecode(rows.single['signed_body'] as String),
    );
    final command = Map<String, dynamic>.from(
      CryptoJson.decode(cryptoBase64(signed['commandBase64'])) as Map,
    );
    if (command['operation'] != 'crypto2.records.batch' ||
        command['accountId'] != account.directory.accountId ||
        command['serverId'] != account.directory.session.profile.serverId ||
        command['payload']['records'] is! List) {
      throw const FormatException('crypto_migration_pending_request');
    }
    final proofs = (command['payload']['records'] as List)
        .cast<Map<String, dynamic>>();
    if (proofs.isEmpty || proofs.length > 32) {
      throw const FormatException('crypto_batch_size');
    }
    await queue.resumeUnresolved(requestIds: {requestId});
    final outcome = (await db.rows(
      'SELECT state FROM crypto_outbox WHERE partition=? AND request_id=?',
      [p, requestId],
    )).single;
    if (outcome['state'] != 'applied') {
      throw const CryptoAuthorityPending(
        'crypto_migration_pending_crypto_intents',
      );
    }
    final domains = <String, Map<String, dynamic>>{};
    for (final proof in proofs) {
      final body = Map<String, dynamic>.from(
        CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map,
      );
      codec.validateUntrustedRecord(body);
      domains['${body['scopeId']}/${body['domain']}'] = body;
    }
    for (final body in domains.values) {
      final read = await access.readContext(body['scopeId'], body['domain']);
      await queue.pull(
        scopeId: body['scopeId'],
        domain: body['domain'],
        accessRevision: read.accessRevision,
      );
    }
    final budget = CryptoBusinessAckHistoryBudget();
    for (final proof in proofs) {
      final body = Map<String, dynamic>.from(
        CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map,
      );
      await _requireAppliedProjection(
        record: await wireRecord(body['scopeId'], body['domain'], body['id']),
        stagedProof: proof,
        budget: budget,
      );
    }
    await CryptoBusinessSettlement.record(
      database: db,
      partition: p,
      requestId: requestId,
    );
  }

  Future<Map<String, dynamic>> publishRaw({
    required String scopeId,
    String domain = 'content',
    required String id,
    required String type,
    required String operationId,
    required int expectedRevision,
    required Map<String, dynamic>? rawPayload,
    required String localHash,
    List<Map<String, dynamic>> tableLeases = const [],
  }) => access.withVerifiedOperation(() async {
    final previous = await _row(scopeId, domain, id, type: type);
    await _writeRaw(
      scopeId: scopeId,
      domain: domain,
      id: id,
      type: type,
      operationId: operationId,
      expectedRevision: expectedRevision,
      raw: rawPayload,
      localHash: localHash,
      previousHash: previous?['record_proof_hash'] as String?,
      tableLeases: tableLeases,
    );
    final result = await _row(scopeId, domain, id, type: type);
    if (result == null) {
      throw const CryptoAuthorityPending('crypto_projection_pending');
    }
    return Map<String, dynamic>.from(
      jsonDecode(result['projection'] as String) as Map,
    );
  });

  /// Load this before generating any random group ciphertext. An unknown
  /// outcome resumes these exact bytes, never a newly sealed financial effect.
  Future<Map<String, dynamic>?> stagedGroup(
    String operationId,
    String localHash,
  ) async {
    final rows = await db.rows(
      'SELECT b.request_hash,o.signed_body FROM crypto_business_requests b JOIN crypto_outbox o ON o.partition=b.partition AND o.request_id=b.request_id WHERE b.partition=? AND b.operation_id=?',
      [p, operationId],
    );
    if (rows.isEmpty) return null;
    if (rows.single['request_hash'] != localHash) {
      throw const FormatException('crypto_immutable_business_request');
    }
    final signed = jsonDecode(rows.single['signed_body'] as String) as Map;
    final command =
        CryptoJson.decode(cryptoBase64(signed['commandBase64'])) as Map;
    return Map<String, dynamic>.from(command['payload'] as Map);
  }

  /// Domain adapters seal all dependency-ordered legs first. This method journals
  /// one immutable atomic server batch and releases its original intent only
  /// after every requested leg has the exact authenticated local projection.
  Future<List<Map<String, dynamic>>> publishPreparedGroup({
    required String operationId,
    required String localHash,
    required List<Map<String, dynamic>> recordProofs,
    required Map<String, dynamic> commitment,
    List<Map<String, dynamic>> tableLeases = const [],
    List<Map<String, dynamic>> exportBindings = const [],
  }) async {
    if (recordProofs.isEmpty || recordProofs.length > 32) {
      throw const FormatException('crypto_batch_size');
    }
    final bodies = <Map<String, dynamic>>[];
    for (final proof in recordProofs) {
      final body = CryptoJson.decode(cryptoBase64(proof['commandBase64']));
      if (body is! Map<String, dynamic>) {
        throw const FormatException('crypto_record_authorization');
      }
      codec.validateUntrustedRecord(body);
      if (body['operationId'] != operationId) {
        throw const FormatException('crypto_business_staged_identity');
      }
      bodies.add(body);
    }
    final payload = {
      'batchId': bodies.first['batchId'],
      'records': recordProofs,
      'commitment': commitment,
      if (tableLeases.isNotEmpty) 'tableLeases': tableLeases,
      if (exportBindings.isNotEmpty) 'exportBindings': exportBindings,
    };
    final existing = await stagedGroup(operationId, localHash);
    if (existing != null) {
      if (CryptoBusinessJson.canonical(existing) !=
          CryptoBusinessJson.canonical(payload)) {
        throw const FormatException('crypto_immutable_business_request');
      }
    } else {
      final first = cryptoRecordAddressFromMetadata(bodies.first);
      await queue.enqueueBatch(
        batchId: bodies.first['batchId'],
        recordProofs: recordProofs,
        commitment: commitment,
        tableLeases: tableLeases,
        exportBindings: exportBindings,
        applyLocal: () async {},
        onStaged: (requestId) => db.execute(
          'INSERT INTO crypto_business_requests VALUES(?,?,?,?,?,?,?)',
          [
            p,
            operationId,
            first.scopeId,
            first.domain,
            localHash,
            requestId,
            first.canonicalId,
          ],
        ),
      );
    }
    final retry = (await db.rows(
      'SELECT request_id FROM crypto_business_requests WHERE partition=? AND operation_id=?',
      [p, operationId],
    )).single;
    await queue.resumeUnresolved(requestIds: {retry['request_id'] as String});
    final request = (await db.rows(
      'SELECT o.state FROM crypto_business_requests b JOIN crypto_outbox o ON o.partition=b.partition AND o.request_id=b.request_id WHERE b.partition=? AND b.operation_id=?',
      [p, operationId],
    )).single;
    if (request['state'] != 'applied') {
      throw const CryptoAuthorityPending('crypto_business_delivery_pending');
    }
    final domains = <String, Map<String, dynamic>>{};
    for (final body in bodies) {
      domains['${body['scopeId']}:${body['domain']}'] = body;
    }
    for (final body in domains.values) {
      await pullVerified(body['scopeId'], body['domain'], attest: false);
    }
    final results = <Map<String, dynamic>>[];
    final ackHistoryBudget = CryptoBusinessAckHistoryBudget();
    for (var i = 0; i < bodies.length; i++) {
      final body = bodies[i];
      final row = await wireRecord(body['scopeId'], body['domain'], body['id']);
      await _requireAppliedProjection(
        record: row,
        stagedProof: recordProofs[i],
        budget: ackHistoryBudget,
      );
      results.add(
        Map<String, dynamic>.from(
          jsonDecode(row!['projection'] as String) as Map,
        ),
      );
    }
    await CryptoBusinessSettlement.record(
      database: db,
      partition: p,
      requestId: retry['request_id'] as String,
    );
    return results;
  }

  List<Map<String, dynamic>> referencesFor(
    String scope,
    String type,
    Map<String, dynamic>? raw,
  ) => _references(scope, type, raw);
  Future<Map<String, dynamic>> notificationStateFor(
    String scope,
    String domain,
    String id,
    String type,
    int expectedRevision,
    Map<String, dynamic>? raw,
  ) => _notificationState(scope, domain, id, type, expectedRevision, raw);
  Future<Map<String, dynamic>> reminderStateFor(
    String scope,
    String domain,
    String id,
    String type,
    Map<String, dynamic>? raw,
  ) => _reminderState(scope, domain, id, type, raw);

  Future<Map<String, dynamic>> businessMetadata({
    required String scopeId,
    required String domain,
    required String type,
    required String canonicalId,
    required int expectedRevision,
    required Map<String, dynamic>? rawPayload,
    List<String>? uniqueRefs,
    List<Map<String, dynamic>> stagedReferenceVersions = const [],
  }) async {
    final refs = _references(scopeId, type, rawPayload);
    final versions = <Map<String, dynamic>>[];
    for (final ref in refs) {
      final staged = stagedReferenceVersions
          .where((v) => v['scopeId'] == ref['scopeId'] && v['id'] == ref['id'])
          .toList();
      if (staged.length > 1) {
        throw const FormatException('crypto_reference_version_binding');
      }
      if (staged.isNotEmpty) {
        versions.add(Map<String, dynamic>.from(staged.single));
      } else {
        versions.addAll(await referenceVersions([ref]));
      }
    }
    versions.sort(
      (a, b) => '${a['scopeId']}/${a['domain']}/${a['id']}'.compareTo(
        '${b['scopeId']}/${b['domain']}/${b['id']}',
      ),
    );
    return {
      'identity': address(scopeId, domain, type, canonicalId).identity,
      'references': refs,
      'referenceVersions': versions,
      'uniqueRefs':
          uniqueRefs ??
          (domain == 'finance'
              ? await CryptoBusinessFinance(
                  this,
                ).uniqueRefs(scopeId, type, rawPayload)
              : <String>[]),
      'blobIds': rawPayload == null
          ? <String>[]
          : (blobIds?.call(rawPayload) ?? <String>[]),
      if (domain == 'finance')
        'auditState': {
          'version': 1,
          'changedAt': DateTime.now().toUtc().toIso8601String(),
        },
      if (_notifiable(type))
        'notificationState': await _notificationState(
          scopeId,
          domain,
          canonicalId,
          type,
          expectedRevision,
          rawPayload,
        ),
      ...await _scheduleMetadata(
        scopeId,
        domain,
        canonicalId,
        type,
        rawPayload,
        refs,
      ),
    };
  }

  Future<Map<String, Object?>?> _row(
    String scope,
    String domain,
    String canonicalId, {
    String? type,
  }) async {
    final wire = await addresses.existingWireId(
      scope,
      domain,
      canonicalId,
      type: type,
    );
    return wire == null ? null : _wireRow(scope, domain, wire);
  }

  Future<Map<String, Object?>?> _wireRow(
    String scope,
    String domain,
    String wireId,
  ) async => (await db.rows(
    'SELECT * FROM crypto_business_records WHERE partition=? AND scope_id=? AND domain=? AND id=?',
    [p, scope, domain, wireId],
  )).firstOrNull;

  Future<Map<String, dynamic>> push(
    String scope,
    String domain,
    Map<String, Object?> params,
  ) async {
    final raw = params['operation'];
    if (raw is! Map) throw const FormatException('crypto_business_operation');
    final op = Map<String, dynamic>.from(raw),
        id = op['recordId'] ?? op['id'],
        operationId = op['opId'];
    if ((op['id'] != null &&
            op['recordId'] != null &&
            op['id'] != op['recordId']) ||
        !isSharedUuid(id) ||
        !isSharedUuid(operationId) ||
        op['expectedRevision'] is! int ||
        op['deleted'] is! bool ||
        op['type'] is! String) {
      throw const FormatException('crypto_business_operation');
    }
    final previous = await _row(
      scope,
      domain,
      id as String,
      type: op['type'] as String,
    );
    final expected = previous == null ? 0 : _localRevision(previous);
    final stagedRequest = await db.rows(
      'SELECT request_id FROM crypto_business_requests WHERE partition=? AND operation_id=?',
      [p, operationId],
    );
    if (op['expectedRevision'] != expected && stagedRequest.isEmpty) {
      throw const CryptoAuthorityPending(
        'crypto_legacy_receipt_reconciliation_required',
      );
    }
    final payload = op['deleted'] == true ? null : op['payload'];
    if (payload != null && payload is! Map) {
      throw const FormatException('crypto_business_payload');
    }
    final retained = previous?['raw_payload'] == null
        ? null
        : jsonDecode(previous!['raw_payload'] as String);
    final changed = payload == null
        ? null
        : <String, dynamic>{
            ...payload,
            // The existing project serializer represents unarchived by omission.
            // Materialize this known default before merging retained future fields.
            if (domain == 'content' &&
                op['type'] == 'project' &&
                !payload.containsKey('archived'))
              'archived': false,
          };
    final merged = changed == null
        ? null
        : Map<String, dynamic>.from(
            CryptoBusinessPayload.merge(retained, changed) as Map,
          );
    await _writeRaw(
      scopeId: scope,
      domain: domain,
      id: id,
      type: op['type'] as String,
      operationId: operationId as String,
      expectedRevision: previous?['crypto_revision'] as int? ?? 0,
      raw: merged,
      previousHash: previous?['record_proof_hash'] as String?,
      localHash: await CryptoBusinessJson.hash(op),
    );
    final canonical = await _row(scope, domain, id, type: op['type'] as String);
    if (canonical == null) {
      throw const CryptoAuthorityPending('crypto_projection_pending');
    }
    return {
      'status': 'applied',
      'record': jsonDecode(canonical['projection'] as String),
    };
  }

  Future<Map<String, dynamic>> pushTaskWithCost(
    String scope,
    Map<String, Object?> params, {
    required String route,
  }) async {
    final routeVersion = int.parse(route.substring(4, 5));
    final contentVersion = params['operationContractVersion'] ?? routeVersion,
        financeVersion = params['financeOperationContractVersion'] ?? 2;
    if (contentVersion is! int ||
        contentVersion < 1 ||
        contentVersion > routeVersion ||
        !const {2, 3}.contains(financeVersion)) {
      throw const FormatException('crypto_task_cost_contract');
    }
    final taskOp = Map<String, dynamic>.from(params['operation'] as Map),
        financeOp = Map<String, dynamic>.from(
          params['financeOperation'] as Map,
        );
    final operation = taskOp['opId'],
        taskId = taskOp['recordId'] ?? taskOp['id'],
        entryId = financeOp['recordId'] ?? financeOp['id'];
    if (!isSharedUuid(operation) ||
        !isSharedUuid(financeOp['opId']) ||
        !isSharedUuid(taskId) ||
        !isSharedUuid(entryId) ||
        taskOp['type'] != 'task' ||
        financeOp['type'] != 'financeEntry' ||
        taskOp['deleted'] != false ||
        financeOp['deleted'] != false ||
        taskOp['expectedRevision'] is! int ||
        financeOp['expectedRevision'] is! int ||
        taskOp['payload'] is! Map ||
        financeOp['payload'] is! Map) {
      throw const FormatException('crypto_task_cost_pair');
    }
    final hash = await CryptoBusinessJson.hash({
      'scopeId': scope,
      'operation': taskOp,
      'financeOperation': financeOp,
      'operationContractVersion': contentVersion,
      'financeOperationContractVersion': financeVersion,
      'route': route,
    });
    final saved = await stagedGroup(operation, hash);
    Future<Map<String, dynamic>> finish(Map<String, dynamic> payload) async {
      _resolvingTaskCosts = true;
      try {
        final result = await publishPreparedGroup(
          operationId: operation,
          localHash: hash,
          recordProofs: (payload['records'] as List)
              .cast<Map<String, dynamic>>(),
          commitment: Map<String, dynamic>.from(payload['commitment'] as Map),
        );
        return {
          'status': 'applied',
          'record': result.singleWhere((r) => r['type'] == 'task'),
          'finance': {
            'status': 'applied',
            'record': result.singleWhere((r) => r['type'] == 'financeEntry'),
          },
        };
      } finally {
        _resolvingTaskCosts = false;
      }
    }

    if (saved != null) return finish(saved);
    await pullVerified(scope, 'content');
    await pullVerified(scope, 'finance');
    final beforeTask = await _row(scope, 'content', taskId, type: 'task'),
        beforeEntry = await _row(
          scope,
          'finance',
          entryId,
          type: 'financeEntry',
        );
    if (taskOp['expectedRevision'] !=
            (beforeTask == null ? 0 : _localRevision(beforeTask)) ||
        financeOp['expectedRevision'] !=
            (beforeEntry == null ? 0 : _localRevision(beforeEntry))) {
      throw const CollaborationException('stale_edit');
    }
    Map<String, dynamic> merge(Map<String, Object?>? before, Map changed) =>
        Map<String, dynamic>.from(
          CryptoBusinessPayload.merge(
                before?['raw_payload'] == null
                    ? null
                    : jsonDecode(before!['raw_payload'] as String),
                changed,
              )
              as Map,
        );
    final taskRaw = merge(beforeTask, taskOp['payload']);
    final entryRaw = await CryptoFinanceAccountChoices(
      this,
    ).prepareFinancialRecord(scope, merge(beforeEntry, financeOp['payload']));
    CryptoBusinessPayload.projection(
      'content',
      'task',
      taskRaw,
      personal: await _personal(scope),
    );
    CryptoBusinessPayload.projection(
      'finance',
      'financeEntry',
      entryRaw,
      personal: await _personal(scope),
    );
    if (entryRaw['taskId'] != null &&
        (entryRaw['taskId'] != taskId ||
            entryRaw['kind'] != 'expense' ||
            entryRaw['plannedAt'] != taskRaw['dueAt'])) {
      throw const FormatException('crypto_task_cost_pair');
    }
    if (entryRaw['taskId'] == null &&
        (beforeEntry == null ||
            (jsonDecode(beforeEntry['raw_payload'] as String)
                    as Map)['taskId'] !=
                taskId)) {
      throw const FormatException('crypto_task_cost_pair');
    }
    final content = await access.writeContext(scope, 'content'),
        finance = await access.writeContext(scope, 'finance'),
        signer = await access.signingKey();
    try {
      if (content.headHash != finance.headHash) {
        throw const CryptoAuthorityPending('crypto_scope_head_changed');
      }
      final batch = account.directory.reducer.crypto.randomId(),
          proofs = <Map<String, dynamic>>[],
          versions = <Map<String, dynamic>>[];
      Future<Map<String, Object?>> seal(
        String domain,
        String id,
        String type,
        Map<String, dynamic> raw,
        Map<String, Object?>? before, {
        bool intent = false,
      }) async {
        final write = domain == 'content' ? content : finance,
            a = address(scope, domain, type, id),
            expected = before?['crypto_revision'] as int? ?? 0;
        final metadata = intent
            ? {
                'identity': a.identity,
                'references': <Object>[],
                'referenceVersions': <Object>[],
                'uniqueRefs': <String>[],
                'blobIds': <String>[],
              }
            : await businessMetadata(
                scopeId: scope,
                domain: domain,
                type: type,
                canonicalId: id,
                expectedRevision: expected,
                rawPayload: raw,
                stagedReferenceVersions: versions,
              );
        final bytes = CryptoBusinessJson.encode({
          'format': 2,
          'identity': a.identity,
          'payload': raw,
        });
        try {
          final proof = codec.sealRecord(
            serverId: account.directory.session.profile.serverId,
            accountId: account.directory.accountId,
            deviceId: account.deviceId,
            batchId: batch,
            scopeId: scope,
            id: a.wireId,
            type: type,
            expectedRevision: expected,
            epoch: write.epoch,
            accessRevision: write.accessRevision,
            membershipHeadHash: write.headHash,
            domain: domain,
            contentContract: domain == 'content' ? 6 : 3,
            operationId: operation,
            previousRecordHash:
                before?['record_proof_hash'] as String? ?? '0' * 64,
            deleted: false,
            plaintext: bytes,
            metadata: metadata,
            contentKey: write.key.key,
            signingKey: signer.key,
          );
          final digest = await codec.digest(proof);
          proofs.add(proof);
          versions.add({
            'scopeId': scope,
            'domain': domain,
            'id': a.wireId,
            'revision': expected + 1,
            'recordProofHash': digest,
          });
          return {
            'crypto_revision': expected + 1,
            'record_proof_hash': digest,
            'deleted': 0,
            'raw_payload': jsonEncode(raw),
          };
        } finally {
          bytes.fillRange(0, bytes.length, 0);
        }
      }

      final task = await seal('content', taskId, 'task', taskRaw, beforeTask);
      final intentId = await _reservedId(scope, 'taskDerivation:$taskId'),
          intentRaw = _taskIntent(
            taskId,
            operation,
            task['crypto_revision'] as int,
            taskRaw,
          ),
          beforeIntent = await _row(
            scope,
            'content',
            intentId,
            type: 'taskDerivationIntent',
          );
      final intent = await seal(
        'content',
        intentId,
        'taskDerivationIntent',
        intentRaw,
        beforeIntent,
        intent: true,
      );
      final entry = await seal(
        'finance',
        entryId,
        'financeEntry',
        entryRaw,
        beforeEntry,
      );
      if (entryRaw['taskId'] != null) {
        proofs.add(
          await sealTaskResolution(
            this,
            scopeId: scope,
            batchId: batch,
            operationId: operation,
            entryId: entryId,
            revision: entry['crypto_revision'] as int,
            entryProofHash: entry['record_proof_hash'] as String,
            taskId: taskId,
            write: finance,
            signingKey: signer.key,
            stagedTask: task,
            stagedIntent: intent,
          ),
        );
      }
      final head = await access.headAt(scope, finance.headHash);
      financeAuthorityMembers[head.headHash] = {
        for (final m in head.members) m['accountId'] as String,
      };
      final projected = <CryptoBusinessProjection>[];
      for (final proof in proofs) {
        final body = Map<String, dynamic>.from(
          CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map,
        );
        final a = cryptoRecordAddressFromMetadata(body);
        Map<String, dynamic>? resolutionRaw;
        if (body['type'] == 'taskDerivationResolution') {
          final bytes = codec.openVerified(body, finance.key.key)!;
          try {
            resolutionRaw = Map<String, dynamic>.from(
              (jsonDecode(utf8.decode(bytes)) as Map)['payload'] as Map,
            );
          } finally {
            bytes.fillRange(0, bytes.length, 0);
          }
        }
        final raw = body['type'] == 'task'
            ? taskRaw
            : body['type'] == 'taskDerivationIntent'
            ? intentRaw
            : body['type'] == 'financeEntry'
            ? entryRaw
            : resolutionRaw!;
        projected.add(
          CryptoBusinessProjection(
            record: {...body, '_canonicalId': a.canonicalId},
            wire: {
              'revision': body['expectedRevision'] + 1,
              'authorization': {'recordProof': proof},
            },
            raw: raw,
            previousRaw:
                body['type'] == 'financeEntry' &&
                    beforeEntry?['raw_payload'] != null
                ? Map<String, dynamic>.from(
                    jsonDecode(beforeEntry!['raw_payload'] as String) as Map,
                  )
                : null,
          ),
        );
      }
      await CryptoBusinessFinance(this).validate(projected, forWrite: true);
      final commitment = await codec.commitBatch(
        serverId: account.directory.session.profile.serverId,
        accountId: account.directory.accountId,
        deviceId: account.deviceId,
        batchId: batch,
        records: proofs,
        signingKey: signer.key,
        projectionToken: (r) async => codec.projectionGroupToken(
          r,
          r['domain'] == 'content' ? content.key.key : finance.key.key,
        ),
      );
      return await finish({'records': proofs, 'commitment': commitment});
    } finally {
      content.key.release();
      finance.key.release();
      signer.release();
    }
  }

  Future<void> _writeRaw({
    required String scopeId,
    required String domain,
    required String id,
    required String type,
    required String operationId,
    required int expectedRevision,
    required Map<String, dynamic>? raw,
    required String localHash,
    String? previousHash,
    List<Map<String, dynamic>> tableLeases = const [],
    String? derivationTaskId,
  }) async {
    if (raw != null &&
        raw.length == 2 &&
        raw['migrationPayload'] == 3 &&
        raw.containsKey('bindingId')) {
      throw const FormatException('crypto_migration_provenance_required');
    }
    final prior = await db.rows(
      'SELECT * FROM crypto_business_requests WHERE partition=? AND operation_id=?',
      [p, operationId],
    );
    if (prior.isNotEmpty) {
      if (prior.single['request_hash'] != localHash ||
          prior.single['scope_id'] != scopeId ||
          prior.single['domain'] != domain ||
          prior.single['record_id'] != id) {
        throw const FormatException('crypto_immutable_business_request');
      }
    } else {
      if (raw != null && prepareOutgoing != null) {
        raw = await prepareOutgoing!(scopeId, type, id, raw, operationId);
      }
      if (raw != null && type != 'scopeMetadata') {
        final projected = validateRaw?.call(domain, type, raw);
        if (projected == null) {
          CryptoBusinessPayload.projection(
            domain,
            type,
            raw,
            personal: await _personal(scopeId),
          );
        }
      }
      if (domain == 'finance') {
        await CryptoBusinessFinance(this).outgoing(scopeId, id, type, raw);
      }
      final write = await access.writeContext(scopeId, domain),
          signing = await access.signingKey();
      Uint8List? plaintext;
      try {
        final wireRaw = raw == null
            ? null
            : await encodePayload?.call(
                    scopeId,
                    domain,
                    type,
                    id,
                    raw,
                    operationId,
                  ) ??
                  raw;
        final recordAddress = address(scopeId, domain, type, id);
        plaintext = wireRaw == null
            ? null
            : CryptoBusinessJson.encode({
                'format': 2,
                'identity': recordAddress.identity,
                'payload': wireRaw,
              });
        // Large records use the forthcoming authenticated blob-manifest path.
        // Retain original UI outbox; never truncate a formerly valid payload.
        if (plaintext != null && plaintext.length > 98304) {
          throw const CryptoAuthorityPending(
            'crypto_large_record_blob_pending',
          );
        }
        final refs = _references(scopeId, type, raw);
        final versions = await referenceVersions(refs);
        final batch = account.directory.reducer.crypto.randomId();
        final proof = codec.sealRecord(
          serverId: account.directory.session.profile.serverId,
          accountId: account.directory.accountId,
          deviceId: account.deviceId,
          batchId: batch,
          scopeId: scopeId,
          id: recordAddress.wireId,
          type: type,
          expectedRevision: expectedRevision,
          epoch: write.epoch,
          accessRevision: write.accessRevision,
          membershipHeadHash: write.headHash,
          domain: domain,
          contentContract: write.contentContract,
          operationId: operationId,
          previousRecordHash: previousHash ?? '0' * 64,
          deleted: raw == null,
          plaintext: plaintext,
          metadata: {
            'identity': recordAddress.identity,
            if (domain == 'finance')
              'auditState': {
                'version': 1,
                'changedAt': DateTime.now().toUtc().toIso8601String(),
              },
            'references': refs,
            'referenceVersions': versions,
            'uniqueRefs': domain == 'finance'
                ? await CryptoBusinessFinance(
                    this,
                  ).uniqueRefs(scopeId, type, raw)
                : <String>[],
            'blobIds': <String>{
              if (raw != null) ...?blobIds?.call(raw),
              if (wireRaw != null) ...?blobIds?.call(wireRaw),
            }.toList()..sort(),
            if (_notifiable(type))
              'notificationState': await _notificationState(
                scopeId,
                domain,
                id,
                type,
                expectedRevision,
                raw,
              ),
            ...await _scheduleMetadata(scopeId, domain, id, type, raw, refs),
          },
          contentKey: write.key.key,
          signingKey: signing.key,
        );
        final proofs = <Map<String, dynamic>>[proof];
        if (type == 'task') {
          final intentId = await _reservedId(scopeId, 'taskDerivation:$id');
          final previousIntent = await _row(
            scopeId,
            'content',
            intentId,
            type: 'taskDerivationIntent',
          );
          final intent = _taskIntent(
            id,
            operationId,
            expectedRevision + 1,
            raw,
          );
          final intentAddress = address(
            scopeId,
            'content',
            'taskDerivationIntent',
            intentId,
          );
          final bytes = CryptoBusinessJson.encode({
            'format': 2,
            'identity': intentAddress.identity,
            'payload': intent,
          });
          try {
            proofs.add(
              codec.sealRecord(
                serverId: account.directory.session.profile.serverId,
                accountId: account.directory.accountId,
                deviceId: account.deviceId,
                batchId: batch,
                scopeId: scopeId,
                id: intentAddress.wireId,
                type: 'taskDerivationIntent',
                expectedRevision:
                    previousIntent?['crypto_revision'] as int? ?? 0,
                epoch: write.epoch,
                accessRevision: write.accessRevision,
                membershipHeadHash: write.headHash,
                domain: 'content',
                contentContract: 6,
                operationId: operationId,
                previousRecordHash:
                    previousIntent?['record_proof_hash'] as String? ?? '0' * 64,
                deleted: false,
                plaintext: bytes,
                metadata: {
                  'identity': intentAddress.identity,
                  'references': <Object>[],
                  'referenceVersions': <Object>[],
                  'uniqueRefs': <String>[],
                  'blobIds': <String>[],
                },
                contentKey: write.key.key,
                signingKey: signing.key,
              ),
            );
          } finally {
            bytes.fillRange(0, bytes.length, 0);
          }
        }
        if (domain == 'finance' &&
            const {'financeEntry', 'personalFinanceEntry'}.contains(type) &&
            (raw?['taskId'] != null || derivationTaskId != null)) {
          proofs.add(
            await sealTaskResolution(
              this,
              scopeId: scopeId,
              batchId: batch,
              operationId: operationId,
              entryId: id,
              revision: expectedRevision + 1,
              entryProofHash: await codec.digest(proof),
              taskId: derivationTaskId ?? raw!['taskId'],
              detached: derivationTaskId != null,
              write: write,
              signingKey: signing.key,
            ),
          );
        }
        final commitment = await codec.commitBatch(
          serverId: account.directory.session.profile.serverId,
          accountId: account.directory.accountId,
          deviceId: account.deviceId,
          batchId: batch,
          records: proofs,
          signingKey: signing.key,
          projectionToken: (r) async =>
              codec.projectionGroupToken(r, write.key.key),
        );
        late String requestId;
        requestId = await queue.enqueueBatch(
          batchId: batch,
          recordProofs: proofs,
          commitment: commitment,
          tableLeases: tableLeases,
          applyLocal: () async {},
          onStaged: (stagedId) async {
            await db.execute(
              'INSERT INTO crypto_business_requests VALUES(?,?,?,?,?,?,?)',
              [p, operationId, scopeId, domain, localHash, stagedId, id],
            );
          },
        );
        if (requestId.isEmpty) {
          throw const FormatException('crypto_business_request');
        }
      } finally {
        plaintext?.fillRange(0, plaintext.length, 0);
        write.key.release();
        signing.release();
      }
    }
    final retry = (await db.rows(
      'SELECT request_id FROM crypto_business_requests WHERE partition=? AND operation_id=?',
      [p, operationId],
    )).single;
    await queue.resumeUnresolved(requestIds: {retry['request_id'] as String});
    final staged = (await db.rows(
      'SELECT o.state,o.signed_body FROM crypto_business_requests b JOIN crypto_outbox o ON o.partition=b.partition AND o.request_id=b.request_id WHERE b.partition=? AND b.operation_id=?',
      [p, operationId],
    )).single;
    if (staged['state'] != 'applied') {
      throw const CryptoAuthorityPending('crypto_business_delivery_pending');
    }
    await queue.pull(
      scopeId: scopeId,
      domain: domain,
      accessRevision: (await access.readContext(
        scopeId,
        domain,
      )).accessRevision,
    );
    final command = Map<String, dynamic>.from(
      CryptoJson.decode(
            cryptoBase64(
              (jsonDecode(staged['signed_body'] as String)
                  as Map)['commandBase64'],
            ),
          )
          as Map,
    );
    final proofs = ((command['payload'] as Map)['records'] as List).map(
      (value) => Map<String, dynamic>.from(value as Map),
    );
    final matches = <Map<String, dynamic>>[];
    for (final proof in proofs) {
      final body =
          CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map;
      if (body['scopeId'] == scopeId &&
          body['domain'] == domain &&
          body['id'] == address(scopeId, domain, type, id).wireId &&
          body['operationId'] == operationId) {
        matches.add(proof);
      }
    }
    if (matches.length != 1) {
      throw const FormatException('crypto_business_staged_identity');
    }
    final proof = matches.single;
    await _requireAppliedProjection(
      record: await _row(scopeId, domain, id, type: type),
      stagedProof: proof,
    );
    final budget = CryptoBusinessAckHistoryBudget();
    // Task and other compound operations have additional signed legs. They
    // must settle too before this immutable request becomes historical work.
    for (final sibling in proofs) {
      final body =
          CryptoJson.decode(cryptoBase64(sibling['commandBase64'])) as Map;
      await _requireAppliedProjection(
        record: await wireRecord(body['scopeId'], body['domain'], body['id']),
        stagedProof: sibling,
        budget: budget,
      );
    }
    await CryptoBusinessSettlement.record(
      database: db,
      partition: p,
      requestId: retry['request_id'] as String,
    );
  }

  Future<void> requirePreparedRecordProof(Map<String, dynamic> proof) async {
    final body = CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map;
    await _requireAppliedProjection(
      record: await wireRecord(body['scopeId'], body['domain'], body['id']),
      stagedProof: proof,
    );
  }

  Future<void> _requireAppliedProjection({
    required Map<String, Object?>? record,
    required Map<String, dynamic> stagedProof,
    CryptoBusinessAckHistoryBudget? budget,
  }) async {
    final body = Map<String, dynamic>.from(
      CryptoJson.decode(cryptoBase64(stagedProof['commandBase64'])) as Map,
    );
    try {
      requireExactBusinessProjection(
        record: record,
        stagedRecord: body,
        stagedProofHash: await codec.digest(stagedProof),
      );
      return;
    } on CryptoAuthorityPending {
      if (record == null ||
          record['crypto_revision'] is! int ||
          (record['crypto_revision'] as int) <=
              (body['expectedRevision'] as int) + 1) {
        rethrow;
      }
    }
    // Every staged leg reaches this independently. No receipt/verdict flag
    // replaces exact descent from the currently authenticated projection.
    await requireAuthenticatedBusinessAckAncestor(
      access: access,
      database: db,
      currentRecord: record,
      stagedProof: stagedProof,
      budget: budget,
    );
  }

  bool _notifiable(String type) => const [
    'project',
    'task',
    'event',
    'shoppingList',
    'shoppingItem',
    'idea',
    'financeAccount',
    'financeEntry',
    'financeTransfer',
    'personalFinanceEntry',
    'personalFinanceAccount',
    'financeRecurrenceRule',
    'paymentEvent',
    'paymentProjection',
    'cashMovement',
  ].contains(type);

  Map<String, dynamic> _notificationShape(
    String scope,
    String domain,
    String type,
    int expectedRevision,
    Map<String, dynamic>? raw,
    Map<String, dynamic>? before,
  ) {
    var kind = raw == null
        ? 'deleted'
        : expectedRevision == 0
        ? 'created'
        : 'updated';
    if (raw != null &&
        type == 'task' &&
        raw['isCompleted'] == true &&
        before?['isCompleted'] != true) {
      kind = 'completed';
    }
    if (raw != null &&
        type == 'shoppingItem' &&
        raw['isChecked'] == true &&
        before?['isChecked'] != true) {
      kind = 'checked';
    }
    final ids =
        domain == 'finance'
              ? <String>[]
              : ((raw ?? before)?['assigneeAccountIds'] as List? ?? [])
                    .cast<String>()
                    .toSet()
                    .toList()
          ..sort();
    return {
      'version': 1,
      'kind': kind,
      'assigneeAccountIds': ids,
      'groupTargetId':
          domain == 'finance' ||
              (raw ?? before)?[type == 'shoppingItem'
                      ? 'listId'
                      : 'projectId'] ==
                  null
          ? null
          : address(
              scope,
              'content',
              type == 'shoppingItem' ? 'shoppingList' : 'project',
              (raw ?? before)![type == 'shoppingItem' ? 'listId' : 'projectId'],
            ).wireId,
    };
  }

  Future<Map<String, dynamic>> _notificationState(
    String scope,
    String domain,
    String id,
    String type,
    int expectedRevision,
    Map<String, dynamic>? raw,
  ) async {
    final previous = await _row(scope, domain, id, type: type);
    if (expectedRevision > 0 && previous == null) {
      throw const CryptoAuthorityPending(
        'crypto_notification_predecessor_pending',
      );
    }
    final before = previous?['raw_payload'] == null
        ? null
        : Map<String, dynamic>.from(
            jsonDecode(previous!['raw_payload'] as String) as Map,
          );
    return _notificationShape(
      scope,
      domain,
      type,
      expectedRevision,
      raw,
      before,
    );
  }

  bool _remindable(String type) =>
      ['task', 'event', 'financeEntry', 'personalFinanceEntry'].contains(type);
  Map<String, dynamic> _scheduleShape(String type, Map<String, dynamic>? raw) {
    final closed =
        raw == null ||
        (type == 'task' && raw['isCompleted'] == true) ||
        (['financeEntry', 'personalFinanceEntry'].contains(type) &&
            (raw['status'] ?? 'posted') != 'planned');
    final date = raw == null
        ? null
        : type == 'task'
        ? raw['dueAt']
        : type == 'event'
        ? raw['startAt']
        : (raw['plannedAt'] ?? raw['occurredAt']);
    return {
      'version': 1,
      'dueAtEpoch': closed || date == null
          ? null
          : DateTime.parse(date as String).toUtc().millisecondsSinceEpoch ~/
                1000,
      'closed': closed,
    };
  }

  String _scheduleDates(Map<String, dynamic>? raw) =>
      CryptoBusinessJson.canonical([
        raw?['dueAt'],
        raw?['startAt'],
        raw?['endAt'],
        raw?['occurredAt'],
        raw?.containsKey('plannedAt') ?? false,
        raw?['plannedAt'],
      ]);
  Future<Map<String, dynamic>?> _previousSchedule(
    String scope,
    String domain,
    String id,
    int revision, {
    String stateKey = 'reminderState',
  }) async {
    final rows = await db.rows(
      'SELECT wire FROM crypto_received WHERE partition=? AND scope_id=? AND domain=? AND record_id=? AND revision=? AND verdict=\'verified\'',
      [p, scope, domain, id, revision],
    );
    if (rows.isEmpty) {
      final history = await db.rows(
        'SELECT record_body FROM crypto_business_history_payloads WHERE partition=? AND scope_id=? AND domain=? AND record_id=? AND revision=?',
        [p, scope, domain, id, revision],
      );
      if (history.length != 1) return null;
      final body = jsonDecode(history.single['record_body'] as String) as Map;
      final state = (body['metadata'] as Map)[stateKey];
      return state is Map ? Map<String, dynamic>.from(state) : null;
    }
    final wire = jsonDecode(rows.single['wire'] as String) as Map;
    final proof = (wire['authorization'] as Map)['recordProof'] as Map;
    final body = CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map;
    final state = (body['metadata'] as Map)[stateKey];
    return state is Map ? Map<String, dynamic>.from(state) : null;
  }

  Future<Map<String, dynamic>> _reminderState(
    String scope,
    String domain,
    String id,
    String type,
    Map<String, dynamic>? raw,
  ) async {
    final previous = await _row(scope, domain, id, type: type);
    String? token;
    Map<String, dynamic>? prior;
    if (previous != null) {
      prior = await _previousSchedule(
        scope,
        domain,
        address(scope, domain, type, id).wireId,
        previous['crypto_revision'] as int,
      );
      if (prior == null) {
        throw const CryptoAuthorityPending(
          'crypto_reminder_schedule_predecessor_pending',
        );
      }
      final before = previous['raw_payload'] == null
          ? null
          : Map<String, dynamic>.from(
              jsonDecode(previous['raw_payload'] as String) as Map,
            );
      if (_scheduleDates(before) == _scheduleDates(raw)) {
        token = prior['scheduleRevision'] as String;
      }
    }
    return CryptoConsentGeneration.transition(
      state: {
        ..._scheduleShape(type, raw),
        'scheduleRevision':
            token ?? account.directory.reducer.crypto.randomId(),
      },
      previous: prior,
      field: 'closed',
      wasDeleted: previous?['deleted'] == 1,
      deleted: raw == null,
      mint: account.directory.reducer.crypto.randomId,
    );
  }

  Future<Map<String, dynamic>> _scheduleMetadata(
    String scope,
    String domain,
    String id,
    String type,
    Map<String, dynamic>? raw,
    List<Map<String, dynamic>> refs,
  ) async {
    final metadata = <String, dynamic>{};
    if (_remindable(type)) {
      metadata['reminderState'] = await _reminderState(
        scope,
        domain,
        id,
        type,
        raw,
      );
    } else if (type == 'project') {
      final previous = await _row(scope, domain, id, type: type);
      final prior = previous == null
          ? null
          : await _previousSchedule(
              scope,
              domain,
              address(scope, domain, type, id).wireId,
              previous['crypto_revision'] as int,
              stateKey: 'projectState',
            );
      if (previous != null && prior == null) {
        throw const CryptoAuthorityPending(
          'crypto_project_state_predecessor_pending',
        );
      }
      metadata['projectState'] = CryptoConsentGeneration.transition(
        state: {
          'version': 1,
          'archived': raw == null || raw['archived'] == true,
        },
        previous: prior,
        field: 'archived',
        wasDeleted: previous?['deleted'] == 1,
        deleted: raw == null,
        mint: account.directory.reducer.crypto.randomId,
      );
    }
    return CryptoConsentGeneration.disclosure(
      metadata,
      (prospective) => CryptoSchedulingUse(this).forTarget(
        scope,
        type,
        address(scope, domain, type, id).wireId,
        {...prospective, 'references': refs},
      ),
    );
  }

  Future<String> _reservedId(String scope, String kind) async {
    final hash = await cryptoSha256(
      utf8.encode(
        'JivieReservedRecord/v2\n${account.directory.session.profile.serverId}:$scope:$kind',
      ),
    );
    return '${hash.substring(0, 8)}-${hash.substring(8, 12)}-4${hash.substring(13, 16)}-a${hash.substring(17, 20)}-${hash.substring(20, 32)}';
  }

  Map<String, dynamic> _taskIntent(
    String task,
    String operation,
    int revision,
    Map<String, dynamic>? raw,
  ) => {
    'version': 1,
    'taskId': task,
    'targetOperationId': operation,
    'targetCryptoRevision': revision,
    'deadlineEpoch': raw?['dueAt'] == null
        ? null
        : DateTime.parse(
                raw!['dueAt'] as String,
              ).toUtc().millisecondsSinceEpoch ~/
              1000,
    'completed': raw?['isCompleted'] ?? false,
    'deleted': raw == null,
  };
  List<Map<String, dynamic>> _references(
    String scope,
    String type,
    Map<String, dynamic>? raw,
  ) {
    if (raw == null) return [];
    final custom = references?.call(type, raw);
    final refs =
        custom ??
        [
          for (final field in switch (type) {
            'task' || 'event' || 'idea' => ['projectId'],
            'shoppingItem' => ['listId'],
            'financeEntry' || 'personalFinanceEntry' => [
              'accountId',
              'ledgerAccountId',
              'taskId',
              'projectId',
              'recurrenceRuleId',
              'payerPersonId',
              'recipientPersonId',
            ],
            'financeTransfer' => ['fromAccountId', 'toAccountId'],
            'taskDerivationResolution' => [
              'taskId',
              'intentId',
              'financeEntryId',
            ],
            'financeRecurrenceRule' => [
              'accountId',
              'payerPersonId',
              'recipientPersonId',
            ],
            _ => <String>[],
          })
            if (raw[field] != null)
              {
                'scopeId': scope,
                'id': raw[field],
                'type': switch (field) {
                  'projectId' => 'project',
                  'listId' => 'shoppingList',
                  'taskId' => 'task',
                  'intentId' => 'taskDerivationIntent',
                  'financeEntryId' => 'financeEntry',
                  'recurrenceRuleId' => 'financeRecurrenceRule',
                  'payerPersonId' || 'recipientPersonId' => 'householdPerson',
                  _ => 'financeAccount',
                },
              },
        ];
    final remoteAccount =
        type == 'financeEntry' &&
        raw['accountScopeId'] != null &&
        raw['accountScopeId'] != scope;
    final witness = raw['accountChoiceWitness'];
    if (remoteAccount &&
        (witness is! Map || !isCryptoCanonicalUuid(witness['manifestId']))) {
      throw const CryptoAuthorityPending(
        'crypto_parent_account_certificate_pending',
      );
    }
    final graphRefs = [
      for (final ref in refs)
        if (!remoteAccount ||
            ref['type'] != 'financeAccount' ||
            !const [
              'accountId',
              'ledgerAccountId',
            ].any((f) => raw[f] == ref['id']))
          ref,
      if (remoteAccount)
        {
          'scopeId': scope,
          'id': (witness as Map)['manifestId'],
          'type': 'financeAccountChoice',
        },
      // Legacy inline-project deletion selects financial rows by either exact
      // project or task association, including preserved future/raw fields on
      // existing supported financial models. New signed proofs expose those
      // same-scope graph edges so deletion can verify its complete source set.
      if (const {
        'financeAccount',
        'personalFinanceAccount',
        'financeEntry',
        'personalFinanceEntry',
        'financeTransfer',
        'financeRecurrenceRule',
      }.contains(type))
        for (final field in ['projectId', 'taskId'])
          if (raw[field] != null)
            {
              'scopeId': scope,
              'id': raw[field],
              'type': field == 'projectId' ? 'project' : 'task',
            },
    ];
    final unique = <String, Map<String, dynamic>>{};
    for (final ref in graphRefs) {
      final targetType = ref['type'];
      final targetScope = ref.containsKey('scopeId') ? ref['scopeId'] : scope;
      if (targetType is! String ||
          !isCryptoCanonicalUuid(targetScope) ||
          !isCryptoCanonicalUuid(ref['id']) ||
          ref.keys.any((key) => !['scopeId', 'id', 'type'].contains(key)) ||
          !ref.containsKey('id')) {
        throw const FormatException('crypto_reference_type_required');
      }
      final wire = cryptoWireRecordId(
        account.directory.session.profile.serverId,
        targetScope as String,
        targetType,
        ref['id'],
      );
      unique['$targetScope/$wire'] = {'scopeId': targetScope, 'id': wire};
    }
    final entries = unique.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return entries.map((e) => e.value).toList();
  }

  Future<List<Map<String, dynamic>>> referenceVersions(
    List<Map<String, dynamic>> refs,
  ) async {
    final result = <Map<String, dynamic>>[];
    for (final ref in refs) {
      final rows = await db.rows(
        'SELECT domain,crypto_revision,record_proof_hash FROM crypto_business_records WHERE partition=? AND scope_id=? AND id=? AND deleted=0',
        [p, ref['scopeId'], ref['id']],
      );
      if (rows.length != 1) throw const CryptoProjectionPending();
      final row = rows.single;
      result.add({
        ...ref,
        'domain': row['domain'],
        'revision': row['crypto_revision'],
        'recordProofHash': row['record_proof_hash'],
      });
    }
    result.sort(
      (a, b) => '${a['scopeId']}/${a['domain']}/${a['id']}'.compareTo(
        '${b['scopeId']}/${b['domain']}/${b['id']}',
      ),
    );
    return result;
  }

  Future<bool> _personal(String scope) async {
    return (await _verifiedScopeDescriptor(scope))['kind'] == 'personal';
  }

  /// Uses the explicit isolated FILE descriptor capability only in cold verification.
  Future<Map<String, dynamic>> verifiedBusinessScopeDescriptor(String scope) =>
      _verifiedScopeDescriptor(scope);

  Future<Map<String, dynamic>> _verifiedScopeDescriptor(String scope) async {
    try {
      return await access.verifiedScopeDescriptor(scope);
    } on CryptoAuthorityPending catch (error) {
      if (error.reason != 'scope_descriptor_migration_pending') rethrow;
      final resolve = coldScopeDescriptor;
      if (resolve == null) rethrow;
      await access.requireReadOnlyFrozenScope(scope);
      return resolve(scope);
    }
  }

  int _localRevision(Map<String, Object?> value) {
    final legacy = value['legacy_revision'] as int,
        revision = value['crypto_revision'] as int;
    return value['revision_namespace'] == 'legacy' || legacy > 0
        ? legacy + revision - 1
        : revision;
  }

  Future<bool> _observedComplete(String scope, String domain) async {
    final rows = await db.rows(
      'SELECT complete FROM crypto_scope_state WHERE partition=? AND scope_id=? AND domain=?',
      [p, scope, domain],
    );
    if (rows.isEmpty || rows.single['complete'] != 1) return false;
    // Content edits by an editor without the finance DEK remain valid while
    // their financial derivation is unresolved. Do not label those totals ready.
    // Only the already verified complete finance inventory can prove that a
    // content intent has no linked money effect; an incomplete page cannot.
    if (domain == 'finance') {
      final pending = await db.rows(
        "SELECT 1 FROM crypto_business_records WHERE partition=? AND scope_id=? AND domain='content' AND type='taskDerivationIntent' AND deleted=0 AND EXISTS(SELECT 1 FROM crypto_business_records linked WHERE linked.partition=crypto_business_records.partition AND linked.scope_id=crypto_business_records.scope_id AND linked.domain='finance' AND linked.type IN ('financeEntry','personalFinanceEntry') AND linked.deleted=0 AND json_extract(linked.raw_payload,'\$.taskId')=json_extract(crypto_business_records.raw_payload,'\$.taskId')) AND NOT EXISTS(SELECT 1 FROM crypto_business_records resolution WHERE resolution.partition=crypto_business_records.partition AND resolution.scope_id=crypto_business_records.scope_id AND resolution.domain='finance' AND resolution.type='taskDerivationResolution' AND resolution.deleted=0 AND json_extract(resolution.raw_payload,'\$.intentProofHash')=crypto_business_records.record_proof_hash AND json_extract(resolution.raw_payload,'\$.state')='derived') LIMIT 1",
        [p, scope],
      );
      if (pending.isNotEmpty) return false;
    }
    return true;
  }

  /// Complete signer-observed structure plus each readable child's authenticated
  /// complete finance inventory. Unknown private tokens never mean zero money.
  Future<Map<String, dynamic>> organizationFinanceCoverage(
    String scope, {
    bool refreshRootFinance = false,
    String? expectedHeadHash,
  }) async {
    final incomplete = <String, dynamic>{
      'organizationFinanceComplete': false,
      'organizationFinanceScopeIds': <String>[],
      'organizationFinanceSequences': <String, int>{},
    };
    final descriptor = await _verifiedScopeDescriptor(scope);
    if (!const ['household', 'organization'].contains(descriptor['kind'])) {
      return incomplete;
    }
    CryptoReadContext? rootRead;
    if (refreshRootFinance) {
      final head = await access.currentHead(scope, online: true);
      if (head.headHash != expectedHeadHash ||
          !const [
            'read',
            'write',
          ].contains(head.member(account.directory.accountId)['financeRole'])) {
        return incomplete;
      }
      await pullVerified(scope, 'finance');
      rootRead = await access.readContext(scope, 'finance');
      if (rootRead.headHash != head.headHash ||
          !await _observedComplete(scope, 'finance') ||
          !await hasReusableCheckpoint(scope, 'finance', rootRead)) {
        return incomplete;
      }
    }
    await pullVerified(scope, 'content');
    final metadata = await _row(
      scope,
      'content',
      await _reservedId(scope, 'scopeMetadata'),
      type: 'scopeMetadata',
    );
    if (metadata == null || metadata['deleted'] == 1) return incomplete;
    final raw = Map<String, dynamic>.from(
      jsonDecode(metadata['raw_payload'] as String),
    );
    if (raw['financeTopology'] is! Map) return incomplete;
    final topology = Map<String, dynamic>.from(raw['financeTopology']);
    final server = account.directory.session.profile.serverId;
    await CryptoFinanceTopology.validate(
      topology,
      serverId: server,
      scopeId: scope,
    );
    final required = (topology['childTokens'] as List).cast<String>().toSet();
    final ids = <String>[], sequences = <String, int>{};
    final checked = <String, String>{
      scope: rootRead?.headHash ?? (await access.currentHead(scope)).headHash,
    };
    for (final candidate in await catalog()) {
      final child = candidate['id'] as String;
      if (child == scope) continue;
      final token = await CryptoFinanceTopology.childToken(
        server,
        scope,
        child,
      );
      final selected = required.contains(token);
      // Catalog is routing only; a selected token is admitted only after its
      // signed descriptor independently confirms this exact parent relation.
      if (!selected && candidate['parentScopeId'] != scope) continue;
      try {
        final childDescriptor = await _verifiedScopeDescriptor(child);
        final parentToken = await cryptoSha256([
          ...utf8.encode('JivieParentLifecycleScope/v2\n'),
          ...CryptoJson.encode({
            'version': 2,
            'serverId': server,
            'scopeId': child,
            'parentScopeId': scope,
          }),
        ]);
        if (childDescriptor['parentScopeToken'] != parentToken) {
          if (selected) return incomplete;
          continue;
        }
        if (!selected) return incomplete;
        final head = await access.currentHead(child, online: true);
        if (!const [
          'read',
          'write',
        ].contains(head.member(account.directory.accountId)['financeRole'])) {
          return incomplete;
        }
        await pullVerified(child, 'finance');
        final read = await access.readContext(child, 'finance');
        if (!await _observedComplete(child, 'finance') ||
            !await hasReusableCheckpoint(child, 'finance', read)) {
          return incomplete;
        }
        final state = await db.rows(
          'SELECT scope_sequence FROM crypto_scope_state WHERE partition=? AND scope_id=? AND domain=\'finance\'',
          [p, child],
        );
        if (state.length != 1 || state.single['scope_sequence'] is! int) {
          return incomplete;
        }
        ids.add(child);
        sequences[child] = state.single['scope_sequence'] as int;
        checked[child] = read.headHash;
        required.remove(token);
      } on CryptoAuthorityPending {
        return incomplete;
      } on CollaborationException {
        return incomplete;
      }
    }
    if (required.isNotEmpty || !await _observedComplete(scope, 'finance')) {
      return incomplete;
    }
    for (final item in checked.entries) {
      if ((await access.currentHead(item.key, online: true)).headHash !=
          item.value) {
        return incomplete;
      }
    }
    final current = await _row(
      scope,
      'content',
      await _reservedId(scope, 'scopeMetadata'),
      type: 'scopeMetadata',
    );
    if (!account.directory.isCurrent() ||
        current?['record_proof_hash'] != metadata['record_proof_hash'] ||
        rootRead != null &&
            !await hasReusableCheckpoint(scope, 'finance', rootRead)) {
      return incomplete;
    }
    ids.sort();
    return {
      'organizationFinanceComplete': true,
      'organizationFinanceScopeIds': ids,
      'organizationFinanceSequences': sequences,
    };
  }

  Future<Map<String, dynamic>> pull(
    String scope,
    String domain,
    Map<String, Object?> params,
  ) async {
    await pullVerified(scope, domain);
    final cursor = params['cursor'];
    if (cursor is! int || cursor < 0) {
      throw const FormatException('crypto_business_cursor');
    }
    final rows = await db.rows(
      'SELECT b.projection,r.sequence FROM crypto_business_records b JOIN crypto_received r ON r.partition=b.partition AND r.scope_id=b.scope_id AND r.domain=b.domain AND r.record_id=b.id AND r.revision=b.crypto_revision WHERE b.partition=? AND b.scope_id=? AND b.domain=? AND r.sequence>? AND b.type NOT IN (\'scopeMetadata\',\'taskDerivationIntent\',\'taskDerivationResolution\',\'financeAccountChoice\') ORDER BY r.sequence LIMIT 100',
      [p, scope, domain, cursor],
    );
    return {
      'records': [
        for (final row in rows) jsonDecode(row['projection'] as String),
      ],
      'cursor': rows.isEmpty ? cursor : rows.last['sequence'],
      'hasMore': rows.length == 100,
      if (domain == 'finance') ...{
        'accessRevision': (await financePolicy(scope))['revision'],
        'cryptoProjectionComplete': await _observedComplete(scope, domain),
        'cryptoCompletenessBasis': 'signerObservedSnapshot',
        ...await organizationFinanceCoverage(scope),
      },
    };
  }

  Future<void> project(List<CryptoProjectionRecord> batch) async {
    final next = <Map<String, dynamic>>[];
    for (final value in batch) {
      if (!value.historicalOnly) {
        await CryptoBusinessHistory(this).requireRestoredIntersection(value);
      } else if (value.historicalAnchorWire == null) {
        throw const FormatException('crypto_projection_historical_anchor');
      }
      if ((value.record['metadata'] as Map)['identity'] == null) {
        throw const CryptoProjectionPending();
      }
      final recordAddress = cryptoRecordAddressFromMetadata(value.record);
      final r = {...value.record, '_canonicalId': recordAddress.canonicalId},
          wire = value.wire;
      final visiblePrevious = await _wireRow(
        r['scopeId'] as String,
        r['domain'] as String,
        r['id'] as String,
      );
      Map<String, Object?>? previous = value.historicalOnly
          ? null
          : visiblePrevious;
      if ((r['expectedRevision'] as int) > 0 &&
          (value.historicalOnly ||
              visiblePrevious?['crypto_revision'] != r['expectedRevision'])) {
        final history = await db.rows(
          'SELECT * FROM crypto_business_history_payloads WHERE partition=? AND scope_id=? AND domain=? AND record_id=? AND revision=? AND proof_hash=?',
          [
            p,
            r['scopeId'],
            r['domain'],
            r['id'],
            r['expectedRevision'],
            r['previousRecordHash'],
          ],
        );
        if (history.isEmpty) throw const CryptoProjectionPending();
        previous = {
          ...history.single,
          'crypto_revision': history.single['revision'],
          'record_proof_hash': history.single['proof_hash'],
          'legacy_revision': visiblePrevious?['legacy_revision'] ?? 0,
          'revision_namespace':
              visiblePrevious?['revision_namespace'] ?? 'crypto',
        };
      }
      if (previous != null &&
          (previous['crypto_revision'] as int) > (wire['revision'] as int)) {
        throw const FormatException('crypto_business_revision_rollback');
      }
      if (previous != null &&
          previous['crypto_revision'] == r['expectedRevision'] &&
          previous['record_proof_hash'] != r['previousRecordHash']) {
        throw const FormatException('crypto_business_predecessor');
      }
      final semanticPrevious = r['expectedRevision'] == 0 ? null : previous;
      Map<String, dynamic>? raw;
      Map<String, dynamic>? decodedEnvelope;
      if (value.plaintext != null) {
        final body = jsonDecode(utf8.decode(value.plaintext!));
        if (body is! Map ||
            body.length !=
                (value.migrationOrigin == null ||
                        value.migrationOrigin!['captureVersion'] == 3 ||
                        value.migrationOrigin!['sourceTable'] ==
                            'familyhub_scopes'
                    ? 3
                    : 4) ||
            body['format'] != 2 ||
            CryptoBusinessJson.canonical(body['identity']) !=
                CryptoBusinessJson.canonical(recordAddress.identity) ||
            body['payload'] is! Map) {
          throw const FormatException('crypto_business_envelope');
        }
        decodedEnvelope = Map<String, dynamic>.from(body);
        raw = Map<String, dynamic>.from(body['payload'] as Map);
      }
      if (raw != null &&
          raw.length == 2 &&
          raw['migrationPayload'] == 3 &&
          raw.containsKey('bindingId') &&
          value.migrationOrigin?['captureVersion'] != 3) {
        throw const FormatException('crypto_migration_provenance_required');
      }
      if (value.migrationOrigin != null) {
        raw = await verifyCryptoMigrationWitness(
          record: value.record,
          origin: value.migrationOrigin!,
          recordProofHash: await codec.digest(
            Map<String, dynamic>.from(
              (wire['authorization'] as Map)['recordProof'] as Map,
            ),
          ),
          envelope: decodedEnvelope,
          detachedWitness: value.migrationWitness,
          reservedId: reservedRecordId,
        );
      }
      if (raw != null && expandPayload != null) {
        raw = await expandPayload!(value, raw);
      }
      final type = r['type'] as String;
      if (_notifiable(type)) {
        if ((r['expectedRevision'] as int) > 0 && previous == null) {
          throw const CryptoProjectionPending();
        }
        final before = semanticPrevious?['raw_payload'] == null
            ? null
            : Map<String, dynamic>.from(
                jsonDecode(semanticPrevious!['raw_payload'] as String) as Map,
              );
        final expected = _notificationShape(
          r['scopeId'],
          r['domain'] as String,
          type,
          r['expectedRevision'] as int,
          raw,
          before,
        );
        if ((value.historyBasis == 'inlineProjectDeletion' ||
                (value.historyBasis == 'managerAttestedProjectRelocation' &&
                    ((value.record['metadata'] as Map)['projectRelocation']
                            as Map?)?['side'] ==
                        'source')) &&
            r['deleted'] == true &&
            raw == null &&
            (r['metadata'] as Map)['inlineDeletion'] is Map) {
          // Finalized whole-project deletion removes the parent edge too.
          // Its verified graph publication, rather than a live reference,
          // authorizes this tombstone's notification grouping.
          expected['groupTargetId'] = null;
        }
        if (CryptoBusinessJson.canonical(
              (r['metadata'] as Map)['notificationState'],
            ) !=
            CryptoBusinessJson.canonical(expected)) {
          throw const FormatException('crypto_notification_state_mismatch');
        }
      }
      if (type == 'project') {
        final supplied = (r['metadata'] as Map)['projectState'];
        if (supplied is! Map ||
            CryptoBusinessJson.canonical(
                  Map<String, dynamic>.from(supplied)
                    ..remove('consentGeneration'),
                ) !=
                CryptoBusinessJson.canonical({
                  'version': 1,
                  'archived': raw == null || raw['archived'] == true,
                })) {
          throw const FormatException('crypto_project_state_mismatch');
        }
        final prior = semanticPrevious == null
            ? null
            : await _previousSchedule(
                r['scopeId'] as String,
                r['domain'] as String,
                r['id'] as String,
                semanticPrevious['crypto_revision'] as int,
                stateKey: 'projectState',
              );
        if (semanticPrevious != null && prior == null) {
          throw const CryptoProjectionPending();
        }
        CryptoConsentGeneration.validate(
          supplied,
          prior,
          'archived',
          semanticPrevious != null && semanticPrevious['raw_payload'] == null,
          r['deleted'] == true,
        );
      }
      if (_remindable(type)) {
        final supplied = (r['metadata'] as Map)['reminderState'];
        if (supplied is! Map ||
            !CryptoConsentGeneration.matchesReminder(
              supplied,
              _scheduleShape(type, raw),
            )) {
          throw const FormatException('crypto_reminder_state_mismatch');
        }
        CryptoConsentGeneration.validate(
          supplied,
          null,
          'closed',
          false,
          r['deleted'] == true,
        );
        if (semanticPrevious != null) {
          final prior = await _previousSchedule(
            r['scopeId'] as String,
            r['domain'] as String,
            r['id'] as String,
            semanticPrevious['crypto_revision'] as int,
          );
          if (prior == null) throw const CryptoProjectionPending();
          CryptoConsentGeneration.validate(
            supplied,
            prior,
            'closed',
            semanticPrevious['raw_payload'] == null,
            r['deleted'] == true,
          );
          final before = semanticPrevious['raw_payload'] == null
              ? null
              : Map<String, dynamic>.from(
                  jsonDecode(semanticPrevious['raw_payload'] as String) as Map,
                );
          final same = _scheduleDates(before) == _scheduleDates(raw);
          if (same !=
              (prior['scheduleRevision'] == supplied['scheduleRevision'])) {
            throw const FormatException('crypto_reminder_schedule_revision');
          }
        }
      }
      Map<String, dynamic>? projected;
      if (raw != null) {
        final extension = await projectExtension?.call(value, raw);
        if (extension != null) {
          projected = extension;
        } else if (type == 'taskDerivationIntent') {
          if (raw.length != 7 ||
              raw['version'] != 1 ||
              !isSharedUuid(raw['taskId']) ||
              !isSharedUuid(raw['targetOperationId']) ||
              raw['targetCryptoRevision'] is! int ||
              raw['completed'] is! bool ||
              raw['deleted'] is! bool) {
            throw const FormatException('crypto_task_derivation_intent');
          }
          projected = raw;
        } else if (type == 'taskDerivationResolution') {
          if (r['domain'] != 'finance' ||
              raw['version'] != 1 ||
              !isSharedUuid(raw['taskId']) ||
              !isSharedUuid(raw['intentId']) ||
              !isSharedUuid(raw['financeEntryId']) ||
              (raw['state'] != 'derived' &&
                  !(raw['state'] == 'legacyPending' &&
                      value.migrationOrigin?['captureVersion'] == 3 &&
                      value.migrationOrigin?['materializationRole'] ==
                          'taskDerivationResolution')) ||
              raw['targetCryptoRevision'] is! int ||
              !isSharedUuid(raw['targetOperationId'])) {
            throw const FormatException('crypto_task_resolution');
          }
          projected = raw;
        } else if (type == 'scopeMetadata') {
          if (raw['name'] is! String || raw['archived'] is! bool) {
            throw const FormatException('crypto_scope_metadata');
          }
          if (recordAddress.canonicalId !=
                  await _reservedId(r['scopeId'] as String, 'scopeMetadata') ||
              raw['scopeId'] != r['scopeId'] ||
              raw['namespaceVersion'] != 1) {
            throw const FormatException('crypto_scope_metadata_namespace');
          }
          validateSharedText(raw['name'], 300);
          if (raw.containsKey('financeTopology')) {
            await CryptoFinanceTopology.validate(
              Map<String, dynamic>.from(raw['financeTopology'] as Map),
              serverId: account.directory.session.profile.serverId,
              scopeId: r['scopeId'],
            );
          }
          projected = raw;
        } else {
          try {
            projected = CryptoBusinessPayload.projection(
              r['domain'] as String,
              type,
              raw,
              personal: await _personal(r['scopeId'] as String),
            );
          } on CollaborationException {
            throw const FormatException('crypto_business_validation');
          }
        }
      }
      final primaryMigration =
          value.migrationOrigin != null &&
          (value.migrationOrigin!['materializationRole'] ?? 'primary') ==
              'primary';
      final relocation = await verifiedProjectRelocationLineage(this, value);
      int? relocationBase;
      if (relocation != null) {
        const keys = {
          'version',
          'actionId',
          'side',
          'logicalRevision',
          'physicalRevision',
          'recordProofHash',
        };
        if (relocation.length != keys.length ||
            !relocation.keys.every(keys.contains) ||
            relocation['version'] != 2 ||
            !isSharedUuid(relocation['actionId']) ||
            !const {'source', 'target'}.contains(relocation['side']) ||
            relocation['logicalRevision'] is! int ||
            relocation['logicalRevision'] < 1 ||
            relocation['physicalRevision'] is! int ||
            relocation['physicalRevision'] < 1 ||
            relocation['physicalRevision'] > wire['revision'] ||
            relocation['recordProofHash'] is! String ||
            !RegExp(
              r'^[a-f0-9]{64}$',
            ).hasMatch(relocation['recordProofHash'])) {
          throw const FormatException('crypto_project_relocation_lineage');
        }
        relocationBase =
            relocation['logicalRevision'] - relocation['physicalRevision'] + 1;
        if (relocationBase! < 1) {
          throw const FormatException('crypto_project_relocation_lineage');
        }
      }
      if (previous?['revision_namespace'] == 'relocation' &&
          relocation == null) {
        throw const CryptoAuthorityPending(
          'crypto_project_relocation_lineage_pending',
        );
      }
      final legacy =
          relocationBase ??
          previous?['legacy_revision'] as int? ??
          (primaryMigration
              ? value.migrationOrigin!['legacyRevision'] as int?
              : null) ??
          0;
      final revisionNamespace = relocationBase != null
          ? 'relocation'
          : primaryMigration ||
                relocationBase != null ||
                previous?['revision_namespace'] == 'legacy' ||
                legacy > 0
          ? 'legacy'
          : 'crypto';
      final revision =
          const {'legacy', 'relocation'}.contains(revisionNamespace)
          ? legacy + (wire['revision'] as int) - 1
          : wire['revision'] as int;
      final canonical = {
        'id': recordAddress.canonicalId,
        'type': type,
        'revision': revision,
        'deleted': r['deleted'],
        'payload': projected,
        'contractVersion': r['domain'] == 'finance' ? 3 : 6,
      };
      next.add({
        'record': r,
        'wire': wire,
        'raw': raw,
        'canonical': canonical,
        'legacy': legacy,
        'revisionNamespace': revisionNamespace,
        'hash': await codec.digest(
          Map<String, dynamic>.from(
            (wire['authorization'] as Map)['recordProof'] as Map,
          ),
        ),
        'basis': value.historyBasis,
        'migrationOrigin': value.migrationOrigin,
        'relocationOrigin': relocation,
        'historicalOnly': value.historicalOnly,
        'historicalAnchorWire': value.historicalAnchorWire,
        'previousRaw': semanticPrevious?['raw_payload'] == null
            ? null
            : jsonDecode(semanticPrevious!['raw_payload'] as String),
      });
    }
    await CryptoBusinessFinance(this).validate([
      for (final value in next)
        CryptoBusinessProjection(
          record: Map<String, dynamic>.from(value['record'] as Map),
          wire: Map<String, dynamic>.from(value['wire'] as Map),
          historicalOnly: value['historicalOnly'] == true,
          historyBasis: value['basis'] as String?,
          historicalAnchorWire:
              value['historicalAnchorWire'] as Map<String, dynamic>?,
          relocationOrigin: value['relocationOrigin'] as Map<String, dynamic>?,
          migrationOrigin: value['migrationOrigin'] == null
              ? null
              : Map<String, dynamic>.from(value['migrationOrigin'] as Map),
          raw: value['raw'] as Map<String, dynamic>?,
          previousRaw: value['previousRaw'] == null
              ? null
              : Map<String, dynamic>.from(value['previousRaw'] as Map),
        ),
    ]);
    // All semantic checks happen before the first visible canonical write.
    for (final value in next) {
      final r = value['record'] as Map, raw = value['raw'] as Map?;
      if (r['type'] == 'task') {
        // This purpose is supplied only by the finalized whole-project graph
        // verifier. Its exact signed all-tombstone set replaces the ordinary
        // live task intent; it never invokes standalone task-cost derivation.
        if (raw == null &&
            (value['basis'] == 'inlineProjectDeletion' &&
                    (r['metadata'] as Map)['inlineDeletion'] is Map ||
                value['basis'] == 'managerAttestedProjectRelocation' &&
                    ((r['metadata'] as Map)['projectRelocation']
                            as Map?)?['side'] ==
                        'source')) {
          continue;
        }
        final intentId = await _reservedId(
          r['scopeId'] as String,
          'taskDerivation:${r['_canonicalId']}',
        );
        final matches = next.where(
          (v) =>
              (v['record'] as Map)['id'] ==
                  address(
                    r['scopeId'],
                    'content',
                    'taskDerivationIntent',
                    intentId,
                  ).wireId &&
              (v['record'] as Map)['type'] == 'taskDerivationIntent',
        );
        if (matches.length != 1) throw const CryptoProjectionPending();
        final expected = _taskIntent(
          r['_canonicalId'] as String,
          r['operationId'] as String,
          (value['wire'] as Map)['revision'] as int,
          raw == null ? null : Map<String, dynamic>.from(raw),
        );
        if (CryptoBusinessJson.canonical(matches.single['raw']) !=
            CryptoBusinessJson.canonical(expected)) {
          throw const FormatException('crypto_task_derivation_mismatch');
        }
      }
      if (raw == null) continue;
      final expectedRefs = _references(
        r['scopeId'] as String,
        r['type'] as String,
        Map<String, dynamic>.from(raw),
      );
      final metadata = r['metadata'] as Map;
      if (CryptoBusinessJson.canonical(metadata['references']) !=
          CryptoBusinessJson.canonical(expectedRefs)) {
        throw const FormatException('crypto_business_reference_binding');
      }
      final versions = metadata['referenceVersions'];
      if (expectedRefs.isNotEmpty && versions is! List) {
        throw const CryptoProjectionPending();
      }
      bool deletedTaskEvidence(Map ref) =>
          r['type'] == 'taskDerivationResolution' &&
          ref['scopeId'] == r['scopeId'] &&
          ref['domain'] == 'content' &&
          ref['id'] ==
              address(r['scopeId'], 'content', 'task', raw['taskId']).wireId &&
          ref['recordProofHash'] == raw['taskProofHash'] &&
          ref['revision'] == raw['targetCryptoRevision'];
      for (final ref in (versions as List? ?? const []).cast<Map>()) {
        final target = next
            .where(
              (v) =>
                  (v['record'] as Map)['scopeId'] == ref['scopeId'] &&
                  (v['record'] as Map)['domain'] == ref['domain'] &&
                  (v['record'] as Map)['id'] == ref['id'] &&
                  (v['wire'] as Map)['revision'] == ref['revision'] &&
                  v['hash'] == ref['recordProofHash'],
            )
            .firstOrNull;
        if (target != null) {
          if ((target['record'] as Map)['deleted'] == true &&
                  !deletedTaskEvidence(ref) ||
              (target['wire'] as Map)['revision'] != ref['revision'] ||
              target['hash'] != ref['recordProofHash']) {
            throw const FormatException('crypto_business_reference');
          }
        } else {
          final historical = await CryptoBusinessReferences(this).resolve(
            Map<String, dynamic>.from(r),
            ref['scopeId'],
            ref['domain'],
            ref['id'],
          );
          if (historical['deleted'] == 1 && !deletedTaskEvidence(ref)) {
            throw const FormatException('crypto_business_reference');
          }
        }
      }
    }
    for (final value in next.where((v) => v['historicalOnly'] != true)) {
      final r = value['record'] as Map, wire = value['wire'] as Map;
      await addresses.install(
        cryptoRecordAddressFromMetadata(Map<String, dynamic>.from(r)),
      );
      await db.execute(
        'INSERT INTO crypto_business_records VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?) ON CONFLICT(partition,scope_id,domain,id) DO UPDATE SET type=excluded.type,crypto_revision=excluded.crypto_revision,legacy_revision=excluded.legacy_revision,record_proof_hash=excluded.record_proof_hash,deleted=excluded.deleted,raw_payload=excluded.raw_payload,projection=excluded.projection,history_basis=excluded.history_basis,revision_namespace=excluded.revision_namespace',
        [
          p,
          r['scopeId'],
          r['domain'],
          r['id'],
          r['type'],
          wire['revision'],
          value['legacy'],
          value['hash'],
          r['deleted'] == true ? 1 : 0,
          value['raw'] == null ? null : jsonEncode(value['raw']),
          jsonEncode(value['canonical']),
          value['basis'],
          value['revisionNamespace'],
        ],
      );
      final origin = value['migrationOrigin'];
      if (r['type'] == 'scopeMetadata' &&
          origin is Map &&
          origin['sourceTable'] == 'familyhub_scopes') {
        final raw = value['raw'] as Map;
        final descriptor = jsonEncode({
          'id': r['scopeId'],
          'kind': raw['kind'],
          'accessPolicyVersion': raw['accessPolicyVersion'],
          'parentScopeToken': raw['parentScopeToken'],
          if (raw.containsKey('financePolicy'))
            'financePolicy': raw['financePolicy'],
          if (raw.containsKey('leaderAccountIds'))
            'leaderAccountIds': raw['leaderAccountIds'],
          if (raw.containsKey('financeTopology'))
            'financeTopology': raw['financeTopology'],
        });
        final known = await db.rows(
          'SELECT descriptor,source_proof_hash FROM crypto_business_scope_descriptors WHERE partition=? AND scope_id=?',
          [p, r['scopeId']],
        );
        if (known.isNotEmpty &&
            (known.single['descriptor'] != descriptor ||
                known.single['source_proof_hash'] != value['hash'])) {
          throw const FormatException('crypto_scope_descriptor_changed');
        }
        await db.execute(
          'INSERT OR IGNORE INTO crypto_business_scope_descriptors VALUES(?,?,?,?)',
          [p, r['scopeId'], descriptor, value['hash']],
        );
      }
    }
  }
}

/// A transport ACK is insufficient: only the exact authenticated, semantically
/// validated local projection can release the original legacy operation.
void requireExactBusinessProjection({
  required Map<String, Object?>? record,
  required Map<String, dynamic> stagedRecord,
  required String stagedProofHash,
}) {
  if (record == null ||
      record['scope_id'] != stagedRecord['scopeId'] ||
      record['domain'] != stagedRecord['domain'] ||
      record['id'] != stagedRecord['id'] ||
      record['crypto_revision'] !=
          (stagedRecord['expectedRevision'] as int) + 1 ||
      record['record_proof_hash'] != stagedProofHash ||
      record['type'] != stagedRecord['type'] ||
      record['deleted'] != (stagedRecord['deleted'] == true ? 1 : 0)) {
    throw const CryptoAuthorityPending(
      'crypto_business_ack_projection_pending',
    );
  }
}

class CryptoBusinessProjection {
  const CryptoBusinessProjection({
    required this.record,
    required this.raw,
    required this.previousRaw,
    this.wire,
    this.migrationOrigin,
    this.relocationOrigin,
    this.historicalOnly = false,
    this.historicalAnchorWire,
    this.historyBasis,
  });
  final bool historicalOnly;
  final Map<String, dynamic>? historicalAnchorWire;

  /// Incoming signature/provenance verifier result; never restored SQL input.
  final String? historyBasis;
  final Map<String, dynamic> record;
  final Map<String, dynamic>? raw, previousRaw;

  /// Exact already authenticated received wire; absent for pre-seal writes.
  final Map<String, dynamic>? wire;

  /// Supplied only after the dedicated migration authority and complete source
  /// witness have passed. Never inferred from a payload flag or restored SQL.
  final Map<String, dynamic>? migrationOrigin;
  final Map<String, dynamic>? relocationOrigin;
}
