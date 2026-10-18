import 'dart:convert';
import 'dart:typed_data';

import '../collaboration_transport.dart';

import 'account_directory_v2.dart';
import 'crypto_business_json.dart';
import 'crypto_business_router.dart';
import 'crypto_inline_deletion_codec.dart';
import 'crypto_json.dart';
import 'crypto_migration_record_source.dart';
import 'crypto_record_address.dart';
import 'crypto_sync_repository.dart';
import 'session_crypto_access.dart';

/// One selected inline project, with all staged batches published together.
/// No staged record is submitted to the ordinary records.batch endpoint.
class CryptoBusinessInlineDeletion {
  CryptoBusinessInlineDeletion(
    this.context, {
    this.inventoryMaxBytes = maxInventoryBytes,
  }) {
    if (inventoryMaxBytes < 1 || inventoryMaxBytes > maxInventoryBytes) {
      throw const FormatException('crypto_inline_delete_inventory_budget');
    }
  }
  final CryptoBusinessSession context;
  // Expanded raw data and retained proof/projection rows, not merely item count.
  // Larger installations remain intact and report a capacity blocker.
  static const maxInventoryBytes = 32 * 1024 * 1024;
  final int inventoryMaxBytes;
  static const operations = {
    'crypto2.inlineDelete.prepare',
    'crypto2.inlineDelete.stage',
    'crypto2.inlineDelete.commit',
    'crypto2.inlineDelete.cancel',
  };
  static const financeTypes = {
    'financeEntry',
    'personalFinanceEntry',
    'financeAccount',
    'personalFinanceAccount',
    'financeTransfer',
    'financeRecurrenceRule',
  };
  Map<String, dynamic> _body(Map proof) => Map<String, dynamic>.from(
    CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map,
  );
  String _newId() => context.account.directory.reducer.crypto.randomId();
  Future<String> _hash(Object? value) => cryptoSha256(CryptoJson.encode(value));

  /// The queue still reconciles an old receipt before invoking this current
  /// issuance guard. A final publication never grants permission to reissue.
  static Future<void> verifyDelivery(
    SessionCryptoAccess access,
    Map<String, dynamic> command,
  ) async {
    final own = await access.account.directory.requireFresh();
    own.activeDevice(access.account.deviceId);
    final p = command['payload'] as Map;
    if (command['operation'] == 'crypto2.inlineDelete.cancel') return;
    Map c = p;
    if (command['operation'] == 'crypto2.inlineDelete.stage') {
      final records = (p['batch'] as Map)['records'] as List;
      if (records.isEmpty || records.length > 32) {
        throw const FormatException('crypto_inline_delete_batch');
      }
      for (final proof in records) {
        final body =
            CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map;
        final tag = (body['metadata'] as Map)['inlineDeletion'];
        if (body['deleted'] != true ||
            tag is! Map ||
            tag['actionId'] != p['actionId'] ||
            tag['planHash'] != p['planHash']) {
          throw const FormatException('crypto_inline_delete_stage_binding');
        }
        final write = await access.writeContext(
          body['scopeId'],
          body['domain'],
          online: true,
        );
        try {
          if (body['membershipHeadHash'] != write.headHash ||
              body['epoch'] != write.epoch ||
              body['accessRevision'] != write.accessRevision) {
            throw const CryptoAuthorityPending(
              'scope_deletion_preview_changed',
            );
          }
        } finally {
          write.key.release();
        }
      }
      return;
    }
    if (command['operation'] == 'crypto2.inlineDelete.commit') {
      c =
          CryptoJson.decode(
                cryptoBase64((p['certificateProof'] as Map)['commandBase64']),
              )
              as Map;
      CryptoInlineDeletionCodec.certificate(c);
      if (c['requestId'] != command['requestId'] ||
          c['accountId'] != own.accountId ||
          c['deviceId'] != access.account.deviceId ||
          c['planHash'] != p['planHash'] ||
          c['actionId'] != p['actionId']) {
        throw const FormatException('crypto_inline_delete_commit_binding');
      }
    }
    final write = await access.writeContext(
      c['scopeId'],
      'content',
      online: true,
    );
    try {
      if (c['membershipHeadHash'] != write.headHash ||
          (c['expectedAccessRevision'] ?? c['accessRevision']) !=
              write.accessRevision ||
          c['authorDirectoryHeadHash'] != own.headHash ||
          c['lifecycleHash'] !=
              await access.verifiedLifecycleHash(c['scopeId'])) {
        throw const CryptoAuthorityPending('scope_deletion_preview_changed');
      }
    } finally {
      write.key.release();
    }
  }

  Future<Map<String, dynamic>> _send(
    String key,
    String operation,
    Map<String, dynamic> payload, {
    String? requestId,
  }) async {
    final request = await context.queue.enqueueCommand(
      actionKey: key,
      requestId: requestId,
      operation: operation,
      payload: payload,
    );
    await context.queue.resumeUnresolved(requestIds: {request});
    final stored = await context.queue.store.outgoing(request);
    if (stored?['state'] == 'rejected') {
      final receipt = jsonDecode(stored!['response'] as String) as Map;
      final response = receipt['response'] as Map;
      throw CollaborationApiException(
        response['errorCode'] as String,
        details: response['details'] is Map
            ? Map<String, dynamic>.from(response['details'] as Map)
            : response['details'] is List &&
                  (response['details'] as List).isEmpty
            ? const <String, dynamic>{}
            : throw const FormatException(
                'crypto_inline_delete_receipt_details',
              ),
      );
    }
    return context.queue.commandResult(request);
  }

  Future<Map<String, dynamic>> dispatch(
    String operation,
    Map<String, Object?> params,
  ) async {
    final scope = params['scopeId'], project = params['projectId'];
    if (!isCryptoCanonicalUuid(scope) || !isCryptoCanonicalUuid(project)) {
      throw const FormatException('crypto_inline_delete_target');
    }
    final wire = context
        .address(scope as String, 'content', 'project', project as String)
        .wireId;
    if (operation == 'scopes.deletionPreview') {
      final own = await context.access.currentHead(scope, online: true);
      // Old signed proofs without project edges cannot establish absence of a
      // hidden finance dependency. Do not disclose counts/IDs in that case.
      if (own.member(context.account.directory.accountId)['financeRole'] ==
          'none') {
        return _blocked(scope, project, 'finance_write_required');
      }
      try {
        await _inventory(scope);
      } on CryptoAuthorityPending catch (error) {
        if (error.reason != 'crypto_inline_delete_inventory_capacity' &&
            error.reason != 'crypto_inline_delete_inventory_limit')
          rethrow;
        return _blocked(scope, project, error.reason);
      }
      if (!await _reconcileProjectEdges(scope, project)) {
        return _blocked(scope, project, 'finance_write_required');
      }
      final page = await context.account.directory.call(
        'crypto2.inlineDelete.preview',
        {'scopeId': scope, 'projectId': project, 'projectWireId': wire},
      );
      if (page['canDelete'] == true) {
        final expected = await _selected(scope, project);
        if (await CryptoInlineDeletionCodec.graphRoot(expected) !=
                page['graphRoot'] ||
            expected.length != page['graphCount']) {
          throw const CryptoAuthorityPending(
            'crypto_inline_delete_metadata_reconciliation_required',
          );
        }
      }
      return {
        ...page,
        'previewHash': await _hash(page),
        'name': await _name(scope, project),
        'scopeNames': <String>[],
        'cryptoDeletionVersion': 2,
      };
    }
    if (operation != 'scopes.delete' ||
        !isCryptoCanonicalUuid(params['requestId'])) {
      throw const FormatException('crypto_inline_delete_request');
    }
    final request = params['requestId'] as String,
        key = 'inlineDeletion:$request';
    final rows = await context.database.rows(
      'SELECT payload FROM crypto_export_drafts WHERE partition=? AND scope_id=? AND action_id=?',
      [context.partition, scope, key],
    );
    late Map<String, dynamic> saved;
    if (rows.isEmpty) {
      final preview = await dispatch('scopes.deletionPreview', params);
      if (preview['canDelete'] != true ||
          preview['previewHash'] != params['previewHash']) {
        throw const CryptoAuthorityPending('scope_deletion_preview_changed');
      }
      final own = await context.account.directory.requireFresh();
      saved = {
        'scopeId': scope,
        'projectId': project,
        'previewHash': params['previewHash'],
        'actionId': _newId(),
        'prepareRequestId': _newId(),
        'prepare': {
          'scopeId': scope,
          'projectId': project,
          'projectWireId': wire,
          'membershipHeadHash': preview['membershipHeadHash'],
          'expectedAccessRevision': preview['expectedAccessRevision'],
          'lifecycleHash': preview['lifecycleHash'],
          'authorDirectoryHeadHash': own.headHash,
          'graphRoot': preview['graphRoot'],
          'graphCount': preview['graphCount'],
        },
        'groups': <Map<String, dynamic>>[],
      };
      (saved['prepare'] as Map)['actionId'] = saved['actionId'];
      await _save(scope, key, saved, insert: true);
    } else {
      saved = Map<String, dynamic>.from(
        jsonDecode(rows.single['payload'] as String) as Map,
      );
      if (saved['scopeId'] != scope ||
          saved['projectId'] != project ||
          saved['previewHash'] != params['previewHash']) {
        throw const FormatException('crypto_inline_delete_immutable_request');
      }
    }
    // Always settle the exact final request first, even after source advances.
    if (saved['commit'] is Map) {
      final result = await _send(
        '$key:commit',
        'crypto2.inlineDelete.commit',
        Map<String, dynamic>.from(saved['commit'] as Map),
        requestId: request,
      );
      return _finish(saved, result);
    }
    final prepared = await _send(
      '$key:prepare',
      'crypto2.inlineDelete.prepare',
      Map<String, dynamic>.from(saved['prepare'] as Map),
      requestId: saved['prepareRequestId'],
    );
    if (prepared['actionId'] != saved['actionId'] ||
        prepared['graphRoot'] != saved['prepare']['graphRoot'] ||
        prepared['graphCount'] != saved['prepare']['graphCount']) {
      throw const FormatException('crypto_inline_delete_prepare_substitution');
    }
    if (saved['planHash'] != null &&
        saved['planHash'] != prepared['planHash']) {
      throw const FormatException('crypto_inline_delete_immutable_plan');
    }
    saved['planHash'] = prepared['planHash'];
    await _save(scope, key, saved);
    final leaves = await _leaves(saved);
    if ((saved['groups'] as List).isEmpty) {
      final selected = await _selected(scope, project);
      if (CryptoBusinessJson.canonical(selected) !=
          CryptoBusinessJson.canonical(leaves)) {
        throw const CryptoAuthorityPending(
          'crypto_inline_delete_source_changed',
        );
      }
      saved['groups'] = await _seal(saved, leaves);
      await _save(scope, key, saved);
    }
    for (var i = 0; i < (saved['groups'] as List).length; i++) {
      await _send('$key:stage:$i', 'crypto2.inlineDelete.stage', {
        'actionId': saved['actionId'],
        'planHash': saved['planHash'],
        'batch': saved['groups'][i],
      });
    }
    final own = await context.account.directory.requireFresh();
    final descriptors = <Map<String, dynamic>>[], batches = <String>[];
    for (final raw in saved['groups'] as List) {
      final g = Map<String, dynamic>.from(raw as Map),
          bh = await context.codec.digest(
            Map<String, dynamic>.from(g['commitment'] as Map),
          );
      batches.add(bh);
      for (final proof in g['records'] as List) {
        final b = _body(proof as Map);
        descriptors.add({
          'id': b['id'],
          'domain': b['domain'],
          'type': b['type'],
          'expectedRevision': b['expectedRevision'],
          'previousRecordHash': b['previousRecordHash'],
          'recordProofHash': await context.codec.digest(
            Map<String, dynamic>.from(proof),
          ),
          'batchCommitmentHash': bh,
        });
      }
    }
    descriptors.sort((a, b) => (a['id'] as String).compareTo(b['id']));
    batches.sort();
    final p = saved['prepare'] as Map;
    final certificate = <String, dynamic>{
      'version': 2,
      'serverId': own.serverId,
      'scopeId': scope,
      'projectId': project,
      'projectWireId': wire,
      'actionId': saved['actionId'],
      'planHash': saved['planHash'],
      'requestId': request,
      'membershipHeadHash': p['membershipHeadHash'],
      'accessRevision': p['expectedAccessRevision'],
      'lifecycleHash': p['lifecycleHash'],
      'graphRoot': p['graphRoot'],
      'graphCount': p['graphCount'],
      'tombstoneRoot': await CryptoInlineDeletionCodec.tombstoneRoot(
        descriptors,
      ),
      'tombstoneCount': descriptors.length,
      'batchRoot': await CryptoInlineDeletionCodec.batchRoot(batches),
      'batchCount': batches.length,
      'accountId': own.accountId,
      'deviceId': context.account.deviceId,
      'authorDirectoryHeadHash': own.headHash,
    };
    CryptoInlineDeletionCodec.certificate(certificate);
    final signing = await context.account.signingKey();
    try {
      final proof = context.account.directory.reducer.crypto.signDomain(
        certificate,
        signing.key,
        CryptoInlineDeletionCodec.domain,
      );
      final event = await context.account.prepareScopeDeletionEvent(
        requestId: request,
        scopeToken: await CryptoInlineDeletionCodec.token(certificate),
        certificateHash: await _hash(proof),
      );
      saved['commit'] = {
        'actionId': saved['actionId'],
        'planHash': saved['planHash'],
        'certificateProof': proof,
        'accountEventProof': event.authorization,
      };
      await _save(scope, key, saved);
    } finally {
      signing.release();
    }
    final result = await _send(
      '$key:commit',
      'crypto2.inlineDelete.commit',
      Map<String, dynamic>.from(saved['commit'] as Map),
      requestId: request,
    );
    return _finish(saved, result);
  }

  Map<String, dynamic> _blocked(String scope, String project, String code) => {
    'scopeId': scope,
    'projectId': project,
    'canDelete': false,
    'incomplete': true,
    'previewHash': '0' * 64,
    'name': '',
    'scopeNames': <String>[],
    'counts': {
      for (final k in [
        'spaces',
        'projects',
        'tasks',
        'events',
        'ideas',
        'photos',
        'tables',
        'attachments',
        'finance',
        'other',
      ])
        k: 0,
    },
    'blockers': [
      {'code': code},
    ],
  };
  Future<String> _name(String scope, String project) async {
    final row = await context.record(
      scope,
      'content',
      project,
      type: 'project',
    );
    if (row == null) return '';
    return (jsonDecode(row['projection'] as String) as Map)['title']
            as String? ??
        '';
  }

  Future<void> _save(
    String scope,
    String key,
    Map saved, {
    bool insert = false,
  }) => context.database.execute(
    insert
        ? 'INSERT INTO crypto_export_drafts VALUES(?,?,?,?)'
        : 'UPDATE crypto_export_drafts SET payload=? WHERE partition=? AND scope_id=? AND action_id=?',
    insert
        ? [context.partition, scope, key, jsonEncode(saved)]
        : [jsonEncode(saved), context.partition, scope, key],
  );
  Future<List<Map<String, dynamic>>> _leaves(Map saved) async {
    final result = <Map<String, dynamic>>[];
    String? after;
    while (true) {
      final page = await context.account.directory
          .call('crypto2.inlineDelete.graph', {
            'actionId': saved['actionId'],
            'limit': 32,
            if (after != null) 'afterId': after,
          });
      if (page['planHash'] != saved['planHash'] ||
          page['graphRoot'] != saved['prepare']['graphRoot'] ||
          page['graphCount'] != saved['prepare']['graphCount'] ||
          page['leaves'] is! List ||
          (page['leaves'] as List).length > 32) {
        throw const FormatException('crypto_inline_delete_graph_substitution');
      }
      for (final raw in page['leaves'] as List) {
        final d = Map<String, dynamic>.from(raw as Map);
        CryptoInlineDeletionCodec.graphDescriptor(d);
        if (result.length >= CryptoInlineDeletionCodec.maxRecords ||
            after != null && after.compareTo(d['id']) >= 0) {
          throw const FormatException('crypto_inline_delete_graph_order');
        }
        result.add(d);
        after = d['id'];
      }
      if (page['hasMore'] == false) break;
      if (page['hasMore'] != true ||
          (page['leaves'] as List).isEmpty ||
          page['nextAfterId'] != after) {
        throw const FormatException('crypto_inline_delete_graph_cursor');
      }
    }
    if (result.length != saved['prepare']['graphCount'] ||
        await CryptoInlineDeletionCodec.graphRoot(result) !=
            saved['prepare']['graphRoot']) {
      throw const FormatException('crypto_inline_delete_graph_incomplete');
    }
    return result;
  }

  Future<List<Map<String, dynamic>>> _seal(
    Map saved,
    List<Map<String, dynamic>> leaves,
  ) async {
    final scope = saved['scopeId'] as String,
        signing = await context.account.signingKey();
    final groups = <Map<String, dynamic>>[];
    try {
      for (var offset = 0; offset < leaves.length; offset += 32) {
        final batchId = _newId(),
            op = _newId(),
            proofs = <Map<String, dynamic>>[];
        final writes = <String, CryptoWriteContext>{};
        try {
          for (final leaf in leaves.skip(offset).take(32)) {
            final domain = leaf['domain'] as String;
            final write = writes[domain] ??= await context.access.writeContext(
              scope,
              domain,
              online: true,
            );
            if (write.headHash != saved['prepare']['membershipHeadHash'] ||
                write.accessRevision !=
                    saved['prepare']['expectedAccessRevision']) {
              throw const CryptoAuthorityPending(
                'scope_deletion_preview_changed',
              );
            }
            final row = await context.wireRecord(scope, domain, leaf['id']);
            if (row == null ||
                row['record_proof_hash'] != leaf['recordProofHash'] ||
                row['crypto_revision'] != leaf['revision']) {
              throw const CryptoAuthorityPending(
                'crypto_inline_delete_source_changed',
              );
            }
            final canonical =
                (jsonDecode(row['projection'] as String) as Map)['id']
                    as String;
            final metadata = await context.businessMetadata(
              scopeId: scope,
              domain: domain,
              type: leaf['type'],
              canonicalId: canonical,
              expectedRevision: leaf['revision'],
              rawPayload: null,
            );
            if (metadata['notificationState'] is Map) {
              // The whole project is gone. No live project/list grouping is
              // asserted by a tombstone with no semantic references.
              (metadata['notificationState'] as Map)['groupTargetId'] = null;
            }
            metadata['inlineDeletion'] = {
              'version': 2,
              'actionId': saved['actionId'],
              'planHash': saved['planHash'],
            };
            proofs.add(
              context.codec.sealRecord(
                serverId: context.account.directory.session.profile.serverId,
                accountId: context.account.directory.accountId,
                deviceId: context.account.deviceId,
                batchId: batchId,
                scopeId: scope,
                id: leaf['id'],
                type: leaf['type'],
                expectedRevision: leaf['revision'],
                epoch: write.epoch,
                accessRevision: write.accessRevision,
                membershipHeadHash: write.headHash,
                domain: domain,
                contentContract: write.contentContract,
                operationId: op,
                previousRecordHash: leaf['recordProofHash'],
                deleted: true,
                plaintext: null,
                metadata: metadata,
                contentKey: write.key.key,
                signingKey: signing.key,
              ),
            );
          }
          final commitment = await context.codec.commitBatch(
            serverId: context.account.directory.session.profile.serverId,
            accountId: context.account.directory.accountId,
            deviceId: context.account.deviceId,
            batchId: batchId,
            records: proofs,
            signingKey: signing.key,
            projectionToken: (r) async => context.codec.projectionGroupToken(
              r,
              writes[r['domain']]!.key.key,
            ),
          );
          groups.add({
            'batchId': batchId,
            'records': proofs,
            'commitment': commitment,
          });
        } finally {
          for (final w in writes.values) {
            w.key.release();
          }
        }
      }
    } finally {
      signing.release();
    }
    return groups;
  }

  Map<String, Map<String, dynamic>>? _verifiedInventory;
  String? _inventoryHead;

  /// Shared bounded, independently authenticated and decrypted inventory for
  /// the finite relocation planner. This returns no authority capability.
  Future<Map<String, Map<String, dynamic>>> verifiedInventory(
    String scope,
  ) async {
    Object? freeze(Object? value) {
      if (value is Map)
        return Map<String, dynamic>.unmodifiable({
          for (final entry in value.entries)
            entry.key as String: freeze(entry.value),
        });
      if (value is List) return List<Object?>.unmodifiable(value.map(freeze));
      return value;
    }

    final values = await _inventory(scope);
    return Map.unmodifiable({
      for (final entry in values.entries)
        entry.key: freeze(entry.value) as Map<String, dynamic>,
    });
  }

  Future<Map<String, Map<String, dynamic>>> _inventory(String scope) async {
    final head = await context.access.currentHead(scope, online: true);
    if (_verifiedInventory != null && _inventoryHead == head.headHash) {
      return _verifiedInventory!;
    }
    final result = <String, Map<String, dynamic>>{};
    var retainedBytes = 0;
    for (final domain in ['content', 'finance']) {
      await context.pullVerified(scope, domain);
      final read = await context.access.readContext(scope, domain);
      if (!await context.hasReusableCheckpoint(scope, domain, read)) {
        throw const CryptoAuthorityPending(
          'crypto_inline_delete_inventory_pending',
        );
      }
      String after = '';
      while (true) {
        final rows = await context.database.rows(
          'SELECT * FROM crypto_business_records WHERE partition=? AND scope_id=? AND domain=? AND id>? ORDER BY id LIMIT 50',
          [context.partition, scope, domain, after],
        );
        if (rows.isEmpty) break;
        for (final row in rows) {
          after = row['id'] as String;
          if (result.length >= CryptoInlineDeletionCodec.maxRecords) {
            throw const CryptoAuthorityPending(
              'crypto_inline_delete_inventory_limit',
            );
          }
          final retained = await context.database.rows(
            'SELECT wire FROM crypto_received WHERE partition=? AND scope_id=? AND domain=? AND record_id=? AND revision=?',
            [
              context.partition,
              scope,
              domain,
              row['id'],
              row['crypto_revision'],
            ],
          );
          if (retained.length != 1) {
            throw const CryptoAuthorityPending(
              'crypto_inline_delete_inventory_pending',
            );
          }
          final wire = Map<String, dynamic>.from(
            jsonDecode(retained.single['wire'] as String) as Map,
          );
          final proof = Map<String, dynamic>.from(
            (wire['authorization'] as Map)['recordProof'] as Map,
          );
          final body = _body(proof),
              authority = await context.access.recordAuthority(_body(proof));
          final record = await context.codec.verifyWire(
            serverId: context.account.directory.session.profile.serverId,
            wire: wire,
            trustedSigningKey: authority.signingKey,
            currentEpoch: authority.currentEpoch,
            closedRecordProofHash: authority.closedRecordProofHash,
          );
          if (record['id'] != row['id'] ||
              record['scopeId'] != scope ||
              record['domain'] != domain ||
              record['expectedRevision'] + 1 != row['crypto_revision'] ||
              await context.codec.digest(proof) != row['record_proof_hash']) {
            throw const FormatException(
              'crypto_inline_delete_inventory_substitution',
            );
          }
          final key = await context.access.recordKey(record);
          late final Uint8List? bytes;
          try {
            bytes = context.codec.openVerified(record, key.key);
          } finally {
            key.release();
          }
          try {
            Map<String, dynamic>? raw;
            Map<String, dynamic>? envelope;
            if (bytes != null) {
              final decoded = jsonDecode(utf8.decode(bytes));
              if (decoded is! Map ||
                  decoded['format'] != 2 ||
                  decoded['payload'] is! Map ||
                  CryptoBusinessJson.canonical(decoded['identity']) !=
                      CryptoBusinessJson.canonical(
                        body['metadata']['identity'],
                      )) {
                throw const FormatException('crypto_business_envelope');
              }
              envelope = Map<String, dynamic>.from(decoded);
              raw = Map<String, dynamic>.from(decoded['payload'] as Map);
            }
            if (authority.migrationOrigin != null) {
              raw = await verifyCryptoMigrationWitness(
                record: record,
                origin: authority.migrationOrigin!,
                recordProofHash: await context.codec.digest(proof),
                envelope: envelope,
                detachedWitness: authority.migrationWitness,
                reservedId: context.reservedRecordId,
              );
            }
            final value = CryptoProjectionRecord(
              wire,
              record,
              bytes,
              historyBasis: authority.historyBasis ?? 'current',
              batchKey: 'inlineInventory',
              migrationOrigin: authority.migrationOrigin,
              migrationWitness: authority.migrationWitness,
            );
            if (raw != null && context.expandPayload != null) {
              await context.prepareHistoricalPayload?.call([value]);
              raw = await context.expandPayload!(value, raw);
            }
            retainedBytes +=
                CryptoBusinessJson.encode(raw).length +
                CryptoBusinessJson.encode(row).length +
                CryptoJson.encode(body).length;
            if (retainedBytes > inventoryMaxBytes) {
              throw const CryptoAuthorityPending(
                'crypto_inline_delete_inventory_capacity',
              );
            }
            result[after] = {
              'body': body,
              'raw': raw,
              'row': row,
              'canonicalId': body['metadata']['identity']['canonicalId'],
            };
          } finally {
            bytes?.fillRange(0, bytes.length, 0);
          }
        }
      }
      final latest = await context.access.readContext(scope, domain);
      if (latest.headHash != read.headHash ||
          latest.epoch != read.epoch ||
          latest.accessRevision != read.accessRevision ||
          !await context.hasReusableCheckpoint(scope, domain, latest)) {
        throw const CryptoAuthorityPending(
          'crypto_inline_delete_inventory_changed',
        );
      }
    }
    if ((await context.access.currentHead(scope, online: true)).headHash !=
        head.headHash) {
      throw const CryptoAuthorityPending(
        'crypto_inline_delete_inventory_changed',
      );
    }
    _inventoryHead = head.headHash;
    _verifiedInventory = result;
    return result;
  }

  /// One-time metadata successors preserve the exact decrypted business map.
  /// This closes edges omitted by older supported producers before the user
  /// reviews the final deletion graph. Every successor uses normal WRITE/CAS
  /// and the same immutable deterministic repair intent on a retry.
  Future<bool> _reconcileProjectEdges(String scope, String project) async {
    final all = await _inventory(scope);
    final tasks = <String>{
      for (final v in all.values)
        if (v['body']['deleted'] == false &&
            v['body']['type'] == 'task' &&
            v['raw'] is Map &&
            v['raw']['projectId'] == project)
          v['canonicalId'] as String,
    };
    final me = (await context.access.currentHead(
      scope,
    )).member(context.account.directory.accountId);
    if (me['financeRole'] != 'write') {
      for (final v in all.values) {
        final b = v['body'] as Map, raw = v['raw'];
        if (b['deleted'] == false &&
            raw is Map &&
            financeTypes.contains(b['type']) &&
            (raw['projectId'] == project || tasks.contains(raw['taskId'])) &&
            !_same(
              context.referencesFor(
                scope,
                b['type'],
                Map<String, dynamic>.from(raw),
              ),
              b['metadata']['references'],
            )) {
          return false;
        }
      }
    }
    var changed = false;
    for (final v in all.values) {
      final b = v['body'] as Map, raw = v['raw'];
      if (b['deleted'] == true ||
          raw is! Map ||
          !(b['type'] == 'idea' || financeTypes.contains(b['type'])) ||
          !(raw['projectId'] == project || tasks.contains(raw['taskId']))) {
        continue;
      }
      final refs = context.referencesFor(
        scope,
        b['type'],
        Map<String, dynamic>.from(raw),
      );
      if (_same(refs, b['metadata']['references'])) continue;
      final row = v['row'] as Map;
      final op = await context.reservedRecordId(
        scope,
        'inlineProjectEdge:${row['record_proof_hash']}',
      );
      await context.push(scope, b['domain'], {
        'scopeId': scope,
        'operation': {
          'recordId': v['canonicalId'],
          'type': b['type'],
          'opId': op,
          'expectedRevision': row['revision_namespace'] == 'legacy'
              ? row['legacy_revision']
              : row['crypto_revision'],
          'deleted': false,
          'payload': Map<String, dynamic>.from(raw),
        },
      });
      changed = true;
    }
    if (changed) {
      _verifiedInventory = null;
      _inventoryHead = null;
      await _inventory(scope);
    }
    return true;
  }

  Future<List<Map<String, dynamic>>> _selected(
    String scope,
    String project,
  ) async {
    final all = await _inventory(scope),
        selected = <String, Map<String, dynamic>>{};
    final tasks = <String>{}, ideas = <String>{};
    for (final e in all.entries) {
      final b = e.value['body'] as Map, raw = e.value['raw'];
      if (b['deleted'] == true) continue;
      if (b['type'] == 'project' && e.value['canonicalId'] == project) {
        selected[e.key] = e.value;
      }
      if (raw is Map &&
          raw['projectId'] == project &&
          const {'task', 'event', 'idea'}.contains(b['type'])) {
        selected[e.key] = e.value;
        if (b['type'] == 'task') tasks.add(e.value['canonicalId']);
        if (b['type'] == 'idea') ideas.add(e.value['canonicalId']);
      }
    }
    final intents = <String>{};
    for (final e in all.entries) {
      final b = e.value['body'] as Map, raw = e.value['raw'];
      if (b['deleted'] == true || raw is! Map) continue;
      if (financeTypes.contains(b['type']) &&
              (raw['projectId'] == project || tasks.contains(raw['taskId'])) ||
          b['type'] == 'attachment' &&
              raw['targetType'] == 'task' &&
              tasks.contains(raw['targetId']) ||
          b['type'] == 'taskDerivationIntent' &&
              tasks.contains(raw['taskId'])) {
        selected[e.key] = e.value;
        if (b['type'] == 'taskDerivationIntent') {
          intents.add(e.value['canonicalId']);
        }
      }
      if (b['type'] == 'ideaAsset') {
        for (final r in b['metadata']['references'] as List) {
          if (r['scopeId'] == scope &&
              selected.containsKey(r['id']) &&
              all[r['id']]?['body']['type'] == 'idea') {
            selected[e.key] = e.value;
          }
        }
      }
    }
    for (final e in all.entries) {
      final b = e.value['body'] as Map, raw = e.value['raw'];
      if (b['deleted'] == true ||
          b['type'] != 'taskDerivationResolution' ||
          raw is! Map) {
        continue;
      }
      if (tasks.contains(raw['taskId']) || intents.contains(raw['intentId'])) {
        selected[e.key] = e.value;
      }
    }
    if (selected.isEmpty ||
        !selected.values.any(
          (v) => v['body']['type'] == 'project' && v['canonicalId'] == project,
        )) {
      throw const CryptoAuthorityPending(
        'crypto_inline_delete_project_pending',
      );
    }
    final descriptors = <Map<String, dynamic>>[
      for (final e in selected.entries)
        {
          'scopeId': scope,
          'id': e.key,
          'type': e.value['body']['type'],
          'domain': e.value['body']['domain'],
          'revision': e.value['row']['crypto_revision'],
          'recordProofHash': e.value['row']['record_proof_hash'],
        },
    ]..sort((a, b) => (a['id'] as String).compareTo(b['id']));
    return descriptors;
  }

  Future<Map<String, dynamic>> _finish(
    Map saved,
    Map<String, dynamic> result,
  ) async {
    final commit = saved['commit'] as Map,
        proof = Map<String, dynamic>.from(commit['certificateProof'] as Map);
    final event = Map<String, dynamic>.from(commit['accountEventProof'] as Map),
        body = _body(event);
    final hash = await cryptoSha256(cryptoBase64(event['commandBase64']));
    final expected = await cryptoSha256(
      utf8.encode(cryptoDirectoryLogDomain) +
          CryptoJson.encode({
            'serverId': body['serverId'],
            'accountId': body['accountId'],
            'generation': body['payload']['expectedGeneration'] + 1,
            'previousHeadHash': body['payload']['previousHeadHash'],
            'commandHash': hash,
            'signatureBase64': event['signatureBase64'],
          }),
    );
    if (result['deleted'] != true ||
        result['scopeId'] != saved['scopeId'] ||
        result['projectId'] != saved['projectId'] ||
        result['actionId'] != saved['actionId'] ||
        result['planHash'] != saved['planHash'] ||
        result['certificateHash'] != await _hash(proof) ||
        !_same(result['certificateProof'], proof) ||
        !_same(result['eventAuthorization'], event) ||
        result['eventCommandHash'] != hash ||
        result['eventHeadHash'] != expected) {
      throw const FormatException('crypto_inline_delete_receipt_substitution');
    }
    final own = await context.account.directory.requireFresh();
    if (!own.includesAnchor(
      body['payload']['expectedGeneration'] + 1,
      expected,
    )) {
      throw const CryptoAuthorityPending('crypto_inline_delete_event_pending');
    }
    context.access.invalidateAuthorityOperation();
    // Receipt settles deletion; projection catch-up can be resumed separately.
    // Replaying this original action never creates another project or cash leg.
    return result;
  }

  bool _same(Object? a, Object? b) =>
      CryptoBusinessJson.canonical(a) == CryptoBusinessJson.canonical(b);
}
