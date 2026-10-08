import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/l10n/app_localizations.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'package:kanban/organizer/presentation/finance/finance_plan_wizard.dart';
import 'package:kanban/organizer/presentation/finance/finance_planning_panel.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';
import 'package:kanban/organizer/state/organizer_provider.dart';
import 'sharing_ui_fixture.dart';
import 'organizer_ui_test.dart' show MemoryOrganizerStorage;

Future<void> pumpFinance(
  WidgetTester tester,
  Widget child, {
  double width = 390,
  double height = 1000,
  double keyboard = 0,
  TextScaler textScaler = TextScaler.noScaling,
  String language = 'sl',
  bool dark = false,
  OrganizerSnapshot? snapshot,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
  addTearDown(tester.view.resetViewInsets);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final storage = MemoryOrganizerStorage();
  if (snapshot != null) storage.snapshot = snapshot;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        collaborationProvider.overrideWith(
          () => SharingUiController(initial: CollaborationState()),
        ),
        organizerStorageProvider.overrideWithValue(() => Future.value(storage)),
        organizerReminderSchedulerProvider.overrideWithValue((_) => (() {})),
      ],
      child: MaterialApp(
        locale: Locale(language),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: textScaler),
          child: child!,
        ),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder field(String prefix) => find.byWidgetPredicate(
  (w) =>
      w is TextFormField &&
      w.key is ValueKey<String> &&
      (w.key as ValueKey<String>).value.startsWith(prefix),
);
Future<void> fillDraft(
  WidgetTester tester,
  String amount, {
  String? title,
}) async {
  if (title != null) {
    await tester.ensureVisible(field('plan-title-').last);
    await tester.enterText(field('plan-title-').last, title);
  }
  await tester.ensureVisible(field('plan-amount-').last);
  await tester.enterText(field('plan-amount-').last, amount);
  final calendar = find
      .widgetWithIcon(OutlinedButton, Icons.calendar_month_outlined)
      .last;
  await tester.ensureVisible(calendar);
  await tester.tap(calendar);
  await tester.pumpAndSettle();
  await tester.tap(find.text('15').last);
  await tester.pumpAndSettle();
  final localizations = MaterialLocalizations.of(
    tester.element(find.byType(DatePickerDialog)),
  );
  await tester.tap(
    find.widgetWithText(TextButton, localizations.okButtonLabel),
  );
  await tester.pumpAndSettle();
}

Future<void> next(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const ValueKey('finance-plan-next')));
  await tester.tap(find.byKey(const ValueKey('finance-plan-next')));
  await tester.pumpAndSettle();
}

void main() {
  for (final width in [390.0, 1440.0]) {
    for (final language in ['sl', 'en']) {
      testWidgets(
        'all five wizard questions create distinct estimates $width $language',
        (tester) async {
          List<FinanceRecurrenceRule>? saved;
          List<LocalFinanceAccount>? accounts;
          await pumpFinance(
            tester,
            Builder(
              builder: (context) => TextButton(
                onPressed: () => showFinancePlanWizard(
                  context,
                  snapshot: OrganizerSnapshot(),
                  scopeDescription: AppLocalizations.of(
                    context,
                  )!.financePlanLocal,
                  wrap: (w) => w,
                  onSave: (a, r) async {
                    accounts = a;
                    saved = r;
                  },
                ),
                child: const Text('Open'),
              ),
            ),
            width: width,
            language: language,
            dark: language == 'en',
          );
          await tester.tap(find.text('Open'));
          await tester.pumpAndSettle();
          // Salary, loan, card have separate required estimates, no prefilled money.
          for (final amount in ['1234,56', '300.00', '240.50']) {
            await tester.tap(find.byType(SwitchListTile).first);
            await tester.pumpAndSettle();
            expect(
              tester
                  .widget<TextFormField>(field('plan-amount-').last)
                  .controller!
                  .text,
              isEmpty,
            );
            await fillDraft(tester, amount);
            await next(tester);
          }
          for (final isIncome in [true, false]) {
            final label = language == 'sl'
                ? (isIncome ? 'Dodaj priliv' : 'Dodaj strošek')
                : (isIncome ? 'Add income' : 'Add expense');
            for (var i = 0; i < 2; i++) {
              await tester.ensureVisible(
                find.widgetWithText(OutlinedButton, label),
              );
              await tester.tap(find.widgetWithText(OutlinedButton, label));
              await tester.pumpAndSettle();
              await fillDraft(tester, '10.20', title: 'Actual user label $i');
            }
            await next(tester);
          }
          expect(saved, isNull);
          await next(tester);
          expect(find.byType(FinancePlanWizard), findsNothing);
          expect(saved, hasLength(7));
          expect(accounts, isEmpty);
          expect(
            saved!.where((r) => r.kind == FinanceRecurrenceKind.salary),
            hasLength(1),
          );
          expect(
            saved!.where((r) => r.kind == FinanceRecurrenceKind.income),
            hasLength(2),
          );
          expect(
            saved!.where((r) => r.kind == FinanceRecurrenceKind.expense),
            hasLength(2),
          );
          expect(saved!.first.estimatedAmountMinor, 123456);
          expect(saved!.every((r) => !r.remindersEnabled), true);
          expect(tester.takeException(), null);
        },
      );
    }
  }
  testWidgets(
    'blank card estimate prevents progression and does not invent a zero amount',
    (tester) async {
      int saves = 0;
      await pumpFinance(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showFinancePlanWizard(
              context,
              snapshot: OrganizerSnapshot(),
              scopeDescription: 'Local',
              wrap: (w) => w,
              onSave: (a, r) async {
                saves++;
              },
            ),
            child: const Text('Open'),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await next(tester);
      await next(tester);
      await tester.tap(find.byType(SwitchListTile).first);
      await tester.pumpAndSettle();
      await next(tester);
      expect(find.text('Ali imaš kartico z odloženim plačilom?'), findsWidgets);
      expect(saves, 0);
      expect(
        tester
            .widget<TextFormField>(field('plan-amount-').last)
            .controller!
            .text,
        isEmpty,
      );
    },
  );
  testWidgets(
    'forecast exposes exact BigInt balance beyond JavaScript safe integer',
    (tester) async {
      final now = DateTime.now().toUtc();
      final account = LocalFinanceAccount(
        id: 'account',
        name: 'User ledger',
        currency: 'EUR',
        openingBalanceMinor: 9000000000000,
        openingBalanceAt: DateTime.utc(2020),
        createdAt: now,
        updatedAt: now,
      );
      final snapshot = OrganizerSnapshot(
        financeAccounts: [account],
        financeEntries: [
          for (var i = 0; i < 1000; i++)
            FinanceEntry(
              id: 'entry-$i',
              title: 'User entry $i',
              amountMinor: 9000000000000,
              currency: 'EUR',
              kind: FinanceEntryKind.income,
              occurredAt: now,
              ledgerAccountId: account.id,
              projectId: null,
              notes: '',
              createdAt: now,
              updatedAt: now,
            ),
        ],
      );
      await pumpFinance(
        tester,
        FinancePlanningPanel(snapshot: snapshot),
        width: 1440,
        snapshot: snapshot,
      );
      final accountPicker = find.byWidgetPredicate(
        (w) =>
            w is DropdownButtonFormField<String> &&
            w.decoration.labelText == 'Finančni račun',
      );
      await tester.ensureVisible(accountPicker);
      await tester.tap(accountPicker);
      await tester.pumpAndSettle();
      await tester.tap(find.text('User ledger · EUR').last);
      await tester.pumpAndSettle();
      expect(find.text('90090000000000.00 EUR'), findsWidgets);
      expect(tester.takeException(), null);
    },
  );
  testWidgets(
    'small keyboard viewport preserves enlarged text, fields and save controls',
    (tester) async {
      await pumpFinance(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showFinancePlanWizard(
              context,
              snapshot: OrganizerSnapshot(),
              scopeDescription: AppLocalizations.of(context)!.financePlanLocal,
              wrap: (w) => w,
              onSave: (a, r) async {},
            ),
            child: const Text('Open'),
          ),
        ),
        width: 320,
        height: 720,
        keyboard: 300,
        textScaler: const TextScaler.linear(2),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(SwitchListTile).first);
      await tester.tap(find.byType(SwitchListTile).first);
      await tester.pumpAndSettle();
      await tester.ensureVisible(field('plan-amount-').last);
      await tester.enterText(field('plan-amount-').last, '123.45');
      await tester.pumpAndSettle();
      expect(tester.takeException(), null);
      final nextButton = find.byKey(const ValueKey('finance-plan-next'));
      expect(tester.getRect(nextButton).bottom, lessThanOrEqualTo(420));
      expect(find.text('Okvirni znesek'), findsWidgets);
      await tester.ensureVisible(
        find.widgetWithIcon(OutlinedButton, Icons.calendar_month_outlined).last,
      );
      expect(tester.takeException(), null);
    },
  );
}
