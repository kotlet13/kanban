import 'dart:convert';

import 'package:cryptography/cryptography.dart' show Sha256;

import '../domain/collaboration_models.dart';
import 'collaboration_database.dart';
import 'collaboration_sync_diagnostics.dart';
import 'device_session_store.dart';
import 'e2ee/crypto_business_json.dart';
import 'e2ee/crypto_json.dart';
import 'e2ee/crypto_record_address.dart';

/// Local work selection, never cryptographic admission or permission evidence.
/// Only the existing ordinary push may replay these immutable requests.
class CollaborationPendingSyncSelection {
  const CollaborationPendingSyncSelection(this.scopes, this.fallback);
  final Map<String, Set<String>> scopes;
  final CollaborationRecoveryFallback? fallback;

  static Future<CollaborationPendingSyncSelection> read({
    required CollaborationDatabase database,
    required DeviceSession session,
    required List<SharedScope> scopes,
    required bool sharedUploadsAllowed,
  }) => database.transaction(() async {
    final p = session.profile.partition;
    final inventory = await database.rows(
      "SELECT request_id,operation,LENGTH(CAST(signed_body AS BLOB)) AS bytes FROM crypto_outbox WHERE partition=? AND state='pending' ORDER BY sequence LIMIT 65",
      [p],
    );
    CollaborationPendingSyncSelection fallback(
      CollaborationRecoveryFallback why,
    ) => CollaborationPendingSyncSelection(const {}, why);
    if (inventory.length > 64 ||
        inventory.fold<int>(0, (n, r) => n + (r['bytes'] as int)) > 1048576) {
      return fallback(CollaborationRecoveryFallback.inventoryLimit);
    }
    final known = {for (final s in scopes) s.id: s};
    final selected = <String, Set<String>>{};
    final ordinary = {
      'project',
      'task',
      'event',
      'shoppingList',
      'shoppingItem',
      'householdPerson',
      'idea',
      'garden',
    };
    try {
      for (final item in inventory) {
        if (item['operation'] != 'crypto2.records.batch') {
          return fallback(CollaborationRecoveryFallback.unsupportedCommand);
        }
        final row = (await database.rows(
          'SELECT * FROM crypto_outbox WHERE partition=? AND request_id=?',
          [p, item['request_id']],
        )).single;
        final signed = jsonDecode(row['signed_body'] as String) as Map;
        if (signed.length != 2 ||
            !signed.containsKey('commandBase64') ||
            !signed.containsKey('signatureBase64')) {
          return fallback(CollaborationRecoveryFallback.invalidEvidence);
        }
        cryptoBase64(signed['signatureBase64'], length: 64);
        final bytes = cryptoBase64(signed['commandBase64']);
        final hash = (await Sha256().hash(
          bytes,
        )).bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
        final command = CryptoJson.decode(bytes) as Map;
        if (hash != row['request_hash'] ||
            command['version'] != 2 ||
            command['operation'] != row['operation'] ||
            command['requestId'] != row['request_id'] ||
            command['serverId'] != session.profile.serverId ||
            command['accountId'] != session.profile.accountId ||
            command['deviceId'] != session.profile.deviceId ||
            command['signer'] != 'device') {
          return fallback(CollaborationRecoveryFallback.invalidEvidence);
        }
        final payload = command['payload'] as Map;
        // Relocation, leases and other extra batch mechanisms have separate
        // replay dependencies. Do not reconstruct their graphs here.
        if (payload.length != 3 ||
            !isCryptoCanonicalUuid(payload['batchId']) ||
            payload['commitment'] is! Map ||
            payload.keys.any(
              (k) => !{'batchId', 'records', 'commitment'}.contains(k),
            )) {
          return fallback(CollaborationRecoveryFallback.unknownDependency);
        }
        final proofs = payload['records'] as List;
        if (proofs.isEmpty || proofs.length > 32) {
          return fallback(CollaborationRecoveryFallback.invalidEvidence);
        }
        final records = <Map>[];
        final claims = <String>{};
        for (final rawProof in proofs) {
          final proof = rawProof as Map;
          cryptoBase64(proof['signatureBase64'], length: 64);
          final r =
              CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map;
          if (r['version'] != 2 ||
              r['operation'] != 'crypto2.record' ||
              !const {6, 7}.contains(r['contentContract']) ||
              r['deleted'] is! bool ||
              !isCryptoCanonicalUuid(r['operationId']) ||
              r['serverId'] != session.profile.serverId ||
              r['accountId'] != session.profile.accountId ||
              r['deviceId'] != session.profile.deviceId ||
              r['batchId'] != payload['batchId'] ||
              !isCryptoCanonicalUuid(r['scopeId']) ||
              !isCryptoWireRecordId(r['id']) ||
              !{'content', 'finance'}.contains(r['domain']) ||
              r['expectedRevision'] is! int ||
              r['expectedRevision'] < 0 ||
              !claims.add(
                '${r['scopeId']}/${r['domain']}/${r['id']}/${r['expectedRevision']}',
              )) {
            return fallback(CollaborationRecoveryFallback.invalidEvidence);
          }
          final scope = known[r['scopeId']];
          if (scope == null ||
              scope.revoked ||
              scope.blocked ||
              scope.archived ||
              scope.deleted) {
            return fallback(CollaborationRecoveryFallback.unknownDependency);
          }
          records.add(r);
        }
        final storedClaims = await database.rows(
          'SELECT scope_id,domain,record_id,expected_revision FROM crypto_outbox_records WHERE partition=? AND request_id=? LIMIT 33',
          [p, row['request_id']],
        );
        if (storedClaims.length != claims.length ||
            storedClaims.any(
              (c) => !claims.contains(
                '${c['scope_id']}/${c['domain']}/${c['record_id']}/${c['expected_revision']}',
              ),
            )) {
          return fallback(CollaborationRecoveryFallback.incompleteClaims);
        }
        final mains = records
            .where((r) => ordinary.contains(r['type']))
            .toList();
        if (mains.length != 1 || mains.single['domain'] != 'content') {
          return fallback(CollaborationRecoveryFallback.unknownDependency);
        }
        final main = mains.single;
        // A post-content task derivation can discover finance only later. Its
        // parent closure is not fully declared by this ordinary request.
        if (main['type'] == 'task' &&
            known[main['scopeId']]!.parentSpaceId != null) {
          return fallback(CollaborationRecoveryFallback.unknownDependency);
        }
        if (records.length > 2) {
          return fallback(CollaborationRecoveryFallback.unknownDependency);
        }
        final mainProof = proofs[records.indexOf(main)] as Map;
        final mainProofHash = (await Sha256().hash(
          CryptoJson.encode(mainProof),
        )).bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
        final business = await database.rows(
          'SELECT * FROM crypto_business_requests WHERE partition=? AND request_id=?',
          [p, row['request_id']],
        );
        if (business.length != 1) {
          return fallback(CollaborationRecoveryFallback.unreplayableOperation);
        }
        final b = business.single;
        final pending = await database.rows(
          "SELECT o.* FROM outbox o LEFT JOIN personal_workspaces w ON w.partition=o.partition AND w.scope_id=o.scope_id WHERE o.partition=? AND o.op_id=? AND o.state='pending' AND NOT EXISTS(SELECT 1 FROM local_meta m WHERE m.name='scope_reconciliation:'||o.partition||':'||o.scope_id) AND (w.id IS NULL OR (w.enabled=1 AND w.paused=0))",
          [p, b['operation_id']],
        );
        if (pending.length != 1 ||
            (!sharedUploadsAllowed &&
                known[main['scopeId']]!.kind != SharedScopeKind.personal)) {
          return fallback(CollaborationRecoveryFallback.unreplayableOperation);
        }
        final op = pending.single;
        final request = jsonDecode(op['request'] as String) as Map;
        final identity = (main['metadata'] as Map)['identity'] as Map;
        final address = cryptoRecordAddressFromMetadata(
          Map<String, dynamic>.from(main),
        );
        if (address.wireId != main['id'] ||
            b['scope_id'] != main['scopeId'] ||
            b['domain'] != main['domain'] ||
            b['record_id'] != identity['canonicalId'] ||
            op['scope_id'] != b['scope_id'] ||
            op['record_id'] != b['record_id'] ||
            !isCryptoCanonicalUuid(request['opId']) ||
            request['expectedRevision'] is! int ||
            request['deleted'] is! bool ||
            (request['id'] != null &&
                request['recordId'] != null &&
                request['id'] != request['recordId']) ||
            request['opId'] != b['operation_id'] ||
            main['operationId'] != b['operation_id'] ||
            (request['recordId'] ?? request['id']) != b['record_id'] ||
            request['type'] != main['type'] ||
            b['request_hash'] != await CryptoBusinessJson.hash(request)) {
          return fallback(CollaborationRecoveryFallback.unreplayableOperation);
        }
        if ((await database.rows('SELECT 1 FROM local_meta WHERE name=?', [
              'task_cost_pair:$p:${op['op_id']}',
            ])).isNotEmpty ||
            (main['type'] == 'project' && request['deleted'] == true)) {
          return fallback(CollaborationRecoveryFallback.unknownDependency);
        }
        for (var i = 0; i < records.length; i++) {
          final r = records[i], metadata = r['metadata'] as Map;
          if (!identical(r, main)) {
            final companion = metadata['recordPolicyCompanion'];
            if (main['type'] != 'task' ||
                r['type'] != 'taskDerivationIntent' ||
                r['scopeId'] != main['scopeId'] ||
                r['domain'] != 'content' ||
                r['operationId'] != main['operationId'] ||
                companion is! Map ||
                r['contentContract'] != 6 ||
                companion.length != 4 ||
                companion['version'] != 1 ||
                companion['taskProofHash'] != mainProofHash ||
                companion['taskId'] != main['id'] ||
                companion['taskRevision'] !=
                    (main['expectedRevision'] as int) + 1) {
              return fallback(CollaborationRecoveryFallback.unknownDependency);
            }
          }
          final refs = metadata['references'] as List;
          final versions = metadata['referenceVersions'] as List? ?? const [];
          if (refs.length != versions.length ||
              (metadata['blobIds'] as List).isNotEmpty) {
            return fallback(CollaborationRecoveryFallback.unknownDependency);
          }
          final pairs = {
            for (final ref in refs) '${(ref as Map)['scopeId']}/${ref['id']}',
          };
          if (pairs.length != refs.length) {
            return fallback(CollaborationRecoveryFallback.unknownDependency);
          }
          (selected[r['scopeId'] as String] ??= {}).add(r['domain'] as String);
          for (final v in versions) {
            final ref = v as Map;
            final scope = known[ref['scopeId']];
            if (scope == null ||
                scope.revoked ||
                scope.blocked ||
                scope.archived ||
                scope.deleted ||
                !{'content', 'finance'}.contains(ref['domain']) ||
                !isCryptoWireRecordId(ref['id']) ||
                ref['revision'] is! int ||
                ref['revision'] < 1 ||
                ref['recordProofHash'] is! String ||
                !RegExp(r'^[a-f0-9]{64}$').hasMatch(ref['recordProofHash']) ||
                !pairs.remove('${ref['scopeId']}/${ref['id']}')) {
              return fallback(CollaborationRecoveryFallback.unknownDependency);
            }
            (selected[ref['scopeId'] as String] ??= {}).add(
              ref['domain'] as String,
            );
          }
        }
      }
    } on FormatException {
      return fallback(CollaborationRecoveryFallback.invalidEvidence);
    } on TypeError {
      return fallback(CollaborationRecoveryFallback.invalidEvidence);
    } on StateError {
      return fallback(CollaborationRecoveryFallback.invalidEvidence);
    }
    return CollaborationPendingSyncSelection(selected, null);
  });
}
