import 'shared_dates.dart';
import 'organizer_models.dart';

const _unsetFinance = Object();

enum SharedFinanceStatus { planned, posted }

enum SharedFinanceGrant { none, read, write }

enum SharedFinanceRecordType {
  financeAccount,
  financeEntry,
  financeTransfer,
  personalFinanceEntry,
}

class SharedFinancePolicy {
  const SharedFinancePolicy({
    this.enabled = false,
    this.grant = SharedFinanceGrant.none,
    this.revision = 0,
  });
  final bool enabled;
  final SharedFinanceGrant grant;
  final int revision;
  bool get canRead => enabled && grant != SharedFinanceGrant.none;
  bool get canWrite => enabled && grant == SharedFinanceGrant.write;
  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'grant': grant.name,
    'revision': revision,
  };
  factory SharedFinancePolicy.fromJson(Map<String, dynamic> j) =>
      SharedFinancePolicy(
        enabled: readBool(j, 'enabled'),
        grant: SharedFinanceGrant.values.byName(readString(j, 'grant')),
        revision: readInt(j, 'revision'),
      );
}

class SharedFinanceAccount {
  const SharedFinanceAccount({
    required this.id,
    this.revision = 0,
    required this.createdAt,
    required this.updatedAt,
    this.createdByAccountId,
    this.updatedByAccountId,
    required this.name,
    required this.currency,
    this.openingBalanceMinor = 0,
    this.ownerAccountId,
  });
  final String id;
  final int revision;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? createdByAccountId;
  final String? updatedByAccountId;
  final String name;
  final String currency;
  final int openingBalanceMinor;
  final String? ownerAccountId;
  SharedFinanceAccount copyWith({
    int? revision,
    DateTime? updatedAt,
    String? name,
    String? currency,
    int? openingBalanceMinor,
    Object? ownerAccountId = _unsetFinance,
  }) => SharedFinanceAccount(
    id: id,
    revision: revision ?? this.revision,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    createdByAccountId: createdByAccountId,
    updatedByAccountId: updatedByAccountId,
    name: name ?? this.name,
    currency: currency ?? this.currency,
    openingBalanceMinor: openingBalanceMinor ?? this.openingBalanceMinor,
    ownerAccountId: identical(ownerAccountId, _unsetFinance)
        ? this.ownerAccountId
        : ownerAccountId as String?,
  );
  Map<String, Object?> toJson() => {
    'id': id,
    'revision': revision,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'createdByAccountId': createdByAccountId,
    'updatedByAccountId': updatedByAccountId,
    'name': name,
    'currency': currency,
    'openingBalanceMinor': openingBalanceMinor,
    'ownerAccountId': ownerAccountId,
  };
  Map<String, Object?> toPayload() => Map.of(toJson())
    ..remove('id')
    ..remove('revision')
    ..remove('createdByAccountId')
    ..remove('updatedByAccountId');
  factory SharedFinanceAccount.fromJson(Map<String, dynamic> j) =>
      SharedFinanceAccount(
        id: readString(j, 'id'),
        revision: readInt(j, 'revision'),
        createdAt: readSharedDate(j, 'createdAt'),
        updatedAt: readSharedDate(j, 'updatedAt'),
        createdByAccountId: readNullableString(j, 'createdByAccountId'),
        updatedByAccountId: readNullableString(j, 'updatedByAccountId'),
        name: readString(j, 'name'),
        currency: readString(j, 'currency'),
        openingBalanceMinor: readInt(j, 'openingBalanceMinor'),
        ownerAccountId: readNullableString(j, 'ownerAccountId'),
      );
}

class SharedFinanceEntry {
  const SharedFinanceEntry({
    required this.id,
    this.revision = 0,
    required this.createdAt,
    required this.updatedAt,
    this.createdByAccountId,
    this.updatedByAccountId,
    required this.accountId,
    required this.kind,
    this.status = SharedFinanceStatus.posted,
    required this.amountMinor,
    required this.currency,
    required this.title,
    this.notes = '',
    this.category = '',
    this.payerAccountId,
    this.recipientAccountId,
    required this.occurredAt,
  });
  final String id;
  final int revision;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? createdByAccountId;
  final String? updatedByAccountId;
  final String accountId;
  final FinanceEntryKind kind;
  final SharedFinanceStatus status;
  final int amountMinor;
  final String currency;
  final String title;
  final String notes;
  final String category;
  final String? payerAccountId;
  final String? recipientAccountId;
  final DateTime occurredAt;
  SharedFinanceEntry copyWith({
    int? revision,
    DateTime? updatedAt,
    String? accountId,
    FinanceEntryKind? kind,
    SharedFinanceStatus? status,
    int? amountMinor,
    String? currency,
    String? title,
    String? notes,
    String? category,
    Object? payerAccountId = _unsetFinance,
    Object? recipientAccountId = _unsetFinance,
    DateTime? occurredAt,
  }) => SharedFinanceEntry(
    id: id,
    revision: revision ?? this.revision,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    createdByAccountId: createdByAccountId,
    updatedByAccountId: updatedByAccountId,
    accountId: accountId ?? this.accountId,
    kind: kind ?? this.kind,
    status: status ?? this.status,
    amountMinor: amountMinor ?? this.amountMinor,
    currency: currency ?? this.currency,
    title: title ?? this.title,
    notes: notes ?? this.notes,
    category: category ?? this.category,
    payerAccountId: identical(payerAccountId, _unsetFinance)
        ? this.payerAccountId
        : payerAccountId as String?,
    recipientAccountId: identical(recipientAccountId, _unsetFinance)
        ? this.recipientAccountId
        : recipientAccountId as String?,
    occurredAt: occurredAt ?? this.occurredAt,
  );
  Map<String, Object?> toJson() => {
    'id': id,
    'revision': revision,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'createdByAccountId': createdByAccountId,
    'updatedByAccountId': updatedByAccountId,
    'accountId': accountId,
    'kind': kind.name,
    'status': status.name,
    'amountMinor': amountMinor,
    'currency': currency,
    'title': title,
    'notes': notes,
    'category': category,
    'payerAccountId': payerAccountId,
    'recipientAccountId': recipientAccountId,
    'occurredAt': occurredAt.toUtc().toIso8601String(),
  };
  Map<String, Object?> toPayload() => Map.of(toJson())
    ..remove('id')
    ..remove('revision')
    ..remove('createdByAccountId')
    ..remove('updatedByAccountId');
  factory SharedFinanceEntry.fromJson(Map<String, dynamic> j) =>
      SharedFinanceEntry(
        id: readString(j, 'id'),
        revision: readInt(j, 'revision'),
        createdAt: readSharedDate(j, 'createdAt'),
        updatedAt: readSharedDate(j, 'updatedAt'),
        createdByAccountId: readNullableString(j, 'createdByAccountId'),
        updatedByAccountId: readNullableString(j, 'updatedByAccountId'),
        accountId: readString(j, 'accountId'),
        kind: FinanceEntryKind.values.byName(readString(j, 'kind')),
        status: SharedFinanceStatus.values.byName(readString(j, 'status')),
        amountMinor: readInt(j, 'amountMinor'),
        currency: readString(j, 'currency'),
        title: readString(j, 'title'),
        notes: readString(j, 'notes'),
        category: readString(j, 'category'),
        payerAccountId: readNullableString(j, 'payerAccountId'),
        recipientAccountId: readNullableString(j, 'recipientAccountId'),
        occurredAt: readSharedDate(j, 'occurredAt'),
      );
}

class SharedFinanceTransfer {
  const SharedFinanceTransfer({
    required this.id,
    this.revision = 0,
    required this.createdAt,
    required this.updatedAt,
    this.createdByAccountId,
    this.updatedByAccountId,
    required this.fromAccountId,
    required this.toAccountId,
    required this.amountMinor,
    required this.currency,
    this.status = SharedFinanceStatus.posted,
    required this.title,
    this.notes = '',
    required this.occurredAt,
  });
  final String id;
  final int revision;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? createdByAccountId;
  final String? updatedByAccountId;
  final String fromAccountId;
  final String toAccountId;
  final int amountMinor;
  final String currency;
  final SharedFinanceStatus status;
  final String title;
  final String notes;
  final DateTime occurredAt;
  SharedFinanceTransfer copyWith({
    int? revision,
    DateTime? updatedAt,
    String? fromAccountId,
    String? toAccountId,
    int? amountMinor,
    String? currency,
    SharedFinanceStatus? status,
    String? title,
    String? notes,
    DateTime? occurredAt,
  }) => SharedFinanceTransfer(
    id: id,
    revision: revision ?? this.revision,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    createdByAccountId: createdByAccountId,
    updatedByAccountId: updatedByAccountId,
    fromAccountId: fromAccountId ?? this.fromAccountId,
    toAccountId: toAccountId ?? this.toAccountId,
    amountMinor: amountMinor ?? this.amountMinor,
    currency: currency ?? this.currency,
    status: status ?? this.status,
    title: title ?? this.title,
    notes: notes ?? this.notes,
    occurredAt: occurredAt ?? this.occurredAt,
  );
  Map<String, Object?> toJson() => {
    'id': id,
    'revision': revision,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'createdByAccountId': createdByAccountId,
    'updatedByAccountId': updatedByAccountId,
    'fromAccountId': fromAccountId,
    'toAccountId': toAccountId,
    'amountMinor': amountMinor,
    'currency': currency,
    'status': status.name,
    'title': title,
    'notes': notes,
    'occurredAt': occurredAt.toUtc().toIso8601String(),
  };
  Map<String, Object?> toPayload() => Map.of(toJson())
    ..remove('id')
    ..remove('revision')
    ..remove('createdByAccountId')
    ..remove('updatedByAccountId');
  factory SharedFinanceTransfer.fromJson(Map<String, dynamic> j) =>
      SharedFinanceTransfer(
        id: readString(j, 'id'),
        revision: readInt(j, 'revision'),
        createdAt: readSharedDate(j, 'createdAt'),
        updatedAt: readSharedDate(j, 'updatedAt'),
        createdByAccountId: readNullableString(j, 'createdByAccountId'),
        updatedByAccountId: readNullableString(j, 'updatedByAccountId'),
        fromAccountId: readString(j, 'fromAccountId'),
        toAccountId: readString(j, 'toAccountId'),
        amountMinor: readInt(j, 'amountMinor'),
        currency: readString(j, 'currency'),
        status: SharedFinanceStatus.values.byName(readString(j, 'status')),
        title: readString(j, 'title'),
        notes: readString(j, 'notes'),
        occurredAt: readSharedDate(j, 'occurredAt'),
      );
}

/// Exact currency totals; a transfer changes account balances, never turnover.
class SharedFinanceTotals {
  SharedFinanceTotals({
    required this.currency,
    required this.incomeMinor,
    required this.expenseMinor,
    required Map<String, BigInt> accountBalances,
  }) : accountBalances = Map.unmodifiable(accountBalances);
  final String currency;
  final BigInt incomeMinor;
  final BigInt expenseMinor;
  final Map<String, BigInt> accountBalances;
  BigInt get netMinor => incomeMinor - expenseMinor;
  BigInt get balanceMinor =>
      accountBalances.values.fold(BigInt.zero, (a, b) => a + b);
}

Map<String, SharedFinanceTotals> summarizeSharedFinance({
  required Iterable<SharedFinanceAccount> accounts,
  required Iterable<SharedFinanceEntry> entries,
  required Iterable<SharedFinanceTransfer> transfers,
}) {
  final byId = {for (final a in accounts) a.id: a};
  final balances = <String, Map<String, BigInt>>{};
  final income = <String, BigInt>{}, expense = <String, BigInt>{};
  for (final a in byId.values) {
    (balances[a.currency] ??= {})[a.id] = BigInt.from(a.openingBalanceMinor);
  }
  for (final e in entries.where(
    (e) => e.status == SharedFinanceStatus.posted,
  )) {
    final a = byId[e.accountId];
    if (a == null || a.currency != e.currency) {
      throw const FormatException('Invalid ledger reference');
    }
    final amount = BigInt.from(e.amountMinor),
        positive = e.kind == FinanceEntryKind.income;
    final totals = positive ? income : expense;
    totals[e.currency] = (totals[e.currency] ?? BigInt.zero) + amount;
    balances[e.currency]![a.id] =
        balances[e.currency]![a.id]! + (positive ? amount : -amount);
  }
  for (final t in transfers.where(
    (e) => e.status == SharedFinanceStatus.posted,
  )) {
    final from = byId[t.fromAccountId], to = byId[t.toAccountId];
    if (from == null ||
        to == null ||
        from.id == to.id ||
        from.currency != t.currency ||
        to.currency != t.currency) {
      throw const FormatException('Invalid transfer reference');
    }
    final amount = BigInt.from(t.amountMinor);
    balances[t.currency]![from.id] = balances[t.currency]![from.id]! - amount;
    balances[t.currency]![to.id] = balances[t.currency]![to.id]! + amount;
  }
  return Map.unmodifiable({
    for (final c in balances.keys)
      c: SharedFinanceTotals(
        currency: c,
        incomeMinor: income[c] ?? BigInt.zero,
        expenseMinor: expense[c] ?? BigInt.zero,
        accountBalances: balances[c]!,
      ),
  });
}

class SharedFinanceAuditEntry {
  SharedFinanceAuditEntry({
    required this.scopeId,
    required this.recordId,
    required this.revision,
    required this.actorAccountId,
    required this.changedAt,
    required this.opId,
    required Map<String, dynamic>? before,
    required Map<String, dynamic>? after,
  }) : before = before == null ? null : Map.unmodifiable(before),
       after = after == null ? null : Map.unmodifiable(after);
  final String scopeId, recordId, actorAccountId, opId;
  final int revision;
  final DateTime changedAt;
  final Map<String, dynamic>? before, after;
  factory SharedFinanceAuditEntry.fromJson(Map<String, dynamic> j) =>
      SharedFinanceAuditEntry(
        scopeId: readString(j, 'scopeId'),
        recordId: readString(j, 'recordId'),
        revision: readInt(j, 'revision'),
        actorAccountId: readString(j, 'actorAccountId'),
        changedAt: readSharedDate(j, 'changedAt'),
        opId: readString(j, 'opId'),
        before: j['before'] as Map<String, dynamic>?,
        after: j['after'] as Map<String, dynamic>?,
      );
}

const sharedEditableCurrencies = ['EUR', 'USD', 'GBP', 'CHF'];
int parseSharedMoneyMinor(
  String value, {
  bool allowSigned = false,
  bool allowZero = false,
}) {
  final normalized = value.trim().replaceAll(',', '.');
  if (!RegExp(
    allowSigned ? r'^-?\d+(?:\.\d{1,2})?$' : r'^\d+(?:\.\d{1,2})?$',
  ).hasMatch(normalized)) {
    throw const FormatException('Invalid amount');
  }
  final negative = normalized.startsWith('-');
  final pieces = (negative ? normalized.substring(1) : normalized).split('.');
  final amount =
      BigInt.parse(pieces.first) * BigInt.from(100) +
      BigInt.parse(pieces.length == 1 ? '0' : pieces[1].padRight(2, '0'));
  if (amount > BigInt.from(9000000000000) ||
      (!allowZero && amount == BigInt.zero)) {
    throw const FormatException('Amount outside allowed range');
  }
  return (negative ? -amount : amount).toInt();
}

String formatSharedMoneyMinor(BigInt value, {int fractionDigits = 2}) {
  if (fractionDigits < 0 || fractionDigits > 6) {
    throw ArgumentError.value(fractionDigits);
  }
  final abs = value.abs().toString().padLeft(fractionDigits + 1, '0');
  final sign = value.isNegative ? '-' : '';
  if (fractionDigits == 0) return '$sign$abs';
  return '$sign${abs.substring(0, abs.length - fractionDigits)}.${abs.substring(abs.length - fractionDigits)}';
}

class SharedFinanceConflict {
  SharedFinanceConflict({
    required this.id,
    required this.scopeId,
    required this.recordId,
    required this.recordType,
    required this.reason,
    this.remoteDeleted = false,
    Map<String, dynamic>? localPayload,
    Map<String, dynamic>? remotePayload,
  }) : localPayload = localPayload == null
           ? null
           : Map.unmodifiable(localPayload),
       remotePayload = remotePayload == null
           ? null
           : Map.unmodifiable(remotePayload);
  final String id, scopeId, recordId, reason;
  final SharedFinanceRecordType recordType;
  final bool remoteDeleted;
  final Map<String, dynamic>? localPayload, remotePayload;
}

bool isFinancialRecordType(String type) =>
    type.startsWith('finance') || type == 'personalFinanceEntry';
