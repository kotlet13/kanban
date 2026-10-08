import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'organizer_ui_test.dart'
    show pumpOrganizer, mobileTab, MemoryOrganizerStorage;

void main() {
  for (final width in [320.0, 390.0, 599.0]) {
    for (final language in ['sl', 'en']) {
      testWidgets(
        'phone drawer reaches modules and closes at $width $language with 2x text',
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
          expect(find.byType(NavigationBar), findsNothing);
          await tester.tap(find.byKey(const ValueKey('organizer-menu-open')));
          await tester.pumpAndSettle();
          final drawer = find.byKey(const ValueKey('organizer-mobile-menu'));
          expect(drawer, findsOneWidget);
          expect(
            find.byKey(const ValueKey('organizer-menu-today')),
            findsOneWidget,
          );
          final target = find.byKey(const ValueKey('organizer-menu-settings'));
          await tester.scrollUntilVisible(
            target,
            160,
            scrollable: find.descendant(
              of: drawer,
              matching: find.byType(Scrollable),
            ),
          );
          await tester.tap(target);
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('content-_Area.settings')),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('organizer-menu-close')).hitTestable(),
            findsNothing,
          );
          expect(find.byType(NavigationBar), findsNothing);
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
        expect(find.widgetWithText(ListTile, 'Projekti'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('closing drawer keeps the current screen', (tester) async {
    await pumpOrganizer(tester, MemoryOrganizerStorage());
    await tester.tap(find.byKey(const ValueKey('organizer-menu-open')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('organizer-menu-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('content-_Area.today')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('phone menu preserves deliberate reopening of setup', (
    tester,
  ) async {
    await pumpOrganizer(tester, MemoryOrganizerStorage());
    await tester.tap(find.byKey(const ValueKey('organizer-menu-open')));
    await tester.pumpAndSettle();
    final setup = find.byKey(const ValueKey('organizer-menu-setup'));
    await tester.ensureVisible(setup);
    await tester.tap(setup);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(
      find.byKey(const ValueKey('organizer-menu-close')).hitTestable(),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });
}
