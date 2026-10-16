// Opt-in store captures of real widgets using synthetic, memory-only records.
// JIVIE_UPGRADE_CAPTURE=1 flutter test tools/release/upgrade_garden_ideas_capture_test.dart
// Output: build/qa/upgrade-store-20261015/{device}/{sl,en}/{04-ideas,07-garden}.png
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/l10n/app_localizations.dart';
import 'package:kanban/theme/jivie_theme.dart';
import 'package:kanban/organizer/domain/garden_models.dart';
import 'package:kanban/organizer/domain/garden_scene.dart';
import 'package:kanban/organizer/presentation/garden/garden_editor.dart';
import 'package:kanban/organizer/presentation/garden/garden_scene_view.dart';
import 'package:kanban/organizer/presentation/ideas/idea_canvas.dart';
import 'package:kanban/organizer/presentation/ideas/idea_editor.dart';
import 'package:kanban/organizer/presentation/ideas/ideas_page.dart';
import 'package:kanban/organizer/state/garden_provider.dart';
import 'package:kanban/organizer/state/idea_provider.dart';
import 'package:kanban/organizer/state/local_database_provider.dart';
import 'package:kanban/organizer/state/organizer_provider.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';
import '../../test/organizer/ui/ideas_ui_test.dart' as qa;

String _id(int n) => '78000000-0000-4000-8000-${n.toString().padLeft(12, '0')}';
String _t(String language, String sl, String en) => language == 'sl' ? sl : en;

class _GardenCaptureController extends GardenController {
  _GardenCaptureController(this.garden);
  final Garden garden;
  @override
  Future<GardenSnapshot> build() async => GardenSnapshot(gardens: [garden]);
  @override
  Future<void> updateGarden(Garden value, {String? expectedWorkspaceKey}) =>
      throw StateError('Capture must never save the editor');
}

Garden _garden(String language) {
  final names = language == 'sl'
      ? ['Paradižnik', 'Solata', 'Korenje', 'Zelje', 'Buče', 'Fižol']
      : ['Tomatoes', 'Lettuce', 'Carrots', 'Cabbage', 'Pumpkins', 'Beans'];
  final garden = Garden(
    id: _id(1),
    name: _t(language, 'Naš zelenjavni vrt', 'Our vegetable garden'),
    createdAt: DateTime.utc(2026, 1, 1),
    updatedAt: DateTime.utc(2026, 10, 15),
    widthMeters: 6,
    heightMeters: 8,
    areas: [
      for (var i = 0; i < 6; i++)
        GardenArea(
          id: _id(10 + i),
          label: names[i],
          x: i.isEven ? .055 : .535,
          y: .045 + (i ~/ 2) * .32,
          width: .41,
          height: .27,
        ),
    ],
    seasons: [
      GardenSeason(
        year: 2025,
        plantings: [
          GardenPlanting(
            id: _id(100),
            areaId: _id(10),
            crop: _t(language, 'Grah', 'Peas'),
            family: 'Fabaceae',
            status: GardenPlantingStatus.actual,
            plantAt: DateTime.utc(2025, 3, 15),
            harvestAt: DateTime.utc(2025, 6, 20),
            harvested: true,
            illustration: GardenCropIllustration.bean,
            spacingCm: 40,
          ),
        ],
      ),
      GardenSeason(
        year: 2026,
        plantings: [
          for (var i = 0; i < 6; i++)
            GardenPlanting(
              id: _id(200 + i),
              areaId: _id(10 + i),
              crop: names[i],
              family: [
                'Solanaceae',
                'Asteraceae',
                'Apiaceae',
                'Brassicaceae',
                'Cucurbitaceae',
                'Fabaceae',
              ][i],
              status: GardenPlantingStatus.actual,
              plantAt: i == 1
                  ? DateTime.utc(2026, 10, 8)
                  : DateTime.utc(2026, 7, 10),
              spacingCm: [65.0, 50.0, 45.0, 65.0, 95.0, 55.0][i],
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
  garden.validate();
  expect(
    gardenVisualGrowth(
      garden.seasonForYear(2026)!.plantings[0],
      DateTime(2026, 10, 15),
    ),
    1,
  );
  expect(
    gardenVisualGrowth(
      garden.seasonForYear(2026)!.plantings[1],
      DateTime(2026, 10, 15),
    ),
    lessThan(.3),
  );
  expect(
    gardenBedGapMeters(garden, garden.areas[0], garden.areas[1]),
    closeTo(.42, .0001),
  );
  return garden;
}

IdeaBoard _board(String language, IdeaAsset asset) => IdeaBoard(
  id: _id(500),
  title: _t(
    language,
    'Kotiček za jutranjo kavo',
    'A corner for morning coffee',
  ),
  createdAt: DateTime.utc(2026, 10, 15),
  updatedAt: DateTime.utc(2026, 10, 15),
  elements: [
    IdeaElement(
      id: _id(501),
      kind: IdeaElementKind.text,
      x: 20,
      y: 18,
      width: 640,
      height: 60,
      fontSize: 38,
      color: 0xff214c71,
      text: _t(
        language,
        'Naš mali jutranji ritual',
        'Our little morning ritual',
      ),
    ),
    IdeaElement(
      id: _id(502),
      kind: IdeaElementKind.image,
      x: 20,
      y: 100,
      width: 280,
      height: 280 * asset.height / asset.width,
      asset: asset,
    ),
    IdeaElement(
      id: _id(503),
      kind: IdeaElementKind.ellipse,
      x: .08,
      y: .44,
      width: .86,
      height: .22,
      color: 0xffdc3545,
      strokeWidth: .009,
      parentImageId: _id(502),
    ),
    IdeaElement(
      id: _id(504),
      kind: IdeaElementKind.sticky,
      x: 325,
      y: 100,
      width: 320,
      height: 210,
      fontSize: 32,
      color: 0xffffe69a,
      text: _t(
        language,
        'Topel les\nMehka svetloba\nČas za knjigo',
        'Warm wood\nSoft light\nTime for a book',
      ),
    ),
    IdeaElement(
      id: _id(505),
      kind: IdeaElementKind.stroke,
      x: 350,
      y: 350,
      width: 270,
      height: 150,
      strokeWidth: 5,
      color: 0xff2367c8,
      points: const [
        IdeaPoint(0, 12),
        IdeaPoint(180, 0),
        IdeaPoint(260, 30),
        IdeaPoint(70, 50),
        IdeaPoint(0, 12),
        IdeaPoint(0, 100),
        IdeaPoint(70, 140),
        IdeaPoint(70, 50),
        IdeaPoint(260, 30),
        IdeaPoint(260, 120),
        IdeaPoint(70, 140),
      ],
    ),
    IdeaElement(
      id: _id(506),
      kind: IdeaElementKind.stroke,
      x: 515,
      y: 305,
      width: 65,
      height: 58,
      color: 0xff2c854e,
      strokeWidth: 4,
      points: const [
        IdeaPoint(28, 58),
        IdeaPoint(28, 14),
        IdeaPoint(2, 0),
        IdeaPoint(28, 14),
        IdeaPoint(54, 0),
        IdeaPoint(28, 14),
        IdeaPoint(28, 58),
      ],
    ),
    IdeaElement(
      id: _id(507),
      kind: IdeaElementKind.sticky,
      x: 325,
      y: 535,
      width: 320,
      height: 110,
      fontSize: 30,
      color: 0xffd4eadc,
      text: _t(
        language,
        'Polica + rastlina\nob oknu',
        'A shelf + a plant\nby the window',
      ),
    ),
  ],
);

Future<void> _fonts(WidgetTester tester, bool ios) async {
  await tester.runAsync(() async {
    final sdk = Platform.resolvedExecutable.split('/bin/cache/').first;
    final font = await File(
      ios
          ? '/System/Library/Fonts/SFNS.ttf'
          : '$sdk/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
    ).readAsBytes();
    for (final family
        in ios
            ? [
                'CupertinoSystemText',
                'CupertinoSystemDisplay',
                '.SF UI Text',
                '.SF UI Display',
                'Roboto',
              ]
            : ['Roboto']) {
      await (FontLoader(
        family,
      )..addFont(Future.value(ByteData.sublistView(font)))).load();
    }
    final icons = await File(
      '$sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    ).readAsBytes();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(Future.value(ByteData.sublistView(icons)))).load();
  });
}

void main() {
  final enabled = Platform.environment['JIVIE_UPGRADE_CAPTURE'] == '1';
  final onlyDevice = Platform.environment['JIVIE_UPGRADE_CAPTURE_DEVICE'];
  final onlyLanguage = Platform.environment['JIVIE_UPGRADE_CAPTURE_LOCALE'];
  for (final device in ['android-phone', 'ios-iphone', 'ios-ipad']) {
    if (Platform.environment['JIVIE_ANDROID_CAPTURE_ONLY'] == '1' &&
        device != 'android-phone') {
      continue;
    }
    for (final language in ['sl', 'en']) {
      testWidgets(
        'upgrade garden and ideas capture $device $language',
        (tester) async {
          final originalDisableShadows = debugDisableShadows;
          debugDisableShadows = false;
          addTearDown(() => debugDisableShadows = originalDisableShadows);
          final ios = device != 'android-phone';
          final ipad = device == 'ios-ipad';
          final size = ipad
              ? const Size(1032, 1376)
              : ios
              ? const Size(440, 956)
              : const Size(360, 640);
          final ratio = ipad
              ? 2.0
              : ios
              ? 3.0
              : 2.0;
          debugDefaultTargetPlatformOverride = ios
              ? TargetPlatform.iOS
              : TargetPlatform.android;
          addTearDown(() => debugDefaultTargetPlatformOverride = null);
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          tester.view.padding = FakeViewPadding(
            top: ipad
                ? 24
                : ios
                ? 62
                : 24,
            bottom: ipad
                ? 20
                : ios
                ? 34
                : 16,
          );
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPadding);
          await _fonts(tester, ios);
          final fixture = await qa.fixture(tester);
          final garden = _garden(language);
          late IdeaAsset asset;
          late IdeaBoard board;
          await tester.runAsync(() async {
            asset = await fixture.ideas.importImage(
              await File(
                'tools/release/fixtures/ideas-coffee.jpg',
              ).readAsBytes(),
            );
            board = _board(language, asset);
            await fixture.ideas.saveBoard(board, isNew: true);
          });
          final key = GlobalKey();
          Widget host(Widget home) => ProviderScope(
            overrides: [
              localDatabaseProvider.overrideWith((ref) async => fixture.db),
              ideaRepositoryProvider.overrideWith((ref) async => fixture.ideas),
              organizerRepositoryProvider.overrideWith(
                (ref) async => fixture.organizer,
              ),
              collaborationRepositoryProvider.overrideWith(
                (ref) async => fixture.shared,
              ),
              gardenProvider.overrideWith(
                () => _GardenCaptureController(garden),
              ),
            ],
            child: RepaintBoundary(
              key: key,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                locale: Locale(language),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                theme: buildJivieTheme(Brightness.light),
                home: home,
              ),
            ),
          );
          final output =
              Platform.environment['JIVIE_UPGRADE_CAPTURE_OUT'] ??
              Platform.environment['JIVIE_STORE_CAPTURE_OUT'] ??
              'build/qa/upgrade-store-20261015';
          Future<void> capture(String name) async {
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            await tester.runAsync(() async {
              final boundary =
                  key.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary;
              final image = await boundary.toImage(pixelRatio: ratio);
              expect(image.width, (size.width * ratio).round());
              expect(image.height, (size.height * ratio).round());
              final data = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final file = File('$output/$device/$language/$name.png');
              await file.parent.create(recursive: true);
              await file.writeAsBytes(data!.buffer.asUint8List());
              image.dispose();
            });
          }

          await tester.pumpWidget(
            host(
              Scaffold(
                body: Consumer(
                  builder: (context, ref, _) {
                    ref.watch(collaborationProvider);
                    return const SingleChildScrollView(child: IdeasPage());
                  },
                ),
              ),
            ),
          );
          await qa.settle(tester);
          await tester.tap(find.byKey(ValueKey('idea-card-${board.id}')));
          await qa.settle(tester);
          expect(find.byType(IdeaEditor), findsOneWidget);
          final canvas = tester.widget<IdeaCanvas>(find.byType(IdeaCanvas));
          expect(
            canvas.images[asset.sha256],
            isNotNull,
            reason: 'Photo must decode through the actual asset cache',
          );
          expect(canvas.editable, isTrue);
          final viewport = find.byKey(const ValueKey('idea-viewport'));
          final rect = tester.getRect(viewport);
          final zoom = math.min(
            (rect.width - 16) / 665,
            (rect.height - 16) / 665,
          );
          final viewer = tester.widget<InteractiveViewer>(viewport);
          viewer.transformationController!.value = Matrix4.identity()
            ..translateByDouble(
              (rect.width - 665 * zoom) / 2,
              (rect.height - 665 * zoom) / 2,
              0,
              1,
            )
            ..scaleByDouble(zoom, zoom, 1, 1);
          await capture('04-ideas');
          // Replace the route tree without saving or interacting with fixture data.
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpWidget(host(const Scaffold()));
          // Match GardenPage._open: the editor is a pushed page, with a
          // real route underneath it for native back navigation.
          final navigator = tester.state<NavigatorState>(
            find.byType(Navigator),
          );
          unawaited(
            navigator.push<void>(
              MaterialPageRoute(
                builder: (_) =>
                    GardenEditor(garden: garden, startInScene: true),
              ),
            ),
          );
          await qa.settle(tester);
          expect(navigator.canPop(), isTrue);
          expect(find.byIcon(Icons.arrow_back), findsOneWidget);
          expect(find.byType(GardenSceneView), findsOneWidget);
          expect(
            tester
                .widget<GardenSceneView>(find.byType(GardenSceneView))
                .garden
                .toJson(),
            garden.toJson(),
          );
          await capture('07-garden');
          debugDefaultTargetPlatformOverride = null;
          debugDisableShadows = originalDisableShadows;
          await qa.close(tester, fixture);
        },
        skip:
            !enabled ||
            (onlyDevice != null && onlyDevice != device) ||
            (onlyLanguage != null && onlyLanguage != language),
      );
    }
  }
}
