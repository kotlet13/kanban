import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/domain/spreadsheet_formula.dart';
import 'package:kanban/organizer/presentation/tables/spreadsheet_grid.dart';

const viewportKey = ValueKey('spreadsheet-viewport');
const inputKey = ValueKey('spreadsheet-formula-input');
const resetKey = ValueKey('spreadsheet-zoom-reset');

Finder get viewport => find.byKey(viewportKey);
Finder get cells => find.byWidgetPredicate(
  (widget) =>
      widget is Semantics && (widget.properties.label?.contains(': ') ?? false),
);

ScrollController scroll(WidgetTester tester, Axis axis) => tester
    .widgetList<SingleChildScrollView>(
      find.descendant(
        of: viewport,
        matching: find.byType(SingleChildScrollView),
      ),
    )
    .singleWhere((widget) => widget.scrollDirection == axis)
    .controller!;

Future<void> pumpGrid(
  WidgetTester tester, {
  bool editable = false,
  double width = 360,
  double textScale = 1,
  String locale = 'en',
  bool dark = false,
  ValueChanged<Map<String, String>>? onChanged,
}) async {
  tester.view.physicalSize = Size(width, 780);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  var data = <String, String>{
    for (var r = 1; r <= 50; r++)
      for (final c in ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H'])
        '$c$r': '$c$r value',
  };
  await tester.pumpWidget(
    MaterialApp(
      locale: Locale(locale),
      supportedLocales: const [Locale('en'), Locale('sl')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: SafeArea(
          child: StatefulBuilder(
            builder: (context, update) => SpreadsheetGrid(
              cells: data,
              editable: editable,
              onChanged: (value) {
                onChanged?.call(value);
                update(() => data = value);
              },
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> pinch(WidgetTester tester, double ratio) async {
  final center = tester.getCenter(viewport);
  final first = await tester.startGesture(
    center - const Offset(70, 0),
    pointer: 1,
  );
  final second = await tester.startGesture(
    center + const Offset(70, 0),
    pointer: 2,
  );
  await tester.pump();
  await first.moveTo(center - Offset(70 * ratio, 0));
  await second.moveTo(center + Offset(70 * ratio, 0));
  await tester.pump();
  await first.up();
  await second.up();
  await tester.pumpAndSettle();
}

void main() {
  for (final editable in [false, true]) {
    testWidgets(
      'pinch scales cells and text only; no writes, editable=$editable',
      (tester) async {
        var writes = 0;
        await pumpGrid(tester, editable: editable, onChanged: (_) => writes++);
        final inputSize = tester.getSize(find.byKey(inputKey));
        final toolbarSize = tester.getSize(find.byKey(resetKey));
        final initialSize = tester.getSize(cells.first);
        final initialStyle = tester
            .widget<Text>(find.text('A1 value').last)
            .style!;
        await pinch(tester, .5);
        expect(find.text('50%'), findsOneWidget);
        expect(tester.getSize(cells.first), initialSize / 2);
        expect(
          tester.widget<Text>(find.text('A1 value').last).style!.fontSize,
          initialStyle.fontSize! / 2,
        );
        expect(tester.getSize(find.byKey(inputKey)), inputSize);
        expect(tester.getSize(find.byKey(resetKey)), toolbarSize);
        expect(
          tester.widget<TextField>(find.byKey(inputKey)).controller!.text,
          'A1 value',
        );
        await pinch(tester, 4);
        expect(find.text('200%'), findsOneWidget);
        expect(tester.getSize(cells.first), initialSize * 2);
        expect(writes, 0);
        await tester.tap(find.byKey(resetKey));
        await tester.pumpAndSettle();
        expect(find.text('100%'), findsOneWidget);
        expect(tester.getSize(cells.first), initialSize);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'pinch keeps the focal cell under the fingers with aligned headers',
    (tester) async {
      await pumpGrid(tester);
      await tester.drag(viewport, const Offset(-140, 0));
      await tester.pumpAndSettle();
      await tester.drag(viewport, const Offset(0, -210));
      await tester.pumpAndSettle();
      final rect = tester.getRect(viewport);
      final center = tester.getCenter(viewport) - rect.topLeft;
      final before = Offset(
        scroll(tester, Axis.horizontal).offset,
        scroll(tester, Axis.vertical).offset,
      );
      final logicalAnchor = before + center - const Offset(56, 48);
      await pinch(tester, 1.5);
      final after = Offset(
        scroll(tester, Axis.horizontal).offset,
        scroll(tester, Axis.vertical).offset,
      );
      expect(
        (after + center - const Offset(84, 72)).dx / 1.5,
        closeTo(logicalAnchor.dx, .1),
      );
      expect(
        (after + center - const Offset(84, 72)).dy / 1.5,
        closeTo(logicalAnchor.dy, .1),
      );
      final cell = tester.widget<Semantics>(cells.first);
      final address = cell.properties.label!.split(':').first;
      final column = address.replaceAll(RegExp(r'\d'), '');
      final row = address.replaceAll(RegExp('[A-Z]'), '');
      final cellRect = tester.getRect(cells.first);
      expect(
        tester.getCenter(find.text(column)).dx,
        closeTo(cellRect.center.dx, .1),
      );
      expect(
        tester.getCenter(find.text(row)).dy,
        closeTo(cellRect.center.dy, .1),
      );
    },
  );

  testWidgets(
    'one-finger scrolling, hit testing and editing work after pinch and lift',
    (tester) async {
      Map<String, String>? changed;
      await pumpGrid(
        tester,
        editable: true,
        onChanged: (value) => changed = value,
      );
      await pinch(tester, 1.5);
      final x = scroll(tester, Axis.horizontal).offset;
      await tester.drag(viewport, const Offset(-100, 0));
      await tester.pumpAndSettle();
      expect(scroll(tester, Axis.horizontal).offset, greaterThan(x));
      final y = scroll(tester, Axis.vertical).offset;
      await tester.drag(viewport, const Offset(0, -100));
      await tester.pumpAndSettle();
      expect(scroll(tester, Axis.vertical).offset, greaterThan(y));
      final candidate = cells.evaluate().firstWhere((element) {
        final render = element.renderObject! as RenderBox;
        final center = render.localToGlobal(render.size.center(Offset.zero));
        return tester.getRect(viewport).deflate(80).contains(center);
      });
      final address = (candidate.widget as Semantics).properties.label!
          .split(':')
          .first;
      await tester.tap(find.byWidget(candidate.widget));
      await tester.pump();
      expect(
        tester.widget<TextField>(find.byKey(inputKey)).controller!.text,
        '$address value',
      );
      await tester.enterText(find.byKey(inputKey), '=SUM(1,5;2,5)');
      await tester.pump();
      expect(changed?[address], '=SUM(1,5;2,5)');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'cancelled pinch and a third finger do not leave scrolling disabled',
    (tester) async {
      await pumpGrid(tester);
      final center = tester.getCenter(viewport);
      final first = await tester.startGesture(
        center - const Offset(50, 0),
        pointer: 1,
      );
      final second = await tester.startGesture(
        center + const Offset(50, 0),
        pointer: 2,
      );
      final third = await tester.startGesture(
        center + const Offset(0, 50),
        pointer: 3,
      );
      await tester.pump();
      await first.cancel();
      await second.moveBy(const Offset(20, 0));
      await tester.pump();
      await second.cancel();
      await third.cancel();
      await tester.pumpAndSettle();
      final y = scroll(tester, Axis.vertical).offset;
      await tester.drag(viewport, const Offset(0, -120));
      await tester.pumpAndSettle();
      expect(scroll(tester, Axis.vertical).offset, greaterThan(y));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('visible zoom buttons clamp and reset without changing cells', (
    tester,
  ) async {
    await pumpGrid(tester);
    for (var i = 0; i < 12; i++) {
      await tester.tap(find.byTooltip('Zoom out'));
      await tester.pump();
    }
    expect(find.text('50%'), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (widget) => widget is IconButton && widget.tooltip == 'Zoom out',
            ),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.byKey(resetKey));
    await tester.pump();
    expect(find.text('100%'), findsOneWidget);
    await tester.tap(find.byTooltip('Zoom in'));
    await tester.pump();
    expect(find.text('110%'), findsOneWidget);
  });

  for (final locale in ['en', 'sl']) {
    testWidgets(
      'formula help is discoverable and scrollable at 320px/2x, $locale',
      (tester) async {
        await pumpGrid(
          tester,
          width: 320,
          textScale: 2,
          locale: locale,
          dark: locale == 'sl',
        );
        await tester.tap(
          find.byTooltip(
            locale == 'sl' ? 'Formule in pomoč' : 'Formulas and help',
          ),
        );
        await tester.pumpAndSettle();
        for (final name in ['SUM', 'AVERAGE', 'COUNT', 'MIN', 'MAX']) {
          expect(find.text('=$name(A1:A10)'), findsOneWidget);
        }
        final dialogScroll = find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(SingleChildScrollView),
        );
        await tester.drag(dialogScroll.first, const Offset(0, -1600));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.text(locale == 'sl' ? 'Zapri' : 'Close'));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(
          tester.widget<TextField>(find.byKey(inputKey)).controller!.text,
          'A1 value',
        );
      },
    );
  }

  test('all documented formula examples evaluate', () {
    final calculator = SpreadsheetCalculator({
      'A1': '1',
      'A2': '2',
      'A3': '3',
      'B1': '4',
      'B2': '=SUM(A1:A10)',
      'B3': '=AVERAGE(A1:A10)',
      'B4': '=COUNT(A1:A10)',
      'B5': '=MIN(A1:A10)',
      'B6': '=MAX(A1:A10)',
      'B7': '=(A1+B1)*2',
      'B8': '=SUM(1,5;2,5)',
    });
    for (final entry in {
      'B2': 6,
      'B3': 2,
      'B4': 3,
      'B5': 1,
      'B6': 3,
      'B7': 10,
      'B8': 4,
    }.entries) {
      expect(calculator.evaluate(entry.key).number, entry.value);
    }
  });
}
