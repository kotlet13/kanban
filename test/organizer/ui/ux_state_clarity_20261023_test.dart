import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/l10n/app_localizations.dart';
import 'package:kanban/organizer/data/e2ee/crypto_migration_coordinator.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'package:kanban/organizer/presentation/finance/finance_planning_panel.dart';
import 'package:kanban/organizer/presentation/finance/shared_finance_ledger.dart';
import 'package:kanban/organizer/presentation/organizer_widgets.dart';
import 'package:kanban/organizer/presentation/recovery/crypto_migration_wizard.dart';

import 'finance_planning_ui_test.dart' show pumpFinance;

class _ReviewController implements CryptoMigrationController {
  _ReviewController(this.committed);
  final bool committed;
  final events = StreamController<CryptoMigrationState>.broadcast();
  @override
  Stream<CryptoMigrationState> get changes => events.stream;
  @override
  Future<List<CryptoMigrationCandidate>> discoverAvailable() async => [
    const CryptoMigrationCandidate(
      scopeId: '11111111-1111-4111-8111-111111111111',
      kind: 'household',
      role: 'owner',
      accessRevision: 0,
    ),
  ];
  @override
  Future<CryptoMigrationState> inspect(String scopeId) async =>
      CryptoMigrationState(
        scopeId: scopeId,
        phase: committed
            ? CryptoMigrationPhase.committed
            : CryptoMigrationPhase.waitingContributors,
      );
  @override
  Future<void> close() => events.close();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _app(Widget child, String language) => ProviderScope(
  child: MaterialApp(
    locale: Locale(language),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: child,
  ),
);

void main() {
  for (final language in ['en', 'sl']) {
    for (final width in [390.0, 1280.0]) {
      testWidgets(
        'protection review $language $width distinguishes preparation from final check',
        (tester) async {
          tester.view.physicalSize = Size(width, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          for (final committed in [false, true]) {
            var finishes = 0;
            await tester.pumpWidget(
              _app(
                CryptoMigrationWizard(
                  key: ValueKey(committed),
                  controller: _ReviewController(committed),
                  onFinished: () async {
                    finishes++;
                    return false;
                  },
                ),
                language,
              ),
            );
            await tester.pumpAndSettle();
            final context = tester.element(find.byType(CryptoMigrationWizard));
            final l = AppLocalizations.of(context)!;
            expect(find.text(l.cryptoConnectionPending), findsNothing);
            expect(find.text(l.cryptoMigrationLocalAvailable), findsNothing);
            expect(
              find.text(
                committed
                    ? l.cryptoMigrationReviewReady
                    : l.cryptoMigrationReviewDescription,
              ),
              findsOneWidget,
            );
            expect(
              find.text(l.cryptoMigrationFinishReview),
              committed ? findsOneWidget : findsNothing,
            );
            if (committed) {
              await tester.tap(find.text(l.cryptoMigrationFinishReview));
              await tester.pumpAndSettle();
              expect(finishes, 1);
              expect(find.byType(CryptoMigrationWizard), findsOneWidget);
            }
            expect(tester.takeException(), isNull);
          }
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
    testWidgets(
      'unavailable account list $language does not claim verified emptiness',
      (tester) async {
        Widget ledger(bool available) => SharedFinanceLedger(
          key: ValueKey(available),
          scopeName: 'Project',
          accounts: const [],
          entries: const [],
          transfers: const [],
          people: const [],
          canWrite: false,
          accountsAvailable: available,
          onAccount: (_) {},
          onEntry: (_) {},
          onTransfer: (_) {},
          onAudit: (_) {},
        );
        for (final available in [false, true]) {
          await tester.pumpWidget(
            _app(
              Scaffold(body: SingleChildScrollView(child: ledger(available))),
              language,
            ),
          );
          final l = AppLocalizations.of(
            tester.element(find.byType(SharedFinanceLedger)),
          )!;
          expect(
            find.text(l.financeNoAccounts),
            available ? findsOneWidget : findsNothing,
          );
          expect(tester.takeException(), isNull);
        }
      },
    );
    testWidgets(
      'all-account forecast $language explains excluded opening balances',
      (tester) async {
        final now = DateTime.utc(2026, 10, 23);
        final snapshot = OrganizerSnapshot(
          financeAccounts: [
            LocalFinanceAccount(
              id: 'account',
              name: 'Cash',
              currency: 'EUR',
              openingBalanceMinor: 10000,
              openingBalanceAt: now,
              createdAt: now,
              updatedAt: now,
            ),
          ],
        );
        await pumpFinance(
          tester,
          FinancePlanningPanel(snapshot: snapshot),
          language: language,
          snapshot: snapshot,
        );
        final l = AppLocalizations.of(
          tester.element(find.byType(FinancePlanningPanel)),
        )!;
        expect(find.text(l.financePlanAllAccountsNetChange), findsOneWidget);
        expect(find.text(l.financePlanNoOpening), findsNothing);
        expect(
          find.textContaining('${l.financePlanOpeningBalanceLabel}:'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
    testWidgets(
      'standalone local household task $language does not imply personal storage',
      (tester) async {
        final now = DateTime.utc(2026, 10, 23);
        final task = LocalTask(
          id: 'task',
          title: 'Task',
          notes: '',
          projectId: null,
          dueAt: null,
          isCompleted: false,
          createdAt: now,
          updatedAt: now,
        );
        await tester.pumpWidget(
          _app(
            Scaffold(
              body: OrganizerTaskRow(
                task: task,
                snapshot: OrganizerSnapshot(workspaceKey: 'household'),
                onEdit: null,
                onCompleted: null,
              ),
            ),
            language,
          ),
        );
        final l = AppLocalizations.of(
          tester.element(find.byType(OrganizerTaskRow)),
        )!;
        expect(find.text(l.organizerNoProject), findsOneWidget);
        expect(find.text(l.organizerPersonal), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
