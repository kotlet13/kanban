import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/l10n/app_localizations.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'package:kanban/organizer/presentation/organizer_editors.dart';

void main() {
  testWidgets(
    'ordinary project change preserves inaccessible task cost selectors exactly',
    (tester) async {
      final date = DateTime.utc(2026, 10, 24);
      OrganizerDraft? saved;
      final projects = [
        for (final name in ['Project A', 'Project B'])
          LocalProject(
            id: name,
            title: name,
            description: '',
            createdAt: date,
            updatedAt: date,
          ),
      ];
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
                  projects: projects,
                  costEditingEnabled: false,
                  draft: OrganizerDraft(
                    title: 'Downloaded task',
                    projectId: 'Project A',
                    costEnabled: true,
                    costAmount: '15.00',
                    costCurrency: 'EUR',
                    ledgerAccountId: 'unavailable-account',
                    payerPersonId: 'original-payer',
                    recipientPersonId: 'original-recipient',
                  ),
                  onSave: (draft) async {
                    saved = draft;
                  },
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('organizer-project-field')),
      );
      await tester.tap(find.byKey(const ValueKey('organizer-project-field')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Project B').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('organizer-save')));
      await tester.pumpAndSettle();
      expect(saved, isNotNull);
      expect(saved!.projectId, 'Project B');
      expect(saved!.costEnabled, true);
      expect(saved!.costAmount, '15.00');
      expect(saved!.costCurrency, 'EUR');
      expect(saved!.ledgerAccountId, 'unavailable-account');
      expect(saved!.payerPersonId, 'original-payer');
      expect(saved!.recipientPersonId, 'original-recipient');
      expect(tester.takeException(), isNull);
    },
  );
}
