import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/l10n/app_localizations.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'package:kanban/organizer/presentation/collection_actions.dart';
import 'package:kanban/organizer/presentation/shopping_page.dart';

class _Actions implements OrganizerCollectionActions {
  final added = <(String, String, String)>[];
  bool fail = false;
  @override
  Future<void> createShoppingItem({
    required String listId,
    required String title,
    String quantity = '1',
  }) async {
    if (fail) throw StateError('synthetic storage failure');
    added.add((listId, title, quantity));
  }

  @override
  String errorMessage(Object error) => 'Could not save';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final now = DateTime(2026, 10, 14);
  final snapshot = OrganizerSnapshot().copyWith(
    shoppingLists: [
      LocalShoppingList(
        id: 'list',
        title: 'Groceries',
        createdAt: now,
        updatedAt: now,
      ),
    ],
  );
  Future<void> pump(
    WidgetTester tester,
    _Actions actions, {
    double width = 390,
    double scale = 1,
  }) async {
    tester.view.physicalSize = Size(width, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            child: OrganizerShoppingPage(
              snapshot: snapshot,
              actions: actions,
              selectedId: 'list',
              onSelection: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final width in [320.0, 390.0, 1280.0]) {
    testWidgets('quick entry saves textual quantity and refocuses at $width', (
      tester,
    ) async {
      final actions = _Actions();
      await pump(tester, actions, width: width, scale: 2);
      final item = find.byKey(const ValueKey('shopping-item-field'));
      final quantity = find.byKey(const ValueKey('shopping-quantity-field'));
      await tester.enterText(item, 'Carrots');
      await tester.enterText(quantity, '2 bags');
      await tester.tap(find.byTooltip('Add item'));
      await tester.pumpAndSettle();
      expect(actions.added, [('list', 'Carrots', '2 bags')]);
      final field = tester.widget<TextField>(item);
      expect(field.controller!.text, '');
      expect(field.focusNode!.hasFocus, isTrue);
      expect(tester.widget<TextField>(quantity).controller!.text, '1');
      await tester.enterText(item, 'Milk');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(actions.added.last, ('list', 'Milk', '1'));
      expect(tester.widget<TextField>(item).focusNode!.hasFocus, isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('failed quick entry retains item and textual quantity', (
    tester,
  ) async {
    final actions = _Actions()..fail = true;
    await pump(tester, actions);
    final item = find.byKey(const ValueKey('shopping-item-field'));
    final quantity = find.byKey(const ValueKey('shopping-quantity-field'));
    await tester.enterText(item, 'Seeds');
    await tester.enterText(quantity, 'one packet');
    await tester.tap(find.byTooltip('Add item'));
    await tester.pumpAndSettle();
    expect(actions.added, isEmpty);
    expect(tester.widget<TextField>(item).controller!.text, 'Seeds');
    expect(tester.widget<TextField>(quantity).controller!.text, 'one packet');
    expect(find.text('Could not save'), findsOneWidget);
  });
}
