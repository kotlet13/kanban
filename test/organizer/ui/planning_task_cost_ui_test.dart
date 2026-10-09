import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'package:kanban/organizer/presentation/organizer_editors.dart';
import 'organizer_ui_test.dart'
    show MemoryOrganizerStorage, pumpOrganizer, mobileTab, saveTitle;

void main() {
  testWidgets(
    'local UI saves phase, estimate and linked planned cost then starts and pauses persistent timer',
    (tester) async {
      final store = MemoryOrganizerStorage(), now = DateTime.now().toUtc();
      store.snapshot = OrganizerSnapshot(
        projects: [
          LocalProject(
            id: 'project',
            title: 'Vrt',
            description: '',
            createdAt: now,
            updatedAt: now,
            phases: const [
              ProjectPhase(
                id: 'phase',
                title: 'Prva faza',
                milestone: 'Pripravljena greda',
              ),
            ],
          ),
        ],
      );
      await pumpOrganizer(tester, store, width: 390, height: 900);
      await tester.ensureVisible(
        find.widgetWithText(TextButton, 'Dodaj opravilo').first,
      );
      await tester.tap(find.widgetWithText(TextButton, 'Dodaj opravilo').first);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('organizer-title-field')),
        'Pripravi gredo',
      );
      final project = find.widgetWithText(
        DropdownButtonFormField<String>,
        'Brez projekta',
      );
      await tester.ensureVisible(project);
      await tester.tap(project);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Vrt').last);
      await tester.pumpAndSettle();
      final phase = find.widgetWithText(
        DropdownButtonFormField<String>,
        'Brez faze',
      );
      await tester.ensureVisible(phase);
      await tester.tap(phase);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Prva faza').last);
      await tester.pumpAndSettle();
      final estimate = find.byKey(const ValueKey('task-estimate'));
      await tester.ensureVisible(estimate);
      await tester.enterText(estimate, '60');
      await tester.ensureVisible(find.text('Strošek opravila'));
      await tester.tap(find.text('Strošek opravila'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Dodaj strošek'));
      await tester.tap(find.text('Dodaj strošek'));
      await tester.pumpAndSettle();
      final amount = find.byKey(const ValueKey('task-cost-amount'));
      await tester.ensureVisible(amount);
      await tester.enterText(amount, '12,50');
      await tester.tap(find.byKey(const ValueKey('organizer-save')));
      await tester.pumpAndSettle();
      expect(store.snapshot.tasks.single.phaseId, 'phase');
      expect(store.snapshot.tasks.single.estimateMinutes, 60);
      expect(
        store.snapshot.financeEntries.single.taskId,
        store.snapshot.tasks.single.id,
      );
      expect(store.snapshot.financeEntries.single.amountMinor, 1250);
      expect(
        store.snapshot.financeEntries.single.status,
        FinanceEntryStatus.planned,
      );
      expect(store.snapshot.financeEntries.single.plannedAt, isNull);
      expect(store.snapshot.balanceForCurrency('EUR'), 0);
      await tester.ensureVisible(find.text('Pripravi gredo'));
      await tester.tap(find.text('Pripravi gredo'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('task-timer-toggle')),
      );
      await tester.tap(find.byKey(const ValueKey('task-timer-toggle')));
      await tester.pumpAndSettle();
      expect(store.snapshot.tasks.single.timer.running, isTrue);
      await tester.pump(const Duration(seconds: 2));
      await tester.tap(find.byKey(const ValueKey('task-timer-toggle')));
      await tester.pumpAndSettle();
      expect(store.snapshot.tasks.single.timer.running, isFalse);
      await tester.tap(find.byKey(const ValueKey('organizer-save')));
      await tester.pumpAndSettle();
      expect(store.snapshot.tasks.single.isCompleted, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'project phase editor saves actual milestone and shows per-phase estimated hours',
    (tester) async {
      final store = MemoryOrganizerStorage();
      await pumpOrganizer(tester, store, width: 320);
      await mobileTab(tester, 'Projekti');
      await tester.tap(find.text('Nov projekt').first);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Faze in mejniki'));
      await tester.tap(find.text('Faze in mejniki'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('planning-add-phase')),
      );
      await tester.tap(find.byKey(const ValueKey('planning-add-phase')));
      await tester.pumpAndSettle();
      final phaseTitle = find.widgetWithText(TextFormField, 'Ime faze');
      await tester.ensureVisible(phaseTitle);
      await tester.enterText(phaseTitle, 'Priprava');
      final milestone = find.widgetWithText(TextFormField, 'Mejnik');
      await tester.ensureVisible(milestone);
      await tester.enterText(milestone, 'Greda pripravljena');
      await saveTitle(tester, 'Domači vrt');
      expect(store.snapshot.projects.single.phases.single.title, 'Priprava');
      await tester.tap(find.text('Domači vrt'));
      await tester.pumpAndSettle();
      expect(find.text('Greda pripravljena'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'shared-style task cost requires explicit ledger account and explains missing setup',
    (tester) async {
      await pumpOrganizer(tester, MemoryOrganizerStorage(), width: 320);
      var saved = 0;
      showOrganizerEditor(
        tester.element(find.byType(Scaffold).first),
        heading: 'Opravilo',
        kind: OrganizerEditorKind.task,
        draft: OrganizerDraft(
          title: 'Task',
          costEnabled: true,
          costAmount: '12.50',
        ),
        costEditingEnabled: true,
        costAccountRequired: true,
        onSave: (_) async {
          saved++;
        },
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Ustvari prvi finančni račun v tem prostoru.'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('organizer-save')));
      await tester.pumpAndSettle();
      expect(saved, 0);
      expect(find.text('Izberi finančni račun.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
