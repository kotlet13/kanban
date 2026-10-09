// Explicit store-asset capture harness. Does not seed the installed application.
// Run from the repository root: flutter test tools/release/store_screenshots_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/app.dart';
import 'package:kanban/app_router.dart';
import 'package:kanban/organizer/domain/garden_models.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'package:kanban/organizer/platform/backup_preferences_replay.dart';
import 'package:kanban/organizer/platform/invitation_links/invitation_link_providers.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';
import 'package:kanban/organizer/state/garden_provider.dart';
import 'package:kanban/organizer/state/organizer_provider.dart';
import 'package:kanban/organizer/state/portable_backup_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../test/organizer/ui/backup_ui_fixture.dart';
import '../../test/organizer/ui/organizer_ui_test.dart'
    show MemoryOrganizerStorage, mobileTab;
import '../../test/organizer/ui/sharing_ui_fixture.dart';

const _out = 'assets/store/google-play';

String _text(String locale, String sl, String en) => locale == 'sl' ? sl : en;
String _id(int value) =>
    '70000000-0000-4000-8000-${value.toString().padLeft(12, '0')}';

OrganizerSnapshot _fixture(String locale, DateTime day) {
  final created = day.subtract(const Duration(days: 6));
  LocalTask task(
    int id,
    String sl,
    String en, {
    String? project,
    int days = 0,
    bool done = false,
  }) => LocalTask(
    id: _id(id),
    title: _text(locale, sl, en),
    notes: '',
    projectId: project,
    dueAt: day.add(Duration(days: days, hours: 17)),
    isCompleted: done,
    estimateMinutes: 30,
    createdAt: created,
    updatedAt: created,
  );
  FinanceEntry entry(
    int id,
    String sl,
    String en,
    int amount, {
    bool income = false,
    int days = 0,
  }) => FinanceEntry(
    id: _id(id),
    title: _text(locale, sl, en),
    amountMinor: amount,
    currency: 'EUR',
    kind: income ? FinanceEntryKind.income : FinanceEntryKind.expense,
    occurredAt: day.subtract(Duration(days: days)),
    projectId: null,
    notes: '',
    ledgerAccountId: _id(90),
    createdAt: created,
    updatedAt: created,
  );
  return OrganizerSnapshot(
    projects: [
      LocalProject(
        id: _id(1),
        title: _text(locale, 'Jesenski izleti', 'Autumn outings'),
        description: _text(
          locale,
          'Ideje za vikende na prostem.',
          'Ideas for weekends outdoors.',
        ),
        createdAt: created,
        updatedAt: created,
      ),
      LocalProject(
        id: _id(2),
        title: _text(locale, 'Ureditev balkona', 'Balcony refresh'),
        description: _text(
          locale,
          'Majhni koraki do prijetnega kotička.',
          'Small steps towards a cosy corner.',
        ),
        area: ProjectArea.home,
        createdAt: created,
        updatedAt: created,
      ),
    ],
    tasks: [
      task(
        10,
        'Izberi pot za sobotni izlet',
        'Choose a route for Saturday',
        project: _id(1),
      ),
      task(11, 'Zalij rastline', 'Water the plants'),
      task(
        12,
        'Izmeri prostor za polico',
        'Measure the shelf space',
        project: _id(2),
        days: 1,
      ),
      task(
        13,
        'Poišči zemljevid poti',
        'Find a trail map',
        project: _id(1),
        done: true,
      ),
      task(14, 'Izberi zelišča', 'Choose some herbs', project: _id(2), days: 3),
    ],
    events: [
      LocalEvent(
        id: _id(20),
        title: _text(locale, 'Sprehod ob jezeru', 'Walk by the lake'),
        notes: '',
        startsAt: day.add(const Duration(hours: 16)),
        endsAt: day.add(const Duration(hours: 17)),
        projectId: null,
        createdAt: created,
        updatedAt: created,
      ),
    ],
    shoppingLists: [
      LocalShoppingList(
        id: _id(30),
        title: _text(locale, 'Tedenski nakup', 'Weekly groceries'),
        createdAt: created,
        updatedAt: created,
      ),
    ],
    shoppingItems: [
      for (final item in [
        (31, 'Jabolka', 'Apples', '1 kg', false),
        (32, 'Ovseni kosmiči', 'Oats', '500 g', false),
        (33, 'Jogurt', 'Yoghurt', '4', false),
        (34, 'Kruh', 'Bread', '1', false),
        (35, 'Čaj', 'Tea', '1', true),
      ])
        LocalShoppingItem(
          id: _id(item.$1),
          listId: _id(30),
          title: _text(locale, item.$2, item.$3),
          quantity: item.$4,
          isChecked: item.$5,
          createdAt: created,
          updatedAt: created,
        ),
    ],
    financeAccounts: [
      LocalFinanceAccount(
        id: _id(90),
        name: _text(locale, 'Osebni račun', 'Personal account'),
        currency: 'EUR',
        createdAt: created,
        updatedAt: created,
      ),
    ],
    financeEntries: [
      entry(
        40,
        'Vračilo stroškov',
        'Expense reimbursement',
        8000,
        income: true,
        days: 4,
      ),
      entry(41, 'Živila', 'Groceries', 4260, days: 2),
      entry(42, 'Knjiga', 'Book', 1890, days: 1),
    ],
  );
}

Garden _garden(String locale, DateTime day) => Garden(
  id: _id(100),
  name: _text(locale, 'Zelenjavni vrt', 'Vegetable garden'),
  notes: _text(
    locale,
    'Zalivanje zvečer. Pot ob ograji.',
    'Water in the evening. Path by the fence.',
  ),
  createdAt: day,
  updatedAt: day,
  areas: [
    GardenArea(
      id: _id(101),
      label: _text(locale, 'Zelišča', 'Herbs'),
      x: .08,
      y: .08,
      width: .38,
      height: .35,
    ),
    GardenArea(
      id: _id(102),
      label: _text(locale, 'Solata', 'Lettuce'),
      x: .55,
      y: .08,
      width: .35,
      height: .35,
    ),
    GardenArea(
      id: _id(103),
      label: _text(locale, 'Korenje', 'Carrots'),
      x: .08,
      y: .56,
      width: .38,
      height: .35,
    ),
    GardenArea(
      id: _id(104),
      label: _text(locale, 'Paradižnik', 'Tomatoes'),
      x: .55,
      y: .56,
      width: .35,
      height: .35,
    ),
  ],
  seasons: [
    GardenSeason(
      year: day.year,
      plantings: [
        GardenPlanting(
          id: _id(110),
          areaId: _id(101),
          crop: _text(locale, 'Bazilika', 'Basil'),
          family: 'Lamiaceae',
        ),
        GardenPlanting(
          id: _id(111),
          areaId: _id(102),
          crop: _text(locale, 'Solata', 'Lettuce'),
          family: 'Asteraceae',
        ),
      ],
    ),
  ],
);

class _GardenController extends GardenController {
  _GardenController(this.garden);
  final Garden garden;
  @override
  Future<GardenSnapshot> build() async => GardenSnapshot(gardens: [garden]);
}

Future<void> _fonts(WidgetTester tester) async => tester.runAsync(() async {
  final root = Platform.resolvedExecutable.split('/bin/cache/').first;
  final dir = '$root/bin/cache/artifacts/material_fonts';
  // Android's system fallback is Roboto. Load it under the Cupertino family
  // names used by the current application theme, avoiding test-only Ahem glyphs.
  final bytes = await File('$dir/Roboto-Regular.ttf').readAsBytes();
  for (final family in [
    'CupertinoSystemText',
    'CupertinoSystemDisplay',
    'Roboto',
  ]) {
    await (FontLoader(
      family,
    )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
  }
  final icons = await File('$dir/MaterialIcons-Regular.otf').readAsBytes();
  await (FontLoader(
    'MaterialIcons',
  )..addFont(Future.value(ByteData.sublistView(icons)))).load();
});

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  expect(tester.takeException(), isNull);
  await tester.runAsync(
    () => precacheImage(
      const AssetImage('assets/branding/jivie/icon-master.png'),
      key.currentContext!,
    ),
  );
  await tester.pump();
  // flutter_tester has no Android system font fallback. Current controls with
  // an explicit TextStyle(fontSize: ...) therefore fall back to test-only Ahem.
  // Restore only those renderer spans to Android's Roboto fallback; keep every
  // widget, string, colour, navigation state and layout constraint unchanged.
  for (final element in find.byType(RichText).evaluate()) {
    final paragraph = element.findRenderObject() as RenderParagraph;
    final span = paragraph.text;
    if (span is TextSpan && span.style?.fontFamily == null) {
      paragraph.text = TextSpan(
        text: span.text,
        style: (span.style ?? const TextStyle()).copyWith(fontFamily: 'Roboto'),
        children: span.children,
        recognizer: span.recognizer,
        mouseCursor: span.mouseCursor,
        onEnter: span.onEnter,
        onExit: span.onExit,
        semanticsLabel: span.semanticsLabel,
        locale: span.locale,
        spellOut: span.spellOut,
      );
    }
  }
  await tester.pump();
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2.5);
    expect(image.width, 1080);
    expect(image.height, 1920);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('$_out/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  for (final locale in ['sl', 'en']) {
    testWidgets('capture actual current phone widgets $locale', (tester) async {
      tester.view.physicalSize = const Size(432, 768);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await _fonts(tester);
      final clock = DateTime.now();
      final day = DateTime(clock.year, clock.month, clock.day);
      final store = MemoryOrganizerStorage()..snapshot = _fixture(locale, day);
      final garden = _garden(locale, day);
      // This capture-only widget test lives in tools/ rather than test/.
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues({
        'app_locale_code': locale,
        'app_theme_mode': 'light',
        'organizer_getting_started_seen_v1': true,
        'jivie_guide_seen_v1': true,
      });
      appRouter.go('/');
      final key = GlobalKey();
      await tester.pumpWidget(
        ProviderScope(
          key: UniqueKey(),
          overrides: [
            invitationLinkSourceProvider.overrideWithValue(null),
            collaborationProvider.overrideWith(
              () => SharingUiController(initial: CollaborationState()),
            ),
            organizerStorageProvider.overrideWithValue(() async => store),
            organizerClockProvider.overrideWithValue(() => day),
            gardenProvider.overrideWith(() => _GardenController(garden)),
            portableBackupProvider.overrideWith(EmptyBackupUiController.new),
            backupPreferencesReplayProvider.overrideWith(
              (ref) async => <String, Object?>{},
            ),
          ],
          child: RepaintBoundary(key: key, child: const KanbanApp()),
        ),
      );
      await tester.pumpAndSettle();
      await _capture(tester, key, '$locale/01-today');
      await mobileTab(tester, _text(locale, 'Načrti', 'Plans'));
      await tester.tap(find.text(_text(locale, 'Projekti', 'Projects')).first);
      await tester.pumpAndSettle();
      await _capture(tester, key, '$locale/02-plans');
      await mobileTab(tester, _text(locale, 'Nakupi', 'Shopping'));
      await _capture(tester, key, '$locale/03-shopping');
      await mobileTab(tester, _text(locale, 'Finance', 'Finances'));
      await _capture(tester, key, '$locale/04-finances');
      await tester.ensureVisible(
        find.text(_text(locale, 'Vračilo stroškov', 'Expense reimbursement')),
      );
      await tester.pumpAndSettle();
      await _capture(tester, key, '$locale/06-finance-ledger');
      await mobileTab(tester, _text(locale, 'Vrt', 'Garden'));
      await tester.tap(find.text(garden.name));
      await tester.pumpAndSettle();
      await _capture(tester, key, '$locale/05-garden');
      expect(store.writes, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }, variant: TargetPlatformVariant({TargetPlatform.android}));
  }
}
