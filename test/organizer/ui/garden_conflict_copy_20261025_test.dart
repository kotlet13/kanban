import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/l10n/app_localizations.dart';
import 'package:kanban/organizer/data/organizer_repository.dart';
import 'package:kanban/organizer/domain/garden_models.dart';
import 'package:kanban/organizer/presentation/garden/garden_editor.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';
import 'package:kanban/organizer/state/garden_provider.dart';

import 'sharing_ui_fixture.dart';

class _GardenController extends GardenController {
  final garden = Garden(
    id: '11111111-1111-4111-8111-111111111111',
    name: 'Synthetic garden',
    notes: 'Existing notes',
    widthMeters: 8,
    heightMeters: 10,
    createdAt: DateTime.utc(2026, 10, 25),
    updatedAt: DateTime.utc(2026, 10, 25),
  );
  Garden? submitted;

  @override
  Future<GardenSnapshot> build() async => GardenSnapshot(gardens: [garden]);

  @override
  Future<void> updateGarden(
    Garden draft, {
    String? expectedWorkspaceKey,
  }) async {
    submitted = draft;
    throw const OrganizerConflictException(
      'Garden changed; reload before editing',
    );
  }
}

void main() {
  testWidgets(
    'normal garden conflict explains stale editor and retains draft',
    (tester) async {
      final garden = _GardenController();
      final shared = SharingUiController(initial: CollaborationState());
      final infrastructure = await sharingUiInfrastructureOverrides(
        tester,
        shared,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...infrastructure,
            gardenProvider.overrideWith(() => garden),
            collaborationProvider.overrideWith(() => shared),
          ],
          child: MaterialApp(
            locale: const Locale('sl'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(body: Text('Under garden editor')),
            routes: {'/garden': (_) => GardenEditor(garden: garden.garden)},
          ),
        ),
      );
      await tester.pumpAndSettle();
      Navigator.of(
        tester.element(find.text('Under garden editor')),
      ).pushNamed('/garden');
      await tester.pumpAndSettle();
      final note = find.widgetWithText(TextFormField, 'Existing notes');
      await tester.ensureVisible(note);
      await tester.enterText(note, 'Existing notes plus unsaved season');
      await tester.tap(find.byKey(const ValueKey('garden-save')));
      await tester.pumpAndSettle();
      final editor = find.byType(GardenEditor);
      final l = AppLocalizations.of(tester.element(editor))!;
      expect(editor, findsOneWidget);
    expect(find.text(l.gardenEditConflict), findsOneWidget);
    expect(find.text(l.sharingStaleEditor), findsNothing);
      expect(find.text(l.organizerConflict), findsNothing);
      expect(find.text('Existing notes plus unsaved season'), findsOneWidget);
      expect(garden.submitted?.notes, 'Existing notes plus unsaved season');
      expect(tester.takeException(), isNull);
    },
  );
}
