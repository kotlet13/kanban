import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kanban/app.dart';
import 'package:kanban/state/providers.dart';
import 'organizer_ui_test.dart' show pumpOrganizer, MemoryOrganizerStorage;

void main() {
  testWidgets(
    'committed preference journal applies after nonblocking local startup',
    (tester) async {
      final ready = Completer<Map<String, Object?>>();
      await pumpOrganizer(
        tester,
        MemoryOrganizerStorage(),
        replayPreferences: () => ready.future,
      );
      expect(find.text('Začni z enim opravilom.'), findsOneWidget);
      ready.complete({'app_locale_code': 'en', 'app_theme_mode': 'dark'});
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(KanbanApp)),
      );
      expect(container.read(themeModeProvider), ThemeMode.dark);
      expect(container.read(appLocaleProvider)?.languageCode, 'en');
    },
  );
  testWidgets('preference replay failure does not block local task creation', (
    tester,
  ) async {
    await pumpOrganizer(
      tester,
      MemoryOrganizerStorage(),
      replayPreferences: () =>
          Future.error(StateError('local preferences unavailable')),
    );
    expect(find.text('Začni z enim opravilom.'), findsOneWidget);
    expect(tester.takeException(), null);
  });
}
