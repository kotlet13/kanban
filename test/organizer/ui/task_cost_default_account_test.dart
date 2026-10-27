import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/l10n/app_localizations.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'package:kanban/organizer/presentation/organizer_editors.dart';

LocalFinanceAccount account(
  String id, {
  String currency = 'EUR',
  bool archived = false,
}) => LocalFinanceAccount(
  id: id,
  name: id,
  currency: currency,
  archived: archived,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

Future<void> open(
  WidgetTester tester,
  OrganizerDraft draft, {
  List<LocalFinanceAccount> accounts = const [],
  OrganizerEditorUpdates? updates,
  Set<String>? localIds,
  Future<void> Function(OrganizerDraft)? onSave,
}) async {
  tester.view.physicalSize = const Size(440, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showOrganizerEditor(
              context,
              heading: 'Task',
              kind: OrganizerEditorKind.task,
              draft: draft,
              financeAccounts: accounts,
              updates: updates,
              localRecordIds: localIds,
              costEditingEnabled: true,
              costAccountRequired: true,
              onSave: onSave ?? (_) async {},
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

Future<void> enableCost(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Task cost'));
  await tester.tap(find.text('Task cost'));
  await tester.pumpAndSettle();
  final toggle = find.byType(SwitchListTile).last;
  await tester.ensureVisible(toggle);
  await tester.tap(toggle);
  await tester.pumpAndSettle();
}

DropdownButtonFormField<String> accountField(WidgetTester tester) => tester
    .widgetList<DropdownButtonFormField<String>>(
      find.byType(DropdownButtonFormField<String>),
    )
    .firstWhere((w) => w.key.toString().contains('task-cost-account-'));

void main() {
  testWidgets(
    'defaulted new cost survives review of independent remote task title',
    (tester) async {
      final updates = OrganizerEditorUpdates()
        ..costEditingEnabled = true
        ..isCurrent = () => true;
      final draft = OrganizerDraft(title: 'Original');
      OrganizerDraft? saved;
      var accepted = 0;
      await open(
        tester,
        draft,
        accounts: [account('own')],
        updates: updates,
        onSave: (d) async => saved = d,
      );
      await enableCost(tester);
      await tester.ensureVisible(
        find.byKey(const ValueKey('task-cost-amount')),
      );
      await tester.enterText(
        find.byKey(const ValueKey('task-cost-amount')),
        '15.20',
      );
      updates.replaceDraft(
        OrganizerDraft(title: 'Remote title'),
        () => accepted++,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('organizer-save')));
      await tester.pumpAndSettle();
      expect(find.text('Review task changes'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('draft-apply-review')));
      await tester.pumpAndSettle();
      expect(accepted, 1);
      await tester.tap(find.byKey(const ValueKey('organizer-save')));
      await tester.pumpAndSettle();
      expect(saved?.title, 'Remote title');
      expect(saved?.ledgerAccountId, 'own');
      expect(saved?.costAmount, '15.20');
      expect(saved?.costEnabled, true);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'read-only cost and explicitly selected currency cannot be overridden by late choices',
    (tester) async {
      final updates = OrganizerEditorUpdates()..costEditingEnabled = true;
      final draft = OrganizerDraft(title: 'Currency choice');
      await open(tester, draft, updates: updates);
      await enableCost(tester);
      final currency = find.byKey(const ValueKey('task-cost-currency-EUR'));
      await tester.ensureVisible(currency);
      await tester.tap(currency);
      await tester.pumpAndSettle();
      await tester.tap(find.text('GBP').last);
      await tester.pumpAndSettle();
      updates.financeAccountChoices = {
        'parent:usd': (
          name: 'Dollar account',
          currency: 'USD',
          archived: false,
        ),
      };
      updates.financeChanged();
      await tester.pumpAndSettle();
      expect(draft.costCurrency, 'GBP');
      expect(draft.ledgerAccountId, isNull);
      updates.costEditingEnabled = false;
      updates.financeAccountChoices = {
        'parent:gbp': (name: 'Pound account', currency: 'GBP', archived: false),
      };
      updates.financeChanged();
      await tester.pumpAndSettle();
      expect(draft.ledgerAccountId, isNull);
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is DropdownButtonFormField<String> &&
              w.key.toString().contains('task-cost-account-'),
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'late sole USD parent updates both visible currency and account',
    (tester) async {
      final updates = OrganizerEditorUpdates()..costEditingEnabled = true;
      final draft = OrganizerDraft(title: 'USD cost');
      await open(tester, draft, updates: updates);
      await enableCost(tester);
      expect(
        find.byKey(const ValueKey('task-cost-currency-EUR')),
        findsOneWidget,
      );
      updates.financeAccountChoices = {
        'parent:usd': (
          name: 'Dollar account',
          currency: 'USD',
          archived: false,
        ),
      };
      updates.financeChanged();
      await tester.pumpAndSettle();
      final field = tester.widget<DropdownButtonFormField<String>>(
        find.byKey(const ValueKey('task-cost-currency-USD')),
      );
      expect(field.initialValue, 'USD');
      expect(draft.costCurrency, 'USD');
      expect(accountField(tester).initialValue, 'parent:usd');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'sole household account is selected and saved without opening dropdown',
    (tester) async {
      final draft = OrganizerDraft(title: 'New cost');
      OrganizerDraft? saved;
      await open(
        tester,
        draft,
        accounts: [account('household')],
        onSave: (d) async => saved = d,
      );
      await enableCost(tester);
      expect(accountField(tester).initialValue, 'household');
      await tester.ensureVisible(
        find.byKey(const ValueKey('task-cost-amount')),
      );
      await tester.enterText(
        find.byKey(const ValueKey('task-cost-amount')),
        '12.34',
      );
      await tester.tap(find.byKey(const ValueKey('organizer-save')));
      await tester.pumpAndSettle();
      expect(saved?.ledgerAccountId, 'household');
      expect(saved?.costAmount, '12.34');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'project account wins over parent and manual selection survives refresh',
    (tester) async {
      final updates = OrganizerEditorUpdates()
        ..costEditingEnabled = true
        ..financeAccountChoices = {
          'parent:p': (name: 'Parent', currency: 'EUR', archived: false),
        };
      final draft = OrganizerDraft(title: 'Project cost');
      await open(
        tester,
        draft,
        accounts: [account('project')],
        updates: updates,
      );
      await enableCost(tester);
      expect(accountField(tester).initialValue, 'project');
      final field = find.byKey(accountField(tester).key!);
      await tester.ensureVisible(field);
      await tester.tap(field);
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Parent ·').last);
      await tester.pumpAndSettle();
      updates.financeChanged();
      await tester.pumpAndSettle();
      expect(draft.ledgerAccountId, 'parent:p');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'parent default waits for loaded permitted choices and updates visible dropdown',
    (tester) async {
      final updates = OrganizerEditorUpdates()..costEditingEnabled = true;
      final draft = OrganizerDraft(title: 'Parent cost');
      await open(tester, draft, updates: updates);
      await enableCost(tester);
      expect(accountField(tester).initialValue, isNull);
      updates.financeAccountChoices = {
        'parent:p': (name: 'Parent', currency: 'EUR', archived: false),
      };
      updates.financeChanged();
      await tester.pumpAndSettle();
      expect(accountField(tester).initialValue, 'parent:p');
      expect(draft.ledgerAccountId, 'parent:p');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('ambiguous project accounts do not default to parent', (
    tester,
  ) async {
    final updates = OrganizerEditorUpdates()
      ..costEditingEnabled = true
      ..financeAccountChoices = {
        'parent:p': (name: 'Parent', currency: 'EUR', archived: false),
      };
    final draft = OrganizerDraft(title: 'Choose');
    await open(
      tester,
      draft,
      accounts: [account('one'), account('two')],
      updates: updates,
    );
    await enableCost(tester);
    expect(accountField(tester).initialValue, isNull);
    expect(draft.ledgerAccountId, isNull);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'archived and foreign ownership accounts excluded and fresh sole currency adopted',
    (tester) async {
      final draft = OrganizerDraft(title: 'Local cost');
      await open(
        tester,
        draft,
        accounts: [
          account('old', archived: true),
          account('foreign'),
          account('usd', currency: 'USD'),
        ],
        localIds: {'old', 'usd'},
      );
      await enableCost(tester);
      expect(draft.ledgerAccountId, 'usd');
      expect(draft.costCurrency, 'USD');
      expect(accountField(tester).initialValue, 'usd');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'stored unassigned cost is never rewritten just by opening editor',
    (tester) async {
      final draft = OrganizerDraft(
        title: 'Existing',
        costEnabled: true,
        costAmount: '8.00',
      );
      await open(tester, draft, accounts: [account('only')]);
      expect(draft.ledgerAccountId, isNull);
      expect(accountField(tester).initialValue, isNull);
      expect(tester.takeException(), isNull);
    },
  );
}
