import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/l10n/app_localizations.dart';
import 'package:kanban/organizer/data/organizer_repository.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'package:kanban/organizer/presentation/inbox/inbox_page.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';
import 'package:kanban/organizer/state/local_database_provider.dart';
import 'package:kanban/organizer/state/organizer_provider.dart';
import 'finance_inbox_ui_test.dart' as finance;
import 'sharing_ui_fixture.dart';

class FreshSnoozeController extends SharingUiController {
  FreshSnoozeController(CollaborationState initial, this.result)
    : super(initial: initial);
  final NotificationOpenStatus result;
  int freshChecks = 0;
  @override
  Future<NotificationOpenResult> openNotificationTarget(
    NotificationTarget target,
  ) async {
    freshChecks++;
    return NotificationOpenResult(status: result, target: target);
  }
}

void main() {
  testWidgets(
    '390px task snooze selects 15 minutes, survives route rebuild and keeps due date',
    (tester) async {
      final fixture = (await tester.runAsync(finance.seed))!;
      var now = DateTime(2026, 10, 8, 12);
      await tester.runAsync(() async {
        final repo = OrganizerRepository(fixture.storage, clock: () => now);
        await repo.initialize();
        await repo.createTask(title: 'Real due task', dueAt: now);
        await repo.close();
      });
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(fixture.db.close);
      });
      await finance.pumpInbox(tester, fixture.db, fixture.storage, () => now);
      expect(find.textContaining('Real due task'), findsOneWidget);
      await tester.tap(find.byTooltip('Odloži opomnik'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Odložitev velja na tej napravi'),
        findsOneWidget,
      );
      await tester.tap(find.text('Čez 15 minut'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Real due task'), findsNothing);
      final snapshot = (await tester.runAsync(fixture.storage.read))!;
      expect(snapshot.tasks.single.dueAt, now.toUtc());
      expect(snapshot.tasks.single.isCompleted, false);
      final rows = (await tester.runAsync(
        () => fixture.db.rows(
          "SELECT value FROM local_meta WHERE name LIKE 'reminder_snooze:%'",
        ),
      ))!;
      expect(rows, hasLength(1));
      expect(
        DateTime.parse(
          (jsonDecode(rows.single['value'] as String) as Map)['until']
              as String,
        ),
        now.add(const Duration(minutes: 15)).toUtc(),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await finance.pumpInbox(tester, fixture.db, fixture.storage, () => now);
      expect(find.textContaining('Real due task'), findsNothing);
      now = now.add(const Duration(minutes: 15));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await finance.pumpInbox(tester, fixture.db, fixture.storage, () => now);
      tester.view.physicalSize = const Size(1440, 1000);
      await tester.pumpAndSettle();
      expect(find.textContaining('Real due task'), findsOneWidget);
      expect(find.byTooltip('Odloži opomnik'), findsOneWidget);
      expect(tester.takeException(), null);
    },
  );
  testWidgets(
    'salary question snoozes without recording payment; returns as read',
    (tester) async {
      final fixture = (await tester.runAsync(finance.seed))!;
      var now = DateTime(2026, 10, 30, 12);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(fixture.db.close);
      });
      await finance.pumpInbox(tester, fixture.db, fixture.storage, () => now);
      await tester.tap(find.byTooltip('Označi kot prebrano'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Odloži opomnik'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Čez 15 minut'));
      await tester.pumpAndSettle();
      expect(find.text('Ali si že dobil plačo?'), findsNothing);
      final before = (await tester.runAsync(fixture.storage.read))!;
      final entry = before.financeEntries.singleWhere(
        (e) => e.occurrenceKey == '2026-10',
      );
      expect(entry.status, FinanceEntryStatus.planned);
      expect(entry.amountMinor, 120000);
      now = now.add(const Duration(minutes: 15));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await finance.pumpInbox(tester, fixture.db, fixture.storage, () => now);
      expect(find.text('Ali si že dobil plačo?'), findsOneWidget);
      expect(find.byIcon(Icons.mark_email_read_outlined), findsOneWidget);
      expect(tester.takeException(), null);
    },
  );
  for (final result in [
    NotificationOpenStatus.offline,
    NotificationOpenStatus.permissionDenied,
  ]) {
    testWidgets(
      'shared snooze requires fresh available authorization: $result',
      (tester) async {
        final fixture = (await tester.runAsync(finance.seed))!;
        final now = DateTime(2026, 10, 8, 12);
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.runAsync(fixture.db.close);
        });
        final task = LocalTask(
          id: newLocalId(),
          title: 'Shared due task',
          projectId: null,
          notes: '',
          isCompleted: false,
          dueAt: now,
          createdAt: now,
          updatedAt: now,
        );
        final state = CollaborationState(
          session: sharingSession(),
          scopes: [sharingScope()],
          data: {
            sharingScopeId: SharedScopeData(tasks: [task]),
          },
          inbox: [
            SharedInboxEntry(
              id: 1,
              scopeId: sharingScopeId,
              kind: 'reminder.due',
              category: 'reminders',
              audience: InboxAudience.personal,
              targetType: 'task',
              targetId: task.id,
              groupKey: task.id,
              createdAt: now,
            ),
          ],
        );
        final controller = FreshSnoozeController(state, result);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              collaborationProvider.overrideWith(() => controller),
              localDatabaseProvider.overrideWith((ref) async => fixture.db),
              organizerStorageProvider.overrideWithValue(
                () async => fixture.storage,
              ),
              organizerClockProvider.overrideWithValue(() => now),
              organizerReminderSchedulerProvider.overrideWithValue(
                (_) => (() {}),
              ),
            ],
            child: MaterialApp(
              locale: const Locale('sl'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(
                body: SingleChildScrollView(
                  child: OrganizerInboxPage(
                    onSettings: () {},
                    onAccount: () {},
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Odloži opomnik'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Čez 15 minut'));
        await tester.pumpAndSettle();
        expect(controller.freshChecks, 1);
        expect(
          (await tester.runAsync(
            () => fixture.db.rows(
              "SELECT * FROM local_meta WHERE name LIKE 'reminder_snooze:%'",
            ),
          ))!,
          isEmpty,
        );
        expect(find.byTooltip('Odloži opomnik'), findsOneWidget);
        expect(tester.takeException(), null);
      },
    );
  }
}
