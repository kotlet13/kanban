import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';

import 'local_spaces_navigation_test.dart'
    show LocalSpaceUiController, loadCaptureFonts;
import 'organizer_ui_test.dart'
    show MemoryOrganizerStorage, pumpOrganizer, mobileTab;
import 'sharing_ui_fixture.dart';
import 'unified_navigation_test.dart' show NavigationIdeaController;

// Synthetic records are isolated test fixtures, never inserted by the app.
OrganizerSnapshot _reviewSnapshot() {
  final now = DateTime.now();
  final day = DateTime(now.year, now.month, now.day);
  LocalEvent event(String id, String title, DateTime at) => LocalEvent(
    id: id,
    title: title,
    notes: '',
    startsAt: at,
    endsAt: at.add(const Duration(hours: 1)),
    projectId: null,
    createdAt: day,
    updatedAt: day,
  );
  return OrganizerSnapshot(
    events: [
      event('today', 'Sprehod ob jezeru', day.add(const Duration(hours: 17))),
      event(
        'tomorrow',
        'Načrt za nov teden',
        day.add(const Duration(days: 1, hours: 10)),
      ),
    ],
    projects: [
      LocalProject(
        id: 'balcony',
        title: 'Naš mali balkon',
        description: 'Prostor za jutranjo kavo.',
        createdAt: day,
        updatedAt: day,
      ),
    ],
    tasks: [
      LocalTask(
        id: 'task',
        title: 'Izberi lončke za zelišča',
        notes: '',
        projectId: 'balcony',
        dueAt: day.add(const Duration(hours: 18)),
        isCompleted: false,
        createdAt: day,
        updatedAt: day,
      ),
    ],
  );
}

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  if (Platform.environment['JIVIE_UI_CAPTURE'] != '1') return;
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final folder = Platform.environment['JIVIE_UI_CAPTURE_PLAY'] == '1'
        ? 'build/qa/unified-mobile-ux/play-capture-source'
        : 'build/qa/unified-mobile-ux';
    final file = File('$folder/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  final playCapture = Platform.environment['JIVIE_UI_CAPTURE_PLAY'] == '1';
  for (final scenario in [
    (
      platform: TargetPlatform.android,
      width: 360.0,
      theme: 'light',
      scale: 1.0,
    ),
    (platform: TargetPlatform.iOS, width: 390.0, theme: 'light', scale: 1.0),
    (platform: TargetPlatform.iOS, width: 390.0, theme: 'dark', scale: 1.0),
    (
      platform: TargetPlatform.android,
      width: 320.0,
      theme: 'light',
      scale: 2.0,
    ),
  ]) {
    if (playCapture &&
        (scenario.platform != TargetPlatform.android || scenario.width != 360)) {
      continue;
    }
    final name =
        '${scenario.platform.name}-${scenario.width.toInt()}-${scenario.theme}-${scenario.scale}';
    testWidgets('unified navigation visual review $name', (tester) async {
      debugDefaultTargetPlatformOverride = scenario.platform;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      tester.platformDispatcher.textScaleFactorTestValue = scenario.scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      tester.view.padding = const FakeViewPadding(top: 44, bottom: 34);
      addTearDown(tester.view.resetPadding);
      await loadCaptureFonts(tester);
      if (Platform.environment['JIVIE_UI_CAPTURE'] == '1') {
        await tester.runAsync(() async {
          final root = Platform.resolvedExecutable.split('/bin/cache/').first;
          final bytes = await File(
            '$root/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
          ).readAsBytes();
          await (FontLoader(
            'Roboto',
          )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
        });
      }
      final key = GlobalKey();
      final store = MemoryOrganizerStorage()..snapshot = _reviewSnapshot();
      await pumpOrganizer(
        tester,
        store,
        width: scenario.width,
        height: playCapture ? 640 : 844,
        theme: scenario.theme,
        repaintBoundaryKey: key,
        localSpacesController: LocalSpaceUiController(LocalSpaceKind.personal),
        collaborationController: SharingUiController(
          initial: CollaborationState(),
        ),
        ideaController: NavigationIdeaController(),
        initialPreferences: const {
          'organizer_getting_started_seen_v1': true,
          'jivie_guide_seen_v1': true,
        },
      );
      final initialWrites = store.writes;
      // Let asynchronously decoded header assets paint before the first PNG.
      // Re-enter Pulse through the same real navigation used by later captures.
      await mobileTab(tester, 'Planer');
      await mobileTab(tester, 'Utrip');
      if (Platform.environment['JIVIE_UI_CAPTURE'] == '1') {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pumpAndSettle();
      }
      for (final tab in ['Utrip', 'Planer', 'Prostor', 'Več']) {
        await mobileTab(tester, tab);
        expect(find.byType(NavigationDestination), findsNWidgets(4));
        expect(tester.takeException(), isNull, reason: '$name $tab');
        expect(
          find.byType(SnackBar),
          findsNothing,
          reason: tester
              .widgetList<Text>(
                find.descendant(
                  of: find.byType(SnackBar),
                  matching: find.byType(Text),
                ),
              )
              .map((text) => text.data)
              .join('; '),
        );
        await _capture(tester, key, '$name-$tab');
      }
      for (final area in ['Opravila', 'Koledar', 'Idejnik']) {
        await mobileTab(tester, area);
        expect(tester.takeException(), isNull, reason: '$name $area');
        await _capture(tester, key, '$name-$area');
      }
      expect(
        store.writes,
        initialWrites,
        reason: 'Navigation never creates or changes records.',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
