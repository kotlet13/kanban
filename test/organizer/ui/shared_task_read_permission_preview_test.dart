import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/l10n/app_localizations.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'package:kanban/organizer/presentation/projects_page.dart';
import 'package:kanban/organizer/presentation/shared/collaboration_actions.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';
import 'package:kanban/organizer/state/organizer_provider.dart';

import 'sharing_ui_fixture.dart';

class _Personal extends OrganizerController {
  @override
  Future<OrganizerSnapshot> build() async => OrganizerSnapshot();
}

class _Reader extends SharingUiController {
  _Reader({required CollaborationState initial}) : super(initial: initial);
  final refresh = Completer<NotificationOpenResult>();
  int refreshes = 0;
  int financePreparations = 0;
  @override
  Future<NotificationOpenResult> refreshVisibleTaskTarget(
    NotificationTarget target,
  ) {
    refreshes++;
    return refresh.future;
  }

  @override
  Future<void> refreshFinanceAccountChoices(String scopeId) async {
    financePreparations++;
  }
}

void main() {
  testWidgets(
    'member can read another author task notes from project task row while refresh waits and editing stays disabled',
    (tester) async {
      final date = DateTime.utc(2026, 10, 24);
      final scope = SharedScope.fromJson({
        ...sharingScope().toJson(),
        'recordPolicyVersion': 1,
        'role': 'member',
      });
      final task = LocalTask(
        id: '10000000-0000-4000-8000-000000000007',
        title: 'Another member task',
        notes: 'Foreign record notes stay readable',
        projectId: null,
        dueAt: null,
        isCompleted: false,
        createdAt: date,
        updatedAt: date,
      );
      final data = SharedScopeData(
        tasks: [task],
        recordCreators: {
          'content:${task.id}': '10000000-0000-4000-8000-000000000099',
        },
      );
      final controller = _Reader(
        initial: CollaborationState(
          session: sharingSession(),
          scopes: [scope],
          selectedSpaceId: scope.id,
          data: {scope.id: data},
        ),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            collaborationProvider.overrideWith(() => controller),
            organizerProvider.overrideWith(_Personal.new),
          ],
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) {
                  final state = ref.watch(collaborationProvider).valueOrNull;
                  if (state == null) return const SizedBox.shrink();
                  return OrganizerTasksPage(
                    snapshot: OrganizerSnapshot(tasks: [task]),
                    actions: CollaborationActions(context, ref, scope, data),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Another member task'));
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pumpAndSettle();
      expect(find.text('Foreign record notes stay readable'), findsOneWidget);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(controller.refreshes, 1);
      expect(controller.refresh.isCompleted, false);
      expect(controller.financePreparations, 0);
      expect(find.byKey(const ValueKey('organizer-save')), findsNothing);
      expect(find.byKey(const ValueKey('organizer-title-field')), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      controller.refresh.completeError(const CollaborationException('network'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
