// Store/website capture only. Run in the isolated, frozen Android25 source copy.
// No installed profile, server, credentials or Android build is changed.
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/l10n/app_localizations.dart';
import 'package:kanban/theme/jivie_theme.dart';
import 'package:kanban/organizer/domain/idea_models.dart';
import 'package:kanban/organizer/presentation/ideas/idea_canvas.dart';
import 'package:kanban/organizer/presentation/ideas/idea_editor.dart';
import 'package:kanban/organizer/presentation/ideas/ideas_page.dart';
import 'package:kanban/organizer/state/idea_provider.dart';
import 'package:kanban/organizer/state/local_database_provider.dart';
import 'package:kanban/organizer/state/organizer_provider.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';
import '../../test/organizer/ui/ideas_ui_test.dart' as qa;

String id(int n) => '76000000-0000-4000-8000-${n.toString().padLeft(12, '0')}';

void main() {
  testWidgets(
    'capture open Android25 idea board with real photo, drawing, notes and attached markings',
    (tester) async {
      final output = Platform.environment['JIVIE_IDEA_CAPTURE_OUT'];
      final photo = Platform.environment['JIVIE_IDEA_CAPTURE_PHOTO'];
      if (output == null || photo == null)
        throw StateError('Explicit fixture input/output required');
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 24, bottom: 16);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPadding);
      await tester.runAsync(() async {
        final sdk = Platform.resolvedExecutable.split('/bin/cache/').first;
        final bytes = await File(
          '$sdk/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
        ).readAsBytes();
        await (FontLoader(
          'Roboto',
        )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
        final icons = await File(
          '$sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
        ).readAsBytes();
        await (FontLoader(
          'MaterialIcons',
        )..addFont(Future.value(ByteData.sublistView(icons)))).load();
      });
      final fixture = await qa.fixture(tester);
      late IdeaAsset asset;
      late IdeaBoard board;
      await tester.runAsync(() async {
        asset = await fixture.ideas.importImage(
          await File(photo).readAsBytes(),
        );
        final now = DateTime.utc(2026, 10, 13);
        board = IdeaBoard(
          id: id(1),
          title: 'Kotiček za jutranjo kavo',
          createdAt: now,
          updatedAt: now,
          elements: [
            IdeaElement(
              id: id(2),
              kind: IdeaElementKind.image,
              x: 40,
              y: 60,
              width: 330,
              height: 330 * asset.height / asset.width,
              asset: asset,
            ),
            IdeaElement(
              id: id(3),
              kind: IdeaElementKind.ellipse,
              x: .08,
              y: .44,
              width: .86,
              height: .22,
              color: 0xffdc3545,
              strokeWidth: .009,
              parentImageId: id(2),
            ),
            IdeaElement(
              id: id(4),
              kind: IdeaElementKind.sticky,
              x: 400,
              y: 95,
              width: 300,
              height: 170,
              color: 0xffffe69a,
              text: 'Topel les\nMehka svetloba\nProstor za knjigo',
            ),
            IdeaElement(
              id: id(5),
              kind: IdeaElementKind.sticky,
              x: 400,
              y: 465,
              width: 300,
              height: 140,
              color: 0xffd4eadc,
              text: 'Mala polica\n+ rastlina\nob oknu',
            ),
            IdeaElement(
              id: id(6),
              kind: IdeaElementKind.stroke,
              x: 440,
              y: 345,
              width: 210,
              height: 130,
              color: 0xff2367c8,
              strokeWidth: 4,
              points: const [
                IdeaPoint(0, 12),
                IdeaPoint(130, 0),
                IdeaPoint(190, 20),
                IdeaPoint(50, 35),
                IdeaPoint(0, 12),
                IdeaPoint(0, 95),
                IdeaPoint(50, 116),
                IdeaPoint(50, 35),
                IdeaPoint(190, 20),
                IdeaPoint(190, 98),
                IdeaPoint(50, 116),
              ],
            ),
            IdeaElement(
              id: id(7),
              kind: IdeaElementKind.stroke,
              x: 582,
              y: 316,
              width: 55,
              height: 40,
              color: 0xff2c854e,
              strokeWidth: 3,
              points: const [
                IdeaPoint(18, 38),
                IdeaPoint(18, 8),
                IdeaPoint(4, 0),
                IdeaPoint(18, 8),
                IdeaPoint(32, 0),
                IdeaPoint(18, 8),
                IdeaPoint(18, 38),
              ],
            ),
            IdeaElement(
              id: id(8),
              kind: IdeaElementKind.arrow,
              x: .85,
              y: .61,
              width: .45,
              height: .06,
              color: 0xffdc3545,
              strokeWidth: .009,
              points: const [IdeaPoint(.45, .06), IdeaPoint(0, 0)],
              parentImageId: id(2),
            ),
          ],
        );
        await fixture.ideas.saveBoard(board, isNew: true);
        final normalized = await fixture.ideas.readAsset(asset);
        await File('$output/coffee-normalized.jpg').writeAsBytes(normalized!);
      });
      final key = GlobalKey();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localDatabaseProvider.overrideWith((ref) async => fixture.db),
            ideaRepositoryProvider.overrideWith((ref) async => fixture.ideas),
            organizerRepositoryProvider.overrideWith(
              (ref) async => fixture.organizer,
            ),
            collaborationRepositoryProvider.overrideWith(
              (ref) async => fixture.shared,
            ),
          ],
          child: RepaintBoundary(
            key: key,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              locale: const Locale('sl'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              theme: buildJivieTheme(Brightness.light),
              home: Scaffold(
                body: Consumer(
                  builder: (context, ref, _) {
                    ref.watch(collaborationProvider);
                    return const SingleChildScrollView(child: IdeasPage());
                  },
                ),
              ),
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
        reason: 'The actual cached photo must be decoded, not a placeholder.',
      );
      expect(canvas.editable, isTrue);
      expect(
        canvas.board.elements
            .where((e) => e.kind == IdeaElementKind.stroke)
            .length,
        2,
      );
      // Viewport positioning only: this is the same camera available through Pan/zoom.
      // Board geometry, image bytes, annotations and all UI pixels remain unmodified.
      final viewer = tester.widget<InteractiveViewer>(
        find.byKey(const ValueKey('idea-viewport')),
      );
      viewer.transformationController!.value = Matrix4.identity()
        ..translateByDouble(-4, -12, 0, 1)
        ..scaleByDouble(.45, .45, 1, 1);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        expect(image.width, 720);
        expect(image.height, 1280);
        await File(
          '$output/07-ideas-board.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
      await qa.close(tester, fixture);
      debugDefaultTargetPlatformOverride = null;
    },
  );
}
