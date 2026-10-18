import 'dart:convert';

import 'account_directory_v2.dart' show cryptoSha256, cryptoDirectoryLogDomain;
import 'crypto_business_router.dart';
import 'crypto_business_inline_deletion.dart';
import 'crypto_business_json.dart';
import 'crypto_finance_topology_successor.dart';
import 'crypto_json.dart';
import 'crypto_record_address.dart';
import 'crypto_scope_deletion_codec.dart';
import 'crypto_sync_repository.dart';
import 'session_crypto_access.dart';

/// Reviewed whole-graph deletion. The original signed request and companion
/// are durable before transport; immutable receipts settle before reissue.
class CryptoBusinessDeletion {
  CryptoBusinessDeletion(this.context);
  final CryptoBusinessSession context;
  static const deliveryOperation = 'crypto2.scope.delete';
  bool supports(String operation) =>
      const {'scopes.deletionPreview', 'scopes.delete'}.contains(operation);

  static Map<String, dynamic> _body(Map proof) => Map<String, dynamic>.from(
    CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map,
  );
  static String _canonical(Object? value) =>
      utf8.decode(CryptoJson.encode(value));
  static Future<String> _hash(Map value) =>
      cryptoSha256(CryptoJson.encode(value));

  static Future<void> verifyDelivery(
    SessionCryptoAccess access,
    Map<String, dynamic> command,
  ) async {
    final p = command['payload'] as Map;
    CryptoScopeDeletionCodec.fields(p, {
      'certificateProof',
      'headerProof',
      'scopeProofs',
      'accountEventProof',
      'authorDirectoryHeadHash',
      if (p.containsKey('parentTopology')) 'parentTopology',
    });
    final own = await access.account.directory.requireFresh();
    own.activeDevice(access.account.deviceId);
    if (p['authorDirectoryHeadHash'] != own.headHash) {
      throw const CryptoAuthorityPending('crypto_member_directory_changed');
    }
    final c = _body(p['certificateProof'] as Map);
    CryptoScopeDeletionCodec.certificate(c);
    if (p.containsKey('parentTopology') !=
            c.containsKey('parentTopologyHash') ||
        p.containsKey('parentTopology') &&
            await _hash(
                  Map<String, dynamic>.from(p['parentTopology'] as Map),
                ) !=
                c['parentTopologyHash']) {
      throw const FormatException('crypto_scope_deletion_topology_binding');
    }
    if (p.containsKey('parentTopology')) {
      final batch = p['parentTopology'] as Map;
      if (batch['records'] is! List || batch['records'].length != 1) {
        throw const FormatException('crypto_scope_deletion_topology_binding');
      }
      final record = _body(batch['records'].single as Map),
          head = await access.currentHead(record['scopeId'], online: true);
      if (record['type'] != 'scopeMetadata' ||
          record['domain'] != 'content' ||
          record['deleted'] != false ||
          record['membershipHeadHash'] != head.headHash ||
          head.member(own.accountId)['manageKeys'] != true) {
        throw const CryptoAuthorityPending(
          'crypto_finance_topology_approval_pending',
        );
      }
      final write = await access.writeContext(record['scopeId'], 'content');
      write.key.release();
    }
    if (c['serverId'] != own.serverId ||
        c['requestId'] != command['requestId'] ||
        c['actorAccountId'] != own.accountId ||
        c['actorDeviceId'] != access.account.deviceId) {
      throw const FormatException('crypto_scope_deletion_context');
    }
    for (final raw in c['scopes'] as List) {
      final descriptor = raw as Map;
      final head = await access.currentHead(
        descriptor['scopeId'],
        online: true,
      );
      if (head.member(own.accountId)['manageKeys'] != true ||
          head.headHash != descriptor['headHash'] ||
          head.accessRevision != descriptor['accessRevision'] ||
          await access.verifiedLifecycleHash(head.scopeId) !=
              descriptor['lifecycleHash']) {
        throw const CryptoAuthorityPending('scope_deletion_preview_changed');
      }
    }
  }

  Future<Map<String, dynamic>> dispatch(
    String operation,
    Map<String, Object?> params,
  ) async {
    if (params['projectId'] != null) {
      return CryptoBusinessInlineDeletion(context).dispatch(operation, params);
    }
    final scope = params['scopeId'];
    if (!isCryptoCanonicalUuid(scope)) {
      throw const FormatException('crypto_scope_deletion_target');
    }
    if (operation == 'scopes.deletionPreview') {
      final page = await context.account.directory.call(
        'crypto2.scope.deletionPreview',
        {'scopeId': scope},
      );
      await _validatePreview(page, scope as String);
      return {
        ...page,
        'cryptoDeletionVersion': 2,
        'name': await _displayName(scope),
        'scopeNames': [
          for (final d in page['scopeContexts'] as List)
            await _displayName((d as Map)['scopeId'] as String),
        ],
      };
    }
    if (operation != 'scopes.delete' ||
        !isCryptoCanonicalUuid(params['requestId'])) {
      throw const FormatException('crypto_scope_deletion_request');
    }
    final request = params['requestId'] as String;
    final key = 'scopeDeletion:$request';
    final rows = await context.database.rows(
      'SELECT payload FROM crypto_export_drafts WHERE partition=? AND scope_id=? AND action_id=?',
      [context.partition, scope, key],
    );
    late Map<String, dynamic> saved;
    if (rows.isEmpty) {
      final preview = await context.account.directory.call(
        'crypto2.scope.deletionPreview',
        {'scopeId': scope},
      );
      await _validatePreview(preview, scope as String);
      if (preview['canDelete'] != true ||
          preview['previewHash'] != params['previewHash']) {
        throw const CryptoAuthorityPending('scope_deletion_preview_changed');
      }
      final own = await context.account.directory.requireFresh();
      final topology = await _parentTopology(scope, request);
      final certificate = <String, dynamic>{
        'version': 2,
        'serverId': own.serverId,
        'rootScopeId': scope,
        'requestId': request,
        'actorAccountId': own.accountId,
        'actorDeviceId': context.account.deviceId,
        'scopes': preview['scopeContexts'],
        'graphRoot': preview['graphRoot'],
        'graphCount': preview['graphCount'],
        'retention': CryptoScopeDeletionCodec.retention,
        if (topology != null) 'parentTopologyHash': await _hash(topology),
      };
      CryptoScopeDeletionCodec.certificate(certificate);
      final lease = await context.account.signingKey();
      late Map<String, dynamic> payload;
      try {
        Map<String, dynamic> sign(Map<String, dynamic> value, String domain) =>
            context.account.directory.reducer.crypto.signDomain(
              value,
              lease.key,
              domain,
            );
        final certificateProof = sign(
          certificate,
          CryptoScopeDeletionCodec.certificateDomain,
        );
        final header = <String, dynamic>{
          'version': 2,
          'serverId': own.serverId,
          'requestId': request,
          'actorAccountId': own.accountId,
          'actorDeviceId': context.account.deviceId,
          'authorDirectoryHeadHash': own.headHash,
          'privateCertificateHash': await _hash(certificateProof),
          'rootToken': await CryptoScopeDeletionCodec.rootToken(certificate),
          'graphRoot': preview['graphRoot'],
          'graphCount': preview['graphCount'],
          'retention': CryptoScopeDeletionCodec.retention,
          'scopeLeafRoot': '0' * 64,
          'scopeLeafCount': preview['graphCount'],
          if (topology != null)
            'parentTopologyHash': certificate['parentTopologyHash'],
        };
        final headerContext = await CryptoScopeDeletionCodec.headerContext(
          header,
        );
        final leaves = <Map<String, dynamic>>[];
        final hashes = <String>[];
        for (final raw in certificate['scopes'] as List) {
          final leaf = <String, dynamic>{
            'version': 2,
            'serverId': own.serverId,
            'requestId': request,
            'headerContextHash': headerContext,
            ...Map<String, dynamic>.from(raw as Map),
          };
          final proof = sign(leaf, CryptoScopeDeletionCodec.leafDomain);
          leaves.add(proof);
          hashes.add(await _hash(proof));
        }
        hashes.sort();
        header['scopeLeafRoot'] = await CryptoScopeDeletionCodec.leafRoot(
          header,
          hashes,
        );
        final headerProof = sign(header, CryptoScopeDeletionCodec.headerDomain);
        final event = await context.account.prepareScopeDeletionEvent(
          requestId: request,
          scopeToken: header['rootToken'],
          certificateHash: await _hash(headerProof),
        );
        payload = {
          'certificateProof': certificateProof,
          'headerProof': headerProof,
          'scopeProofs': leaves,
          'accountEventProof': event.authorization,
          'authorDirectoryHeadHash': own.headHash,
          if (topology != null) 'parentTopology': topology,
        };
      } finally {
        lease.release();
      }
      saved = {
        'scopeId': scope,
        'previewHash': params['previewHash'],
        'payload': payload,
      };
      await context.database.execute(
        'INSERT INTO crypto_export_drafts VALUES(?,?,?,?)',
        [context.partition, scope, key, jsonEncode(saved)],
      );
    } else {
      saved = Map<String, dynamic>.from(
        jsonDecode(rows.single['payload'] as String) as Map,
      );
      if (saved['scopeId'] != scope ||
          saved['previewHash'] != params['previewHash']) {
        throw const FormatException('crypto_scope_deletion_immutable_request');
      }
    }
    final payload = Map<String, dynamic>.from(saved['payload'] as Map);
    final original = await context.queue.enqueueCommand(
      actionKey: key,
      requestId: request,
      operation: deliveryOperation,
      payload: payload,
    );
    await context.queue.resumeUnresolved(requestIds: {original});
    final result = await context.queue.commandResult(original);
    await _verifyOwnResult(result, payload, scope as String);
    return result;
  }

  Future<Map<String, dynamic>?> _parentTopology(
    String scope,
    String operation,
  ) async {
    final rows = await context.db.rows(
      'SELECT data FROM scopes WHERE partition=? AND id=?',
      [context.partition, scope],
    );
    if (rows.length != 1)
      throw const CryptoAuthorityPending('crypto_scope_descriptor_pending');
    final local = Map<String, dynamic>.from(
      jsonDecode(rows.single['data'] as String),
    );
    if (local['kind'] != 'project' || local['parentSpaceId'] == null)
      return null;
    final parent = local['parentSpaceId'];
    if (!isCryptoCanonicalUuid(parent))
      throw const FormatException('crypto_scope_deletion_parent');
    final prepared = await CryptoFinanceTopologySuccessor.prepare(
      runtime: context,
      parentScopeId: parent,
      childScopeId: scope,
      remove: true,
    );
    final previous = prepared.previous,
        id = await context.reservedRecordId(parent, 'scopeMetadata'),
        address = context.address(parent, 'content', 'scopeMetadata', id),
        write = await context.access.writeContext(parent, 'content'),
        signing = await context.account.signingKey();
    List<int>? plain;
    try {
      final raw =
          await context.encodePayload?.call(
            parent,
            'content',
            'scopeMetadata',
            id,
            prepared.raw,
            operation,
          ) ??
          prepared.raw;
      final bytes = CryptoBusinessJson.encode({
        'format': 2,
        'identity': address.identity,
        'payload': raw,
      });
      plain = bytes;
      if (bytes.length > 98304)
        throw const CryptoAuthorityPending('crypto_finance_topology_capacity');
      final batchId = context.codec.crypto.randomId();
      final proof = context.codec.sealRecord(
        serverId: context.account.directory.session.profile.serverId,
        accountId: context.account.directory.accountId,
        deviceId: context.account.deviceId,
        batchId: batchId,
        scopeId: parent,
        id: address.wireId,
        type: 'scopeMetadata',
        expectedRevision: previous['crypto_revision'] as int,
        epoch: write.epoch,
        accessRevision: write.accessRevision,
        membershipHeadHash: write.headHash,
        domain: 'content',
        contentContract: write.contentContract,
        operationId: operation,
        previousRecordHash: previous['record_proof_hash'] as String,
        deleted: false,
        plaintext: bytes,
        metadata: await context.businessMetadata(
          scopeId: parent,
          domain: 'content',
          type: 'scopeMetadata',
          canonicalId: id,
          expectedRevision: previous['legacy_revision'] as int,
          rawPayload: raw,
        ),
        contentKey: write.key.key,
        signingKey: signing.key,
      );
      final commitment = await context.codec.commitBatch(
        serverId: context.account.directory.session.profile.serverId,
        accountId: context.account.directory.accountId,
        deviceId: context.account.deviceId,
        batchId: batchId,
        records: [proof],
        signingKey: signing.key,
        projectionToken: (record) async =>
            context.codec.projectionGroupToken(record, write.key.key),
      );
      return {
        'batchId': batchId,
        'records': [proof],
        'commitment': commitment,
      };
    } finally {
      if (plain != null) plain.fillRange(0, plain.length, 0);
      signing.release();
      write.key.release();
    }
  }

  /// Former members authenticate their own leaf against an already anchored
  /// exact scope head. No private graph or fresh issuance authority is inferred.
  Future<Map<String, dynamic>> retainedStatus(String scope) async {
    final status = await context.account.directory.call(
      'crypto2.scope.deletionStatus',
      {'scopeId': scope},
    );
    final headerProof = Map<String, dynamic>.from(status['headerProof'] as Map);
    final leafProof = Map<String, dynamic>.from(status['leafProof'] as Map);
    final header = _body(headerProof), leaf = _body(leafProof);
    CryptoScopeDeletionCodec.header(header);
    CryptoScopeDeletionCodec.leaf(leaf);
    if (status['scopeId'] != scope ||
        leaf['scopeId'] != scope ||
        leaf['serverId'] != header['serverId'] ||
        leaf['requestId'] != header['requestId'] ||
        header['serverId'] !=
            context.account.directory.session.profile.serverId ||
        status['certificateHash'] != await _hash(headerProof) ||
        leaf['headerContextHash'] !=
            await CryptoScopeDeletionCodec.headerContext(header)) {
      throw const FormatException('crypto_scope_deletion_context');
    }
    final digests = (status['leafDigests'] as List).cast<String>();
    if (await CryptoScopeDeletionCodec.leafRoot(header, digests) !=
            header['scopeLeafRoot'] ||
        !digests.contains(await _hash(leafProof))) {
      throw const FormatException('crypto_scope_deletion_inclusion');
    }
    return context.access.withVerifiedDeletedScope(
      scope,
      Map<String, dynamic>.from(status['membershipHead'] as Map),
      (head) async {
        if (head.headHash != leaf['headHash'] ||
            head.accessRevision != leaf['accessRevision']) {
          throw const FormatException('crypto_scope_deletion_head');
        }
        final manager = head.member(header['actorAccountId']);
        if (manager['manageKeys'] != true) {
          throw const FormatException('crypto_scope_deletion_manager');
        }
        final before = await context.access.directoryAt(
          scopeId: scope,
          scopeHeadHash: head.headHash,
          accountId: header['actorAccountId'],
          directoryHeadHash: header['authorDirectoryHeadHash'],
          online: true,
          allowUnverifiedContact: true,
        );
        if (before.snapshot['rootSigningKeyBase64'] !=
                manager['rootSigningKeyBase64'] ||
            before.snapshot['rootEncryptionKeyBase64'] !=
                manager['rootEncryptionKeyBase64'] ||
            before.deviceSnapshotHash != manager['deviceSnapshotHash']) {
          throw const FormatException(
            'crypto_scope_deletion_manager_directory',
          );
        }
        final key = cryptoBase64(
          before.activeDevice(header['actorDeviceId'])['signingKeyBase64'],
          length: 32,
        );
        final crypto = context.account.directory.reducer.crypto;
        crypto.verifyDomain(
          headerProof,
          key,
          CryptoScopeDeletionCodec.headerDomain,
        );
        crypto.verifyDomain(
          leafProof,
          key,
          CryptoScopeDeletionCodec.leafDomain,
        );
        final eventProof = Map<String, dynamic>.from(
          status['eventAuthorization'] as Map,
        );
        final event = _body(eventProof), ep = event['payload'] as Map;
        if (event['operation'] != 'crypto2.account.scopeDeletion' ||
            event['requestId'] != header['requestId'] ||
            event['accountId'] != before.accountId ||
            event['deviceId'] != header['actorDeviceId'] ||
            ep['scopeToken'] != header['rootToken'] ||
            ep['certificateHash'] != status['certificateHash'] ||
            ep['previousHeadHash'] != before.headHash) {
          throw const FormatException('crypto_scope_deletion_event_binding');
        }
        final commandHash = await cryptoSha256(
          cryptoBase64(eventProof['commandBase64']),
        );
        final generation = before.generation + 1;
        final eventHead = await cryptoSha256(
          utf8.encode(cryptoDirectoryLogDomain) +
              CryptoJson.encode({
                'serverId': before.serverId,
                'accountId': before.accountId,
                'generation': generation,
                'previousHeadHash': before.headHash,
                'commandHash': commandHash,
                'signatureBase64': eventProof['signatureBase64'],
              }),
        );
        if (status['eventHeadHash'] != eventHead ||
            status['eventCommandHash'] != commandHash) {
          throw const FormatException('crypto_scope_deletion_event_binding');
        }
        final reduced = await context.account.directory.reducer.apply(
          previous: before,
          entry: {
            'generation': generation,
            'headHash': eventHead,
            'previousHeadHash': before.headHash,
            'commandHash': commandHash,
            'authorization': eventProof,
          },
          serverId: before.serverId,
          accountId: before.accountId,
          pinnedRootFingerprint: before.rootFingerprint,
        );
        final included = await context.access.directoryAt(
          scopeId: scope,
          scopeHeadHash: head.headHash,
          accountId: before.accountId,
          directoryHeadHash: eventHead,
          online: true,
          allowUnverifiedContact: true,
        );
        if (included.headHash != reduced.headHash ||
            included.snapshotHash != reduced.snapshotHash) {
          throw const FormatException('crypto_scope_deletion_event_inclusion');
        }
        return status;
      },
    );
  }

  Future<String> _displayName(String scope) async {
    final rows = await context.database.rows(
      'SELECT data FROM scopes WHERE partition=? AND id=?',
      [context.partition, scope],
    );
    if (rows.length == 1) {
      final raw = jsonDecode(rows.single['data'] as String) as Map;
      final name = raw['name'];
      if (name is String && name.isNotEmpty) return name;
    }
    return scope;
  }

  Future<void> _validatePreview(
    Map<String, dynamic> preview,
    String scope,
  ) async {
    if (preview['scopeId'] != scope ||
        preview['canDelete'] is! bool ||
        preview['scopeContexts'] is! List ||
        preview['previewHash'] is! String) {
      throw const FormatException('crypto_scope_deletion_preview');
    }
    if (preview['incomplete'] == true) {
      if (preview['canDelete'] != false ||
          preview['graphRoot'] != null ||
          preview['graphCount'] != 0 ||
          (preview['scopeContexts'] as List).isNotEmpty ||
          (preview['counts'] as Map).values.any((v) => v != 0)) {
        throw const FormatException('crypto_scope_deletion_redacted_preview');
      }
      return;
    }
    if (preview['graphRoot'] != preview['previewHash']) {
      throw const FormatException('crypto_scope_deletion_preview');
    }
    CryptoScopeDeletionCodec.digest(preview['graphRoot']);
    CryptoScopeDeletionCodec.safeInt(
      preview['graphCount'],
      minimum: 1,
      maximum: CryptoScopeDeletionCodec.maxScopes,
    );
    CryptoScopeDeletionCodec.retained(preview['retention'] as Map);
    if (preview['canDelete'] != true) return;
    if ((preview['scopeContexts'] as List).length != preview['graphCount']) {
      throw const FormatException('crypto_scope_deletion_count');
    }
    String? previous;
    for (final raw in preview['scopeContexts'] as List) {
      final d = raw as Map;
      CryptoScopeDeletionCodec.scope(d);
      if (previous != null && previous.compareTo(d['scopeId']) >= 0) {
        throw const FormatException('crypto_scope_deletion_order');
      }
      previous = d['scopeId'];
      final head = await context.access.currentHead(d['scopeId'], online: true);
      if (head.headHash != d['headHash'] ||
          head.accessRevision != d['accessRevision'] ||
          head.member(context.account.directory.accountId)['manageKeys'] !=
              true ||
          await context.access.verifiedLifecycleHash(head.scopeId) !=
              d['lifecycleHash']) {
        throw const CryptoAuthorityPending('scope_deletion_preview_changed');
      }
    }
  }

  Future<void> _verifyOwnResult(
    Map<String, dynamic> result,
    Map<String, dynamic> payload,
    String scope,
  ) async {
    final c = _body(payload['certificateProof'] as Map);
    final ids = [for (final d in c['scopes'] as List) (d as Map)['scopeId']];
    final event = _body(payload['accountEventProof'] as Map);
    if (result['deleted'] != true ||
        result['scopeId'] != scope ||
        _canonical(result['deletedScopeIds']) != _canonical(ids) ||
        result['certificateHash'] !=
            await _hash(payload['headerProof'] as Map) ||
        _canonical(result['headerProof']) !=
            _canonical(payload['headerProof']) ||
        _canonical(result['eventAuthorization']) !=
            _canonical(payload['accountEventProof']) ||
        result['eventCommandHash'] !=
            await cryptoSha256(
              cryptoBase64(
                (payload['accountEventProof'] as Map)['commandBase64'],
              ),
            )) {
      throw const FormatException('crypto_scope_deletion_result');
    }
    final own = await context.account.directory.requireFresh();
    if (!own.includesAnchor(
      (event['payload'] as Map)['expectedGeneration'] + 1,
      result['eventHeadHash'],
    )) {
      throw const FormatException('crypto_scope_deletion_event_inclusion');
    }
    context.access.invalidateAuthorityOperation();
  }
}
