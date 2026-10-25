import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/l10n/app_localizations.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'package:kanban/organizer/presentation/shared/collaboration_actions.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';

import 'sharing_ui_fixture.dart';

class _Controller extends SharingUiController {
  _Controller({required CollaborationState initial}) : super(initial: initial);
  int saves = 0;
  @override
  Future<void> updateTask(String scopeId, LocalTask task) async {
    saves++;
  }
}

void main() {
  testWidgets(
    'record-only assignment loss keeps dirty task draft and disables saving while scope revoke still closes',
    (tester) async {
      final session = sharingSession();
      final date = DateTime.utc(2026, 10, 24);
      final scope = SharedScope.fromJson({
        ...sharingScope().toJson(),
        'recordPolicyVersion': 1,
        'role': 'viewer',
      });
      final original = LocalTask(
        id: '10000000-0000-4000-8000-000000000008',
        title: 'Assigned task',
        notes: 'Accepted note',
        projectId: null,
        dueAt: null,
        isCompleted: false,
        assigneeAccountIds: [session.accountId],
        createdAt: date,
        updatedAt: date,
        revision: 1,
      );
      CollaborationState state(LocalTask task, {bool revoked = false}) =>
          CollaborationState(
            session: session,
            scopes: [
              SharedScope.fromJson({...scope.toJson(), 'revoked': revoked}),
            ],
            selectedSpaceId: scope.id,
            recordContractVersion: 6,
            data: {
              scope.id: SharedScopeData(
                tasks: [task],
                recordCreators: {
                  'content:${task.id}': '10000000-0000-4000-8000-000000000099',
                },
              ),
            },
          );
      final controller = _Controller(initial: state(original));
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
                  final current = ref.watch(collaborationProvider).valueOrNull;
                  if (current == null) return const SizedBox.shrink();
                  return TextButton(
                    onPressed: () => CollaborationActions(
                      context,
                      ref,
                      scope,
                      current.dataForScope(scope.id),
                    ).task(task: current.dataForScope(scope.id).tasks.single),
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
      final notes = find.byKey(const ValueKey('organizer-notes-field'));
      await tester.enterText(notes, 'Unsaved local text must remain');
      final updated = original.copyWith(
        notes: 'New shared note',
        assigneeAccountIds: [],
        revision: 2,
      );
      controller.replace(state(updated));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      final editable = tester.widget<EditableText>(
        find.descendant(of: notes, matching: find.byType(EditableText)),
      );
      expect(editable.controller.text, 'Unsaved local text must remain');
      expect(editable.readOnly, true);
      expect(
        find.byKey(const ValueKey('organizer-record-read-only')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('organizer-newer-version')),
        findsOneWidget,
      );
      final save = tester.widget<IconButton>(
        find.descendant(
          of: find.byKey(const ValueKey('organizer-save')),
          matching: find.byType(IconButton),
        ),
      );
      expect(save.onPressed, isNull);
      final completed = tester.widget<CheckboxListTile>(
        find.byKey(const ValueKey('organizer-task-completed')),
      );
      expect(completed.onChanged, isNull);
      expect(controller.saves, 0);
      expect(tester.takeException(), isNull);
      controller.replace(state(updated, revoked: true));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(controller.saves, 0);
      expect(tester.takeException(), isNull);
    },
  );
}
