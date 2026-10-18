import 'dart:convert';

import 'crypto_business_json.dart';
import 'crypto_record_address.dart';

/// A verified, decrypted current record. The caller must supply a complete
/// authenticated source inventory, including retained payment history. This
/// planner preserves the old finite project selection; it is not a reference
/// closure that silently moves unrelated dependants.
class CryptoRelocationRecord {
  CryptoRelocationRecord({
    required this.id,
    required this.wireId,
    required this.type,
    required this.revision,
    required this.logicalRevision,
    required this.proofHash,
    required this.deleted,
    required Map<String, dynamic>? raw,
  }) : raw = raw == null
           ? null
           : Map<String, dynamic>.unmodifiable(
               jsonDecode(jsonEncode(raw)) as Map<String, dynamic>,
             ) {
    if (!isCryptoCanonicalUuid(id) ||
        !isCryptoWireRecordId(wireId) ||
        revision < 1 ||
        logicalRevision < 0 ||
        revision > 9007199254740991 ||
        logicalRevision > 9007199254740991 ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(proofHash) ||
        !deleted && raw == null) {
      throw const FormatException('crypto_relocation_source');
    }
    cryptoRecordDomain(type);
  }
  final String id, wireId, type, proofHash;
  final int revision, logicalRevision;
  final bool deleted;
  final Map<String, dynamic>? raw;
  String get domain => cryptoRecordDomain(type);
  Map<String, dynamic> get descriptor => {
    'id': id,
    'wireId': wireId,
    'type': type,
    'domain': domain,
    'revision': revision,
    'logicalRevision': logicalRevision,
    'recordProofHash': proofHash,
    'deleted': deleted,
  };
}

class CryptoProjectRelocationGraph {
  CryptoProjectRelocationGraph._(this.records, this.blockers);
  final List<CryptoRelocationRecord> records;
  final List<Map<String, dynamic>> blockers;
  bool get canApply => blockers.isEmpty;
  bool get needsFinance => records.any((r) => r.domain == 'finance');

  /// This root contains only exact encrypted-proof coordinates and revisions.
  /// Plaintext payloads, names, balances and low-entropy values are excluded.
  Future<String> get root => CryptoBusinessJson.hash({
    'domain': 'JivieProjectRelocationGraph/v2',
    'records': records.map((r) => r.descriptor).toList(),
  });

  static CryptoProjectRelocationGraph select({
    required String projectId,
    required List<CryptoRelocationRecord> inventory,
    required List<CryptoRelocationRecord> paymentHistory,
    bool targetScopeExists = false,
    int maximumRecords = 10000,
  }) {
    if (!isCryptoCanonicalUuid(projectId) || maximumRecords < 1) {
      throw const FormatException('crypto_relocation_project');
    }
    final all = <String, CryptoRelocationRecord>{};
    final wire = <String>{};
    for (final record in inventory) {
      if (all.containsKey(
            '${cryptoRecordSourceKind(record.type)}:${record.id}',
          ) ||
          !wire.add(record.wireId)) {
        throw const FormatException('crypto_relocation_inventory_duplicate');
      }
      all['${cryptoRecordSourceKind(record.type)}:${record.id}'] = record;
    }
    final project = all['records:$projectId'];
    if (project == null || project.type != 'project' || project.deleted) {
      throw const FormatException('crypto_relocation_project_missing');
    }
    final selected = <String, CryptoRelocationRecord>{project.wireId: project};
    final blockers = <String, Map<String, dynamic>>{};
    void block(String code, [String? id]) {
      blockers['$code:${id ?? ''}'] = {
        'code': code,
        if (id != null) 'recordId': id,
      };
    }

    if (targetScopeExists) block('project_scope_id_collision');
    final tasks = <String>{}, people = <String>{};
    void personRefs(Map<String, dynamic>? raw) {
      if (raw == null) return;
      for (final key in const [
        'assigneePersonId',
        'payerPersonId',
        'recipientPersonId',
        'createdByPersonId',
      ]) {
        if (raw[key] is String) people.add(raw[key] as String);
      }
      final subjects = raw['subjectPersonIds'];
      if (subjects is List) people.addAll(subjects.cast<String>());
    }

    for (final row in inventory) {
      if (const {'task', 'event', 'idea'}.contains(row.type) &&
          row.raw?['projectId'] == projectId) {
        selected[row.wireId] = row;
        if (row.type == 'task') tasks.add(row.id);
        personRefs(row.raw);
      }
      if (row.domain == 'finance' &&
          !row.deleted &&
          row.raw?['projectId'] == projectId) {
        block('project_finance_scope_reference', row.id);
      }
    }
    final accounts = <String>{}, rules = <String>{};
    for (final row in inventory) {
      if (row.domain != 'finance' || !tasks.contains(row.raw?['taskId'])) {
        continue;
      }
      // Payment rows never become an ordinary task-cost movement.
      if (_payments.contains(row.type)) {
        block('project_linked_payment_dependency', row.id);
        continue;
      }
      selected[row.wireId] = row;
      for (final field in const ['accountId', 'ledgerAccountId']) {
        if (row.raw?[field] is String) accounts.add(row.raw![field] as String);
      }
      if (row.raw?['recurrenceRuleId'] is String) {
        rules.add(row.raw!['recurrenceRuleId'] as String);
      }
      personRefs(row.raw);
    }
    for (final row in inventory) {
      if (row.type != 'financeRecurrenceRule' || !rules.contains(row.id)) {
        continue;
      }
      selected[row.wireId] = row;
      if (row.raw?['ledgerAccountId'] is String) {
        accounts.add(row.raw!['ledgerAccountId'] as String);
      }
    }
    for (final row in inventory) {
      final raw = row.raw;
      if (const {
            'financeAccount',
            'personalFinanceAccount',
          }.contains(row.type) &&
          accounts.contains(row.id)) {
        selected[row.wireId] = row;
        continue;
      }
      if (row.domain != 'finance' ||
          selected.containsKey(row.wireId) ||
          row.deleted) {
        continue;
      }
      if (row.type == 'financeTransfer' &&
          accounts.contains(raw?['fromAccountId']) &&
          accounts.contains(raw?['toAccountId'])) {
        selected[row.wireId] = row;
        continue;
      }
      if (rules.contains(raw?['recurrenceRuleId'])) {
        block('project_recurrence_shared', row.id);
      }
      if (const [
        'accountId',
        'ledgerAccountId',
        'fromAccountId',
        'toAccountId',
      ].any((k) => accounts.contains(raw?[k]))) {
        block(
          row.type == 'financeTransfer'
              ? 'project_transfer_cross_scope'
              : 'project_finance_account_shared',
          row.id,
        );
      }
    }
    for (final row in inventory) {
      if (row.type == 'householdPerson' && people.contains(row.id)) {
        selected[row.wireId] = row;
      }
    }
    for (final row in inventory) {
      if (selected.containsKey(row.wireId) || row.deleted) continue;
      final refs = <String>{};
      for (final key in const [
        'assigneePersonId',
        'payerPersonId',
        'recipientPersonId',
        'createdByPersonId',
      ]) {
        if (row.raw?[key] is String) refs.add(row.raw![key] as String);
      }
      if (row.raw?['subjectPersonIds'] is List) {
        refs.addAll((row.raw!['subjectPersonIds'] as List).cast<String>());
      }
      if (refs.any(people.contains)) block('project_person_shared', row.id);
    }
    // Technical companions follow their already selected task/idea only.
    // Their reserved canonical IDs are remapped by the normal reserved-ID
    // helper when sealing for the target scope, never invented here.
    for (final row in inventory) {
      final raw = row.raw;
      final taskCompanion =
          const {
            'taskDerivationIntent',
            'taskDerivationResolution',
          }.contains(row.type) &&
          tasks.contains(raw?['taskId']);
      final attachment =
          row.type == 'attachment' &&
          raw?['targetType'] == 'task' &&
          tasks.contains(raw?['targetId']);
      final asset =
          row.type == 'ideaAsset' &&
          selected.values.any(
            (r) => r.type == 'idea' && r.id == raw?['ideaId'],
          );
      if (taskCompanion || attachment || asset) selected[row.wireId] = row;
    }
    for (final row in [...inventory, ...paymentHistory]) {
      if (!_payments.contains(row.type)) continue;
      final raw = row.raw;
      // Deliberately inspect retained history, even cancelled/deleted events.
      // Such an event still proves the existing linked-payment dependency.
      if (const ['entryId', 'sourceEntryId'].any(
            (key) => selected.values.any(
              (r) => r.domain == 'finance' && r.id == raw?[key],
            ),
          ) ||
          const [
            'accountId',
            'privateAccountId',
          ].any((key) => accounts.contains(raw?[key]))) {
        block('project_linked_payment_dependency', row.id);
      }
    }
    if (selected.length > maximumRecords) {
      throw const FormatException('crypto_relocation_capacity');
    }
    if (selected.values.any(
      (r) =>
          r.revision >= 9007199254740991 ||
          r.logicalRevision >= 9007199254740991,
    )) {
      throw const FormatException('crypto_relocation_revision_exhausted');
    }
    final records = selected.values.toList()
      ..sort((a, b) => a.wireId.compareTo(b.wireId));
    final reasons = blockers.values.toList()
      ..sort(
        (a, b) => '${a['code']}:${a['recordId'] ?? ''}'.compareTo(
          '${b['code']}:${b['recordId'] ?? ''}',
        ),
      );
    return CryptoProjectRelocationGraph._(
      List.unmodifiable(records),
      List.unmodifiable(reasons),
    );
  }

  static const _payments = {
    'paymentEvent',
    'paymentProjection',
    'cashMovement',
    'financeAccountChoice',
  };
}
