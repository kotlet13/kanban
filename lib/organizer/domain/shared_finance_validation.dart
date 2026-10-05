import 'shared_finance_models.dart';
import 'shared_payload_validation.dart';
import 'collaboration_models.dart' show CollaborationException;
import 'dart:convert';

void validateSharedFinancePayload(
  SharedFinanceRecordType type,
  Map<String, dynamic> p,
) {
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
