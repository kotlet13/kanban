import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/l10n/app_localizations.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/garden_repository.dart';
import 'package:kanban/organizer/data/garden_storage.dart';
import 'package:kanban/organizer/domain/garden_models.dart';
import 'package:kanban/organizer/presentation/garden/garden_bed_detail.dart';
import 'package:kanban/organizer/presentation/garden/garden_canvas.dart';
import 'package:kanban/organizer/presentation/garden/garden_editor.dart';
import 'package:kanban/organizer/presentation/garden/garden_page.dart';
import 'package:kanban/organizer/state/garden_provider.dart';

const areaA = GardenArea(
  id: '22222222-2222-4222-8222-222222222222',
  label: 'Greda A',
  x: .1,
  y: .2,
  width: .3,
  height: .2,
);
const areaB = GardenArea(
  id: '44444444-4444-4444-8444-444444444444',
  label: 'Greda B',
  x: .6,
  y: .2,
  width: .3,
  height: .2,
);

class GardenSqlFixture {
  GardenSqlFixture(this.directory);
  final Directory directory;
  late CollaborationDatabase db;
  late GardenRepository repo;
  Future<void> open() async {
    db = CollaborationDatabase(
      NativeDatabase(File('${directory.path}/garden.sqlite')),
    );
    repo = GardenRepository(GardenStorage(db));
    await repo.initialize();
  }

  Future<void> close() async {
    await repo.close();
    await db.close();
  }
}

Future<GardenSqlFixture> fixture(WidgetTester tester) async {
  final fixture = (await tester.runAsync(() async {
    final fixture = GardenSqlFixture(
      await Directory.systemTemp.createTemp('garden-ui-integration-'),
    );
    await fixture.open();
    return fixture;
  }))!;
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() async {
      await fixture.close();
      await fixture.directory.delete(recursive: true);
    });
  });
  return fixture;
}

Future<void> host(WidgetTester tester, GardenRepository repo) async {
  tester.view.physicalSize = const Size(1280, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [gardenRepositoryProvider.overrideWith((ref) async => repo)],
      child: MaterialApp(
        locale: const Locale('sl'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
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

Future<void> tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> save(WidgetTester tester, GardenRepository repo) async {
  await tester.runAsync(() async {
    await tester.tap(find.byKey(const ValueKey('garden-save')));
    await repo.reload();
  });
  await tester.pumpAndSettle();
}

Garden draft(WidgetTester tester) =>
    tester.widget<GardenBedDetail>(find.byType(GardenBedDetail)).garden;
Future<void> addArea(WidgetTester tester, String label) async {
  await tap(tester, find.byKey(const ValueKey('garden-add-area')));
  await tester.enterText(
    find.byKey(const ValueKey('garden-area-label')),
    label,
  );
  await tap(tester, find.byKey(const ValueKey('garden-area-save')));
}

Future<void> addSeason(WidgetTester tester, int year, {int? copyFrom}) async {
  await tap(tester, find.byKey(const ValueKey('garden-new-season')));
  await tester.enterText(
    find.byKey(const ValueKey('garden-season-year')),
    '$year',
  );
  if (copyFrom != null) {
    await tap(tester, find.byKey(const ValueKey('garden-season-copy')));
    await tap(tester, find.text('$copyFrom').last);
  }
  await tap(tester, find.byKey(const ValueKey('garden-season-save')));
}

Future<void> selectYear(WidgetTester tester, int year) async {
  final picker = find.byWidgetPredicate(
    (w) => w is DropdownButtonFormField<int>,
  );
  await tap(tester, picker);
  await tap(tester, find.text('$year').last);
}

Future<void> selectArea(WidgetTester tester, String areaId) =>
    tap(tester, find.byKey(ValueKey('garden-area-$areaId')));
Future<void> date(WidgetTester tester, int field) async {
  await tap(tester, find.byKey(ValueKey('garden-planting-date-$field')));
  await tap(tester, find.text('15').last);
  final label = MaterialLocalizations.of(
    tester.element(find.byType(DatePickerDialog)),
  ).okButtonLabel;
  await tap(tester, find.text(label));
}

Future<void> addPlanting(
  WidgetTester tester,
  String areaId,
  String crop, {
  bool actual = false,
  bool dates = false,
}) async {
  await tap(tester, find.byKey(ValueKey('garden-add-planting-$areaId')));
  await tester.enterText(find.byKey(const ValueKey('garden-crop')), crop);
  await tester.enterText(
    find.byKey(const ValueKey('garden-variety')),
    'Moja sorta',
  );
  await tester.enterText(
    find.byKey(const ValueKey('garden-family')),
    'Solanaceae',
  );
  await tester.enterText(
    find.byKey(const ValueKey('garden-planting-notes')),
    'Opomba zasaditve',
  );
  if (actual) {
    await tap(tester, find.byKey(const ValueKey('garden-planting-status')));
    await tap(tester, find.text('Dejanska zasaditev').last);
  }
  if (dates) {
    for (var i = 0; i < 3; i++) {
      await date(tester, i);
    }
  }
  await tap(tester, find.byKey(const ValueKey('garden-planting-save')));
}

Future<void> openSaved(WidgetTester tester, GardenRepository repo) async {
  await tap(
    tester,
    find.byKey(ValueKey('garden-${repo.snapshot.gardens.single.id}')),
  );
}

Future<void> seed(
  WidgetTester tester,
  GardenRepository repo, {
  List<GardenArea> areas = const [areaA, areaB],
}) async {
  await tester.runAsync(
    () => repo.createGarden(
      name: 'Moj vrt',
      areas: areas,
      seasons: [
        GardenSeason(
          year: 2026,
          notes: 'Prvotno 2026',
          plantings: [
            GardenPlanting(
              id: '33333333-3333-4333-8333-333333333333',
              areaId: areaA.id,
              crop: 'Paradižnik',
              family: 'Solanaceae',
              status: GardenPlantingStatus.actual,
            ),
          ],
        ),
        GardenSeason(year: 2027, notes: 'Prvotno 2027'),
      ],
    ),
  );
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  testWidgets(
    'new garden, actual crop and explicit season copy survive Save and actual SQLite reopen',
    (tester) async {
      final f = await fixture(tester);
      await host(tester, f.repo);
      await tap(tester, find.text('Nov vrt'));
      await tester.enterText(
        find.byKey(const ValueKey('garden-name')),
        'Moj novi vrt',
      );
      await addArea(tester, 'Moja greda');
      final areaId = draft(tester).areas.single.id;
      await addSeason(tester, 2026);
      await addPlanting(
        tester,
        areaId,
        'Paradižnik',
        actual: true,
        dates: true,
      );
      await addPlanting(tester, areaId, 'Paprika', actual: true);
      await tester.enterText(
        find.byKey(const ValueKey('garden-season-notes-2026')),
        'Sezonski zapis 2026',
      );
      await addSeason(tester, 2027, copyFrom: 2026);
      await tester.enterText(
        find.byKey(const ValueKey('garden-season-notes-2027')),
        'Načrt 2027',
      );
      await tester.pumpAndSettle();
      final expected = draft(tester);
      final originals = expected.seasonForYear(2026)!.plantings;
      final copies = expected.seasonForYear(2027)!.plantings;
      expect(originals.length, 2);
      expect(copies.length, 2);
      expect(
        copies
            .map((p) => p.id)
            .toSet()
            .intersection(originals.map((p) => p.id).toSet()),
        isEmpty,
      );
      expect(
        copies.every(
          (p) =>
              p.status == GardenPlantingStatus.planned &&
              p.sowAt == null &&
              p.plantAt == null &&
              p.harvestAt == null,
        ),
        isTrue,
      );
      expect(f.repo.snapshot.gardens, isEmpty);
      await selectYear(tester, 2026);
      expect(find.text('Sezonski zapis 2026'), findsOneWidget);
      await save(tester, f.repo);
      expect(find.byType(GardenEditor), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async {
        await f.close();
        await f.open();
      });
      final saved = f.repo.snapshot.gardens.single;
      expect(
        saved.areas.map((a) => a.toJson()).toList(),
        expected.areas.map((a) => a.toJson()).toList(),
      );
      expect(
        saved.seasons.map((s) => s.toJson()).toList(),
        expected.seasons.map((s) => s.toJson()).toList(),
      );
      expect(saved.seasonForYear(2026)!.plantings.first.sowAt, isNotNull);
      expect(saved.seasonForYear(2026)!.plantings.first.variety, 'Moja sorta');
      expect(
        await tester.runAsync(() => f.db.rows('SELECT * FROM outbox')),
        isEmpty,
      );
      await host(tester, f.repo);
      await openSaved(tester, f.repo);
      expect(find.text('Načrt 2027'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'draft season notes survive year and bed changes, remain uncommitted, and save both years',
    (tester) async {
      final f = await fixture(tester);
      await seed(tester, f.repo);
      final original = f.repo.snapshot.toJson();
      await host(tester, f.repo);
      await openSaved(tester, f.repo);
      await tester.enterText(
        find.byKey(const ValueKey('garden-season-notes-2027')),
        'Urejeno 2027',
      );
      await selectArea(tester, areaB.id);
      expect(find.text('Urejeno 2027'), findsOneWidget);
      await selectYear(tester, 2026);
      expect(find.text('Prvotno 2026'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('garden-season-notes-2026')),
        'Urejeno 2026',
      );
      await selectYear(tester, 2027);
      expect(find.text('Urejeno 2027'), findsOneWidget);
      await tap(tester, find.byIcon(Icons.arrow_back));
      expect(find.text('Neshranjene spremembe'), findsOneWidget);
      await tap(tester, find.text('Nadaljuj urejanje'));
      expect(f.repo.snapshot.toJson(), original);
      await save(tester, f.repo);
      final saved = f.repo.snapshot.gardens.single;
      expect(saved.seasonForYear(2026)!.notes, 'Urejeno 2026');
      expect(saved.seasonForYear(2027)!.notes, 'Urejeno 2027');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'archived bed remains in saved history and is excluded from explicit copy into a new season',
    (tester) async {
      final f = await fixture(tester);
      await seed(tester, f.repo);
      await host(tester, f.repo);
      await openSaved(tester, f.repo);
      await tap(tester, find.text('Upokoji gredo'));
      expect(draft(tester).areas.first.archived, isTrue);
      expect(
        tester
            .widget<GardenCanvas>(find.byType(GardenCanvas))
            .areas
            .any((a) => a.id == areaA.id),
        isFalse,
      );
      await addSeason(tester, 2028, copyFrom: 2026);
      expect(draft(tester).seasonForYear(2028)!.plantings, isEmpty);
      expect(
        draft(tester).seasonForYear(2026)!.plantings.single.crop,
        'Paradižnik',
      );
      await save(tester, f.repo);
      final saved = f.repo.snapshot.gardens.single;
      expect(saved.areas.first.archived, isTrue);
      expect(saved.areas.first.id, areaA.id);
      expect(saved.seasonForYear(2026)!.plantings.single.crop, 'Paradižnik');
      await openSaved(tester, f.repo);
      await selectArea(tester, areaA.id);
      expect(
        find.byKey(ValueKey('garden-history-${areaA.id}-2026')),
        findsOneWidget,
      );
      await tap(tester, find.text('Obnovi gredo'));
      await save(tester, f.repo);
      expect(f.repo.snapshot.gardens.single.areas.first.archived, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'geometry undo after planting in a newly added bed keeps referentially valid recoverable draft',
    (tester) async {
      final f = await fixture(tester);
      await seed(tester, f.repo, areas: [areaA]);
      await host(tester, f.repo);
      await openSaved(tester, f.repo);
      await addArea(tester, 'Nova greda B');
      final areaId = draft(tester).areas.last.id;
      await addPlanting(tester, areaId, 'Grah');
      final seasonalContent = draft(
        tester,
      ).seasons.map((s) => s.toJson()).toList();
      await tap(tester, find.byTooltip('Razveljavi spremembo razporeditve'));
      expect(draft(tester).validate, returnsNormally);
      expect(
        draft(tester).seasons.map((s) => s.toJson()).toList(),
        seasonalContent,
      );
      await save(tester, f.repo);
      expect(find.byType(GardenEditor), findsNothing);
      expect(
        f.repo.snapshot.gardens.single
            .seasonForYear(2027)!
            .plantings
            .single
            .crop,
        'Grah',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'renaming a legacy sub-one-percent area preserves its original ID and exact geometry',
    (tester) async {
      final f = await fixture(tester);
      final tiny = areaA.copyWith(
        x: .12345678,
        y: .23456789,
        width: .0004,
        height: .0006,
      );
      await tester.runAsync(
        () => f.repo.createGarden(name: 'Stara skica', areas: [tiny]),
      );
      await host(tester, f.repo);
      await openSaved(tester, f.repo);
      final tile = find.byKey(ValueKey('garden-area-${tiny.id}'));
      await tap(
        tester,
        find.descendant(of: tile, matching: find.byType(IconButton)),
      );
      await tester.enterText(
        find.byKey(const ValueKey('garden-area-label')),
        'Preimenovana stara greda',
      );
      await tap(tester, find.byKey(const ValueKey('garden-area-save')));
      expect(find.byType(AlertDialog), findsNothing);
      await save(tester, f.repo);
      final saved = f.repo.snapshot.gardens.single.areas.single;
      expect(
        (saved.id, saved.x, saved.y, saved.width, saved.height),
        (tiny.id, tiny.x, tiny.y, tiny.width, tiny.height),
      );
      expect(saved.label, 'Preimenovana stara greda');
      expect(tester.takeException(), isNull);
    },
  );
}
