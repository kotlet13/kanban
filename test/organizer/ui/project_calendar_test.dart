import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/l10n/app_localizations.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'package:kanban/organizer/domain/project_calendar.dart';
import 'package:kanban/organizer/presentation/planning/project_calendar.dart';
import 'package:kanban/organizer/presentation/planning/project_planning_summary.dart';
import 'package:kanban/organizer/presentation/planning/task_timer_panel.dart';

void main() {
  final now = DateTime(2026, 10, 1);
  final project = LocalProject(
    id: 'p',
    title: 'Project interval',
    description: '',
    createdAt: now,
    updatedAt: now,
    startAt: DateTime(2026, 9, 29),
    endAt: DateTime(2026, 10, 4),
    phases: [
      ProjectPhase(
        id: 'phase',
        title: 'Phase milestone',
        startAt: DateTime(2026, 9, 30),
        endAt: DateTime(2026, 10, 2),
      ),
    ],
  );
  LocalTask task(
    String id,
    String? projectId, {
    DateTime? start,
    DateTime? end,
    DateTime? due,
  }) => LocalTask(
    id: id,
    title: id,
    notes: '',
    projectId: projectId,
    dueAt: due,
    startAt: start,
    endAt: end,
    isCompleted: false,
    createdAt: now,
    updatedAt: now,
  );
  final tasks = [
    task(
      'Midnight task',
      'p',
      start: DateTime(2026, 9, 30, 23),
      end: DateTime(2026, 10, 2),
    ),
    task('Due task', 'p', due: DateTime(2026, 10, 2, 15)),
    task('Other project', 'other', due: DateTime(2026, 10, 2)),
  ];
  test(
    'project filter; phase end inclusive; task midnight end exclusive and separate due point',
    () {
      final items = projectCalendarItems(project, tasks);
      expect(items.where((i) => i.title == 'Other project'), isEmpty);
      final timed = items.firstWhere((i) => i.title == 'Midnight task');
      expect(timed.covers(DateTime(2026, 9, 30)), isTrue);
      expect(timed.covers(DateTime(2026, 10, 1)), isTrue);
      expect(timed.covers(DateTime(2026, 10, 2)), isFalse);
      final phase = items.firstWhere(
        (i) => i.kind == ProjectCalendarKind.phase,
      );
      expect(phase.covers(DateTime(2026, 10, 2)), isTrue);
      expect(phase.covers(DateTime(2026, 10, 3)), isFalse);
      expect(
        items
            .firstWhere((i) => i.title == 'Due task')
            .covers(DateTime(2026, 10, 2)),
        isTrue,
      );
      final ranged = ProjectCalendarItem(
        id: 'x',
        title: 'x',
        kind: ProjectCalendarKind.task,
        start: DateTime(2026, 10, 1),
        end: DateTime(2026, 10, 2),
        due: DateTime(2026, 10, 5),
      );
      expect(ranged.covers(DateTime(2026, 10, 2)), isFalse);
      expect(ranged.covers(DateTime(2026, 10, 5)), isTrue);
    },
  );
  for (final width in [320.0, 390.0, 1280.0]) {
    for (final locale in ['sl', 'en']) {
      for (final brightness in [Brightness.light, Brightness.dark]) {
        testWidgets(
          'month calendar $width $locale $brightness selects exact task and changes period',
          (tester) async {
            tester.view.physicalSize = Size(width, 900);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            LocalTask? opened;
            await tester.pumpWidget(
              MaterialApp(
                locale: Locale(locale),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                theme: ThemeData(brightness: brightness),
                home: Scaffold(
                  body: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: ProjectCalendar(
                        project: project,
                        tasks: tasks,
                        initialMonth: DateTime(2026, 10, 1),
                        onTaskSelected: (t) => opened = t,
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            expect(
              find.byKey(const ValueKey('project-calendar-day-2026-10-31')),
              findsOneWidget,
            );
            await tester.tap(
              find.byKey(const ValueKey('project-calendar-day-2026-10-2')),
            );
            await tester.pumpAndSettle();
            expect(find.text('Other project'), findsNothing);
            expect(find.text('Midnight task'), findsNothing);
            expect(find.text('Phase milestone'), findsOneWidget);
            final due = find.byKey(
              const ValueKey('project-calendar-item-task-Due task'),
            );
            await tester.ensureVisible(due);
            await tester.tap(due);
            expect(opened?.id, 'Due task');
            await tester.ensureVisible(
              find.byKey(const ValueKey('project-calendar-next')),
            );
            await tester.tap(
              find.byKey(const ValueKey('project-calendar-next')),
            );
            await tester.pumpAndSettle();
            expect(
              find.byKey(const ValueKey('project-calendar-day-2026-11-30')),
              findsOneWidget,
            );
            await tester.tap(
              find.byKey(const ValueKey('project-calendar-previous')),
            );
            await tester.pumpAndSettle();
            await tester.tap(
              find.byKey(const ValueKey('project-calendar-previous')),
            );
            await tester.pumpAndSettle();
            expect(
              find.byKey(const ValueKey('project-calendar-day-2026-9-30')),
              findsOneWidget,
            );
            await tester.tap(
              find.byKey(const ValueKey('project-calendar-day-2026-9-30')),
            );
            await tester.pumpAndSettle();
            expect(find.text('Midnight task'), findsOneWidget);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
  testWidgets(
    'large text month calendar remains scrollable on 320px with keyboard',
    (tester) async {
      tester.view.physicalSize = const Size(320, 780);
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = const FakeViewPadding(bottom: 340);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('sl'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              child: ProjectCalendar(
                project: project,
                tasks: tasks,
                initialMonth: DateTime(2026, 10, 1),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final day = find.byKey(const ValueKey('project-calendar-day-2026-10-31'));
      await tester.ensureVisible(day);
      await tester.tap(day);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'two phases display exact assigned tasks and unassigned group; row opens concrete task',
    (tester) async {
      final phased = project.copyWith(
        phases: const [
          ProjectPhase(id: 'one', title: 'First milestone'),
          ProjectPhase(id: 'two', title: 'Second milestone'),
        ],
      );
      final first = task(
        'First phase task',
        'p',
      ).copyWith(phaseId: 'one', estimateMinutes: 30, isCompleted: true);
      final second = task(
        'Second phase task',
        'p',
      ).copyWith(phaseId: 'two', estimateMinutes: 90);
      final unassigned = task('Unassigned task', 'p');
      final other = task('Other project task', 'different');
      LocalTask? opened;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('sl'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: ProjectPlanningSummary(
                project: phased,
                tasks: [first, second, unassigned, other],
                onTaskSelected: (task) => opened = task,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final firstGroup = find.byKey(const ValueKey('project-phase-one'));
      final secondGroup = find.byKey(const ValueKey('project-phase-two'));
      final unassignedGroup = find.byKey(
        const ValueKey('project-phase-unassigned'),
      );
      expect(
        find.descendant(of: firstGroup, matching: find.text(first.title)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: firstGroup, matching: find.text(second.title)),
        findsNothing,
      );
      expect(
        find.descendant(of: secondGroup, matching: find.text(second.title)),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: unassignedGroup,
          matching: find.text(unassigned.title),
        ),
        findsOneWidget,
      );
      expect(find.text(other.title), findsNothing);
      final target = find.byKey(
        const ValueKey('project-phase-task-phase-two-Second phase task'),
      );
      await tester.ensureVisible(target);
      await tester.tap(target);
      expect(opened?.id, second.id);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'running timer readout advances without any persistence callback',
    (tester) async {
      var clock = DateTime.utc(2026, 10, 8, 12);
      final timer = TaskTimerState(runningSince: clock, runId: 'run');
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('sl'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: TaskTimerPanel(
              timer: timer,
              estimateMinutes: 1,
              showControls: false,
              clock: () => clock,
            ),
          ),
        ),
      );
      expect(find.textContaining('0:00:00'), findsOneWidget);
      clock = clock.add(const Duration(seconds: 5));
      await tester.pump(const Duration(seconds: 5));
      expect(find.textContaining('0:00:05'), findsOneWidget);
      expect(find.textContaining('0:00:55'), findsOneWidget);
      expect(find.byType(OutlinedButton), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
