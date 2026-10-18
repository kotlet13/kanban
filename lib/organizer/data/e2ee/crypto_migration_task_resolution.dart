import 'package:sodium/sodium.dart';

import 'crypto_business_json.dart';
import 'crypto_business_router.dart';
import 'crypto_sync_repository.dart';
import 'scope_crypto_codec.dart';
import 'crypto_migration_prepared_target.dart';

/// A closed companion of an existing captured expense, never a new expense.
/// A legacy mismatch stays unresolved; it is not silently corrected at capture.
Future<Map<String, dynamic>?> sealCapturedTaskResolution({
  required CryptoBusinessSession context,
  required String migrationId,
  required String scopeId,
  required String entryId,
  required Map<String, dynamic> expense,
  required String expenseProofHash,
  required String batchId,
  required String operationId,
  required VerifiedScopeHead head,
  required SecureKey financeKey,
  required SecureKey signingKey,
  required List<String> witnessBlobIds,
  required Map<String, dynamic> migrationTag,
}) async {
  if (expense['taskId'] == null) return null;
  final taskId = expense['taskId'] as String;
  final intentId = await context.reservedRecordId(
    scopeId,
    'taskDerivation:$taskId',
  );
  Future<({Map<String, dynamic> record, Map<String, dynamic> raw, String hash})>
  staged(String type, String id) async {
    final value = await prepareCryptoMigrationTarget(
      context: context,
      migrationId: migrationId,
      scopeId: scopeId,
      domain: 'content',
      wireId: context.address(scopeId, 'content', type, id).wireId,
    );
    if (value.record['type'] != type ||
        value.record['membershipHeadHash'] != head.headHash ||
        value.record['deleted'] != false ||
        value.raw == null) {
      throw const FormatException('crypto_migration_task_anchor');
    }
    return (record: value.record, raw: value.raw!, hash: value.proofHash);
  }

  final task = await staged('task', taskId),
      intent = await staged('taskDerivationIntent', intentId);
  final deadline = expense['plannedAt'] == null
      ? null
      : DateTime.parse(
              expense['plannedAt'] as String,
            ).toUtc().millisecondsSinceEpoch ~/
            1000;
  if (expense['kind'] != 'expense' ||
      intent.raw['deleted'] != false ||
      intent.raw['taskId'] != taskId ||
      intent.raw['targetOperationId'] != task.record['operationId'] ||
      intent.raw['targetCryptoRevision'] != 1) {
    throw const CryptoProjectionPending();
  }
  final id = await context.reservedRecordId(scopeId, 'taskResolution:$taskId');
  final raw = <String, dynamic>{
    'version': 1,
    'taskId': taskId,
    'intentId': intentId,
    'targetOperationId': intent.raw['targetOperationId'],
    'targetCryptoRevision': 1,
    'intentProofHash': intent.hash,
    'taskProofHash': task.hash,
    'financeEntryId': entryId,
    'financeRecordProofHash': expenseProofHash,
    'state': deadline == intent.raw['deadlineEpoch']
        ? 'derived'
        : 'legacyPending',
  };
  final refs = context.referencesFor(scopeId, 'taskDerivationResolution', raw);
  final versions =
      <Map<String, dynamic>>[
        for (final value in [task, intent])
          {
            'scopeId': scopeId,
            'domain': 'content',
            'id': value.record['id'],
            'revision': 1,
            'recordProofHash': value.hash,
          },
        {
          'scopeId': scopeId,
          'domain': 'finance',
          'id': context
              .address(scopeId, 'finance', 'financeEntry', entryId)
              .wireId,
          'revision': 1,
          'recordProofHash': expenseProofHash,
        },
      ]..sort(
        (a, b) => '${a['scopeId']}/${a['domain']}/${a['id']}'.compareTo(
          '${b['scopeId']}/${b['domain']}/${b['id']}',
        ),
      );
  final metadata = await context.businessMetadata(
    scopeId: scopeId,
    domain: 'finance',
    type: 'taskDerivationResolution',
    canonicalId: id,
    expectedRevision: 0,
    rawPayload: raw,
    stagedReferenceVersions: versions,
  );
  metadata.remove('auditState');
  metadata['migrationOrigin'] = migrationTag;
  metadata['references'] = refs;
  metadata['blobIds'] = [...witnessBlobIds]..sort();
  final address = context.address(
    scopeId,
    'finance',
    'taskDerivationResolution',
    id,
  );
  final bytes = CryptoBusinessJson.encode({
    'format': 2,
    'identity': address.identity,
    'payload': raw,
  });
  try {
    return context.codec.sealRecord(
      serverId: context.account.directory.session.profile.serverId,
      accountId: context.account.directory.accountId,
      deviceId: context.account.deviceId,
      batchId: batchId,
      scopeId: scopeId,
      id: address.wireId,
      type: 'taskDerivationResolution',
      expectedRevision: 0,
      epoch: head.epoch,
      accessRevision: head.accessRevision,
      membershipHeadHash: head.headHash,
      domain: 'finance',
      contentContract: 3,
      operationId: operationId,
      previousRecordHash: '0' * 64,
      deleted: false,
      plaintext: bytes,
      metadata: metadata,
      contentKey: financeKey,
      signingKey: signingKey,
    );
  } finally {
    bytes.fillRange(0, bytes.length, 0);
  }
}
