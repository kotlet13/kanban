import 'dart:convert';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kanban/l10n/app_localizations.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/organizer_repository.dart';
import 'package:kanban/organizer/data/sqlite_organizer_storage.dart';
import 'package:kanban/organizer/data/finance_inbox_store.dart';
import 'package:kanban/organizer/domain/finance_reminder_plans.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'package:kanban/organizer/presentation/inbox/inbox_page.dart';
import 'package:kanban/organizer/presentation/inbox/notification_target_view.dart';
import 'package:kanban/organizer/platform/local_notification_adapter.dart';
import 'package:kanban/organizer/state/local_database_provider.dart';
import 'package:kanban/organizer/state/organizer_provider.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';
import '../platform/local_notification_adapter_test.dart' show FakeScheduler;
import 'sharing_ui_fixture.dart';

Future<({CollaborationDatabase db, SqliteOrganizerStorage storage})>
seed() async {
  final db = CollaborationDatabase(NativeDatabase.memory());
  final storage = SqliteOrganizerStorage(db);
  await storage.initialize();
  final clock = DateTime(2026, 10, 8, 12);
  final repo = OrganizerRepository(storage, clock: () => clock);
  await repo.initialize();
  await repo.saveFinancePlan(
    accounts: [],
    rules: [
      FinanceRecurrenceRule(
        id: newLocalId(),
        title: 'Real user salary label',
        kind: FinanceRecurrenceKind.salary,
        currency: 'EUR',
        estimatedAmountMinor: 120000,
        startYear: 2026,
        startMonth: 10,
        monthDay: 31,
        remindersEnabled: true,
        createdAt: clock.toUtc(),
        updatedAt: clock.toUtc(),
      ),
    ],
    expectedRevision: 0,
    expectedWorkspaceKey: 'local',
  );
  await repo.close();
  return (db: db, storage: storage);
}

Future<void> pumpInbox(
  WidgetTester tester,
  CollaborationDatabase db,
  SqliteOrganizerStorage storage,
  DateTime Function() clock, {
  NotificationTarget? launch,
}) async {
  tester.view.physicalSize = const Size(390, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        collaborationProvider.overrideWith(
          () => SharingUiController(initial: CollaborationState()),
        ),
        localDatabaseProvider.overrideWith((ref) async => db),
        organizerStorageProvider.overrideWithValue(() => Future.value(storage)),
        organizerClockProvider.overrideWithValue(clock),
        organizerReminderSchedulerProvider.overrideWithValue((_) => (() {})),
      ],
      child: MaterialApp(
        locale: const Locale('sl'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: launch == null
                ? OrganizerInboxPage(onSettings: () {}, onAccount: () {})
                : Consumer(
                    builder: (context, ref, _) => TextButton(
                      onPressed: () =>
                          showNotificationTarget(context, ref, launch),
                      child: const Text('Open notification'),
                    ),
                  ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  testWidgets(
    'Friday read receipt survives rebuild; Monday remains one new unconfirmed question; confirmation books same entry',
    (tester) async {
      final fixture = (await tester.runAsync(seed))!;
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(fixture.db.close);
      });
      var now = DateTime(2026, 10, 30, 12);
      await pumpInbox(tester, fixture.db, fixture.storage, () => now);
      expect(find.text('Ali si že dobil plačo?'), findsOneWidget);
      await tester.tap(find.byTooltip('Označi kot prebrano'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.mark_email_read_outlined), findsOneWidget);
      var snapshot = (await tester.runAsync(fixture.storage.read))!;
      final entry = snapshot.financeEntries.singleWhere(
        (e) => e.occurrenceKey == '2026-10',
      );
      expect(entry.status, FinanceEntryStatus.planned);
      expect(entry.amountMinor, 120000);
      final plans = desiredFinanceReminderPlans(
        personal: snapshot,
        shared: CollaborationState(),
      );
      final store = FinanceInboxStore(fixture.db);
      expect(await tester.runAsync(() => store.readKeys(plans)), hasLength(1));
      // A new route/widget loads its receipt from SQLite; no settings/global OS opt-in is needed.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await pumpInbox(tester, fixture.db, fixture.storage, () => now);
      expect(find.byIcon(Icons.mark_email_read_outlined), findsOneWidget);
      now = DateTime(2026, 11, 2, 12);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await pumpInbox(tester, fixture.db, fixture.storage, () => now);
      expect(find.text('Ali si že dobil plačo?'), findsOneWidget);
      expect(find.byIcon(Icons.mark_email_unread_outlined), findsOneWidget);
      await tester.tap(find.text('Ali si že dobil plačo?'));
      await tester.pumpAndSettle();
      expect(find.text('Potrdi dejanski znesek'), findsWidgets);
      final amount = find.byKey(const ValueKey('sharing-actual-amount'));
      await tester.enterText(amount, '1299.50');
      await tester.tap(find.byKey(const ValueKey('sharing-submit')));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      snapshot = (await tester.runAsync(fixture.storage.read))!;
      final posted = snapshot.financeEntries.singleWhere(
        (e) => e.id == entry.id,
      );
      expect(posted.status, FinanceEntryStatus.posted);
      expect(posted.amountMinor, 129950);
      expect(posted.paidAt, now.toUtc());
      expect(find.text('Ali si že dobil plačo?'), findsNothing);
      expect(snapshot.financeEntries, hasLength(12));
      expect(tester.takeException(), null);
    },
  );
  testWidgets(
    'cold notification reference opens actual confirmation without booking on open or cancel',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final fixture = (await tester.runAsync(seed))!;
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(fixture.db.close);
      });
      final snapshot = (await tester.runAsync(fixture.storage.read))!;
      final plan = dueFinanceInboxPlans(
        personal: snapshot,
        shared: CollaborationState(),
        now: DateTime(2026, 10, 30, 12),
      ).single;
      final scheduler = FakeScheduler()
        ..launchPayload = jsonEncode(plan.target.toJson());
      final adapter = LocalNotificationAdapter(
        scheduler: scheduler,
        preferences: await SharedPreferences.getInstance(),
      );
      final target = await adapter.initialize((_) {});
      expect(target, isNotNull);
      expect(scheduler.permissionRequests, 0);
      await pumpInbox(
        tester,
        fixture.db,
        fixture.storage,
        () => DateTime(2026, 10, 30, 12),
        launch: target,
      );
      await tester.tap(find.text('Open notification'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('sharing-actual-amount')),
        findsOneWidget,
      );
      await tester.tap(find.text('Prekliči'));
      await tester.pumpAndSettle();
      expect(
        (await tester.runAsync(
          fixture.storage.read,
        ))!.financeEntries.first.status,
        FinanceEntryStatus.planned,
      );
      expect(scheduler.permissionRequests, 0);
      expect(tester.takeException(), null);
    },
  );
  test(
    'receipt store rejects stale visibility and never changes money rows',
    () async {
      final fixture = await seed();
      addTearDown(fixture.db.close);
      final before = await fixture.storage.read();
      final plan = desiredFinanceReminderPlans(
        personal: before,
        shared: CollaborationState(),
      ).first;
      final store = FinanceInboxStore(fixture.db);
      await expectLater(
        store.markRead(plan, stillVisible: () => false),
        throwsA(isA<CollaborationException>()),
      );
      expect(await store.readKeys([plan]), isEmpty);
      expect((await fixture.storage.read()).toJson(), before.toJson());
    },
  );
}
