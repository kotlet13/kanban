import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/l10n/app_localizations.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'package:kanban/organizer/presentation/shared/collaboration_actions.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';
import 'sharing_ui_fixture.dart';

const orgId = '10000000-0000-4000-8000-000000000002';
const childId = '10000000-0000-4000-8000-000000000003';
const org = SharedScope(
  id: '10000000-0000-4000-8000-000000000002',
  name: 'Mobile E2EE 20261018',
  kind: SharedScopeKind.organization,
  role: SharedRole.owner,
  accessPolicyVersion: 3,
);
const child = SharedScope(
  id: '10000000-0000-4000-8000-000000000003',
  name: 'MOBILE-PROJECT-1',
  kind: SharedScopeKind.project,
  role: SharedRole.owner,
  parentScopeId: orgId,
  organizationId: orgId,
  accessPolicyVersion: 3,
);
const finance = SharedFinancePolicy(
  enabled: true,
  grant: SharedFinanceGrant.write,
  revision: 1,
  managedByOrganizationPolicy: true,
);
CollaborationState fixtureState() => CollaborationState(
  session: sharingSession(),
  scopes: const [org, child],
  selectedSpaceId: child.id,
  organizationFinanceSupported: true,
  financeSupported: true,
  financeContractVersion: 3,
  recordContractVersion: 6,
  financePolicies: const {childId: finance},
  financeSnapshotComplete: const {childId: true},
  data: {child.id: SharedScopeData()},
);

class SaveController extends SharingUiController {
  SaveController({this.saveGate}) : super(initial: fixtureState());
  final Future<void>? saveGate;
  int creates = 0;
  String? savedTitle, savedNote;
  @override
  Future<void> refreshFinanceAccountChoices(String scopeId) async {}
  @override
  Future<String> createTask({
    required String scopeId,
    required String title,
    String notes = '',
    String? projectId,
    DateTime? dueAt,
    DateTime? startAt,
    DateTime? endAt,
    Iterable<String> assigneeAccountIds = const [],
    String? assigneePersonId,
    Iterable<String> subjectPersonIds = const [],
    String? phaseId,
    int? estimateMinutes,
    int? availabilityMinutes,
    AvailabilityPeriod? availabilityPeriod,
    TaskTimerState timer = const TaskTimerState(),
  }) async {
    expect(scopeId, child.id);
    expect(projectId, child.id);
    creates++;
    savedTitle = title;
    savedNote = notes;
    if (saveGate != null) await saveGate;
    return '10000000-0000-4000-8000-000000000004';
  }
}

void main() {
  testWidgets('real shared child task Save dispatches once and closes editor', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = SaveController();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [collaborationProvider.overrideWith(() => controller)],
        child: MaterialApp(
          locale: const Locale('sl'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(platform: TargetPlatform.android),
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) {
                final state = ref.watch(collaborationProvider).valueOrNull;
                return TextButton(
                  onPressed: state == null
                      ? null
                      : () => CollaborationActions(
                          context,
                          ref,
                          child,
                          state.dataForScope(child.id),
                        ).task(),
                  child: const Text('Open shared task'),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open shared task'));
    await tester.pumpAndSettle();
    expect(
      tester.takeException(),
      isNull,
      reason: 'Opening real editor must not throw',
    );
    await tester.enterText(
      find.byKey(const ValueKey('organizer-title-field')),
      'MOBILE-SHARED-1',
    );
    await tester.enterText(
      find.byKey(const ValueKey('organizer-notes-field')),
      'FROM-A-20261018',
    );
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    final save = find.byKey(const ValueKey('organizer-save'));
    expect(save.hitTestable(), findsOneWidget);
    await tester.tapAt(tester.getCenter(save));
    await tester.pumpAndSettle();
    expect(
      tester.takeException(),
      isNull,
      reason: 'Includes validation/Form.save before _save catch',
    );
    expect(controller.creates, 1);
    expect(controller.savedTitle, 'MOBILE-SHARED-1');
    expect(controller.savedNote, 'FROM-A-20261018');
    expect(find.byType(AlertDialog), findsNothing);
  });
  testWidgets(
    'async shared task Save error is visible and announced without losing draft',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final semantics = tester.ensureSemantics();
      try {
        final gate = Completer<void>();
        final controller = SaveController(saveGate: gate.future);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [collaborationProvider.overrideWith(() => controller)],
            child: MaterialApp(
              locale: const Locale('sl'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              theme: ThemeData(platform: TargetPlatform.android),
              home: Scaffold(
                body: Consumer(
                  builder: (context, ref, _) {
                    final state = ref.watch(collaborationProvider).valueOrNull;
                    return TextButton(
                      onPressed: state == null
                          ? null
                          : () => CollaborationActions(
                              context,
                              ref,
                              child,
                              state.dataForScope(child.id),
                            ).task(),
                      child: const Text('Open shared task'),
                    );
                  },
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Open shared task'));
        await tester.pumpAndSettle();
        final title = find.byKey(const ValueKey('organizer-title-field'));
        final notes = find.byKey(const ValueKey('organizer-notes-field'));
        await tester.enterText(title, 'MOBILE-SHARED-1');
        await tester.enterText(notes, 'FROM-A-20261018');
        tester.testTextInput.hide();
        await tester.pumpAndSettle();
        final scrollable = find.descendant(
          of: find.byKey(const ValueKey('organizer-editor-scroll')),
          matching: find.byType(Scrollable),
        );
        final scrollPosition = tester
            .state<ScrollableState>(scrollable.first)
            .position;
        scrollPosition.jumpTo(scrollPosition.minScrollExtent);
        await tester.pump();
        final titleEditable = find.descendant(
          of: title,
          matching: find.byType(EditableText),
        );
        final noteEditable = find.descendant(
          of: notes,
          matching: find.byType(EditableText),
        );
        final titleController = tester
            .widget<EditableText>(titleEditable)
            .controller;
        final noteController = tester
            .widget<EditableText>(noteEditable)
            .controller;
        final noteSelection = noteController.selection;
        final save = find.byKey(const ValueKey('organizer-save'));
        expect(save.hitTestable(), findsOneWidget);
        await tester.tap(save);
        await tester.pump();
        expect(controller.creates, 1);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        final focusedWhileSaving = FocusManager.instance.primaryFocus;
        // Complete the actual awaited persistence future; a loading form cannot pass.
        gate.completeError(
          const CollaborationException('synthetic_save_failure'),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(controller.creates, 1);
        expect(controller.savedTitle, 'MOBILE-SHARED-1');
        expect(controller.savedNote, 'FROM-A-20261018');
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        const message = 'Dejanje ni uspelo. Preveri povezavo in poskusi znova.';
        expect(find.text(message), findsOneWidget);
        expect(
          find.text(message).hitTestable(),
          findsOneWidget,
          reason:
              'Async Save failure must be visible without scrolling the long form',
        );
        final announcement = find.ancestor(
          of: find.text(message),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Semantics && widget.properties.liveRegion == true,
          ),
        );
        expect(announcement, findsOneWidget);
        expect(
          tester.getSemantics(announcement),
          matchesSemantics(label: message, isLiveRegion: true),
        );
        expect(
          tester.widget<EditableText>(titleEditable).controller,
          same(titleController),
        );
        expect(
          tester.widget<EditableText>(noteEditable).controller,
          same(noteController),
        );
        expect(titleController.text, 'MOBILE-SHARED-1');
        expect(noteController.text, 'FROM-A-20261018');
        expect(noteController.selection, noteSelection);
        expect(FocusManager.instance.primaryFocus, same(focusedWhileSaving));
        final saveButton = find.descendant(
          of: save,
          matching: find.byType(IconButton),
        );
        expect(tester.widget<IconButton>(saveButton).onPressed, isNotNull);
        await tester.pump(const Duration(seconds: 1));
        expect(
          controller.creates,
          1,
          reason: 'Failure must not automatically resubmit',
        );
      } finally {
        semantics.dispose();
      }
    },
  );
}
