import 'dart:convert';
import 'dart:typed_data';
import '../../domain/shared_payload_validation.dart' show isSharedUuid;

import 'package:cryptography/cryptography.dart' show Sha256;
import 'package:sodium/sodium.dart';

import '../collaboration_transport.dart';
import '../device_session_store.dart';
import 'crypto_codec.dart';
import 'crypto_json.dart';
import 'crypto_record_proof_codec.dart';
import 'crypto_record_policy.dart';
import 'crypto_record_address.dart'
    show isCryptoCanonicalUuid, isCryptoWireRecordId;
import 'crypto_sync_store.dart';
import 'crypto_moderation_receipt.dart';

/// Trust resolution must validate pinned identity, historical membership head,
/// author role, domain capability and revocation epoch before returning a key.
typedef CryptoAuthorKey =
    Future<CryptoRecordAuthority> Function(Map<String, dynamic> record);
typedef CryptoContentKey =
    Future<CryptoKeyLease> Function(Map<String, dynamic> record);
typedef CryptoProjection =
    Future<void> Function(List<CryptoProjectionRecord> records);

typedef CryptoCompletenessProof =
    Future<bool> Function({
      required String scopeId,
      required String domain,
      required int accessRevision,
      required int scopeSequence,
      required int transportCursor,
    });

class CryptoReadContext {
  const CryptoReadContext({
    required this.epoch,
    required this.accessRevision,
    required this.headHash,
  });
  final int epoch, accessRevision;
  final String headHash;
}

class CryptoKeyLease {
  CryptoKeyLease.owned(this.key) : owned = true;
  CryptoKeyLease.borrowed(this.key) : owned = false;
  final SecureKey key;
  final bool owned;
  void release() {
    if (owned) key.dispose();
  }
}

class CryptoProjectionRecord {
  const CryptoProjectionRecord(
    this.wire,
    this.record,
    this.plaintext, {
    required this.historyBasis,
    required this.batchKey,
    this.migrationOrigin,
    this.migrationWitness,
    this.relocationOrigin,
    this.historicalOnly = false,
    this.historicalAnchorWire,
  });

  /// Evidence-only sibling, supplied only after exact authenticated ancestry.
  /// Never installed as a current row or used to acknowledge another intent.
  final bool historicalOnly;
  final Map<String, dynamic>? historicalAnchorWire;
  final String historyBasis, batchKey;
  final Map<String, dynamic> wire, record;
  final Uint8List? plaintext;

  /// Dedicated certificate-verified captured-source binding. Never populated
  /// from unsigned transport metadata or restored SQL flags.
  final Map<String, dynamic>? migrationOrigin;
  final Map<String, dynamic>? relocationOrigin;

  /// Decrypted detached source witness, verified before the SQL transaction.
  /// Kept transient; never exported as public proof or persisted in an outbox.
  final Map<String, dynamic>? migrationWitness;
}

/// Missing trusted evidence is distinct from a corrupt authenticated record.
/// Raw history remains an unconfirmed candidate and cannot enter a balance.
class CryptoProjectionHistoryBudget {
  int remaining = 32;
  bool take() {
    if (remaining <= 0) return false;
    remaining--;
    return true;
  }
}

class CryptoAuthorityPending implements Exception {
  const CryptoAuthorityPending(this.reason);
  final String reason;
  @override
  String toString() => 'CryptoAuthorityPending($reason)';
}

class CryptoProjectionPending implements Exception {
  const CryptoProjectionPending();
}

class CryptoRecordAuthority {
  const CryptoRecordAuthority({
    required this.signingKey,
    required this.currentEpoch,
    this.closedRecordProofHash,
    this.historyBasis,
    this.migrationOrigin,
    this.migrationWitness,
    this.relocationOrigin,
  });
  final Uint8List signingKey;
  final bool currentEpoch;
  final String? closedRecordProofHash;
  final String? historyBasis;
  final Map<String, dynamic>? migrationOrigin,
      migrationWitness,
      relocationOrigin;
}

/// Separate exact-byte ciphertext delivery. Legacy outbox rows are never
/// rewritten, acknowledged, deleted or transmitted by this repository.
class CryptoSyncRepository {
  CryptoSyncRepository({
    required this.crypto,
    required this.session,
    required this.transport,
    required this.store,
    required this.signingKey,
    required this.authorKey,
    required this.contentKey,
    required this.project,
    this.prepareProjection,
    this.resolveHistoricalSiblings,
    required this.isCurrent,
    this.completenessProof,
    this.beforeDelivery,
    this.readContext,
    this.deliverySidecar,
    this.supportsRecordPolicy,
  });
  final Future<bool> Function()? supportsRecordPolicy;
  final CryptoCodec crypto;
  final DeviceSession session;
  final CollaborationTransport transport;
  final CryptoSyncStore store;
  final Future<CryptoKeyLease> Function() signingKey;
  final CryptoAuthorKey authorKey;
  final CryptoContentKey contentKey;
  final CryptoProjection project;
  final Future<void> Function(List<CryptoProjectionRecord>)? prepareProjection;
  final Future<List<CryptoProjectionRecord>> Function(
    List<CryptoProjectionRecord> current,
    Set<String> missingDigests,
    CryptoProjectionHistoryBudget budget,
  )?
  resolveHistoricalSiblings;
  final bool Function() isCurrent;

  /// Server cursor/hasMore is not a signed completeness proof. Production
  /// supplies a verified domain/component checkpoint; absence stays incomplete.
  final CryptoCompletenessProof? completenessProof;
  final Future<CryptoReadContext> Function(String scopeId, String domain)?
  readContext;

  /// Refresh signed directory/member snapshots and current scope heads before
  /// online delivery. Absence never grants permission from cached capability.
  final Future<void> Function(Map<String, dynamic> signed)? beforeDelivery;

  /// Transient comparison secrets for capture3 only. Called after an exact
  /// receipt lookup proves no saved outcome; never persisted with signed bytes.
  final Future<Map<String, dynamic>> Function(Map<String, dynamic> signed)?
  deliverySidecar;
  CryptoRecordProofCodec get records => CryptoRecordProofCodec(crypto);

  static final _queues = <String, Future<void>>{};
  Future<T> _exclusive<T>(Future<T> Function() body) async {
    final partition = store.partition;
    final completion = (_queues[partition] ?? Future<void>.value()).then(
      (_) => body(),
    );
    final marker = completion.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    _queues[partition] = marker;
    try {
      return await completion;
    } finally {
      if (identical(_queues[partition], marker)) _queues.remove(partition);
    }
  }

  void _current() {
    if (!isCurrent() || store.partition != session.profile.partition) {
      throw const FormatException('crypto_stale_identity');
    }
  }

  Future<Map<String, dynamic>> _call(
    String operation,
    Map<String, dynamic> params,
  ) async {
    _current();
    final result = await transport.call(
      serverUrl: session.profile.serverUrl,
      operation: operation,
      params: params,
      token: session.token,
      allowLocalHttp: session.profile.allowLocalHttp,
    );
    _current();
    return result;
  }

  Future<String> _hash(Map<String, dynamic> signed) async =>
      (await Sha256().hash(
        cryptoBase64(signed['commandBase64']),
      )).bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  /// Durable metadata/ciphertext protocol command. The exact five moderation
  /// report/disclosure operations are the explicit reporter-reviewed disclosure
  /// exception; migration exports are reads and archive uploads are ciphertext.
  Future<String> enqueueCommand({
    required String actionKey,
    required String operation,
    required Map<String, dynamic> payload,
    String? requestId,
  }) => _exclusive(() async {
    _current();
    if (requestId != null && !isCryptoCanonicalUuid(requestId)) {
      throw const FormatException('crypto_command_request_id');
    }
    if (!operation.startsWith('crypto2.migration.') &&
        !operation.startsWith('crypto2.legacy.') &&
        !operation.startsWith('crypto2.blob.') &&
        !const {
          'crypto2.table.acquire',
          'crypto2.table.renew',
          'crypto2.table.release',
          'crypto2.domain.checkpoint',
          'crypto2.reminders.put',
          'crypto2.reminders.cancel',
          'crypto2.moderation.report',
          'crypto2.moderation.disclosure.begin',
          'crypto2.moderation.disclosure.chunk',
          'crypto2.moderation.disclosure.complete',
          'crypto2.moderation.disclosure.abort',
          'crypto2.inbox.read',
          'crypto2.inbox.preferences.set',
          'crypto2.scope.lifecycle.prepare',
          'crypto2.scope.lifecycle.observation.put',
          'crypto2.scope.archive',
          'crypto2.scope.lifecycle.cancel',
          'crypto2.scope.lifecycle.delegate',
          'crypto2.scope.financePolicy.propose',
          'crypto2.scope.recordPolicy.prepare',
          'crypto2.scope.recordPolicy.stage',
          'crypto2.scope.recordPolicy.activate',
          'crypto2.scope.delete',
          'crypto2.inlineDelete.prepare',
          'crypto2.inlineDelete.stage',
          'crypto2.inlineDelete.commit',
          'crypto2.inlineDelete.cancel',
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
          'crypto2.exports.propose',
          'crypto2.exports.delegate',
          'crypto2.exports.certify',
        }.contains(operation)) {
      throw const FormatException('crypto_command_namespace');
    }
    final payloadHash = (await Sha256().hash(
      CryptoJson.encode({'operation': operation, 'payload': payload}),
    )).bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    final prior = await store.database.rows(
      'SELECT request_id,payload_hash FROM crypto_command_keys WHERE partition=? AND action_key=?',
      [store.partition, actionKey],
    );
    if (prior.isNotEmpty) {
      if (prior.single['payload_hash'] != payloadHash ||
          (requestId != null && prior.single['request_id'] != requestId)) {
        throw const FormatException('crypto_immutable_command');
      }
      return prior.single['request_id'] as String;
    }
    final id = requestId ?? crypto.randomId();
    final lease = await signingKey();
    late Map<String, dynamic> signed;
    try {
      signed = records.signCommand({
        'version': 2,
        'operation': operation,
        'requestId': id,
        'serverId': session.profile.serverId,
        'accountId': session.profile.accountId,
        'deviceId': session.profile.deviceId,
        'signer': 'device',
        'payload': payload,
      }, lease.key);
    } finally {
      lease.release();
    }
    final hash = await _hash(signed);
    await store.transaction(() async {
      _current();
      await store.stage(
        requestId: id,
        operation: operation,
        signed: signed,
        requestHash: hash,
      );
      await store.database.execute(
        'INSERT INTO crypto_command_keys VALUES(?,?,?,?)',
        [store.partition, actionKey, id, payloadHash],
      );
    });
    return id;
  });

  Future<Map<String, dynamic>> commandResult(String requestId) async {
    final row = await store.outgoing(requestId);
    if (row == null || row['state'] != 'applied') {
      throw const CryptoAuthorityPending('crypto_command_receipt_pending');
    }
    final receipt = jsonDecode(row['response'] as String) as Map;
    return Map<String, dynamic>.from(receipt['response'] as Map);
  }

  /// Persist ciphertext/signature once, atomically with the business mutation.
  /// The callback must use this store's database transaction and no network I/O.
  Future<String> enqueueBatch({
    required String batchId,
    required List<Map<String, dynamic>> recordProofs,
    required Map<String, dynamic> commitment,
    required Future<void> Function() applyLocal,
    List<Map<String, dynamic>> tableLeases = const [],
    List<Map<String, dynamic>> exportBindings = const [],
    Future<void> Function(String requestId)? onStaged,
  }) => _exclusive(
    () => _enqueueBatch(
      batchId: batchId,
      recordProofs: recordProofs,
      commitment: commitment,
      applyLocal: applyLocal,
      tableLeases: tableLeases,
      exportBindings: exportBindings,
      onStaged: onStaged,
    ),
  );

  /// Explicit same-intent reauthorization after a definitive rejected receipt.
  /// Unknown/403 outcomes never release a revision claim. Local business state
  /// is not applied twice, and the original request/receipt remains retained.
  Future<String> rebaseRejectedBatch({
    required String rejectedRequestId,
    required String batchId,
    required List<Map<String, dynamic>> recordProofs,
    required Map<String, dynamic> commitment,
  }) => _exclusive(() async {
    final old = await store.outgoing(rejectedRequestId);
    if (old == null || old['state'] != 'rejected') {
      throw const FormatException('crypto_rebase_requires_rejection');
    }
    final signed =
        jsonDecode(old['signed_body'] as String) as Map<String, dynamic>;
    if (await _hash(signed) != old['request_hash']) {
      throw const FormatException('crypto_rebase_original_changed');
    }
    final command =
        CryptoJson.decode(cryptoBase64(signed['commandBase64'])) as Map;
    if ((command['payload'] as Map).containsKey('exportBindings')) {
      throw const FormatException('crypto_export_reauthorization_required');
    }
    final original = (command['payload'] as Map)['records'] as List;
    if (original.length != recordProofs.length) {
      throw const FormatException('crypto_rebase_intent_changed');
    }
    final oldRecords = <String, Map<String, dynamic>>{};
    for (final proof in original) {
      final r =
          CryptoJson.decode(cryptoBase64((proof as Map)['commandBase64']))
              as Map<String, dynamic>;
      oldRecords['${r['scopeId']}:${r['domain']}:${r['id']}'] = r;
    }
    for (final proof in recordProofs) {
      final next =
          CryptoJson.decode(cryptoBase64(proof['commandBase64']))
              as Map<String, dynamic>;
      final previous = oldRecords.remove(
        '${next['scopeId']}:${next['domain']}:${next['id']}',
      );
      if (previous == null ||
          [
            'serverId',
            'accountId',
            'scopeId',
            'domain',
            'id',
            'type',
            'operationId',
            'expectedRevision',
            'previousRecordHash',
            'deleted',
          ].any((k) => previous[k] != next[k])) {
        throw const FormatException('crypto_rebase_intent_changed');
      }
      if (base64Encode(CryptoJson.encode(previous['metadata'])) !=
          base64Encode(CryptoJson.encode(next['metadata']))) {
        throw const FormatException('crypto_rebase_intent_changed');
      }
      if (next['deleted'] != true) {
        Uint8List? before, after;
        final oldKey = await contentKey(previous);
        CryptoKeyLease? newKey;
        try {
          newKey = await contentKey(next);
          before = records.openVerified(previous, oldKey.key);
          after = records.openVerified(next, newKey.key);
          if (before == null ||
              after == null ||
              before.length != after.length) {
            throw const FormatException('crypto_rebase_intent_changed');
          }
          var difference = 0;
          for (var i = 0; i < before.length; i++) {
            difference |= before[i] ^ after[i];
          }
          if (difference != 0) {
            throw const FormatException('crypto_rebase_intent_changed');
          }
        } finally {
          before?.fillRange(0, before.length, 0);
          after?.fillRange(0, after.length, 0);
          oldKey.release();
          newKey?.release();
        }
      }
    }
    if (oldRecords.isNotEmpty) {
      throw const FormatException('crypto_rebase_intent_changed');
    }
    return _enqueueBatch(
      batchId: batchId,
      recordProofs: recordProofs,
      commitment: commitment,
      applyLocal: () async {},
      replacesRejectedRequestId: rejectedRequestId,
    );
  });

  /// A separate policy adoption successor, never a rewrite of an old request.
  /// The authority callback must use already verified/cached baseline and
  /// predecessor evidence, including expanded document payloads. It must not
  /// call this queue or perform network work while its partition lock is held.
  Future<String> reauthorizeRejectedPolicyBatch({
    required String rejectedRequestId,
    required String batchId,
    required List<Map<String, dynamic>> recordProofs,
    required Map<String, dynamic> commitment,
    required Future<void> Function(
      Map<String, dynamic> previous,
      Map<String, dynamic> next,
      Map<String, dynamic>? previousPayload,
      Map<String, dynamic>? nextPayload,
    )
    validateAuthority,
    required Future<void> Function(String requestId) onStaged,
    List<Map<String, dynamic>> tableLeases = const [],
  }) => _exclusive(() async {
    _current();
    final old = await store.outgoing(rejectedRequestId);
    if (old == null ||
        old['operation'] != 'crypto2.records.batch' ||
        old['state'] != 'rejected' ||
        old['response'] is! String) {
      throw const FormatException('crypto_policy_successor_requires_rejection');
    }
    final signed =
        jsonDecode(old['signed_body'] as String) as Map<String, dynamic>;
    final receipt = jsonDecode(old['response'] as String) as Map;
    final command =
        CryptoJson.decode(cryptoBase64(signed['commandBase64'])) as Map;
    if (await _hash(signed) != old['request_hash'] ||
        receipt['status'] != 409 ||
        receipt['response'] is! Map ||
        receipt['response']['errorCode'] != 'crypto_upgrade_required' ||
        receipt['requestId'] != rejectedRequestId ||
        receipt['requestHash'] != old['request_hash'] ||
        base64Encode(CryptoJson.encode(receipt['authorization'])) !=
            base64Encode(CryptoJson.encode(signed)) ||
        command['serverId'] != session.profile.serverId ||
        command['accountId'] != session.profile.accountId ||
        command['deviceId'] != session.profile.deviceId) {
      throw const FormatException('crypto_policy_successor_receipt');
    }
    final payload = command['payload'] as Map;
    if ((payload['exportBindings'] as List? ?? const []).isNotEmpty) {
      throw const CryptoAuthorityPending(
        'crypto_export_reauthorization_required',
      );
    }
    final priorLinks = await store.database.rows(
      'SELECT new_request_id FROM crypto_outbox_reconciliations WHERE partition=? AND old_request_id=?',
      [store.partition, rejectedRequestId],
    );
    if (priorLinks.isNotEmpty) {
      final prior = await store.outgoing(
        priorLinks.single['new_request_id'] as String,
      );
      if (prior == null)
        throw const FormatException('crypto_policy_successor_missing');
      final next =
          CryptoJson.decode(
                cryptoBase64(
                  (jsonDecode(prior['signed_body'] as String)
                      as Map)['commandBase64'],
                ),
              )
              as Map;
      if (base64Encode(CryptoJson.encode(next['payload'])) !=
          base64Encode(
            CryptoJson.encode({
              'batchId': batchId,
              'records': recordProofs,
              'commitment': commitment,
              if (tableLeases.isNotEmpty) 'tableLeases': tableLeases,
            }),
          )) {
        throw const FormatException('crypto_policy_successor_exists');
      }
      return prior['request_id'] as String;
    }
    final original = (payload['records'] as List).cast<Map>();
    if (original.length != recordProofs.length)
      throw const FormatException('crypto_policy_successor_group');
    final before = <String, Map<String, dynamic>>{},
        after = <String, Map<String, dynamic>>{};
    final hashes = <String, String>{};
    String address(Map r) => '${r['scopeId']}:${r['domain']}:${r['id']}';
    for (final proof in original) {
      final r = Map<String, dynamic>.from(
        CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map,
      );
      if (before.containsKey(address(r)))
        throw const FormatException('crypto_policy_successor_group');
      before[address(r)] = r;
    }
    for (final proof in recordProofs) {
      final r = Map<String, dynamic>.from(
        CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map,
      );
      if (after.containsKey(address(r)))
        throw const FormatException('crypto_policy_successor_group');
      after[address(r)] = r;
    }
    if (before.keys.toSet().difference(after.keys.toSet()).isNotEmpty ||
        after.length != before.length) {
      throw const FormatException('crypto_policy_successor_group');
    }
    for (final proof in original) {
      final r = CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map;
      final nextProof = recordProofs.singleWhere(
        (p) =>
            address(
              CryptoJson.decode(cryptoBase64(p['commandBase64'])) as Map,
            ) ==
            address(r),
      );
      hashes[await records.digest(Map<String, dynamic>.from(proof))] =
          await records.digest(nextProof);
    }
    Object? canonical(Object? value) => base64Encode(CryptoJson.encode(value));
    Map<String, dynamic> normalizedMetadata(
      Map<String, dynamic> r, {
      required bool next,
    }) {
      final result = Map<String, dynamic>.from(r['metadata'] as Map);
      if (next) {
        result.remove('recordPolicy');
        result.remove('recordPolicyCompanion');
      }
      final refs = result['referenceVersions'];
      if (!next && refs is List) {
        result['referenceVersions'] = [
          for (final ref in refs)
            {
              ...Map<String, dynamic>.from(ref as Map),
              'recordProofHash':
                  hashes[ref['recordProofHash']] ?? ref['recordProofHash'],
            },
        ];
      }
      return result;
    }

    var ordinary = 0;
    for (final key in before.keys) {
      final previous = before[key]!, next = after[key]!;
      if (const [
        'serverId',
        'accountId',
        'deviceId',
        'scopeId',
        'domain',
        'id',
        'type',
        'operationId',
        'expectedRevision',
        'previousRecordHash',
        'deleted',
        'membershipHeadHash',
        'epoch',
        'accessRevision',
      ].any((field) => previous[field] != next[field])) {
        throw const FormatException('crypto_policy_successor_identity');
      }
      final business = CryptoRecordPolicy.businessTypes.contains(next['type']);
      if (business) {
        ordinary++;
        if (previous['contentContract'] !=
                (previous['domain'] == 'finance' ? 3 : 6) ||
            next['contentContract'] != (next['domain'] == 'finance' ? 4 : 7) ||
            (previous['metadata'] as Map).containsKey('recordPolicy')) {
          throw const FormatException('crypto_policy_successor_contract');
        }
        CryptoRecordPolicy.validate(
          Map<String, dynamic>.from(next['metadata']['recordPolicy'] as Map),
        );
      } else if (!const {
            'taskDerivationIntent',
            'taskDerivationResolution',
          }.contains(next['type']) ||
          previous['contentContract'] != next['contentContract']) {
        throw const CryptoAuthorityPending(
          'crypto_policy_successor_type_pending',
        );
      }
      if (canonical(normalizedMetadata(previous, next: false)) !=
          canonical(normalizedMetadata(next, next: true))) {
        throw const FormatException('crypto_policy_successor_metadata');
      }
      Uint8List? oldBytes, newBytes;
      final oldKey = await contentKey(previous);
      CryptoKeyLease? nextKey;
      try {
        nextKey = await contentKey(next);
        oldBytes = records.openVerified(previous, oldKey.key);
        newBytes = records.openVerified(next, nextKey.key);
        Map<String, dynamic>? oldPayload, nextPayload;
        if (previous['deleted'] != true) {
          if (oldBytes == null || newBytes == null)
            throw const FormatException('crypto_policy_successor_payload');
          final oldEnvelope = Map<String, dynamic>.from(
            jsonDecode(utf8.decode(oldBytes)) as Map,
          );
          final nextEnvelope = Map<String, dynamic>.from(
            jsonDecode(utf8.decode(newBytes)) as Map,
          );
          oldPayload = Map<String, dynamic>.from(oldEnvelope['payload'] as Map);
          nextPayload = Map<String, dynamic>.from(
            nextEnvelope['payload'] as Map,
          );
          final oldSemantic = Map<String, dynamic>.from(oldPayload),
              nextSemantic = Map<String, dynamic>.from(nextPayload);
          if (business) {
            if (oldSemantic.containsKey(CryptoRecordPolicy.secretField))
              throw const FormatException(
                'crypto_policy_successor_existing_secret',
              );
            final secret = CryptoRecordPolicy.secret(nextSemantic);
            secret.fillRange(0, secret.length, 0);
            nextSemantic.remove(CryptoRecordPolicy.secretField);
          }
          if (next['type'] == 'taskDerivationResolution') {
            for (final field in const [
              'intentProofHash',
              'taskProofHash',
              'financeRecordProofHash',
            ]) {
              if (hashes.containsKey(oldSemantic[field]))
                oldSemantic[field] = hashes[oldSemantic[field]];
            }
          }
          oldEnvelope['payload'] = oldSemantic;
          nextEnvelope['payload'] = nextSemantic;
          if (canonical(oldEnvelope) != canonical(nextEnvelope))
            throw const FormatException('crypto_policy_successor_payload');
        } else if (oldBytes != null || newBytes != null) {
          throw const FormatException('crypto_policy_successor_payload');
        }
        await validateAuthority(previous, next, oldPayload, nextPayload);
        _current();
      } finally {
        oldBytes?.fillRange(0, oldBytes.length, 0);
        newBytes?.fillRange(0, newBytes.length, 0);
        oldKey.release();
        nextKey?.release();
      }
    }
    if (ordinary == 0)
      throw const FormatException('crypto_policy_successor_group');
    return _enqueueBatch(
      batchId: batchId,
      recordProofs: recordProofs,
      commitment: commitment,
      tableLeases: tableLeases,
      applyLocal: () async {},
      replacesRejectedRequestId: rejectedRequestId,
      reconciliationReason: 'record_policy_upgrade',
      onStaged: onStaged,
    );
  });

  Future<String> _enqueueBatch({
    String? replacesRejectedRequestId,
    String reconciliationReason = 'definitive_rejection',
    List<Map<String, dynamic>> tableLeases = const [],
    List<Map<String, dynamic>> exportBindings = const [],
    Future<void> Function(String requestId)? onStaged,
    required String batchId,
    required List<Map<String, dynamic>> recordProofs,
    required Map<String, dynamic> commitment,
    required Future<void> Function() applyLocal,
  }) async {
    _current();
    if (recordProofs.isEmpty || recordProofs.length > 32) {
      throw const FormatException('crypto_batch_size');
    }
    if (tableLeases.length > 32) {
      throw const FormatException('crypto_table_leases');
    }
    final leaseIds = <String>{};
    for (final lease in tableLeases) {
      if (lease.length != 3 ||
          !isSharedUuid(lease['scopeId']) ||
          !isSharedUuid(lease['id']) ||
          lease['tokenBase64'] is! String ||
          !leaseIds.add('${lease['scopeId']}:${lease['id']}')) {
        throw const FormatException('crypto_table_leases');
      }
      cryptoBase64(lease['tokenBase64'], max: 4096);
    }
    if (exportBindings.length > 32) {
      throw const FormatException('crypto_export_bindings');
    }
    final exportTargets = <String>{};
    for (final binding in exportBindings) {
      if (binding.length != 7 ||
          !isCryptoCanonicalUuid(binding['sourceScopeId']) ||
          !isCryptoCanonicalUuid(binding['targetScopeId']) ||
          !isCryptoWireRecordId(binding['sourceId']) ||
          !isCryptoWireRecordId(binding['targetId']) ||
          binding['sourceRecordProofHash'] is! String ||
          !RegExp(
            r'^[a-f0-9]{64}$',
          ).hasMatch(binding['sourceRecordProofHash']) ||
          binding['delegationHash'] is! String ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(binding['delegationHash']) ||
          binding['certificateProof'] is! Map ||
          !exportTargets.add(
            '${binding['targetScopeId']}:${binding['targetId']}',
          )) {
        throw const FormatException('crypto_export_bindings');
      }
      final proof = binding['certificateProof'] as Map;
      if (proof.length != 2 ||
          !proof.containsKey('commandBase64') ||
          !proof.containsKey('signatureBase64')) {
        throw const FormatException('crypto_export_bindings');
      }
      CryptoJson.decode(cryptoBase64(proof['commandBase64']));
      cryptoBase64(proof['signatureBase64'], length: 64);
    }
    final decodedRecords = <Map<String, dynamic>>[];
    for (final proof in recordProofs) {
      final r =
          CryptoJson.decode(cryptoBase64(proof['commandBase64']))
              as Map<String, dynamic>;
      if (r['serverId'] != session.profile.serverId ||
          r['accountId'] != session.profile.accountId ||
          r['deviceId'] != session.profile.deviceId ||
          r['batchId'] != batchId) {
        throw const FormatException('crypto_batch_identity');
      }
      decodedRecords.add(r);
      final authority = await authorKey(r);
      await records.verifyWire(
        serverId: session.profile.serverId,
        wire: {
          ...r,
          'revision': (r['expectedRevision'] as int) + 1,
          'authorization': {
            'recordProof': proof,
            'batchCommitment': commitment,
          },
        },
        trustedSigningKey: authority.signingKey,
        currentEpoch: authority.currentEpoch,
        closedRecordProofHash: authority.closedRecordProofHash,
      );
      _current();
    }
    for (final binding in exportBindings) {
      final sources = <int>[], targets = <int>[];
      for (var i = 0; i < decodedRecords.length; i++) {
        final body = decodedRecords[i];
        if (body['scopeId'] == binding['sourceScopeId'] &&
            body['id'] == binding['sourceId']) {
          sources.add(i);
        }
        if (body['scopeId'] == binding['targetScopeId'] &&
            body['id'] == binding['targetId']) {
          targets.add(i);
        }
      }
      if (sources.length != 1 ||
          targets.length != 1 ||
          await records.digest(recordProofs[sources.single]) !=
              binding['sourceRecordProofHash']) {
        throw const FormatException('crypto_export_bindings');
      }
    }
    final id = crypto.randomId();
    final keyLease = await signingKey();
    late Map<String, dynamic> signed;
    try {
      signed = records.signCommand({
        'version': 2,
        'operation': 'crypto2.records.batch',
        'requestId': id,
        'serverId': session.profile.serverId,
        'accountId': session.profile.accountId,
        'deviceId': session.profile.deviceId,
        'signer': 'device',
        'payload': {
          'batchId': batchId,
          'records': recordProofs,
          'commitment': commitment,
          if (tableLeases.isNotEmpty) 'tableLeases': tableLeases,
          if (exportBindings.isNotEmpty) 'exportBindings': exportBindings,
        },
      }, keyLease.key);
    } finally {
      keyLease.release();
    }
    if (cryptoBase64(signed['commandBase64']).length > 524288) {
      throw const CryptoAuthorityPending('crypto_atomic_batch_size_pending');
    }
    final hash = await _hash(signed);
    _current();
    await store.transaction(() async {
      _current();
      await store.stage(
        requestId: id,
        operation: 'crypto2.records.batch',
        signed: signed,
        requestHash: hash,
      );
      for (final record in decodedRecords) {
        await store.claimRecord(
          record,
          id,
          replacesRejectedRequestId: replacesRejectedRequestId,
        );
      }
      if (replacesRejectedRequestId != null) {
        await store.database.execute(
          'INSERT INTO crypto_outbox_reconciliations(partition,old_request_id,new_request_id,reason) VALUES(?,?,?,?)',
          [
            store.partition,
            replacesRejectedRequestId,
            id,
            reconciliationReason,
          ],
        );
      }
      await onStaged?.call(id);
      await applyLocal();
      _current();
    });
    return id;
  }

  /// A lost response replays the persisted bytes; it never reseals the body.
  /// Exact receipts are retained even after ACK, independently of UI state.
  Future<void> deliver() => _exclusive(_deliver);

  /// Explicit retry of previously intended, unresolved local work. Imported
  /// evidence never enters this active queue; terminal receipts and exact
  /// signed bytes/revision claims remain untouched. Delivery still looks up
  /// the historical receipt FIRST, then refreshes authority before any resend.
  Future<void> resumeUnresolved({Set<String>? requestIds}) {
    // Snapshot before entering the asynchronous partition queue: a caller may
    // not widen its original explicit retry selection while it waits.
    final selected = requestIds == null
        ? null
        : Set<String>.unmodifiable(requestIds);
    return _exclusive(() async {
      await for (final row in store.blockedDelivery()) {
        _current();
        final id = row['request_id'] as String;
        if (selected != null && !selected.contains(id)) continue;
        final saved = jsonDecode(row['response'] as String);
        if (saved is! Map || saved['outcome'] != 'unresolved') {
          throw const FormatException('crypto_retry_not_unresolved');
        }
        await store.retryBlocked(id);
      }
      await _deliver(requestIds: selected);
    });
  }

  /// Consume only already recorded terminal outcomes for an exact selection.
  /// Unknown or denied lookups retain pending work; this never sends a mutation
  /// or retries blocked work, even when a verified projection is already newer.
  Future<void> reconcileTerminalReceipts({required Set<String> requestIds}) {
    final selected = Set<String>.unmodifiable(requestIds);
    return _exclusive(() => _deliver(requestIds: selected, terminalOnly: true));
  }

  Future<void> _deliver({
    Set<String>? requestIds,
    bool terminalOnly = false,
  }) async {
    await for (final row in store.pendingDelivery()) {
      _current();
      if (requestIds != null && !requestIds.contains(row['request_id'])) {
        continue;
      }
      final signed =
          jsonDecode(row['signed_body'] as String) as Map<String, dynamic>;
      late Map<String, dynamic> receipt;
      Future<Map<String, dynamic>?> lookup() async {
        try {
          return await _call('crypto2.receipt.get', {
            'requestId': row['request_id'],
            'requestHash': row['request_hash'],
          });
        } on CollaborationApiException catch (error) {
          if (!{
            'permission_revoked',
            'finance_forbidden',
            'forbidden',
            'crypto_grant_missing',
            'crypto_device_keys_pending',
          }.contains(error.code)) {
            rethrow;
          }
          if (terminalOnly) return null;
          await store.transaction(() async {
            _current();
            await store.outcome(row['request_id'] as String, 'blocked', {
              'outcome': 'unresolved',
              'reason': error.code,
            });
          });
          return null;
        }
      }

      final historical = await lookup();
      if (historical == null) continue;
      receipt = historical;
      if (receipt['outcome'] == 'unknown') {
        if (terminalOnly) continue;
        final fresh = beforeDelivery;
        if (fresh == null) {
          throw const CryptoAuthorityPending(
            'crypto_delivery_reconciliation_required',
          );
        }
        try {
          await fresh(signed);
          _current();
        } on CryptoAuthorityPending catch (error) {
          await store.transaction(() async {
            _current();
            await store.outcome(row['request_id'] as String, 'blocked', {
              'outcome': 'unresolved',
              'reason': 'authority_pending',
              'code': error.reason,
            });
          });
          continue;
        } on CollaborationApiException catch (error) {
          if (!{
            'permission_revoked',
            'finance_forbidden',
            'forbidden',
            'crypto_grant_missing',
            'crypto_device_keys_pending',
          }.contains(error.code)) {
            rethrow;
          }
          await store.transaction(() async {
            _current();
            await store.outcome(row['request_id'] as String, 'blocked', {
              'outcome': 'unresolved',
              'reason': error.code,
            });
          });
          continue;
        }
        try {
          final sidecar =
              await deliverySidecar?.call(signed) ?? const <String, dynamic>{};
          if (sidecar.isNotEmpty &&
              (!const {
                    'crypto2.migration.capture.bind',
                    'crypto2.migration.recordsStage',
                  }.contains(row['operation']) ||
                  sidecar.length != 1 ||
                  !sidecar.containsKey('captureSecrets'))) {
            throw const FormatException('crypto_capture_sidecar_operation');
          }
          await _call(row['operation'] as String, {...signed, ...sidecar});
        } on CollaborationApiException catch (error) {
          // Required acceptance has no terminal receipt; keep the exact pending work.
          if (error.code == 'policy_acceptance_required') {
            rethrow;
          }
          /* Persisted conclusive failures are resolved by their exact receipt. */
        }
        final afterSend = await lookup();
        if (afterSend == null) continue;
        receipt = afterSend;
      }
      if (receipt['outcome'] == 'unknown') continue;
      final sameAuthorization =
          base64Encode(CryptoJson.encode(receipt['authorization'])) ==
          base64Encode(CryptoJson.encode(signed));
      if (receipt['requestId'] != row['request_id'] ||
          receipt['requestHash'] != row['request_hash'] ||
          (!sameAuthorization &&
              !await CryptoModerationReceipt.matches(
                signed: signed,
                operation: row['operation'] as String,
                requestHash: row['request_hash'] as String,
                receipt: receipt,
              ))) {
        throw const FormatException('crypto_receipt_substitution');
      }
      final response = Map<String, dynamic>.from(receipt['response'] as Map);
      final applied = receipt['status'] == 200;
      if (applied && row['operation'] == 'crypto2.records.batch') {
        _verifyBatchAck(signed, response);
      }
      await store.transaction(() async {
        _current();
        await store.outcome(
          row['request_id'] as String,
          applied ? 'applied' : 'rejected',
          receipt,
        );
      });
    }
  }

  void _verifyBatchAck(
    Map<String, dynamic> signed,
    Map<String, dynamic> response,
  ) {
    final command =
        CryptoJson.decode(cryptoBase64(signed['commandBase64'])) as Map;
    final expected = <String, int>{};
    for (final proof in (command['payload'] as Map)['records'] as List) {
      final r =
          CryptoJson.decode(cryptoBase64((proof as Map)['commandBase64']))
              as Map;
      expected['${r['scopeId']}:${r['id']}'] =
          (r['expectedRevision'] as int) + 1;
    }
    final actual = response['records'];
    if (response['status'] != 'applied' ||
        actual is! List ||
        actual.length != expected.length) {
      throw const FormatException('crypto_batch_ack');
    }
    for (final r in actual) {
      if (r is! Map ||
          expected.remove('${r['scopeId']}:${r['id']}') != r['revision'] ||
          r['sequence'] is! int ||
          (r['sequence'] as int) < 1) {
        throw const FormatException('crypto_batch_ack');
      }
    }
    if (expected.isNotEmpty) throw const FormatException('crypto_batch_ack');
  }

  Future<void> _attemptRows(
    String scopeId,
    String domain,
    List<Map<String, Object?>> rows, {
    bool candidates = false,
  }) => store.transaction(() async {
    _current();
    final marker = await store.database.rows(
      'SELECT COALESCE(MAX(last_attempt),0)+1 AS value FROM ${candidates ? 'crypto_received_candidates' : 'crypto_received'} WHERE partition=?',
      [store.partition],
    );
    for (final row in rows) {
      await store.database.execute(
        'UPDATE ${candidates ? 'crypto_received_candidates' : 'crypto_received'} SET last_attempt=? WHERE partition=? AND scope_id=? AND domain=? AND record_id=? AND revision=?${candidates ? ' AND candidate_hash=?' : ''}',
        [
          marker.single['value'],
          store.partition,
          scopeId,
          domain,
          row['record_id'],
          row['revision'],
          if (candidates) row['candidate_hash'],
        ],
      );
    }
  });

  Future<void> pull({
    required String scopeId,
    required String domain,
    required int accessRevision,
  }) => _exclusive(
    () =>
        _pull(scopeId: scopeId, domain: domain, accessRevision: accessRevision),
  );

  Future<void> _pull({
    required String scopeId,
    required String domain,
    required int accessRevision,
  }) async {
    if (!['content', 'finance'].contains(domain)) {
      throw const FormatException('crypto_domain');
    }
    final resolve = readContext;
    if (resolve == null) {
      throw const CryptoAuthorityPending('crypto_read_context_required');
    }
    final trusted = await resolve(scopeId, domain);
    _current();
    if (trusted.epoch < 1 ||
        trusted.accessRevision != accessRevision ||
        trusted.headHash.length != 64) {
      throw const CryptoAuthorityPending('crypto_read_context_changed');
    }
    var state = await store.scope(scopeId, domain);
    var cursor = state?['transport_cursor'] as int? ?? 0;
    var projectionCursor = state?['projection_cursor'] as int? ?? 0;
    final siblingBudget = CryptoProjectionHistoryBudget();
    final recordPolicySupported = await supportsRecordPolicy?.call() ?? false;
    _current();
    while (true) {
      final page = await _call('crypto2.records.pull', {
        'scopeId': scopeId,
        'domain': domain,
        'accessRevision': accessRevision,
        'cursor': cursor,
        'limit': 20,
        if (recordPolicySupported) 'supportedRecordPolicyVersion': 1,
      });
      final next = page['cursor'],
          sequence = page['scopeSequence'],
          epoch = page['epoch'],
          incoming = page['records'];
      if (next is! int ||
          next < cursor ||
          sequence is! int ||
          next > sequence ||
          epoch is! int ||
          epoch < 1 ||
          epoch != trusted.epoch ||
          epoch < (state?['floor'] as int? ?? 0) ||
          page['accessRevision'] != accessRevision ||
          page['hasMore'] is! bool ||
          incoming is! List ||
          incoming.length > 50 ||
          (page['hasMore'] == true && next == cursor)) {
        throw const FormatException('crypto_pull_checkpoint');
      }
      var previous = cursor;
      final wires = <Map<String, dynamic>>[];
      for (final value in incoming) {
        if (value is! Map<String, dynamic> ||
            value['scopeId'] != scopeId ||
            value['sequence'] is! int ||
            (value['sequence'] as int) <= previous ||
            (value['sequence'] as int) > next ||
            value['revision'] is! int ||
            (value['revision'] as int) < 1) {
          throw const FormatException('crypto_pull_record');
        }
        previous = value['sequence'] as int;
        wires.add(value);
      }
      // Durable receipt/cursor is independent of the verified projection cursor.
      await store.transaction(() async {
        _current();
        for (final wire in wires) {
          await store.receive(
            scopeId: scopeId,
            domain: domain,
            wire: wire,
            verdict: 'received',
          );
        }
        await store.checkpoint(
          scopeId: scopeId,
          domain: domain,
          epoch: epoch,
          accessRevision: accessRevision,
          transportCursor: next,
          projectionCursor: projectionCursor,
          scopeSequence: sequence,
          complete: false,
        );
      });
      // Authenticate bounded proof candidates first, without decrypting. The
      // durable commitment hash lets projection select a whole authorized batch
      // even when its legs arrived on different pages or interleaved with work
      // that is waiting for another peer/key.
      final unstaged = await store.database.rows(
        "SELECT wire,record_id,revision,candidate_hash FROM crypto_received_candidates WHERE partition=? AND scope_id=? AND domain=? AND verdict='received' AND batch_key IS NULL ORDER BY last_attempt,sequence LIMIT 32",
        [store.partition, scopeId, domain],
      );
      await _attemptRows(scopeId, domain, unstaged, candidates: true);
      for (final candidate in unstaged) {
        final wire =
            jsonDecode(candidate['wire'] as String) as Map<String, dynamic>;
        try {
          final auth = wire['authorization'];
          if (auth is! Map || auth['recordProof'] is! Map) {
            throw const FormatException('crypto_record_authorization');
          }
          final decoded = CryptoJson.decode(
            cryptoBase64((auth['recordProof'] as Map)['commandBase64']),
          );
          if (decoded is! Map<String, dynamic> || decoded['domain'] != domain) {
            throw const FormatException('crypto_domain_substitution');
          }
          records.validateUntrustedRecord(decoded);
          final authority = await authorKey(decoded);
          await records.verifyWire(
            serverId: session.profile.serverId,
            wire: wire,
            trustedSigningKey: authority.signingKey,
            currentEpoch: authority.currentEpoch,
            closedRecordProofHash: authority.closedRecordProofHash,
          );
          final batch = await records.digest(
            Map<String, dynamic>.from(auth['batchCommitment'] as Map),
          );
          _current();
          await store.receive(
            scopeId: scopeId,
            domain: domain,
            wire: wire,
            verdict: 'received',
            batchKey: batch,
          );
        } on CryptoAuthorityPending catch (error) {
          _current();
          await store.receive(
            scopeId: scopeId,
            domain: domain,
            wire: wire,
            verdict: 'received',
            error:
                RegExp(
                  r'^(crypto|scope)_[a-z0-9_]{1,90}$',
                ).hasMatch(error.reason)
                ? error.reason
                : 'crypto_authority_pending',
          );
        } on FormatException catch (error) {
          _current();
          await store.receive(
            scopeId: scopeId,
            domain: domain,
            wire: wire,
            verdict: 'quarantined',
            error:
                RegExp(
                  r'^(crypto|scope)_[a-z0-9_]{1,90}$',
                ).hasMatch(error.message)
                ? error.message
                : 'crypto_record_verification',
          );
        }
      }
      // A transport page can contain twenty independent groups. Process them
      // in small allocations, without retrying a permanently pending group in
      // the same call or leaving an ordinary cold page mostly unprojected.
      final attemptedBatches = <String>[];
      for (var round = 0; round < 8; round++) {
        final chosen = await store.database.rows(
          "SELECT batch_key FROM crypto_received WHERE partition=? AND scope_id=? AND domain=? AND verdict='received' AND batch_key IS NOT NULL ${attemptedBatches.isEmpty ? '' : 'AND batch_key NOT IN (${List.filled(attemptedBatches.length, '?').join(',')})'} GROUP BY batch_key ORDER BY MIN(last_attempt),MIN(sequence) LIMIT 4",
          [store.partition, scopeId, domain, ...attemptedBatches],
        );
        if (chosen.isEmpty) break;
        for (final selection in chosen) {
          attemptedBatches.add(selection['batch_key'] as String);
          final verifiedRecords = <CryptoProjectionRecord>[];
          Set<String>? expectedDigests;
          final actualDigests = <String>{};
          final pendingRows = await store.database.rows(
            "SELECT wire,record_id,revision FROM crypto_received WHERE partition=? AND scope_id=? AND domain=? AND verdict='received' AND batch_key=? ORDER BY sequence LIMIT 33",
            [store.partition, scopeId, domain, selection['batch_key']],
          );
          if (pendingRows.length > 32) {
            throw const FormatException('crypto_batch_size');
          }
          await _attemptRows(scopeId, domain, pendingRows);
          try {
            for (final pendingRow in pendingRows) {
              final wire =
                  jsonDecode(pendingRow['wire'] as String)
                      as Map<String, dynamic>;
              Uint8List? plaintext;
              String? authenticatedBatchKey;
              try {
                final authorization = wire['authorization'];
                if (authorization is! Map ||
                    authorization['recordProof'] is! Map) {
                  throw const FormatException('crypto_record_authorization');
                }
                final decoded = CryptoJson.decode(
                  cryptoBase64(
                    (authorization['recordProof'] as Map)['commandBase64'],
                  ),
                );
                if (decoded is! Map<String, dynamic>) {
                  throw const FormatException('crypto_record_authorization');
                }
                final r = decoded;
                records.validateUntrustedRecord(r);
                if (r['domain'] != domain) {
                  throw const FormatException('crypto_domain_substitution');
                }
                final authority = await authorKey(r);
                final verified = await records.verifyWire(
                  serverId: session.profile.serverId,
                  wire: wire,
                  trustedSigningKey: authority.signingKey,
                  currentEpoch: authority.currentEpoch,
                  closedRecordProofHash: authority.closedRecordProofHash,
                );
                final restoredAnchor = (await store.database.rows(
                  'SELECT revision,proof_hash FROM crypto_restore_record_anchors WHERE partition=? AND scope_id=? AND domain=? AND record_id=?',
                  [store.partition, scopeId, domain, verified['id']],
                )).firstOrNull;
                if (restoredAnchor != null) {
                  final revision = wire['revision'] as int;
                  if (revision < (restoredAnchor['revision'] as int)) {
                    throw const CryptoAuthorityPending(
                      'crypto_restore_newer_record_pending',
                    );
                  }
                  if (revision == restoredAnchor['revision'] &&
                      await records.digest(
                            Map<String, dynamic>.from(
                              authorization['recordProof'] as Map,
                            ),
                          ) !=
                          restoredAnchor['proof_hash']) {
                    throw const FormatException(
                      'crypto_restore_record_equivocation',
                    );
                  }
                }
                authenticatedBatchKey = await records.digest(
                  Map<String, dynamic>.from(
                    authorization['batchCommitment'] as Map,
                  ),
                );
                _current();
                final basis = authority.currentEpoch
                    ? 'currentEpoch'
                    : authority.historyBasis;
                if (![
                  'currentEpoch',
                  'verifiedCheckpoint',
                  'reviewedRecoveryBaseline',
                  'migrationCapturedSource',
                  'inlineProjectDeletion',
                  'managerAttestedProjectRelocation',
                ].contains(basis)) {
                  throw const CryptoAuthorityPending(
                    'crypto_history_basis_required',
                  );
                }
                final keyLease = await contentKey(verified);
                try {
                  final expected = records
                      .expectedProjectionDigests(
                        record: verified,
                        commitment: Map<String, dynamic>.from(
                          authorization['batchCommitment'] as Map,
                        ),
                        contentKey: keyLease.key,
                      )
                      .toSet();
                  if (expectedDigests != null &&
                      (expected.length != expectedDigests.length ||
                          !expected.containsAll(expectedDigests))) {
                    throw const FormatException(
                      'crypto_projection_group_changed',
                    );
                  }
                  expectedDigests = expected;
                  actualDigests.add(
                    await records.digest(
                      Map<String, dynamic>.from(
                        authorization['recordProof'] as Map,
                      ),
                    ),
                  );
                  try {
                    plaintext = records.openVerified(verified, keyLease.key);
                  } on SodiumException {
                    throw const FormatException('crypto_authentication');
                  }
                } finally {
                  keyLease.release();
                }
                _current();
                verifiedRecords.add(
                  CryptoProjectionRecord(
                    wire,
                    verified,
                    plaintext,
                    historyBasis: basis!,
                    batchKey: authenticatedBatchKey,
                    migrationOrigin: authority.migrationOrigin,
                    relocationOrigin: authority.relocationOrigin,
                    migrationWitness: authority.migrationWitness,
                  ),
                );
              } on CryptoAuthorityPending catch (error) {
                plaintext?.fillRange(0, plaintext.length, 0);
                await store.transaction(() async {
                  _current();
                  await store.receive(
                    scopeId: scopeId,
                    domain: domain,
                    wire: wire,
                    verdict: 'received',
                    error: error.reason == 'crypto_restore_newer_record_pending'
                        ? error.reason
                        : 'crypto_authority_pending',
                  );
                });
              } on FormatException catch (error) {
                plaintext?.fillRange(0, plaintext.length, 0);
                await store.transaction(() async {
                  _current();
                  await store.receive(
                    scopeId: scopeId,
                    domain: domain,
                    wire: wire,
                    verdict: 'quarantined',
                    error: error.message == 'crypto_restore_record_equivocation'
                        ? 'crypto_restore_record_equivocation'
                        : 'crypto_record_verification',
                    batchKey: authenticatedBatchKey,
                  );
                });
              }
            }
            final batches = <String, List<CryptoProjectionRecord>>{};
            for (final value in verifiedRecords) {
              (batches[value.batchKey] ??= <CryptoProjectionRecord>[]).add(
                value,
              );
            }
            for (final batch in batches.values) {
              try {
                if (expectedDigests != null &&
                    actualDigests.length < expectedDigests.length &&
                    resolveHistoricalSiblings != null) {
                  final missing = expectedDigests.difference(actualDigests);
                  final siblings = await resolveHistoricalSiblings!(
                    batch,
                    missing,
                    siblingBudget,
                  );
                  // Own all returned buffers before any subsequent check can fail.
                  verifiedRecords.addAll(siblings);
                  for (final sibling in siblings) {
                    final digest = await records.digest(
                      Map<String, dynamic>.from(
                        (sibling.wire['authorization'] as Map)['recordProof']
                            as Map,
                      ),
                    );
                    if (!sibling.historicalOnly ||
                        sibling.historicalAnchorWire == null ||
                        sibling.batchKey != batch.first.batchKey ||
                        sibling.record['scopeId'] != scopeId ||
                        sibling.record['domain'] != domain ||
                        !missing.remove(digest) ||
                        !actualDigests.add(digest)) {
                      throw const FormatException(
                        'crypto_projection_historical_binding',
                      );
                    }
                    final lease = await contentKey(sibling.record);
                    try {
                      final expected = records
                          .expectedProjectionDigests(
                            record: sibling.record,
                            commitment: Map<String, dynamic>.from(
                              (sibling.wire['authorization']
                                      as Map)['batchCommitment']
                                  as Map,
                            ),
                            contentKey: lease.key,
                          )
                          .toSet();
                      if (expected.length != expectedDigests.length ||
                          !expected.containsAll(expectedDigests)) {
                        throw const FormatException(
                          'crypto_projection_group_changed',
                        );
                      }
                    } finally {
                      lease.release();
                    }
                    batch.add(sibling);
                  }
                }
                if (expectedDigests == null ||
                    expectedDigests.length != actualDigests.length ||
                    !actualDigests.containsAll(expectedDigests)) {
                  throw const CryptoProjectionPending();
                }
                // Fetch/decrypt authenticated blobs outside the SQL projection
                // transaction. This callback never grants visible business state.
                await prepareProjection?.call(batch);
                _current();
                await store.transaction(() async {
                  _current();
                  final context = await store.scope(scopeId, domain);
                  if (context == null ||
                      context['transport_cursor'] != next ||
                      context['epoch'] != epoch ||
                      context['access_revision'] != accessRevision) {
                    throw const FormatException(
                      'crypto_projection_context_changed',
                    );
                  }
                  final badLeg = await store.database.rows(
                    "SELECT record_id FROM crypto_received WHERE partition=? AND batch_key=? AND verdict='quarantined' LIMIT 1",
                    [store.partition, batch.first.batchKey],
                  );
                  if (badLeg.isNotEmpty) {
                    throw const FormatException('crypto_batch_corrupt_leg');
                  }
                  if (expectedDigests == null ||
                      expectedDigests.length != actualDigests.length ||
                      !actualDigests.containsAll(expectedDigests)) {
                    throw const CryptoProjectionPending();
                  }
                  final pending = <CryptoProjectionRecord>[];
                  for (final value in batch.where((v) => !v.historicalOnly)) {
                    final rows = await store.database.rows(
                      'SELECT verdict FROM crypto_received WHERE partition=? AND scope_id=? AND domain=? AND record_id=? AND revision=?',
                      [
                        store.partition,
                        scopeId,
                        domain,
                        value.wire['id'],
                        value.wire['revision'],
                      ],
                    );
                    if (rows.isEmpty) {
                      throw const FormatException(
                        'crypto_projection_missing_evidence',
                      );
                    }
                    if (![
                      'verified',
                      'superseded',
                    ].contains(rows.single['verdict'])) {
                      pending.add(value);
                    }
                  }
                  if (pending.isEmpty) return;
                  if (pending.length !=
                      batch.where((v) => !v.historicalOnly).length) {
                    throw const CryptoProjectionPending();
                  }
                  // Domain callback validates the entire authorized compound subset
                  // before writing. Other independent batches remain processable.
                  await project([
                    ...pending,
                    ...batch.where((v) => v.historicalOnly),
                  ]);
                  _current();
                  for (final value in pending) {
                    // The business projector has validated the predecessor chain
                    // and whole authenticated group before a restored floor moves.
                    await store.database.execute(
                      'UPDATE crypto_restore_record_anchors SET revision=?,proof_hash=?,wire=? WHERE partition=? AND scope_id=? AND domain=? AND record_id=? AND revision<?',
                      [
                        value.wire['revision'],
                        await records.digest(
                          Map<String, dynamic>.from(
                            (value.wire['authorization'] as Map)['recordProof']
                                as Map,
                          ),
                        ),
                        jsonEncode(value.wire),
                        store.partition,
                        scopeId,
                        domain,
                        value.wire['id'],
                        value.wire['revision'],
                      ],
                    );
                    await store.receive(
                      scopeId: scopeId,
                      domain: domain,
                      wire: value.wire,
                      verdict: 'verified',
                      historyBasis: value.historyBasis,
                      batchKey: value.batchKey,
                    );
                    final repair = value.record['metadata']['repairOf'];
                    if (repair is Map) {
                      await store.supersede(
                        scopeId: scopeId,
                        domain: domain,
                        recordId: value.wire['id'] as String,
                        revision: repair['revision'] as int,
                        proofHash: repair['recordProofHash'] as String,
                        replacementRevision: value.wire['revision'] as int,
                      );
                    }
                  }
                });
              } on CryptoProjectionPending {
                // Keep a local diagnostic without acknowledging or activating
                // any effect. A later exact retry replaces it after validation.
                await store.transaction(() async {
                  _current();
                  for (final value in batch.where((v) => !v.historicalOnly)) {
                    await store.receive(
                      scopeId: scopeId,
                      domain: domain,
                      wire: value.wire,
                      verdict: 'received',
                      error: 'crypto_projection_pending',
                      batchKey: value.batchKey,
                    );
                  }
                });
              } on CryptoAuthorityPending catch (error) {
                await store.transaction(() async {
                  _current();
                  for (final value in batch.where((v) => !v.historicalOnly)) {
                    await store.receive(
                      scopeId: scopeId,
                      domain: domain,
                      wire: value.wire,
                      verdict: 'received',
                      error:
                          RegExp(
                            r'^crypto_[a-z0-9_]{1,90}$',
                          ).hasMatch(error.reason)
                          ? error.reason
                          : 'crypto_authority_pending',
                      batchKey: value.batchKey,
                    );
                  }
                });
              } on FormatException catch (error) {
                if (error.message == 'crypto_projection_context_changed') {
                  rethrow;
                }
                await store.transaction(() async {
                  _current();
                  for (final value in batch.where((v) => !v.historicalOnly)) {
                    await store.receive(
                      scopeId: scopeId,
                      domain: domain,
                      wire: value.wire,
                      verdict: 'quarantined',
                      error:
                          RegExp(
                            r'^crypto_[a-z0-9_]{1,90}$',
                          ).hasMatch(error.message)
                          ? error.message
                          : 'crypto_semantic_verification',
                      batchKey: value.batchKey,
                    );
                  }
                });
              }
            }
          } finally {
            for (final value in verifiedRecords) {
              value.plaintext?.fillRange(0, value.plaintext!.length, 0);
            }
          }
        }
      }
      final blocked = await store.database.rows(
        "SELECT MIN(sequence) AS first FROM crypto_received WHERE partition=? AND scope_id=? AND domain=? AND verdict NOT IN ('verified','superseded')",
        [store.partition, scopeId, domain],
      );
      final first = blocked.single['first'] as int?;
      if (first == null) {
        projectionCursor = next;
      } else if (projectionCursor > first) {
        throw const FormatException('crypto_projection_checkpoint');
      }
      final complete =
          first == null &&
          page['hasMore'] == false &&
          completenessProof != null &&
          await completenessProof!(
            scopeId: scopeId,
            domain: domain,
            accessRevision: accessRevision,
            scopeSequence: sequence,
            transportCursor: next,
          );
      _current();
      await store.transaction(() async {
        _current();
        await store.checkpoint(
          scopeId: scopeId,
          domain: domain,
          epoch: epoch,
          accessRevision: accessRevision,
          transportCursor: next,
          projectionCursor: projectionCursor,
          scopeSequence: sequence,
          complete: complete,
        );
      });
      cursor = next;
      state = await store.scope(scopeId, domain);
      if (page['hasMore'] == false) break;
    }
  }
}
