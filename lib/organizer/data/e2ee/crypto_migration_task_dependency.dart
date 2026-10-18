import 'dart:convert';

import 'crypto_business_router.dart';
import 'crypto_json.dart';
import 'crypto_migration_stage_verifier.dart';
import 'crypto_sync_repository.dart';
import 'session_crypto_access.dart';

/// Existing scoped stagedRecords is routing only. Only the exact owner-signed
/// task+intent batch accepted by verifyTaskDependency supplies a reference.
Future<List<CryptoProjectionRecord>> _readTaskDependency({
  required CryptoBusinessSession context,
  required String migrationId,
  required String scopeId,
  required String taskWire,
  String? taskHash,
  String? intentHash,
  CryptoMigrationCandidate? preparing,
}) async {
  String? after;
  var count = 0;
  while (true) {
    final page = await context.account.directory
        .call('crypto2.migration.stagedRecords', {
          'migrationId': migrationId,
          'scopeId': scopeId,
          'domain': 'content',
          'limit': 20,
          if (after != null) 'afterId': after,
        });
    if (page['migrationId'] != migrationId ||
        page['scopeId'] != scopeId ||
        page['domain'] != 'content' ||
        page['stages'] is! List ||
        (page['stages'] as List).length > 20) {
      throw const FormatException('crypto_migration_task_dependency_page');
    }
    for (final item in page['stages'] as List) {
      if (++count > 1000000) {
        throw const CryptoAuthorityPending(
          'crypto_migration_dependencies_capacity',
        );
      }
      final authorization = Map<String, dynamic>.from(
            (item as Map)['authorization'],
          ),
          command =
              CryptoJson.decode(cryptoBase64(authorization['commandBase64']))
                  as Map,
          records = command['payload']['batch']['records'] as List;
      final matches = records.where((proof) {
        final body =
            CryptoJson.decode(cryptoBase64((proof as Map)['commandBase64']))
                as Map;
        return body['id'] == taskWire;
      }).toList();
      if (matches.isEmpty) continue;
      if (matches.length != 1) {
        throw const FormatException('crypto_migration_task_dependency');
      }
      return CryptoMigrationStageVerifier(context).verifyTaskDependency(
        migrationId: migrationId,
        scopeId: scopeId,
        taskWireId: taskWire,
        authorization: authorization,
        expectedTaskHash: taskHash,
        expectedIntentHash: intentHash,
        preparing: preparing,
      );
    }
    if (page['hasMore'] == false) break;
    final next = page['nextAfterId'];
    if (page['hasMore'] != true ||
        next is! String ||
        next.isEmpty ||
        after != null && next.compareTo(after) <= 0 ||
        (page['stages'] as List).isEmpty) {
      throw const FormatException('crypto_migration_task_dependency_cursor');
    }
    after = next;
  }
  throw const CryptoAuthorityPending('crypto_migration_dependencies_pending');
}

/// No live projection: retain the verified original signed proofs solely for
/// canonical reference versions and the source-bound task resolution producer.
Future<void> prepareCapturedTaskDependency({
  required CryptoBusinessSession context,
  required String migrationId,
  required String captureId,
  required String scopeId,
  required String taskId,
}) async {
  final taskWire = context.address(scopeId, 'content', 'task', taskId).wireId,
      existing = await context.db.rows(
        'SELECT record_proof FROM crypto_migration_staged_records WHERE partition=? AND migration_id=? AND scope_id=? AND domain=? AND record_id=?',
        [context.partition, migrationId, scopeId, 'content', taskWire],
      );
  if (existing.length == 1) {
    final proof = jsonDecode(existing.single['record_proof'] as String) as Map,
        body = CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map;
    if (body['accountId'] == context.account.directory.accountId &&
        body['metadata']['migrationOrigin']['captureId'] == captureId) {
      return;
    }
  }
  final candidate = await context.access.migrationCandidate(
    scopeId: scopeId,
    migrationId: migrationId,
    captureId: captureId,
  );
  final values = await _readTaskDependency(
    context: context,
    migrationId: migrationId,
    scopeId: scopeId,
    taskWire: taskWire,
    preparing: candidate,
  );
  try {
    await context.db.transaction(() async {
      for (final value in values) {
        final r = value.record,
            proof = (value.wire['authorization'] as Map)['recordProof'],
            commitment =
                (value.wire['authorization'] as Map)['batchCommitment'],
            hash = await context.codec.digest(Map<String, dynamic>.from(proof));
        final key = [
              context.partition,
              migrationId,
              scopeId,
              'content',
              r['id'],
            ],
            previous = await context.db.rows(
              'SELECT record_proof_hash FROM crypto_migration_staged_records WHERE partition=? AND migration_id=? AND scope_id=? AND domain=? AND record_id=?',
              key,
            );
        if (previous.isNotEmpty &&
            previous.single['record_proof_hash'] != hash) {
          throw const FormatException('crypto_migration_stage_immutable');
        }
        // The companion uses its primary source binding; both are closed over
        // the exact same verified original batch commitment.
        final primary = values.singleWhere((v) => v.record['type'] == 'task');
        await context.db.execute(
          'INSERT OR IGNORE INTO crypto_migration_staged_records VALUES(?,?,?,?,?,?,?,?,?)',
          [
            ...key,
            hash,
            jsonEncode(proof),
            jsonEncode(commitment),
            jsonEncode(primary.migrationOrigin),
          ],
        );
      }
    });
  } finally {
    for (final value in values) {
      value.plaintext?.fillRange(0, value.plaintext!.length, 0);
    }
  }
}

/// Called only inside the already verified own FILE/frozen scope. The exact
/// hashes come from the reader's own signed financial batch. No foreign source
/// binding, artifact or object is added to that account's parity/control fold.
Future<void> projectCapturedTaskDependency({
  required CryptoBusinessSession context,
  required String migrationId,
  required String scopeId,
  required String taskId,
  required String taskHash,
  required String intentHash,
}) async {
  await context.access.requireReadOnlyFrozenScope(scopeId);
  final taskWire = context.address(scopeId, 'content', 'task', taskId).wireId,
      intentId = await context.reservedRecordId(
        scopeId,
        'taskDerivation:$taskId',
      ),
      intentWire = context
          .address(scopeId, 'content', 'taskDerivationIntent', intentId)
          .wireId;
  final rows = await context.db.rows(
    'SELECT id,record_proof_hash FROM crypto_business_records WHERE partition=? AND scope_id=? AND domain=? AND id IN (?,?)',
    [context.partition, scopeId, 'content', taskWire, intentWire],
  );
  if (rows.length == 2) {
    if (rows.singleWhere((r) => r['id'] == taskWire)['record_proof_hash'] !=
            taskHash ||
        rows.singleWhere((r) => r['id'] == intentWire)['record_proof_hash'] !=
            intentHash) {
      throw const FormatException('crypto_migration_task_dependency');
    }
    return;
  }
  final values = await _readTaskDependency(
    context: context,
    migrationId: migrationId,
    scopeId: scopeId,
    taskWire: taskWire,
    taskHash: taskHash,
    intentHash: intentHash,
  );
  try {
    await context.prepareRecords?.call(values);
    await context.db.transaction(() => context.project(values));
  } finally {
    for (final value in values) {
      value.plaintext?.fillRange(0, value.plaintext!.length, 0);
    }
  }
}
