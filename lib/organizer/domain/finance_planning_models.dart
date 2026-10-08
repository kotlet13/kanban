part of 'organizer_models.dart';

/// A named ledger reference; it does not connect to or move money at a bank.
class LocalFinanceAccount {
  const LocalFinanceAccount({
    required this.id,
    required this.name,
    required this.currency,
    this.openingBalanceMinor,
    this.openingBalanceAt,
    this.archived = false,
    this.revision = 0,
    required this.createdAt,
    required this.updatedAt,
  });
  final String id, name, currency;
  final int? openingBalanceMinor;
  final DateTime? openingBalanceAt;
  final bool archived;
  final int revision;
  final DateTime createdAt, updatedAt;

  LocalFinanceAccount copyWith({
    String? name,
    String? currency,
    Object? openingBalanceMinor = _unset,
    Object? openingBalanceAt = _unset,
    bool? archived,
    int? revision,
    DateTime? updatedAt,
  }) => LocalFinanceAccount(
    id: id,
    name: name ?? this.name,
    currency: currency ?? this.currency,
    openingBalanceMinor: identical(openingBalanceMinor, _unset)
        ? this.openingBalanceMinor
        : openingBalanceMinor as int?,
    openingBalanceAt: identical(openingBalanceAt, _unset)
        ? this.openingBalanceAt
        : openingBalanceAt as DateTime?,
    archived: archived ?? this.archived,
    revision: revision ?? this.revision,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  void validate() {
    _validateFinancePlanIdentity(id, name, revision, createdAt, updatedAt);
    if (!supportedCurrencies.contains(currency) ||
        openingBalanceMinor == null && openingBalanceAt != null ||
        (openingBalanceMinor?.abs() ?? 0) > maxMoneyMinor) {
      throw const FormatException('Invalid finance account balance');
    }
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'currency': currency,
    'openingBalanceMinor': openingBalanceMinor,
    'openingBalanceAt': openingBalanceAt?.toUtc().toIso8601String(),
    'archived': archived,
    'revision': revision,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };
  factory LocalFinanceAccount.fromJson(Map<String, dynamic> json) {
    final record = LocalFinanceAccount(
      id: readString(json, 'id'),
      name: readString(json, 'name'),
      currency: readString(json, 'currency'),
      openingBalanceMinor: json['openingBalanceMinor'] == null
          ? null
          : readInt(json, 'openingBalanceMinor'),
      openingBalanceAt: readNullableDate(json, 'openingBalanceAt'),
      archived: readBool(json, 'archived'),
      revision: readInt(json, 'revision'),
      createdAt: readDate(json, 'createdAt'),
      updatedAt: readDate(json, 'updatedAt'),
    );
    record.validate();
    return record;
  }
}

enum FinanceRecurrenceKind {
  salary,
  income,
  loanInstallment,
  cardSettlement,
  expense,
}

/// One monthly estimate. Confirmation updates its occurrence, never books twice.
class FinanceRecurrenceRule {
  const FinanceRecurrenceRule({
    required this.id,
    required this.title,
    required this.kind,
    this.ledgerAccountId,
    required this.currency,
    required this.estimatedAmountMinor,
    this.loanPrincipalMinor,
    required this.startYear,
    required this.startMonth,
    required this.monthDay,
    this.endYear,
    this.endMonth,
    this.active = true,
    this.remindersEnabled = false,
    this.reminderMinuteOfDay = 540,
    this.revision = 0,
    required this.createdAt,
    required this.updatedAt,
  });
  final String id, title, currency;
  final FinanceRecurrenceKind kind;
  final String? ledgerAccountId;
  final int estimatedAmountMinor;
  final int? loanPrincipalMinor;
  final int startYear, startMonth, monthDay;
  final int? endYear, endMonth;
  final bool active, remindersEnabled;
  final int reminderMinuteOfDay, revision;
  final DateTime createdAt, updatedAt;
  FinanceEntryKind get entryKind =>
      kind == FinanceRecurrenceKind.salary ||
          kind == FinanceRecurrenceKind.income
      ? FinanceEntryKind.income
      : FinanceEntryKind.expense;
  bool includesMonth(int year, int month) {
    final key = year * 12 + month;
    return active &&
        key >= startYear * 12 + startMonth &&
        (endYear == null || key <= endYear! * 12 + endMonth!);
  }

  DateTime dateForMonth(int year, int month) => DateTime(
    year,
    month,
    monthDay.clamp(1, DateTime(year, month + 1, 0).day),
  );
  String keyForMonth(int year, int month) =>
      '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}';
  FinanceRecurrenceRule copyWith({
    String? title,
    FinanceRecurrenceKind? kind,
    Object? ledgerAccountId = _unset,
    String? currency,
    int? estimatedAmountMinor,
    Object? loanPrincipalMinor = _unset,
    int? startYear,
    int? startMonth,
    int? monthDay,
    Object? endYear = _unset,
    Object? endMonth = _unset,
    bool? active,
    bool? remindersEnabled,
    int? reminderMinuteOfDay,
    int? revision,
    DateTime? updatedAt,
  }) => FinanceRecurrenceRule(
    id: id,
    title: title ?? this.title,
    kind: kind ?? this.kind,
    ledgerAccountId: identical(ledgerAccountId, _unset)
        ? this.ledgerAccountId
        : ledgerAccountId as String?,
    currency: currency ?? this.currency,
    estimatedAmountMinor: estimatedAmountMinor ?? this.estimatedAmountMinor,
    loanPrincipalMinor: identical(loanPrincipalMinor, _unset)
        ? this.loanPrincipalMinor
        : loanPrincipalMinor as int?,
    startYear: startYear ?? this.startYear,
    startMonth: startMonth ?? this.startMonth,
    monthDay: monthDay ?? this.monthDay,
    endYear: identical(endYear, _unset) ? this.endYear : endYear as int?,
    endMonth: identical(endMonth, _unset) ? this.endMonth : endMonth as int?,
    active: active ?? this.active,
    remindersEnabled: remindersEnabled ?? this.remindersEnabled,
    reminderMinuteOfDay: reminderMinuteOfDay ?? this.reminderMinuteOfDay,
    revision: revision ?? this.revision,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  void validate() {
    _validateFinancePlanIdentity(id, title, revision, createdAt, updatedAt);
    if (!supportedCurrencies.contains(currency) ||
        estimatedAmountMinor <= 0 ||
        estimatedAmountMinor > maxMoneyMinor ||
        (loanPrincipalMinor != null &&
            (loanPrincipalMinor! <= 0 ||
                loanPrincipalMinor! > maxMoneyMinor ||
                kind != FinanceRecurrenceKind.loanInstallment)) ||
        startYear < 1900 ||
        startYear > 2200 ||
        startMonth < 1 ||
        startMonth > 12 ||
        monthDay < 1 ||
        monthDay > 31 ||
        reminderMinuteOfDay < 0 ||
        reminderMinuteOfDay >= 1440 ||
        (endYear == null) != (endMonth == null) ||
        (endYear != null &&
            (endYear! < startYear ||
                endYear! > 2200 ||
                endMonth! < 1 ||
                endMonth! > 12 ||
                endYear! * 12 + endMonth! < startYear * 12 + startMonth)) ||
        ledgerAccountId == '') {
      throw const FormatException('Invalid monthly finance rule');
    }
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'kind': kind.name,
    'ledgerAccountId': ledgerAccountId,
    'currency': currency,
    'estimatedAmountMinor': estimatedAmountMinor,
    'loanPrincipalMinor': loanPrincipalMinor,
    'startYear': startYear,
    'startMonth': startMonth,
    'monthDay': monthDay,
    'endYear': endYear,
    'endMonth': endMonth,
    'active': active,
    'remindersEnabled': remindersEnabled,
    'reminderMinuteOfDay': reminderMinuteOfDay,
    'revision': revision,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };
  factory FinanceRecurrenceRule.fromJson(Map<String, dynamic> json) {
    final kind = switch (readString(json, 'kind')) {
      'salary' => FinanceRecurrenceKind.salary,
      'income' => FinanceRecurrenceKind.income,
      'loanInstallment' => FinanceRecurrenceKind.loanInstallment,
      'cardSettlement' => FinanceRecurrenceKind.cardSettlement,
      'expense' => FinanceRecurrenceKind.expense,
      _ => throw const FormatException('Invalid recurrence kind'),
    };
    final rule = FinanceRecurrenceRule(
      id: readString(json, 'id'),
      title: readString(json, 'title'),
      kind: kind,
      ledgerAccountId: readNullableString(json, 'ledgerAccountId'),
      currency: readString(json, 'currency'),
      estimatedAmountMinor: readInt(json, 'estimatedAmountMinor'),
      loanPrincipalMinor: json['loanPrincipalMinor'] == null
          ? null
          : readInt(json, 'loanPrincipalMinor'),
      startYear: readInt(json, 'startYear'),
      startMonth: readInt(json, 'startMonth'),
      monthDay: readInt(json, 'monthDay'),
      endYear: json['endYear'] == null ? null : readInt(json, 'endYear'),
      endMonth: json['endMonth'] == null ? null : readInt(json, 'endMonth'),
      active: readBool(json, 'active'),
      remindersEnabled: readBool(json, 'remindersEnabled'),
      reminderMinuteOfDay: readInt(json, 'reminderMinuteOfDay'),
      revision: readInt(json, 'revision'),
      createdAt: readDate(json, 'createdAt'),
      updatedAt: readDate(json, 'updatedAt'),
    );
    rule.validate();
    return rule;
  }
}

void _validateFinancePlanIdentity(
  String id,
  String title,
  int revision,
  DateTime createdAt,
  DateTime updatedAt,
) {
  if (id.isEmpty ||
      id.length > 200 ||
      title.trim().isEmpty ||
      title.length > 500 ||
      revision < 0 ||
      updatedAt.isBefore(createdAt)) {
    throw const FormatException('Invalid finance planning record');
  }
}
