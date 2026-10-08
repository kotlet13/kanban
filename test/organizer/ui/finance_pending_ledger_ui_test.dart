import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/l10n/app_localizations.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/organizer_repository.dart';
import 'package:kanban/organizer/data/organizer_storage.dart';
import 'package:kanban/organizer/data/sqlite_organizer_storage.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'package:kanban/organizer/presentation/finance_page.dart';
import 'package:kanban/organizer/presentation/finance/shared_finance_actions.dart';
import 'package:kanban/organizer/presentation/finance/finance_planning_panel.dart';
import 'package:kanban/organizer/domain/finance_forecast.dart';
import 'package:kanban/organizer/presentation/organizer_actions.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';
import 'package:kanban/organizer/state/organizer_provider.dart';
import 'organizer_ui_test.dart' show MemoryOrganizerStorage;
import 'sharing_ui_fixture.dart';

class _SharedConfirmationController extends SharingUiController {
  _SharedConfirmationController(CollaborationState initial)
    : super(initial: initial);
  SharedFinanceEntry? confirmed;
  int? amount;
  DateTime? paidAt;
  @override
  Future<void> confirmFinanceOccurrenceForScope(
    String scopeId,
    SharedFinanceEntry entry, {
    required int amountMinor,
    required DateTime paidAt,
  }) async {
    confirmed = entry;
    amount = amountMinor;
    this.paidAt = paidAt;
  }
}

Future<void> pumpLedger(
  WidgetTester tester, {
  required Future<OrganizerStorage> Function() storage,
  required DateTime clock,
  double width = 390,
}) async {
  tester.view.physicalSize = Size(width, 600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        organizerStorageProvider.overrideWithValue(storage),
        organizerClockProvider.overrideWithValue(() => clock),
        organizerReminderSchedulerProvider.overrideWithValue((_) => (() {})),
        collaborationProvider.overrideWith(
          () => SharingUiController(initial: CollaborationState()),
        ),
      ],
      child: MaterialApp(
        locale: const Locale('sl'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) {
              final snapshot = ref.watch(organizerProvider).valueOrNull;
              if (snapshot == null) return const SizedBox.shrink();
              return OrganizerFinancePage(
                snapshot: snapshot,
                actions: OrganizerActions(context, ref, snapshot),
              );
            },
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  for (final width in [390.0, 1280.0]) {
    testWidgets(
      'undated task cost and out-of-horizon planned entry remain accessible; payment persists same ID $width',
      (tester) async {
        final now = DateTime.now().toUtc();
        final fixture = (await tester.runAsync(() async {
          final db = CollaborationDatabase(NativeDatabase.memory());
          final storage = SqliteOrganizerStorage(db);
          await storage.initialize();
          final repo = OrganizerRepository(storage, clock: () => now);
          await repo.initialize();
          final task = LocalTask(
            id: newLocalId(),
            title: 'Izmera prostora',
            notes: '',
            isCompleted: false,
            projectId: null,
            dueAt: null,
            estimateMinutes: 60,
            createdAt: now,
            updatedAt: now,
          );
          await repo.saveTaskWithCost(
            task: task,
            isNew: true,
            cost: const TaskCostDraft(amountMinor: 2550),
            expectedWorkspaceKey: 'local',
          );
          final costId = repo.snapshot.financeEntries.single.id;
          final far = now.add(const Duration(days: 400));
          await repo.createFinanceEntry(
            title: 'Obveznost prihodnje leto',
            amountMinor: 5500,
            currency: 'EUR',
            kind: FinanceEntryKind.expense,
            occurredAt: far,
          );
          final future = repo.snapshot.financeEntries.singleWhere(
            (e) => e.id != costId,
          );
          await repo.updateFinanceEntry(
            future.copyWith(status: FinanceEntryStatus.planned, plannedAt: far),
          );
          await repo.close();
          return (db: db, storage: storage, costId: costId, task: task);
        }))!;
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.runAsync(fixture.db.close);
        });
        await pumpLedger(
          tester,
          storage: () async => fixture.storage,
          clock: now,
          width: width,
        );
        expect(find.text('Izmera prostora'), findsOneWidget);
        expect(find.text('Obveznost prihodnje leto'), findsOneWidget);
        expect(find.textContaining('Datum ni določen'), findsOneWidget);
        expect(
          find.text('Tvoj pregled se začne s prvim zapisom.'),
          findsNothing,
        );
        expect(find.text('Evidentirana neto sprememba'), findsNothing);
        final pending = find.byKey(
          ValueKey('planned-finance-${fixture.costId}'),
        );
        await tester.ensureVisible(pending);
        await tester.tap(pending);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('sharing-actual-amount')),
          findsOneWidget,
        );
        await tester.enterText(
          find.byKey(const ValueKey('sharing-actual-amount')),
          '27.40',
        );
        await tester.tap(find.byKey(const ValueKey('sharing-submit')));
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        final saved = (await tester.runAsync(fixture.storage.read))!;
        final paid = saved.financeEntries.singleWhere(
          (e) => e.id == fixture.costId,
        );
        expect(saved.financeEntries, hasLength(2));
        expect(paid.amountMinor, 2740);
        expect(paid.status, FinanceEntryStatus.posted);
        expect(paid.taskId, fixture.task.id);
        expect(paid.plannedAt, isNull);
        expect(paid.paidAt, now);
        expect(saved.tasks.single.dueAt, isNull);
        expect(saved.tasks.single.estimateMinutes, 60);
        expect(saved.tasks.single.revision, fixture.task.revision);
        expect(find.text('Izmera prostora'), findsOneWidget);
        expect(pending, findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await pumpLedger(
          tester,
          storage: () async => fixture.storage,
          clock: now,
          width: width,
        );
        expect(find.text('Izmera prostora'), findsOneWidget);
        expect(find.text('Obveznost prihodnje leto'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'shared undated task cost retains null forecast date and opens actual confirmation from ledger',
    (tester) async {
      final now = DateTime.now().toUtc();
      final entry = SharedFinanceEntry(
        id: 'cost',
        accountId: 'account',
        ledgerAccountId: 'account',
        kind: FinanceEntryKind.expense,
        status: SharedFinanceStatus.planned,
        taskId: 'task',
        amountMinor: 2550,
        currency: 'EUR',
        title: 'Skupna izmera prostora',
        occurredAt: now,
        createdAt: now,
        updatedAt: now,
      );
      final state = CollaborationState(
        session: sharingSession(),
        scopes: [sharingScope()],
        financeContractVersion: 2,
        financePolicies: {
          sharingScopeId: const SharedFinancePolicy(
            enabled: true,
            grant: SharedFinanceGrant.write,
          ),
        },
        financeSnapshotComplete: {sharingScopeId: true},
        data: {
          sharingScopeId: SharedScopeData(financeEntries: [entry]),
        },
      );
      final planning = sharedFinancePlanningSnapshot(state, sharingScopeId);
      expect(planning.financeEntries.single.plannedAt, isNull);
      final forecast = forecastFinance(
        planning,
        currency: 'EUR',
        through: now.add(const Duration(days: 120)),
      );
      expect(forecast.points, isEmpty);
      expect(forecast.undatedCount, 1);
      final controller = _SharedConfirmationController(state);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [collaborationProvider.overrideWith(() => controller)],
          child: MaterialApp(
            locale: const Locale('sl'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) {
                  final shared = ref.watch(collaborationProvider).valueOrNull;
                  if (shared == null) return const SizedBox.shrink();
                  return TextButton(
                    onPressed: () => SharedFinanceActions(
                      context,
                      ref,
                      sharingScope(),
                      shared,
                    ).entry(entry),
                    child: const Text('Edit ledger row'),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit ledger row'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('sharing-actual-amount')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('sharing-status')), findsNothing);
      await tester.enterText(
        find.byKey(const ValueKey('sharing-actual-amount')),
        '29.10',
      );
      await tester.tap(find.byKey(const ValueKey('sharing-submit')));
      await tester.pumpAndSettle();
      expect(controller.confirmed?.id, entry.id);
      expect(controller.confirmed?.taskId, entry.taskId);
      expect(controller.amount, 2910);
      expect(controller.paidAt, isNotNull);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'twelve planned salary occurrences replace the empty ledger and remain scrollable at 600px',
    (tester) async {
      final now = DateTime.now().toUtc();
      final storage = MemoryOrganizerStorage();
      final repo = OrganizerRepository(storage, clock: () => now);
      await repo.initialize();
      await repo.saveFinancePlan(
        accounts: [],
        rules: [
          FinanceRecurrenceRule(
            id: newLocalId(),
            title: 'Moja plača',
            kind: FinanceRecurrenceKind.salary,
            currency: 'EUR',
            estimatedAmountMinor: 100000,
            startYear: now.toLocal().year,
            startMonth: now.toLocal().month,
            monthDay: 10,
            createdAt: now,
            updatedAt: now,
          ),
        ],
        expectedRevision: 0,
        expectedWorkspaceKey: 'local',
      );
      await repo.close();
      await pumpLedger(tester, storage: () async => storage, clock: now);
      expect(find.text('Tvoj pregled se začne s prvim zapisom.'), findsNothing);
      expect(find.text('Nepotrjeni vnosi'), findsOneWidget);
      final last = find.byKey(
        ValueKey('planned-finance-${storage.snapshot.financeEntries.last.id}'),
      );
      await tester.ensureVisible(last);
      expect(last.hitTestable(), findsOneWidget);
      expect(storage.snapshot.financeEntries, hasLength(12));
      expect(
        storage.snapshot.financeEntries.every(
          (e) => e.status == FinanceEntryStatus.planned,
        ),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
