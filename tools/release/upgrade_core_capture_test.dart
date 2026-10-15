// Opt-in capture of the current real widgets; synthetic memory records only.
// JIVIE_UI_CAPTURE=1 flutter test tools/release/upgrade_core_capture_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';

import '../../test/organizer/ui/local_spaces_navigation_test.dart'
    show LocalSpaceUiController, loadCaptureFonts;
import '../../test/organizer/ui/organizer_ui_test.dart'
    show MemoryOrganizerStorage, pumpOrganizer, mobileTab;
import '../../test/organizer/ui/sharing_ui_fixture.dart';
import '../../test/organizer/ui/unified_navigation_test.dart'
    show NavigationIdeaController;

String _t(String locale, String sl, String en) => locale == 'sl' ? sl : en;
String _id(int n) => '71000000-0000-4000-8000-${n.toString().padLeft(12, '0')}';

OrganizerSnapshot _fixture(String locale) {
  final now = DateTime.now();
  final day = DateTime(now.year, now.month, now.day);
  final created = day.subtract(const Duration(days: 12));
  LocalTask task(int id, String sl, String en, int days, {String? project}) =>
      LocalTask(
        id: _id(id),
        title: _t(locale, sl, en),
        notes: '',
        projectId: project,
        dueAt: day.add(Duration(days: days, hours: 18)),
        isCompleted: false,
        estimateMinutes: 30,
        createdAt: created,
        updatedAt: created,
      );
  LocalEvent event(int id, String sl, String en, int days, int hour) =>
      LocalEvent(
        id: _id(id),
        title: _t(locale, sl, en),
        notes: '',
        startsAt: day.add(Duration(days: days, hours: hour)),
        endsAt: day.add(Duration(days: days, hours: hour + 1)),
        projectId: null,
        createdAt: created,
        updatedAt: created,
      );
  FinanceEntry entry(
    int id,
    String sl,
    String en,
    int amount,
    int days, {
    bool income = false,
  }) => FinanceEntry(
    id: _id(id),
    title: _t(locale, sl, en),
    amountMinor: amount,
    currency: 'EUR',
    kind: income ? FinanceEntryKind.income : FinanceEntryKind.expense,
    occurredAt: day.subtract(Duration(days: days)),
    projectId: null,
    ledgerAccountId: _id(90),
    notes: '',
    createdAt: created,
    updatedAt: created,
  );
  return OrganizerSnapshot(
    projects: [
      LocalProject(
        id: _id(1),
        title: _t(locale, 'Naš mali balkon', 'Our little balcony'),
        description: _t(
          locale,
          'Zelišča, nova polica in kotiček za jutranjo kavo.',
          'Herbs, a new shelf and a corner for morning coffee.',
        ),
        startAt: created,
        endAt: day.add(const Duration(days: 14)),
        createdAt: created,
        updatedAt: created,
      ),
      LocalProject(
        id: _id(2),
        title: _t(locale, 'Jesenski izleti', 'Autumn outings'),
        description: _t(
          locale,
          'Skupaj načrtujemo naslednji vikend.',
          'Planning our next weekend together.',
        ),
        createdAt: created,
        updatedAt: created,
      ),
    ],
    tasks: [
      task(
        10,
        'Izberi lončke za zelišča',
        'Choose pots for the herbs',
        0,
        project: _id(1),
      ),
      task(11, 'Rezerviraj mizo za soboto', 'Book a table for Saturday', 0),
      task(
        12,
        'Izmeri prostor za polico',
        'Measure the shelf space',
        1,
        project: _id(1),
      ),
      task(
        13,
        'Izberi pot za izlet',
        'Choose a trail for our walk',
        2,
        project: _id(2),
      ),
      task(14, 'Pripravi seznam za nakup', 'Write the shopping list', 3),
    ],
    events: [
      event(20, 'Sprehod ob jezeru', 'Walk by the lake', 0, 17),
      event(21, 'Kava s prijatelji', 'Coffee with friends', 1, 10),
      event(22, 'Izlet na obalo', 'A day by the sea', 3, 9),
    ],
    financeAccounts: [
      LocalFinanceAccount(
        id: _id(90),
        name: _t(locale, 'Osebni račun', 'Personal account'),
        currency: 'EUR',
        openingBalanceMinor: 85000,
        openingBalanceAt: created,
        createdAt: created,
        updatedAt: created,
      ),
    ],
    financeEntries: [
      entry(40, 'Mesečni prihodek', 'Monthly income', 185000, 5, income: true),
      entry(41, 'Tedenski nakup', 'Weekly groceries', 6840, 0),
      entry(42, 'Vozovnica za vlak', 'Train ticket', 1480, 1),
      entry(43, 'Zelišča za balkon', 'Herbs for the balcony', 2250, 2),
      entry(44, 'Kosilo v mestu', 'Lunch in town', 2850, 3),
      entry(45, 'Kava in pecivo', 'Coffee and pastries', 690, 4),
      entry(46, 'Knjiga za vikend', 'A book for the weekend', 1990, 6),
      entry(47, 'Mesečna vozovnica', 'Monthly travel pass', 3700, 7),
      entry(48, 'Obisk tržnice', 'Farmers market', 1760, 8),
    ],
  );
}

bool _robotoLoaded = false;
Future<void> _fonts(WidgetTester tester) async {
  await loadCaptureFonts(tester);
  if (_robotoLoaded) return;
  await tester.runAsync(() async {
    final root = Platform.resolvedExecutable.split('/bin/cache/').first;
    final dir = '$root/bin/cache/artifacts/material_fonts';
    for (final weight in ['Regular', 'Medium', 'Bold']) {
      final file = File('$dir/Roboto-$weight.ttf');
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        await (FontLoader(
          'Roboto',
        )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
      }
    }
  });
  _robotoLoaded = true;
}

Future<void> _capture(
  WidgetTester tester,
  GlobalKey key,
  String path,
  double ratio,
  Size size,
  TargetPlatform platform,
) async {
  // Flutter test's Ahem default is replaced only in render paragraphs, following
  // the existing store harness; all content/layout/controls are actual widgets.
  for (final element in find.byType(RichText).evaluate()) {
    final paragraph = element.findRenderObject() as RenderParagraph;
    final span = paragraph.text;
    if (span is TextSpan &&
        (span.style?.fontFamily == null || span.style?.fontFamily == 'Ahem')) {
      paragraph.text = TextSpan(
        text: span.text,
        style: (span.style ?? const TextStyle()).copyWith(
          fontFamily: platform == TargetPlatform.iOS
              ? 'CupertinoSystemText'
              : 'Roboto',
        ),
        children: span.children,
        recognizer: span.recognizer,
        semanticsLabel: span.semanticsLabel,
        locale: span.locale,
        spellOut: span.spellOut,
      );
    }
  }
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: ratio);
    expect(image.width, (size.width * ratio).round());
    expect(image.height, (size.height * ratio).round());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('build/qa/upgrade-store-20261015/$path.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  for (final scene in [
    (
      name: 'android-phone',
      size: const Size(360, 640),
      ratio: 2.0,
      platform: TargetPlatform.android,
      top: 0.0,
      bottom: 0.0,
    ),
    (
      name: 'ios-iphone',
      size: const Size(440, 956),
      ratio: 3.0,
      platform: TargetPlatform.iOS,
      top: 62.0,
      bottom: 34.0,
    ),
    (
      name: 'ios-ipad',
      size: const Size(1032, 1376),
      ratio: 2.0,
      platform: TargetPlatform.iOS,
      top: 24.0,
      bottom: 20.0,
    ),
  ]) {
    for (final locale in ['sl', 'en']) {
      testWidgets('upgrade core captures ${scene.name} $locale', (
        tester,
      ) async {
        final previousShadows = debugDisableShadows;
        debugDisableShadows = false;
        addTearDown(() => debugDisableShadows = previousShadows);
        debugDefaultTargetPlatformOverride = scene.platform;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        tester.view.padding = FakeViewPadding(
          top: scene.top,
          bottom: scene.bottom,
        );
        addTearDown(tester.view.resetPadding);
        await _fonts(tester);
        final key = GlobalKey();
        final store = MemoryOrganizerStorage()..snapshot = _fixture(locale);
        await pumpOrganizer(
          tester,
          store,
          width: scene.size.width,
          height: scene.size.height,
          locale: locale,
          theme: 'light',
          repaintBoundaryKey: key,
          localSpacesController: LocalSpaceUiController(
            LocalSpaceKind.personal,
          ),
          collaborationController: SharingUiController(
            initial: CollaborationState(),
          ),
          ideaController: NavigationIdeaController(),
          initialPreferences: const {
            'organizer_getting_started_seen_v1': true,
            'jivie_guide_seen_v1': true,
          },
        );
        await tester.runAsync(
          () => precacheImage(
            const AssetImage('assets/branding/jivie/icon-master.png'),
            key.currentContext!,
          ),
        );
        await tester.pumpAndSettle();
        expect(store.writes, 0);
        for (final screen in [
          ('01-pulse', 'Utrip', 'Pulse'),
          ('02-planner', 'Opravila', 'Tasks'),
          ('03-calendar', 'Koledar', 'Calendar'),
          ('08-finances', 'Finance', 'Finances'),
        ]) {
          await mobileTab(tester, _t(locale, screen.$2, screen.$3));
          if (screen.$1 == '03-calendar') {
            final now = DateTime.now();
            final month = DateFormat.yMMMM(locale).format(now);
            await Scrollable.ensureVisible(
              find.text(month).first.evaluate().single,
              alignment: scene.name == 'ios-iphone' ? .02 : .08,
            );
            await tester.pumpAndSettle();
          }
          if (screen.$1 == '08-finances' && scene.name != 'ios-ipad') {
            final label = _t(
              locale,
              'Evidentirana neto sprememba',
              'Recorded net change',
            );
            await Scrollable.ensureVisible(
              find.widgetWithText(Card, label).first.evaluate().single,
              alignment: .06,
            );
            await tester.pumpAndSettle();
          }
          await _capture(
            tester,
            key,
            '${scene.name}/$locale/${screen.$1}',
            scene.ratio,
            scene.size,
            scene.platform,
          );
        }
        expect(store.writes, 0);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        debugDefaultTargetPlatformOverride = null;
        debugDisableShadows = previousShadows;
      }, skip: Platform.environment['JIVIE_UI_CAPTURE'] != '1');
    }
  }
}
