import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/l10n/app_localizations.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'package:kanban/organizer/presentation/planning/project_capacity_panel.dart';

void main() {
  final now = DateTime.utc(2026, 10, 8);
  final project = LocalProject(
    id: 'p',
    title: 'Project',
    description: '',
    createdAt: now,
    updatedAt: now,
    availabilityMinutes: 60,
    availabilityPeriod: AvailabilityPeriod.day,
  );
  final task = LocalTask(
    id: 't',
    title: 'Task',
    notes: '',
    projectId: 'p',
    dueAt: null,
    isCompleted: false,
    createdAt: now,
    updatedAt: now,
    estimateMinutes: 90,
    timer: const TaskTimerState(elapsedSeconds: 1800),
  );
  Future<void> pump(
    WidgetTester tester, {
    required String language,
    required LocalProject p,
    required List<LocalTask> tasks,
  }) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        locale: Locale(language),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          body: SingleChildScrollView(
            child: ProjectCapacityPanel(
              project: p,
              tasks: tasks,
              clock: () => now,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final language in ['sl', 'en']) {
    testWidgets('capacity and missing values fit narrow 2x UI in $language', (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pump(tester, language: language, p: project, tasks: [task]);
      expect(
        find.text(
          language == 'sl'
              ? 'Okvirno trajanje v dnevih: 1'
              : 'Approximate duration in days: 1',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('1:00:00'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await pump(
        tester,
        language: language,
        p: project.copyWith(
          availabilityMinutes: null,
          availabilityPeriod: null,
        ),
        tasks: [task, task.copyWith(estimateMinutes: null)],
      );
      expect(
        find.textContaining(
          language == 'sl' ? 'brez ocene dela:' : 'without an effort estimate:',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          language == 'sl'
              ? 'brez dnevne ali tedenske'
              : 'without daily or weekly',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          language == 'sl'
              ? 'Okvirno trajanje v dnevih:'
              : 'Approximate duration in days:',
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('running timer updates capacity without mutating records', (
    tester,
  ) async {
    var clock = now;
    final running = task.copyWith(
      timer: TaskTimerState(runningSince: now, runId: 'r'),
    );
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: ProjectCapacityPanel(
            project: project,
            tasks: [running],
            clock: () => clock,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.textContaining('1:30:00'), findsOneWidget);
    clock = clock.add(const Duration(minutes: 30));
    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('1:00:00'), findsOneWidget);
    expect(running.timer.elapsedSeconds, 0);
    await tester.pumpWidget(const SizedBox());
  });
}
