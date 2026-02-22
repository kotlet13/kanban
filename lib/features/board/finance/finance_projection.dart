import '../../../models/finance_models.dart';

class FinanceProjectionMonth {
  const FinanceProjectionMonth({
    required this.monthKey,
    required this.openingBalanceCents,
    required this.totalIncomeCents,
    required this.totalRecurringExpenseCents,
    required this.totalPlannedExpenseCents,
    required this.totalExpenseCents,
    required this.netCents,
    required this.closingBalanceCents,
  });

  final String monthKey;
  final int openingBalanceCents;
  final int totalIncomeCents;
  final int totalRecurringExpenseCents;
  final int totalPlannedExpenseCents;
  final int totalExpenseCents;
  final int netCents;
  final int closingBalanceCents;
}

class FinanceProjectionSummary {
  const FinanceProjectionSummary({
    required this.months,
    required this.lowestBalanceCents,
    required this.lowestBalanceMonthKey,
    required this.firstNegativeMonthKey,
    required this.endBalanceCents,
  });

  final List<FinanceProjectionMonth> months;
  final int lowestBalanceCents;
  final String? lowestBalanceMonthKey;
  final String? firstNegativeMonthKey;
  final int endBalanceCents;
}

FinanceProjectionSummary buildFinanceProjection({
  required FinanceTableData tableData,
  required int horizonMonths,
  String? startMonthKey,
}) {
  if (horizonMonths <= 0) {
    return FinanceProjectionSummary(
      months: const <FinanceProjectionMonth>[],
      lowestBalanceCents: tableData.currentBalanceCents,
      lowestBalanceMonthKey: null,
      firstNegativeMonthKey: null,
      endBalanceCents: tableData.currentBalanceCents,
    );
  }

  final normalizedStartMonth =
      _normalizeMonthKey(startMonthKey) ?? _currentMonthKey();
  var openingBalance = tableData.currentBalanceCents;
  final rows = <FinanceProjectionMonth>[];
  String? firstNegative;
  String? lowestMonth;
  var lowestBalance = openingBalance;

  for (var i = 0; i < horizonMonths; i++) {
    final monthKey = shiftMonthKey(normalizedStartMonth, i);
    final manualIncomeCents = _incomeForMonth(
      tableData: tableData,
      monthKey: monthKey,
    );
    final recurringIncomeCents = _recurringIncomeForMonth(
      recurringIncomes: tableData.recurringIncomes,
      monthKey: monthKey,
    );
    final plannedIncomeCents = _plannedIncomeForMonth(
      plannedIncomes: tableData.plannedIncomes,
      monthKey: monthKey,
    );
    final incomeCents =
        manualIncomeCents + recurringIncomeCents + plannedIncomeCents;
    final recurringCents = _recurringForMonth(
      recurringExpenses: tableData.recurringExpenses,
      monthKey: monthKey,
    );
    final plannedCents = _plannedForMonth(
      plannedExpenses: tableData.plannedExpenses,
      monthKey: monthKey,
    );
    final totalExpense = recurringCents + plannedCents;
    final net = incomeCents - totalExpense;
    final closing = openingBalance + net;

    if (closing < 0 && firstNegative == null) {
      firstNegative = monthKey;
    }
    if (rows.isEmpty || closing < lowestBalance) {
      lowestBalance = closing;
      lowestMonth = monthKey;
    }

    rows.add(
      FinanceProjectionMonth(
        monthKey: monthKey,
        openingBalanceCents: openingBalance,
        totalIncomeCents: incomeCents,
        totalRecurringExpenseCents: recurringCents,
        totalPlannedExpenseCents: plannedCents,
        totalExpenseCents: totalExpense,
        netCents: net,
        closingBalanceCents: closing,
      ),
    );
    openingBalance = closing;
  }

  return FinanceProjectionSummary(
    months: rows,
    lowestBalanceCents: lowestBalance,
    lowestBalanceMonthKey: lowestMonth,
    firstNegativeMonthKey: firstNegative,
    endBalanceCents: rows.isEmpty
        ? tableData.currentBalanceCents
        : rows.last.closingBalanceCents,
  );
}

int _incomeForMonth({
  required FinanceTableData tableData,
  required String monthKey,
}) {
  for (final month in tableData.months) {
    if (month.monthKey == monthKey) {
      return month.totalIncomeCents;
    }
  }
  return 0;
}

int _plannedIncomeForMonth({
  required List<PlannedIncome> plannedIncomes,
  required String monthKey,
}) {
  var total = 0;
  for (final income in plannedIncomes) {
    if (income.monthKey == monthKey) {
      total += income.amountCents;
    }
  }
  return total;
}

int _recurringIncomeForMonth({
  required List<RecurringIncome> recurringIncomes,
  required String monthKey,
}) {
  var total = 0;
  for (final income in recurringIncomes) {
    if (!income.enabled) continue;
    if (!_isMonthInRange(
      monthKey: monthKey,
      startMonthKey: income.startMonthKey,
      endMonthKey: income.endMonthKey,
    )) {
      continue;
    }
    total += income.amountCents;
  }
  return total;
}

int _plannedForMonth({
  required List<PlannedExpense> plannedExpenses,
  required String monthKey,
}) {
  var total = 0;
  for (final expense in plannedExpenses) {
    if (expense.monthKey == monthKey) {
      total += expense.amountCents;
    }
  }
  return total;
}

int _recurringForMonth({
  required List<RecurringExpense> recurringExpenses,
  required String monthKey,
}) {
  var total = 0;
  for (final expense in recurringExpenses) {
    if (!expense.enabled) continue;
    if (!_isMonthInRange(
      monthKey: monthKey,
      startMonthKey: expense.startMonthKey,
      endMonthKey: expense.endMonthKey,
    )) {
      continue;
    }
    total += expense.amountCents;
  }
  return total;
}

bool _isMonthInRange({
  required String monthKey,
  required String startMonthKey,
  required String? endMonthKey,
}) {
  if (monthKey.compareTo(startMonthKey) < 0) return false;
  if (endMonthKey == null || endMonthKey.trim().isEmpty) return true;
  return monthKey.compareTo(endMonthKey.trim()) <= 0;
}

String? _normalizeMonthKey(String? raw) {
  if (raw == null) return null;
  final text = raw.trim();
  if (!RegExp(r'^\d{4}-\d{2}$').hasMatch(text)) return null;
  final month = int.tryParse(text.substring(5));
  if (month == null || month < 1 || month > 12) return null;
  return text;
}

String _currentMonthKey() {
  final now = DateTime.now();
  return '${now.year}-${now.month.toString().padLeft(2, '0')}';
}

String shiftMonthKey(String monthKey, int deltaMonths) {
  final year = int.tryParse(monthKey.substring(0, 4)) ?? DateTime.now().year;
  final month = int.tryParse(monthKey.substring(5, 7)) ?? 1;
  final current = DateTime(year, month);
  final shifted = DateTime(current.year, current.month + deltaMonths);
  return '${shifted.year}-${shifted.month.toString().padLeft(2, '0')}';
}
