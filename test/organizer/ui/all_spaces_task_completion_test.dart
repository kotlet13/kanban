import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/presentation/all_spaces/all_spaces_page.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';

import 'all_spaces_ui_test.dart'
    show AllSpacesController, pumpAll, sharedData, secondScope;
import 'sharing_ui_fixture.dart';

class CompletingController extends AllSpacesController {
  CompletingController({super.initial});
  final completions = <(String, String, bool)>[];
  Completer<void>? gate;

  @override
  Future<void> setTaskCompleted(String scopeId, String id, bool value) async {
    completions.add((scopeId, id, value));
    await gate?.future;
    final old = state.requireValue;
    final data = old.dataForScope(scopeId);
    replace(
      CollaborationState(
        session: old.session,
        selectedSpaceId: old.selectedSpaceId,
        allSpacesSelected: old.allSpacesSelected,
        scopes: old.scopes,
        data: {
          ...old.data,
          scopeId: SharedScopeData(
            projects: data.projects,
            tasks: data.tasks.map(
              (t) => t.id == id ? t.copyWith(isCompleted: value) : t,
            ),
          ),
        },
      ),
    );
  }
}

Finder taskCheckbox(String title) => find.descendant(
  of: find.ancestor(of: find.text(title), matching: find.byType(Card)).first,
  matching: find.byType(Checkbox),
);

void main() {
  testWidgets(
    'aggregate circle completes exact source and can reopen without navigating',
    (tester) async {
      final shared = CompletingController();
      await pumpAll(tester, area: AllSpacesArea.tasks, shared: shared);
      await tester.tap(taskCheckbox('QA skupno opravilo'));
      await tester.pumpAndSettle();
      expect(shared.completions, [(sharingScopeId, 'same-task', true)]);
      expect(find.text('QA skupno opravilo'), findsNothing);
      expect(find.text('QA preveri izvajalca'), findsOneWidget);
      expect(
        shared.state.requireValue
            .dataForScope(secondScope.id)
            .tasks
            .single
            .isCompleted,
        isFalse,
      );
      expect(shared.state.requireValue.allSpacesSelected, isTrue);
      expect(shared.opened, isEmpty);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Opravljeno'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Checkbox>(taskCheckbox('QA skupno opravilo')).value,
        isTrue,
      );
      await tester.tap(taskCheckbox('QA skupno opravilo'));
      await tester.pumpAndSettle();
      expect(shared.completions.last, (sharingScopeId, 'same-task', false));
      expect(find.text('QA skupno opravilo'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('aggregate reader sees disabled completion and no write', (
    tester,
  ) async {
    final initial = sharedData();
    final shared = CompletingController(
      initial: CollaborationState(
        session: initial.session,
        allSpacesSelected: true,
        scopes: [
          SharedScope(
            id: sharingScopeId,
            name: 'Dom',
            kind: SharedScopeKind.household,
            role: SharedRole.viewer,
          ),
          secondScope,
        ],
        data: initial.data,
      ),
    );
    await pumpAll(tester, area: AllSpacesArea.tasks, shared: shared);
    expect(
      tester.widget<Checkbox>(taskCheckbox('QA skupno opravilo')).onChanged,
      isNull,
    );
    await tester.tap(taskCheckbox('QA skupno opravilo'));
    await tester.pumpAndSettle();
    expect(shared.completions, isEmpty);
  });

  testWidgets('rapid completion taps enqueue only one action while saving', (
    tester,
  ) async {
    final shared = CompletingController()..gate = Completer<void>();
    await pumpAll(tester, area: AllSpacesArea.tasks, shared: shared);
    await tester.tap(taskCheckbox('QA skupno opravilo'));
    await tester.pump();
    await tester.pump();
    await tester.tap(taskCheckbox('QA skupno opravilo'));
    await tester.pump();
    expect(shared.completions.length, 1);
    shared.gate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('QA skupno opravilo'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
