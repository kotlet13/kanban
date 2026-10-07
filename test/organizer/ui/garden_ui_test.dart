import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/l10n/app_localizations.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/garden_repository.dart';
import 'package:kanban/organizer/data/garden_storage.dart';
import 'package:kanban/organizer/domain/garden_models.dart';
import 'package:kanban/organizer/presentation/garden/garden_canvas.dart';
import 'package:kanban/organizer/presentation/garden/garden_editor.dart';
import 'package:kanban/organizer/presentation/garden/garden_page.dart';
import 'package:kanban/organizer/state/garden_provider.dart';
import 'organizer_ui_test.dart' show pumpOrganizer, MemoryOrganizerStorage;

void main() {
  Future<GardenRepository> repository(WidgetTester tester) async {
    final repo = (await tester.runAsync(() async {
      // Keep the SQL repository's stream subscription in the real async zone.
      // A subscription created in FakeAsync can start a SQLite transaction
      // which then waits for real I/O while widget timers are being pumped.
      final db = CollaborationDatabase(NativeDatabase.memory());
      final repo = GardenRepository(GardenStorage(db));
      await repo.initialize();
      return repo;
    }))!;
    addTearDown(() async {
      await repo.close();
      await repo.storage.database.close();
    });
    return repo;
  }

  Future<void> pump(
    WidgetTester tester,
    GardenRepository repo, {
    double width = 390,
    String locale = 'sl',
    Brightness brightness = Brightness.light,
  }) async {
    tester.view.physicalSize = Size(width, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [gardenRepositoryProvider.overrideWith((ref) async => repo)],
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
          home: const Scaffold(
            body: SingleChildScrollView(
              padding: EdgeInsets.all(20),
              child: GardenPage(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> save(WidgetTester tester, GardenRepository repo) async {
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('garden-save')));
      // Reload is queued after the button's mutation (including a rejected
      // stale save), so this awaits SQL completion without wall-clock guesses.
      await repo.reload();
    });
    await tester.pumpAndSettle();
  }

  testWidgets(
    'garden form saves notes and area, reopens from storage, and deletes',
    (tester) async {
      final repo = await repository(tester);
      await pump(tester, repo);
      await tester.tap(find.text('Nov vrt'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('garden-name')),
        'Zelenjavni vrt',
      );
      await tester.enterText(
        find.byKey(const ValueKey('garden-notes')),
        'Zalij zvečer.',
      );
      await tester.ensureVisible(find.byKey(const ValueKey('garden-add-area')));
      await tester.tap(find.byKey(const ValueKey('garden-add-area')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('garden-area-label')),
        'Paradižniki',
      );
      await tester.enterText(
        find.byKey(const ValueKey('garden-area-number-0')),
        '90',
      );
      await tester.enterText(
        find.byKey(const ValueKey('garden-area-number-2')),
        '20',
      );
      await tester.tap(find.byKey(const ValueKey('garden-area-save')));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Območje mora v celoti ostati znotraj skice. Zmanjšaj velikost ali popravi položaj.',
        ),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const ValueKey('garden-area-number-2')),
        '10',
      );
      await tester.tap(find.byKey(const ValueKey('garden-area-save')));
      await tester.pumpAndSettle();
      await save(tester, repo);
      final stored = await tester.runAsync(repo.storage.read);
      expect(stored!.gardens.single.name, 'Zelenjavni vrt');
      expect(stored.gardens.single.notes, 'Zalij zvečer.');
      expect(stored.gardens.single.areas.single.label, 'Paradižniki');
      expect(
        stored.gardens.single.areas.single.x +
            stored.gardens.single.areas.single.width,
        1,
      );
      await tester.tap(find.text('Zelenjavni vrt'));
      await tester.pumpAndSettle();
      expect(find.byType(GardenEditor), findsOneWidget);
      expect(find.text('Zalij zvečer.'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('garden-notes')),
        'Obrezano.',
      );
      await save(tester, repo);
      expect(repo.snapshot.gardens.single.notes, 'Obrezano.');
      await tester.runAsync(() => tester.tap(find.byTooltip('Izbriši')));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('garden-confirm-delete')));
        await Future<void>.value();
        await repo.reload();
      });
      await tester.pumpAndSettle();
      expect((await tester.runAsync(repo.storage.read))!.gardens, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'back preserves unsaved draft until explicit discard, without writing',
    (tester) async {
      final repo = await repository(tester);
      await pump(tester, repo, width: 320);
      await tester.tap(find.text('Nov vrt'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('garden-name')),
        'Osnutek',
      );
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(find.text('Neshranjene spremembe'), findsOneWidget);
      await tester.tap(find.text('Nadaljuj urejanje'));
      await tester.pumpAndSettle();
      expect(find.text('Osnutek'), findsOneWidget);
      expect(repo.snapshot.gardens, isEmpty);
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('garden-discard')));
      await tester.pumpAndSettle();
      expect(find.byType(GardenEditor), findsNothing);
      expect(repo.snapshot.gardens, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'stale garden save keeps the draft and preserves the newer record',
    (tester) async {
      final repo = await repository(tester);
      await tester.runAsync(
        () => repo.createGarden(name: 'Vrt', notes: 'Prvotno'),
      );
      await pump(tester, repo);
      await tester.tap(find.text('Vrt').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('garden-notes')),
        'Moj osnutek',
      );
      await tester.runAsync(
        () => repo.updateGarden(
          repo.snapshot.gardens.single.copyWith(notes: 'Novejši zapis'),
        ),
      );
      await save(tester, repo);
      expect(find.byType(GardenEditor), findsOneWidget);
      expect(find.text('Moj osnutek'), findsOneWidget);
      expect(repo.snapshot.gardens.single.notes, 'Novejši zapis');
      expect(find.textContaining('Osnutek je še odprt.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'draw then move uses bounded normalized geometry and commits on release',
    (tester) async {
      Rect? drawn;
      GardenArea? moved;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              child: GardenCanvas(
                areas: const [],
                tool: GardenTool.draw,
                selectedId: null,
                onSelect: (_) {},
                onDraw: (rect) => drawn = rect,
                onMove: (_) {},
                semanticLabel: 'Sketch',
              ),
            ),
          ),
        ),
      );
      final canvas = find.byKey(const ValueKey('garden-canvas'));
      final rect = tester.getRect(canvas);
      final gesture = await tester.startGesture(
        rect.topLeft + const Offset(40, 30),
      );
      await gesture.moveTo(rect.topLeft + const Offset(160, 120));
      await tester.pump();
      expect(drawn, isNull);
      await gesture.up();
      await tester.pump();
      expect(drawn!.left, closeTo(.1, .005));
      expect(drawn!.width, closeTo(.3, .005));
      final edge = await tester.startGesture(
        rect.topLeft + const Offset(41, 31),
      );
      await edge.moveTo(rect.bottomRight);
      await edge.up();
      await tester.pump();
      final edgeArea = GardenArea(
        id: '00000000-0000-4000-8000-000000000001',
        label: 'Edge',
        x: drawn!.left,
        y: drawn!.top,
        width: drawn!.width,
        height: drawn!.height,
      );
      expect(edgeArea.validate, returnsNormally);
      expect(edgeArea.x + edgeArea.width, 1);
      expect(edgeArea.y + edgeArea.height, 1);
      const area = GardenArea(
        id: 'a',
        label: 'Bed',
        x: .1,
        y: .1,
        width: .3,
        height: .3,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              child: GardenCanvas(
                areas: const [area],
                tool: GardenTool.select,
                selectedId: 'a',
                onSelect: (_) {},
                onDraw: (_) {},
                onMove: (area) => moved = area,
                semanticLabel: 'Sketch',
              ),
            ),
          ),
        ),
      );
      final next = tester.getRect(canvas);
      await tester.dragFrom(
        next.topLeft + const Offset(60, 50),
        const Offset(500, 500),
      );
      await tester.pump();
      expect(moved!.x, closeTo(.7, .0001));
      expect(moved!.y, closeTo(.7, .0001));
      expect(tester.takeException(), isNull);
    },
  );

  for (final height in [640.0, 720.0]) {
    testWidgets(
      'desktop garden navigation remains accessible at height $height',
      (tester) async {
        final repo = await repository(tester);
        await pumpOrganizer(
          tester,
          MemoryOrganizerStorage(),
          width: 1280,
          height: height,
          gardenRepository: repo,
        );
        final gardenTile = find.widgetWithText(ListTile, 'Vrt');
        await tester.scrollUntilVisible(
          gardenTile,
          100,
          scrollable: find.descendant(
            of: find.byType(ListView).first,
            matching: find.byType(Scrollable),
          ),
        );
        await tester.tap(gardenTile);
        await tester.pumpAndSettle();
        expect(find.byType(GardenPage), findsOneWidget);
        expect(find.text('Tvoj prvi vrt'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final width in [320.0, 390.0, 1280.0]) {
    for (final locale in ['sl', 'en']) {
      for (final brightness in [Brightness.light, Brightness.dark]) {
        testWidgets('garden editor fits $width $locale $brightness', (
          tester,
        ) async {
          final repo = await repository(tester);
          await pump(
            tester,
            repo,
            width: width,
            locale: locale,
            brightness: brightness,
          );
          await tester.tap(
            find.text(locale == 'sl' ? 'Nov vrt' : 'New garden'),
          );
          await tester.pumpAndSettle();
          await tester.ensureVisible(
            find.byKey(const ValueKey('garden-canvas')),
          );
          await tester.pumpAndSettle();
          expect(find.byType(GardenCanvas), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.ensureVisible(
            find.byKey(const ValueKey('garden-add-area')),
          );
          await tester.tap(find.byKey(const ValueKey('garden-add-area')));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}
