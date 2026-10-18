import 'dart:convert';
import 'dart:typed_data';

import '../collaboration_transport.dart';
import 'account_directory_v2.dart';
import 'crypto_business_inline_deletion.dart';
import 'crypto_business_json.dart';
import 'crypto_business_finance.dart';
import 'crypto_business_router.dart';
import 'crypto_document_blob.dart';
import 'crypto_finance_audit_evidence.dart';
import 'crypto_finance_policy_actions.dart';
import 'crypto_finance_topology.dart';
import 'crypto_json.dart';
import 'crypto_lifecycle_evidence.dart';
import 'crypto_project_relocation_codec.dart';
import 'crypto_project_relocation_graph.dart';
import 'crypto_project_relocation_target.dart';
import 'crypto_record_address.dart';
import 'crypto_migration_record_source.dart';
import 'crypto_sync_repository.dart';
import 'session_crypto_access.dart'
    show CryptoWriteContext, SessionCryptoAccess;

/// Existing inline household project → separate shared project. The complete
/// graph, bytes and history are prepared before one atomic signed publication.
class CryptoBusinessProjectRelocation {
  CryptoBusinessProjectRelocation(this.context);
  final CryptoBusinessSession context;
  static const operations = {
    'scopes.projectSharingPreview',
    'scopes.projectSharingApply',
  };
  static const deliveryOperations = {
    'crypto2.projectRelocation.prepare',
    'crypto2.projectRelocation.sources',
    'crypto2.projectRelocation.origin',
    'crypto2.projectRelocation.targetCommand',
    'crypto2.projectRelocation.targetActivation',
    'crypto2.projectRelocation.records',
    'crypto2.projectRelocation.blob',
    'crypto2.projectRelocation.auditStage',
    'crypto2.projectRelocation.notificationCandidates',
    'crypto2.projectRelocation.notificationStage',
    'crypto2.projectRelocation.commit',
    'crypto2.projectRelocation.cancel',
  };
  static Future<void> verifyDelivery(
    SessionCryptoAccess access,
    Map<String, dynamic> command,
  ) async {
    if (!deliveryOperations.contains(command['operation']))
      throw const FormatException('crypto_relocation_operation');
    final account = access.account,
        own = await access.account.directory.requireFresh();
    final device = own.activeDevice(account.deviceId);
    if (device['keyringWrite'] != true)
      throw const CryptoAuthorityPending('device_keyring_write_required');
    final payload = command['payload'] as Map;
    Map<String, dynamic> proof;
    Map<String, dynamic>? workflow;
    if (command['operation'] == 'crypto2.projectRelocation.prepare') {
      proof = Map<String, dynamic>.from(payload['planProof'] as Map);
    } else {
      final rows = await account.store.database.rows(
        "SELECT payload FROM crypto_membership_intents WHERE partition=? AND state='projectRelocationWorkflow'",
        [account.store.partition],
      );
      for (final row in rows) {
        final value =
            jsonDecode(utf8.decode((row['payload'] as List).cast<int>()))
                as Map;
        if (value['actionId'] == payload['actionId']) {
          if (workflow != null)
            throw const FormatException('crypto_relocation_local_duplicate');
          workflow = Map<String, dynamic>.from(value);
        }
      }
      if (workflow == null || workflow['planHash'] != payload['planHash'])
        throw const CryptoAuthorityPending('crypto_relocation_plan_pending');
      proof = Map<String, dynamic>.from(workflow['planProof'] as Map);
    }
    final plan = CryptoProjectRelocationCodec.body(proof);
    if (plan['version'] != 2 ||
        plan['serverId'] != own.serverId ||
        plan['accountId'] != own.accountId ||
        plan['deviceId'] != account.deviceId ||
        payload['actionId'] != null && plan['actionId'] != payload['actionId'])
      throw const FormatException('crypto_relocation_delivery_identity');
    if (command['operation'] == 'crypto2.projectRelocation.cancel') return;
    final source = await access.currentHead(
      plan['sourceScopeId'],
      online: true,
    );
    if (source.headHash != plan['sourceHeadHash'] ||
        source.accessRevision != plan['sourceAccessRevision'] ||
        source.member(own.accountId)['manageKeys'] != true)
      throw const CryptoAuthorityPending('project_sharing_preview_changed');
    final prefix = await access.directoryAt(
      scopeId: source.scopeId,
      scopeHeadHash: source.headHash,
      accountId: own.accountId,
      directoryHeadHash: plan['authorDirectoryHeadHash'],
      online: true,
    );
    if (prefix.identityEpochId != own.identityEpochId ||
        prefix.deviceSnapshotHash != own.deviceSnapshotHash ||
        prefix.rootFingerprint != own.rootFingerprint)
      throw const CryptoAuthorityPending('crypto_relocation_identity_changed');
    account.directory.reducer.crypto.verifyDomain(
      proof,
      cryptoBase64(
        prefix.activeDevice(account.deviceId)['signingKeyBase64'],
        length: 32,
      ),
      'JivieProjectRelocationPlan/v2\n',
    );
    final lifecycle = await CryptoLifecycleEvidence(
      access,
    ).current(source.scopeId);
    if (lifecycle['headHash'] != plan['sourceLifecycleHash'])
      throw const CryptoAuthorityPending('project_sharing_preview_changed');
    if ((workflow?['preview']?['movedFinanceRecordIds'] as List? ?? const [])
            .isNotEmpty &&
        source.member(own.accountId)['financeRole'] != 'write')
      throw const CryptoAuthorityPending('finance_write_required');
    if (command['operation'] == 'crypto2.projectRelocation.commit') {
      final event = CryptoProjectRelocationCodec.body(
        payload['accountEventProof'] as Map,
      );
      if (event['operation'] != 'crypto2.account.projectRelocation' ||
          event['requestId'] != command['requestId'] ||
          event['accountId'] != own.accountId ||
          event['deviceId'] != account.deviceId ||
          event['payload']['actionId'] != plan['actionId'])
        throw const FormatException('crypto_relocation_companion_binding');
    }
  }

  bool supports(String operation) => operations.contains(operation);
  String _id() => context.account.directory.reducer.crypto.randomId();
  Map<String, dynamic> _body(Map proof) => Map<String, dynamic>.from(
    CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map,
  );
  Future<String> _hash(Object? value) => cryptoSha256(CryptoJson.encode(value));
  Future<Map<String, dynamic>> _sign(
    Map<String, dynamic> body,
    String domain,
  ) async {
    final lease = await context.account.signingKey();
    try {
      return context.account.directory.reducer.crypto.signDomain(
        body,
        lease.key,
        domain,
      );
    } finally {
      lease.release();
    }
  }

  Future<Map<String, dynamic>?> _load(String scope, String key) async {
    final rows = await context.database.rows(
      'SELECT payload FROM crypto_membership_intents WHERE partition=? AND scope_id=? AND intent_id=? AND state=?',
      [context.partition, scope, key, 'projectRelocationWorkflow'],
    );
    return rows.isEmpty
        ? null
        : Map<String, dynamic>.from(
            jsonDecode(
                  utf8.decode((rows.single['payload'] as List).cast<int>()),
                )
                as Map,
          );
  }

  Future<void> _save(
    String scope,
    String key,
    Map<String, dynamic> value,
  ) => context.database.execute(
    'INSERT INTO crypto_membership_intents VALUES(?,?,?,?,?,NULL) ON CONFLICT(partition,scope_id,intent_id) DO UPDATE SET payload=excluded.payload',
    [
      context.partition,
      scope,
      key,
      'projectRelocationWorkflow',
      CryptoBusinessJson.encode(value),
    ],
  );
  Future<Map<String, dynamic>> _send(
    String key,
    String operation,
    Map<String, dynamic> payload, {
    String? requestId,
  }) async {
    final id = await context.queue.enqueueCommand(
      actionKey: key,
      requestId: requestId,
      operation: operation,
      payload: payload,
    );
    await context.queue.resumeUnresolved(requestIds: {id});
    final row = await context.queue.store.outgoing(id);
    if (row?['state'] == 'blocked') {
      final blocked = jsonDecode(row!['response'] as String) as Map;
      final reason = blocked['code'] ?? blocked['reason'];
      throw CryptoAuthorityPending(
        reason is String ? reason : 'crypto_command_receipt_pending',
      );
    }
    if (row?['state'] == 'rejected') {
      final r =
          (jsonDecode(row!['response'] as String) as Map)['response'] as Map;
      throw CollaborationApiException(
        r['errorCode'] as String,
        details: r['details'] is Map
            ? Map<String, dynamic>.from(r['details'] as Map)
            : const {},
      );
    }
    return context.queue.commandResult(id);
  }

  Future<List<CryptoRelocationRecord>> _historicalLinks(
    String scope,
    Map<String, Map<String, dynamic>> inventory,
  ) async {
    final payments = <CryptoRelocationRecord>[];
    for (final item in inventory.values) {
      final current = item['body'] as Map;
      if (current['deleted'] != true && current['type'] != 'paymentEvent')
        continue;
      final retained = await context.database.rows(
        'SELECT wire FROM crypto_received WHERE partition=? AND scope_id=? AND domain=? AND record_id=? AND revision=?',
        [
          context.partition,
          scope,
          current['domain'],
          current['id'],
          current['expectedRevision'] + 1,
        ],
      );
      if (retained.length != 1)
        throw const CryptoAuthorityPending('crypto_relocation_history_pending');
      final wire = Map<String, dynamic>.from(
        jsonDecode(retained.single['wire'] as String) as Map,
      );
      final chain = await context.access.openHistoryChain(wire);
      var candidate = wire, count = 0;
      while (!chain.complete) {
        if (++count > 10000)
          throw const CryptoAuthorityPending(
            'crypto_relocation_history_capacity',
          );
        final authority = await chain.authority(candidate);
        final body = _body(candidate['authorization']['recordProof'] as Map);
        await context.codec.verifyWire(
          serverId: body['serverId'],
          wire: candidate,
          trustedSigningKey: authority.signingKey,
          currentEpoch: authority.currentEpoch,
          closedRecordProofHash: authority.closedRecordProofHash,
        );
        if (body['deleted'] != true) {
          final key = await context.access.recordKey(body);
          Uint8List? bytes;
          try {
            bytes = context.codec.openVerified(body, key.key);
            if (bytes == null)
              throw const FormatException('crypto_relocation_history_payload');
            final envelope = Map<String, dynamic>.from(
              jsonDecode(utf8.decode(bytes)) as Map,
            );
            Map<String, dynamic>? raw = Map<String, dynamic>.from(
              envelope['payload'] as Map,
            );
            if (authority.migrationOrigin != null)
              raw = await verifyCryptoMigrationWitness(
                record: body,
                origin: authority.migrationOrigin!,
                recordProofHash: await _hash(
                  candidate['authorization']['recordProof'],
                ),
                envelope: envelope,
                detachedWitness: authority.migrationWitness,
                reservedId: context.reservedRecordId,
              );
            final value = CryptoProjectionRecord(
              candidate,
              body,
              bytes,
              historyBasis: authority.historyBasis ?? 'currentEpoch',
              batchKey: 'relocationHistory',
              migrationOrigin: authority.migrationOrigin,
              migrationWitness: authority.migrationWitness,
              relocationOrigin: authority.relocationOrigin,
            );
            if (raw != null && context.expandPayload != null) {
              await context.prepareHistoricalPayload?.call([value]);
              raw = await context.expandPayload!(value, raw);
            }
            if (current['deleted'] == true && item['raw'] == null)
              item['raw'] = raw;
            if (body['type'] == 'paymentEvent')
              payments.add(
                CryptoRelocationRecord(
                  id: body['metadata']['identity']['canonicalId'],
                  wireId: body['id'],
                  type: body['type'],
                  revision: body['expectedRevision'] + 1,
                  logicalRevision: body['expectedRevision'] + 1,
                  proofHash: await _hash(
                    candidate['authorization']['recordProof'],
                  ),
                  deleted: false,
                  raw: raw,
                ),
              );
          } finally {
            bytes?.fillRange(0, bytes.length, 0);
            key.release();
          }
          if (current['type'] != 'paymentEvent') break;
        }
        if (chain.complete) break;
        final read = await context.access.readContext(scope, current['domain']);
        final page = await context.account.directory.call(
          'crypto2.records.historyGet',
          {
            'scopeId': scope,
            'domain': current['domain'],
            'accessRevision': read.accessRevision,
            'id': current['id'],
            'revision': chain.nextRevision,
            'recordProofHash': chain.nextHash,
            'evidenceFor': {
              'scopeId': scope,
              'id': current['id'],
              'revision': wire['revision'],
              'recordProofHash': await _hash(
                wire['authorization']['recordProof'],
              ),
            },
          },
        );
        candidate = Map<String, dynamic>.from(page['record'] as Map);
      }
    }
    return payments;
  }

  int _logicalRevision(Map row) {
    final physical = row['crypto_revision'];
    final projection = row['projection'], legacy = row['legacy_revision'];
    if (physical is! int ||
        physical < 1 ||
        physical > 9007199254740991 ||
        legacy is! int ||
        legacy < 0 ||
        legacy > 9007199254740991 ||
        projection is! String) {
      throw const FormatException('crypto_relocation_source_revision');
    }
    final decoded = jsonDecode(projection);
    if (decoded is! Map) {
      throw const FormatException('crypto_relocation_source_revision');
    }
    final revision = decoded.containsKey('revision')
        ? decoded['revision']
        : (legacy > 0 ? legacy + physical - 1 : physical);
    if (revision is! int || revision < 1 || revision > 9007199254740991) {
      throw const FormatException('crypto_relocation_source_revision');
    }
    return revision;
  }

  Future<
    ({
      CryptoProjectRelocationGraph graph,
      Map<String, Map<String, dynamic>> inventory,
      List<Map<String, dynamic>> audit,
      Map<String, dynamic> preview,
    })
  >
  _preview(String scope, String project) async {
    final head = await context.access.currentHead(scope, online: true);
    final descriptor = await context.access.verifiedScopeDescriptor(scope);
    if (descriptor['kind'] != 'household' ||
        descriptor['accessPolicyVersion'] != 3 ||
        head.member(context.account.directory.accountId)['manageKeys'] != true)
      throw const CryptoAuthorityPending('access_migration_required');
    final verifiedInventory = await CryptoBusinessInlineDeletion(
      context,
    ).verifiedInventory(scope);
    final inventory = <String, Map<String, dynamic>>{
      for (final e in verifiedInventory.entries)
        e.key: Map<String, dynamic>.from(e.value),
    };
    final paymentHistory = await _historicalLinks(scope, inventory);
    final parentMetadata = inventory.values
        .where(
          (v) =>
              v['body']['type'] == 'scopeMetadata' &&
              v['body']['deleted'] == false,
        )
        .toList();
    if (parentMetadata.length != 1 ||
        parentMetadata.single['raw']?['financeTopology'] is! Map)
      throw const CryptoAuthorityPending(
        'crypto_finance_topology_baseline_pending',
      );
    final parentTopology = Map<String, dynamic>.from(
      parentMetadata.single['raw']['financeTopology'] as Map,
    );
    await CryptoFinanceTopology.validate(
      parentTopology,
      serverId:
          head.body['serverId'] as String? ??
          context.account.directory.session.profile.serverId,
      scopeId: scope,
    );
    final rows = <CryptoRelocationRecord>[];
    for (final item in inventory.values) {
      final body = item['body'] as Map, row = item['row'] as Map;
      rows.add(
        CryptoRelocationRecord(
          id: item['canonicalId'],
          wireId: body['id'],
          type: body['type'],
          revision: body['expectedRevision'] + 1,
          logicalRevision: _logicalRevision(row),
          proofHash: row['record_proof_hash'],
          deleted: body['deleted'],
          raw: item['raw'] == null
              ? null
              : Map<String, dynamic>.from(item['raw'] as Map),
        ),
      );
    }
    final graph = CryptoProjectRelocationGraph.select(
      projectId: project,
      inventory: rows,
      paymentHistory: paymentHistory,
      targetScopeExists: (await context.catalog()).any(
        (s) => s['id'] == project,
      ),
    );
    final audit = <Map<String, dynamic>>[];
    if (graph.canApply) {
      for (final record in graph.records.where(
        (r) =>
            cryptoRecordSourceKind(r.type) == 'finance_records' &&
            r.type != 'taskDerivationResolution',
      )) {
        await for (final page in CryptoFinanceAuditEvidence(
          context,
        ).historyPages(scope, record.id)) {
          for (final entry in page) {
            if (audit.length >= 10000)
              throw const CryptoAuthorityPending('crypto_relocation_capacity');
            audit.add({...entry, 'sourceWireId': record.wireId});
          }
        }
      }
    }
    audit.sort(
      (a, b) => (a['sourceEvidenceHash'] as String).compareTo(
        b['sourceEvidenceHash'],
      ),
    );
    if (audit.map((a) => a['sourceEvidenceHash']).toSet().length !=
        audit.length)
      throw const FormatException('crypto_relocation_audit_duplicate');
    final lifecycle = await CryptoLifecycleEvidence(
      context.access,
    ).current(scope);
    final graphRoot = await graph.root;
    final previewHash = await _hash({
      'version': 2,
      'scopeId': scope,
      'projectId': project,
      'sourceHeadHash': head.headHash,
      'accessRevision': head.accessRevision,
      'lifecycleHash': lifecycle['headHash'],
      'graphRoot': graphRoot,
      'parentMetadataProofHash':
          parentMetadata.single['row']['record_proof_hash'],
      'parentTopologyRoot': parentTopology['root'],
      'auditRoot': await CryptoProjectRelocationCodec.digestRoot(
        'audit',
        audit.map((a) => a['sourceEvidenceHash'] as String).toList(),
      ),
    });
    final root = graph.records.singleWhere(
      (r) => r.type == 'project' && r.id == project,
    );
    final result = <String, dynamic>{
      'scopeId': scope,
      'projectId': project,
      'projectName': root.raw?['name'] ?? root.raw?['title'] ?? '',
      'canApply': graph.canApply,
      'previewHash': previewHash,
      'blockers': graph.blockers,
      'movedRecordIds': [
        for (final r in graph.records)
          if (r.domain == 'content') r.id,
      ],
      'movedFinanceRecordIds': [
        for (final r in graph.records)
          if (r.domain == 'finance') r.id,
      ],
      'movedReminderIds': <String>[],
      'financeAccounts': [
        for (final r in graph.records)
          if (r.type == 'financeAccount' || r.type == 'personalFinanceAccount')
            r.raw!,
      ],
      'householdPeople': [
        for (final r in graph.records)
          if (r.type == 'householdPerson') r.raw!,
      ],
    };
    return (graph: graph, inventory: inventory, audit: audit, preview: result);
  }

  Future<Map<String, dynamic>> dispatch(
    String operation,
    Map<String, Object?> params,
  ) async {
    if (!supports(operation) ||
        !isCryptoCanonicalUuid(params['scopeId']) ||
        !isCryptoCanonicalUuid(params['projectId']))
      throw const FormatException('crypto_relocation_action');
    final scope = params['scopeId'] as String,
        project = params['projectId'] as String;
    if (operation == 'scopes.projectSharingPreview')
      return (await _preview(scope, project)).preview;
    if (!isCryptoCanonicalUuid(params['requestId']) ||
        params['previewHash'] is! String)
      throw const FormatException('crypto_relocation_request');
    final request = params['requestId'] as String,
        key = 'projectRelocation:$request';
    var saved = await _load(scope, key);
    // Retrieve an accepted outcome before any new source inventory, attachment
    // read or current-role requirement; later legitimate changes stay intact.
    if (saved?['commit'] is Map) {
      final result = await _send(
        '$key:commit',
        'crypto2.projectRelocation.commit',
        Map<String, dynamic>.from(saved!['commit'] as Map),
        requestId: saved['commitRequestId'],
      );
      return _finish(saved, result);
    }
    final preview = await _preview(scope, project);
    if (!preview.graph.canApply)
      throw const CryptoAuthorityPending('project_sharing_blocked');
    if (preview.preview['previewHash'] != params['previewHash'])
      throw const CryptoAuthorityPending('project_sharing_preview_changed');
    if (saved == null) {
      final own = await context.account.directory.requireFresh(),
          head = await context.access.currentHead(scope, online: true);
      final lifecycle = await CryptoLifecycleEvidence(
        context.access,
      ).current(scope);
      final action = _id();
      final plan = {
        'version': 2,
        'serverId': own.serverId,
        'actionId': action,
        'requestId': request,
        'accountId': own.accountId,
        'deviceId': context.account.deviceId,
        'authorDirectoryHeadHash': own.headHash,
        'sourceScopeId': scope,
        'targetScopeId': project,
        'projectId': project,
        'projectWireId': context
            .address(scope, 'content', 'project', project)
            .wireId,
        'sourceHeadHash': head.headHash,
        'sourceAccessRevision': head.accessRevision,
        'sourceLifecycleHash': lifecycle['headHash'],
        'sourceGraphRoot': await preview.graph.root,
        'sourceGraphCount': preview.graph.records.length,
        'sourceAuditRoot': await CryptoProjectRelocationCodec.digestRoot(
          'audit',
          preview.audit.map((e) => e['sourceEvidenceHash'] as String).toList(),
        ),
        'sourceAuditCount': preview.audit.length,
        'parentMetadataProofHash': preview.inventory.values.singleWhere(
          (v) => v['body']['type'] == 'scopeMetadata',
        )['row']['record_proof_hash'],
        'parentTopologyGeneration': preview.inventory.values.singleWhere(
          (v) => v['body']['type'] == 'scopeMetadata',
        )['raw']['financeTopology']['generation'],
        'targetOwnerAccountId': head.members.singleWhere(
          (m) => m['role'] == 'owner',
        )['accountId'],
        'targetParentScopeToken': await CryptoLifecycleEvidence(
          context.access,
        ).parentToken(project, scope),
      };
      final proof = await _sign(plan, 'JivieProjectRelocationPlan/v2\n');
      final planHash = await _hash(proof);
      final origin = await _sign({
        'version': 2,
        'operation': 'crypto2.scope.origin',
        'serverId': own.serverId,
        'scopeId': project,
        'kind': 'project',
        'accessPolicyVersion': 3,
        'parentScopeToken': plan['targetParentScopeToken'],
        'requestId': request,
        'accountId': own.accountId,
        'deviceId': context.account.deviceId,
        'authorDirectoryHeadHash': own.headHash,
        'projectRelocation': {
          'version': 2,
          'actionId': action,
          'planHash': planHash,
        },
      }, 'JivieE2EE/scopeOrigin/v2\n');
      saved = {
        'scopeId': scope,
        'projectId': project,
        'requestId': request,
        'previewHash': params['previewHash'],
        'actionId': action,
        'planHash': planHash,
        'planProof': proof,
        'originProof': origin,
        'preview': preview.preview,
      };
      await _save(scope, key, saved);
    }
    if (saved['previewHash'] != params['previewHash'] ||
        saved['scopeId'] != scope ||
        saved['projectId'] != project)
      throw const FormatException('crypto_relocation_immutable_action');
    await _send('$key:prepare', 'crypto2.projectRelocation.prepare', {
      'planProof': saved['planProof'],
    }, requestId: request);
    for (var offset = 0; offset < preview.graph.records.length; offset += 32) {
      await _send('$key:sources:$offset', 'crypto2.projectRelocation.sources', {
        'actionId': saved['actionId'],
        'planHash': saved['planHash'],
        'descriptors': preview.graph.records
            .skip(offset)
            .take(32)
            .map((r) => r.descriptor)
            .toList(),
      });
    }
    final targetProducer = CryptoProjectRelocationTarget(
      context,
      (k, op, p) => _send(k, op, p),
    );
    final target = await targetProducer.prepare(
      planProof: Map<String, dynamic>.from(saved['planProof'] as Map),
      originProof: Map<String, dynamic>.from(saved['originProof'] as Map),
    );
    if (saved['groups'] == null) {
      saved['groups'] = await _seal(
        saved,
        preview.graph,
        preview.inventory,
        target,
        targetProducer,
      );
      await _save(scope, key, saved);
    }
    for (var i = 0; i < (saved['groups'] as List).length; i++) {
      await _send('$key:records:$i', 'crypto2.projectRelocation.records', {
        'actionId': saved['actionId'],
        'planHash': saved['planHash'],
        ...Map<String, dynamic>.from(saved['groups'][i] as Map),
      });
    }
    final audit = await _audit(saved, preview.audit, target, targetProducer);
    final notifications = await _notifications(saved, key);
    final commit = await _publication(saved, target, audit, notifications);
    saved['commit'] = commit;
    saved['commitRequestId'] = _body(
      commit['accountEventProof'] as Map,
    )['requestId'];
    await _save(scope, key, saved);
    final result = await _send(
      '$key:commit',
      'crypto2.projectRelocation.commit',
      commit,
      requestId: saved['commitRequestId'],
    );
    return _finish(saved, result);
  }

  Future<Object?> _retargetBlobs(
    Object? value,
    String canonical,
    String operation,
    PreparedProjectRelocationTarget target,
    CryptoProjectRelocationTarget producer,
    Map<String, dynamic> saved,
  ) async {
    if (value is List)
      return [
        for (final item in value)
          await _retargetBlobs(
            item,
            canonical,
            operation,
            target,
            producer,
            saved,
          ),
      ];
    if (value is! Map) return value;
    if (value['version'] == 2 &&
        value['scopeId'] is String &&
        value['manifestBase64'] is String &&
        value['cipherSha256'] is String) {
      final blobs = CryptoDocumentBlob(context),
          old = Map<String, dynamic>.from(value);
      final bytes = await blobs.open(old);
      try {
        final d = await blobs.stage(
          scopeId: target.head.scopeId,
          recordId: canonical,
          operationId: '$operation:${old['id']}',
          kind: 'projectRelocation',
          plaintext: bytes,
          domain: old['domain'],
          relocationTarget: target,
        );
        await producer.uploadBlob(
          actionId: saved['actionId'],
          planHash: saved['planHash'],
          descriptor: d,
        );
        return d;
      } finally {
        bytes.fillRange(0, bytes.length, 0);
      }
    }
    return <String, dynamic>{
      for (final entry in value.entries)
        entry.key as String: await _retargetBlobs(
          entry.value,
          canonical,
          operation,
          target,
          producer,
          saved,
        ),
    };
  }

  void _collectBlobs(Object? value, Set<String> ids) {
    if (value is List) {
      for (final item in value) {
        _collectBlobs(item, ids);
      }
      return;
    }
    if (value is! Map) return;
    if (value['version'] == 2 &&
        value['scopeId'] is String &&
        value['manifestBase64'] is String &&
        value['id'] is String)
      ids.add(value['id']);
    for (final item in value.values) {
      _collectBlobs(item, ids);
    }
  }

  Future<List<Map<String, dynamic>>> _seal(
    Map<String, dynamic> saved,
    CryptoProjectRelocationGraph graph,
    Map<String, Map<String, dynamic>> inventory,
    PreparedProjectRelocationTarget target,
    CryptoProjectRelocationTarget producer,
  ) async {
    final source = saved['scopeId'] as String, scope = target.head.scopeId;
    final families = <String, List<CryptoRelocationRecord>>{};
    final familyByWire = <String, String>{};
    for (final row in graph.records) {
      final task = row.type == 'task' ? row.id : row.raw?['taskId'];
      final family = task is String ? 'task:$task' : 'record:${row.wireId}';
      (families[family] ??= []).add(row);
      familyByWire[row.wireId] = family;
    }
    if (families.values.any((rows) => rows.length > 32))
      throw const CryptoAuthorityPending(
        'crypto_relocation_atomic_family_capacity',
      );
    final familyBatches = {for (final family in families.keys) family: _id()};
    final familyOperations = {
      for (final family in families.keys) family: _id(),
    };
    final canonical = <String, String>{};
    final targetIds = <String, String>{};
    for (final row in graph.records) {
      var id = row.id;
      if (row.type == 'taskDerivationIntent')
        id = await context.reservedRecordId(
          scope,
          'taskDerivation:${row.raw!['taskId']}',
        );
      if (row.type == 'taskDerivationResolution')
        id = await context.reservedRecordId(
          scope,
          'taskResolution:${row.raw!['taskId']}',
        );
      canonical[row.wireId] = id;
      targetIds[row.wireId] = context
          .address(scope, row.domain, row.type, id)
          .wireId;
    }
    final signing = await context.account.signingKey(),
        content = await target.key('content'),
        finance = await target.key('finance');
    final keys = {'content': content, 'finance': finance};
    final completed = <String, Map<String, dynamic>>{};
    final operations = <String, String>{
      for (final row in graph.records)
        row.wireId: familyOperations[familyByWire[row.wireId]]!,
    };
    final groups = <Map<String, dynamic>>[];
    final pending = graph.records.toList();
    final targetProofs = <Map<String, dynamic>>[],
        targetBindings = <Map<String, dynamic>>[];
    try {
      while (pending.isNotEmpty) {
        var advanced = false;
        for (final row in pending.toList()) {
          final old = inventory[row.wireId]!['body'] as Map;
          final refs = row.deleted
              ? <Map>[]
              : (old['metadata']['references'] as List).cast<Map>();
          if (refs.any((r) => !targetIds.containsKey(r['id'])))
            throw const CryptoAuthorityPending('project_sharing_blocked');
          if (refs.any((r) => !completed.containsKey(r['id']))) continue;
          final op = familyOperations[familyByWire[row.wireId]]!,
              id = canonical[row.wireId]!;
          Map<String, dynamic>? raw = row.deleted || row.raw == null
              ? null
              : Map<String, dynamic>.from(
                  jsonDecode(jsonEncode(row.raw)) as Map,
                );
          if (raw != null) {
            if (raw['scopeId'] == source) raw['scopeId'] = scope;
            if (row.type == 'financeEntry' && raw['accountScopeId'] == source) {
              final accountIds = [
                raw['accountId'],
                raw['ledgerAccountId'],
              ].whereType<String>().toList();
              if (accountIds.isEmpty ||
                  !accountIds.every(
                    (accountId) => graph.records.any(
                      (r) =>
                          r.domain == 'finance' &&
                          const {
                            'financeAccount',
                            'personalFinanceAccount',
                          }.contains(r.type) &&
                          r.id == accountId &&
                          !r.deleted,
                    ),
                  )) {
                throw const CryptoAuthorityPending('project_sharing_blocked');
              }
              raw['accountScopeId'] = scope;
            }
            if (row.type == 'taskDerivationIntent') {
              final task = graph.records.singleWhere(
                (r) => r.type == 'task' && r.id == raw!['taskId'],
              );
              raw['targetCryptoRevision'] = 1;
              raw['targetOperationId'] = operations[task.wireId];
            }
            if (row.type == 'taskDerivationResolution') {
              final task = graph.records.singleWhere(
                (r) => r.type == 'task' && r.id == raw!['taskId'],
              );
              final intent = graph.records.singleWhere(
                (r) =>
                    r.type == 'taskDerivationIntent' &&
                    r.raw?['taskId'] == raw!['taskId'],
              );
              final entry = graph.records.singleWhere(
                (r) => r.domain == 'finance' && r.id == raw!['financeEntryId'],
              );
              raw.addAll({
                'intentId': canonical[intent.wireId],
                'targetCryptoRevision': 1,
                'targetOperationId': operations[task.wireId],
                'taskProofHash': completed[task.wireId]!['recordProofHash'],
                'intentProofHash': completed[intent.wireId]!['recordProofHash'],
                'financeRecordProofHash':
                    completed[entry.wireId]!['recordProofHash'],
              });
            }
            raw = Map<String, dynamic>.from(
              await _retargetBlobs(
                    raw,
                    id,
                    'relocation:${saved['actionId']}:$id',
                    target,
                    producer,
                    saved,
                  )
                  as Map,
            );
          }
          final identity = context
              .address(scope, row.domain, row.type, id)
              .identity;
          final metadata = Map<String, dynamic>.from(old['metadata'] as Map)
            ..remove('migrationOrigin')
            ..remove('inlineDeletion')
            ..remove('schedulingUse');
          metadata['identity'] = identity;
          if (row.domain == 'finance') {
            metadata['uniqueRefs'] = await CryptoBusinessFinance(
              context,
            ).uniqueRefs(scope, row.type, raw, relocationTarget: target);
          }
          metadata['references'] = [
            for (final ref in refs)
              {'scopeId': scope, 'id': targetIds[ref['id']]},
          ]..sort((a, b) => (a['id'] as String).compareTo(b['id'] as String));
          metadata['referenceVersions'] =
              [
                for (final ref in refs)
                  {
                    'scopeId': scope,
                    'domain': completed[ref['id']]!['domain'],
                    'id': targetIds[ref['id']],
                    'revision': 1,
                    'recordProofHash': completed[ref['id']]!['recordProofHash'],
                  },
              ]..sort(
                (a, b) => '${a['scopeId']}/${a['domain']}/${a['id']}'.compareTo(
                  '${b['scopeId']}/${b['domain']}/${b['id']}',
                ),
              );
          if (metadata['notificationState'] is Map)
            metadata['notificationState'] = await context.notificationStateFor(
              scope,
              row.domain,
              id,
              row.type,
              0,
              raw,
            );
          if (row.deleted) {
            metadata['references'] = [];
            metadata['referenceVersions'] = [];
          }
          final blobs = <String>{};
          _collectBlobs(raw, blobs);
          metadata['blobIds'] = blobs.toList()..sort();
          metadata['projectRelocation'] = {
            'version': 2,
            'actionId': saved['actionId'],
            'planHash': saved['planHash'],
            'side': 'target',
          };
          Map<String, dynamic>? payload = raw;
          final bytes = raw == null ? null : CryptoBusinessJson.encode(raw);
          try {
            if (bytes != null && bytes.length > 90000) {
              final d = await CryptoDocumentBlob(context).stage(
                scopeId: scope,
                recordId: id,
                operationId: 'relocation:${saved['actionId']}:$id:payload',
                kind: 'payload:${row.type}',
                plaintext: bytes,
                domain: row.domain,
                relocationTarget: target,
              );
              await producer.uploadBlob(
                actionId: saved['actionId'],
                planHash: saved['planHash'],
                descriptor: d,
              );
              payload = {
                'documentFormat': 1,
                'documentType': 'payload',
                'payloadType': row.type,
                'blob': d,
              };
              metadata['blobIds'] = [...blobs, d['id']]..sort();
            }
          } finally {
            bytes?.fillRange(0, bytes.length, 0);
          }
          final batch = familyBatches[familyByWire[row.wireId]]!;
          final plain = payload == null
              ? null
              : CryptoBusinessJson.encode({
                  'format': 2,
                  'identity': identity,
                  'payload': payload,
                });
          try {
            final proof = context.codec.sealRecord(
              serverId: context.account.directory.session.profile.serverId,
              accountId: context.account.directory.accountId,
              deviceId: context.account.deviceId,
              batchId: batch,
              scopeId: scope,
              id: targetIds[row.wireId]!,
              type: row.type,
              expectedRevision: 0,
              epoch: 1,
              accessRevision: target.head.accessRevision,
              membershipHeadHash: target.head.headHash,
              domain: row.domain,
              contentContract: row.domain == 'finance' ? 3 : 6,
              operationId: op,
              previousRecordHash: cryptoZeroHash,
              deleted: row.deleted,
              plaintext: plain,
              metadata: metadata,
              contentKey: keys[row.domain]!,
              signingKey: signing.key,
            );
            completed[row.wireId] = {
              'recordProofHash': await _hash(proof),
              'domain': row.domain,
              'proof': proof,
              'batchId': batch,
            };
            targetProofs.add(proof);
            targetBindings.add({
              'sourceWireId': row.wireId,
              'targetWireId': targetIds[row.wireId],
            });
          } finally {
            plain?.fillRange(0, plain.length, 0);
          }
          pending.remove(row);
          advanced = true;
        }
        if (!advanced)
          throw const CryptoAuthorityPending(
            'crypto_relocation_reference_cycle',
          );
      }
      // Each proof already binds its batch ID. Grouping the full target DAG
      // into bounded batches is deterministic and does not publish any prefix.
      for (final family in families.keys) {
        final records = <Map<String, dynamic>>[],
            bindings = <Map<String, dynamic>>[];
        for (var i = 0; i < targetProofs.length; i++)
          if (_body(targetProofs[i])['batchId'] == familyBatches[family]) {
            records.add(targetProofs[i]);
            bindings.add(targetBindings[i]);
          }
        final first = _body(records.first), batchId = familyBatches[family]!;
        final commitment = await context.codec.commitBatch(
          serverId: first['serverId'],
          accountId: first['accountId'],
          deviceId: first['deviceId'],
          batchId: batchId,
          records: records,
          signingKey: signing.key,
          projectionToken: (r) async =>
              context.codec.projectionGroupToken(r, keys[r['domain']]!),
        );
        groups.add({
          'batch': {
            'batchId': batchId,
            'records': records,
            'commitment': commitment,
          },
          'bindings': bindings,
        });
      }
      final plan = _body(saved['planProof'] as Map);
      final metadataCanonical = await context.reservedRecordId(
        scope,
        'scopeMetadata',
      );
      final project = graph.records.singleWhere(
        (r) => r.type == 'project' && r.id == scope,
      );
      final snapshot = CryptoFinancePolicySnapshot(
        enabled: true,
        revision: 1,
        requiredContractVersion: 3,
        grants: [
          {'accountId': plan['targetOwnerAccountId'], 'grant': 'write'},
        ],
      );
      final metadataRaw = {
        'scopeId': scope,
        'namespaceVersion': 1,
        'kind': 'project',
        'accessPolicyVersion': 3,
        'parentScopeToken': plan['targetParentScopeToken'],
        'name': project.raw?['name'] ?? project.raw?['title'] ?? '',
        'archived': false,
        'financePolicy': {
          ...snapshot.header,
          'policyHash': await snapshot.hash(),
          'grantCount': 1,
        },
      };
      final address = context.address(
            scope,
            'content',
            'scopeMetadata',
            metadataCanonical,
          ),
          batch = _id();
      final plain = CryptoBusinessJson.encode({
        'format': 2,
        'identity': address.identity,
        'payload': metadataRaw,
      });
      try {
        final proof = context.codec.sealRecord(
          serverId: plan['serverId'],
          accountId: plan['accountId'],
          deviceId: plan['deviceId'],
          batchId: batch,
          scopeId: scope,
          id: address.wireId,
          type: 'scopeMetadata',
          expectedRevision: 0,
          epoch: 1,
          accessRevision: target.head.accessRevision,
          membershipHeadHash: target.head.headHash,
          domain: 'content',
          contentContract: 6,
          operationId: _id(),
          previousRecordHash: cryptoZeroHash,
          deleted: false,
          plaintext: plain,
          metadata: {
            'identity': address.identity,
            'references': [],
            'referenceVersions': [],
            'uniqueRefs': [],
            'blobIds': [],
            'projectRelocation': {
              'version': 2,
              'actionId': saved['actionId'],
              'planHash': saved['planHash'],
              'side': 'target',
            },
          },
          contentKey: content,
          signingKey: signing.key,
        );
        groups.add({
          'batch': {
            'batchId': batch,
            'records': [proof],
            'commitment': await context.codec.commitBatch(
              serverId: plan['serverId'],
              accountId: plan['accountId'],
              deviceId: plan['deviceId'],
              batchId: batch,
              records: [proof],
              signingKey: signing.key,
              projectionToken: (r) async =>
                  context.codec.projectionGroupToken(r, content),
            ),
          },
          'bindings': <Map<String, dynamic>>[],
        });
      } finally {
        plain.fillRange(0, plain.length, 0);
      }
      final parent = inventory.values.singleWhere(
        (v) => v['body']['type'] == 'scopeMetadata',
      );
      final parentBody = parent['body'] as Map,
          parentRaw = Map<String, dynamic>.from(parent['raw'] as Map);
      final beforeTopology = Map<String, dynamic>.from(
        parentRaw['financeTopology'] as Map,
      );
      if (parent['row']['record_proof_hash'] !=
              plan['parentMetadataProofHash'] ||
          beforeTopology['generation'] != plan['parentTopologyGeneration'])
        throw const CryptoAuthorityPending('project_sharing_preview_changed');
      final token = await CryptoFinanceTopology.childToken(
        plan['serverId'],
        source,
        scope,
      );
      if ((beforeTopology['childTokens'] as List).contains(token))
        throw const FormatException('crypto_relocation_topology_duplicate');
      parentRaw['financeTopology'] = await CryptoFinanceTopology.create(
        serverId: plan['serverId'],
        scopeId: source,
        childTokens: [
          ...(beforeTopology['childTokens'] as List).cast<String>(),
          token,
        ],
        previous: beforeTopology,
      );
      final parentWrite = await context.access.writeContext(
            source,
            'content',
            online: true,
          ),
          parentBatch = _id();
      final parentPlain = CryptoBusinessJson.encode({
        'format': 2,
        'identity': parentBody['metadata']['identity'],
        'payload': parentRaw,
      });
      try {
        final parentProof = context.codec.sealRecord(
          serverId: plan['serverId'],
          accountId: plan['accountId'],
          deviceId: plan['deviceId'],
          batchId: parentBatch,
          scopeId: source,
          id: parentBody['id'],
          type: 'scopeMetadata',
          expectedRevision: parentBody['expectedRevision'] + 1,
          epoch: parentWrite.epoch,
          accessRevision: parentWrite.accessRevision,
          membershipHeadHash: parentWrite.headHash,
          domain: 'content',
          contentContract: parentWrite.contentContract,
          operationId: _id(),
          previousRecordHash: plan['parentMetadataProofHash'],
          deleted: false,
          plaintext: parentPlain,
          metadata: {
            'identity': parentBody['metadata']['identity'],
            'references': [],
            'referenceVersions': [],
            'uniqueRefs': [],
            'blobIds': [],
            'projectRelocation': {
              'version': 2,
              'actionId': saved['actionId'],
              'planHash': saved['planHash'],
              'side': 'source',
            },
          },
          contentKey: parentWrite.key.key,
          signingKey: signing.key,
        );
        groups.add({
          'batch': {
            'batchId': parentBatch,
            'records': [parentProof],
            'commitment': await context.codec.commitBatch(
              serverId: plan['serverId'],
              accountId: plan['accountId'],
              deviceId: plan['deviceId'],
              batchId: parentBatch,
              records: [parentProof],
              signingKey: signing.key,
              projectionToken: (r) async =>
                  context.codec.projectionGroupToken(r, parentWrite.key.key),
            ),
          },
          'bindings': <Map<String, dynamic>>[],
        });
      } finally {
        parentPlain.fillRange(0, parentPlain.length, 0);
        parentWrite.key.release();
      }
      for (final family in families.values) {
        final batch = _id(),
            sourceOperation = _id(),
            proofs = <Map<String, dynamic>>[],
            bindings = <Map<String, dynamic>>[],
            writes = <String, CryptoWriteContext>{};
        try {
          for (final row in family) {
            final write = writes[row.domain] ??= await context.access
                .writeContext(source, row.domain, online: true);
            final metadata = await context.businessMetadata(
              scopeId: source,
              domain: row.domain,
              type: row.type,
              canonicalId: row.id,
              expectedRevision: row.revision,
              rawPayload: null,
            );
            if (metadata['notificationState'] is Map)
              metadata['notificationState']['groupTargetId'] = null;
            metadata['projectRelocation'] = {
              'version': 2,
              'actionId': saved['actionId'],
              'planHash': saved['planHash'],
              'side': 'source',
            };
            proofs.add(
              context.codec.sealRecord(
                serverId: plan['serverId'],
                accountId: plan['accountId'],
                deviceId: plan['deviceId'],
                batchId: batch,
                scopeId: source,
                id: row.wireId,
                type: row.type,
                expectedRevision: row.revision,
                epoch: write.epoch,
                accessRevision: write.accessRevision,
                membershipHeadHash: write.headHash,
                domain: row.domain,
                contentContract: write.contentContract,
                operationId: sourceOperation,
                previousRecordHash: row.proofHash,
                deleted: true,
                plaintext: null,
                metadata: metadata,
                contentKey: write.key.key,
                signingKey: signing.key,
              ),
            );
            bindings.add({
              'sourceWireId': row.wireId,
              'targetWireId': row.wireId,
            });
          }
          final commitment = await context.codec.commitBatch(
            serverId: plan['serverId'],
            accountId: plan['accountId'],
            deviceId: plan['deviceId'],
            batchId: batch,
            records: proofs,
            signingKey: signing.key,
            projectionToken: (r) async => context.codec.projectionGroupToken(
              r,
              writes[r['domain']]!.key.key,
            ),
          );
          groups.add({
            'batch': {
              'batchId': batch,
              'records': proofs,
              'commitment': commitment,
            },
            'bindings': <Map<String, dynamic>>[],
          });
        } finally {
          for (final write in writes.values) {
            write.key.release();
          }
        }
      }
      return groups;
    } finally {
      content.dispose();
      finance.dispose();
      signing.release();
    }
  }

  Future<Map<String, dynamic>> _audit(
    Map<String, dynamic> saved,
    List<Map<String, dynamic>> entries,
    PreparedProjectRelocationTarget target,
    CryptoProjectRelocationTarget producer,
  ) async {
    final key = 'projectRelocation:${saved['requestId']}',
        scope = target.head.scopeId;
    if (saved['auditSnapshots'] == null) {
      final own = await context.account.directory.requireFresh(),
          snapshots = <Map<String, dynamic>>[];
      final finance = await target.key('finance');
      try {
        final mapping = <String, Map<String, dynamic>>{};
        for (final group in saved['groups'] as List) {
          for (final binding in (group['bindings'] as List).cast<Map>()) {
            final proof = (group['batch']['records'] as List)
                .cast<Map>()
                .singleWhere((p) => _body(p)['id'] == binding['targetWireId']);
            final body = _body(proof);
            if (body['metadata']['projectRelocation']['side'] == 'target')
              mapping[binding['sourceWireId']] = body;
          }
        }
        for (final entry in entries) {
          final body = mapping[entry['sourceWireId']];
          if (body == null)
            throw const FormatException('crypto_relocation_audit_mapping');
          final sourceHash = entry['sourceEvidenceHash'] as String;
          final token = await cryptoSha256([
            ...utf8.encode('JivieProjectRelocationAuditSource/v2\n'),
            ...CryptoJson.encode({
              'version': 2,
              'serverId': own.serverId,
              'actionId': saved['actionId'],
              'scopeId': scope,
              'sourceEvidenceHash': sourceHash,
            }),
          ]);
          final value = Map<String, dynamic>.from(entry)
            ..remove('sourceWireId');
          value['scopeId'] = scope;
          if (value['typedRow'] is Map) {
            value['typedRow'] = {
              ...Map<String, dynamic>.from(value['typedRow'] as Map),
              'scope_id': scope,
            };
          }
          final bytes = CryptoBusinessJson.encode({
            'version': 2,
            'sourceEvidenceHash': sourceHash,
            'entry': value,
          });
          Map<String, dynamic> plain;
          final blobIds = <String>[];
          try {
            if (bytes.length > 90000) {
              final d = await CryptoDocumentBlob(context).stage(
                scopeId: scope,
                recordId: body['metadata']['identity']['canonicalId'],
                operationId: 'relocation:${saved['actionId']}:audit:$token',
                kind: 'relocatedAudit',
                plaintext: bytes,
                domain: 'finance',
                relocationTarget: target,
              );
              await producer.uploadBlob(
                actionId: saved['actionId'],
                planHash: saved['planHash'],
                descriptor: d,
              );
              blobIds.add(d['id']);
              plain = {'version': 2, 'entryBlob': d};
            } else {
              plain = {
                'version': 2,
                'sourceEvidenceHash': sourceHash,
                'entry': value,
              };
            }
            final snapshot = <String, dynamic>{
              'version': 2,
              'operation': 'crypto2.projectRelocation.auditSnapshot',
              'serverId': own.serverId,
              'scopeId': scope,
              'actionId': saved['actionId'],
              'planHash': saved['planHash'],
              'sourceToken': token,
              'recordId': body['id'],
              'epoch': target.head.epoch,
              'membershipHeadHash': target.head.headHash,
              'accessRevision': target.head.accessRevision,
              'blobIds': blobIds,
              'accountId': own.accountId,
              'deviceId': context.account.deviceId,
              'authorDirectoryHeadHash': own.headHash,
            };
            final content = CryptoBusinessJson.encode(plain);
            try {
              snapshot['envelopeBase64'] = base64Encode(
                CryptoJson.encode(
                  context.codec.crypto.encrypt(
                    plaintext: content,
                    key: finance,
                    context: {'purpose': 'projectRelocationAudit', ...snapshot},
                  ),
                ),
              );
            } finally {
              content.fillRange(0, content.length, 0);
            }
            snapshots.add({
              'sourceEvidenceHash': sourceHash,
              'authorization': await _sign(
                snapshot,
                'JivieProjectRelocationAudit/v2\n',
              ),
            });
          } finally {
            bytes.fillRange(0, bytes.length, 0);
          }
        }
      } finally {
        finance.dispose();
      }
      saved['auditSnapshots'] = snapshots;
      await _save(saved['scopeId'], key, saved);
    }
    final proofs = (saved['auditSnapshots'] as List).cast<Map>();
    for (var offset = 0; offset < proofs.length; offset += 32) {
      await _send(
        '$key:audit:$offset',
        'crypto2.projectRelocation.auditStage',
        {
          'actionId': saved['actionId'],
          'planHash': saved['planHash'],
          'snapshots': proofs.skip(offset).take(32).toList(),
        },
      );
    }
    final hashes =
        await Future.wait(proofs.map((p) => _hash(p['authorization'])))
          ..sort();
    return {
      'count': hashes.length,
      'root': await CryptoProjectRelocationCodec.digestRoot('audit', hashes),
    };
  }

  Future<Map<String, dynamic>> _notifications(
    Map<String, dynamic> saved,
    String key,
  ) async {
    if (saved['notificationProofs'] == null) {
      String? after;
      final proofs = <Map<String, dynamic>>[];
      final own = await context.account.directory.requireFresh();
      while (true) {
        final page = await _send(
          '$key:notificationCandidates:${after ?? 'first'}',
          'crypto2.projectRelocation.notificationCandidates',
          {
            'actionId': saved['actionId'],
            'planHash': saved['planHash'],
            'limit': 32,
            if (after != null) 'afterRouteId': after,
          },
        );
        final rows = page['routes'];
        if (rows is! List || rows.length > 32)
          throw const FormatException('crypto_relocation_notification_page');
        for (final raw in rows) {
          final value = Map<String, dynamic>.from(raw['routing'] as Map);
          if (value['actionId'] != saved['actionId'] ||
              value['planHash'] != saved['planHash'] ||
              value['targetScopeId'] != saved['projectId'] ||
              after != null && after.compareTo(value['routeId']) >= 0 ||
              proofs.length >= 10000)
            throw const FormatException(
              'crypto_relocation_notification_binding',
            );
          after = value['routeId'];
          proofs.add(
            await _sign({
              ...value,
              'accountId': own.accountId,
              'deviceId': context.account.deviceId,
              'authorDirectoryHeadHash': own.headHash,
            }, 'JivieProjectRelocationNotification/v2\n'),
          );
        }
        if (page['hasMore'] == false) break;
        if (page['hasMore'] != true ||
            rows.isEmpty ||
            page['nextAfterId'] != after)
          throw const FormatException('crypto_relocation_notification_cursor');
      }
      saved['notificationProofs'] = proofs;
      await _save(saved['scopeId'], key, saved);
    }
    final proofs = (saved['notificationProofs'] as List).cast<Map>();
    for (var offset = 0; offset < proofs.length; offset += 32) {
      await _send(
        '$key:notificationStage:$offset',
        'crypto2.projectRelocation.notificationStage',
        {
          'actionId': saved['actionId'],
          'planHash': saved['planHash'],
          'authorizations': proofs.skip(offset).take(32).toList(),
        },
      );
    }
    final hashes = await Future.wait(proofs.map(_hash))
      ..sort();
    return {
      'count': hashes.length,
      'root': await CryptoProjectRelocationCodec.digestRoot(
        'notifications',
        hashes,
      ),
    };
  }

  Future<Map<String, dynamic>> _publication(
    Map<String, dynamic> saved,
    PreparedProjectRelocationTarget target,
    Map audit,
    Map notifications,
  ) async {
    final own = await context.account.directory.requireFresh(),
        plan = _body(saved['planProof'] as Map),
        request = _id();
    final source = await context.access.currentHead(
      saved['scopeId'],
      online: true,
    );
    final sourceWire = await context.account.directory.call(
      'crypto2.scope.headGet',
      {'scopeId': source.scopeId, 'headHash': source.headHash},
    );
    final sourceActivation = sourceWire['activationAuthorization'];
    if (sourceActivation is! Map)
      throw const CryptoAuthorityPending('scope_activation_pending');
    final descriptors = <String, List<Map<String, dynamic>>>{
          'source': [],
          'target': [],
        },
        batches = <String, Set<String>>{'source': {}, 'target': {}};
    final original = <String, Map>{};
    final proofRows = await context.database.rows(
      'SELECT payload FROM crypto_membership_intents WHERE partition=? AND scope_id=? AND intent_id=?',
      [
        context.partition,
        saved['scopeId'],
        'projectRelocation:${saved['requestId']}',
      ],
    );
    if (proofRows.length != 1)
      throw const FormatException('crypto_relocation_private_plan');
    for (final group in saved['groups'] as List) {
      final batchHash = await _hash(group['batch']['commitment']);
      for (final proof in group['batch']['records'] as List) {
        final body = _body(proof as Map),
            side = body['metadata']['projectRelocation']['side'] as String;
        var logical = 1;
        if (side == 'source') {
          final row = await context.wireRecord(
            body['scopeId'],
            body['domain'],
            body['id'],
          );
          if (row == null)
            throw const CryptoAuthorityPending(
              'project_sharing_preview_changed',
            );
          logical = body['type'] == 'scopeMetadata'
              ? body['expectedRevision'] + 1
              : ((jsonDecode(row['projection'] as String) as Map)['revision']
                        as int) +
                    1;
          original[body['id']] = row;
        } else if (body['type'] != 'scopeMetadata') {
          final binding = (group['bindings'] as List).cast<Map>().singleWhere(
            (b) => b['targetWireId'] == body['id'],
          );
          final sourceRow = await context.wireRecord(
            saved['scopeId'],
            body['domain'],
            binding['sourceWireId'],
          );
          if (sourceRow == null)
            throw const CryptoAuthorityPending(
              'project_sharing_preview_changed',
            );
          logical = _logicalRevision(sourceRow);
        }
        descriptors[side]!.add({
          'id': body['id'],
          'type': body['type'],
          'domain': body['domain'],
          'recordProofHash': await _hash(proof),
          'logicalRevision': logical,
        });
        batches[side]!.add(batchHash);
      }
    }
    final publications = <String, dynamic>{};
    for (final side in ['source', 'target']) {
      final head = side == 'source' ? source : target.head,
          scope = head.scopeId,
          other = side == 'source' ? target.head.scopeId : source.scopeId;
      final leafHashes =
          await Future.wait(
              descriptors[side]!.map(CryptoProjectRelocationCodec.recordLeaf),
            )
            ..sort();
      final batchHashes = batches[side]!.toList()..sort();
      final body = {
        'version': 2,
        'serverId': own.serverId,
        'scopeId': scope,
        'side': side,
        'actionId': saved['actionId'],
        'planHash': saved['planHash'],
        'requestId': request,
        'accountId': own.accountId,
        'deviceId': context.account.deviceId,
        'authorDirectoryHeadHash': own.headHash,
        'membershipHeadHash': head.headHash,
        'proposalProofHash': await _hash(head.authorization),
        'activationProofHash': await _hash(
          side == 'source' ? sourceActivation : target.activation,
        ),
        'accessRevision': head.accessRevision,
        'lifecycleHash': side == 'source'
            ? plan['sourceLifecycleHash']
            : cryptoZeroHash,
        'counterpartToken': await cryptoSha256([
          ...utf8.encode('JivieProjectRelocationCounterpart/v2\n'),
          ...CryptoJson.encode({
            'version': 2,
            'serverId': own.serverId,
            'actionId': saved['actionId'],
            'scopeId': scope,
            'counterpartScopeId': other,
          }),
        ]),
        'recordRoot': await CryptoProjectRelocationCodec.digestRoot(
          'records',
          leafHashes,
        ),
        'recordCount': leafHashes.length,
        'batchRoot': await CryptoProjectRelocationCodec.digestRoot(
          'batches',
          batchHashes,
        ),
        'batchCount': batchHashes.length,
        'auditRoot': side == 'source'
            ? await CryptoProjectRelocationCodec.digestRoot('audit', [])
            : audit['root'],
        'auditCount': side == 'source' ? 0 : audit['count'],
        'notificationRoot': notifications['root'],
        'notificationCount': notifications['count'],
      };
      CryptoProjectRelocationCodec.publication(body);
      publications[side] = await _sign(
        body,
        CryptoProjectRelocationCodec.publicationDomain,
      );
    }
    final root = await CryptoProjectRelocationCodec.publicationRoot(
      await _hash(publications['source']),
      await _hash(publications['target']),
    );
    final event = await context.account.prepareProjectRelocationEvent(
      requestId: request,
      actionId: saved['actionId'],
      publicationRoot: root,
    );
    return {
      'actionId': saved['actionId'],
      'planHash': saved['planHash'],
      'publications': publications,
      'accountEventProof': event.authorization,
    };
  }

  Future<Map<String, dynamic>> _finish(
    Map<String, dynamic> saved,
    Map<String, dynamic> result,
  ) async {
    final commit = saved['commit'] as Map,
        event = _body(commit['accountEventProof'] as Map),
        p = event['payload'] as Map;
    final expected = await cryptoSha256([
      ...utf8.encode(cryptoDirectoryLogDomain),
      ...CryptoJson.encode({
        'serverId': event['serverId'],
        'accountId': event['accountId'],
        'generation': p['expectedGeneration'] + 1,
        'previousHeadHash': p['previousHeadHash'],
        'commandHash': await cryptoSha256(
          cryptoBase64(commit['accountEventProof']['commandBase64']),
        ),
        'signatureBase64': commit['accountEventProof']['signatureBase64'],
      }),
    ]);
    if (result['moved'] != true ||
        result['actionId'] != saved['actionId'] ||
        result['planHash'] != saved['planHash'] ||
        result['projectId'] != saved['projectId'] ||
        result['targetScopeId'] != saved['projectId'] ||
        result['publicationRoot'] != p['publicationRoot'] ||
        result['eventHeadHash'] != expected)
      throw const FormatException('crypto_relocation_outcome_substitution');
    final own = await context.account.directory.requireFresh();
    if (!own.includesAnchor(p['expectedGeneration'] + 1, expected))
      throw const CryptoAuthorityPending('crypto_relocation_event_pending');
    context.access.invalidateAuthorityOperation();
    // Normal readers verify the exact final publications. Retrying this action
    // never republishes data or rolls back a legitimate later successor.
    await context.access.currentHead(saved['projectId'], online: true);
    await context.access.hydrateScopeKeys(saved['projectId']);
    await context.pullVerified(saved['projectId'], 'content');
    await context.pullVerified(saved['projectId'], 'finance');
    final scopes = await context.scopes();
    final scope = (scopes['scopes'] as List).cast<Map>().singleWhere(
      (s) => s['id'] == saved['projectId'],
    );
    final preview = saved['preview'] as Map;
    return {
      'scope': Map<String, dynamic>.from(scope),
      'movedRecordIds': preview['movedRecordIds'],
      'movedFinanceRecordIds': preview['movedFinanceRecordIds'],
      'movedReminderIds': <String>[],
    };
  }
}
