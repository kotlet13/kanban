import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/l10n/app_localizations.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'package:kanban/organizer/presentation/inbox/remote_reminder_editor.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';

import 'sharing_ui_fixture.dart';

const taskId = '10000000-0000-4000-8000-000000000002';
const reminderId = '10000000-0000-4000-8000-000000000003';
final now = DateTime(2026, 10, 8, 12);
SharedScheduledReminder reminder({
  String syncState = 'synced',
  String state = 'pending',
  DateTime? remindAt,
}) => SharedScheduledReminder(
  id: reminderId,
  scopeId: sharingScopeId,
  targetType: 'task',
  targetId: taskId,
  remindAt: remindAt ?? now.add(const Duration(hours: 2)),
  revision: 4,
  state: state,
  syncState: syncState,
);
CollaborationState state({
  List<SharedScheduledReminder> reminders = const [],
  bool completed = false,
  bool revoked = false,
  SharedRole role = SharedRole.owner,
}) => CollaborationState(
  session: sharingSession(),
  inboxSupported: true,
  selectedSpaceId: sharingScopeId,
  scopes: [sharingScope(revoked: revoked, role: role)],
  data: {
    sharingScopeId: SharedScopeData(
      tasks: [
        LocalTask(
          id: taskId,
          projectId: null,
          title: 'Moje skupno opravilo',
          notes: '',
          dueAt: now.add(const Duration(days: 1)),
          isCompleted: completed,
          createdAt: now,
          updatedAt: now,
        ),
      ],
    ),
  },
  scheduledReminders: reminders,
);

class ReminderController extends SharingUiController {
  ReminderController(CollaborationState initial) : super(initial: initial);
  String? savedId, partition;
  DateTime? savedAt;
  int? savedRevision;
  SharedScheduledReminder? cancelled;
  Object? failure;
  @override
  Future<String> putReminder({
    String? id,
    required String scopeId,
    required String targetType,
    required String targetId,
    required DateTime remindAt,
    int expectedRevision = 0,
    String? expectedPartition,
  }) async {
    if (failure != null) throw failure!;
    if (id != null &&
        this.state.requireValue.scheduledReminders
                .where((r) => r.id == id)
                .firstOrNull
                ?.revision !=
            expectedRevision) {
      throw const CollaborationException('stale_edit');
    }
    savedId = id;
    savedAt = remindAt;
    savedRevision = expectedRevision;
    partition = expectedPartition;
    calls.add('put');
    return id ?? reminderId;
  }

  @override
  Future<void> cancelReminder(
    SharedScheduledReminder reminder, {
    String? expectedPartition,
  }) async {
    if (this.state.requireValue.scheduledReminders
            .where((r) => r.id == reminder.id)
            .firstOrNull
            ?.revision !=
        reminder.revision) {
      throw const CollaborationException('stale_edit');
    }
    cancelled = reminder;
    partition = expectedPartition;
    calls.add('cancel');
  }
}

Future<void> pump(
  WidgetTester tester,
  ReminderController controller, {
  double width = 390,
  String type = 'task',
  String id = taskId,
}) async {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        collaborationProvider.overrideWith(() => controller),
        collaborationClockProvider.overrideWithValue(() => now),
      ],
      child: MaterialApp(
        locale: const Locale('sl'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: RemoteReminderButton(
            scopeId: sharingScopeId,
            targetType: type,
            targetId: id,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'viewer cannot create or edit but can cancel their existing reminder',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = ReminderController(state(role: SharedRole.viewer));
      await pump(tester, controller);
      expect(find.byType(IconButton), findsNothing);
      controller.replace(
        state(role: SharedRole.viewer, reminders: [reminder()]),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Prekliči opomnik'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Shrani'))
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('Prekliči opomnik'));
      await tester.pumpAndSettle();
      expect(controller.calls, ['cancel']);
    },
  );

  testWidgets(
    '390px time input fits with keyboard and stale account cannot save from picker',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      final controller = ReminderController(state());
      await pump(tester, controller);
      await tester.tap(find.byTooltip('Dodaj oddaljeni opomnik'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('remote-reminder-time')));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.keyboard_outlined));
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNWidgets(2));
      expect(tester.takeException(), isNull);
      controller.switchAccount();
      await tester.pumpAndSettle();
      // Both modal layers dismiss on an account change, including the keyboard picker.
      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      expect(find.byType(TimePickerDialog), findsNothing);
      expect(find.text('Oddaljeni opomnik'), findsNothing);
      expect(controller.calls, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'past selected time is rejected locally and can still be cancelled',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = ReminderController(
        state(
          reminders: [
            reminder(remindAt: now.subtract(const Duration(minutes: 1))),
          ],
        ),
      );
      await pump(tester, controller);
      await tester.tap(find.byTooltip('Uredi oddaljeni opomnik'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Shrani'));
      await tester.pumpAndSettle();
      expect(find.text('Izberi čas v prihodnosti.'), findsOneWidget);
      expect(controller.calls, isEmpty);
      await tester.tap(find.text('Prekliči opomnik'));
      await tester.pumpAndSettle();
      expect(controller.calls, ['cancel']);
    },
  );
  testWidgets(
    'finance read access and complete snapshot are required; revoke closes editor',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      CollaborationState finance({bool complete = true, bool read = true}) =>
          CollaborationState(
            session: sharingSession(),
            inboxSupported: true,
            scopes: [sharingScope()],
            financeSnapshotComplete: {sharingScopeId: complete},
            financePolicies: {
              sharingScopeId: SharedFinancePolicy(
                enabled: read,
                grant: SharedFinanceGrant.read,
                revision: read ? 4 : 5,
              ),
            },
            data: {
              sharingScopeId: SharedScopeData(
                financeEntries: [
                  SharedFinanceEntry(
                    id: taskId,
                    accountId: reminderId,
                    title: 'Pravi planirani račun',
                    kind: FinanceEntryKind.expense,
                    status: SharedFinanceStatus.planned,
                    amountMinor: 200,
                    currency: 'EUR',
                    occurredAt: now,
                    createdAt: now,
                    updatedAt: now,
                  ),
                ],
              ),
            },
          );
      final controller = ReminderController(finance(complete: false));
      await pump(tester, controller, type: 'financeEntry');
      expect(find.byType(IconButton), findsNothing);
      controller.replace(finance());
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Dodaj oddaljeni opomnik'));
      await tester.pumpAndSettle();
      expect(find.text('Pravi planirani račun'), findsOneWidget);
      controller.replace(finance(read: false));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(controller.calls, isEmpty);
    },
  );

  testWidgets(
    '390px adds current-account UTC remote reminder without changing due date',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final initial = state();
      final controller = ReminderController(initial);
      await pump(tester, controller);
      await tester.tap(find.byTooltip('Dodaj oddaljeni opomnik'));
      await tester.pumpAndSettle();
      expect(find.textContaining('samo tvojemu računu'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('remote-reminder-date')),
        findsOneWidget,
      );
      await tester.tap(find.text('Shrani'));
      await tester.pumpAndSettle();
      expect(controller.calls, ['put']);
      expect(controller.savedRevision, 0);
      expect(controller.savedAt, now.add(const Duration(hours: 1)).toUtc());
      expect(controller.partition, sharingSession().partition);
      expect(
        initial.dataForScope(sharingScopeId).tasks.single.dueAt,
        now.add(const Duration(days: 1)),
      );
      expect(find.textContaining('čaka na strežnik'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'desktop edits saved revision and cancels with captured account',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = ReminderController(state(reminders: [reminder()]));
      await pump(tester, controller, width: 1200);
      await tester.tap(find.byTooltip('Uredi oddaljeni opomnik'));
      await tester.pumpAndSettle();
      expect(find.text('Termin je shranjen na strežniku.'), findsOneWidget);
      await tester.tap(find.text('Shrani'));
      await tester.pumpAndSettle();
      expect(controller.savedId, reminderId);
      expect(controller.savedRevision, 4);
      await tester.tap(find.byTooltip('Uredi oddaljeni opomnik'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Prekliči opomnik'));
      await tester.pumpAndSettle();
      expect(controller.cancelled?.revision, 4);
      expect(controller.partition, sharingSession().partition);
    },
  );
  for (final status in ['queued', 'blocked']) {
    testWidgets('shows $status separate from server saved schedule', (
      tester,
    ) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = ReminderController(
        state(reminders: [reminder(syncState: status)]),
      );
      await pump(tester, controller);
      await tester.tap(find.byTooltip('Uredi oddaljeni opomnik'));
      await tester.pumpAndSettle();
      expect(find.text('Termin je shranjen na strežniku.'), findsNothing);
      expect(
        find.text(
          status == 'queued'
              ? 'Čaka na potrditev strežnika. Dostava še ni potrjena.'
              : 'Sprememba ni bila sprejeta. Preveri dostop in osveži podatke.',
        ),
        findsOneWidget,
      );
      if (status == 'blocked') {
        expect(
          tester
              .widget<FilledButton>(find.widgetWithText(FilledButton, 'Shrani'))
              .onPressed,
          isNotNull,
        );
        await tester.tap(find.text('Shrani'));
        await tester.pumpAndSettle();
        expect(controller.calls, ['put']);
        expect(controller.savedId, reminderId);
        expect(controller.savedRevision, 4);
      }
      expect(tester.takeException(), isNull);
    });
  }
  for (final change in [
    'account',
    'space',
    'completed',
    'revoked',
    'deleted',
  ]) {
    testWidgets('$change closes stale editor without saving', (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = ReminderController(state());
      await pump(tester, controller);
      await tester.tap(find.byTooltip('Dodaj oddaljeni opomnik'));
      await tester.pumpAndSettle();
      controller.replace(switch (change) {
        'account' => CollaborationState(session: sharingSession(second: true)),
        'space' => CollaborationState(
          session: sharingSession(),
          selectedSpaceId: 'other',
        ),
        'completed' => state(completed: true),
        'revoked' => state(revoked: true),
        _ => CollaborationState(
          session: sharingSession(),
          inboxSupported: true,
          scopes: [sharingScope()],
        ),
      });
      await tester.pumpAndSettle();
      expect(find.text('Oddaljeni opomnik'), findsNothing);
      expect(controller.calls, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('repository rejection remains visible without announcing saved', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = ReminderController(state())
      ..failure = const CollaborationException('stale_edit');
    await pump(tester, controller);
    await tester.tap(find.byTooltip('Dodaj oddaljeni opomnik'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Shrani'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.textContaining('čaka na strežnik'), findsNothing);
    expect(controller.calls, isEmpty);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'existing remote date beyond picker range opens safely and preserves date until chosen',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final future = DateTime(now.year + 20, 6, 15, 10);
      final controller = ReminderController(
        state(reminders: [reminder(remindAt: future)]),
      );
      await pump(tester, controller);
      await tester.tap(find.byTooltip('Uredi oddaljeni opomnik'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('remote-reminder-date')));
      await tester.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsOneWidget);
      final picker = tester.widget<DatePickerDialog>(
        find.byType(DatePickerDialog),
      );
      expect(picker.initialDate, DateTime(now.year + 10, 12, 31));
      expect(tester.takeException(), isNull);
      Navigator.of(tester.element(find.byType(DatePickerDialog))).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Shrani'));
      await tester.pumpAndSettle();
      expect(controller.savedAt, future.toUtc());
    },
  );
  testWidgets(
    'late canonical revision cannot overwrite or cancel from an older open editor',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = ReminderController(state(reminders: [reminder()]));
      await pump(tester, controller);
      await tester.tap(find.byTooltip('Uredi oddaljeni opomnik'));
      await tester.pumpAndSettle();
      controller.replace(
        state(
          reminders: [
            SharedScheduledReminder.fromJson({
              ...reminder().toJson(),
              'revision': 5,
            }),
          ],
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Shrani'));
      await tester.pumpAndSettle();
      expect(controller.calls, isEmpty);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.textContaining('čaka na strežnik'), findsNothing);
      await tester.tap(find.text('Prekliči opomnik'));
      await tester.pumpAndSettle();
      expect(controller.calls, isEmpty);
      expect(controller.cancelled, isNull);
    },
  );
}
