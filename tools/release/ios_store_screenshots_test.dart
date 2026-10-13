// iOS store capture only, from frozen fa809b8/mobile25.
// Synthetic in-memory records; SFNS system fallback; no installed data or production code is modified.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';

import '../../test/organizer/ui/local_spaces_navigation_test.dart'
    show LocalSpaceUiController, loadCaptureFonts;
import '../../test/organizer/ui/organizer_ui_test.dart'
    show MemoryOrganizerStorage, pumpOrganizer, mobileTab;
import '../../test/organizer/ui/sharing_ui_fixture.dart';
import '../../test/organizer/ui/unified_navigation_test.dart'
    show NavigationIdeaController;

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

Future<void> _capture(
  WidgetTester tester,
  GlobalKey key,
  String name,
  double ratio,
) async {
  if (Platform.environment['JIVIE_UI_CAPTURE'] != '1') return;
  for (final element in find.byType(RichText).evaluate()) {
    final paragraph = element.findRenderObject() as RenderParagraph;
    final span = paragraph.text;
    if (span is TextSpan &&
        (span.style?.fontFamily == null || span.style?.fontFamily == 'Ahem')) {
      paragraph.text = TextSpan(
        text: span.text,
        style: (span.style ?? const TextStyle()).copyWith(
          fontFamily: 'CupertinoSystemText',
        ),
        children: span.children,
      );
    }
  }
  await tester.pump();
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: ratio);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final folder = Platform.environment['JIVIE_IOS_CAPTURE_OUT']!;
    final file = File('$folder/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  for (final scenario in [
    (name: 'iphone', width: 440.0, height: 956.0, ratio: 3.0),
    (name: 'ipad', width: 1032.0, height: 1376.0, ratio: 2.0),
  ]) {
    final name = scenario.name;
    testWidgets('iOS store screenshots $name', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      tester.view.padding = FakeViewPadding(
        top: name == 'iphone' ? 62 : 24,
        bottom: name == 'iphone' ? 34 : 20,
      );
      addTearDown(tester.view.resetPadding);
      await loadCaptureFonts(tester);
      final key = GlobalKey();
      final store = MemoryOrganizerStorage()..snapshot = _reviewSnapshot();
      await pumpOrganizer(
        tester,
        store,
        width: scenario.width,
        height: scenario.height,
        theme: 'light',
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
      await mobileTab(tester, 'Planer');
      await mobileTab(tester, 'Utrip');
      await tester.runAsync(
        () => precacheImage(
          const AssetImage('assets/branding/jivie/icon-master.png'),
          key.currentContext!,
        ),
      );
      await tester.pumpAndSettle();
      for (final item in [
        (1, 'Utrip'),
        (2, 'Opravila'),
        (3, 'Koledar'),
        (4, 'Idejnik'),
        (5, 'Prostor'),
        (6, 'Več'),
      ]) {
        await mobileTab(tester, item.$2);
        expect(tester.takeException(), isNull);
        await _capture(
          tester,
          key,
          '$name/${item.$1.toString().padLeft(2, '0')}-${item.$2}',
          scenario.ratio,
        );
      }
      expect(store.writes, initialWrites);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
