import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/l10n/app_localizations.dart';
import 'package:kanban/organizer/domain/all_spaces_projection.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'package:kanban/organizer/presentation/all_spaces/all_spaces_page.dart';
import 'package:kanban/organizer/presentation/finance/shared_finance_actions.dart';
import 'package:kanban/organizer/presentation/organizer_actions.dart';
import 'package:kanban/organizer/presentation/shared/collaboration_actions.dart';
import 'package:kanban/organizer/presentation/shared/sharing_workspace.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';
import 'package:kanban/organizer/state/organizer_provider.dart';

import 'sharing_ui_fixture.dart';
import 'shared_task_save_event_regression_test.dart' show finance;

final now = DateTime(2026, 10, 27, 12);
final task = LocalTask(
  id: '10000000-0000-4000-8000-000000000087',
  title: 'Preview consistently',
  notes: 'Read before choosing Edit',
  projectId: null,
  dueAt: now,
  isCompleted: false,
  createdAt: now,
  updatedAt: now,
);
const child = SharedScope(
  id: '10000000-0000-4000-8000-000000000088',
  name: 'Child project',
  kind: SharedScopeKind.project,
  parentScopeId: sharingScopeId,
  role: SharedRole.owner,
);
SharedScope parent(SharedScopeKind kind) => SharedScope(
  id: sharingScopeId,
  name: 'Selected parent',
  kind: kind,
  role: SharedRole.owner,
  accessPolicyVersion: 3,
);
CollaborationState stateFor(SharedScope scope, {bool twoLists = false}) =>
    CollaborationState(
      session: sharingSession(),
      scopes: [scope, child],
      selectedSpaceId: scope.id,
      spaceProjectMembershipSupported: true,
      organizationFinanceSupported: true,
      scopeArchivingSupported: true,
      financeSupported: true,
      financePolicies: {scope.id: finance, child.id: finance},
      financeSnapshotComplete: {scope.id: true, child.id: true},
      data: {
        scope.id: SharedScopeData(
          tasks: [task],
          shoppingLists: [
            LocalShoppingList(
              id: 'list',
              title: 'One list',
              createdAt: now,
              updatedAt: now,
            ),
            if (twoLists)
              LocalShoppingList(
                id: 'second-list',
                title: 'Other list',
                createdAt: now,
                updatedAt: now,
              ),
          ],
        ),
      },
    );

class Personal extends OrganizerController {
  Personal({this.withTask = false});
  final bool withTask;
  @override
  Future<OrganizerSnapshot> build() async =>
      OrganizerSnapshot(tasks: withTask ? [task] : []);
}

class Controller extends SharingUiController {
  Controller(CollaborationState initial) : super(initial: initial);
  int refreshes = 0;
  @override
  Future<NotificationOpenResult> refreshVisibleTaskTarget(
    NotificationTarget target,
  ) async {
    refreshes++;
    return NotificationOpenResult(
      status: NotificationOpenStatus.offline,
      target: target,
    );
  }
}

Future<void> mount(
  WidgetTester tester,
  Widget child, {
  List<Override> overrides = const [],
  double width = 480,
  double textScale = 1,
}) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        organizerClockProvider.overrideWithValue(() => now),
        ...overrides,
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final kind in [
    SharedScopeKind.household,
    SharedScopeKind.organization,
  ]) {
    for (final view in [SharingView.tasks, SharingView.timeline]) {
      testWidgets(
        '$kind $view aggregate creates directly in selected parent with children',
        (tester) async {
          final scope = parent(kind);
          final state = stateFor(scope);
          await mount(
            tester,
            SharingWorkspace(
              view: view,
              selectedScopeId: scope.id,
              onScopeSelected: (_) {},
              onConnect: () {},
              showScopePicker: false,
            ),
            overrides: [
              collaborationProvider.overrideWith(() => Controller(state)),
            ],
          );
          final aggregate = tester.widget<AllSpacesPage>(
            find.byType(AllSpacesPage),
          );
          expect(aggregate.creationScopeId, scope.id);
          await tester.tap(find.widgetWithIcon(OutlinedButton, Icons.add));
          await tester.pumpAndSettle();
          expect(find.text('Choose a space'), findsNothing);
          expect(
            find.byKey(const ValueKey('organizer-title-field')),
            findsOneWidget,
          );
          expect(
            find.text(view == SharingView.tasks ? 'Add task' : 'Add event'),
            findsWidgets,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final blocked in [false, true]) {
    testWidgets(
      'explicit creation target eligibility $blocked never falls back to child',
      (tester) async {
        final scope = parent(SharedScopeKind.household);
        final state = stateFor(scope);
        final sources = [
          for (final s in state.scopes)
            AllSpacesSource(
              canReadFinance: false,
              financeComplete: true,
              key: s.id,
              scope: s,
              session: state.session,
              data: SharedScopeData(),
            ),
        ];
        final created = <String?>[];
        await mount(
          tester,
          AllSpacesPage(
            area: AllSpacesArea.tasks,
            snapshot: AllSpacesSnapshot(sources),
            creationScopeId: scope.id,
            canCreateInSource: (source) =>
                source.scopeId != scope.id || !blocked,
            onCreateSource: (source) async => created.add(source.scopeId),
            onSource: (_, _, _) async {},
          ),
        );
        await tester.tap(find.widgetWithIcon(OutlinedButton, Icons.add));
        await tester.pumpAndSettle();
        expect(created, blocked ? isEmpty : [scope.id]);
        expect(find.byType(SimpleDialog), findsNothing);
      },
    );
  }

  testWidgets('all-spaces creation still requires explicit target choice', (
    tester,
  ) async {
    final scope = parent(SharedScopeKind.household);
    final state = stateFor(scope);
    final created = <String?>[];
    await mount(
      tester,
      AllSpacesPage(
        area: AllSpacesArea.tasks,
        snapshot: AllSpacesSnapshot([
          for (final s in state.scopes)
            AllSpacesSource(
              canReadFinance: false,
              financeComplete: true,
              key: s.id,
              scope: s,
              session: state.session,
              data: SharedScopeData(),
            ),
        ]),
        onCreateSource: (source) async => created.add(source.scopeId),
        onSource: (_, _, _) async {},
      ),
    );
    await tester.tap(find.widgetWithIcon(OutlinedButton, Icons.add));
    await tester.pumpAndSettle();
    expect(find.byType(SimpleDialog), findsOneWidget);
    expect(created, isEmpty);
    await tester.tap(find.text('Child project'));
    await tester.pumpAndSettle();
    expect(created, [child.id]);
  });

  testWidgets(
    'aggregate calendar can switch to timeline and back after changing period',
    (tester) async {
      final scope = parent(SharedScopeKind.household);
      final state = stateFor(scope);
      await mount(
        tester,
        AllSpacesPage(
          area: AllSpacesArea.calendar,
          allowCreation: false,
          snapshot: AllSpacesSnapshot([
            AllSpacesSource(
              canReadFinance: false,
              financeComplete: true,
              key: scope.id,
              scope: scope,
              session: state.session,
              data: SharedScopeData(tasks: [task]),
            ),
          ]),
          onSource: (_, _, _) async {},
        ),
      );
      expect(
        find.byKey(const ValueKey('shared-month-calendar')),
        findsOneWidget,
      );
      expect(find.text(task.title), findsOneWidget);
      await tester.tap(find.text('Timeline'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('shared-month-calendar')), findsNothing);
      await tester.tap(find.byTooltip('Next month'));
      await tester.pumpAndSettle();
      expect(find.text(task.title), findsNothing);
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('aggregate-calendar-view')),
          matching: find.text('Calendar'),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('shared-month-calendar')),
        findsOneWidget,
      );
      expect(find.text(task.title), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'parent finance creation opens selected parent editor without a second scope chooser',
    (tester) async {
      final scope = parent(SharedScopeKind.organization);
      final state = stateFor(scope);
      await mount(
        tester,
        Consumer(
          builder: (context, ref, _) {
            ref.watch(collaborationProvider);
            return TextButton(
              onPressed: () => unawaited(
                SharedFinanceActions(context, ref, scope, state).entry(),
              ),
              child: const Text('New finance'),
            );
          },
        ),
        overrides: [
          collaborationProvider.overrideWith(() => Controller(state)),
        ],
      );
      await tester.tap(find.text('New finance'));
      await tester.pumpAndSettle();
      expect(find.text('Choose where to add the entry'), findsNothing);
      expect(find.byType(SimpleDialog), findsNothing);
      expect(find.byType(TextFormField), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  for (final personal in [false, true]) {
    testWidgets(
      'editable ${personal ? 'personal' : 'shared'} task opens preview with explicit Edit',
      (tester) async {
        final scope = parent(SharedScopeKind.household);
        final controller = Controller(stateFor(scope));
        await mount(
          tester,
          Consumer(
            builder: (context, ref, _) {
              final shared = ref.watch(collaborationProvider).valueOrNull;
              final local = ref.watch(organizerProvider).valueOrNull;
              if (shared == null || local == null) {
                return const SizedBox.shrink();
              }
              return TextButton(
                onPressed: () => unawaited(
                  personal
                      ? OrganizerActions(context, ref, local).openTask(task)
                      : CollaborationActions(
                          context,
                          ref,
                          scope,
                          shared.dataForScope(scope.id),
                        ).openTask(task),
                ),
                child: const Text('Open task'),
              );
            },
          ),
          overrides: [
            collaborationProvider.overrideWith(() => controller),
            organizerProvider.overrideWith(() => Personal(withTask: personal)),
          ],
        );
        await tester.tap(find.text('Open task'));
        await tester.pumpAndSettle();
        expect(find.text(task.notes), findsOneWidget);
        expect(find.text('Edit task'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('organizer-title-field')),
          findsNothing,
        );
        expect(controller.refreshes, personal ? 0 : 1);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'shopping detail keeps only list overflow and sync without scope actions',
    (tester) async {
      final scope = parent(SharedScopeKind.household);
      final state = stateFor(scope);
      await mount(
        tester,
        SharingWorkspace(
          view: SharingView.shopping,
          selectedScopeId: scope.id,
          onScopeSelected: (_) {},
          onConnect: () {},
          showScopePicker: false,
        ),
        overrides: [
          collaborationProvider.overrideWith(() => Controller(state)),
        ],
      );
      expect(find.byKey(ValueKey('scope-lifecycle-${scope.id}')), findsNothing);
      expect(find.byIcon(Icons.more_horiz), findsOneWidget);
      expect(
        find.byKey(ValueKey('sharing-status-${scope.id}-SharingView.shopping')),
        findsOneWidget,
      );
      await tester.tap(find.byIcon(Icons.more_horiz));
      await tester.pumpAndSettle();
      expect(find.text('Edit list'), findsOneWidget);
      expect(find.text('Selected parent'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'compact shopping detail at 320px double text has one list menu and sync',
    (tester) async {
      final scope = parent(SharedScopeKind.household);
      final state = stateFor(scope);
      await mount(
        tester,
        SharingWorkspace(
          view: SharingView.shopping,
          selectedScopeId: scope.id,
          selectedListId: 'list',
          onScopeSelected: (_) {},
          onConnect: () {},
          showScopePicker: false,
        ),
        width: 320,
        textScale: 2,
        overrides: [
          collaborationProvider.overrideWith(() => Controller(state)),
        ],
      );
      expect(find.byIcon(Icons.more_horiz), findsOneWidget);
      expect(find.byKey(ValueKey('scope-lifecycle-${scope.id}')), findsNothing);
      expect(
        find.byKey(ValueKey('sharing-status-${scope.id}-SharingView.shopping')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'calendar empty selected day uses day-specific copy without claiming no space records',
    (tester) async {
      final scope = parent(SharedScopeKind.household);
      final state = stateFor(scope);
      await mount(
        tester,
        AllSpacesPage(
          area: AllSpacesArea.calendar,
          allowCreation: false,
          snapshot: AllSpacesSnapshot([
            AllSpacesSource(
              key: scope.id,
              scope: scope,
              session: state.session,
              data: SharedScopeData(tasks: [task]),
              canReadFinance: false,
              financeComplete: true,
            ),
          ]),
          onSource: (_, _, _) async {},
        ),
      );
      await tester.tap(
        find.byKey(const ValueKey('shared-calendar-day-2026-10-28')),
      );
      await tester.pumpAndSettle();
      final l = AppLocalizations.of(
        tester.element(find.byType(AllSpacesPage)),
      )!;
      expect(find.text(l.planningNoAgenda), findsOneWidget);
      expect(find.text(l.allSpacesEmpty), findsNothing);
      expect(find.text(task.title), findsNothing);
      expect(
        find.byKey(const ValueKey('aggregate-calendar-view')),
        findsOneWidget,
      );
    },
  );

  testWidgets('shared viewer preview stays readable and does not offer Edit', (
    tester,
  ) async {
    final scope = SharedScope.fromJson({
      ...parent(SharedScopeKind.household).toJson(),
      'role': 'viewer',
      'recordPolicyVersion': 1,
    });
    final controller = Controller(stateFor(scope));
    await mount(
      tester,
      Consumer(
        builder: (context, ref, _) {
          final shared = ref.watch(collaborationProvider).valueOrNull;
          final local = ref.watch(organizerProvider).valueOrNull;
          if (shared == null || local == null) return const SizedBox.shrink();
          return TextButton(
            onPressed: () => unawaited(
              CollaborationActions(
                context,
                ref,
                scope,
                shared.dataForScope(scope.id),
              ).openTask(task),
            ),
            child: const Text('Preview viewer task'),
          );
        },
      ),
      overrides: [
        collaborationProvider.overrideWith(() => controller),
        organizerProvider.overrideWith(Personal.new),
      ],
    );
    await tester.tap(find.text('Preview viewer task'));
    await tester.pumpAndSettle();
    expect(find.text(task.notes), findsOneWidget);
    expect(find.text('Edit task'), findsNothing);
    expect(find.byKey(const ValueKey('organizer-save')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('personal preview explicit Edit opens existing task editor', (
    tester,
  ) async {
    final controller = Controller(stateFor(parent(SharedScopeKind.household)));
    await mount(
      tester,
      Consumer(
        builder: (context, ref, _) {
          final shared = ref.watch(collaborationProvider).valueOrNull;
          final local = ref.watch(organizerProvider).valueOrNull;
          if (shared == null || local == null) return const SizedBox.shrink();
          return TextButton(
            onPressed: () =>
                unawaited(OrganizerActions(context, ref, local).openTask(task)),
            child: const Text('Preview then edit'),
          );
        },
      ),
      overrides: [
        collaborationProvider.overrideWith(() => controller),
        organizerProvider.overrideWith(() => Personal(withTask: true)),
      ],
    );
    await tester.tap(find.text('Preview then edit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit task'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('organizer-title-field')), findsOneWidget);
    expect(find.widgetWithText(TextField, task.title), findsOneWidget);
    expect(find.byKey(const ValueKey('organizer-save')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'shopping overview retains space actions while list detail removes them and Back restores overview',
    (tester) async {
      final scope = parent(SharedScopeKind.household);
      final state = stateFor(scope, twoLists: true);
      String? selected;
      await mount(
        tester,
        StatefulBuilder(
          builder: (context, setState) => SharingWorkspace(
            view: SharingView.shopping,
            selectedScopeId: scope.id,
            selectedListId: selected,
            onListSelected: (id) => setState(() => selected = id),
            onScopeSelected: (_) {},
            onConnect: () {},
            showScopePicker: false,
          ),
        ),
        overrides: [
          collaborationProvider.overrideWith(() => Controller(state)),
        ],
      );
      final spaceMenu = find.byKey(ValueKey('scope-lifecycle-${scope.id}'));
      expect(spaceMenu, findsOneWidget);
      await tester.tap(find.text('One list'));
      await tester.pumpAndSettle();
      expect(spaceMenu, findsNothing);
      expect(find.byIcon(Icons.more_horiz), findsOneWidget);
      expect(
        find.byKey(ValueKey('sharing-status-${scope.id}-SharingView.shopping')),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(TextButton, 'Shopping'));
      await tester.pumpAndSettle();
      expect(spaceMenu, findsOneWidget);
      expect(find.text('One list'), findsOneWidget);
      expect(find.text('Other list'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
