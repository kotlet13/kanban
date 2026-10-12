import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/l10n/l10n.dart';
import 'organizer_ui_test.dart'
    show pumpOrganizer, mobileTab, MemoryOrganizerStorage;

void main() {
  for (final width in [320.0, 390.0, 599.0]) {
    for (final language in ['sl', 'en']) {
      testWidgets(
        'phone destinations reach modules at $width $language with 2x text',
        (tester) async {
          tester.platformDispatcher.textScaleFactorTestValue = 2;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          final storage = MemoryOrganizerStorage();
          await pumpOrganizer(
            tester,
            storage,
            width: width,
            height: 800,
            locale: language,
          );
          expect(find.byType(NavigationBar), findsOneWidget);
          expect(find.byType(Drawer), findsNothing);
          await mobileTab(tester, language == 'sl' ? 'Nastavitve' : 'Settings');
          expect(
            find.byKey(const ValueKey('content-_Area.settings')),
            findsOneWidget,
          );
          expect(find.byType(NavigationBar), findsOneWidget);
          await mobileTab(tester, language == 'sl' ? 'Danes' : 'Today');
          expect(
            find.byKey(const ValueKey('content-_Area.today')),
            findsOneWidget,
          );
          expect(storage.writes, 0);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  for (final width in [600.0, 899.0, 900.0, 1280.0]) {
    testWidgets('tablet and desktop navigation stays at $width', (
      tester,
    ) async {
      await pumpOrganizer(tester, MemoryOrganizerStorage(), width: width);
      expect(find.byKey(const ValueKey('organizer-menu-open')), findsNothing);
      expect(
        find.byType(NavigationBar),
        width < 900 ? findsOneWidget : findsNothing,
      );
      if (width >= 900) {
        expect(find.widgetWithText(ListTile, 'Prostor'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('More preserves deliberate reopening of setup', (tester) async {
    await pumpOrganizer(tester, MemoryOrganizerStorage());
    await mobileTab(tester, 'Več');
    // The setup entry retains its existing localized flow.
    final setupLabel = tester.element(
      find.byKey(const ValueKey('content-_Area.more')),
    );
    final entry = find.widgetWithText(ListTile, setupLabel.l10n.setupOpen);
    await tester.ensureVisible(entry);
    await tester.tap(entry);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
