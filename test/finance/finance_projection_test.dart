import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/board/finance/finance_projection.dart';
import 'package:kanban/models/finance_models.dart';

void main() {
  group('buildFinanceProjection', () {
    test('aggregates contributor incomes per month', () {
      final table = FinanceTableData(
        schemaVersion: 1,
        currencyCode: 'EUR',
        currentBalanceCents: 10000,
        contributors: const <FinanceContributor>[
          FinanceContributor(id: 'a', name: 'A'),
          FinanceContributor(id: 'b', name: 'B'),
        ],
        months: const <FinanceMonthEntry>[
          FinanceMonthEntry(
            monthKey: '2026-03',
            incomesByContributorCents: <String, int>{'a': 100000, 'b': 50000},
          ),
        ],
        recurringIncomes: const <RecurringIncome>[],
        plannedIncomes: const <PlannedIncome>[],
        recurringExpenses: const <RecurringExpense>[],
        plannedExpenses: const <PlannedExpense>[],
      );

      final result = buildFinanceProjection(
        tableData: table,
        horizonMonths: 1,
        startMonthKey: '2026-03',
      );

      expect(result.months, hasLength(1));
      expect(result.months.first.totalIncomeCents, 150000);
      expect(result.months.first.netCents, 150000);
      expect(result.months.first.closingBalanceCents, 160000);
    });

    test('combines recurring and planned expenses correctly', () {
      final table = FinanceTableData(
        schemaVersion: 1,
        currencyCode: 'EUR',
        currentBalanceCents: 0,
        contributors: const <FinanceContributor>[],
        months: const <FinanceMonthEntry>[
          FinanceMonthEntry(
            monthKey: '2026-03',
            incomesByContributorCents: <String, int>{},
          ),
        ],
        recurringIncomes: const <RecurringIncome>[],
        plannedIncomes: const <PlannedIncome>[],
        recurringExpenses: const <RecurringExpense>[
          RecurringExpense(
            id: 'rent',
            category: 'Rent',
            amountCents: 70000,
            startMonthKey: '2026-01',
            endMonthKey: null,
            enabled: true,
          ),
        ],
        plannedExpenses: const <PlannedExpense>[
          PlannedExpense(
            id: 'car',
            title: 'Car service',
            category: 'Car',
            amountCents: 12000,
            monthKey: '2026-03',
          ),
        ],
      );

      final result = buildFinanceProjection(
        tableData: table,
        horizonMonths: 1,
        startMonthKey: '2026-03',
      );

      expect(result.months.first.totalRecurringExpenseCents, 70000);
      expect(result.months.first.totalPlannedExpenseCents, 12000);
      expect(result.months.first.totalExpenseCents, 82000);
      expect(result.months.first.netCents, -82000);
    });

    test('detects first negative month and lowest balance', () {
      final table = FinanceTableData(
        schemaVersion: 1,
        currencyCode: 'EUR',
        currentBalanceCents: 50000,
        contributors: const <FinanceContributor>[],
        months: const <FinanceMonthEntry>[
          FinanceMonthEntry(
            monthKey: '2026-03',
            incomesByContributorCents: <String, int>{},
          ),
          FinanceMonthEntry(
            monthKey: '2026-04',
            incomesByContributorCents: <String, int>{},
          ),
        ],
        recurringIncomes: const <RecurringIncome>[],
        plannedIncomes: const <PlannedIncome>[],
        recurringExpenses: const <RecurringExpense>[
          RecurringExpense(
            id: 'fixed',
            category: 'Fixed',
            amountCents: 30000,
            startMonthKey: '2026-03',
            endMonthKey: null,
            enabled: true,
          ),
        ],
        plannedExpenses: const <PlannedExpense>[
          PlannedExpense(
            id: 'tax',
            title: 'Tax',
            category: 'Tax',
            amountCents: 60000,
            monthKey: '2026-04',
          ),
        ],
      );

      final result = buildFinanceProjection(
        tableData: table,
        horizonMonths: 2,
        startMonthKey: '2026-03',
      );

      expect(result.months, hasLength(2));
      expect(result.firstNegativeMonthKey, '2026-04');
      expect(result.lowestBalanceMonthKey, '2026-04');
      expect(result.endBalanceCents, -70000);
    });

    test('adds recurring and planned incomes on top of monthly incomes', () {
      final table = FinanceTableData(
        schemaVersion: 1,
        currencyCode: 'EUR',
        currentBalanceCents: 0,
        contributors: const <FinanceContributor>[
          FinanceContributor(id: 'u1', name: 'User 1'),
        ],
        months: const <FinanceMonthEntry>[
          FinanceMonthEntry(
            monthKey: '2026-05',
            incomesByContributorCents: <String, int>{'u1': 100000},
          ),
        ],
        recurringIncomes: const <RecurringIncome>[
          RecurringIncome(
            id: 'salary',
            title: 'Salary',
            amountCents: 50000,
            startMonthKey: '2026-01',
            enabled: true,
            contributorId: 'u1',
          ),
        ],
        plannedIncomes: const <PlannedIncome>[
          PlannedIncome(
            id: 'bonus',
            title: 'Bonus',
            amountCents: 20000,
            monthKey: '2026-05',
          ),
        ],
        recurringExpenses: const <RecurringExpense>[],
        plannedExpenses: const <PlannedExpense>[],
      );

      final result = buildFinanceProjection(
        tableData: table,
        horizonMonths: 1,
        startMonthKey: '2026-05',
      );

      expect(result.months, hasLength(1));
      expect(result.months.first.totalIncomeCents, 170000);
      expect(result.months.first.closingBalanceCents, 170000);
    });
  });
}
