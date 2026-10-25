import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/l10n/app_localizations.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'package:kanban/organizer/presentation/shared/collaboration_actions.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';

import 'shared_task_save_event_regression_test.dart'
    show child, childId, org, orgId, finance;
import 'sharing_ui_fixture.dart';

final _date = DateTime.utc(2026, 10, 24);
final _task = LocalTask(
  id: '10000000-0000-4000-8000-000000000004',
  revision: 1,
  title: 'Downloaded task',
  notes: 'Original note',
  projectId: childId,
  dueAt: null,
  isCompleted: false,
  createdAt: _date,
  updatedAt: _date,
);
final _cost = SharedFinanceEntry(
  id: '10000000-0000-4000-8000-000000000005',
  revision: 3,
  accountId: '10000000-0000-4000-8000-000000000006',
  accountScopeId: orgId,
  taskId: _task.id,
  kind: FinanceEntryKind.expense,
  status: SharedFinanceStatus.planned,
  amountMinor: 1500,
  currency: 'EUR',
  title: _task.title,
  occurredAt: _date,
  createdAt: _date,
  updatedAt: _date,
);

CollaborationState _state({
  LocalTask? task,
  SharedFinanceEntry? cost,
  bool costReadable = true,
  AccountSession? session,
  SharedScope? project,
  Map<String, String?> creators = const {},
}) => CollaborationState(
  session: session ?? sharingSession(),
  scopes: [org, project ?? child],
  selectedSpaceId: childId,
  organizationFinanceSupported: true,
  financeSupported: true,
  financeContractVersion: 3,
  recordContractVersion: 6,
  financePolicies: {
    childId: costReadable ? finance : const SharedFinancePolicy(),
  },
  financeSnapshotComplete: {childId: costReadable},
  financeAccountChoices: {
    childId: [
      SharedFinanceAccountChoice(
        scopeId: orgId,
        id: _cost.accountId,
        name: 'Project account',
        currency: 'EUR',
      ),
    ],
  },
  data: {
    childId: SharedScopeData(
      recordCreators: creators,
      tasks: [task ?? _task],
      financeEntries: [cost ?? _cost],
    ),
  },
);

class _Controller extends SharingUiController {
  _Controller({CollaborationState? initial})
    : super(initial: initial ?? _state());
  final preparation = Completer<void>();
  int preparationCalls = 0;
  int taskSaves = 0;
  int pairedSaves = 0;
  LocalTask? saved;
  TaskCostDraft? savedCost;
  int? expectedFinanceRevision;

  @override
  Future<void> refreshFinanceAccountChoices(String scopeId) {
    expect(scopeId, childId);
    preparationCalls++;
    return preparation.future;
  }

  @override
  Future<void> updateTask(String scopeId, LocalTask task) async {
    expect(scopeId, childId);
    taskSaves++;
    saved = task;
  }

  @override
  Future<void> saveTaskWithCost(
    String scopeId,
    LocalTask task, {
    bool isNew = false,
    TaskCostDraft? cost,
    bool removeCost = false,
    int? expectedFinanceRevision,
  }) async {
    pairedSaves++;
    saved = task;
    savedCost = cost;
    this.expectedFinanceRevision = expectedFinanceRevision;
  }
}

Future<VoidCallback> _mount(WidgetTester tester, _Controller controller) async {
  tester.view.physicalSize = const Size(480, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  late VoidCallback open;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [collaborationProvider.overrideWith(() => controller)],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) {
              final state = ref.watch(collaborationProvider).valueOrNull;
              if (state == null) return const SizedBox.shrink();
              open = () => unawaited(
                CollaborationActions(
                  context,
                  ref,
                  state.scopes.singleWhere((scope) => scope.id == childId),
                  state.dataForScope(childId),
                ).task(task: state.dataForScope(childId).tasks.single),
              );
              return TextButton(onPressed: open, child: const Text('Open'));
            },
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return () => open();
}

String _text(WidgetTester tester, String key) => tester
    .widget<EditableText>(
      find.descendant(
        of: find.byKey(ValueKey(key)),
        matching: find.byType(EditableText),
      ),
    )
    .controller
    .text;

Future<void> _save(WidgetTester tester) async {
  tester.testTextInput.hide();
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('organizer-save')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'task-cost policy regression viewer creator can edit own financial cost',
    (tester) async {
      final own = sharingSession().accountId;
      final activeViewer = SharedScope.fromJson({
        ...child.toJson(),
        'role': 'viewer',
        'recordPolicyVersion': 1,
      });
      final controller = _Controller(
        initial: _state(
          project: activeViewer,
          creators: {'content:${_task.id}': own, 'finance:${_cost.id}': own},
        ),
      );
      final open = await _mount(tester, controller);
      open();
      await tester.pumpAndSettle();
      controller.preparation.complete();
      await tester.pumpAndSettle();
      final amount = find.byKey(const ValueKey('task-cost-amount'));
      expect(tester.widget<TextFormField>(amount).enabled, isTrue);
      await tester.ensureVisible(amount);
      await tester.enterText(amount, '17.00');
      await _save(tester);
      expect(controller.pairedSaves, 1);
      expect(controller.savedCost!.amountMinor, 1700);
      expect(controller.taskSaves, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'task-cost policy regression assignee preserves readonly foreign cost in task-only save',
    (tester) async {
      final own = sharingSession().accountId;
      const foreign = '10000000-0000-4000-8000-000000000009';
      final activeViewer = SharedScope.fromJson({
        ...child.toJson(),
        'role': 'viewer',
        'recordPolicyVersion': 1,
      });
      final controller = _Controller(
        initial: _state(
          project: activeViewer,
          task: _task.copyWith(assigneeAccountIds: [own]),
          creators: {
            'content:${_task.id}': foreign,
            'finance:${_cost.id}': foreign,
          },
        ),
      );
      final open = await _mount(tester, controller);
      open();
      await tester.pumpAndSettle();
      controller.preparation.complete();
      await tester.pumpAndSettle();
      final amount = find.byKey(const ValueKey('task-cost-amount'));
      expect(amount, findsNothing);
      expect(find.textContaining('15.00 EUR'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('organizer-notes-field')),
        'Assigned task note',
      );
      await _save(tester);
      expect(controller.taskSaves, 1);
      expect(controller.saved!.notes, 'Assigned task note');
      expect(controller.pairedSaves, 0);
      expect(controller.savedCost, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'downloaded task paints first frame and saves while finance really waits; duplicate open coalesces',
    (tester) async {
      final controller = _Controller();
      final open = await _mount(tester, controller);
      final began = tester.binding.clock.now();
      open();
      open();
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(_text(tester, 'organizer-title-field'), _task.title);
      expect(
        tester
            .getSize(find.byKey(const ValueKey('organizer-title-field')))
            .height,
        greaterThan(0),
      );
      expect(
        tester.binding.clock.now().difference(began),
        const Duration(milliseconds: 16),
      );
      expect(controller.preparationCalls, 1);
      expect(controller.preparation.isCompleted, isFalse);
      expect(
        find.byKey(const ValueKey('organizer-finance-loading')),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const ValueKey('organizer-notes-field')),
        'Local note while offline',
      );
      await _save(tester);
      expect(controller.taskSaves, 1);
      expect(
        controller.pairedSaves,
        0,
        reason: 'Text save must preserve a linked finance record',
      );
      expect(controller.saved!.notes, 'Local note while offline');
      expect(find.byType(AlertDialog), findsNothing);
      controller.preparation.complete();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'pristine task follows newer local snapshot; dirty draft keeps its save base and newer notice',
    (tester) async {
      final controller = _Controller();
      final open = await _mount(tester, controller);
      open();
      await tester.pumpAndSettle();
      final second = _task.copyWith(
        title: 'New title',
        notes: 'New shared note',
        revision: 2,
      );
      controller.replace(_state(task: second));
      await tester.pumpAndSettle();
      expect(_text(tester, 'organizer-title-field'), 'New title');
      expect(_text(tester, 'organizer-notes-field'), 'New shared note');
      expect(
        find.byKey(const ValueKey('organizer-newer-version')),
        findsNothing,
      );
      await tester.enterText(
        find.byKey(const ValueKey('organizer-notes-field')),
        'Unsaved note',
      );
      controller.replace(
        _state(task: second.copyWith(notes: 'Third shared note', revision: 3)),
      );
      await tester.pumpAndSettle();
      expect(_text(tester, 'organizer-notes-field'), 'Unsaved note');
      expect(
        find.byKey(const ValueKey('organizer-newer-version')),
        findsOneWidget,
      );
      controller.preparation.complete();
      await tester.pumpAndSettle();
      expect(_text(tester, 'organizer-notes-field'), 'Unsaved note');
      await _save(tester);
      expect(
        controller.saved!.revision,
        2,
        reason: 'A dirty editor must not silently rebase over revision 3',
      );
      expect(controller.saved!.notes, 'Unsaved note');
      expect(controller.pairedSaves, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'failed finance preparation disables only cost and preserves task draft',
    (tester) async {
      final controller = _Controller();
      final open = await _mount(tester, controller);
      open();
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('organizer-notes-field')),
        'Keep this note',
      );
      controller.preparation.completeError(StateError('offline'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('organizer-finance-unavailable')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('task-cost-amount')), findsNothing);
      expect(_text(tester, 'organizer-notes-field'), 'Keep this note');
      await _save(tester);
      expect(controller.saved!.notes, 'Keep this note');
      expect(controller.taskSaves, 1);
      expect(controller.pairedSaves, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'finance read loss hides cost while ordinary dirty task remains editable',
    (tester) async {
      final controller = _Controller();
      final open = await _mount(tester, controller);
      open();
      await tester.pumpAndSettle();
      controller.preparation.complete();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('task-cost-amount')), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('organizer-notes-field')),
        'Keep private task edits',
      );
      controller.replace(_state(costReadable: false));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('task-cost-amount')), findsNothing);
      expect(_text(tester, 'organizer-notes-field'), 'Keep private task edits');
      await _save(tester);
      expect(controller.saved!.notes, 'Keep private task edits');
      expect(controller.taskSaves, 1);
      expect(controller.pairedSaves, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'changed cost still uses paired save and exact original finance revision',
    (tester) async {
      final controller = _Controller();
      final open = await _mount(tester, controller);
      open();
      await tester.pumpAndSettle();
      controller.preparation.complete();
      await tester.pumpAndSettle();
      final amount = find.byKey(const ValueKey('task-cost-amount'));
      await tester.ensureVisible(amount);
      await tester.enterText(amount, '17.00');
      await _save(tester);
      expect(controller.taskSaves, 0);
      expect(controller.pairedSaves, 1);
      expect(controller.savedCost!.amountMinor, 1700);
      expect(controller.savedCost!.accountScopeId, orgId);
      expect(controller.expectedFinanceRevision, 3);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('closing pending editor ignores late finance completion', (
    tester,
  ) async {
    final controller = _Controller();
    final open = await _mount(tester, controller);
    open();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    controller.preparation.complete();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(controller.taskSaves, 0);
    expect(tester.takeException(), isNull);
  });
}
