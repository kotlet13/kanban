import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/l10n/app_localizations.dart';
import 'package:kanban/organizer/domain/garden_models.dart';
import 'package:kanban/organizer/presentation/garden/garden_area_form.dart';
import 'package:kanban/organizer/presentation/garden/garden_editor.dart';
import 'package:kanban/organizer/presentation/garden/garden_planting_form.dart';
import 'package:kanban/organizer/presentation/garden/garden_scene_view.dart';
import 'package:kanban/organizer/state/garden_provider.dart';
import 'package:kanban/organizer/state/local_spaces_provider.dart';
import 'package:kanban/organizer/presentation/editor_actions.dart';
import 'garden_season_ui_test.dart' show GardenUiController;

String id(int n) => 'eeeeeeee-eeee-4eee-8eee-${n.toString().padLeft(12, '0')}';
Garden illustratedGarden() => Garden(
  id: id(1),
  name: 'Zelenjavni vrt',
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
  widthMeters: 8,
  heightMeters: 10,
  areas: [
    for (var i = 0; i < 6; i++)
      GardenArea(
        id: id(10 + i),
        label: ['Paradižnik', 'Solata', 'Korenje', 'Zelje', 'Buče', 'Fižol'][i],
        x: i.isEven ? .08 : .56,
        y: .08 + (i ~/ 2) * .3,
        width: .36,
        height: .23,
      ),
  ],
  seasons: [
    GardenSeason(
      year: 2025,
      plantings: [
        GardenPlanting(
          id: id(100),
          areaId: id(10),
          crop: 'Krompir lani',
          status: GardenPlantingStatus.actual,
        ),
      ],
    ),
    GardenSeason(
      year: 2026,
      plantings: [
        for (var i = 0; i < 6; i++)
          GardenPlanting(
            id: id(200 + i),
            areaId: id(10 + i),
            crop: [
              'Paradižnik',
              'Solata',
              'Korenje',
              'Zelje',
              'Buče',
              'Fižol',
            ][i],
            status: GardenPlantingStatus.actual,
            plantAt: DateTime.utc(2026, 5, 1),
            spacingCm: 50,
            illustration: [
              GardenCropIllustration.tomato,
              GardenCropIllustration.lettuce,
              GardenCropIllustration.carrot,
              GardenCropIllustration.cabbage,
              GardenCropIllustration.pumpkin,
              GardenCropIllustration.bean,
            ][i],
          ),
      ],
    ),
  ],
);

class ScopedGardenUiController extends GardenUiController {
  ScopedGardenUiController(super.garden);
  @override
  Future<GardenSnapshot> build() async =>
      GardenSnapshot(gardens: [garden], workspaceKey: 'household');
}

class GardenLocalSpacesController extends LocalSpacesController {
  @override
  Future<LocalSpacesState> build() async => LocalSpacesState(
    selectedSpaceId: 'household',
    spaces: const [
      LocalSpace(id: 'household', kind: LocalSpaceKind.household, name: 'Dom'),
    ],
  );
  void archive() => state = AsyncData(
    LocalSpacesState(
      selectedSpaceId: 'household',
      spaces: const [
        LocalSpace(
          id: 'household',
          kind: LocalSpaceKind.household,
          name: 'Dom',
          archived: true,
        ),
      ],
    ),
  );
  void remove() => state = AsyncData(LocalSpacesState());
}

Future<void> host(
  WidgetTester tester,
  Widget child, {
  double width = 390,
  double height = 844,
  double scale = 1,
  Brightness brightness = Brightness.light,
  String locale = 'sl',
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      locale: Locale(locale),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(
        fontFamily: 'Roboto',
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: brightness,
        ),
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: child,
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'view pinch and zoom buttons work over beds without editing geometry; tap opens bed',
    (tester) async {
      final garden = illustratedGarden();
      GardenArea? tapped;
      await host(
        tester,
        Scaffold(
          body: GardenSceneView(
            garden: garden,
            year: 2026,
            onBed: (a) => tapped = a,
          ),
        ),
      );
      final viewer = tester.widget<InteractiveViewer>(
        find.byKey(const ValueKey('garden-scene-viewer')),
      );
      final before = garden.toJson();
      final bed = find.byKey(ValueKey('garden-scene-bed-${id(10)}'));
      await tester.tap(bed);
      expect(tapped?.id, id(10));
      final center = tester.getCenter(bed);
      final first = await tester.startGesture(
        center - const Offset(12, 0),
        pointer: 1,
      );
      final second = await tester.startGesture(
        center + const Offset(12, 0),
        pointer: 2,
      );
      await tester.pump();
      await first.moveTo(center - const Offset(45, 0));
      await second.moveTo(center + const Offset(45, 0));
      await tester.pump();
      await first.up();
      await second.up();
      await tester.pumpAndSettle();
      expect(
        viewer.transformationController!.value.getMaxScaleOnAxis(),
        greaterThan(1),
      );
      expect(garden.toJson(), before);
      await tester.tap(find.byKey(const ValueKey('garden-scene-zoom-in')));
      await tester.pump();
      expect(
        viewer.transformationController!.value.getMaxScaleOnAxis(),
        greaterThan(1),
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'scene bed history and harvest remain draft through scene/layout switching until save',
    (tester) async {
      final garden = illustratedGarden(),
          controller = GardenUiController(illustratedGarden());
      await host(
        tester,
        ProviderScope(
          overrides: [gardenProvider.overrideWith(() => controller)],
          child: GardenEditor(garden: garden, startInScene: true),
        ),
      );
      await tester.tap(find.byKey(ValueKey('garden-scene-bed-${id(10)}')));
      await tester.pumpAndSettle();
      expect(find.text('Krompir lani'), findsOneWidget);
      final harvest = find.byKey(ValueKey('garden-harvest-${id(200)}'));
      await tester.ensureVisible(harvest);
      await tester.tap(harvest);
      await tester.pumpAndSettle();
      expect(controller.saved, isNull);
      expect(find.text('Pobrano'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close).first);
      await tester.pumpAndSettle();
      final scene = tester.widget<GardenSceneView>(
        find.byType(GardenSceneView),
      );
      expect(
        scene.garden.seasonForYear(2026)!.plantings.first.harvested,
        isTrue,
      );
      await tester.tap(find.byKey(const ValueKey('garden-edit-layout')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('garden-open-scene')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<GardenSceneView>(find.byType(GardenSceneView))
            .garden
            .seasonForYear(2026)!
            .plantings
            .first
            .harvested,
        isTrue,
      );
      await tester.tap(find.byKey(const ValueKey('garden-save')));
      await tester.pumpAndSettle();
      expect(
        controller.saved?.seasonForYear(2026)!.plantings.first.harvested,
        isTrue,
      );
      expect(
        controller.saved?.seasons.first.plantings.single.crop,
        'Krompir lani',
      );
    },
  );
  testWidgets(
    'open scene becomes read-only on local archive and deletion, preserving history access',
    (tester) async {
      final garden = illustratedGarden();
      final controller = ScopedGardenUiController(garden);
      final spaces = GardenLocalSpacesController();
      final container = ProviderContainer(
        overrides: [
          gardenProvider.overrideWith(() => controller),
          localSpacesProvider.overrideWith(() => spaces),
        ],
      );
      addTearDown(container.dispose);
      await container.read(gardenProvider.future);
      await container.read(localSpacesProvider.future);
      await host(
        tester,
        UncontrolledProviderScope(
          container: container,
          child: GardenEditor(garden: garden, startInScene: true),
        ),
      );
      expect(
        tester
            .widget<EditorSaveButton>(find.byKey(const ValueKey('garden-save')))
            .onPressed,
        isNotNull,
      );
      spaces.archive();
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<EditorSaveButton>(find.byKey(const ValueKey('garden-save')))
            .onPressed,
        isNull,
      );
      expect(find.byKey(const ValueKey('garden-edit-layout')), findsNothing);
      await tester.tap(find.byKey(ValueKey('garden-scene-bed-${id(10)}')));
      await tester.pumpAndSettle();
      expect(find.text('Krompir lani'), findsOneWidget);
      expect(find.byKey(ValueKey('garden-harvest-${id(200)}')), findsNothing);
      await tester.tap(find.byIcon(Icons.close).first);
      await tester.pumpAndSettle();
      spaces.remove();
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<EditorSaveButton>(find.byKey(const ValueKey('garden-save')))
            .onPressed,
        isNull,
      );
      expect(controller.saved, isNull);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'metric area form preserves exact unchanged geometry, accepts decimal meters and rejects beyond bounds',
    (tester) async {
      final garden = illustratedGarden();
      GardenArea? result;
      await host(
        tester,
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showGardenAreaForm(
                  context,
                  garden.areas.first,
                  garden: garden,
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('m'), findsNWidgets(4));
      await tester.enterText(
        find.byKey(const ValueKey('garden-area-label')),
        'Ime',
      );
      await tester.tap(find.byKey(const ValueKey('garden-area-save')));
      await tester.pumpAndSettle();
      expect(result!.x, garden.areas.first.x);
      expect(result!.width, garden.areas.first.width);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('garden-area-number-0')),
        '7,5',
      );
      await tester.tap(find.byKey(const ValueKey('garden-area-save')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('garden-area-save')), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('garden-area-number-0')),
        '1,25',
      );
      await tester.enterText(
        find.byKey(const ValueKey('garden-area-number-2')),
        '2,5',
      );
      await tester.tap(find.byKey(const ValueKey('garden-area-save')));
      await tester.pumpAndSettle();
      expect(result!.x, 1.25 / 8);
      expect(result!.width, 2.5 / 8);
    },
  );
  testWidgets(
    'planting form stores custom spacing, illustration and growth duration without changing crop identity',
    (tester) async {
      final original = illustratedGarden().seasons.last.plantings.first;
      GardenPlanting? edited;
      await host(
        tester,
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                edited = await showGardenPlantingForm(
                  context,
                  original,
                  isNew: false,
                );
              },
              child: const Text('Plant'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Plant'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('garden-spacing')),
        '37,5',
      );
      await tester.enterText(
        find.byKey(const ValueKey('garden-growth-days')),
        '90',
      );
      await tester.tap(find.byKey(const ValueKey('garden-illustration')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Paprika').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('garden-planting-save')));
      await tester.pumpAndSettle();
      expect(edited!.spacingCm, 37.5);
      expect(edited!.visualGrowthDays, 90);
      expect(edited!.illustration, GardenCropIllustration.pepper);
      expect(edited!.crop, original.crop);
      expect(edited!.id, original.id);
    },
  );
  testWidgets('bed remains operable from keyboard without a touch gesture', (
    tester,
  ) async {
    GardenArea? selected;
    await host(
      tester,
      Scaffold(
        body: GardenSceneView(
          garden: illustratedGarden(),
          year: 2026,
          onBed: (a) => selected = a,
        ),
      ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(selected?.id, id(10));
  });
  testWidgets(
    'invalid in-progress physical size never feeds NaN or zero into either canvas',
    (tester) async {
      final controller = GardenUiController(illustratedGarden());
      await host(
        tester,
        ProviderScope(
          overrides: [gardenProvider.overrideWith(() => controller)],
          child: GardenEditor(garden: controller.garden),
        ),
      );
      final field = find.byKey(const ValueKey('garden-width-meters'));
      await tester.ensureVisible(field);
      await tester.enterText(field, 'NaN');
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('garden-open-scene')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<GardenSceneView>(find.byType(GardenSceneView))
            .garden
            .widthMeters,
        8,
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('garden-save')));
      await tester.pumpAndSettle();
      expect(controller.saved, isNull);
      expect(find.byType(GardenSceneView), findsNothing);
    },
  );
  for (final configuration in [
    (320.0, 700.0, 2.0, Brightness.light, 'sl'),
    (390.0, 844.0, 1.0, Brightness.light, 'sl'),
    (1280.0, 800.0, 1.0, Brightness.dark, 'en'),
  ]) {
    testWidgets(
      'fullscreen scene responsive render ${configuration.$1}/${configuration.$3}/${configuration.$5}',
      (tester) async {
        final capture = Platform.environment['JIVIE_GARDEN_CAPTURE'];
        if (capture != null) {
          debugDisableShadows = false;
          addTearDown(() => debugDisableShadows = true);
        }
        if (capture != null) {
          await tester.runAsync(() async {
            final sdk = Platform.resolvedExecutable.split('/bin/cache/').first;
            for (final font in [
              ('Roboto', 'Roboto-Regular.ttf'),
              ('MaterialIcons', 'MaterialIcons-Regular.otf'),
            ]) {
              final bytes = await File(
                '$sdk/bin/cache/artifacts/material_fonts/${font.$2}',
              ).readAsBytes();
              await (FontLoader(
                font.$1,
              )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
            }
          });
        }
        final key = GlobalKey(),
            controller = GardenUiController(illustratedGarden());
        await host(
          tester,
          RepaintBoundary(
            key: key,
            child: ProviderScope(
              overrides: [gardenProvider.overrideWith(() => controller)],
              child: GardenEditor(
                garden: controller.garden,
                startInScene: true,
              ),
            ),
          ),
          width: configuration.$1,
          height: configuration.$2,
          scale: configuration.$3,
          brightness: configuration.$4,
          locale: configuration.$5,
        );
        expect(tester.takeException(), isNull);
        expect(find.byType(GardenSceneView), findsOneWidget);
        if (capture != null) {
          await tester.runAsync(() async {
            final boundary =
                key.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final image = await boundary.toImage(pixelRatio: 1.5),
                bytes = await image.toByteData(format: ui.ImageByteFormat.png);
            await Directory(capture).create(recursive: true);
            await File(
              '$capture/garden-scene-${configuration.$1.toInt()}.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        debugDisableShadows = true;
        await tester.tap(find.byKey(const ValueKey('garden-scene-beds')));
        await tester.pumpAndSettle();
        expect(find.text('Paradižnik'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
