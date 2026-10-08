import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/l10n/app_localizations.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'package:kanban/organizer/presentation/finance/finance_source_link.dart';
import 'package:kanban/organizer/state/organizer_provider.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';
import 'finance_pending_ledger_ui_test.dart' show pumpLedger;
import 'organizer_ui_test.dart' show MemoryOrganizerStorage;
import 'sharing_ui_fixture.dart';

class SourceController extends SharingUiController {
  SourceController(CollaborationState initial) : super(initial: initial);
  NotificationTarget? opened;
  @override
  Future<NotificationOpenResult> openNotificationTarget(
    NotificationTarget target,
  ) async {
    opened = target;
    return NotificationOpenResult(
      status: NotificationOpenStatus.available,
      target: target,
    );
  }
}

void main() {
  final now = DateTime.now().toUtc();
  LocalFinanceAccount account(String id) => LocalFinanceAccount(
    id: id,
    name: id,
    currency: 'EUR',
    openingBalanceMinor: 10000,
    openingBalanceAt: now,
    createdAt: now,
    updatedAt: now,
  );
  FinanceEntry entry(String id, {String? accountId}) => FinanceEntry(
    id: id,
    title: id,
    amountMinor: 2500,
    kind: FinanceEntryKind.expense,
    currency: 'EUR',
    occurredAt: now,
    projectId: null,
    notes: '',
    ledgerAccountId: accountId,
    createdAt: now,
    updatedAt: now,
  );
  for (final width in [390.0, 1280.0]) {
    testWidgets(
      'manual account selector persists bank and account/unassigned filters select exact entries $width',
      (tester) async {
        final store = MemoryOrganizerStorage()
          ..snapshot = OrganizerSnapshot(
            financeAccounts: [account('TRR')],
            financeEntries: [entry('Brez računa')],
          );
        await pumpLedger(
          tester,
          storage: () async => store,
          clock: now,
          width: width,
        );
        await tester.tap(find.text('Dodaj zapis').first);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('organizer-title-field')),
          'Material',
        );
        final amount = find.byKey(const ValueKey('personal-finance-amount'));
        await tester.ensureVisible(amount);
        await tester.enterText(amount, '25,00');
        final picker = find.byKey(const ValueKey('personal-finance-account'));
        await tester.ensureVisible(picker);
        await tester.pumpAndSettle();
        await tester.tap(picker);
        await tester.pumpAndSettle();
        await tester.tap(find.text('TRR · EUR').last);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('organizer-save')));
        await tester.pumpAndSettle();
        expect(
          store.snapshot.financeEntries
              .firstWhere((e) => e.title == 'Material')
              .ledgerAccountId,
          'TRR',
        );
        final filter = find.byKey(
          const ValueKey('personal-finance-account-filter'),
        );
        await tester.ensureVisible(filter);
        await tester.pumpAndSettle();
        await tester.tap(filter);
        await tester.pumpAndSettle();
        await tester.tap(find.text('TRR · EUR').last);
        await tester.pumpAndSettle();
        expect(find.text('Material'), findsOneWidget);
        expect(find.text('Brez računa'), findsNothing);
        await tester.ensureVisible(filter);
        await tester.pumpAndSettle();
        await tester.tap(filter);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Brez izbire računa').last);
        await tester.pumpAndSettle();
        expect(find.text('Material'), findsNothing);
        expect(find.text('Brez računa'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
    testWidgets(
      'linked personal cost opens its actual task and project $width',
      (tester) async {
        final task = LocalTask(
          id: 'task',
          title: 'Izmera',
          notes: 'Opis izvornega opravila',
          isCompleted: false,
          dueAt: null,
          projectId: 'project',
          createdAt: now,
          updatedAt: now,
        );
        final cost = entry(
          'Strošek izmere',
        ).copyWith(taskId: task.id, projectId: 'project');
        final store = MemoryOrganizerStorage()
          ..snapshot = OrganizerSnapshot(
            projects: [
              LocalProject(
                id: 'project',
                title: 'Prenova',
                description: '',
                createdAt: now,
                updatedAt: now,
              ),
            ],
            tasks: [task],
            financeEntries: [cost],
          );
        await pumpLedger(
          tester,
          storage: () async => store,
          clock: now,
          width: width,
        );
        final link = find.byKey(ValueKey('finance-source-${cost.id}'));
        await tester.ensureVisible(link);
        await tester.tap(link);
        await tester.pumpAndSettle();
        expect(find.text('Opis izvornega opravila'), findsOneWidget);
        expect(find.text('Izmera'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'shared source uses correct account/scope, and denied/missing source never exposes another scope',
    (tester) async {
      SharedFinanceEntry cost() => SharedFinanceEntry(
        id: 'cost',
        accountId: 'bank',
        taskId: 'task',
        title: 'Cost',
        kind: FinanceEntryKind.expense,
        currency: 'EUR',
        amountMinor: 10,
        occurredAt: now,
        createdAt: now,
        updatedAt: now,
      );
      CollaborationState shared({bool revoked = false, bool missing = false}) =>
          CollaborationState(
            session: sharingSession(),
            scopes: [sharingScope(revoked: revoked)],
            financeContractVersion: 2,
            financePolicies: {
              sharingScopeId: const SharedFinancePolicy(
                enabled: true,
                grant: SharedFinanceGrant.read,
              ),
            },
            financeSnapshotComplete: {sharingScopeId: true},
            data: {
              sharingScopeId: SharedScopeData(
                financeEntries: [cost()],
                tasks: missing ? [] : sharingData().tasks,
                projects: sharingData().projects,
              ),
            },
          );
      final controller = SourceController(shared());
      final store = MemoryOrganizerStorage();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            organizerStorageProvider.overrideWithValue(() async => store),
            organizerReminderSchedulerProvider.overrideWithValue(
              (_) => (() {}),
            ),
            collaborationProvider.overrideWith(() => controller),
          ],
          child: MaterialApp(
            locale: const Locale('sl'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: FinanceSourceLink(
                entryId: 'cost',
                scopeId: sharingScopeId,
                partition: sharingSession().partition,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Projekt: Skupni vrt'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('finance-source-cost')));
      await tester.pumpAndSettle();
      expect(controller.opened!.scopeId, sharingScopeId);
      expect(controller.opened!.accountId, sharingSession().accountId);
      expect(controller.opened!.records.single.recordId, 'task');
      await tester.tap(find.text('Zapri').last);
      await tester.pumpAndSettle();
      controller.replace(shared(missing: true));
      await tester.pumpAndSettle();
      expect(find.text('Povezano opravilo ni več na voljo.'), findsOneWidget);
      expect(find.byKey(const ValueKey('finance-source-cost')), findsNothing);
      controller.replace(shared(revoked: true));
      await tester.pumpAndSettle();
      expect(find.text('Povezano opravilo ni več na voljo.'), findsNothing);
      controller.switchAccount();
      await tester.pumpAndSettle();
      expect(find.textContaining('Pripravi zemljo'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
