import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/l10n/app_localizations.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'package:kanban/organizer/presentation/planning/shared_agenda_page.dart';
import 'package:kanban/organizer/presentation/planning/shared_today_overview.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';
import 'sharing_ui_fixture.dart' show SharingUiController, sharingSession;

void main() {
  final now = DateTime.now();
  LocalTask task(String title) => LocalTask(
    id: title,
    title: title,
    notes: '',
    projectId: null,
    dueAt: now,
    isCompleted: false,
    createdAt: now,
    updatedAt: now,
  );
  const active = SharedScope(
    id: 'active',
    name: 'Active project',
    kind: SharedScopeKind.project,
    role: SharedRole.owner,
  );
  const archived = SharedScope(
    id: 'archived',
    name: 'Archived project',
    kind: SharedScopeKind.project,
    role: SharedRole.owner,
    archived: true,
  );
  final data = {
    'active': SharedScopeData(tasks: [task('Active task')]),
    'archived': SharedScopeData(tasks: [task('Archived task')]),
  };
  MaterialApp app(Widget child) => MaterialApp(
    locale: const Locale('sl'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );
  testWidgets(
    'shared today excludes archived scope and restores it after unarchive',
    (tester) async {
      final controller = SharingUiController(
        initial: CollaborationState(
          session: sharingSession(),
          scopes: const [active, archived],
          data: data,
        ),
      );
      String? opened;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [collaborationProvider.overrideWith(() => controller)],
          child: app(SharedTodayOverview(onAgenda: (id) => opened = id)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Active task'), findsOneWidget);
      expect(find.text('Archived task'), findsNothing);
      await tester.tap(find.text('Active task'));
      expect(opened, 'active');
      controller.replace(
        CollaborationState(
          session: sharingSession(),
          scopes: const [
            active,
            SharedScope(
              id: 'archived',
              name: 'Archived project',
              kind: SharedScopeKind.project,
              role: SharedRole.owner,
            ),
          ],
          data: data,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Archived task'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'archived scope contributes no daily items while historical timeline remains readable',
    (tester) async {
      await tester.pumpWidget(
        app(
          SharedAgendaPage(
            scope: archived,
            data: data['archived']!,
            people: const [],
            onOpen: (_) => {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Archived task'), findsNothing);
      await tester.pumpWidget(
        app(
          SharedAgendaPage(
            key: const ValueKey('history'),
            scope: archived,
            data: data['archived']!,
            people: const [],
            onOpen: (_) => {},
            timeline: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Archived task'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
