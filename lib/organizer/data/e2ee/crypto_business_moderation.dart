import 'dart:convert';
import 'dart:typed_data';

import '../../domain/idea_models.dart';
import 'account_directory_v2.dart' show cryptoSha256;
import 'crypto_business_documents.dart';
import 'crypto_business_json.dart';
import 'crypto_business_payload.dart';
import 'crypto_business_router.dart';
import 'crypto_record_address.dart';
import 'crypto_sync_repository.dart';
import 'session_crypto_access.dart';

/// Existing report preview remains the explicit disclosure review boundary.
/// Only selected semantic fields and reviewed image bytes reach moderation.
class CryptoBusinessModeration {
  CryptoBusinessModeration(this.context);
  final CryptoBusinessSession context;
  static const operations = {'moderation.reportPreview', 'moderation.report'};
  static const deliveryOperations = {
    'crypto2.moderation.report',
    'crypto2.moderation.disclosure.begin',
    'crypto2.moderation.disclosure.chunk',
    'crypto2.moderation.disclosure.complete',
    'crypto2.moderation.disclosure.abort',
  };
  bool supports(String operation) => operations.contains(operation);

  /// Safety reporting needs current own identity and READ, never content edit,
  /// a new DEK grant, or verified-email/business-upload consent.
  static Future<void> verifyDelivery(
    SessionCryptoAccess access,
    Map<String, dynamic> command,
  ) async {
    final operation = command['operation'];
    if (!deliveryOperations.contains(operation)) {
      throw const FormatException('crypto_moderation_operation');
    }
    final own = await access.account.directory.requireFresh();
    own.activeDevice(access.account.deviceId);
    final payload = command['payload'] as Map;
    Map? selected;
    if (operation == 'crypto2.moderation.report' ||
        operation == 'crypto2.moderation.disclosure.begin') {
      selected = payload['sourceContext'] as Map;
    } else {
      final stage = payload['stageId'];
      final rows = await access.account.store.database.rows(
        "SELECT payload FROM crypto_membership_intents WHERE partition=? AND state='moderationPreview' AND CAST(payload AS TEXT) LIKE ?",
        [access.account.store.partition, '%$stage%'],
      );
      for (final row in rows) {
        final value =
            jsonDecode(utf8.decode((row['payload'] as List).cast<int>()))
                as Map;
        if (value['snapshotStageId'] == stage ||
            (value['assets'] as List? ?? const []).any(
              (a) => (a as Map)['stageId'] == stage,
            )) {
          if (selected != null) {
            throw const FormatException('crypto_report_stage_ambiguous');
          }
          selected = value['sourceContext'] as Map;
        }
      }
    }
    if (selected == null) {
      throw const CryptoAuthorityPending('crypto_report_review_missing');
    }
    if (operation == 'crypto2.moderation.disclosure.abort') return;
    final scope = selected['scopeId'] as String;
    final head = await access.currentHead(scope, online: true);
    if (head.headHash != selected['membershipHeadHash']) {
      throw const CryptoAuthorityPending('report_preview_changed');
    }
    final domain = selected['domain'] as String? ?? 'content';
    await access.readContext(scope, domain);
    if (selected['targetType'] == 'user') {
      head.member(selected['targetId'] as String);
      return;
    }
    final rows = await access.account.store.database.rows(
      'SELECT crypto_revision,record_proof_hash,deleted FROM crypto_business_records WHERE partition=? AND scope_id=? AND domain=? AND id=?',
      [access.account.store.partition, scope, domain, selected['targetId']],
    );
    if (rows.length != 1 ||
        rows.single['deleted'] == 1 ||
        rows.single['crypto_revision'] != selected['targetRevision'] ||
        rows.single['record_proof_hash'] != selected['recordProofHash']) {
      throw const CryptoAuthorityPending('report_preview_changed');
    }
  }

  Future<Map<String, dynamic>> dispatch(
    String operation,
    Map<String, Object?> params,
  ) async {
    if (!supports(operation) || !isCryptoCanonicalUuid(params['scopeId'])) {
      throw const FormatException('crypto_moderation_operation');
    }
    return operation == 'moderation.reportPreview'
        ? _preview(params)
        : _report(params);
  }

  /// Explicit closed allowlist excludes every blob key, ciphertext, witness and
  /// unknown extension. Selected evidence is not a server-verified plaintext.
  static Map<String, dynamic> selectEvidence(String type, Map projection) {
    final source = projection['payload'] is Map
        ? projection['payload'] as Map
        : projection;
    const fields = {
      'id',
      'type',
      'title',
      'name',
      'notes',
      'description',
      'revision',
      'createdAt',
      'updatedAt',
      'archived',
      'isCompleted',
      'completedAt',
      'deadline',
      'startAt',
      'endAt',
      'startsAt',
      'endsAt',
      'location',
      'quantity',
      'unit',
      'isChecked',
      'address',
      'amountMinor',
      'currency',
      'kind',
      'occurredOn',
      'paidAt',
      'status',
      'fileName',
      'mime',
      'size',
      'cells',
      'rowCount',
      'columnCount',
      'username',
      'displayName',
      'role',
    };
    final result = <String, dynamic>{
      for (final key in fields)
        if (source.containsKey(key) &&
            source[key] is! Map &&
            source[key] is! List)
          key: source[key],
    };
    if (type == 'table' && source['cells'] is Map) {
      final cells = source['cells'] as Map;
      if (cells.keys.any((k) => k is! String) ||
          cells.values.any((v) => v is! String)) {
        throw const FormatException('crypto_report_cells');
      }
      result['cells'] = Map<String, dynamic>.from(cells);
    }
    return result;
  }

  Future<Map<String, dynamic>> _preview(Map<String, Object?> params) async {
    final scope = params['scopeId'] as String;
    final canonical = params['targetId'];
    final kind = params['targetType'];
    if (!isCryptoCanonicalUuid(canonical) ||
        !const {
          'record',
          'finance',
          'table',
          'attachment',
          'user',
        }.contains(kind)) {
      throw const FormatException('crypto_moderation_target');
    }
    late String type, wire;
    late Map<String, dynamic> evidence;
    Map<String, Object?>? row;
    if (kind == 'user') {
      final head = await context.access.currentHead(scope, online: true);
      final member = head.member(canonical as String);
      type = 'user';
      wire = canonical;
      evidence = selectEvidence(type, member);
    } else {
      final domain = kind == 'finance' ? 'finance' : 'content';
      await context.pullVerified(scope, domain, attest: false);
      row = await context.record(
        scope,
        domain,
        canonical as String,
        type: kind == 'table' || kind == 'attachment' ? kind as String : null,
      );
      if (row == null || row['deleted'] == 1) {
        throw const CryptoAuthorityPending('crypto_report_target_pending');
      }
      type = row['type'] as String;
      wire = context.address(scope, domain, type, canonical).wireId;
      evidence = selectEvidence(
        type,
        jsonDecode(row['projection'] as String) as Map,
      );
    }
    final remote = await context.account.directory.call(
      'crypto2.moderation.reportPreview',
      {'scopeId': scope, 'targetType': kind, 'targetId': wire},
    );
    final source = Map<String, dynamic>.from(remote['sourceContext'] as Map);
    final head = await context.access.currentHead(scope, online: true);
    if (source['scopeId'] != scope ||
        source['targetId'] != wire ||
        source['targetType'] != kind ||
        source['type'] != type ||
        source['membershipHeadHash'] != head.headHash ||
        row != null &&
            (source['targetRevision'] != row['crypto_revision'] ||
                source['recordProofHash'] != row['record_proof_hash'])) {
      throw const CryptoAuthorityPending('report_preview_changed');
    }
    final crypto = context.account.directory.reducer.crypto;
    // This opaque token remains local; no low-entropy plaintext hash is sent.
    final token = await cryptoSha256(
      utf8.encode('${crypto.randomId()}:${crypto.randomId()}'),
    );
    final title =
        (evidence['title'] ?? evidence['name'] ?? evidence['fileName'] ?? type)
            .toString();
    final disclosure = {
      'subject': {'title': title, 'type': type},
      'evidence': evidence,
    };
    final assets = <Map<String, dynamic>>[];
    if (type == 'idea' && row != null) {
      final board = IdeaBoard.fromJson(
        CryptoBusinessPayload.projection(
          'content',
          'idea',
          Map<String, dynamic>.from(
            (jsonDecode(row['projection'] as String) as Map)['payload'] as Map,
          ),
        ),
      );
      final byHash = <String, IdeaAsset>{};
      for (final asset in board.assets) {
        final prior = byHash[asset.sha256];
        if (prior != null &&
            jsonEncode(prior.toJson()) != jsonEncode(asset.toJson())) {
          throw const FormatException('crypto_report_asset_descriptor');
        }
        byHash[asset.sha256] = asset;
      }
      final selected = byHash.values.toList()
        ..sort((a, b) => a.sha256.compareTo(b.sha256));
      evidence.clear();
      evidence.addAll({
        'board': board.toJson(),
        'assets': [for (final asset in selected) asset.toJson()],
      });
      for (final asset in selected) {
        assets.add({
          'descriptor': asset.toJson(),
          'stageId': crypto.randomId(),
        });
      }
    }
    final value = {
      'sourceContext': source,
      'canonicalId': canonical,
      'disclosure': disclosure,
      'snapshotStageId': crypto.randomId(),
      'assets': assets,
    };
    await context.database.execute(
      'INSERT INTO crypto_membership_intents VALUES(?,?,?,?,?,NULL)',
      [
        context.partition,
        scope,
        'moderationPreview:$token',
        'moderationPreview',
        Uint8List.fromList(utf8.encode(jsonEncode(value))),
      ],
    );
    final session = context.account.directory.session.profile;
    return {
      'serverId': session.serverId,
      'accountId': session.accountId,
      'scopeId': scope,
      'targetType': kind,
      'targetId': canonical,
      'targetRevision': source['targetRevision'],
      'previewHash': token,
      'subject': disclosure['subject'],
      'evidence': evidence,
      'recipient': remote['recipient'],
    };
  }

  Future<Map<String, dynamic>> _send(
    String operation,
    String actionKey,
    Map<String, dynamic> payload,
  ) async {
    if (!deliveryOperations.contains(operation)) {
      throw const FormatException('crypto_moderation_operation');
    }
    final request = await context.queue.enqueueCommand(
      actionKey: actionKey,
      operation: operation,
      payload: payload,
    );
    await context.queue.resumeUnresolved(requestIds: {request});
    return context.queue.commandResult(request);
  }

  Future<Map<String, dynamic>> _report(Map<String, Object?> params) async {
    final scope = params['scopeId'] as String;
    final request = params['requestId'];
    final token = params['previewHash'];
    if (!isCryptoCanonicalUuid(request) ||
        token is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(token) ||
        !const {
          'harassment',
          'hate',
          'sexual',
          'violence',
          'illegal',
          'spam',
          'privacy',
          'other',
        }.contains(params['reason']) ||
        params['details'] is! String ||
        utf8.encode(params['details'] as String).length > 2000) {
      throw const FormatException('crypto_moderation_report');
    }
    final rows = await context.database.rows(
      "SELECT payload FROM crypto_membership_intents WHERE partition=? AND scope_id=? AND intent_id=? AND state='moderationPreview'",
      [context.partition, scope, 'moderationPreview:$token'],
    );
    if (rows.length != 1) {
      throw const CryptoAuthorityPending('crypto_report_review_missing');
    }
    final value =
        jsonDecode(utf8.decode((rows.single['payload'] as List).cast<int>()))
            as Map;
    final source = Map<String, dynamic>.from(value['sourceContext'] as Map);
    if (source['targetType'] != params['targetType'] ||
        value['canonicalId'] != params['targetId']) {
      throw const FormatException('crypto_report_review_mismatch');
    }
    final directory = await context.account.directory.requireFresh();
    final workflow = value['workflow'];
    if (workflow == null) {
      value['workflow'] = {
        'requestId': request,
        'reason': params['reason'],
        'details': params['details'],
        'authorDirectoryHeadHash': directory.headHash,
      };
      await context.database.execute(
        'UPDATE crypto_membership_intents SET payload=? WHERE partition=? AND scope_id=? AND intent_id=?',
        [
          Uint8List.fromList(utf8.encode(jsonEncode(value))),
          context.partition,
          scope,
          'moderationPreview:$token',
        ],
      );
    } else if ((workflow as Map)['requestId'] != request ||
        workflow['reason'] != params['reason'] ||
        workflow['details'] != params['details']) {
      throw const FormatException('crypto_report_review_mismatch');
    }
    final authorReference =
        (value['workflow'] as Map)['authorDirectoryHeadHash'];
    final reportPayload = <String, dynamic>{
      'reportId': request,
      'sourceContext': source,
      'authorDirectoryHeadHash': authorReference,
      'consentVersion': 1,
      'disclosure': null,
      'snapshotStageId': value['snapshotStageId'],
      'assetStageIds': [
        for (final asset in value['assets'] as List? ?? const [])
          (asset as Map)['stageId'],
      ],
      'reason': params['reason'],
      'details': params['details'],
    };
    final existing = await context.database.rows(
      'SELECT request_id FROM crypto_command_keys WHERE partition=? AND action_key=?',
      [context.partition, 'moderation:$request:report'],
    );
    if (existing.isNotEmpty) {
      // This exact final command was durably staged only after all selected
      // uploads completed. Reconcile its own receipt before reopening images.
      // Unknown outcomes still pass the queue's fresh source/authority guard.
      return _send(
        'crypto2.moderation.report',
        'moderation:$request:report',
        reportPayload,
      );
    }
    for (final rawAsset in value['assets'] as List? ?? const []) {
      final asset = Map<String, dynamic>.from(rawAsset as Map);
      final descriptor = asset['descriptor'] as Map;
      final bytes = BytesBuilder(copy: false);
      while (bytes.length < (descriptor['size'] as int)) {
        final chunk = await CryptoBusinessDocuments(context)
            .dispatch('ideas.asset.get', {
              'scopeId': scope,
              'boardId': value['canonicalId'],
              'sha256': descriptor['sha256'],
              'offset': bytes.length,
              'limit': 196608,
            });
        final data = base64Decode(chunk['data'] as String);
        if (data.isEmpty ||
            bytes.length + data.length > descriptor['size'] ||
            chunk['sha256'] != descriptor['sha256']) {
          throw const FormatException('crypto_report_asset_changed');
        }
        bytes.add(data);
      }
      final data = bytes.takeBytes();
      try {
        if (await cryptoSha256(data) != descriptor['sha256']) {
          throw const FormatException('crypto_report_asset_changed');
        }
        await _upload(
          scope,
          request as String,
          source,
          authorReference as String,
          asset['stageId'] as String,
          'asset',
          descriptor['mime'] as String,
          data,
          'asset:${descriptor['sha256']}',
        );
      } finally {
        data.fillRange(0, data.length, 0);
      }
    }
    final snapshot = CryptoBusinessJson.encode(value['disclosure']);
    if (snapshot.length > 2097152) {
      throw const FormatException('crypto_report_disclosure_limit');
    }
    final stage = value['snapshotStageId'] as String;
    // Stage semantic JSON bytes, keeping floats out of command canonicalization.
    await _upload(
      scope,
      request as String,
      source,
      authorReference as String,
      stage,
      'snapshot',
      'application/json',
      snapshot,
      'snapshot',
    );
    return _send(
      'crypto2.moderation.report',
      'moderation:$request:report',
      reportPayload,
    );
  }

  Future<void> _upload(
    String scope,
    String report,
    Map<String, dynamic> source,
    String author,
    String stage,
    String kind,
    String mime,
    Uint8List bytes,
    String suffix,
  ) async {
    if (bytes.length > 2097152) {
      throw const FormatException('crypto_report_disclosure_limit');
    }
    final key = 'moderation:$report:$suffix';
    await _send('crypto2.moderation.disclosure.begin', '$key:begin', {
      'stageId': stage,
      'reportId': report,
      'sourceContext': source,
      'authorDirectoryHeadHash': author,
      'consentVersion': 1,
      'kind': kind,
      'mime': mime,
      'size': bytes.length,
      'sha256': await cryptoSha256(bytes),
    });
    for (var offset = 0; offset < bytes.length; offset += 196608) {
      final end = offset + 196608 < bytes.length
          ? offset + 196608
          : bytes.length;
      await _send('crypto2.moderation.disclosure.chunk', '$key:chunk:$offset', {
        'stageId': stage,
        'offset': offset,
        'dataBase64': base64Encode(Uint8List.sublistView(bytes, offset, end)),
      });
    }
    await _send('crypto2.moderation.disclosure.complete', '$key:complete', {
      'stageId': stage,
    });
  }
}
