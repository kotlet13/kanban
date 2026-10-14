import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';
import 'package:kanban/organizer/state/organizer_provider.dart';

import 'organizer_ui_test.dart' show MemoryOrganizerStorage, pumpOrganizer;
import 'local_spaces_navigation_test.dart'
    show LocalSpaceUiController, loadCaptureFonts;
import 'sharing_ui_fixture.dart';
import 'unified_navigation_test.dart' show NavigationIdeaController;

class _DesktopCatalog extends LocalSpaceUiController {
  _DesktopCatalog(this.store) : super(LocalSpaceKind.personal);
  final MemoryOrganizerStorage store;
  @override
  Future<LocalSpacesState> build() async => LocalSpacesState(
    spaces: const [
      LocalSpace(id: 'local', name: '', kind: LocalSpaceKind.personal),
    ],
    snapshots: {'local': store.snapshot},
  );
  @override
  Future<void> selectSpace(String id) async {
    final previous = state.requireValue;
    state = AsyncData(
      LocalSpacesState(
        spaces: previous.spaces,
        selectedSpaceId: id,
        snapshots: {'local': store.snapshot},
      ),
    );
  }

  void refresh(OrganizerSnapshot snapshot) {
    final previous = state.requireValue;
    state = AsyncData(
      LocalSpacesState(
        spaces: previous.spaces,
        selectedSpaceId: previous.selectedSpaceId,
        snapshots: {'local': snapshot},
      ),
    );
  }
}

MemoryOrganizerStorage _storage() {
  final now = DateTime.now();
  final day = DateTime(now.year, now.month, now.day);
  return MemoryOrganizerStorage()
    ..snapshot = OrganizerSnapshot(
      tasks: [
        LocalTask(
          id: 'desktop-task',
          title: 'Izberi lončke za zelišča',
          notes: 'Za balkon.',
          dueAt: day.add(const Duration(hours: 18)),
          isCompleted: false,
          projectId: 'desktop-project',
          createdAt: day,
          updatedAt: day,
        ),
      ],
      events: [
        LocalEvent(
          id: 'desktop-event',
          title: 'Sprehod ob jezeru',
          notes: '',
          startsAt: day.add(const Duration(hours: 17)),
          endsAt: day.add(const Duration(hours: 18)),
          projectId: null,
          createdAt: day,
          updatedAt: day,
        ),
      ],
      projects: [
        LocalProject(
          id: 'desktop-project',
          title: 'Naš mali balkon',
          description: 'Prostor za jutranjo kavo.',
          createdAt: day,
          updatedAt: day,
        ),
      ],
      financeEntries: [
        FinanceEntry(
          id: 'desktop-finance',
          title: 'Lončki za balkon',
          amountMinor: 1800,
          currency: 'EUR',
          kind: FinanceEntryKind.expense,
          occurredAt: day,
          projectId: null,
          notes: '',
          createdAt: day,
          updatedAt: day,
        ),
      ],
    );
}

Future<GlobalKey> _pump(
  WidgetTester tester,
  MemoryOrganizerStorage store, {
  String theme = 'light',
  double width = 1440,
  double height = 960,
}) async {
  await loadCaptureFonts(tester);
  if (Platform.environment['JIVIE_UI_CAPTURE'] == '1') {
    await tester.runAsync(() async {
      final root = Platform.resolvedExecutable.split('/bin/cache/').first;
      final bytes = await File(
        '$root/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
      ).readAsBytes();
      for (final family in [
        'Roboto',
        'Segoe UI',
        '.SF UI Text',
        '.SF UI Display',
        '.AppleSystemUIFont',
      ]) {
        final systemFont = File('/System/Library/Fonts/SFNS.ttf');
        final familyBytes =
            family == '.AppleSystemUIFont' && await systemFont.exists()
            ? await systemFont.readAsBytes()
            : bytes;
        await (FontLoader(
          family,
        )..addFont(Future.value(ByteData.sublistView(familyBytes)))).load();
      }
    });
  }
  final boundary = GlobalKey();
  final catalog = _DesktopCatalog(store);
  await pumpOrganizer(
    tester,
    store,
    width: width,
    height: height,
    theme: theme,
    ideaController: NavigationIdeaController(),
    collaborationController: SharingUiController(initial: CollaborationState()),
    localSpacesController: catalog,
    repaintBoundaryKey: boundary,
    initialPreferences: {
      'organizer_getting_started_seen_v1': true,
      'jivie_guide_seen_v1': true,
    },
  );
  final container = ProviderScope.containerOf(
    tester.element(find.byKey(const ValueKey('organizer-desktop-frame'))),
  );
  catalog.refresh(container.read(organizerProvider).requireValue);
  await tester.pumpAndSettle();
  return boundary;
}

Future<void> _leaf(WidgetTester tester, String area) async {
  final row = find.byKey(ValueKey('organizer-leaf-$area'));
  await tester.ensureVisible(row);
  await tester.tap(row);
  await tester.pumpAndSettle();
}

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  if (Platform.environment['JIVIE_UI_CAPTURE'] != '1') return;
  await tester.runAsync(() async {
    final render =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await render.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('build/qa/desktop-ux/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  for (final platform in [
    TargetPlatform.macOS,
    TargetPlatform.windows,
    TargetPlatform.linux,
  ]) {
    testWidgets(
      '${platform.name} shell keeps draft while navigating and resizing, then saves exact task',
      (tester) async {
        final store = _storage();
        final capture = await _pump(
          tester,
          store,
          theme: platform == TargetPlatform.linux ? 'dark' : 'light',
        );
        expect(
          find.byKey(const ValueKey('organizer-desktop-frame')),
          findsOneWidget,
        );
        expect(find.byType(NavigationBar), findsNothing);
        expect(
          find.byType(MenuBar),
          platform == TargetPlatform.macOS ? findsNothing : findsOneWidget,
        );
        final writes = store.writes;
        await _leaf(tester, 'plans');
        await _leaf(tester, 'calendar');
        // The searchable space selector can make the sidebar scroll. Return
        // to Pulse through the actual scrollable instead of assuming all links
        // remain mounted after selecting a lower row.
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('organizer-destination-pulse')),
          -150,
          scrollable: find
              .descendant(
                of: find.byKey(const ValueKey('organizer-desktop-frame')),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.ensureVisible(
          find.byKey(const ValueKey('organizer-destination-pulse')),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('organizer-destination-pulse')),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('content-_Area.today')),
          findsOneWidget,
        );
        await _capture(tester, capture, '${platform.name}-pulse');
        await _leaf(tester, 'plans');
        await tester.tap(find.text('Izberi lončke za zelišča').last);
        await tester.pumpAndSettle();
        final title = find.byKey(const ValueKey('organizer-title-field'));
        expect(title, findsOneWidget);
        await tester.enterText(title, 'Neshranjen namizni osnutek');
        await _leaf(tester, 'calendar');
        expect(find.text('Neshranjen namizni osnutek'), findsOneWidget);
        expect(store.writes, writes);
        expect(
          tester
              .widget<FilledButton>(find.byKey(const ValueKey('desktop-new')))
              .onPressed,
          isNull,
        );
        await _capture(tester, capture, '${platform.name}-inspector');
        tester.view.physicalSize = const Size(800, 700);
        await tester.pumpAndSettle();
        expect(find.text('Neshranjen namizni osnutek'), findsOneWidget);
        expect(find.byType(NavigationBar), findsNothing);
        expect(tester.takeException(), isNull);
        tester.view.physicalSize = const Size(1440, 960);
        await tester.pumpAndSettle();
        expect(find.text('Neshranjen namizni osnutek'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('organizer-save')));
        await tester.pumpAndSettle();
        expect(store.snapshot.tasks.single.id, 'desktop-task');
        expect(store.snapshot.tasks.single.title, 'Neshranjen namizni osnutek');
        expect(
          find.byKey(const ValueKey('organizer-desktop-inspector')),
          findsNothing,
        );
        await _leaf(tester, 'finances');
        await _capture(tester, capture, '${platform.name}-finance');
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(platform),
    );
  }

  testWidgets(
    'desktop search opens an exact existing local task; Cancel does not write',
    (tester) async {
      final store = _storage();
      await _pump(tester, store);
      final writes = store.writes;
      await tester.tap(find.byKey(const ValueKey('desktop-search')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('desktop-search-input')),
        'lončke',
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('desktop-search-local:task:desktop-task')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('organizer-desktop-inspector')),
        findsOneWidget,
        reason:
            'titleFields=${find.byKey(const ValueKey("organizer-title-field")).evaluate().length}; dialogs=${find.byType(Dialog).evaluate().length}; root=${find.byKey(const ValueKey("organizer-desktop-frame")).evaluate().length}',
      );
      expect(find.text('Izberi lončke za zelišča'), findsWidgets);
      await tester.enterText(
        find.byKey(const ValueKey('organizer-title-field')),
        'Ne shrani',
      );
      await tester.tap(find.widgetWithText(TextButton, 'Prekliči'));
      await tester.pumpAndSettle();
      expect(store.writes, writes);
      expect(store.snapshot.tasks.single.title, 'Izberi lončke za zelišča');
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'small desktop window with doubled text retains navigation and usable editors',
    (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final store = _storage();
      await _pump(tester, store, width: 640, height: 480);
      expect(find.byType(NavigationBar), findsNothing);
      await _leaf(tester, 'calendar');
      expect(tester.takeException(), isNull);
      await _leaf(tester, 'finances');
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('desktop-new')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dodaj opravilo'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('organizer-title-field')),
        'Veliko besedilo',
      );
      await tester.tap(find.widgetWithText(TextButton, 'Prekliči'));
      await tester.pumpAndSettle();
      expect(
        store.snapshot.tasks.where((t) => t.title == 'Veliko besedilo'),
        isEmpty,
      );
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );

  testWidgets(
    'desktop New uses explicit editor Save and sidebar resize has keyboard actions',
    (tester) async {
      final store = _storage();
      await _pump(tester, store);
      final writes = store.writes;
      await tester.tap(find.byKey(const ValueKey('desktop-new')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dodaj opravilo'));
      await tester.pumpAndSettle();
      expect(store.writes, writes);
      await tester.enterText(
        find.byKey(const ValueKey('organizer-title-field')),
        'Novo namizno opravilo',
      );
      await tester.tap(find.byKey(const ValueKey('organizer-save')));
      await tester.pumpAndSettle();
      expect(
        store.snapshot.tasks
            .where((t) => t.title == 'Novo namizno opravilo')
            .length,
        1,
      );
      final semantics = tester.ensureSemantics();
      await tester.pumpAndSettle();
      final splitter = find.bySemanticsLabel(
        'Spremeni širino stranske vrstice',
      );
      expect(splitter, findsOneWidget);
      semantics.dispose();
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );
}
