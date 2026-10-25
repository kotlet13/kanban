import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/l10n/app_localizations.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'package:kanban/organizer/presentation/shared/collaboration_actions.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';
import 'sharing_ui_fixture.dart';
import 'shared_task_save_event_regression_test.dart'
    show child, childId, org, orgId, finance;

final _date = DateTime.utc(2026, 10, 24);
final _task = LocalTask(
  id: '10000000-0000-4000-8000-000000000074',
  revision: 1,
  title: 'Plain task',
  notes: 'Original note',
  projectId: childId,
  dueAt: null,
  isCompleted: false,
  createdAt: _date,
  updatedAt: _date,
);
final _cost = SharedFinanceEntry(
  id: '10000000-0000-4000-8000-000000000075',
  revision: 3,
  accountId: '10000000-0000-4000-8000-000000000076',
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
  SharedFinancePolicy policy = finance,
  bool complete = true,
}) => CollaborationState(
  session: sharingSession(),
  scopes: const [org, child],
  selectedSpaceId: childId,
  organizationFinanceSupported: true,
  financeSupported: true,
  financeContractVersion: 3,
  recordContractVersion: 6,
  financePolicies: {childId: policy},
  financeSnapshotComplete: {childId: complete},
  financeAccountChoices: {
    childId: [
      SharedFinanceAccountChoice(
        scopeId: orgId,
        id: _cost.accountId,
        name: 'Cached parent account',
        currency: 'EUR',
      ),
    ],
  },
  data: {
    childId: SharedScopeData(
      tasks: [task ?? _task],
      financeEntries: cost == null ? [] : [cost],
    ),
  },
);

class _Controller extends SharingUiController {
  _Controller({CollaborationState? initial})
    : super(initial: initial ?? _state());
  final preparation = Completer<void>();
  int choiceCalls = 0, taskSaves = 0, pairedSaves = 0;
  LocalTask? saved;
  @override
  Future<void> refreshFinanceAccountChoices(String scopeId) {
    expect(scopeId, childId);
    choiceCalls++;
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
  }
}

Future<void> _open(WidgetTester tester, _Controller controller) async {
  tester.view.physicalSize = const Size(480, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
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
              return TextButton(
                onPressed: state == null
                    ? null
                    : () => unawaited(
                        CollaborationActions(
                          context,
                          ref,
                          child,
                          state.dataForScope(childId),
                        ).task(task: state.dataForScope(childId).tasks.single),
                      ),
                child: const Text('Open'),
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

Future<void> _toggleSection(WidgetTester tester) async {
  final tile = find.byKey(const ValueKey('task-cost-section'));
  await tester.ensureVisible(tile);
  await tester.tap(find.descendant(of: tile, matching: find.text('Task cost')));
  await tester.pumpAndSettle();
}

SwitchListTile _switch(WidgetTester tester) => tester.widget<SwitchListTile>(
  find.descendant(
    of: find.byKey(const ValueKey('task-cost-section')),
    matching: find.byType(SwitchListTile),
  ),
);
String _notes(WidgetTester tester) => tester
    .widget<EditableText>(
      find.descendant(
        of: find.byKey(const ValueKey('organizer-notes-field')),
        matching: find.byType(EditableText),
      ),
    )
    .controller
    .text;
Future<void> _note(WidgetTester tester, String text) async {
  final field = find.byKey(const ValueKey('organizer-notes-field'));
  await tester.ensureVisible(field);
  await tester.enterText(field, text);
  tester.testTextInput.hide();
  await tester.pumpAndSettle();
}

Future<void> _save(WidgetTester tester) async {
  tester.testTextInput.hide();
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('organizer-save')));
  await tester.pumpAndSettle();
}

Future<void> _close(WidgetTester tester) async {
  await tester.tap(find.text('Cancel'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'lazy plain task opens publishes and saves with zero selector preparation',
    (tester) async {
      final c = _Controller();
      await _open(tester, c);
      expect(c.choiceCalls, 0);
      expect(
        find.byKey(const ValueKey('organizer-finance-loading')),
        findsNothing,
      );
      c.replace(_state());
      await tester.pumpAndSettle();
      expect(c.choiceCalls, 0);
      await _note(tester, 'Plain offline draft');
      await _save(tester);
      expect(c.choiceCalls, 0);
      expect(c.taskSaves, 1);
      expect(c.pairedSaves, 0);
      expect(c.saved!.notes, 'Plain offline draft');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'first cost expansion prepares once and cached options never enable pending controls',
    (tester) async {
      final c = _Controller();
      await _open(tester, c);
      await _note(tester, 'Keep typed draft');
      await _toggleSection(tester);
      expect(c.choiceCalls, 1);
      expect(_switch(tester).onChanged, isNull);
      await _toggleSection(tester);
      await _toggleSection(tester);
      c.replace(_state());
      await tester.pumpAndSettle();
      expect(c.choiceCalls, 1);
      expect(_switch(tester).onChanged, isNull);
      c.preparation.complete();
      await tester.pumpAndSettle();
      expect(_switch(tester).onChanged, isNotNull);
      expect(_notes(tester), 'Keep typed draft');
      expect(c.choiceCalls, 1);
      await _close(tester);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'failed lazy preparation keeps cost disabled and ordinary task draft savable',
    (tester) async {
      final c = _Controller();
      await _open(tester, c);
      await _note(tester, 'Keep after selector failure');
      await _toggleSection(tester);
      c.preparation.completeError(const CollaborationException('network'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('organizer-finance-unavailable')),
        findsOneWidget,
      );
      expect(_switch(tester).onChanged, isNull);
      await _toggleSection(tester);
      await _toggleSection(tester);
      expect(c.choiceCalls, 1);
      await _save(tester);
      expect(c.taskSaves, 1);
      expect(c.pairedSaves, 0);
      expect(c.saved!.notes, 'Keep after selector failure');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'write downgrade during lazy preparation cannot authorize cached cost choices',
    (tester) async {
      final c = _Controller();
      await _open(tester, c);
      await _note(tester, 'Task remains writable');
      await _toggleSection(tester);
      c.replace(
        _state(
          policy: const SharedFinancePolicy(
            enabled: true,
            grant: SharedFinanceGrant.read,
            revision: 2,
            managedByOrganizationPolicy: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      c.preparation.complete();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('task-cost-section')), findsNothing);
      expect(_notes(tester), 'Task remains writable');
      await _save(tester);
      expect(c.taskSaves, 1);
      expect(c.pairedSaves, 0);
      expect(c.choiceCalls, 1);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'existing linked cost retains automatic preparation and local display',
    (tester) async {
      final c = _Controller(initial: _state(cost: _cost));
      await _open(tester, c);
      expect(c.choiceCalls, 1);
      expect(find.textContaining('15.00 EUR'), findsOneWidget);
      expect(find.byKey(const ValueKey('task-cost-amount')), findsNothing);
      await _note(tester, 'Preserve existing cost draft');
      c.preparation.complete();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('task-cost-amount')), findsOneWidget);
      expect(_notes(tester), 'Preserve existing cost draft');
      await _close(tester);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'pristine incoming linked cost starts deferred preparation when accepted',
    (tester) async {
      final c = _Controller();
      await _open(tester, c);
      expect(c.choiceCalls, 0);
      c.replace(_state(task: _task.copyWith(revision: 2), cost: _cost));
      await tester.pumpAndSettle();
      expect(c.choiceCalls, 1);
      expect(find.textContaining('15.00 EUR'), findsOneWidget);
      c.preparation.complete();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('task-cost-amount')), findsOneWidget);
      await _close(tester);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'dirty incoming linked cost keeps draft notice and does not prepare unaccepted replacement',
    (tester) async {
      final c = _Controller();
      await _open(tester, c);
      await _note(tester, 'Unsaved plain task');
      c.replace(
        _state(
          task: _task.copyWith(revision: 2, notes: 'Remote note'),
          cost: _cost,
        ),
      );
      await tester.pumpAndSettle();
      expect(c.choiceCalls, 0);
      expect(_notes(tester), 'Unsaved plain task');
      expect(
        find.byKey(const ValueKey('organizer-newer-version')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('task-cost-amount')), findsNothing);
      await _close(tester);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'denied finance hides cached cost and offers no preparation trigger',
    (tester) async {
      final c = _Controller(
        initial: _state(cost: _cost, policy: const SharedFinancePolicy()),
      );
      await _open(tester, c);
      expect(c.choiceCalls, 0);
      expect(find.byKey(const ValueKey('task-cost-section')), findsNothing);
      expect(find.textContaining('15.00 EUR'), findsNothing);
      expect(find.textContaining('Cached parent account'), findsNothing);
      expect(
        find.byKey(const ValueKey('organizer-finance-loading')),
        findsNothing,
      );
      await _note(tester, 'Only visible task fields');
      await _save(tester);
      expect(c.taskSaves, 1);
      expect(c.pairedSaves, 0);
      expect(c.saved!.notes, 'Only visible task fields');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'incomplete coverage offers neutral preparation without enabling or displaying cached finance',
    (tester) async {
      final c = _Controller(initial: _state(complete: false));
      await _open(tester, c);
      expect(c.choiceCalls, 0);
      expect(find.byKey(const ValueKey('task-cost-section')), findsOneWidget);
      await _note(tester, 'Keep cold draft');
      await _toggleSection(tester);
      expect(c.choiceCalls, 1);
      expect(find.byType(SwitchListTile), findsNothing);
      expect(find.textContaining('Cached parent account'), findsNothing);
      expect(find.byKey(const ValueKey('task-cost-amount')), findsNothing);
      c.preparation.complete();
      await tester.pumpAndSettle();
      expect(
        find.byType(SwitchListTile),
        findsNothing,
        reason: 'Selector success cannot assert complete finance coverage',
      );
      expect(_notes(tester), 'Keep cold draft');
      c.replace(_state());
      await tester.pumpAndSettle();
      expect(_switch(tester).onChanged, isNotNull);
      expect(c.choiceCalls, 1);
      expect(_notes(tester), 'Keep cold draft');
      await _close(tester);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'incomplete denied coverage exposes neither preparation nor cached linked cost',
    (tester) async {
      final c = _Controller(
        initial: _state(
          complete: false,
          cost: _cost,
          policy: const SharedFinancePolicy(),
        ),
      );
      await _open(tester, c);
      expect(c.choiceCalls, 0);
      expect(find.byKey(const ValueKey('task-cost-section')), findsNothing);
      expect(find.byType(SwitchListTile), findsNothing);
      expect(find.textContaining('15.00 EUR'), findsNothing);
      expect(find.textContaining('Cached parent account'), findsNothing);
      await _close(tester);
      expect(tester.takeException(), isNull);
    },
  );
}
