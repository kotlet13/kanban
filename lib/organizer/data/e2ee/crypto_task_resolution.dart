import 'dart:convert';

import 'package:sodium/sodium.dart';

import 'account_directory_v2.dart' show cryptoSha256;
import 'crypto_business_router.dart';
import 'crypto_business_json.dart';
import 'crypto_sync_repository.dart';
import 'session_crypto_access.dart';
import '../collaboration_database.dart';

/// Keyset traversal keeps memory bounded without permanently revisiting only
/// the first sixteen already resolved entries. Updating a payload never changes
/// its authenticated wire address, so it cannot move behind this cursor.
Stream<List<Map<String, Object?>>> cryptoTaskDerivationPages(
  CollaborationDatabase database,
  String partition,
  String scope,
) async* {
  String? after;
  while (true) {
    final rows = await database.rows(
      "SELECT * FROM crypto_business_records WHERE partition=? AND scope_id=? AND domain='finance' AND type IN ('financeEntry','personalFinanceEntry') AND deleted=0 AND json_extract(raw_payload,'\$.taskId') IS NOT NULL ${after == null ? '' : 'AND id>?'} ORDER BY id LIMIT 16",
      [partition, scope, if (after != null) after],
    );
    if (rows.isEmpty) return;
    yield rows;
    after = rows.last['id'] as String;
    if (rows.length < 16) return;
  }
}

/// A finance-authorized contributor seals this leg beside the canonical expense.
/// Content-only editors never receive a finance key or a private expense ID.
Future<Map<String, dynamic>> sealTaskResolution(
  CryptoBusinessSession context, {
  required String scopeId,
  required String batchId,
  required String operationId,
  required String entryId,
  required int revision,
  required String entryProofHash,
  required String taskId,
  required CryptoWriteContext write,
  required SecureKey signingKey,
  bool detached = false,
  Map<String, Object?>? stagedTask,
  Map<String, Object?>? stagedIntent,
}) async {
  final intentId = await context.reservedRecordId(
    scopeId,
    'taskDerivation:$taskId',
  );
  final intent =
      stagedIntent ??
      await context.record(
        scopeId,
        'content',
        intentId,
        type: 'taskDerivationIntent',
      );
  final task =
      stagedTask ??
      await context.record(scopeId, 'content', taskId, type: 'task');
  if (intent == null || task == null || (task['deleted'] == 1) != detached) {
    throw const CryptoProjectionPending();
  }
  final target = Map<String, dynamic>.from(
    jsonDecode(intent['raw_payload'] as String) as Map,
  );
  if (target['targetCryptoRevision'] != task['crypto_revision'] ||
      (target['deleted'] == true) != detached) {
    throw const CryptoProjectionPending();
  }
  final id = await context.reservedRecordId(scopeId, 'taskResolution:$taskId');
  final before = await context.record(
    scopeId,
    'finance',
    id,
    type: 'taskDerivationResolution',
  );
  final payload = {
    'version': 1,
    'taskId': taskId,
    'intentId': intentId,
    'targetOperationId': target['targetOperationId'],
    'targetCryptoRevision': target['targetCryptoRevision'],
    'intentProofHash': intent['record_proof_hash'],
    'taskProofHash': task['record_proof_hash'],
    'financeEntryId': entryId,
    'financeRecordProofHash': entryProofHash,
    'state': 'derived',
  };
  final refs =
      [
        {
          'scopeId': scopeId,
          'id': context.address(scopeId, 'content', 'task', taskId).wireId,
        },
        {
          'scopeId': scopeId,
          'id': context
              .address(scopeId, 'content', 'taskDerivationIntent', intentId)
              .wireId,
        },
        {
          'scopeId': scopeId,
          'id': context
              .address(scopeId, 'finance', 'financeEntry', entryId)
              .wireId,
        },
      ]..sort(
        (a, b) => '${a['scopeId']}/${a['id']}'.compareTo(
          '${b['scopeId']}/${b['id']}',
        ),
      );
  final versions =
      [
        for (final pair in [
          (taskId, 'content', task),
          (intentId, 'content', intent),
        ])
          {
            'scopeId': scopeId,
            'id': context
                .address(
                  scopeId,
                  pair.$2,
                  pair.$1 == taskId ? 'task' : 'taskDerivationIntent',
                  pair.$1,
                )
                .wireId,
            'domain': pair.$2,
            'revision': pair.$3['crypto_revision'],
            'recordProofHash': pair.$3['record_proof_hash'],
          },
        {
          'scopeId': scopeId,
          'id': context
              .address(scopeId, 'finance', 'financeEntry', entryId)
              .wireId,
          'domain': 'finance',
          'revision': revision,
          'recordProofHash': entryProofHash,
        },
      ]..sort(
        (a, b) => '${a['scopeId']}/${a['domain']}/${a['id']}'.compareTo(
          '${b['scopeId']}/${b['domain']}/${b['id']}',
        ),
      );
  final recordAddress = context.address(
    scopeId,
    'finance',
    'taskDerivationResolution',
    id,
  );
  final bytes = CryptoBusinessJson.encode({
    'format': 2,
    'identity': recordAddress.identity,
    'payload': payload,
  });
  try {
    return context.codec.sealRecord(
      serverId: context.account.directory.session.profile.serverId,
      accountId: context.account.directory.accountId,
      deviceId: context.account.deviceId,
      batchId: batchId,
      scopeId: scopeId,
      id: recordAddress.wireId,
      type: 'taskDerivationResolution',
      expectedRevision: before?['crypto_revision'] as int? ?? 0,
      epoch: write.epoch,
      accessRevision: write.accessRevision,
      membershipHeadHash: write.headHash,
      domain: 'finance',
      contentContract: 3,
      operationId: operationId,
      previousRecordHash: before?['record_proof_hash'] as String? ?? '0' * 64,
      deleted: false,
      plaintext: bytes,
      metadata: {
        'identity': recordAddress.identity,
        'auditState': {
          'version': 1,
          'changedAt': DateTime.now().toUtc().toIso8601String(),
        },
        'references': refs,
        'referenceVersions': versions,
        'uniqueRefs': [
          await cryptoSha256(
            utf8.encode(
              'JivieTaskResolution/v2\n$scopeId:${intent['record_proof_hash']}',
            ),
          ),
        ],
        'blobIds': <String>[],
      },
      contentKey: write.key.key,
      signingKey: signingKey,
    );
  } finally {
    bytes.fillRange(0, bytes.length, 0);
  }
}
