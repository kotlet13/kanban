import 'crypto_finance_account_choices.dart';
import 'session_crypto_access.dart';
import 'dart:convert';

import '../../domain/collaboration_models.dart' show CollaborationException;
import 'account_directory_v2.dart' show cryptoSha256;
import 'crypto_business_payload.dart';
import 'crypto_record_address.dart';
import 'crypto_business_router.dart';
import 'crypto_business_references.dart';
import 'crypto_inventory_json.dart';
import 'crypto_sync_repository.dart';
import 'crypto_finance_uniqueness.dart';
import 'crypto_project_relocation_target.dart';

/// Financial semantic validation runs before upload and again before any group
/// becomes visible. Missing authorized dependencies are pending, never guessed.
class CryptoBusinessFinance {
  CryptoBusinessFinance(this.context);
  final CryptoBusinessSession context;
  late final _uniqueTags = CryptoFinanceUniqueTags(context.access);

  Future<List<String>> uniqueRefs(
    String scope,
    String type,
    Map<String, dynamic>? raw, {
    CryptoMigrationCandidate? migrationCandidate,
    PreparedProjectRelocationTarget? relocationTarget,
  }) async {
    if (raw == null) return [];
    if (const {
      'paymentEvent',
      'paymentProjection',
      'cashMovement',
    }.contains(type)) {
      return [
        await _uniqueTags.tag(
          scope,
          migrationCandidate: migrationCandidate,
          relocationTarget: relocationTarget,
          purpose: 'paymentUniqueness',
          value: {
            'version': 2,
            'type': type,
            'id': type == 'paymentEvent'
                ? raw['sourceEntryId']
                : raw['id'] ?? raw['eventId'],
          },
        ),
      ];
    }
    if (type == 'taskDerivationResolution') {
      return [
        await cryptoSha256(
          utf8.encode(
            'JivieTaskResolution/v2\n$scope:${raw['intentProofHash']}',
          ),
        ),
      ];
    }
    final ids = <String>[];
    for (final ref in [
      if (raw['taskId'] != null) ['task', raw['taskId']],
    ]) {
      ids.add(
        await cryptoSha256(
          utf8.encode(
            'JivieFinanceUnique/v2\n$scope:${CryptoInventoryJson.canonical(ref)}',
          ),
        ),
      );
    }
    if (raw['recurrenceRuleId'] != null) {
      ids.add(
        await _uniqueTags.tag(
          scope,
          migrationCandidate: migrationCandidate,
          relocationTarget: relocationTarget,
          purpose: 'financeOccurrence',
          value: {
            'version': 2,
            'recurrenceRuleId': raw['recurrenceRuleId'],
            'occurrenceKey': raw['occurrenceKey'],
          },
        ),
      );
    }
    return ids..sort();
  }

  Future<void> outgoing(
    String scope,
    String id,
    String type,
    Map<String, dynamic>? raw,
  ) async {
    final previous = await context.record(scope, 'finance', id, type: type);
    final head = await context.access.currentHead(scope);
    context.financeAuthorityMembers[head.headHash] = {
      for (final m in head.members) m['accountId'] as String,
    };
    await validate([
      CryptoBusinessProjection(
        record: {
          'scopeId': scope,
          'domain': 'finance',
          'id': id,
          'type': type,
          'membershipHeadHash': head.headHash,
          'metadata': {'uniqueRefs': await uniqueRefs(scope, type, raw)},
        },
        raw: raw,
        previousRaw: previous?['raw_payload'] == null
            ? null
            : Map<String, dynamic>.from(
                jsonDecode(previous!['raw_payload'] as String) as Map,
              ),
      ),
    ], forWrite: true);
  }

  Future<void> validate(
    List<CryptoBusinessProjection> batch, {
    bool forWrite = false,
  }) async {
    if (forWrite && batch.any((v) => v.historicalOnly)) {
      throw const FormatException('crypto_projection_historical_write');
    }
    if (context.validateFinanceExtension != null &&
        batch.any((entry) => entry.record['domain'] == 'finance')) {
      await context.validateFinanceExtension!(batch, forWrite: forWrite);
    } else if (batch.any(
      (entry) =>
          context.supportsFinanceExtension?.call(
            entry.record['type'] as String,
          ) ==
          true,
    )) {
      throw const CryptoAuthorityPending('crypto_finance_type_pending');
    }
    Map<String, dynamic>? semanticSource;
    Future<Map<String, dynamic>?> lookup(
      String scope,
      String domain,
      String id, {
      Set<String>? types,
      bool bound = false,
    }) async {
      if (types != null &&
          types.map(cryptoRecordSourceKind).toSet().length != 1) {
        throw const FormatException('crypto_finance_reference_namespace');
      }
      final reference = bound && !forWrite
          ? ((semanticSource?['metadata'] as Map?)?['referenceVersions']
                    as List?)
                ?.whereType<Map>()
                .where(
                  (ref) =>
                      ref['scopeId'] == scope &&
                      ref['domain'] == domain &&
                      types != null &&
                      ref['id'] ==
                          context
                              .address(scope, domain, types.first, id)
                              .wireId,
                )
                .firstOrNull
          : null;
      final stagedRows = <CryptoBusinessProjection>[];
      for (final candidate in batch) {
        if (candidate.record['scopeId'] != scope ||
            candidate.record['domain'] != domain ||
            (candidate.record['_canonicalId'] ?? candidate.record['id']) !=
                id ||
            (types != null && !types.contains(candidate.record['type']))) {
          continue;
        }
        if (reference == null) {
          if (!candidate.historicalOnly) stagedRows.add(candidate);
        } else if (candidate.wire?['revision'] == reference['revision'] &&
            await context.codec.digest(
                  Map<String, dynamic>.from(
                    (candidate.wire!['authorization'] as Map)['recordProof']
                        as Map,
                  ),
                ) ==
                reference['recordProofHash']) {
          stagedRows.add(candidate);
        }
      }
      if (stagedRows.length > 1) {
        throw const FormatException('crypto_finance_reference_duplicate');
      }
      final staged = stagedRows.firstOrNull;
      if (staged != null) {
        if (types != null && !types.contains(staged.record['type'])) {
          throw const FormatException('crypto_finance_parent_type');
        }
        return staged.raw;
      }
      final row =
          bound &&
              !forWrite &&
              ((semanticSource?['metadata'] as Map?)?['references'] as List?)
                      ?.isNotEmpty ==
                  true
          ? await CryptoBusinessReferences(context).resolve(
              semanticSource!,
              scope,
              domain,
              context.address(scope, domain, types!.first, id).wireId,
            )
          : await context.record(scope, domain, id, type: types?.first);
      if (row != null && types != null && !types.contains(row['type'])) {
        throw const FormatException('crypto_finance_parent_type');
      }
      if (row == null || row['deleted'] == 1 || row['raw_payload'] == null) {
        return null;
      }
      return Map<String, dynamic>.from(
        jsonDecode(row['raw_payload'] as String) as Map,
      );
    }

    Future<Map<String, Object?>> reference(
      Map<String, dynamic> source,
      String scope,
      String domain,
      String wire,
    ) async {
      final refs = (source['metadata']['referenceVersions'] as List)
          .cast<Map>()
          .where(
            (v) =>
                v['scopeId'] == scope &&
                v['domain'] == domain &&
                v['id'] == wire,
          )
          .toList();
      if (refs.length != 1) throw const CryptoProjectionPending();
      final ref = refs.single;
      for (final v in batch) {
        if (v.record['scopeId'] == scope &&
            v.record['domain'] == domain &&
            v.record['id'] == wire &&
            v.wire?['revision'] == ref['revision'] &&
            await context.codec.digest(
                  Map<String, dynamic>.from(
                    v.wire!['authorization']['recordProof'] as Map,
                  ),
                ) ==
                ref['recordProofHash']) {
          return {
            'type': v.record['type'],
            'deleted': v.record['deleted'] == true ? 1 : 0,
            'raw_payload': v.raw == null ? null : jsonEncode(v.raw),
            'crypto_revision': ref['revision'],
            'record_proof_hash': ref['recordProofHash'],
          };
        }
      }
      return CryptoBusinessReferences(
        context,
      ).resolve(source, scope, domain, wire);
    }

    for (final candidate in batch.where(
      (x) => x.record['domain'] == 'finance',
    )) {
      semanticSource = candidate.record;
      final r = candidate.record,
          raw = candidate.raw,
          before = candidate.previousRaw;
      final scope = r['scopeId'] as String,
          id = (r['_canonicalId'] ?? r['id']) as String,
          type = r['type'] as String;
      if (candidate.historyBasis == 'inlineProjectDeletion') {
        if (forWrite ||
            raw != null ||
            (r['metadata'] as Map)['inlineDeletion'] is! Map) {
          throw const FormatException('crypto_inline_delete_publication');
        }
        // The dedicated final certificate covers the complete exact graph,
        // including children that may arrive in another bounded batch. No new
        // balance or live resolution is derived from these tombstones.
        continue;
      }
      if (context.supportsFinanceExtension?.call(type) == true) continue;
      if (![
        'financeAccount',
        'personalFinanceAccount',
        'financeEntry',
        'personalFinanceEntry',
        'financeTransfer',
        'financeRecurrenceRule',
        'taskDerivationResolution',
      ].contains(type)) {
        throw const CryptoAuthorityPending('crypto_finance_type_pending');
      }
      final refs = await uniqueRefs(scope, type, raw);
      if (CryptoInventoryJson.canonical((r['metadata'] as Map)['uniqueRefs']) !=
          CryptoInventoryJson.canonical(refs)) {
        throw const FormatException('crypto_finance_unique_binding');
      }
      if (type == 'taskDerivationResolution') {
        if (raw == null) continue;
        final expectedId = await context.reservedRecordId(
          scope,
          'taskResolution:${raw['taskId']}',
        );
        final intentId = await context.reservedRecordId(
          scope,
          'taskDerivation:${raw['taskId']}',
        );
        final legacyPending =
            raw['state'] == 'legacyPending' &&
            candidate.migrationOrigin?['captureVersion'] == 3 &&
            candidate.migrationOrigin?['materializationRole'] ==
                'taskDerivationResolution';
        if (id != expectedId ||
            raw['intentId'] != intentId ||
            (raw['state'] != 'derived' && !legacyPending)) {
          throw const FormatException('crypto_task_resolution');
        }
        final intentRecord = await reference(
          r,
          scope,
          'content',
          context
              .address(scope, 'content', 'taskDerivationIntent', intentId)
              .wireId,
        );
        if (intentRecord['deleted'] == 1 ||
            intentRecord['raw_payload'] == null) {
          throw const FormatException('crypto_task_resolution_binding');
        }
        final intent = Map<String, dynamic>.from(
          jsonDecode(intentRecord['raw_payload'] as String) as Map,
        );
        final versions = ((r['metadata'] as Map)['referenceVersions'] as List)
            .cast<Map>();
        final taskRef = versions
            .where(
              (v) =>
                  v['id'] ==
                      context
                          .address(scope, 'content', 'task', raw['taskId'])
                          .wireId &&
                  v['domain'] == 'content',
            )
            .firstOrNull;
        final expenseRef = versions
            .where(
              (v) =>
                  v['id'] ==
                      context
                          .address(
                            scope,
                            'finance',
                            'financeEntry',
                            raw['financeEntryId'],
                          )
                          .wireId &&
                  v['domain'] == 'finance',
            )
            .firstOrNull;
        if (taskRef == null || expenseRef == null) {
          throw const FormatException('crypto_task_resolution_binding');
        }
        if (raw['intentProofHash'] != intentRecord['record_proof_hash'] ||
            raw['targetOperationId'] != intent['targetOperationId'] ||
            raw['targetCryptoRevision'] != intent['targetCryptoRevision'] ||
            raw['taskProofHash'] != taskRef['recordProofHash'] ||
            raw['financeRecordProofHash'] != expenseRef['recordProofHash']) {
          throw const FormatException('crypto_task_resolution_binding');
        }
        final taskRecord = await reference(r, scope, 'content', taskRef['id']);
        final detached = intent['deleted'] == true;
        if ((taskRecord['deleted'] == 1) != detached ||
            taskRecord['record_proof_hash'] != raw['taskProofHash'] ||
            taskRecord['crypto_revision'] != raw['targetCryptoRevision']) {
          throw const FormatException('crypto_task_resolution_binding');
        }
        final expense = batch
            .where(
              (v) =>
                  v.record['scopeId'] == scope &&
                  v.record['domain'] == 'finance' &&
                  (v.record['_canonicalId'] ?? v.record['id']) ==
                      raw['financeEntryId'],
            )
            .firstOrNull;
        if (expense?.raw == null) throw const CryptoProjectionPending();
        final fact = expense!.raw!;
        final deadline = fact['plannedAt'] == null
            ? null
            : DateTime.parse(
                    fact['plannedAt'] as String,
                  ).toUtc().millisecondsSinceEpoch ~/
                  1000;
        if (detached
            ? (fact['taskId'] != null ||
                  fact['plannedAt'] != null ||
                  legacyPending)
            : (fact['taskId'] != raw['taskId'] ||
                  (legacyPending
                      ? deadline == intent['deadlineEpoch']
                      : deadline != intent['deadlineEpoch']))) {
          throw const FormatException('crypto_task_resolution_fact');
        }
        continue;
      }
      if (raw == null) {
        // Account/rule deletion keeps existing child facts. Every linked row
        // must be deleted/detached in this same authenticated group first.
        if ([
          'financeAccount',
          'personalFinanceAccount',
          'financeRecurrenceRule',
        ].contains(type)) {
          final rows = await context.database.rows(
            "SELECT json_extract(projection,'\$.id') AS id,raw_payload FROM crypto_business_records WHERE partition=? AND scope_id=? AND domain='finance' AND deleted=0 AND (json_extract(raw_payload,'\$.accountId')=? OR json_extract(raw_payload,'\$.ledgerAccountId')=? OR json_extract(raw_payload,'\$.fromAccountId')=? OR json_extract(raw_payload,'\$.toAccountId')=? OR json_extract(raw_payload,'\$.recurrenceRuleId')=?)",
            [context.partition, scope, id, id, id, id, id],
          );
          for (final row in rows) {
            final surviving = await lookup(
              scope,
              'finance',
              row['id'] as String,
            );
            if (surviving != null &&
                [
                  'accountId',
                  'ledgerAccountId',
                  'fromAccountId',
                  'toAccountId',
                  'recurrenceRuleId',
                ].any((f) => surviving[f] == id)) {
              throw const FormatException('crypto_finance_parent_has_children');
            }
          }
        }
        continue;
      }
      try {
        CryptoBusinessPayload.projection('finance', type, raw);
      } on CollaborationException {
        throw const FormatException('crypto_finance_payload');
      }
      for (final field in [
        'ownerAccountId',
        'payerAccountId',
        'recipientAccountId',
      ]) {
        if (raw[field] != null && raw[field] != before?[field]) {
          final members =
              context.financeAuthorityMembers[r['membershipHeadHash']];
          if (members == null) throw const CryptoProjectionPending();
          if (!members.contains(raw[field])) {
            throw const FormatException('crypto_finance_actor_reference');
          }
        }
      }
      if (before != null && !sameDate(before['createdAt'], raw['createdAt'])) {
        throw const FormatException('crypto_finance_created_immutable');
      }
      if ([
            'financeAccount',
            'personalFinanceAccount',
            'financeRecurrenceRule',
          ].contains(type) &&
          before != null &&
          before['currency'] != raw['currency']) {
        throw const FormatException('crypto_finance_currency_immutable');
      }
      if (type == 'financeRecurrenceRule' &&
          before != null &&
          before['kind'] != raw['kind']) {
        throw const FormatException('crypto_finance_rule_kind_immutable');
      }
      final parentAccount =
          raw['accountScopeId'] != null && raw['accountScopeId'] != scope;
      if (parentAccount) {
        if (type != 'financeEntry') {
          throw const FormatException('crypto_parent_account_type');
        }
        await CryptoFinanceAccountChoices(context).verifyFinancialRecord(
          scope,
          raw,
          record: forWrite ? null : r,
          verifiedManifest: forWrite
              ? null
              : batch
                    .where(
                      (v) =>
                          v.record['scopeId'] == scope &&
                          v.record['type'] == 'financeAccountChoice' &&
                          v.record['metadata']['identity']['canonicalId'] ==
                              raw['accountChoiceWitness']?['manifestId'],
                    )
                    .firstOrNull,
        );
      }
      Future<void> account(Object? accountId, String field) async {
        if (accountId == null ||
            parentAccount &&
                const {'accountId', 'ledgerAccountId'}.contains(field)) {
          return;
        }
        final target = await lookup(
          scope,
          'finance',
          accountId as String,
          types: {'financeAccount', 'personalFinanceAccount'},
          bound: true,
        );
        if (target == null) throw const CryptoProjectionPending();
        if (target['currency'] != raw['currency']) {
          if (!forWrite) throw const CryptoProjectionPending();
          throw const FormatException('crypto_finance_currency_mismatch');
        }
        if (target['archived'] == true && before?[field] != accountId) {
          if (!forWrite) throw const CryptoProjectionPending();
          throw const FormatException('crypto_finance_account_archived');
        }
      }

      if (type == 'financeTransfer') {
        if (raw['fromAccountId'] == raw['toAccountId']) {
          throw const FormatException('crypto_finance_same_transfer_account');
        }
        await account(raw['fromAccountId'], 'fromAccountId');
        await account(raw['toAccountId'], 'toAccountId');
      } else {
        await account(raw['accountId'], 'accountId');
        await account(raw['ledgerAccountId'], 'ledgerAccountId');
      }
      for (final field in ['payerPersonId', 'recipientPersonId']) {
        if (raw[field] != null && before?[field] != raw[field]) {
          final person = await lookup(
            scope,
            'content',
            raw[field] as String,
            types: {'householdPerson'},
            bound: true,
          );
          if (person == null) throw const CryptoProjectionPending();
          if (person['archived'] == true) {
            if (!forWrite) throw const CryptoProjectionPending();
            throw const FormatException('crypto_finance_person_archived');
          }
        }
      }
      if (raw['projectId'] != null) {
        final project = await lookup(
          scope,
          'content',
          raw['projectId'] as String,
          types: {'project'},
          bound: true,
        );
        if (project == null) throw const CryptoProjectionPending();
        if (project['archived'] == true &&
            before?['projectId'] != raw['projectId']) {
          if (!forWrite) throw const CryptoProjectionPending();
          throw const FormatException('crypto_finance_project_archived');
        }
      }
      if (raw['taskId'] != null) {
        final task = await lookup(
          scope,
          'content',
          raw['taskId'] as String,
          types: {'task'},
          bound: true,
        );
        if (task == null) throw const CryptoProjectionPending();
        if (raw['kind'] != 'expense') {
          throw const FormatException('crypto_task_cost_kind');
        }
        if (!sameDate(task['dueAt'], raw['plannedAt'])) {
          // Later content changes do not make the prior financial fact corrupt.
          // Historical reference authority and its derivation remain pending.
          if (!forWrite &&
              candidate.migrationOrigin?['captureVersion'] == 3 &&
              candidate.migrationOrigin?['type'] == type &&
              (candidate.migrationOrigin?['materializationRole'] ??
                      'primary') ==
                  'primary') {
            // The exact captured legacy fact is retained. Its source-bound
            // legacyPending companion prohibits an upgrade-only correction.
            final baseline = batch.where(
              (b) =>
                  b.record['type'] == 'taskDerivationResolution' &&
                  b.raw?['financeEntryId'] == id &&
                  b.raw?['state'] == 'legacyPending' &&
                  b.migrationOrigin?['captureVersion'] == 3 &&
                  b.migrationOrigin?['materializationRole'] ==
                      'taskDerivationResolution',
            );
            if (baseline.length != 1) throw const CryptoProjectionPending();
          } else if (!forWrite) {
            throw const CryptoProjectionPending();
          } else {
            throw const FormatException('crypto_task_cost_date_mismatch');
          }
        }
      }
      if (raw['recurrenceRuleId'] != null) {
        final rule = await lookup(
          scope,
          'finance',
          raw['recurrenceRuleId'] as String,
          types: {'financeRecurrenceRule'},
          bound: true,
        );
        if (rule == null) throw const CryptoProjectionPending();
        if (rule['currency'] != raw['currency'] ||
            (['salary', 'income'].contains(rule['kind'])
                    ? 'income'
                    : 'expense') !=
                raw['kind']) {
          throw const FormatException('crypto_finance_occurrence_rule');
        }
      }
      // Authenticated unique commitments are also enforced by the opaque server
      // index; local validation detects malicious hidden payload substitutions.
      for (final unique in refs) {
        final others = await context.database.rows(
          "SELECT json_extract(projection,'\$.id') AS id,raw_payload,type FROM crypto_business_records WHERE partition=? AND scope_id=? AND domain='finance' AND deleted=0 AND id<>? AND (json_extract(raw_payload,'\$.taskId')=? OR (json_extract(raw_payload,'\$.recurrenceRuleId')=? AND json_extract(raw_payload,'\$.occurrenceKey')=?))",
          [
            context.partition,
            scope,
            context.address(scope, 'finance', type, id).wireId,
            raw['taskId'],
            raw['recurrenceRuleId'],
            raw['occurrenceKey'],
          ],
        );
        for (final other in others) {
          final surviving = await lookup(
            scope,
            'finance',
            other['id'] as String,
            types: {other['type'] as String},
          );
          if (surviving != null &&
              (await uniqueRefs(
                scope,
                other['type'] as String,
                surviving,
              )).contains(unique)) {
            throw const FormatException('crypto_finance_duplicate_reference');
          }
        }
        for (final other in batch.where(
          (x) =>
              x.record['domain'] == 'finance' &&
              x.record['scopeId'] == scope &&
              !((x.record['_canonicalId'] ?? x.record['id']) == id &&
                  cryptoRecordSourceKind(x.record['type'] as String) ==
                      cryptoRecordSourceKind(type)) &&
              x.raw != null,
        )) {
          if ((await uniqueRefs(
            scope,
            other.record['type'] as String,
            other.raw,
          )).contains(unique)) {
            throw const FormatException('crypto_finance_duplicate_reference');
          }
        }
      }
    }
  }

  bool sameDate(Object? a, Object? b) => a == null || b == null
      ? a == b
      : DateTime.parse(
          a as String,
        ).isAtSameMomentAs(DateTime.parse(b as String));
}
