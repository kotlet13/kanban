import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/l10n/app_localizations.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'package:kanban/organizer/presentation/planning/record_planning_fields.dart';
import 'package:kanban/organizer/presentation/planning/task_timer_panel.dart';
import 'package:kanban/organizer/presentation/shared/collaboration_actions.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';
import 'package:kanban/organizer/state/organizer_provider.dart';

import 'sharing_ui_fixture.dart';

class _Personal extends OrganizerController {
  @override
  Future<OrganizerSnapshot> build() async => OrganizerSnapshot();
}

final _date = DateTime.utc(2026, 10, 25);
final _task = LocalTask(
  id: '10000000-0000-4000-8000-000000000015',
  title: 'Already open task',
  notes: 'Shared base',
  projectId: null,
  dueAt: null,
  isCompleted: false,
  revision: 1,
  createdAt: _date,
  updatedAt: _date,
);

CollaborationState _state({
  bool revoked = false,
  bool deletion = false,
  bool localAccess = true,
  bool viewer = false,
  AccountSession? session,
}) {
  final scope = SharedScope.fromJson({
    ...sharingScope(revoked: revoked).toJson(),
    if (viewer) 'role': 'viewer',
    if (viewer) 'recordPolicyVersion': 1,
  });
  return CollaborationState(
    session: session ?? sharingSession(),
    scopes: [scope],
    deletionPending: deletion,
    localAccessAllowed: localAccess,
    selectedSpaceId: scope.id,
    recordContractVersion: 6,
    data: {
      scope.id: SharedScopeData(
        tasks: [_task],
        recordCreators: {
          'content:${_task.id}': viewer
              ? 'foreign-author'
              : sharingSession().accountId,
        },
      ),
    },
  );
}

class _Controller extends SharingUiController {
  _Controller({CollaborationState? initial})
    : super(initial: initial ?? _state());
  String epoch = 'initial-session-epoch';
  @override
  String get editorSessionIdentity => epoch;
  int saves = 0, timers = 0, financePreparations = 0;
  final previewRefresh = Completer<NotificationOpenResult>();
  Completer<SharedContentPolicy>? policyGate;
  @override
  Future<SharedContentPolicy> sharedContentPolicy({String? scopeId}) =>
      policyGate?.future ?? super.sharedContentPolicy(scopeId: scopeId);
  @override
  Future<void> updateTask(String scopeId, LocalTask task) async => saves++;
  @override
  Future<LocalTask> toggleTaskTimer(String scopeId, LocalTask task) async {
    timers++;
    return task;
  }

  @override
  Future<void> refreshFinanceAccountChoices(String scopeId) async =>
      financePreparations++;
  @override
  Future<NotificationOpenResult> refreshVisibleTaskTarget(
    NotificationTarget target,
  ) => previewRefresh.future;
}

Future<void> _mount(
  WidgetTester tester,
  _Controller controller, {
  bool preview = false,
}) async {
  tester.view.physicalSize = preview
      ? const Size(480, 900)
      : const Size(900, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        collaborationProvider.overrideWith(() => controller),
        if (preview) organizerProvider.overrideWith(_Personal.new),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) {
              if (preview) ref.watch(organizerProvider);
              final current = ref.watch(collaborationProvider).valueOrNull;
              if (current == null) return const SizedBox.shrink();
              return TextButton(
                child: const Text('Open'),
                onPressed: () {
                  final actions = CollaborationActions(
                    context,
                    ref,
                    current.scopes.single,
                    current.dataForScope(sharingScopeId),
                  );
                  unawaited(
                    preview
                        ? actions.openTask(_task)
                        : actions.task(task: _task),
                  );
                },
              );
            },
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

Finder get _notes => find.byKey(const ValueKey('organizer-notes-field'));

void main() {
  testWidgets(
    'revoked task retains typed input while stale Save and Timer callbacks cannot publish',
    (tester) async {
      final controller = _Controller();
      await _mount(tester, controller);
      final oldSave = tester
          .widget<IconButton>(
            find.descendant(
              of: find.byKey(const ValueKey('organizer-save')),
              matching: find.byType(IconButton),
            ),
          )
          .onPressed!;
      final oldTimer = tester
          .widget<TaskTimerPanel>(find.byType(TaskTimerPanel))
          .onToggle!;
      await tester.enterText(_notes, 'Unsaved before rights loss');
      controller.replace(_state(revoked: true));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.byKey(const ValueKey('organizer-local-draft-only')),
        findsOneWidget,
      );
      await tester.enterText(_notes, 'Finished in this open form');
      expect(
        tester
            .widget<EditableText>(
              find.descendant(of: _notes, matching: find.byType(EditableText)),
            )
            .controller
            .text,
        'Finished in this open form',
      );
      oldSave();
      await oldTimer();
      await tester.pumpAndSettle();
      expect(controller.saves, 0);
      expect(controller.timers, 0);
      expect(controller.financePreparations, 0);
      final fields = tester.widget<OrganizerRecordPlanningFields>(
        find.byType(OrganizerRecordPlanningFields),
      );
      expect(fields.costEditingEnabled, isFalse);
      expect(fields.onCostSectionOpened, isNull);
      expect(find.byTooltip('Delete'), findsNothing);
      expect(
        tester.widget<TaskTimerPanel>(find.byType(TaskTimerPanel)).onToggle,
        isNull,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final boundary in ['account', 'epoch', 'deletion', 'locked']) {
    testWidgets('$boundary boundary still closes old task draft', (
      tester,
    ) async {
      final controller = _Controller();
      await _mount(tester, controller);
      await tester.enterText(_notes, 'Private old-session draft');
      if (boundary == 'epoch') controller.epoch = 'new-session-epoch';
      controller.replace(
        _state(
          session: boundary == 'account' ? sharingSession(second: true) : null,
          deletion: boundary == 'deletion',
          localAccess: boundary != 'locked',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(_notes, findsNothing);
      expect(find.text('Private old-session draft'), findsNothing);
      expect(controller.saves, 0);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('initial viewer preview never becomes a local editing form', (
    tester,
  ) async {
    final controller = _Controller(initial: _state(viewer: true));
    await _mount(tester, controller, preview: true);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Shared base'), findsOneWidget);
    expect(_notes, findsNothing);
    expect(
      find.byKey(const ValueKey('organizer-local-draft-only')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('organizer-save')), findsNothing);
    expect(controller.saves, 0);
    expect(controller.financePreparations, 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'same-account epoch change during policy await blocks old task save',
    (tester) async {
      final controller = _Controller();
      await _mount(tester, controller);
      await tester.enterText(_notes, 'Old epoch unsaved notes');
      final policy = await controller.sharedContentPolicy(
        scopeId: sharingScopeId,
      );
      final gate = controller.policyGate = Completer<SharedContentPolicy>();
      await tester.tap(find.byKey(const ValueKey('organizer-save')));
      await tester.pump();
      expect(controller.saves, 0);
      controller.epoch = 'new-epoch-while-policy-pending';
      gate.complete(policy);
      await tester.pumpAndSettle();
      expect(controller.saves, 0);
      expect(controller.timers, 0);
      controller.replace(_state());
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Old epoch unsaved notes'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
