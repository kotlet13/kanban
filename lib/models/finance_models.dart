class FinanceContributor {
  const FinanceContributor({required this.id, required this.name});

  final String id;
  final String name;

  factory FinanceContributor.fromJson(Map<String, dynamic> json) {
    return FinanceContributor(
      id: (json['id'] ?? '').toString().trim(),
      name: (json['name'] ?? '').toString().trim(),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{'id': id, 'name': name};
}

class FinanceMonthEntry {
  const FinanceMonthEntry({
    required this.monthKey,
    required this.incomesByContributorCents,
  });

  final String monthKey;
  final Map<String, int> incomesByContributorCents;

  int get totalIncomeCents =>
      incomesByContributorCents.values.fold(0, (sum, value) => sum + value);

  factory FinanceMonthEntry.fromJson(Map<String, dynamic> json) {
    final rawIncomes = json['incomesByContributorCents'];
    final incomes = <String, int>{};
    if (rawIncomes is Map) {
      rawIncomes.forEach((key, value) {
        final contributorId = key.toString().trim();
        final parsed = int.tryParse('${value ?? 0}') ?? 0;
        if (contributorId.isNotEmpty) {
          incomes[contributorId] = parsed < 0 ? 0 : parsed;
        }
      });
    }
    return FinanceMonthEntry(
      monthKey: (json['monthKey'] ?? '').toString().trim(),
      incomesByContributorCents: incomes,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'monthKey': monthKey,
    'incomesByContributorCents': incomesByContributorCents,
  };
}

class RecurringExpense {
  const RecurringExpense({
    required this.id,
    required this.category,
    required this.amountCents,
    required this.startMonthKey,
    this.endMonthKey,
    this.contributorId,
    this.enabled = true,
  });

  final String id;
  final String category;
  final int amountCents;
  final String startMonthKey;
  final String? endMonthKey;
  final String? contributorId;
  final bool enabled;

  factory RecurringExpense.fromJson(Map<String, dynamic> json) {
    return RecurringExpense(
      id: (json['id'] ?? '').toString().trim(),
      category: (json['category'] ?? '').toString().trim(),
      amountCents: _parseNonNegativeInt(json['amountCents']),
      startMonthKey: (json['startMonthKey'] ?? '').toString().trim(),
      endMonthKey: (json['endMonthKey'] ?? '').toString().trim().isEmpty
          ? null
          : json['endMonthKey'].toString().trim(),
      contributorId: (json['contributorId'] ?? '').toString().trim().isEmpty
          ? null
          : json['contributorId'].toString().trim(),
      enabled: _parseBool(json['enabled'], fallback: true),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'category': category,
    'amountCents': amountCents,
    'startMonthKey': startMonthKey,
    'endMonthKey': endMonthKey,
    'contributorId': contributorId,
    'enabled': enabled,
  };
}

class PlannedExpense {
  const PlannedExpense({
    required this.id,
    required this.title,
    required this.category,
    required this.amountCents,
    required this.monthKey,
    this.contributorId,
  });

  final String id;
  final String title;
  final String category;
  final int amountCents;
  final String monthKey;
  final String? contributorId;

  factory PlannedExpense.fromJson(Map<String, dynamic> json) {
    return PlannedExpense(
      id: (json['id'] ?? '').toString().trim(),
      title: (json['title'] ?? '').toString().trim(),
      category: (json['category'] ?? '').toString().trim(),
      amountCents: _parseNonNegativeInt(json['amountCents']),
      monthKey: (json['monthKey'] ?? '').toString().trim(),
      contributorId: (json['contributorId'] ?? '').toString().trim().isEmpty
          ? null
          : json['contributorId'].toString().trim(),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'title': title,
    'category': category,
    'amountCents': amountCents,
    'monthKey': monthKey,
    'contributorId': contributorId,
  };
}

class RecurringIncome {
  const RecurringIncome({
    required this.id,
    required this.title,
    required this.amountCents,
    required this.startMonthKey,
    this.endMonthKey,
    this.contributorId,
    this.enabled = true,
  });

  final String id;
  final String title;
  final int amountCents;
  final String startMonthKey;
  final String? endMonthKey;
  final String? contributorId;
  final bool enabled;

  factory RecurringIncome.fromJson(Map<String, dynamic> json) {
    return RecurringIncome(
      id: (json['id'] ?? '').toString().trim(),
      title: (json['title'] ?? '').toString().trim(),
      amountCents: _parseNonNegativeInt(json['amountCents']),
      startMonthKey: (json['startMonthKey'] ?? '').toString().trim(),
      endMonthKey: (json['endMonthKey'] ?? '').toString().trim().isEmpty
          ? null
          : json['endMonthKey'].toString().trim(),
      contributorId: (json['contributorId'] ?? '').toString().trim().isEmpty
          ? null
          : json['contributorId'].toString().trim(),
      enabled: _parseBool(json['enabled'], fallback: true),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'title': title,
    'amountCents': amountCents,
    'startMonthKey': startMonthKey,
    'endMonthKey': endMonthKey,
    'contributorId': contributorId,
    'enabled': enabled,
  };
}

class PlannedIncome {
  const PlannedIncome({
    required this.id,
    required this.title,
    required this.amountCents,
    required this.monthKey,
    this.contributorId,
  });

  final String id;
  final String title;
  final int amountCents;
  final String monthKey;
  final String? contributorId;

  factory PlannedIncome.fromJson(Map<String, dynamic> json) {
    return PlannedIncome(
      id: (json['id'] ?? '').toString().trim(),
      title: (json['title'] ?? '').toString().trim(),
      amountCents: _parseNonNegativeInt(json['amountCents']),
      monthKey: (json['monthKey'] ?? '').toString().trim(),
      contributorId: (json['contributorId'] ?? '').toString().trim().isEmpty
          ? null
          : json['contributorId'].toString().trim(),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'title': title,
    'amountCents': amountCents,
    'monthKey': monthKey,
    'contributorId': contributorId,
  };
}

class FinanceTableData {
  const FinanceTableData({
    required this.schemaVersion,
    required this.currencyCode,
    required this.currentBalanceCents,
    required this.contributors,
    required this.months,
    required this.recurringIncomes,
    required this.plannedIncomes,
    required this.recurringExpenses,
    required this.plannedExpenses,
  });

  static const int currentSchemaVersion = 1;

  final int schemaVersion;
  final String currencyCode;
  final int currentBalanceCents;
  final List<FinanceContributor> contributors;
  final List<FinanceMonthEntry> months;
  final List<RecurringIncome> recurringIncomes;
  final List<PlannedIncome> plannedIncomes;
  final List<RecurringExpense> recurringExpenses;
  final List<PlannedExpense> plannedExpenses;

  factory FinanceTableData.empty() {
    return const FinanceTableData(
      schemaVersion: currentSchemaVersion,
      currencyCode: 'EUR',
      currentBalanceCents: 0,
      contributors: <FinanceContributor>[],
      months: <FinanceMonthEntry>[],
      recurringIncomes: <RecurringIncome>[],
      plannedIncomes: <PlannedIncome>[],
      recurringExpenses: <RecurringExpense>[],
      plannedExpenses: <PlannedExpense>[],
    );
  }

  factory FinanceTableData.fromJson(Map<String, dynamic> json) {
    List<T> parseList<T>(dynamic raw, T Function(Map<String, dynamic>) parse) {
      if (raw is! List) return <T>[];
      return raw
          .whereType<Map>()
          .map((entry) => parse(Map<String, dynamic>.from(entry)))
          .toList();
    }

    final currencyCode = (json['currencyCode'] ?? 'EUR').toString().trim();

    return FinanceTableData(
      schemaVersion: _parseNonNegativeInt(
        json['schemaVersion'],
        fallback: currentSchemaVersion,
      ),
      currencyCode: currencyCode.isEmpty ? 'EUR' : currencyCode.toUpperCase(),
      currentBalanceCents: _parseInt(json['currentBalanceCents']),
      contributors: parseList(
        json['contributors'],
        FinanceContributor.fromJson,
      ),
      months: parseList(json['months'], FinanceMonthEntry.fromJson),
      recurringIncomes: parseList(
        json['recurringIncomes'],
        RecurringIncome.fromJson,
      ),
      plannedIncomes: parseList(json['plannedIncomes'], PlannedIncome.fromJson),
      recurringExpenses: parseList(
        json['recurringExpenses'],
        RecurringExpense.fromJson,
      ),
      plannedExpenses: parseList(
        json['plannedExpenses'],
        PlannedExpense.fromJson,
      ),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'schemaVersion': schemaVersion,
    'currencyCode': currencyCode,
    'currentBalanceCents': currentBalanceCents,
    'contributors': contributors.map((entry) => entry.toJson()).toList(),
    'months': months.map((entry) => entry.toJson()).toList(),
    'recurringIncomes': recurringIncomes
        .map((entry) => entry.toJson())
        .toList(),
    'plannedIncomes': plannedIncomes.map((entry) => entry.toJson()).toList(),
    'recurringExpenses': recurringExpenses
        .map((entry) => entry.toJson())
        .toList(),
    'plannedExpenses': plannedExpenses.map((entry) => entry.toJson()).toList(),
  };

  FinanceTableData copyWith({
    int? schemaVersion,
    String? currencyCode,
    int? currentBalanceCents,
    List<FinanceContributor>? contributors,
    List<FinanceMonthEntry>? months,
    List<RecurringIncome>? recurringIncomes,
    List<PlannedIncome>? plannedIncomes,
    List<RecurringExpense>? recurringExpenses,
    List<PlannedExpense>? plannedExpenses,
  }) {
    return FinanceTableData(
      schemaVersion: schemaVersion ?? this.schemaVersion,
      currencyCode: currencyCode ?? this.currencyCode,
      currentBalanceCents: currentBalanceCents ?? this.currentBalanceCents,
      contributors: contributors ?? this.contributors,
      months: months ?? this.months,
      recurringIncomes: recurringIncomes ?? this.recurringIncomes,
      plannedIncomes: plannedIncomes ?? this.plannedIncomes,
      recurringExpenses: recurringExpenses ?? this.recurringExpenses,
      plannedExpenses: plannedExpenses ?? this.plannedExpenses,
    );
  }
}

int _parseNonNegativeInt(dynamic value, {int fallback = 0}) {
  final parsed = int.tryParse('${value ?? fallback}') ?? fallback;
  if (parsed < 0) return fallback;
  return parsed;
}

int _parseInt(dynamic value, {int fallback = 0}) {
  return int.tryParse('${value ?? fallback}') ?? fallback;
}

bool _parseBool(dynamic value, {bool fallback = false}) {
  if (value is bool) return value;
  if (value is int) return value != 0;
  if (value is String) {
    final lower = value.trim().toLowerCase();
    if (lower == 'true' || lower == '1') return true;
    if (lower == 'false' || lower == '0') return false;
  }
  return fallback;
}
