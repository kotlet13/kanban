import '../account_work_coordinator.dart';
import 'crypto_record_blob_target.dart';
import 'crypto_record_policy.dart';
import 'crypto_migration_idea_draft_recovery.dart';
import 'dart:convert';
import 'dart:typed_data';
import '../../domain/attachment_models.dart';
import '../../domain/idea_models.dart';
import '../idea_repository.dart' show verifyIdeaAsset;
import '../../domain/collaboration_models.dart';
import '../../domain/spreadsheet_models.dart';
import 'crypto_business_router.dart';
import 'account_directory_v2.dart' show cryptoSha256;
import 'crypto_document_blob.dart';
import 'crypto_business_json.dart';
import 'crypto_business_payload.dart';
import 'crypto_sync_repository.dart';
import 'crypto_record_address.dart';
import '../collaboration_transport.dart' show CollaborationApiException;

/// Adapts the existing document gateways to authenticated encrypted records.
/// All document names, cells, plaintext hashes and file metadata stay inside
/// encrypted payloads; only opaque blob IDs occur in signed public metadata.
class CryptoBusinessDocuments {
  CryptoBusinessDocuments(this.context) : blobs = CryptoDocumentBlob(context);
  final CryptoBusinessSession context;
  final CryptoDocumentBlob blobs;
  String get p => context.partition;
  bool supports(String op) =>
      op.startsWith('tables.') ||
      op.startsWith('attachments.') ||
      op.startsWith('ideas.asset.');
  List<String> blobIds(Map<String, dynamic> raw) => [
    if (raw['documentFormat'] == 1) raw['blob']['id'] as String,
    if (raw['cryptoBlob'] is Map) raw['cryptoBlob']['id'] as String,
    if (raw['cryptoPayloadBlob'] is Map)
      raw['cryptoPayloadBlob']['id'] as String,
    for (final asset in raw['assets'] as List? ?? const [])
      if (asset is Map && asset['cryptoBlob'] is Map)
        asset['cryptoBlob']['id'] as String,
  ];
  List<Map<String, dynamic>>? references(
    String type,
    Map<String, dynamic>? raw,
  ) {
    if (type != 'attachment' || raw == null) return null;
    final target = AttachmentTarget(
      scopeId: raw['scopeId'],
      targetType: raw['targetType'],
      targetId: raw['targetId'],
    );
    target.validate();
    return target.targetType == 'scope'
        ? []
        : [
            {
              'scopeId': target.scopeId,
              'id': target.targetId,
              'type': target.targetType,
            },
          ];
  }

  bool _manifest(Map raw) => raw['documentFormat'] == 1;
  Map<String, dynamic>? validateRaw(
    String domain,
    String type,
    Map<String, dynamic> raw,
  ) {
    if (domain != 'content') return null;
    raw = CryptoRecordPolicy.businessPayload(raw);
    if (type == 'table') {
      if (_manifest(raw)) {
        if (raw.length != 3 ||
            raw['documentType'] != 'table' ||
            raw['blob'] is! Map) {
          throw const FormatException('crypto_table_manifest');
        }
        blobs.validate(raw['blob'] as Map);
        return raw;
      }
      _table(raw);
      return raw;
    }
    if (type == 'attachment') {
      final m = AttachmentMetadata.fromJson(raw);
      if (!m.complete || raw['cryptoBlob'] is! Map) {
        throw const FormatException('crypto_attachment_manifest');
      }
      blobs.validate(raw['cryptoBlob'] as Map);
      return raw;
    }
    return null;
  }

  void _table(Map<String, dynamic> raw) {
    final doc = SpreadsheetDocument.fromJson(raw);
    if (!isCryptoCanonicalUuid(doc.id) ||
        !isCryptoCanonicalUuid(doc.scopeId) ||
        doc.revision < 1 ||
        doc.title.trim().isEmpty ||
        utf8.encode(doc.title).length > 200 ||
        doc.cells.length > 10000 ||
        utf8.encode(jsonEncode(doc.cells)).length > 512 * 1024 ||
        doc.cells.entries.any(
          (e) =>
              SpreadsheetAddress.parse(e.key)?.label != e.key ||
              utf8.encode(e.value).length > 4096,
        )) {
      throw const FormatException('crypto_table_payload');
    }
  }

  Future<Map<String, dynamic>> encodePayload(
    String scope,
    String domain,
    String type,
    String id,
    Map<String, dynamic> raw,
    String operationId,
  ) async {
    if (_manifest(raw)) return raw;
    final source = Map<String, dynamic>.from(raw)..remove('cryptoPayloadBlob');
    final bytes = CryptoBusinessJson.encode(source);
    try {
      if (bytes.length <= 90000) return source;
      final descriptor = await blobs.stage(
        scopeId: scope,
        recordId: id,
        operationId: '$operationId:payload',
        kind: 'payload:$type',
        plaintext: bytes,
        domain: domain,
      );
      await blobs.upload(descriptor);
      return {
        'documentFormat': 1,
        'documentType': 'payload',
        'payloadType': type,
        'blob': descriptor,
      };
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  }

  void _validateManifest(
    CryptoProjectionRecord record,
    Map<String, dynamic> raw,
  ) {
    raw = CryptoRecordPolicy.businessPayload(raw);
    if (raw['documentType'] == 'payload') {
      if (raw.length != 4 ||
          raw['payloadType'] != record.record['type'] ||
          raw['blob'] is! Map) {
        throw const FormatException('crypto_payload_manifest');
      }
    } else if (raw['documentType'] == 'table' &&
        record.record['type'] == 'table') {
      validateRaw(record.record['domain'], 'table', raw);
    } else {
      throw const FormatException('crypto_document_manifest_type');
    }
  }

  void _nestedBindings(
    CryptoProjectionRecord record,
    Map<String, dynamic> raw,
  ) {
    for (final key in ['cryptoBlob', 'cryptoPayloadBlob']) {
      if (raw[key] is Map) {
        _recordBinding(record, Map<String, dynamic>.from(raw[key] as Map));
      }
    }
    for (final asset in raw['assets'] as List? ?? const []) {
      if (asset is Map && asset['cryptoBlob'] is Map) {
        _recordBinding(
          record,
          Map<String, dynamic>.from(asset['cryptoBlob'] as Map),
        );
      }
    }
  }

  Future<void> prepareRecords(List<CryptoProjectionRecord> records) async {
    for (final record in records) {
      if (record.plaintext == null) continue;
      final envelope = jsonDecode(utf8.decode(record.plaintext!));
      if (envelope is! Map || envelope['payload'] is! Map) continue;
      var raw = Map<String, dynamic>.from(envelope['payload'] as Map);
      if (_manifest(raw)) {
        _validateManifest(record, raw);
        final d = Map<String, dynamic>.from(raw['blob'] as Map);
        _recordBinding(record, d);
        final bytes = await blobs.open(d);
        try {
          final full = jsonDecode(utf8.decode(bytes));
          if (full is! Map) {
            throw const FormatException('crypto_payload_manifest');
          }
          raw = Map<String, dynamic>.from(full);
          _nestedBindings(record, raw);
        } finally {
          bytes.fillRange(0, bytes.length, 0);
        }
      }
      if (record.record['type'] == 'idea') {
        await _verifyIdeaAssets(record, raw);
      }
      if (raw['cryptoBlob'] is Map) {
        _recordBinding(
          record,
          Map<String, dynamic>.from(raw['cryptoBlob'] as Map),
        );
      }
      for (final asset in raw['assets'] as List? ?? const []) {
        if (asset is Map && asset['cryptoBlob'] is Map) {
          _recordBinding(
            record,
            Map<String, dynamic>.from(asset['cryptoBlob'] as Map),
          );
        }
      }
    }
  }

  Map<String, IdeaAsset> _ideaAssets(Map<String, dynamic> raw) {
    final board = IdeaBoard.fromJson(
      CryptoBusinessPayload.projection('content', 'idea', raw),
    );
    final result = <String, IdeaAsset>{};
    for (final asset in board.assets) {
      final previous = result[asset.sha256];
      if (previous != null &&
          jsonEncode(previous.toJson()) != jsonEncode(asset.toJson())) {
        throw const FormatException('crypto_idea_asset_descriptor');
      }
      result[asset.sha256] = asset;
    }
    return result;
  }

  Future<void> _verifyIdeaAssets(
    CryptoProjectionRecord record,
    Map<String, dynamic> raw,
  ) async {
    final expected = _ideaAssets(raw);
    final technical = raw['assets'];
    if (technical is! List || technical.length != expected.length) {
      throw const FormatException('crypto_idea_asset_manifest');
    }
    final seen = <String>{};
    for (final value in technical) {
      if (value is! Map ||
          value.length != 6 ||
          !value.keys.every(
            const {
              'sha256',
              'mime',
              'size',
              'width',
              'height',
              'cryptoBlob',
            }.contains,
          )) {
        throw const FormatException('crypto_idea_asset_manifest');
      }
      final asset = expected[value['sha256']];
      if (asset == null ||
          !seen.add(asset.sha256) ||
          jsonEncode(asset.toJson()) !=
              jsonEncode({
                for (final field in [
                  'sha256',
                  'mime',
                  'size',
                  'width',
                  'height',
                ])
                  field: value[field],
              })) {
        throw const FormatException('crypto_idea_asset_manifest');
      }
      final descriptor = Map<String, dynamic>.from(value['cryptoBlob'] as Map);
      _recordBinding(record, descriptor);
      final bytes = await blobs.open(descriptor);
      try {
        await verifyIdeaAsset(asset, bytes);
      } finally {
        bytes.fillRange(0, bytes.length, 0);
      }
    }
  }

  void _recordBinding(CryptoProjectionRecord value, Map<String, dynamic> d) {
    blobs.validate(d);
    final r = value.record;
    if (d['recordPolicyTarget'] is Map)
      CryptoRecordBlobTarget.requireRecordBinding(
        Map<String, dynamic>.from(d['recordPolicyTarget'] as Map),
        r,
      );

    if (d['scopeId'] != r['scopeId'] ||
        d['domain'] != r['domain'] ||
        d['epoch'] > r['epoch'] ||
        !(r['metadata']['blobIds'] as List).contains(d['id'])) {
      throw const FormatException('crypto_document_record_binding');
    }
  }

  Future<Map<String, dynamic>> expandPayload(
    CryptoProjectionRecord value,
    Map<String, dynamic> raw,
  ) async {
    if (!_manifest(raw)) return raw;
    _validateManifest(value, raw);
    final descriptor = Map<String, dynamic>.from(raw['blob'] as Map);
    _recordBinding(value, descriptor);
    final bytes = await blobs.open(descriptor, online: false);
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map) {
        throw const FormatException('crypto_document_payload');
      }
      if (raw.containsKey(CryptoRecordPolicy.secretField) &&
          decoded.containsKey(CryptoRecordPolicy.secretField) &&
          CryptoBusinessJson.canonical(raw[CryptoRecordPolicy.secretField]) !=
              CryptoBusinessJson.canonical(
                decoded[CryptoRecordPolicy.secretField],
              )) {
        throw const FormatException('crypto_record_policy_blob_secret');
      }
      return {
        ...Map<String, dynamic>.from(decoded),
        if (raw.containsKey(CryptoRecordPolicy.secretField))
          CryptoRecordPolicy.secretField: raw[CryptoRecordPolicy.secretField],
        if (raw['documentType'] == 'payload')
          'cryptoPayloadBlob': descriptor
        else
          'cryptoBlob': descriptor,
      };
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  }

  Future<Map<String, dynamic>?> projectRecord(
    CryptoProjectionRecord value,
    Map<String, dynamic> raw,
  ) async {
    final type = value.record['type'];
    if (!['table', 'attachment'].contains(type)) return null;
    validateRaw(value.record['domain'], type, raw);
    if (raw['id'] !=
            (value.record['metadata']['identity']?['canonicalId'] ??
                value.record['id']) ||
        raw['scopeId'] != value.record['scopeId']) {
      throw const FormatException('crypto_document_identity');
    }
    return CryptoRecordPolicy.businessPayload(raw)..remove('cryptoBlob');
  }

  Future<Map<String, dynamic>> prepareOutgoing(
    String scope,
    String type,
    String recordId,
    Map<String, dynamic> raw,
    String operationId,
  ) async {
    raw = Map<String, dynamic>.from(raw)..remove('cryptoPayloadBlob');
    if (type != 'idea') return raw;
    final recovered = await CryptoMigrationIdeaDraftRecovery.rows(
      context.database,
      'shared:$p:$scope',
      'idea_drafts',
      id: recordId,
    );
    if (recovered.isNotEmpty) {
      final original = Map<String, dynamic>.from(
        jsonDecode(recovered.single['payload'] as String) as Map,
      );
      raw = Map<String, dynamic>.from(
        CryptoBusinessPayload.merge({...original, ...raw}, raw) as Map,
      );
    }
    final expected = _ideaAssets(raw);
    final previous = <String, Map<String, dynamic>>{};
    for (final value in raw['assets'] as List? ?? const []) {
      if (value is! Map || value['sha256'] is! String) {
        throw const FormatException('crypto_idea_asset_manifest');
      }
      final asset = Map<String, dynamic>.from(value);
      if (previous.containsKey(asset['sha256']) &&
          CryptoBusinessJson.canonical(previous[asset['sha256']]) !=
              CryptoBusinessJson.canonical(asset)) {
        throw const FormatException('crypto_idea_asset_manifest');
      }
      previous[asset['sha256']] = asset;
    }
    final assets = <Map<String, dynamic>>[];
    final ordered = expected.keys.toList()..sort();
    for (final hash in ordered) {
      final asset = expected[hash]!;
      final old = previous[hash];
      if (old != null && old['cryptoBlob'] is Map) {
        final metadata = {
          for (final field in ['sha256', 'mime', 'size', 'width', 'height'])
            field: old[field],
        };
        if (CryptoBusinessJson.canonical(metadata) !=
            CryptoBusinessJson.canonical(asset.toJson())) {
          throw const FormatException('crypto_idea_asset_manifest');
        }
        blobs.validate(old['cryptoBlob'] as Map);
        if (old['cryptoBlob']['scopeId'] != scope ||
            old['cryptoBlob']['domain'] != 'content') {
          throw const FormatException('crypto_idea_asset_manifest');
        }
        assets.add({...asset.toJson(), 'cryptoBlob': old['cryptoBlob']});
        continue;
      }
      final rows = await context.database.rows(
        'SELECT bytes FROM idea_assets WHERE workspace=? AND sha256=?',
        ['shared:$p:$scope', hash],
      );
      final bytes = rows.isEmpty
          ? await CryptoMigrationIdeaDraftRecovery.asset(
              context.database,
              'shared:$p:$scope',
              asset,
            )
          : Uint8List.fromList((rows.single['bytes'] as List).cast<int>());
      if (bytes == null) {
        throw const CryptoAuthorityPending('idea_asset_missing');
      }
      try {
        await verifyIdeaAsset(asset, bytes);
        final descriptor = await blobs.stage(
          scopeId: scope,
          recordId: recordId,
          operationId: '$operationId:$hash',
          kind: 'ideaAsset',
          plaintext: bytes,
        );
        await blobs.upload(descriptor);
        assets.add({...asset.toJson(), 'cryptoBlob': descriptor});
      } finally {
        bytes.fillRange(0, bytes.length, 0);
      }
    }
    return {...raw, 'assets': assets};
  }

  Future<List<Map<String, dynamic>>> _records(String scope, String type) async {
    final rows = await context.database.rows(
      'SELECT raw_payload FROM crypto_business_records WHERE partition=? AND scope_id=? AND domain=? AND type=? AND raw_payload IS NOT NULL',
      [p, scope, 'content', type],
    );
    return [
      for (final r in rows)
        CryptoRecordPolicy.businessPayload(
          Map<String, dynamic>.from(
            jsonDecode(r['raw_payload'] as String) as Map,
          ),
        ),
    ];
  }

  Future<Map<String, dynamic>> _raw(
    String scope,
    String id,
    String type,
  ) async {
    final row = await context.record(scope, 'content', id, type: type);
    if (row == null || row['type'] != type || row['raw_payload'] == null) {
      throw CollaborationException(
        type == 'table' ? 'table_unavailable' : 'attachment_unavailable',
      );
    }
    return Map<String, dynamic>.from(
      jsonDecode(row['raw_payload'] as String) as Map,
    );
  }

  Map<String, dynamic> _sheet(Map<String, dynamic> raw) =>
      CryptoRecordPolicy.businessPayload(raw)..remove('cryptoBlob');
  Future<Map<String, dynamic>> _lease(String scope, String id) async {
    final head = await context.access.currentHead(scope, online: true);
    final reply = await context.account.directory.call('crypto2.table.lease', {
      'scopeId': scope,
      'id': cryptoWireRecordId(
        context.account.directory.session.profile.serverId,
        scope,
        'table',
        id,
      ),
      'accessRevision': head.accessRevision,
    });
    return {'lease': await _leaseWire(scope, reply['lease'])};
  }

  Future<Map<String, dynamic>?> _leaseWire(String scope, Object? raw) async {
    if (raw == null) return null;
    final value = Map<String, dynamic>.from(raw as Map);
    if (value['expiresAt'] is! int ||
        !isCryptoCanonicalUuid(value['holderAccountId']) ||
        !isCryptoCanonicalUuid(value['holderDeviceId'])) {
      throw const FormatException('crypto_table_lease');
    }
    final names = await context.database.rows(
      'SELECT data FROM members WHERE partition=? AND scope_id=? AND account_id=?',
      [p, scope, value['holderAccountId']],
    );
    final name = names.isEmpty
        ? ''
        : (jsonDecode(names.single['data'] as String) as Map)['displayName']
                  as String? ??
              '';
    return {
      ...value,
      'holderName': name,
      if (value['tokenBase64'] != null) 'token': value['tokenBase64'],
    }..remove('tokenBase64');
  }

  Future<Map<String, dynamic>> _write(
    String op,
    String action,
    Map<String, dynamic> payload,
  ) async {
    final id = await context.queue.enqueueCommand(
      actionKey: action,
      operation: op,
      payload: payload,
    );
    await context.queue.resumeUnresolved(requestIds: {id});
    return context.queue.commandResult(id);
  }

  Future<Map<String, dynamic>> _action(
    String op,
    Map<String, Object?> params,
    Future<Map<String, dynamic>> Function() build,
  ) async {
    final request = params['requestId'];
    if (!isCryptoCanonicalUuid(request)) {
      throw const FormatException('crypto_document_request_id');
    }
    final hash = await CryptoBusinessJson.hash({
      'operation': op,
      'params': params,
    });
    return context.database.transaction(() async {
      final prior = await context.database.rows(
        'SELECT * FROM crypto_document_actions WHERE partition=? AND request_id=?',
        [p, request],
      );
      if (prior.isNotEmpty) {
        if (prior.single['operation'] != op ||
            prior.single['request_hash'] != hash) {
          throw const FormatException('crypto_document_immutable_intent');
        }
        return {
          'intent': jsonDecode(prior.single['intent'] as String),
          if (prior.single['result'] != null)
            'result': jsonDecode(prior.single['result'] as String),
        };
      }
      final intent = await build();
      await context.database.execute(
        'INSERT INTO crypto_document_actions VALUES(?,?,?,?,?,NULL)',
        [p, request, op, hash, jsonEncode(intent)],
      );
      return {'intent': intent};
    });
  }

  Future<Map<String, dynamic>> _finishAction(
    String request,
    Map<String, dynamic> result,
  ) async {
    await context.database.execute(
      'UPDATE crypto_document_actions SET result=? WHERE partition=? AND request_id=?',
      [jsonEncode(result), p, request],
    );
    return result;
  }

  Future<Map<String, dynamic>> dispatch(
    String operation,
    Map<String, Object?> params,
  ) => withAccountWorkJob(
    context.account.directory.transport,
    AccountWorkKind.documents,
    () => _accountWorkDispatch(operation, params),
  );

  Future<Map<String, dynamic>> _accountWorkDispatch(
    String operation,
    Map<String, Object?> params,
  ) async {
    for (var attempt = 0; ; attempt++) {
      try {
        return await _dispatch(operation, params);
      } on CollaborationApiException catch (error) {
        context.access.invalidateBlobDelivery();
        if (error.code != 'rate_limited' || attempt >= 4) rethrow;
        final wait = error.details['retryAfter'];
        await Future<void>.delayed(
          Duration(
            seconds: wait is int
                ? wait.clamp(1, 60)
                : (2 << attempt).clamp(2, 30),
          ),
        );
        if (!context.account.directory.isCurrent()) {
          throw const CryptoAuthorityPending('crypto_identity_changed');
        }
      }
    }
  }

  Future<Map<String, dynamic>> _dispatch(
    String op,
    Map<String, Object?> params,
  ) async {
    final scope = params['scopeId'];
    if (!isCryptoCanonicalUuid(scope)) {
      throw const FormatException('crypto_document_scope');
    }
    final s = scope as String;
    if (op.startsWith('ideas.asset.')) return _idea(op, s, params);
    if (op.startsWith('attachments.')) return _attachment(op, s, params);
    if (op == 'tables.list' || op == 'tables.get') {
      await context.pullVerified(s, 'content');
      if (op == 'tables.list') {
        return {
          'sheets': [
            for (final row in await _records(s, 'table'))
              {..._sheet(row), 'cells': <String, String>{}},
          ],
        };
      }
      final id = params['id'] as String;
      return {
        'sheet': _sheet(await _raw(s, id, 'table')),
        ...await _lease(s, id),
      };
    }
    if (['tables.acquire', 'tables.renew', 'tables.release'].contains(op)) {
      final id = params['id'] as String,
          head = await context.access.currentHead(s, online: true);
      final operation = op.replaceFirst('tables.', 'crypto2.table.');
      final request =
          params['requestId'] as String? ??
          context.account.directory.reducer.crypto.randomId();
      final result = await _write(operation, '$operation:$id:$request', {
        'scopeId': s,
        'id': cryptoWireRecordId(
          context.account.directory.session.profile.serverId,
          s,
          'table',
          id,
        ),
        'domain': 'content',
        'epoch': head.epoch,
        'accessRevision': head.accessRevision,
        'membershipHeadHash': head.headHash,
        if (params['token'] != null) 'tokenBase64': params['token'],
      });
      if (op == 'tables.release') return result;
      return {'lease': await _leaseWire(s, result['lease'])};
    }
    if (['tables.create', 'tables.save', 'tables.delete'].contains(op)) {
      final id = params['id'] as String,
          request = params['requestId'] as String;
      final action = await _action(op, params, () async {
        final previous = await context.record(s, 'content', id, type: 'table'),
            expected = previous?['crypto_revision'] as int? ?? 0;
        if (op != 'tables.create' && params['expectedRevision'] != expected) {
          throw const CollaborationException('revision_conflict');
        }
        Map<String, dynamic>? raw;
        if (op != 'tables.delete') {
          final existing = previous?['raw_payload'] == null
              ? <String, dynamic>{}
              : Map<String, dynamic>.from(
                  jsonDecode(previous!['raw_payload'] as String) as Map,
                );
          raw = {
            ...existing,
            'id': id,
            'scopeId': s,
            'title': params['title'],
            'cells': params['cells'] ?? <String, String>{},
            'revision': expected + 1,
            'updatedAt': DateTime.now().millisecondsSinceEpoch ~/ 1000,
          }..remove('cryptoBlob');
          _table(raw);
        }
        return {'expectedRevision': expected, 'raw': raw};
      });
      if (action['result'] != null) {
        return Map<String, dynamic>.from(action['result'] as Map);
      }
      final expected = action['intent']['expectedRevision'] as int;
      Map<String, dynamic>? raw = action['intent']['raw'] == null
          ? null
          : Map<String, dynamic>.from(action['intent']['raw'] as Map);
      // Commit the full semantic table first. The shared encoder chooses
      // inline ciphertext or a payload blob after authorization commitments.
      final result = await context.publishRaw(
        scopeId: s,
        id: id,
        type: 'table',
        operationId: request,
        expectedRevision: expected,
        rawPayload: raw,
        localHash: await CryptoBusinessJson.hash({
          'operation': op,
          'params': params,
        }),
        tableLeases: expected == 0
            ? []
            : [
                {
                  'scopeId': s,
                  'id': cryptoWireRecordId(
                    context.account.directory.session.profile.serverId,
                    s,
                    'table',
                    id,
                  ),
                  'tokenBase64': params['token'],
                },
              ],
      );
      return _finishAction(
        request,
        op == 'tables.delete'
            ? {'deleted': true}
            : {'sheet': result['payload']},
      );
    }
    throw const CryptoAuthorityPending('crypto_document_operation_pending');
  }

  Future<Map<String, dynamic>> _attachment(
    String op,
    String scope,
    Map<String, Object?> params,
  ) async {
    bool matches(Map r) =>
        r['targetType'] == params['targetType'] &&
        r['targetId'] == params['targetId'];
    if (op == 'attachments.list' ||
        op == 'attachments.get' ||
        op == 'attachments.delete') {
      await context.pullVerified(scope, 'content');
      if (op == 'attachments.list') {
        return {
          'attachments': [
            for (final raw in await _records(scope, 'attachment'))
              if (matches(raw)) _sheet(raw),
          ],
        };
      }
      final id = params['id'] as String,
          raw = await _raw(scope, id, 'attachment');
      if (!matches(raw)) {
        throw const CollaborationException('attachment_unavailable');
      }
      if (op == 'attachments.delete') {
        final previous = (await context.record(
          scope,
          'content',
          id,
          type: 'attachment',
        ))!;
        await context.publishRaw(
          scopeId: scope,
          id: id,
          type: 'attachment',
          operationId: params['requestId'] as String,
          expectedRevision: previous['crypto_revision'] as int,
          rawPayload: null,
          localHash: await CryptoBusinessJson.hash({
            'operation': op,
            'params': params,
          }),
        );
        return {'deleted': true};
      }
      final bytes = await blobs.open(
        Map<String, dynamic>.from(raw['cryptoBlob'] as Map),
      );
      try {
        final offset = params['offset'] as int, limit = params['limit'] as int;
        if (offset < 0 ||
            offset >= bytes.length ||
            limit < 1 ||
            limit > attachmentChunkBytes) {
          throw const FormatException('crypto_attachment_offset');
        }
        return {
          'attachment': _sheet(raw),
          'offset': offset,
          'total': bytes.length,
          'dataBase64': base64Encode(
            Uint8List.sublistView(
              bytes,
              offset,
              (offset + limit).clamp(0, bytes.length),
            ),
          ),
        };
      } finally {
        bytes.fillRange(0, bytes.length, 0);
      }
    }
    final id = params['id'] as String;
    Map<String, dynamic>? completion;
    if (op == 'attachments.complete') {
      completion = await _action(op, params, () async {
        final previous = await context.record(
          scope,
          'content',
          id,
          type: 'attachment',
        );
        return {'expectedRevision': previous?['crypto_revision'] as int? ?? 0};
      });
      if (completion['result'] != null) {
        return Map<String, dynamic>.from(completion['result'] as Map);
      }
    }
    if (op == 'attachments.begin') {
      final metadata = <String, dynamic>{
        for (final key in [
          'id',
          'scopeId',
          'targetType',
          'targetId',
          'name',
          'mime',
          'size',
          'sha256',
        ])
          key: params[key],
        'createdAt': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'complete': false,
        'offset': 0,
      };
      validateAttachmentFile(
        metadata['name'],
        metadata['size'],
        mime: metadata['mime'],
      );
      AttachmentMetadata.fromJson(metadata);
      final existing = await context.database.rows(
        'SELECT metadata,received,state FROM crypto_document_uploads WHERE partition=? AND id=?',
        [p, id],
      );
      if (existing.isNotEmpty) {
        final old = jsonDecode(existing.single['metadata'] as String) as Map;
        for (final key in [
          'scopeId',
          'targetType',
          'targetId',
          'name',
          'mime',
          'size',
          'sha256',
        ]) {
          if (old[key] != metadata[key]) {
            throw const FormatException('crypto_attachment_immutable');
          }
        }
        return {
          'attachment': {
            ...old,
            'offset': existing.single['received'],
            'complete': existing.single['state'] == 'complete',
          },
        };
      }
      await context.database.execute(
        'INSERT INTO crypto_document_uploads VALUES(?,?,?,?,?,?)',
        [p, scope, id, jsonEncode(metadata), 0, 'receiving'],
      );
      return {'attachment': metadata};
    }
    final rows = await context.database.rows(
      'SELECT * FROM crypto_document_uploads WHERE partition=? AND id=?',
      [p, id],
    );
    if (rows.length != 1) {
      throw const CollaborationException('attachment_unavailable');
    }
    final row = rows.single,
        metadata = Map<String, dynamic>.from(
          jsonDecode(row['metadata'] as String) as Map,
        );
    if (row['scope_id'] != scope || !matches(metadata)) {
      throw const CollaborationException('attachment_unavailable');
    }
    if (op == 'attachments.chunk') {
      final offset = params['offset'] as int,
          bytes = base64Decode(params['dataBase64'] as String);
      if (bytes.isEmpty ||
          bytes.length > attachmentChunkBytes ||
          offset < 0 ||
          offset + bytes.length > metadata['size']) {
        throw const FormatException('crypto_attachment_chunk');
      }
      if (offset < (row['received'] as int)) {
        final prior = await context.database.rows(
          'SELECT bytes FROM crypto_document_upload_chunks WHERE partition=? AND id=? AND offset=?',
          [p, id, offset],
        );
        if (prior.length != 1 ||
            base64Encode((prior.single['bytes'] as List).cast<int>()) !=
                base64Encode(bytes)) {
          throw const FormatException('crypto_attachment_chunk_conflict');
        }
      } else {
        if (offset != row['received']) {
          throw const FormatException('crypto_attachment_offset');
        }
        await context.database.transaction(() async {
          await context.database.execute(
            'INSERT INTO crypto_document_upload_chunks VALUES(?,?,?,?)',
            [p, id, offset, bytes],
          );
          await context.database.execute(
            'UPDATE crypto_document_uploads SET received=? WHERE partition=? AND id=?',
            [offset + bytes.length, p, id],
          );
        });
      }
      return {
        'attachment': {
          ...metadata,
          'offset': (row['received'] as int) > offset + bytes.length
              ? row['received']
              : offset + bytes.length,
        },
      };
    }
    if (op == 'attachments.complete') {
      if (row['state'] == 'complete') {
        return {'attachment': _sheet(await _raw(scope, id, 'attachment'))};
      }
      if (row['received'] != metadata['size']) {
        throw const FormatException('crypto_attachment_incomplete');
      }
      final chunks = await context.database.rows(
            'SELECT offset,bytes FROM crypto_document_upload_chunks WHERE partition=? AND id=? ORDER BY offset',
            [p, id],
          ),
          builder = BytesBuilder(copy: false);
      for (final chunk in chunks) {
        if (chunk['offset'] != builder.length) {
          throw const FormatException('crypto_attachment_incomplete');
        }
        builder.add((chunk['bytes'] as List).cast<int>());
      }
      final bytes = builder.takeBytes();
      try {
        if (bytes.length != metadata['size'] ||
            await _sha(bytes) != metadata['sha256']) {
          throw const FormatException('crypto_attachment_hash');
        }
        final descriptor = await blobs.stage(
          scopeId: scope,
          recordId: id,
          operationId: id,
          kind: 'attachment',
          plaintext: bytes,
        );
        // The plaintext hash is verified locally and remains inside encryption.
        final plainHash = await _sha(bytes);
        if (plainHash != metadata['sha256']) {
          throw const FormatException('crypto_attachment_hash');
        }
        await blobs.upload(descriptor);
        final raw = {
          ...metadata,
          'complete': true,
          'offset': bytes.length,
          'cryptoBlob': descriptor,
        };
        final result = await context.publishRaw(
          scopeId: scope,
          id: id,
          type: 'attachment',
          operationId: params['requestId'] as String,
          expectedRevision: completion!['intent']['expectedRevision'] as int,
          rawPayload: raw,
          localHash: await CryptoBusinessJson.hash({
            'operation': op,
            'params': params,
          }),
        );
        await context.database.transaction(() async {
          await context.database.execute(
            "UPDATE crypto_document_uploads SET state='complete' WHERE partition=? AND id=?",
            [p, id],
          );
          await context.database.execute(
            'DELETE FROM crypto_document_upload_chunks WHERE partition=? AND id=?',
            [p, id],
          );
        });
        return await _finishAction(params['requestId'] as String, {
          'attachment': result['payload'],
        });
      } finally {
        bytes.fillRange(0, bytes.length, 0);
      }
    }
    throw const CryptoAuthorityPending('crypto_attachment_operation_pending');
  }

  Future<String> _sha(Uint8List bytes) async => cryptoSha256(bytes);
  Future<Map<String, dynamic>> _idea(
    String op,
    String scope,
    Map<String, Object?> params,
  ) async {
    final sha = params['sha256'] as String, workspace = 'shared:$p:$scope';
    if (op != 'ideas.asset.get') {
      final rows = await context.database.rows(
        'SELECT metadata,bytes FROM idea_assets WHERE workspace=? AND sha256=?',
        [workspace, sha],
      );
      if (rows.length != 1) {
        throw const CryptoAuthorityPending('idea_asset_missing');
      }
      final asset = IdeaAsset.fromJson(
        Map<String, dynamic>.from(
          jsonDecode(rows.single['metadata'] as String) as Map,
        ),
      );
      final bytes = Uint8List.fromList(
        (rows.single['bytes'] as List).cast<int>(),
      );
      try {
        if (asset.sha256 != sha) {
          throw const FormatException('crypto_idea_asset_hash');
        }
        await verifyIdeaAsset(asset, bytes);
        return {...asset.toJson(), 'offset': bytes.length, 'complete': true};
      } finally {
        bytes.fillRange(0, bytes.length, 0);
      }
    }
    await context.pullVerified(scope, 'content');
    final board = await _raw(scope, params['boardId'] as String, 'idea'),
        asset =
            (board['assets'] as List).singleWhere((a) => a['sha256'] == sha)
                as Map;
    if (asset['cryptoBlob'] is! Map) {
      throw const CryptoAuthorityPending('idea_asset_key_pending');
    }
    final bytes = await blobs.open(
      Map<String, dynamic>.from(asset['cryptoBlob'] as Map),
    );
    try {
      if (await _sha(bytes) != sha || bytes.length != asset['size']) {
        throw const FormatException('crypto_idea_asset_hash');
      }
      final offset = params['offset'] as int, limit = params['limit'] as int;
      if (offset < 0 || offset >= bytes.length || limit < 1 || limit > 262144) {
        throw const FormatException('crypto_idea_asset_offset');
      }
      final descriptor = IdeaAsset.fromJson({
        for (final field in ['sha256', 'mime', 'size', 'width', 'height'])
          field: asset[field],
      });
      await verifyIdeaAsset(descriptor, bytes);
      return {
        ...descriptor.toJson(),
        'offset': offset,
        'complete': true,
        'data': base64Encode(
          Uint8List.sublistView(
            bytes,
            offset,
            (offset + limit).clamp(0, bytes.length),
          ),
        ),
      };
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  }
}
