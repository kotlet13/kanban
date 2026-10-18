import 'dart:convert';
import 'dart:typed_data';
import '../../domain/collaboration_models.dart' show CollaborationException;
import '../../domain/linked_payment_models.dart';
import 'account_directory_v2.dart';
import 'crypto_business_router.dart';
import 'crypto_business_finance.dart';
import 'crypto_business_json.dart';
import 'crypto_finance_uniqueness.dart';
import 'crypto_migration_payments.dart';
import 'crypto_business_references.dart';
import 'crypto_business_documents.dart';
import 'crypto_payment_semantics.dart';
import 'crypto_payment_payload.dart';
import 'crypto_scoped_exports.dart';
import 'crypto_scoped_export_workflow.dart';

import 'crypto_json.dart';
import 'crypto_record_address.dart';
import 'crypto_sync_repository.dart';
import 'session_crypto_access.dart';

part 'crypto_payment_catchup.dart';

class _PaymentWrite {
  _PaymentWrite(this.scope, this.id, this.type, this.before, this.raw);
  final String scope, id, type;
  final Map<String, Object?>? before;
  final Map<String, dynamic> raw;
}

/// Personal advances are sidecars, never a second expense. Shared writers can
/// reimburse a source event; only the payer can update their private projection.
class CryptoBusinessPayments {
  CryptoBusinessPayments(this.context);
  final CryptoBusinessSession context;
  static const types = {'paymentEvent', 'paymentProjection', 'cashMovement'};
  final _preparedWitnesses = <String, _PreparedPaymentWitness>{};
  // Exact original batch companions only; never source/target issuance floors,
  // current projection facts, manifest completion or visible business state.
  final _historicalGroupWitnesses = <String, _PreparedPaymentWitness>{};
  final _preparedManifests = <String>{};
  final _preparedUnique = <String, String>{};
  late final _uniqueness = CryptoFinanceUniqueTags(context.access);
  final _latestFacts = <String, _LatestPaymentFacts>{};
  final _refreshingConfirmations = <String>{};
  String? lastPendingCode;
  StackTrace? lastPendingTrace;

  /// All network-backed witness verification happens before the projection
  /// transaction. The SQL validator consumes only this exact proof-bound memo.
  Future<void> prepareRecords(List<CryptoProjectionRecord> records) =>
      context.access.withVerifiedOperation(() => _prepareRecords(records));

  Future<void> _prepareHistoricalCompanions(
    List<CryptoProjectionRecord> records,
  ) async {
    for (final sibling in records.where(
      (v) => v.historicalOnly && v.record['type'] == 'paymentProjection',
    )) {
      if (sibling.historicalAnchorWire == null || sibling.plaintext == null) {
        throw const CryptoProjectionPending();
      }
      final envelope = jsonDecode(utf8.decode(sibling.plaintext!)) as Map;
      final raw =
          await context.expandPayload?.call(
            sibling,
            Map<String, dynamic>.from(envelope['payload'] as Map),
          ) ??
          Map<String, dynamic>.from(envelope['payload'] as Map);
      await validateHistoryPayload(sibling, raw);
      final originalUnique = await _unique(
        sibling.record['scopeId'],
        sibling.record['type'],
        raw,
      );
      if (CryptoBusinessJson.canonical(
            sibling.record['metadata']['uniqueRefs'],
          ) !=
          CryptoBusinessJson.canonical([originalUnique])) {
        throw const FormatException('crypto_payment_unique_binding');
      }
      final disclosure = await CryptoScopedExports(context.access)
          .verifyHistoricalTarget(
            sibling.wire,
            anchorWire: sibling.historicalAnchorWire,
          );
      if (CryptoBusinessJson.canonical(
            CryptoScopedExportWorkflow.paymentDisclosure(raw),
          ) !=
          CryptoBusinessJson.canonical(disclosure.disclosure)) {
        throw const FormatException('crypto_payment_projection_disclosure');
      }
      final pins = <String, String?>{};
      for (final key in [
        'scope2:$p:${sibling.record['scopeId']}',
        'directory2:$p:$actor',
      ]) {
        pins[key] = await context.account.store.secure.read(key);
      }
      for (final cash in records.where(
        (v) =>
            !v.historicalOnly &&
            v.record['type'] == 'cashMovement' &&
            v.batchKey == sibling.batchKey &&
            v.record['scopeId'] == sibling.record['scopeId'],
      )) {
        if (cash.plaintext == null) throw const CryptoProjectionPending();
        final cashEnvelope = jsonDecode(utf8.decode(cash.plaintext!)) as Map;
        final cashRaw =
            await context.expandPayload?.call(
              cash,
              Map<String, dynamic>.from(cashEnvelope['payload'] as Map),
            ) ??
            Map<String, dynamic>.from(cashEnvelope['payload'] as Map);
        final link = cashRaw['paymentLink'];
        if (link is! Map ||
            link['eventId'] != raw['eventId'] ||
            link['sourceScopeId'] != raw['sourceScopeId'])
          continue;
        if (link['eventRevision'] != raw['revision'] ||
            !const {'advance', 'refundCredit'}.contains(link['kind']) ||
            raw['privateAccountId'] == null) {
          throw const FormatException('crypto_payment_historical_group');
        }
        CryptoPaymentSemantics.cash(
          raw: cashRaw,
          before: cashRaw,
          event: PaymentEvent.fromJson(disclosure.disclosure),
          scopeId: cash.record['scopeId'],
          movementId: _id(cash.record),
          kind: link['kind'],
          legId: link['legId'],
          accountId: raw['privateAccountId'],
        );
        final hash = await context.codec.digest(
          Map<String, dynamic>.from(
            (cash.wire['authorization'] as Map)['recordProof'] as Map,
          ),
        );
        _historicalGroupWitnesses[hash] = _PreparedPaymentWitness(
          disclosure,
          pins,
        );
      }
    }
  }

  /// Shape validation of an already authenticated opaque-chain beforeimage.
  /// Call after document hydration. This deliberately creates no current
  /// issuer, uniqueness, completeness or balance memo.
  Future<void> validateHistoryPayload(
    CryptoProjectionRecord value,
    Map<String, dynamic> raw,
  ) async {
    if (!types.contains(value.record['type'])) return;
    await projectRecord(value, raw);
  }

  Future<void> _prepareRecords(List<CryptoProjectionRecord> records) async {
    await _prepareHistoricalCompanions(records);
    for (final value in records.where((v) => !v.historicalOnly)) {
      if (types.contains(value.record['type']) && value.plaintext != null) {
        final envelope = jsonDecode(utf8.decode(value.plaintext!)) as Map;
        final raw =
            await context.expandPayload?.call(
              value,
              Map<String, dynamic>.from(envelope['payload'] as Map),
            ) ??
            Map<String, dynamic>.from(envelope['payload'] as Map);
        final expected = await _unique(
          value.record['scopeId'],
          value.record['type'],
          raw,
        );
        if (CryptoBusinessJson.canonical(
              value.record['metadata']['uniqueRefs'],
            ) !=
            CryptoBusinessJson.canonical([expected])) {
          throw const FormatException('crypto_payment_unique_binding');
        }
        _preparedUnique[await context.codec.digest(
              Map<String, dynamic>.from(
                (value.wire['authorization'] as Map)['recordProof'] as Map,
              ),
            )] =
            expected;
        if (value.migrationOrigin != null) {
          validateCryptoMigrationPaymentBaseline(
            origin: value.migrationOrigin!,
            record: value.record,
            recordProofHash: await context.codec.digest(
              Map<String, dynamic>.from(
                (value.wire['authorization'] as Map)['recordProof'] as Map,
              ),
            ),
            raw: raw,
          );
          continue;
        }
      }
      if (!const {
            'cashMovement',
            'paymentProjection',
          }.contains(value.record['type']) ||
          value.plaintext == null) {
        continue;
      }
      final envelope = jsonDecode(utf8.decode(value.plaintext!));
      if (envelope is! Map || envelope['payload'] is! Map) {
        throw const FormatException('crypto_payment_envelope');
      }
      final raw =
          await context.expandPayload?.call(
            value,
            Map<String, dynamic>.from(envelope['payload'] as Map),
          ) ??
          Map<String, dynamic>.from(envelope['payload'] as Map);
      final witness = raw['paymentSourceWitness'];
      if (witness == null) continue;
      if (witness is! Map ||
          witness['version'] != 2 ||
          witness.length != 5 ||
          witness['disclosure'] is! Map) {
        throw const FormatException('crypto_payment_witness');
      }
      final helper = CryptoScopedExports(context.access);
      final scope = value.record['scopeId'] as String;
      final current = await context.access.currentHead(scope, online: true);
      final certificate = Map<String, dynamic>.from(
        witness['certificateProof'] as Map,
      );
      final body =
          CryptoJson.decode(cryptoBase64(certificate['commandBase64'])) as Map;
      final targetHash = await context.codec.digest(
        Map<String, dynamic>.from(
          (value.wire['authorization'] as Map)['recordProof'] as Map,
        ),
      );
      if (_historicalGroupWitnesses.containsKey(targetHash)) {
        await _preparedWitness(
          CryptoBusinessProjection(
            record: value.record,
            raw: raw,
            previousRaw: null,
            wire: value.wire,
          ),
        );
        continue;
      }
      VerifiedScopedDisclosure verified;
      final confirmed = await _confirmedFactsFor(value, raw, targetHash);
      if (confirmed != null) {
        verified = confirmed;
      } else if (body['membershipHeadHash'] != current.headHash) {
        verified = await helper.verifyHistoricalTarget(value.wire);
      } else {
        try {
          final batch = Map<String, dynamic>.from(
            (value.wire['authorization'] as Map)['batchCommitment'] as Map,
          );
          verified = await helper.verify(
            targetScopeId: scope,
            purpose: 'paymentSource',
            disclosure: Map<String, dynamic>.from(witness['disclosure'] as Map),
            disclosureSaltBase64: witness['disclosureSaltBase64'],
            delegationProof: Map<String, dynamic>.from(
              witness['delegationProof'] as Map,
            ),
            certificateProof: certificate,
            targetRecord: value.record,
            batchCommitment: Map<String, dynamic>.from(
              CryptoJson.decode(cryptoBase64(batch['commandBase64'])) as Map,
            ),
          );
        } on CryptoAuthorityPending {
          verified = await helper.verifyHistoricalTarget(value.wire);
        } on FormatException catch (error) {
          if (error.message != 'scoped_export_source_rollback') rethrow;
          verified = await helper.verifyHistoricalTarget(value.wire);
        }
      }
      final hash = await context.codec.digest(
        Map<String, dynamic>.from(
          (value.wire['authorization'] as Map)['recordProof'] as Map,
        ),
      );
      final pins = <String, String?>{};
      for (final key in [
        'scope2:$p:$scope',
        'directory2:$p:$actor',
        if (!verified.historicalEvidence) ...[
          'directory2:$p:${body['accountId']}',
          'scopedAuthority2:$p:$scope:${body['accountId']}',
        ],
      ]) {
        pins[key] = await context.account.store.secure.read(key);
      }
      final oldMemo = _preparedWitnesses[hash];
      _preparedWitnesses[hash] = _PreparedPaymentWitness(
        verified,
        pins,
        confirmedByTargetProofHash: confirmed == null
            ? null
            : oldMemo?.confirmedByTargetProofHash,
      );
      if (value.record['type'] == 'paymentProjection' &&
          !verified.historicalEvidence &&
          confirmed == null) {
        final expected = CryptoScopedExportWorkflow.paymentDisclosure(raw);
        if (CryptoBusinessJson.canonical(expected) !=
            CryptoBusinessJson.canonical(verified.disclosure)) {
          throw const FormatException('crypto_payment_projection_disclosure');
        }
        final latest = _LatestPaymentFacts(
          verified,
          Map<String, dynamic>.from(raw),
          value.wire,
          pins,
          hash,
        );
        _latestFacts['${value.record['scopeId']}:${raw['sourceScopeId']}:${raw['eventId']}'] =
            latest;
        await _prepareCashConfirmations(value, raw, latest);
      }
    }
    for (final value in records.where(
      (v) =>
          !v.historicalOnly &&
          v.record['type'] == 'paymentProjection' &&
          v.migrationOrigin == null,
    )) {
      if (value.plaintext == null) continue;
      final envelope = jsonDecode(utf8.decode(value.plaintext!)) as Map;
      final raw =
          await context.expandPayload?.call(
            value,
            Map<String, dynamic>.from(envelope['payload'] as Map),
          ) ??
          Map<String, dynamic>.from(envelope['payload'] as Map);
      if (raw['state'] != 'complete') continue;
      final hash = await context.codec.digest(
        Map<String, dynamic>.from(
          (value.wire['authorization'] as Map)['recordProof'] as Map,
        ),
      );
      if (_preparedWitnesses[hash]?.confirmedByTargetProofHash != null) {
        continue;
      }
      await _verifyCashManifest(raw, value.record);
      _preparedManifests.add(
        await context.codec.digest(
          Map<String, dynamic>.from(
            (value.wire['authorization'] as Map)['recordProof'] as Map,
          ),
        ),
      );
    }
  }

  Future<VerifiedScopedDisclosure> _preparedWitness(
    CryptoBusinessProjection value,
  ) async {
    final wire = value.wire;
    if (wire == null) throw const CryptoProjectionPending();
    final hash = await context.codec.digest(
      Map<String, dynamic>.from(
        (wire['authorization'] as Map)['recordProof'] as Map,
      ),
    );
    final prepared =
        _preparedWitnesses[hash] ?? _historicalGroupWitnesses[hash];
    if (prepared == null) throw const CryptoProjectionPending();
    for (final pin in prepared.pins.entries) {
      if (await context.account.store.secure.read(pin.key) != pin.value) {
        throw const CryptoProjectionPending();
      }
    }
    if (!context.account.directory.isCurrent()) {
      throw const CryptoProjectionPending();
    }
    return prepared.disclosure;
  }

  Future<VerifiedScopedDisclosure> _witness(
    CryptoBusinessProjection value, {
    required bool forWrite,
  }) async {
    if (!forWrite) return _preparedWitness(value);
    final witness = value.raw?['paymentSourceWitness'];
    if (witness is! Map || witness.length != 5 || witness['version'] != 2) {
      throw const CryptoProjectionPending();
    }
    return CryptoScopedExports(context.access).verify(
      targetScopeId: value.record['scopeId'],
      purpose: 'paymentSource',
      disclosure: Map<String, dynamic>.from(witness['disclosure'] as Map),
      disclosureSaltBase64: witness['disclosureSaltBase64'],
      delegationProof: Map<String, dynamic>.from(
        witness['delegationProof'] as Map,
      ),
      certificateProof: Map<String, dynamic>.from(
        witness['certificateProof'] as Map,
      ),
      targetRecord: value.record,
      batchCommitment: {
        'batchId': value.record['batchId'],
        'recordDigests': [
          (CryptoJson.decode(
                cryptoBase64(witness['certificateProof']['commandBase64']),
              )
              as Map)['sourceRecordProofHash'],
        ],
      },
      rememberFloor: false,
    );
  }

  bool supports(String operation) => const {
    'finance3.payments',
    'finance3.paymentCommit',
    'finance3.paymentProject',
    'finance3.paymentReimburse',
  }.contains(operation);
  bool supportsType(String type) => types.contains(type);
  String get p => context.partition;
  String get actor => context.account.directory.accountId;
  int _localRevision(Map<String, Object?> row) {
    final legacy = row['legacy_revision'] as int;
    final revision = row['crypto_revision'] as int;
    return row['revision_namespace'] == 'legacy' || legacy > 0
        ? legacy + revision - 1
        : revision;
  }

  Map<String, dynamic> _raw(Map<String, Object?> row) =>
      Map<String, dynamic>.from(
        jsonDecode(row['raw_payload'] as String) as Map,
      );
  String _id(Map record) =>
      (record['_canonicalId'] ??
              (record['metadata'] as Map?)?['identity']?['canonicalId'] ??
              record['id'])
          as String;
  Map<String, dynamic>? validateRaw(
    String domain,
    String type,
    Map<String, dynamic> raw,
  ) {
    if (domain != 'finance' || !types.contains(type)) return null;
    switch (type) {
      case 'paymentEvent':
        PaymentEvent.fromJson(raw);
      case 'paymentProjection':
        PaymentProjection.fromJson(raw);
      case 'cashMovement':
        PaymentCashMovement.fromJson(raw);
    }
    if (raw['paymentFormat'] != 2) {
      throw const FormatException('crypto_payment_contract');
    }
    return raw;
  }

  Future<Map<String, dynamic>?> projectRecord(
    CryptoProjectionRecord value,
    Map<String, dynamic> raw,
  ) async {
    if (!types.contains(value.record['type'])) return null;
    if (value.migrationOrigin != null) {
      validateCryptoMigrationPaymentBaseline(
        origin: value.migrationOrigin!,
        record: value.record,
        recordProofHash: await context.codec.digest(
          Map<String, dynamic>.from(
            (value.wire['authorization'] as Map)['recordProof'] as Map,
          ),
        ),
        raw: raw,
      );
    } else {
      validateRaw('finance', value.record['type'], raw);
    }
    final id = _id(value.record);
    if ((value.record['type'] == 'cashMovement' ? raw['id'] : raw['eventId']) !=
        id) {
      throw const FormatException('crypto_payment_identity');
    }
    return raw;
  }

  List<Map<String, dynamic>>? references(
    String type,
    Map<String, dynamic>? raw,
  ) {
    if (raw == null || !types.contains(type)) return null;
    if (type == 'paymentEvent') {
      return [
        {
          'scopeId': raw['sourceScopeId'],
          'id': raw['sourceEntryId'],
          'type': 'financeEntry',
        },
      ];
    }
    // Cross-scope source relations exist only inside the target finance AEAD
    // disclosure and its opaque scoped-export witness.
    if (type == 'paymentProjection') {
      final id = raw['privateAccountId'];
      if (id == null) return [];
      if (!isCryptoCanonicalUuid(id)) {
        throw const FormatException('crypto_payment_private_account');
      }
      return [
        {'id': id, 'type': 'personalFinanceAccount'},
      ];
    }
    return [
      {
        'scopeId': raw['paymentLink']['accountScopeId'],
        'id': raw['accountId'],
        'type': raw['paymentLink']['kind'] == 'refundDebit'
            ? 'financeAccount'
            : 'personalFinanceAccount',
      },
    ];
  }

  Future<List<Map<String, Object?>>> _rows(
    String scope,
    String type,
  ) => context.database.rows(
    'SELECT * FROM crypto_business_records WHERE partition=? AND scope_id=? AND domain=? AND type=? AND deleted=0 AND raw_payload IS NOT NULL',
    [p, scope, 'finance', type],
  );
  Future<Map<String, Object?>> _require(
    String scope,
    String id,
    String type,
  ) async {
    final row = await context.record(scope, 'finance', id, type: type);
    if (row == null || row['deleted'] == 1 || row['raw_payload'] == null) {
      throw const CollaborationException('parent_missing');
    }
    return row;
  }

  Future<Map<String, dynamic>> _account(
    String scope,
    String id,
    String type,
    String currency,
  ) async {
    await context.pullVerified(scope, 'finance');
    final raw = _raw(await _require(scope, id, type));
    if (raw['archived'] == true) {
      throw const CollaborationException('parent_missing');
    }
    if (raw['currency'] != currency) {
      throw const CollaborationException('currency_mismatch');
    }
    return raw;
  }

  Future<String> _unique(
    String scope,
    String type,
    Map<String, dynamic> raw,
  ) async {
    return _uniqueness.tag(
      scope,
      purpose: 'paymentUniqueness',
      value: {
        'version': 2,
        'type': type,
        'id': type == 'paymentEvent'
            ? raw['sourceEntryId']
            : raw['id'] ?? raw['eventId'],
      },
    );
  }

  Future<List<Map<String, dynamic>>> _publish(
    String operationId,
    String hash,
    List<_PaymentWrite> writes,
  ) async {
    final saved = await context.stagedGroup(operationId, hash);
    if (saved != null) {
      return context.publishPreparedGroup(
        operationId: operationId,
        localHash: hash,
        recordProofs: (saved['records'] as List).cast<Map<String, dynamic>>(),
        commitment: Map<String, dynamic>.from(saved['commitment'] as Map),
        exportBindings: [
          for (final binding in saved['exportBindings'] as List? ?? const [])
            Map<String, dynamic>.from(binding as Map),
        ],
      );
    }
    final journal = await _paymentGroupJournal(operationId, hash, writes);
    writes = [
      for (final value in journal['writes'] as List)
        _PaymentWrite(
          value['scope'],
          value['id'],
          value['type'],
          value['before'] == null
              ? null
              : Map<String, Object?>.from(value['before'] as Map),
          Map<String, dynamic>.from(value['raw'] as Map),
        ),
    ];
    final batch = journal['batchId'] as String,
        proofs = <Map<String, dynamic>>[],
        versions = <Map<String, dynamic>>[],
        projections = <CryptoBusinessProjection>[];
    final keys = <String, CryptoWriteContext>{};
    final signer = await context.account.signingKey();
    try {
      for (var index = 0; index < writes.length; index++) {
        final w = writes[index];
        final write = keys[w.scope] ??= await context.access.writeContext(
          w.scope,
          'finance',
          online: true,
        );
        final head = await context.access.headAt(w.scope, write.headHash);
        context.financeAuthorityMembers[head.headHash] = {
          for (final member in head.members) member['accountId'] as String,
        };
        final expected = w.before?['crypto_revision'] as int? ?? 0;
        final metadata = await context.businessMetadata(
          scopeId: w.scope,
          domain: 'finance',
          type: w.type,
          canonicalId: w.id,
          expectedRevision: expected,
          rawPayload: w.raw,
          uniqueRefs: types.contains(w.type)
              ? [await _unique(w.scope, w.type, w.raw)]
              : null,
          stagedReferenceVersions: versions,
        );
        final address = context.address(w.scope, 'finance', w.type, w.id);
        if (w.type == 'cashMovement' &&
            w.raw['paymentLink']['sourceScopeId'] != w.scope &&
            w.raw['paymentSourceWitness'] == null) {
          await _bindCrossScopeCash(journal, operationId, index, w, proofs, {
            'scopeId': w.scope,
            'domain': 'finance',
            'type': w.type,
            'id': address.wireId,
            'batchId': batch,
            'operationId': operationId,
            'expectedRevision': expected,
            'membershipHeadHash': write.headHash,
            'accountId': actor,
            'deviceId': context.account.deviceId,
            'metadata': metadata,
          });
        }
        late Map<String, dynamic> proof;
        final retained = journal['proofs'] as List;
        if (index < retained.length) {
          proof = Map<String, dynamic>.from(retained[index] as Map);
          final own = await context.account.directory.requireFresh();
          final body = context.codec.crypto.verifyDomain(
            proof,
            cryptoBase64(
              own.activeDevice(context.account.deviceId)['signingKeyBase64'],
              length: 32,
            ),
            'JivieE2EE/record/v2\n',
          );
          context.codec.validateUntrustedRecord(body);
          if (body['scopeId'] != w.scope ||
              body['id'] != address.wireId ||
              body['type'] != w.type ||
              body['accountId'] != actor ||
              body['deviceId'] != context.account.deviceId ||
              body['batchId'] != batch ||
              body['expectedRevision'] != expected ||
              body['membershipHeadHash'] != write.headHash ||
              body['epoch'] != write.epoch ||
              body['accessRevision'] != write.accessRevision ||
              body['previousRecordHash'] !=
                  (w.before?['record_proof_hash'] ?? cryptoZeroHash)) {
            throw const CryptoAuthorityPending(
              'crypto_payment_group_authority_changed',
            );
          }
        } else {
          final envelope = context.encodePayload == null
              ? w.raw
              : await context.encodePayload!(
                  w.scope,
                  'finance',
                  w.type,
                  w.id,
                  w.raw,
                  operationId,
                );
          metadata['blobIds'] = {
            <String>[
              ...metadata['blobIds'] as List<String>,
              ...?context.blobIds?.call(envelope),
            ],
          }.expand((v) => v).toSet().toList()..sort();
          final bytes = Uint8List.fromList(
            utf8.encode(
              jsonEncode({
                'format': 2,
                'identity': address.identity,
                'payload': envelope,
              }),
            ),
          );
          try {
            proof = context.codec.sealRecord(
              serverId: context.account.directory.session.profile.serverId,
              accountId: actor,
              deviceId: context.account.deviceId,
              batchId: batch,
              scopeId: w.scope,
              id: address.wireId,
              type: w.type,
              expectedRevision: expected,
              epoch: write.epoch,
              accessRevision: write.accessRevision,
              membershipHeadHash: write.headHash,
              domain: 'finance',
              contentContract: 3,
              operationId: operationId,
              previousRecordHash:
                  w.before?['record_proof_hash'] as String? ?? cryptoZeroHash,
              deleted: false,
              plaintext: bytes,
              metadata: metadata,
              contentKey: write.key.key,
              signingKey: signer.key,
            );
          } finally {
            bytes.fillRange(0, bytes.length, 0);
          }
          retained.add(proof);
          await _savePaymentGroup(journal, operationId);
        }
        proofs.add(proof);
        final digest = await context.codec.digest(proof);
        versions.add({
          'scopeId': w.scope,
          'domain': 'finance',
          'id': address.wireId,
          'revision': expected + 1,
          'recordProofHash': digest,
        });
        final body = Map<String, dynamic>.from(
          CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map,
        );
        projections.add(
          CryptoBusinessProjection(
            record: {...body, '_canonicalId': w.id, '_proofHash': digest},
            raw: w.raw,
            previousRaw: w.before?['raw_payload'] == null
                ? null
                : _raw(w.before!),
          ),
        );
      }
      await validateFinanceGroup(projections, forWrite: true);
      await CryptoBusinessFinance(
        context,
      ).validate(projections, forWrite: true);
      final commitment = await context.codec.commitBatch(
        serverId: context.account.directory.session.profile.serverId,
        accountId: actor,
        deviceId: context.account.deviceId,
        batchId: batch,
        records: proofs,
        signingKey: signer.key,
        projectionToken: (r) async =>
            context.codec.projectionGroupToken(r, keys[r['scopeId']]!.key.key),
      );
      return await context.publishPreparedGroup(
        operationId: operationId,
        localHash: hash,
        recordProofs: proofs,
        commitment: commitment,
        exportBindings: [
          for (final binding in journal['exportBindings'] as List)
            Map<String, dynamic>.from(binding as Map),
        ],
      );
    } finally {
      signer.release();
      for (final k in keys.values) {
        k.key.release();
      }
    }
  }

  Future<Map<String, dynamic>> dispatch(
    String operation,
    Map<String, Object?> params,
  ) => context.access.withVerifiedOperation(() => _dispatch(operation, params));

  Future<Map<String, dynamic>> _dispatch(
    String operation,
    Map<String, Object?> params,
  ) async {
    if (!supports(operation)) {
      throw const CollaborationException('unsupported_operation');
    }
    final scope = params['scopeId'];
    if (!isCryptoCanonicalUuid(scope)) {
      throw const FormatException('crypto_payment_scope');
    }
    if (operation == 'finance3.payments') return _snapshot(scope as String);
    final request = params['requestId'];
    if (!isCryptoCanonicalUuid(request)) {
      throw const FormatException('crypto_payment_request');
    }
    final hash = await CryptoBusinessJson.hash({
      'operation': operation,
      'params': params,
    });
    final staged = await context.stagedGroup(request as String, hash);
    if (staged != null) {
      await _publish(request, hash, []);
      return _finishTargets(scope as String, params, request, hash);
    }
    await context.pullVerified(scope as String, 'finance');
    if (operation == 'finance3.paymentCommit') {
      await _commit(scope, params, request, hash);
    } else if (operation == 'finance3.paymentReimburse') {
      await _reimburse(scope, params, request, hash);
    } else {
      await _project(scope, params, request, hash);
    }
    return _finishTargets(scope, params, request, hash);
  }

  Future<Map<String, dynamic>> _eventReply(String scope, String id) async => {
    'event': _raw(await _require(scope, id, 'paymentEvent')),
  };
  Future<void> _commit(
    String scope,
    Map params,
    String request,
    String hash,
  ) async {
    final before = await _require(scope, params['entryId'], 'financeEntry'),
        entry = _raw(await _require(scope, params['entryId'], 'financeEntry'));
    if (_localRevision(before) != params['expectedEntryRevision'] ||
        entry['kind'] != 'expense' ||
        entry['status'] != 'posted' ||
        entry['accountScopeId'] != null ||
        entry['payerAccountId'] != null && entry['payerAccountId'] != actor ||
        entry['paidAt'] != null &&
            DateTime.parse(entry['paidAt']) !=
                DateTime.parse(params['paidAt'])) {
      throw const CollaborationException('payment_source_changed');
    }
    if ((await _rows(
      scope,
      'paymentEvent',
    )).any((r) => _raw(r)['sourceEntryId'] == params['entryId'])) {
      throw const CollaborationException('payment_already_linked');
    }
    final paidAt = DateTime.parse(params['paidAt'] as String).toUtc();
    final next = {
      ...entry,
      'paidAt': paidAt.toIso8601String(),
      'occurredAt': paidAt.toIso8601String(),
      'payerAccountId': actor,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    };
    final event = PaymentEvent(
      eventId: params['eventId'],
      sourceScopeId: scope,
      sourceEntryId: params['entryId'],
      sourceRevision: _localRevision(before) + 1,
      payerAccountId: actor,
      amountMinor: entry['amountMinor'],
      currency: entry['currency'],
      paidAt: paidAt,
      expectReimbursement: params['expectReimbursement'],
      revision: 1,
    );
    final writes = [
      _PaymentWrite(scope, params['entryId'], 'financeEntry', before, next),
      _PaymentWrite(scope, event.eventId, 'paymentEvent', null, {
        ...event.toJson(),
        'paymentFormat': 2,
        'sourceState': 'active',
      }),
    ];
    await _publish(request, hash, writes);
  }

  Future<void> _project(
    String scope,
    Map params,
    String request,
    String hash,
  ) async {
    final event = PaymentEvent.fromJson(
      _raw(await _require(scope, params['eventId'], 'paymentEvent')),
    );
    final journals = await context.database.rows(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='crypto_export_drafts'",
    );
    var retainedIntent = false;
    if (journals.isNotEmpty) {
      final saved = await context.database.rows(
        'SELECT payload FROM crypto_export_drafts WHERE partition=? AND action_id=?',
        [p, request],
      );
      for (final row in saved) {
        final journal = jsonDecode(row['payload'] as String) as Map;
        if (journal['operation'] != 'crypto2.payment.catchup') continue;
        if (journal['intentHash'] != hash ||
            journal['sourceScopeId'] != scope ||
            journal['eventId'] != event.eventId) {
          throw const FormatException('crypto_payment_immutable_catchup');
        }
        retainedIntent = true;
      }
    }
    if ((!retainedIntent && event.revision != params['expectedRevision']) ||
        event.payerAccountId != actor) {
      throw const CollaborationException('payment_changed');
    }
    // The durable target catch-up runs after the authenticated source read.
  }

  Future<_PaymentWrite> _cash(
    String scope,
    String id,
    String account,
    int amount,
    String currency,
    DateTime date,
    PaymentEvent event,
    String kind,
    String? leg,
  ) async {
    final before = await _knownPaymentRow(scope, id, 'cashMovement');
    if (before != null) {
      final old = _raw(before);
      final revision = old['paymentLink']?['eventRevision'];
      if (revision is! int || revision > event.revision) {
        throw const FormatException('crypto_payment_cash_facts');
      }
      CryptoPaymentSemantics.cash(
        raw: old,
        before: old,
        event: PaymentEvent.fromJson({...event.toJson(), 'revision': revision}),
        scopeId: scope,
        movementId: id,
        kind: kind,
        legId: leg,
        accountId: account,
      );
      return _PaymentWrite(scope, id, 'cashMovement', before, old);
    }
    final changed = {
      ...PaymentCashMovement(
        id: id,
        accountId: account,
        amountMinor: amount,
        currency: currency,
        paidAt: date,
      ).toJson(),
      'paymentFormat': 2,
      'paymentLink': {
        'version': 1,
        'sourceScopeId': event.sourceScopeId,
        'eventId': event.eventId,
        'eventRevision': event.revision,
        'kind': kind,
        'legId': leg,
        'accountScopeId': scope,
      },
    };
    final raw = Map<String, dynamic>.from(
      mergeCryptoPaymentPayload(before == null ? null : _raw(before), changed)
          as Map,
    );
    return _PaymentWrite(scope, id, 'cashMovement', before, raw);
  }

  Future<void> _reimburse(
    String scope,
    Map params,
    String request,
    String hash,
  ) async {
    final before = await _require(scope, params['eventId'], 'paymentEvent'),
        old = _raw(await _require(scope, params['eventId'], 'paymentEvent')),
        event = PaymentEvent.fromJson(
          _raw(await _require(scope, params['eventId'], 'paymentEvent')),
        );
    final amount = params['amountMinor'],
        paid = DateTime.parse(params['paidAt'] as String).toUtc(),
        accountScope = params['organizationAccountScopeId'] ?? scope;
    if (event.revision != params['expectedRevision']) {
      throw const CollaborationException('payment_changed');
    }
    final paidSource = _raw(
      await _require(scope, event.sourceEntryId, 'financeEntry'),
    );
    if (paidSource['kind'] != 'expense' ||
        paidSource['status'] != 'posted' ||
        paidSource['amountMinor'] != event.amountMinor ||
        paidSource['currency'] != event.currency ||
        paidSource['payerAccountId'] != event.payerAccountId ||
        paidSource['paidAt'] == null ||
        DateTime.parse(paidSource['paidAt'] as String).toUtc() !=
            event.paidAt) {
      throw const CollaborationException('payment_source_changed');
    }
    if (old['paymentFormat'] != 2) {
      throw const CryptoAuthorityPending(
        'crypto_payment_baseline_transition_pending',
      );
    }
    if (!event.expectReimbursement ||
        amount is! int ||
        amount <= 0 ||
        BigInt.from(amount) + event.reimbursedTotal >
            BigInt.from(event.amountMinor) ||
        event.reimbursements.length >= 500 ||
        event.reimbursements.any((l) => l.legId == params['legId']) ||
        paid.isBefore(event.paidAt)) {
      throw const CollaborationException('reimbursement_exceeds_payment');
    }
    await _account(
      accountScope,
      params['organizationAccountId'],
      'financeAccount',
      event.currency,
    );
    final nextRaw = <String, dynamic>{
      ...old,
      'revision': event.revision + 1,
      'reimbursements': [
        ...old['reimbursements'] as List,
        PaymentReimbursement(
          legId: params['legId'],
          amountMinor: amount,
          paidAt: paid,
          approvedByAccountId: actor,
          organizationAccountId: params['organizationAccountId'],
          organizationAccountScopeId: accountScope,
        ).toJson(),
      ],
    };
    final next = PaymentEvent.fromJson(nextRaw);
    await _publish(request, hash, [
      _PaymentWrite(scope, event.eventId, 'paymentEvent', before, {
        ...nextRaw,
        'paymentFormat': 2,
        'sourceState': old['sourceState'],
      }),
      await _cash(
        accountScope,
        params['legId'],
        params['organizationAccountId'],
        -amount,
        event.currency,
        paid,
        next,
        'refundDebit',
        params['legId'],
      ),
    ]);
  }

  Future<Map<String, dynamic>> _snapshot(String scope) async {
    await context.pullVerified(scope, 'finance');
    final events = [
          for (final r in await _rows(scope, 'paymentEvent')) _raw(r),
        ],
        projections = <Map<String, dynamic>>[];
    var pending = 0;
    for (final row in await _rows(scope, 'paymentProjection')) {
      final raw = _raw(row), projection = PaymentProjection.fromJson(raw);
      var state = projection.state;
      try {
        await context.pullVerified(projection.event.sourceScopeId, 'finance');
        final source = PaymentEvent.fromJson(
          _raw(
            await _require(
              projection.event.sourceScopeId,
              projection.eventId,
              'paymentEvent',
            ),
          ),
        );
        if (source.revision != projection.event.revision) {
          state = PaymentProjectionState.pending;
          pending++;
        }
      } on CryptoAuthorityPending {
        state = PaymentProjectionState.blocked;
        pending++;
      } on CollaborationException {
        state = PaymentProjectionState.blocked;
        pending++;
      }
      projections.add({...raw, 'state': state.name});
    }
    final read = await context.access.readContext(scope, 'finance');
    final checkpoints = await context.database.rows(
      'SELECT sequence FROM crypto_domain_checkpoints WHERE partition=? AND scope_id=? AND domain=? AND head_hash=? ORDER BY sequence DESC LIMIT 1',
      [p, scope, 'finance', read.headHash],
    );
    final scopeState = await context.database.rows(
      'SELECT complete FROM crypto_scope_state WHERE partition=? AND scope_id=? AND domain=?',
      [p, scope, 'finance'],
    );
    final observedComplete =
        checkpoints.isNotEmpty &&
        scopeState.length == 1 &&
        scopeState.single['complete'] == 1;
    return {
      'events': events,
      'projections': projections,
      'cashMovements': [
        for (final r in await _rows(scope, 'cashMovement')) _raw(r),
      ],
      'accessRevision': read.accessRevision,
      'scopeSequence': checkpoints.isEmpty ? 0 : checkpoints.single['sequence'],
      'complete': observedComplete && pending == 0,
      'pendingCount': pending,
    };
  }

  Future<void> validateFinanceGroup(
    List<CryptoBusinessProjection> batch, {
    required bool forWrite,
  }) async {
    if (forWrite && batch.any((v) => v.historicalOnly)) {
      throw const FormatException('crypto_payment_historical_write');
    }
    batch = batch.where((v) => !v.historicalOnly).toList();
    final events = <String, PaymentEvent>{};
    final sourceCandidates = <String, CryptoBusinessProjection>{};
    for (final value in batch.where((v) => types.contains(v.record['type']))) {
      if (value.raw == null) {
        throw const FormatException('crypto_payment_delete_forbidden');
      }
      final baseline = !forWrite && value.migrationOrigin != null;
      if (baseline) {
        if (value.wire == null) throw const CryptoProjectionPending();
        validateCryptoMigrationPaymentBaseline(
          origin: value.migrationOrigin!,
          record: value.record,
          recordProofHash: await context.codec.digest(
            Map<String, dynamic>.from(
              (value.wire!['authorization'] as Map)['recordProof'] as Map,
            ),
          ),
          raw: value.raw!,
        );
      } else {
        validateRaw('finance', value.record['type'], value.raw!);
      }
      final String? unique;
      if (forWrite) {
        unique = await _unique(
          value.record['scopeId'],
          value.record['type'],
          value.raw!,
        );
      } else if (value.wire != null) {
        unique =
            _preparedUnique[await context.codec.digest(
              Map<String, dynamic>.from(
                (value.wire!['authorization'] as Map)['recordProof'] as Map,
              ),
            )];
      } else {
        unique = null;
      }
      if (unique == null) throw const CryptoProjectionPending();
      if (CryptoBusinessJson.canonical(
            value.record['metadata']['uniqueRefs'],
          ) !=
          CryptoBusinessJson.canonical([unique])) {
        throw const FormatException('crypto_payment_unique_binding');
      }
      if (baseline) continue;
      if (value.record['type'] != 'paymentEvent') continue;
      final raw = value.raw!;
      final scope = value.record['scopeId'] as String;
      final event = PaymentEvent.fromJson(raw);
      if (event.sourceScopeId != scope) {
        throw const FormatException('crypto_payment_source_scope');
      }
      final staged = batch
          .where(
            (candidate) =>
                candidate.record['scopeId'] == scope &&
                candidate.record['domain'] == 'finance' &&
                candidate.record['type'] == 'financeEntry' &&
                _id(candidate.record) == event.sourceEntryId,
          )
          .toList();
      if (staged.length > 1) {
        throw const FormatException('crypto_payment_duplicate_source');
      }
      final current = await context.record(
        scope,
        'finance',
        event.sourceEntryId,
        type: 'financeEntry',
      );
      late Map<String, dynamic> paid;
      late int sourceRevision;
      if (staged.isNotEmpty) {
        final source = staged.single;
        if (source.raw == null || current == null) {
          throw const CryptoProjectionPending();
        }
        paid = source.raw!;
        final legacy = current['legacy_revision'] as int;
        final cryptoRevision = (source.record['expectedRevision'] as int) + 1;
        sourceRevision = current['revision_namespace'] == 'legacy' || legacy > 0
            ? legacy + cryptoRevision - 1
            : cryptoRevision;
      } else {
        final wire = context
            .address(scope, 'finance', 'financeEntry', event.sourceEntryId)
            .wireId;
        final row = await CryptoBusinessReferences(
          context,
        ).resolve(value.record, scope, 'finance', wire);
        if (row['deleted'] == 1 ||
            row['raw_payload'] == null ||
            current == null) {
          throw const CryptoProjectionPending();
        }
        paid = _raw(row);
        if (row['local_revision'] is int) {
          sourceRevision = row['local_revision'] as int;
        } else if (current['crypto_revision'] == row['crypto_revision'] &&
            current['record_proof_hash'] == row['record_proof_hash']) {
          final legacy = current['legacy_revision'] as int;
          final cryptoRevision = row['crypto_revision'] as int;
          sourceRevision =
              current['revision_namespace'] == 'legacy' || legacy > 0
              ? legacy + cryptoRevision - 1
              : cryptoRevision;
        } else {
          // A current legacy offset cannot authenticate an arbitrary old
          // branch. Historical mappings require the verified source lineage.
          throw const CryptoProjectionPending();
        }
      }
      // Later harmless source edits may have a larger local revision. The
      // immutable event still names its original paid-source revision.
      if (value.previousRaw != null) {
        if (sourceRevision < event.sourceRevision) {
          throw const FormatException('crypto_payment_source_revision');
        }
        sourceRevision = event.sourceRevision;
      }
      events['$scope:${event.eventId}'] = CryptoPaymentSemantics.event(
        raw: raw,
        before: value.previousRaw,
        scopeId: scope,
        eventId: _id(value.record),
        authorAccountId:
            value.record['authorAccountId'] ?? value.record['accountId'],
        paidSource: paid,
        paidSourceRevision: sourceRevision,
      );
      sourceCandidates['$scope:${event.eventId}'] = value;
    }
    final seenCash = <String>{};
    for (final value in batch.where(
      (v) => v.record['type'] == 'cashMovement' && v.migrationOrigin == null,
    )) {
      final raw = value.raw!, link = raw['paymentLink'];
      if (link is! Map ||
          link['sourceScopeId'] is! String ||
          link['eventId'] is! String) {
        throw const FormatException('crypto_payment_cash_binding');
      }
      final cashScope = value.record['scopeId'] as String;
      final accountType = link['kind'] == 'refundDebit'
          ? 'financeAccount'
          : 'personalFinanceAccount';
      final accountWire = context
          .address(cashScope, 'finance', accountType, raw['accountId'])
          .wireId;
      final account = await CryptoBusinessReferences(
        context,
      ).resolve(value.record, cashScope, 'finance', accountWire);
      if (account['deleted'] == 1 ||
          account['type'] != accountType ||
          account['raw_payload'] == null) {
        throw const CryptoProjectionPending();
      }
      final accountRaw = _raw(account);
      if (accountRaw['currency'] != raw['currency'] ||
          accountRaw['archived'] == true) {
        throw const FormatException('crypto_payment_cash_account');
      }
      var event = events['${link['sourceScopeId']}:${link['eventId']}'];
      // A private catch-up must carry a separately verified scoped-export
      // witness. Until present it has no authority to manufacture cash effects.
      if (event == null || link['kind'] != 'refundDebit') {
        final disclosure = await _witness(value, forWrite: forWrite);
        event = PaymentEvent.fromJson(disclosure.disclosure);
        if (!forWrite && value.wire != null) {
          final hash = await context.codec.digest(
            Map<String, dynamic>.from(
              (value.wire!['authorization'] as Map)['recordProof'] as Map,
            ),
          );
          if (_preparedWitnesses[hash]?.confirmedByTargetProofHash != null) {
            event = PaymentEvent.fromJson({
              ...disclosure.disclosure,
              'revision': link['eventRevision'],
            });
          }
        }
        if (!disclosure.historicalEvidence &&
            disclosure.disclosure['sourceState'] != 'active') {
          throw const FormatException('crypto_payment_source_removed');
        }
        CryptoPaymentSemantics.cash(
          raw: raw,
          before: value.previousRaw,
          event: event,
          scopeId: value.record['scopeId'],
          movementId: _id(value.record),
          kind: link['kind'],
          legId: link['legId'],
          accountId: raw['accountId'],
        );
        if (!seenCash.add(
          '${event.sourceScopeId}:${event.eventId}:${link['kind']}:${link['legId']}',
        )) {
          throw const FormatException('crypto_payment_duplicate_cash');
        }
        continue;
      }
      final scope = value.record['scopeId'] as String;
      final kind = link['kind'];
      if (scope != event.sourceScopeId) {
        final disclosure = await _witness(value, forWrite: forWrite);
        final expected = CryptoScopedExportWorkflow.paymentDisclosure(
          sourceCandidates['${event.sourceScopeId}:${event.eventId}']!.raw!,
        );
        if (CryptoBusinessJson.canonical(expected) !=
            CryptoBusinessJson.canonical(disclosure.disclosure)) {
          throw const FormatException('crypto_payment_cross_scope_disclosure');
        }
        if (forWrite &&
            disclosure.sourceRecordProofHash !=
                sourceCandidates['${event.sourceScopeId}:${event.eventId}']!
                    .record['_proofHash']) {
          throw const FormatException('crypto_payment_cross_scope_source');
        }
      }
      if (!const {'advance', 'refundCredit', 'refundDebit'}.contains(kind)) {
        throw const FormatException('crypto_payment_cash_kind');
      }
      if (kind != 'refundDebit') throw const CryptoProjectionPending();
      final legs = event.reimbursements
          .where((l) => l.legId == link['legId'])
          .toList();
      if (legs.length != 1 ||
          (legs.single.organizationAccountScopeId ?? event.sourceScopeId) !=
              scope) {
        throw const FormatException('crypto_payment_cash_account');
      }
      final leg = legs.single;
      CryptoPaymentSemantics.cash(
        raw: raw,
        before: value.previousRaw,
        event: event,
        scopeId: scope,
        movementId: _id(value.record),
        kind: kind,
        legId: leg.legId,
        accountId: leg.organizationAccountId!,
      );
      if (!seenCash.add(
        '${event.sourceScopeId}:${event.eventId}:${leg.legId}',
      )) {
        throw const FormatException('crypto_payment_duplicate_cash');
      }
    }
    for (final entry in events.entries) {
      final value = sourceCandidates[entry.key]!;
      if (value.previousRaw == null) continue;
      final event = entry.value, leg = event.reimbursements.last;
      if (!seenCash.contains(
        '${event.sourceScopeId}:${event.eventId}:${leg.legId}',
      )) {
        throw const CryptoProjectionPending();
      }
    }
    for (final value in batch.where(
      (v) =>
          v.record['type'] == 'paymentProjection' && v.migrationOrigin == null,
    )) {
      final disclosure = await _witness(value, forWrite: forWrite);
      final raw = value.raw!;
      final known = PaymentEvent.fromJson(raw).toJson();
      known['reimbursements'] = [
        for (final leg in PaymentEvent.fromJson(raw).reimbursements)
          leg.toJson(projection: true),
      ];
      known['sourceState'] = raw['sourceState'];
      final closed = {
        for (final field in CryptoScopedExports.allowedFields['paymentSource']!)
          field: known[field],
      };
      final hash = value.wire == null
          ? null
          : await context.codec.digest(
              Map<String, dynamic>.from(
                (value.wire!['authorization'] as Map)['recordProof'] as Map,
              ),
            );
      final confirmation = hash == null
          ? null
          : _preparedWitnesses[hash]?.confirmedByTargetProofHash;
      if (confirmation == null &&
          CryptoBusinessJson.canonical(closed) !=
              CryptoBusinessJson.canonical(disclosure.disclosure)) {
        throw const FormatException('crypto_payment_projection_disclosure');
      }
      // The issuer attestation confirms selected source facts. Completeness
      // still requires the separately verified exact cash-leg manifest.
      if (raw['state'] == 'complete' && confirmation == null) {
        if (forWrite) {
          await _verifyCashManifest(raw, value.record);
        } else {
          final wire = value.wire;
          if (wire == null ||
              !_preparedManifests.contains(
                await context.codec.digest(
                  Map<String, dynamic>.from(
                    (wire['authorization'] as Map)['recordProof'] as Map,
                  ),
                ),
              )) {
            throw const CryptoProjectionPending();
          }
        }
      }
    }
  }
}

class _PreparedPaymentWitness {
  const _PreparedPaymentWitness(
    this.disclosure,
    this.pins, {
    this.confirmedByTargetProofHash,
  });
  final String? confirmedByTargetProofHash;
  final VerifiedScopedDisclosure disclosure;
  final Map<String, String?> pins;
}
