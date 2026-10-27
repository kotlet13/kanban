import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/l10n/app_localizations.dart';
import 'package:kanban/organizer/domain/draft_three_way_merge.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'package:kanban/organizer/presentation/organizer_editors.dart';

Future<void> _open(
  WidgetTester tester,
  OrganizerDraft draft,
  OrganizerEditorUpdates updates,
  Future<void> Function(OrganizerDraft) save,
) async {
  tester.view.physicalSize = const Size(600, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showOrganizerEditor(
              context,
              heading: 'Task',
              kind: OrganizerEditorKind.task,
              draft: draft,
              updates: updates,
              onSave: save,
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const ValueKey('organizer-title-field')),
    'My title',
  );
}

Future<void> _review(WidgetTester tester) async {
  await tester.ensureVisible(
    find.byKey(const ValueKey('organizer-review-latest')),
  );
  await tester.tap(find.byKey(const ValueKey('organizer-review-latest')));
  await tester.pumpAndSettle();
}

Future<void> _apply(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('draft-apply-review')));
  await tester.pumpAndSettle();
}

void main() {
  test(
    'three-way comparison merges separate changes and requires explicit same-field choices',
    () {
      final comparison = DraftThreeWayMerge(
        base: {'title': 'Old', 'notes': 'Base'},
        mine: {'title': 'Mine', 'notes': 'Base'},
        latest: {'title': 'Old', 'notes': 'New'},
      );
      expect(comparison.conflicts, isEmpty);
      expect(comparison.resolve({}), {'title': 'Mine', 'notes': 'New'});
      final conflict = DraftThreeWayMerge(
        base: {
          'cost': ['EUR', 'A', 10],
        },
        mine: {
          'cost': ['USD', 'B', 20],
        },
        latest: {
          'cost': ['EUR', 'C', 30],
        },
      );
      expect(conflict.resolve({}), isNull);
      expect(conflict.resolve({'cost': true}), {
        'cost': ['USD', 'B', 20],
      });
      expect(conflict.resolve({'cost': false}), {
        'cost': ['EUR', 'C', 30],
      });
    },
  );

  testWidgets(
    'dirty task reviews separate changes and advances latest base only after apply',
    (tester) async {
      final draft = OrganizerDraft(title: 'Original', notes: 'Base notes');
      final updates = OrganizerEditorUpdates();
      var accepted = 0;
      OrganizerDraft? saved;
      await _open(tester, draft, updates, (value) async => saved = value);
      updates.replaceDraft(
        OrganizerDraft(title: 'Original', notes: 'Latest notes'),
        () => accepted++,
      );
      await tester.pumpAndSettle();
      expect(draft.title, 'My title');
      expect(accepted, 0);
      await _review(tester);
      expect(find.textContaining('Original: Original'), findsOneWidget);
      expect(find.textContaining('My draft: My title'), findsOneWidget);
      expect(find.textContaining('Latest: Latest notes'), findsOneWidget);
      await _apply(tester);
      expect(accepted, 1);
      expect(
        find.byKey(const ValueKey('organizer-newer-version')),
        findsNothing,
      );
      await tester.tap(find.byKey(const ValueKey('organizer-save')));
      await tester.pumpAndSettle();
      expect(saved?.title, 'My title');
      expect(saved?.notes, 'Latest notes');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'same title conflicts require explicit choice and cancel preserves draft',
    (tester) async {
      final draft = OrganizerDraft(title: 'Original');
      final updates = OrganizerEditorUpdates();
      var accepted = 0, saves = 0;
      await _open(tester, draft, updates, (_) async => saves++);
      updates.replaceDraft(
        OrganizerDraft(title: 'Latest title'),
        () => accepted++,
      );
      await tester.pumpAndSettle();
      await _review(tester);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('draft-apply-review')),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();
      expect(draft.title, 'My title');
      expect(accepted, 0);
      await tester.tap(find.byKey(const ValueKey('organizer-save')));
      await tester.pumpAndSettle();
      expect(saves, 0);
      await tester.tap(find.byKey(const ValueKey('draft-keep-mine-title')));
      await tester.pump();
      await _apply(tester);
      expect(accepted, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a newer replacement during review closes review without advancing base',
    (tester) async {
      final draft = OrganizerDraft(title: 'Original');
      final updates = OrganizerEditorUpdates();
      var accepted = 0;
      await _open(tester, draft, updates, (_) async {});
      updates.replaceDraft(OrganizerDraft(title: 'Second'), () => accepted++);
      await tester.pumpAndSettle();
      await _review(tester);
      updates.replaceDraft(OrganizerDraft(title: 'Third'), () => accepted++);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('draft-apply-review')), findsNothing);
      expect(accepted, 0);
      expect(draft.title, 'My title');
      expect(
        find.text(
          'The task or access changed during review. Your draft is preserved. Review the latest changes again.',
        ),
        findsOneWidget,
      );
      await _review(tester);
      expect(find.textContaining('Latest: Third'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'access change during compare removes sensitive review and preserves draft',
    (tester) async {
      final draft = OrganizerDraft(title: 'Original');
      var current = true;
      final updates = OrganizerEditorUpdates()..isCurrent = () => current;
      var accepted = 0;
      await _open(tester, draft, updates, (_) async {});
      updates.replaceDraft(OrganizerDraft(title: 'Latest'), () => accepted++);
      await tester.pumpAndSettle();
      await _review(tester);
      current = false;
      updates.editingAllowed = false;
      updates.costVisible = false;
      updates.financeChanged();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('draft-apply-review')), findsNothing);
      expect(accepted, 0);
      expect(draft.title, 'My title');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'task-only access hides latest financial values and cannot discard edited cost',
    (tester) async {
      final draft = OrganizerDraft(
        title: 'Original',
        costEnabled: true,
        costAmount: '5',
      );
      final updates = OrganizerEditorUpdates()..costVisible = false;
      var accepted = 0;
      await _open(tester, draft, updates, (_) async {});
      updates.replaceDraft(
        OrganizerDraft(
          title: 'Original',
          costEnabled: true,
          costAmount: 'SECRET-99',
          costCurrency: 'USD',
        ),
        () => accepted++,
      );
      await tester.pumpAndSettle();
      await _review(tester);
      expect(find.textContaining('SECRET-99'), findsNothing);
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();
      draft.costAmount = '6';
      await _review(tester);
      expect(find.byKey(const ValueKey('draft-apply-review')), findsNothing);
      expect(accepted, 0);
      expect(draft.costAmount, '6');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'cost choice stays atomic while latest posted history and operational timer remain authoritative',
    (tester) async {
      final draft = OrganizerDraft(
        title: 'Original',
        costEnabled: true,
        costAmount: '5',
        timer: const TaskTimerState(elapsedSeconds: 1),
      );
      final updates = OrganizerEditorUpdates()..costEditingEnabled = true;
      OrganizerDraft? saved;
      var accepted = 0;
      await _open(tester, draft, updates, (value) async => saved = value);
      await tester.ensureVisible(
        find.byKey(const ValueKey('task-cost-amount')),
      );
      await tester.enterText(
        find.byKey(const ValueKey('task-cost-amount')),
        '6',
      );
      updates.replaceDraft(
        OrganizerDraft(
          title: 'Original',
          costEnabled: true,
          costAmount: '7',
          costCurrency: 'USD',
          costWasPaid: true,
          timer: const TaskTimerState(elapsedSeconds: 100),
        ),
        () => accepted++,
      );
      await tester.pumpAndSettle();
      await _review(tester);
      expect(find.byKey(const ValueKey('draft-keep-mine-timer')), findsNothing);
      expect(find.textContaining('Previously posted:'), findsNWidgets(3));
      await tester.ensureVisible(
        find.byKey(const ValueKey('draft-keep-mine-cost')),
      );
      await tester.tap(find.byKey(const ValueKey('draft-keep-mine-cost')));
      await tester.pump();
      await _apply(tester);
      expect(accepted, 1);
      await tester.ensureVisible(find.byKey(const ValueKey('organizer-save')));
      await tester.tap(find.byKey(const ValueKey('organizer-save')));
      await tester.pumpAndSettle();
      expect(saved?.costAmount, '6');
      expect(saved?.costCurrency, 'EUR');
      expect(saved?.costWasPaid, isTrue);
      expect(saved?.timer.elapsedSeconds, 100);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'finance readiness loss invalidates review even while task write permission remains',
    (tester) async {
      final draft = OrganizerDraft(title: 'Original');
      final updates = OrganizerEditorUpdates()..costEditingEnabled = true;
      var accepted = 0;
      await _open(tester, draft, updates, (_) async {});
      updates.replaceDraft(OrganizerDraft(title: 'Latest'), () => accepted++);
      await tester.pumpAndSettle();
      await _review(tester);
      updates.financeUnavailable = true;
      updates.financeChanged();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('draft-apply-review')), findsNothing);
      expect(accepted, 0);
      expect(draft.title, 'My title');
      expect(updates.editingAllowed, isTrue);
      expect(tester.takeException(), isNull);
    },
  );
}
