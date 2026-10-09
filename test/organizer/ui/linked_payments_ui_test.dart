import 'package:kanban/organizer/platform/backup_preferences_replay.dart';
import 'package:kanban/organizer/platform/invitation_links/invitation_link_providers.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kanban/app.dart';
import 'package:kanban/app_router.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/local_spaces_repository.dart';
import 'package:kanban/organizer/data/linked_payments_repository.dart';
import 'package:kanban/organizer/data/organizer_repository.dart';
import 'package:kanban/organizer/data/sqlite_organizer_storage.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'package:kanban/organizer/domain/finance_forecast.dart';
import 'package:kanban/organizer/presentation/all_spaces/all_spaces_payments.dart';
import 'package:kanban/organizer/presentation/finance/payment_presentation.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';
import 'package:kanban/organizer/state/linked_payments_provider.dart';
import 'package:kanban/organizer/state/local_spaces_provider.dart';
import 'package:kanban/organizer/state/local_database_provider.dart';
import 'package:kanban/organizer/state/organizer_provider.dart';
import 'package:kanban/organizer/state/portable_backup_provider.dart';
import 'package:kanban/organizer/platform/notification_providers.dart';
import 'organizer_ui_test.dart' show mobileTab;
import 'sharing_ui_fixture.dart';
import 'backup_ui_fixture.dart';
import 'local_spaces_navigation_test.dart' show loadCaptureFonts;
import '../platform/local_notification_adapter_test.dart' as scheduler;

const cardId = '10000000-0000-4000-8000-000000000001';
const bankId = '10000000-0000-4000-8000-000000000002';
const expenseId = '10000000-0000-4000-8000-000000000003';
const projectId = '10000000-0000-4000-8000-000000000004';

class Fixture {
  Fixture(this.db, this.org, this.home);
  final CollaborationDatabase db;
  final LocalSpace org, home;
  late final payments = LinkedPaymentsRepository(db);
}

Future<Fixture> setup(WidgetTester tester) async =>
    (await tester.runAsync(() async {
      final db = CollaborationDatabase(NativeDatabase.memory());
      final personal = OrganizerRepository(SqliteOrganizerStorage(db));
      await personal.initialize();
      final now = DateTime.now().toUtc().subtract(const Duration(days: 1));
      await personal.saveFinancePlan(
        accounts: [
          LocalFinanceAccount(
            id: cardId,
            name: 'QA osebna kartica',
            currency: 'EUR',
            openingBalanceMinor: 10000,
            openingBalanceAt: now,
            createdAt: now,
            updatedAt: now,
          ),
        ],
        rules: [],
        expectedRevision: personal.snapshot.revision,
        expectedWorkspaceKey: 'local',
      );
      final spaces = LocalSpacesRepository(db);
      final org = await spaces.createSpace(
        kind: LocalSpaceKind.organization,
        name: 'QA TriparNA',
      );
      final home = await spaces.createSpace(
        kind: LocalSpaceKind.household,
        name: 'QA gospodinjstvo',
      );
      var sequence = 0;
      final repository = OrganizerRepository(
        SqliteOrganizerStorage(db, workspaceId: org.id),
        idGenerator: () => sequence++ == 0 ? projectId : expenseId,
      );
      await repository.initialize();
      await repository.saveFinancePlan(
        accounts: [
          LocalFinanceAccount(
            id: bankId,
            name: 'QA račun organizacije',
            currency: 'EUR',
            openingBalanceMinor: 0,
            openingBalanceAt: now,
            createdAt: now,
            updatedAt: now,
          ),
        ],
        rules: [],
        expectedRevision: repository.snapshot.revision,
        expectedWorkspaceKey: org.id,
      );
      await repository.createProject(title: 'QA spletna stran');
      await repository.createFinanceEntry(
        title: 'QA domena',
        amountMinor: 3000,
        kind: FinanceEntryKind.expense,
        occurredAt: DateTime.now().toUtc(),
        projectId: projectId,
        ledgerAccountId: bankId,
      );
      await spaces.selectSpace(org.id);
      await personal.close();
      await repository.close();
      return Fixture(db, org, home);
    }))!;
Future<void> capture(WidgetTester tester, GlobalKey key, String name) async {
  if (Platform.environment['JIVIE_UI_CAPTURE'] != '1') return;
  await tester.pumpAndSettle();
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('build/qa/spaces-next-ui/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

Future<void> dropdown(WidgetTester tester, String key, String choice) async {
  await tester.ensureVisible(find.byKey(ValueKey(key)));
  await tester.tap(find.byKey(ValueKey(key)));
  await tester.pumpAndSettle();
  await tester.tap(find.textContaining(choice).last);
  await tester.pumpAndSettle();
}

PaymentEvent event({int revision = 1, int refund = 0}) => PaymentEvent(
  eventId: expenseId,
  sourceScopeId: bankId,
  sourceEntryId: projectId,
  sourceRevision: 1,
  payerAccountId: cardId,
  amountMinor: 3000,
  currency: 'EUR',
  paidAt: DateTime.utc(2026, 10, 9),
  expectReimbursement: true,
  revision: revision,
  reimbursements: refund == 0
      ? []
      : [
          PaymentReimbursement(
            legId: projectId,
            amountMinor: refund,
            paidAt: DateTime.utc(2026, 10, 10),
            approvedByAccountId: cardId,
          ),
        ],
);
void main() {
  test(
    'Vsi chooses newest receipt revision and counts personal/household once',
    () {
      final merged = mergeVisiblePayments([
        (
          payments: PaymentSnapshot(
            fresh: true,
            projections: [
              PaymentProjection(
                event: event(),
                state: PaymentProjectionState.complete,
              ),
            ],
          ),
          name: 'QA dom',
          source: null,
        ),
        (
          payments: PaymentSnapshot(
            fresh: true,
            projections: [
              PaymentProjection(
                event: event(revision: 2, refund: 1000),
                state: PaymentProjectionState.complete,
              ),
            ],
          ),
          name: 'QA osebno',
          source: null,
        ),
        (
          payments: PaymentSnapshot(
            fresh: true,
            events: [event(revision: 3, refund: 3000)],
          ),
          name: 'QA organizacija',
          source: null,
        ),
      ]);
      expect(merged.receipts, hasLength(1));
      expect(merged.receipts.single.event.revision, 3);
      expect(merged.totals.receivableByCurrency['EUR'], BigInt.zero);
      expect(merged.receipts.single.name, 'QA organizacija');
      final removed = mergeVisiblePayments([
        (
          payments: PaymentSnapshot(
            fresh: false,
            projections: [
              PaymentProjection(
                event: event(),
                state: PaymentProjectionState.complete,
              ),
            ],
          ),
          name: 'QA dom',
          source: null,
        ),
        (
          payments: PaymentSnapshot(
            fresh: true,
            projections: [
              PaymentProjection(
                event: event(),
                state: PaymentProjectionState.sourceRemoved,
              ),
            ],
          ),
          name: 'QA osebno',
          source: null,
        ),
      ]);
      expect(removed.incomplete, isTrue);
      expect(
        removed.receipts.single.projection!.state,
        PaymentProjectionState.sourceRemoved,
      );
      expect(removed.totals.receivableByCurrency['EUR'], BigInt.zero);
    },
  );
  test(
    'private cash account mapping affects presentation forecast while canonical IDs stay unchanged',
    () {
      final shared = CollaborationState(
        session: sharingSession(),
        privateRecordIds: {bankId: cardId},
      );
      final now = DateTime.utc(2026, 10, 9);
      final personal = OrganizerSnapshot(
        workspaceKey: 'private:${sharingSession().partition}',
        financeAccounts: [
          LocalFinanceAccount(
            id: cardId,
            name: 'QA kartica',
            currency: 'EUR',
            openingBalanceMinor: 10000,
            openingBalanceAt: now.subtract(const Duration(days: 1)),
            createdAt: now,
            updatedAt: now,
          ),
        ],
      );
      final raw = PaymentSnapshot(
        fresh: true,
        cashMovements: [
          PaymentCashMovement(
            id: expenseId,
            accountId: bankId,
            amountMinor: -3000,
            currency: 'EUR',
            paidAt: now,
          ),
        ],
      );
      final mapped = paymentsForPersonalSnapshot(personal, shared, raw)!;
      expect(raw.cashMovements.single.accountId, bankId);
      expect(mapped.cashMovements.single.id, expenseId);
      expect(
        forecastFinance(
          personal,
          currency: 'EUR',
          through: now.add(const Duration(days: 1)),
          account: personal.financeAccounts.single,
          payments: mapped,
        ).endMinor,
        BigInt.from(7000),
      );
    },
  );
  testWidgets(
    'actual local expense personal card household and10/20 refunds update cash once',
    (tester) async {
      await loadCaptureFonts(tester);
      SharedPreferences.setMockInitialValues({
        'app_locale_code': 'sl',
        'app_theme_mode': 'light',
      });
      final fixture = await setup(tester), key = GlobalKey();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(fixture.db.close);
      });
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetViewInsets);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      appRouter.go('/');
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            backupPreferencesReplayProvider.overrideWith((ref) async => {}),
            invitationLinkSourceProvider.overrideWithValue(null),
            localDatabaseProvider.overrideWith((ref) async => fixture.db),
            organizerStorageProvider.overrideWithValue(
              () async => SqliteOrganizerStorage(fixture.db),
            ),
            collaborationProvider.overrideWith(
              () => SharingUiController(initial: CollaborationState()),
            ),
            linkedPaymentsRepositoryProvider.overrideWith(
              (ref) async => fixture.payments,
            ),
            portableBackupProvider.overrideWith(EmptyBackupUiController.new),
            localNotificationSchedulerProvider.overrideWithValue(
              scheduler.FakeScheduler(),
            ),
          ],
          child: RepaintBoundary(key: key, child: const KanbanApp()),
        ),
      );
      await tester.pumpAndSettle();
      await mobileTab(tester, 'Finance');
      final pay = find.byKey(const ValueKey('personal-payment-$expenseId'));
      await tester.ensureVisible(pay);
      await tester.tap(pay);
      await tester.pumpAndSettle();
      await dropdown(tester, 'sharing-personal-account', 'QA osebna kartica');
      await dropdown(tester, 'sharing-household', 'QA gospodinjstvo');
      await capture(tester, key, 'finance-payment-form-390');
      await tester.ensureVisible(find.byKey(const ValueKey('sharing-submit')));
      await tester.tap(find.byKey(const ValueKey('sharing-submit')));
      await tester.pumpAndSettle();
      var org = await tester.runAsync(
        () => fixture.payments.read(PaymentSpaceRef(fixture.org.id)),
      );
      expect(org!.events, hasLength(1));
      final eventId = org.events.single.eventId;
      expect(org.events.single.receivableMinor, 3000);
      Future<void> refund(String amount, {bool keyboard = false}) async {
        if (keyboard) {
          tester.view.physicalSize = const Size(320, 640);
          tester.platformDispatcher.textScaleFactorTestValue = 1.5;
          await tester.pumpAndSettle();
        }
        await tester.ensureVisible(
          find.byKey(ValueKey('refund-payment-$eventId')),
        );
        await tester.tap(find.byKey(ValueKey('refund-payment-$eventId')));
        await tester.pumpAndSettle();
        await dropdown(
          tester,
          'sharing-refund-account',
          'QA račun organizacije',
        );
        await tester.ensureVisible(
          find.byKey(const ValueKey('sharing-refund-amount')),
        );
        await tester.enterText(
          find.byKey(const ValueKey('sharing-refund-amount')),
          amount,
        );
        if (keyboard) {
          tester.view.viewInsets = const FakeViewPadding(bottom: 260);
          await tester.pumpAndSettle();
          await Scrollable.ensureVisible(
            tester.element(find.byKey(const ValueKey('sharing-refund-amount'))),
            alignment: .3,
          );
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('sharing-refund-amount')).hitTestable(),
            findsOneWidget,
          );
        }
        await tester.ensureVisible(
          find.byKey(const ValueKey('sharing-submit')),
        );
        if (keyboard) await capture(tester, key, 'finance-refund-keyboard-320');
        await tester.tap(find.byKey(const ValueKey('sharing-submit')));
        await tester.pumpAndSettle();
        if (keyboard) {
          tester.view.resetViewInsets();
          tester.platformDispatcher.clearTextScaleFactorTestValue();
          tester.view.physicalSize = const Size(390, 844);
          await tester.pumpAndSettle();
        }
      }

      final container = ProviderScope.containerOf(
        tester.element(find.byType(KanbanApp)),
      );
      Future<void> select(String id) async {
        await container.read(localSpacesProvider.notifier).selectSpace(id);
        await tester.pumpAndSettle();
      }

      await select('local');
      await dropdown(
        tester,
        'personal-finance-account-filter',
        'QA osebna kartica',
      );
      expect(find.text('70.00 EUR'), findsWidgets);
      await select(fixture.org.id);
      await refund('10');
      org = await tester.runAsync(
        () => fixture.payments.read(PaymentSpaceRef(fixture.org.id)),
      );
      expect(org!.events.single.receivableMinor, 2000);
      await select('local');
      await dropdown(
        tester,
        'personal-finance-account-filter',
        'QA osebna kartica',
      );
      expect(find.text('80.00 EUR'), findsWidgets);
      await select(fixture.org.id);
      for (final width in [320.0, 1280.0]) {
        tester.view.physicalSize = Size(width, width == 320 ? 640 : 900);
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(ValueKey('linked-payment-$eventId')),
        );
        await tester.pumpAndSettle();
        await capture(tester, key, 'finance-partial-refund-${width.toInt()}');
      }
      tester.view.physicalSize = const Size(390, 844);
      await tester.pumpAndSettle();
      await refund('20', keyboard: true);
      org = await tester.runAsync(
        () => fixture.payments.read(PaymentSpaceRef(fixture.org.id)),
      );
      expect(org!.events.single.receivableMinor, 0);
      expect(org.events.single.reimbursements, hasLength(2));
      await select('local');
      await dropdown(
        tester,
        'personal-finance-account-filter',
        'QA osebna kartica',
      );
      expect(find.text('100.00 EUR'), findsWidgets);
      final personal = await tester.runAsync(
        () => SqliteOrganizerStorage(fixture.db, workspaceId: 'local').read(),
      );
      final source = await tester.runAsync(
        () => SqliteOrganizerStorage(
          fixture.db,
          workspaceId: fixture.org.id,
        ).read(),
      );
      final household = await tester.runAsync(
        () => SqliteOrganizerStorage(
          fixture.db,
          workspaceId: fixture.home.id,
        ).read(),
      );
      expect(source!.financeEntries, hasLength(1));
      expect(source.financeEntries.single.amountMinor, 3000);
      expect(personal!.financeEntries, isEmpty);
      expect(household!.financeEntries, isEmpty);
      expect(
        (await tester.runAsync(
          () => fixture.payments.read(PaymentSpaceRef(fixture.home.id)),
        ))!.projections.single.receivableMinor,
        0,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
