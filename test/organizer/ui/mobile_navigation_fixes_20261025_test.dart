import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'package:kanban/organizer/domain/organizer_projections.dart';
import 'package:kanban/organizer/presentation/finance/shared_finance_accounts_dialog.dart';
import 'package:kanban/organizer/presentation/planning/agenda_month_calendar.dart';
import 'package:kanban/organizer/presentation/planning/shared_agenda_page.dart';
import 'package:kanban/organizer/presentation/planning/task_plan_fields.dart';
import 'package:kanban/organizer/presentation/shared/organization_workspace.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';
import 'onboarding_ui_test.dart' show pumpPanel;
import 'organization_people_ui_test.dart' show CreationController, org;
import 'organization_finance_ui_test.dart' as finance;
import 'organizer_ui_test.dart' show pumpOrganizer, MemoryOrganizerStorage;
import 'sharing_ui_fixture.dart';

class _DelayedSyncCreation extends CreationController {
  final sync = Completer<void>();
  int syncCalls = 0;
  @override
  Future<void> syncNow() {
    syncCalls++;
    return sync.future;
  }
}

final _now = DateTime.now();
LocalTask _task(
  String id,
  String project,
  String person, {
  int dayOffset = 0,
}) => LocalTask(
  id: id,
  title: id,
  notes: '',
  projectId: project,
  dueAt: DateTime(_now.year, _now.month, _now.day + dayOffset, 12),
  assigneeAccountIds: [person],
  isCompleted: false,
  createdAt: _now,
  updatedAt: _now,
);

void main() {
  test(
    'calendar uses local half-open day ranges and retains separate due date',
    () {
      final day = DateTime(2026, 10, 25); // Europe/Ljubljana DST transition.
      final item = AgendaItem(
        type: 'event',
        id: 'e',
        title: 'e',
        startAt: DateTime(2026, 10, 24, 23),
        endAt: DateTime(2026, 10, 26),
        dueAt: DateTime(2026, 10, 28),
      );
      expect(agendaItemCoversDay(item, day), isTrue);
      expect(agendaItemCoversDay(item, DateTime(2026, 10, 26)), isFalse);
      expect(agendaItemCoversDay(item, DateTime(2026, 10, 28)), isTrue);
      expect(
        agendaItemCoversDay(AgendaItem(type: 'task', id: 'u', title: 'u'), day),
        isFalse,
      );
      expect(
        agendaItemCoversDay(
          AgendaItem(
            type: 'task',
            id: 'c',
            title: 'c',
            dueAt: day,
            isCompleted: true,
          ),
          day,
        ),
        isFalse,
      );
    },
  );

  for (final width in [390.0, 1440.0]) {
    testWidgets('project completion does not wait on full sync $width', (
      tester,
    ) async {
      final controller = _DelayedSyncCreation()..loseFirst = false;
      String? opened;
      await pumpPanel(
        tester,
        controller,
        OrganizationWorkspace(
          organization: org,
          onProject: (id) => opened = id,
          onMembers: (_) {},
        ),
        width: width,
      );
      await tester.tap(find.text('Dodaj projekt v organizacijo'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField).first,
        'New scoped project',
      );
      await tester.tap(find.byKey(const ValueKey('sharing-submit')));
      await tester.pumpAndSettle();
      expect(controller.requests.length, 1);
      expect(controller.syncCalls, 0);
      expect(
        find.byKey(const ValueKey('organization-created-open')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('organization-created-open')));
      await tester.pumpAndSettle();
      expect(opened, controller.created.keys.single);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'shared calendar switches views without losing project/person filters $width',
      (tester) async {
        const scope = SharedScope(
          id: 'calendar-scope',
          name: 'Scoped calendar',
          kind: SharedScopeKind.project,
          role: SharedRole.owner,
        );
        final controller = SharingUiController(
          initial: CollaborationState(
            session: sharingSession(),
            scopes: [scope],
          ),
        );
        final data = SharedScopeData(
          projects: [
            LocalProject(
              id: 'p',
              title: 'Wanted project',
              description: '',
              createdAt: _now,
              updatedAt: _now,
            ),
            LocalProject(
              id: 'other',
              title: 'Other project',
              description: '',
              createdAt: _now,
              updatedAt: _now,
            ),
          ],
          tasks: [
            _task('Included task', 'p', 'a'),
            _task('Other person task', 'p', 'b'),
            _task('Other project task', 'other', 'a'),
            _task('Next day task', 'p', 'a', dayOffset: 1),
          ],
        );
        var adds = 0;
        AgendaItem? opened;
        await pumpPanel(
          tester,
          controller,
          SharedAgendaPage(
            scope: scope,
            data: data,
            timeline: true,
            selectedProjectId: 'p',
            people: [
              OrganizerPersonOption(id: 'a', label: 'Alice'),
              OrganizerPersonOption(id: 'b', label: 'Bob'),
            ],
            onOpen: (item) => opened = item,
            onAddEvent: () => adds++,
          ),
          width: width,
          textScale: width == 390 ? 1.5 : 1,
        );
        expect(
          find.byKey(const ValueKey('shared-month-calendar')),
          findsOneWidget,
        );
        expect(
          find.widgetWithText(FilledButton, 'Dodaj dogodek'),
          findsOneWidget,
        );
        await tester.tap(find.widgetWithText(FilledButton, 'Dodaj dogodek'));
        await tester.pump();
        expect(adds, 1);
        final person = find.byType(DropdownButtonFormField<String>).last;
        await tester.ensureVisible(person);
        await tester.tap(person);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Alice').last);
        await tester.pumpAndSettle();
        expect(find.text('Other project task'), findsNothing);
        expect(find.text('Other person task'), findsNothing);
        expect(find.text('Next day task'), findsNothing);
        await tester.ensureVisible(find.text('Included task'));
        await tester.tap(find.text('Included task'));
        await tester.pumpAndSettle();
        expect(opened?.id, 'Included task');
        await tester.ensureVisible(find.byType(SegmentedButton<bool>));
        await tester.tap(find.text('Časovnica').last);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('shared-month-calendar')),
          findsNothing,
        );
        expect(find.text('Next day task'), findsOneWidget);
        expect(find.text('Other person task'), findsNothing);
        expect(find.text('Other project task'), findsNothing);
        await tester.tap(find.text('Koledar').last);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('shared-month-calendar')),
          findsOneWidget,
        );
        expect(find.text('Next day task'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'Računi prostora opens actual parent accounts before a separate Add',
    (tester) async {
      final controller = finance.FinanceController(finance.fixture());
      await finance.pumpFinance(tester, controller, scopeId: 'project');
      final manage = find.text('Računi prostora');
      await tester.ensureVisible(manage);
      await tester.tap(manage);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('space-finance-account-bank')),
        findsOneWidget,
      );
      expect(find.byType(TextField), findsNothing);
      expect(controller.accountsCreated, isEmpty);
      await tester.tap(find.byKey(const ValueKey('space-finance-add-account')));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsWidgets);
      expect(controller.accountsCreated, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'project-only accounts list uses sanitized choices without parent or Add',
    (tester) async {
      final state = finance.fixture(projectOnly: true);
      final controller = finance.FinanceController(state);
      await pumpPanel(
        tester,
        controller,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showSharedFinanceAccounts(
              context,
              state,
              'org',
              projectScopeId: 'project',
            ),
            child: const Text('Računi prostora'),
          ),
        ),
      );
      await tester.tap(find.text('Računi prostora'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('space-finance-choice-bank')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('space-finance-add-account')),
        findsNothing,
      );
      expect(find.byIcon(Icons.edit_outlined), findsNothing);
      expect(find.text('TriparNA'), findsNothing);
      controller.switchAccount();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('space-finance-choice-bank')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final complete in [true, false]) {
    testWidgets(
      'space accounts distinguish confirmed empty from unavailable $complete',
      (tester) async {
        final state = CollaborationState(
          session: sharingSession(),
          financeSupported: true,
          scopes: [finance.organization],
          financePolicies: {'org': finance.policy},
          financeSnapshotComplete: {'org': complete},
        );
        final controller = SharingUiController(initial: state);
        await pumpPanel(
          tester,
          controller,
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showSharedFinanceAccounts(context, state, 'org'),
              child: const Text('Open accounts'),
            ),
          ),
        );
        await tester.tap(find.text('Open accounts'));
        await tester.pumpAndSettle();
        expect(
          find.text('Ustvari prvi finančni račun v tem prostoru.'),
          complete ? findsOneWidget : findsNothing,
        );
        expect(
          find.text(
            'Računi prostora še niso na voljo. Povežite se in osvežite projekt.',
          ),
          complete ? findsNothing : findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('space-finance-add-account')),
          complete ? findsOneWidget : findsNothing,
        );
        controller.switchAccount();
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('space-finance-add-account')),
          findsNothing,
        );
        expect(
          find.text('Ustvari prvi finančni račun v tem prostoru.'),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'month markers describe day content and date selection at narrow large text',
    (tester) async {
      final semantics = tester.ensureSemantics();
      DateTime? selected;
      await pumpPanel(
        tester,
        SharingUiController(initial: CollaborationState()),
        AgendaMonthCalendar(
          day: DateTime(2026, 10, 25),
          items: [
            AgendaItem(
              type: 'event',
              id: 'e',
              title: 'Range',
              startAt: DateTime(2026, 10, 24, 23),
              endAt: DateTime(2026, 10, 26),
            ),
            AgendaItem(
              type: 'task',
              id: 't',
              title: 'Deadline',
              dueAt: DateTime(2026, 10, 25, 12),
            ),
          ],
          onSelected: (day) => selected = day,
        ),
        width: 320,
        textScale: 2,
      );
      final day = find.byKey(const ValueKey('shared-calendar-day-2026-10-25'));
      await tester.ensureVisible(day);
      final node = tester.getSemantics(day);
      expect(node.label, contains('2 načrtovanih vsebin'));
      await tester.tap(day);
      await tester.pumpAndSettle();
      expect(selected, DateTime(2026, 10, 25));
      semantics.dispose();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Android pulse scrolls through cards and nav labels clear system inset',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      tester.view.padding = const FakeViewPadding(bottom: 34);
      tester.view.viewPadding = const FakeViewPadding(bottom: 34);
      addTearDown(tester.view.resetPadding);
      addTearDown(tester.view.resetViewPadding);
      await pumpOrganizer(
        tester,
        MemoryOrganizerStorage(),
        width: 390,
        height: 844,
        collaborationController: SharingUiController(
          initial: CollaborationState(),
        ),
      );
      final add = find.widgetWithText(TextButton, 'Dodaj dogodek');
      await tester.ensureVisible(add);
      expect(add, findsOneWidget);
      final scroll = find.byKey(const ValueKey('content-_Area.today'));
      await tester.drag(scroll, const Offset(0, -1000));
      await tester.pumpAndSettle();
      expect(find.text('Na vrsti').hitTestable(), findsOneWidget);
      for (final label in ['Utrip', 'Planer', 'Prostor', 'Več']) {
        final text = find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text(label),
        );
        expect(tester.getBottomLeft(text).dy, lessThanOrEqualTo(810));
      }
      debugDefaultTargetPlatformOverride = null;
      expect(tester.takeException(), isNull);
    },
  );
}
