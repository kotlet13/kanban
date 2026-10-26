import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/presentation/finance/shared_finance_account_overview.dart';
import 'package:kanban/organizer/presentation/finance/shared_finance_ledger.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';

import 'organization_finance_ui_test.dart' as finance;

CollaborationState accountOverviewState({bool complete = true}) {
  final base = finance.fixture();
  return CollaborationState(
    session: base.session,
    financeSupported: true,
    organizationFinanceSupported: true,
    financeContractVersion: 3,
    selectedSpaceId: 'project',
    scopes: base.scopes,
    financePolicies: base.financePolicies,
    financeSnapshotComplete: {'org': true, 'project': complete},
    financeSnapshotSequences: base.financeSnapshotSequences,
    financeAccountChoices: base.financeAccountChoices,
    data: {
      'org': SharedScopeData(
        financeAccounts: [
          finance.account('bank', 'racunqa25'),
          finance.account('other', 'Other account'),
        ],
        financeEntries: [
          finance.entry(
            'other-cost',
            'Unrelated account cost',
            500,
            accountId: 'other',
          ),
        ],
      ),
      'project': SharedScopeData(
        financeEntries: [
          finance.entry('cost', 'test fin 25', 1234, accountScopeId: 'org'),
        ],
      ),
    },
  );
}

Future<void> openFromAccounts(WidgetTester tester) async {
  final manage = find.text('Računi prostora');
  await tester.ensureVisible(manage);
  await tester.tap(manage);
  await tester.pumpAndSettle();
  final overview = find.byKey(const ValueKey('space-finance-overview-bank'));
  await tester.ensureVisible(overview);
  await tester.tap(overview);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'live incomplete account overview withdraws balance while retaining selected movement',
    (tester) async {
      final controller = finance.FinanceController(accountOverviewState());
      await finance.pumpFinance(
        tester,
        controller,
        scopeId: 'project',
        content: (context, ref, state) => TextButton(
          onPressed: () =>
              showSharedFinanceAccountOverview(context, state, 'org', 'bank'),
          child: const Text('Open overview'),
        ),
      );
      await tester.tap(find.text('Open overview'));
      await tester.pumpAndSettle();
      expect(find.textContaining('987.66'), findsWidgets);
      controller.replace(accountOverviewState(complete: false));
      await tester.pumpAndSettle();
      expect(find.textContaining('987.66'), findsNothing);
      expect(find.textContaining('1000.00'), findsNothing);
      expect(
        find.textContaining('Pregled projektnih financ še ni popoln'),
        findsOneWidget,
      );
      expect(find.text('test fin 25'), findsOneWidget);
      expect(find.text('Unrelated account cost'), findsNothing);
      final ledger = tester.widget<SharedFinanceLedger>(
        find.byType(SharedFinanceLedger),
      );
      expect(ledger.initialAccountId, 'org:bank');
      expect(ledger.cashAvailable, isFalse);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'project account overview selects parent account and shows posted balance without editor',
    (tester) async {
      final controller = finance.FinanceController(accountOverviewState());
      await finance.pumpFinance(tester, controller, scopeId: 'project');
      await openFromAccounts(tester);
      expect(find.text('Pregled računa'), findsOneWidget);
      expect(find.text('test fin 25'), findsOneWidget);
      expect(find.text('Unrelated account cost'), findsNothing);
      expect(find.text('Other account'), findsNothing);
      expect(find.textContaining('987.66'), findsWidgets);
      expect(find.byType(TextField), findsNothing);
      final ledger = tester.widget<SharedFinanceLedger>(
        find.byType(SharedFinanceLedger).last,
      );
      expect(ledger.initialAccountId, 'org:bank');
      expect(ledger.canWrite, isFalse);
      expect(find.text('Dodaj zapis'), findsNothing);
      expect(find.text('Dodaj račun'), findsNothing);
      expect(find.byIcon(Icons.edit_outlined), findsNothing);
      expect(controller.accountsCreated, isEmpty);
      expect(controller.entriesCreated, isEmpty);
      expect(controller.updatedEntry, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'account overview retains incomplete warning and hides inferred balance',
    (tester) async {
      final controller = finance.FinanceController(
        accountOverviewState(complete: false),
      );
      await finance.pumpFinance(
        tester,
        controller,
        scopeId: 'project',
        content: (context, ref, state) => TextButton(
          onPressed: () =>
              showSharedFinanceAccountOverview(context, state, 'org', 'bank'),
          child: const Text('Open overview'),
        ),
      );
      await tester.tap(find.text('Open overview'));
      await tester.pumpAndSettle();
      final ledger = tester.widget<SharedFinanceLedger>(
        find.byType(SharedFinanceLedger),
      );
      expect(ledger.cashAvailable, isFalse);
      expect(
        find.textContaining('Pregled projektnih financ še ni popoln'),
        findsOneWidget,
      );
      expect(find.textContaining('987.66'), findsNothing);
      expect(find.textContaining('1000.00'), findsNothing);
      expect(find.text('test fin 25'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'open account overview removes data on parent access loss and account switch',
    (tester) async {
      final controller = finance.FinanceController(accountOverviewState());
      await finance.pumpFinance(
        tester,
        controller,
        scopeId: 'project',
        content: (context, ref, state) => TextButton(
          onPressed: () =>
              showSharedFinanceAccountOverview(context, state, 'org', 'bank'),
          child: const Text('Open overview'),
        ),
      );
      await tester.tap(find.text('Open overview'));
      await tester.pumpAndSettle();
      expect(find.text('test fin 25'), findsOneWidget);
      controller.replace(finance.fixture(projectOnly: true));
      await tester.pumpAndSettle();
      expect(find.byType(SharedFinanceLedger), findsNothing);
      expect(find.text('test fin 25'), findsNothing);
      expect(find.text('racunqa25'), findsNothing);
      controller.switchAccount();
      await tester.pumpAndSettle();
      expect(find.byType(SharedFinanceLedger), findsNothing);
      expect(find.text('test fin 25'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'sanitized project account does not offer or authorize parent overview',
    (tester) async {
      final state = finance.fixture(projectOnly: true);
      final controller = finance.FinanceController(state);
      await finance.pumpFinance(tester, controller, scopeId: 'project');
      await tester.ensureVisible(find.text('Računi prostora'));
      await tester.tap(find.text('Računi prostora'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('space-finance-choice-bank')),
        findsOneWidget,
      );
      expect(find.text('Pregled računa'), findsNothing);
      expect(
        find.byKey(const ValueKey('space-finance-overview-bank')),
        findsNothing,
      );
      final context = tester.element(
        find.byKey(const ValueKey('space-finance-choice-bank')),
      );
      showSharedFinanceAccountOverview(context, state, 'org', 'bank');
      await tester.pumpAndSettle();
      expect(find.byType(SharedFinanceLedger), findsNothing);
      expect(find.text('TriparNA'), findsNothing);
      expect(find.textContaining('1000.00'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
