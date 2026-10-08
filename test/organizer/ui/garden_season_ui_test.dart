import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/l10n/app_localizations.dart';
import 'package:kanban/organizer/domain/garden_models.dart';
import 'package:kanban/organizer/presentation/garden/garden_canvas.dart';
import 'package:kanban/organizer/presentation/garden/garden_editor.dart';
import 'package:kanban/organizer/presentation/garden/garden_page.dart';
import 'package:kanban/organizer/state/garden_provider.dart';

const gardenId = '10000000-0000-4000-8000-000000000001';
const bedId = '10000000-0000-4000-8000-000000000002';
const secondBedId = '10000000-0000-4000-8000-000000000003';
const oldPlantingId = '10000000-0000-4000-8000-000000000004';
const plantingId = '10000000-0000-4000-8000-000000000005';
final fixtureNow = DateTime(2026, 10, 8);
Garden fixtureGarden({bool history = true}) => Garden(
  id: gardenId,
  name: 'Testni zelenjavni vrt',
  notes: 'Izrecna testna vsebina',
  createdAt: fixtureNow,
  updatedAt: fixtureNow,
  areas: const [
    GardenArea(
      id: bedId,
      label: 'Greda ob ograji',
      x: .08,
      y: .12,
      width: .38,
      height: .33,
    ),
    GardenArea(
      id: secondBedId,
      label: 'Srednja greda',
      x: .55,
      y: .15,
      width: .32,
      height: .5,
    ),
  ],
  seasons: [
    if (history)
      GardenSeason(
        year: 2025,
        plantings: [
          GardenPlanting(
            id: oldPlantingId,
            areaId: bedId,
            crop: 'Paradižnik',
            family: 'Solanaceae',
            status: GardenPlantingStatus.actual,
            plantAt: DateTime(2025, 5, 15),
          ),
        ],
      ),
    GardenSeason(
      year: 2026,
      plantings: [
        GardenPlanting(
          id: plantingId,
          areaId: bedId,
          crop: 'Krompir',
          variety: 'Testna sorta',
          family: 'Razhudnikovke',
          sowAt: DateTime(2026, 3, 15),
        ),
        const GardenPlanting(
          id: '10000000-0000-4000-8000-000000000006',
          areaId: secondBedId,
          crop: 'Solata',
          family: 'Asteraceae',
        ),
      ],
    ),
  ],
);

class GardenUiController extends GardenController {
  GardenUiController(this.garden);
  Garden garden;
  Garden? saved;
  @override
  Future<GardenSnapshot> build() async => GardenSnapshot(gardens: [garden]);
  @override
  Future<void> updateGarden(Garden value) async {
    saved = value;
    garden = value.copyWith(revision: value.revision + 1);
    state = AsyncData(GardenSnapshot(gardens: [garden]));
  }
}

Future<void> pumpGarden(
  WidgetTester tester,
  GardenUiController controller, {
  double width = 390,
  Brightness brightness = Brightness.light,
  String locale = 'sl',
}) async {
  tester.view.physicalSize = Size(width, 950);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [gardenProvider.overrideWith(() => controller)],
      child: MaterialApp(
        locale: Locale(locale),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: brightness,
          ),
        ),
        home: const Scaffold(body: SingleChildScrollView(child: GardenPage())),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text(controller.garden.name));
  await tester.pumpAndSettle();
}

Future<void> visibleTap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'stored UTC calendar date displays its day and explicit year without local timezone conversion',
    (tester) async {
      final garden = fixtureGarden();
      final day = DateTime.utc(2018, 11, 4);
      final modified = garden.copyWith(
        seasons: [
          garden.seasons.last.copyWith(
            plantings: [
              garden.seasons.last.plantings.first.copyWith(sowAt: day),
            ],
          ),
        ],
      );
      await pumpGarden(tester, GardenUiController(modified));
      await visibleTap(tester, find.byTooltip('Uredi kulturo'));
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Setev: 4. nov. 2018'),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'new empty season and second crop remain draft until global save',
    (tester) async {
      final controller = GardenUiController(fixtureGarden());
      await pumpGarden(tester, controller);
      expect(
        find.byKey(ValueKey('garden-rotation-$plantingId')),
        findsOneWidget,
      );
      await visibleTap(tester, find.byKey(const ValueKey('garden-new-season')));
      await tester.enterText(
        find.byKey(const ValueKey('garden-season-year')),
        '2027',
      );
      await tester.tap(find.byKey(const ValueKey('garden-season-save')));
      await tester.pumpAndSettle();
      expect(controller.saved, isNull);
      expect(
        find.text('Ta greda v izbrani sezoni še nima kultur.'),
        findsOneWidget,
      );
      await visibleTap(
        tester,
        find.byKey(const ValueKey('garden-add-planting-$bedId')),
      );
      await tester.enterText(
        find.byKey(const ValueKey('garden-crop')),
        'Fižol',
      );
      await tester.enterText(
        find.byKey(const ValueKey('garden-family')),
        'Fabaceae',
      );
      await tester.tap(find.byKey(const ValueKey('garden-planting-save')));
      await tester.pumpAndSettle();
      await visibleTap(
        tester,
        find.byKey(const ValueKey('garden-add-planting-$bedId')),
      );
      await tester.enterText(
        find.byKey(const ValueKey('garden-crop')),
        'Solata',
      );
      await tester.tap(find.byKey(const ValueKey('garden-planting-save')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('garden-save')));
      await tester.pumpAndSettle();
      expect(
        controller.saved!.seasonForYear(2027)!.plantings.map((p) => p.crop),
        ['Fižol', 'Solata'],
      );
      expect(
        controller.saved!.seasonForYear(2025)!.plantings.single.status,
        GardenPlantingStatus.actual,
      );
      expect(controller.saved!.areas.first.id, bedId);
    },
  );
  testWidgets(
    'copy is explicit and produces new planned entries without dates',
    (tester) async {
      final controller = GardenUiController(fixtureGarden());
      await pumpGarden(tester, controller);
      await visibleTap(tester, find.byKey(const ValueKey('garden-new-season')));
      await tester.enterText(
        find.byKey(const ValueKey('garden-season-year')),
        '2027',
      );
      await tester.tap(find.byKey(const ValueKey('garden-season-copy')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('2025').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('garden-season-save')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('garden-save')));
      await tester.pumpAndSettle();
      final copy = controller.saved!.seasonForYear(2027)!.plantings.single;
      expect(copy.id, isNot(oldPlantingId));
      expect(copy.areaId, bedId);
      expect(copy.status, GardenPlantingStatus.planned);
      expect(copy.plantAt, isNull);
      expect(
        controller.saved!.seasonForYear(2025)!.plantings.single.plantAt,
        DateTime(2025, 5, 15),
      );
    },
  );
  for (final width in [320.0, 390.0, 1280.0]) {
    for (final brightness in [Brightness.light, Brightness.dark]) {
      testWidgets(
        'season plan, selected crops and planting keyboard fit $width $brightness',
        (tester) async {
          final controller = GardenUiController(fixtureGarden());
          await pumpGarden(
            tester,
            controller,
            width: width,
            brightness: brightness,
          );
          expect(find.byType(GardenEditor), findsOneWidget);
          expect(
            find.textContaining(
              'Ista zapisana družina Razhudnikovke (Solanaceae)',
            ),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
          await visibleTap(
            tester,
            find.byKey(const ValueKey('garden-add-planting-$bedId')),
          );
          await tester.enterText(
            find.byKey(const ValueKey('garden-crop')),
            'Prava kultura',
          );
          tester.view.viewInsets = const FakeViewPadding(bottom: 280);
          await tester.pumpAndSettle();
          addTearDown(tester.view.resetViewInsets);
          expect(tester.takeException(), isNull);
          await tester.ensureVisible(
            find.byKey(const ValueKey('garden-planting-notes')),
          );
          await tester.enterText(
            find.byKey(const ValueKey('garden-planting-notes')),
            'Moji zapiski',
          );
          await tester.tap(find.byKey(const ValueKey('garden-planting-save')));
          tester.view.resetViewInsets();
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  testWidgets(
    'unknown family has no safety claim; actual-only rotation and history are visible',
    (tester) async {
      final g = fixtureGarden();
      final edited = g.copyWith(
        seasons: [
          g.seasons.first,
          g.seasons.last.copyWith(
            plantings: [
              g.seasons.last.plantings.first.copyWith(
                family: 'Moja neznana družina',
              ),
            ],
          ),
        ],
      );
      await pumpGarden(tester, GardenUiController(edited));
      expect(find.byKey(ValueKey('garden-rotation-$plantingId')), findsNothing);
      expect(
        find.textContaining('Neznana družina ali manjkajoča zgodovina'),
        findsOneWidget,
      );
      await visibleTap(
        tester,
        find.byKey(const ValueKey('garden-history-$bedId-2025')),
      );
      expect(find.text('Paradižnik'), findsNWidgets(2));
      expect(find.textContaining('Dejanska zasaditev'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'resizing at excluded right-bottom edge preserves selection and commits one bounded change',
    (tester) async {
      GardenArea area = const GardenArea(
        id: bedId,
        label: 'Greda',
        x: .2,
        y: .2,
        width: .3,
        height: .3,
      );
      String? selected = bedId;
      var commits = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              child: StatefulBuilder(
                builder: (context, setState) => GardenCanvas(
                  areas: [area],
                  tool: GardenTool.select,
                  selectedId: selected,
                  onSelect: (id) => setState(() => selected = id),
                  onDraw: (_) {},
                  onMove: (value) => setState(() {
                    area = value;
                    commits++;
                  }),
                  semanticLabel: 'Testni načrt',
                ),
              ),
            ),
          ),
        ),
      );
      final rect = tester.getRect(find.byKey(const ValueKey('garden-canvas')));
      final gesture = await tester.startGesture(
        rect.topLeft + Offset(rect.width * .5, rect.height * .5),
      );
      await tester.pump();
      await gesture.moveBy(const Offset(60, 30));
      await tester.pump();
      expect(commits, 0);
      await gesture.up();
      await tester.pump();
      expect(selected, bedId);
      expect(commits, 1);
      expect(area.x, .2);
      expect(area.width, closeTo(.45, .0001));
      expect(area.height, closeTo(.4, .0001));
      expect(area.validate, returnsNormally);
    },
  );
  testWidgets('legacy tiny corner resize avoids reversed clamp range', (
    tester,
  ) async {
    const initial = GardenArea(
      id: bedId,
      label: 'Majhna stara greda',
      x: 0,
      y: .5,
      width: .004,
      height: .004,
    );
    GardenArea? changed;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: GardenCanvas(
              areas: const [initial],
              tool: GardenTool.select,
              selectedId: bedId,
              onSelect: (_) {},
              onDraw: (_) {},
              onMove: (a) {
                changed = a;
              },
              semanticLabel: 'Testni načrt',
            ),
          ),
        ),
      ),
    );
    final rect = tester.getRect(find.byKey(const ValueKey('garden-canvas')));
    await tester.dragFrom(
      rect.topLeft + Offset(8, rect.height * .5 + .1),
      const Offset(80, -80),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(changed, isNotNull);
    expect(changed!.validate, returnsNormally);
    expect(changed!.height, greaterThan(initial.height));
  });
  testWidgets(
    'zoomed pan and bed resize use actual transformed pointer coordinates',
    (tester) async {
      var tool = GardenTool.pan;
      GardenArea area = const GardenArea(
        id: bedId,
        label: 'Greda',
        x: .2,
        y: .2,
        width: .3,
        height: .3,
      );
      late StateSetter rebuild;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              child: StatefulBuilder(
                builder: (context, setState) {
                  rebuild = setState;
                  return GardenCanvas(
                    areas: [area],
                    tool: tool,
                    selectedId: bedId,
                    onSelect: (_) {},
                    onDraw: (_) {},
                    onMove: (a) => setState(() => area = a),
                    semanticLabel: 'Testni načrt',
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('garden-zoom-in')));
      await tester.pump();
      var rect = tester.getRect(find.byKey(const ValueKey('garden-canvas')));
      expect(rect.width, closeTo(500, .1));
      await tester.dragFrom(const Offset(200, 100), const Offset(-30, -20));
      await tester.pumpAndSettle();
      final panned = tester.getRect(
        find.byKey(const ValueKey('garden-canvas')),
      );
      expect(panned.left, lessThan(rect.left));
      rebuild(() => tool = GardenTool.select);
      await tester.pump();
      rect = tester.getRect(find.byKey(const ValueKey('garden-canvas')));
      await tester.dragFrom(
        rect.topLeft + Offset(rect.width * .5, rect.height * .5),
        const Offset(40, 30),
      );
      await tester.pump();
      expect(area.width, closeTo(.38, .0001));
      expect(area.height, closeTo(.38, .0001));
      expect(area.validate, returnsNormally);
      expect(tester.takeException(), isNull);
    },
  );
}
