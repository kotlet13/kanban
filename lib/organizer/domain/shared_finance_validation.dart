import 'shared_finance_models.dart';
import 'shared_dates.dart';
import 'organizer_models.dart';
import 'shared_payload_validation.dart';
import 'collaboration_models.dart' show CollaborationException;
import 'dart:convert';

void validateSharedFinancePayload(
  SharedFinanceRecordType type,
  Map<String, dynamic> p, {
  int contractVersion = 1,
}) {
  if (contractVersion == 2) {
    return validateFinancePlanningPayload(type, p);
  }
  final keys = <String>{
    'currency',
    'createdAt',
    'updatedAt',
    ...switch (type) {
      SharedFinanceRecordType.personalFinanceEntry => [
        'title',
        'amountMinor',
        'kind',
        'occurredAt',
        'projectId',
        'notes',
      ],
      SharedFinanceRecordType.financeAccount => [
        'name',
        'openingBalanceMinor',
        'ownerAccountId',
      ],
      SharedFinanceRecordType.financeEntry => [
        'accountId',
        'kind',
        'status',
        'amountMinor',
        'title',
        'notes',
        'category',
        'payerAccountId',
        'recipientAccountId',
        'occurredAt',
      ],
      SharedFinanceRecordType.personalFinanceAccount ||
      SharedFinanceRecordType.financeRecurrenceRule =>
        throw const CollaborationException('unsupported_version'),
      SharedFinanceRecordType.financeTransfer => [
        'fromAccountId',
        'toAccountId',
        'amountMinor',
        'status',
        'title',
        'notes',
        'occurredAt',
      ],
    },
  };
  if (p.length != keys.length ||
      !p.keys.every(keys.contains) ||
      utf8
              .encode(
                jsonEncode(p)
                    .replaceAll('/', r'\/')
                    .replaceAll('\u2028', r'\u2028')
                    .replaceAll('\u2029', r'\u2029'),
              )
              .length >
          (type == SharedFinanceRecordType.personalFinanceEntry
              ? 524288
              : 8192) ||
      !sharedEditableCurrencies.contains(p['currency'])) {
    throw const CollaborationException('validation_error');
  }
  void date(Object? value) {
    if (value is! String ||
        !RegExp(
          r'^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d{1,6})?Z$',
        ).hasMatch(value)) {
      throw const CollaborationException('validation_error');
    }
    final d = DateTime.tryParse(value);
    if (d == null ||
        d.toUtc().toIso8601String().substring(0, 19) !=
            value.substring(0, 19)) {
      throw const CollaborationException('validation_error');
    }
  }

  date(p['createdAt']);
  date(p['updatedAt']);
  void money(Object? v, {bool signed = false}) {
    if (v is! int || v.abs() > 9000000000000 || (!signed && v <= 0)) {
      throw const CollaborationException('validation_error');
    }
  }

  void uuid(Object? v, {bool nullable = false}) {
    if (nullable && v == null) return;
    if (!isSharedUuid(v)) {
      throw const CollaborationException('validation_error');
    }
  }

  if (type == SharedFinanceRecordType.financeAccount) {
    validateSharedText(p['name'], 300);
    money(p['openingBalanceMinor'], signed: true);
    uuid(p['ownerAccountId'], nullable: true);
    return;
  }
  money(p['amountMinor']);
  date(p['occurredAt']);
  final personal = type == SharedFinanceRecordType.personalFinanceEntry;
  validateSharedText(p['title'], personal ? 2000 : 300);
  validateSharedText(p['notes'], personal ? 200000 : 4096, empty: true);
  if (personal) {
    if ((p['title'] as String).length > 500 ||
        (p['notes'] as String).length > 50000 ||
        !['income', 'expense'].contains(p['kind'])) {
      throw const CollaborationException('validation_error');
    }
    uuid(p['projectId'], nullable: true);
    return;
  }
  if (!['planned', 'posted'].contains(p['status'])) {
    throw const CollaborationException('validation_error');
  }
  if (type == SharedFinanceRecordType.financeEntry) {
    uuid(p['accountId']);
    uuid(p['payerAccountId'], nullable: true);
    uuid(p['recipientAccountId'], nullable: true);
    validateSharedText(p['category'], 100, empty: true);
    if (!['income', 'expense'].contains(p['kind'])) {
      throw const CollaborationException('validation_error');
    }
  } else {
    uuid(p['fromAccountId']);
    uuid(p['toAccountId']);
    if (p['fromAccountId'] == p['toAccountId']) {
      throw const CollaborationException('validation_error');
    }
  }
}

void validateFinancePlanningPayload(
  SharedFinanceRecordType type,
  Map<String, dynamic> p,
) {
  const entryFields = [
    'status',
    'plannedAt',
    'paidAt',
    'taskId',
    'ledgerAccountId',
    'payerPersonId',
    'recipientPersonId',
    'createdByPersonId',
    'recurrenceRuleId',
    'occurrenceKey',
  ];
  final fields = <String>{
    'currency',
    'createdAt',
    'updatedAt',
    ...switch (type) {
      SharedFinanceRecordType.personalFinanceAccount => [
        'name',
        'openingBalanceMinor',
        'openingBalanceAt',
        'archived',
      ],
      SharedFinanceRecordType.financeRecurrenceRule => [
        'title',
        'kind',
        'ledgerAccountId',
        'estimatedAmountMinor',
        'loanPrincipalMinor',
        'startYear',
        'startMonth',
        'monthDay',
        'endYear',
        'endMonth',
        'active',
        'remindersEnabled',
        'reminderMinuteOfDay',
      ],
      SharedFinanceRecordType.personalFinanceEntry => [
        'title',
        'amountMinor',
        'kind',
        'occurredAt',
        'projectId',
        'notes',
        ...entryFields,
      ],
      SharedFinanceRecordType.financeAccount => [
        'name',
        'openingBalanceMinor',
        'ownerAccountId',
        'openingBalanceAt',
        'archived',
      ],
      SharedFinanceRecordType.financeEntry => [
        'accountId',
        'kind',
        'amountMinor',
        'title',
        'notes',
        'category',
        'payerAccountId',
        'recipientAccountId',
        'occurredAt',
        ...entryFields,
      ],
      SharedFinanceRecordType.financeTransfer => [
        'fromAccountId',
        'toAccountId',
        'amountMinor',
        'status',
        'title',
        'notes',
        'occurredAt',
      ],
    },
  };
  if (p.length != fields.length ||
      !p.keys.every(fields.contains) ||
      utf8.encode(jsonEncode(p)).length > 524288) {
    throw const CollaborationException('validation_error');
  }
  try {
    final local = <String, dynamic>{...p, 'id': 'wire', 'revision': 0};
    // Wire timestamps allow the native contract's canonical Z form with optional
    // fractions. Local model round trips use Dart's explicit milliseconds.
    for (final key in [
      'createdAt',
      'updatedAt',
      'openingBalanceAt',
      'occurredAt',
      'plannedAt',
      'paidAt',
    ]) {
      if (local[key] != null) {
        local[key] = readSharedDate(local, key).toIso8601String();
      }
    }
    switch (type) {
      case SharedFinanceRecordType.personalFinanceAccount:
      case SharedFinanceRecordType.financeAccount:
        LocalFinanceAccount.fromJson(local);
        if (type == SharedFinanceRecordType.financeAccount &&
            p['ownerAccountId'] != null &&
            !isSharedUuid(p['ownerAccountId'])) {
          throw const FormatException('Invalid owner');
        }
      case SharedFinanceRecordType.financeRecurrenceRule:
        FinanceRecurrenceRule.fromJson(local);
        if (p['ledgerAccountId'] != null &&
            !isSharedUuid(p['ledgerAccountId'])) {
          throw const FormatException('Invalid account');
        }
      case SharedFinanceRecordType.financeEntry:
      case SharedFinanceRecordType.personalFinanceEntry:
        if (type == SharedFinanceRecordType.financeEntry &&
            (!isSharedUuid(p['accountId']) ||
                (p['ledgerAccountId'] != null &&
                    p['ledgerAccountId'] != p['accountId']))) {
          throw const FormatException('Invalid account');
        }
        if (!['income', 'expense'].contains(p['kind']) ||
            !['planned', 'posted'].contains(p['status']) ||
            p['amountMinor'] is! int ||
            (p['amountMinor'] as int) <= 0 ||
            (p['amountMinor'] as int) > maxMoneyMinor ||
            !supportedCurrencies.contains(p['currency'])) {
          throw const FormatException('Invalid amount');
        }
        validateSharedText(p['title'], 500);
        validateSharedText(p['notes'], 50000, empty: true);
        for (final key in [
          'taskId',
          'ledgerAccountId',
          'payerPersonId',
          'recipientPersonId',
          'createdByPersonId',
          'recurrenceRuleId',
          if (type == SharedFinanceRecordType.personalFinanceEntry) 'projectId',
          if (type == SharedFinanceRecordType.financeEntry) ...[
            'payerAccountId',
            'recipientAccountId',
          ],
        ]) {
          if (p[key] != null && !isSharedUuid(p[key])) {
            throw const FormatException('Invalid financial reference');
          }
        }
        if (p['createdByPersonId'] != null) {
          throw const FormatException('Author is server metadata');
        }
        if ((p['recurrenceRuleId'] == null) != (p['occurrenceKey'] == null) ||
            (p['occurrenceKey'] != null &&
                (p['occurrenceKey'] is! String ||
                    !RegExp(
                      r'^\d{4}-(0[1-9]|1[0-2])$',
                    ).hasMatch(p['occurrenceKey'] as String))) ||
            (p['status'] == 'planned' && p['paidAt'] != null)) {
          throw const FormatException('Invalid occurrence');
        }
        if (p['paidAt'] != null &&
            readSharedDate(p, 'paidAt') != readSharedDate(p, 'occurredAt')) {
          throw const FormatException('Actual date mismatch');
        }
      case SharedFinanceRecordType.financeTransfer:
        validateSharedFinancePayload(type, p);
    }
  } on FormatException {
    throw const CollaborationException('validation_error');
  }
}

Map<String, dynamic> financePayloadForContract(
  SharedFinanceRecordType type,
  Map<String, dynamic> source,
  int version,
) {
  final payload = Map<String, dynamic>.of(source);
  if (version == 2) {
    if (type == SharedFinanceRecordType.personalFinanceEntry ||
        type == SharedFinanceRecordType.financeEntry) {
      payload.putIfAbsent('status', () => 'posted');
      for (final key in [
        'plannedAt',
        'paidAt',
        'taskId',
        'ledgerAccountId',
        'payerPersonId',
        'recipientPersonId',
        'createdByPersonId',
        'recurrenceRuleId',
        'occurrenceKey',
      ]) {
        payload.putIfAbsent(
          key,
          () =>
              key == 'plannedAt' &&
                  payload['status'] == 'planned' &&
                  payload['taskId'] == null
              ? payload['occurredAt']
              : null,
        );
      }
    } else if (type == SharedFinanceRecordType.financeAccount) {
      payload.putIfAbsent('openingBalanceAt', () => null);
      payload.putIfAbsent('archived', () => false);
    }
  }
  return payload;
}
