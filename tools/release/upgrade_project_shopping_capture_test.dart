// Opt-in store assets from the current real application widgets.
// JIVIE_UI_CAPTURE=1 flutter test tools/release/upgrade_project_shopping_capture_test.dart
// Every account, shared scope and record is synthetic and memory-only. No save,
// login, synchronization, installed storage or store-console action is performed.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';
import 'package:kanban/organizer/state/local_spaces_provider.dart';

import '../../test/organizer/ui/organizer_ui_test.dart'
    show MemoryOrganizerStorage, pumpOrganizer, mobileTab;
import '../../test/organizer/ui/sharing_ui_fixture.dart';
import '../../test/organizer/ui/unified_navigation_test.dart'
    show NavigationIdeaController;

final _out =
    Platform.environment['JIVIE_STORE_CAPTURE_OUT'] ??
    'build/qa/upgrade-store-20261015';
String _t(String locale, String sl, String en) => locale == 'sl' ? sl : en;
const _scope = '10000000-0000-4000-8000-000000000001';
const _project = '70000000-0000-4000-8000-000000000001';
const _phase = '70000000-0000-4000-8000-000000000002';
const _list = '70000000-0000-4000-8000-000000000030';

class _LocalCatalog extends LocalSpacesController {
  @override
  Future<LocalSpacesState> build() async => LocalSpacesState(
    spaces: const [
      LocalSpace(id: 'local', kind: LocalSpaceKind.personal, name: ''),
    ],
  );
}

CollaborationState _fixture(String locale, {required bool compact}) {
  final now = DateTime.now();
  final day = DateTime(now.year, now.month, now.day);
  final created = day.subtract(const Duration(days: 7));
  final data = SharedScopeData(
    projects: [
      LocalProject(
        id: _project,
        title: _t(locale, 'Mali balkon', 'Our balcony'),
        description: _t(
          locale,
          'Prostor za kavo in zelišča.',
          'A place for coffee and herbs.',
        ),
        area: ProjectArea.home,
        startAt: day,
        endAt: day.add(const Duration(days: 12)),
        phases: [
          ProjectPhase(
            id: _phase,
            title: _t(locale, 'Priprava', 'Preparation'),
            milestone: _t(
              locale,
              'Mejnik: prostor za novo polico',
              'Milestone: space for a new shelf',
            ),
            startAt: day,
            endAt: day.add(const Duration(days: 3)),
          ),
        ],
        createdAt: created,
        updatedAt: created,
      ),
    ],
    tasks: [
      for (final item in [
        (10, 'Izmeri prostor', 'Measure the space', true, 0),
        (11, 'Izberi polico', 'Choose a shelf', false, 2),
      ])
        LocalTask(
          id: '70000000-0000-4000-8000-${item.$1.toString().padLeft(12, '0')}',
          projectId: _project,
          phaseId: _phase,
          title: _t(locale, item.$2, item.$3),
          notes: '',
          dueAt: day.add(Duration(days: item.$5, hours: 17)),
          isCompleted: item.$4,
          estimateMinutes: item.$1 == 10 ? 20 : 40,
          createdAt: created,
          updatedAt: created,
        ),
    ],
    shoppingLists: [
      LocalShoppingList(
        id: _list,
        title: _t(locale, 'Živila', 'Groceries'),
        createdAt: created,
        updatedAt: created,
      ),
    ],
    shoppingItems: [
      for (final item in [
        (31, 'Jabolka', 'Apples', '1 kg', false),
        if (!compact) (32, 'Ovseni kosmiči', 'Oats', '500 g', false),
        if (!compact) (34, 'Jogurt', 'Yoghurt', '4', false),
        if (!compact) (35, 'Kruh', 'Bread', '1', false),

        (33, 'Čaj', 'Tea', '', true),
      ])
        LocalShoppingItem(
          id: '70000000-0000-4000-8000-${item.$1.toString().padLeft(12, '0')}',
          listId: _list,
          title: _t(locale, item.$2, item.$3),
          quantity: item.$4,
          isChecked: item.$5,
          createdAt: created,
          updatedAt: created,
        ),
    ],
  );
  return CollaborationState(
    session: sharingSession(),
    selectedSpaceId: _scope,
    recordContractVersion: 5,
    lastSuccessfulSyncAt: now,
    scopes: [
      SharedScope(
        id: _scope,
        name: _t(locale, 'Naš dom', 'Our home'),
        kind: SharedScopeKind.household,
        role: SharedRole.owner,
      ),
    ],
    data: {_scope: data},
  );
}

Future<void> _fonts(WidgetTester tester, bool ios) async {
  await tester.runAsync(() async {
    final root = Platform.resolvedExecutable.split('/bin/cache/').first;
    final dir = '$root/bin/cache/artifacts/material_fonts';
    final bytes = await File(
      ios ? '/System/Library/Fonts/SFNS.ttf' : '$dir/Roboto-Regular.ttf',
    ).readAsBytes();
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
}

Future<void> _capture(
  WidgetTester tester,
  GlobalKey key,
  String path,
  double ratio,
  Size size,
  bool ios,
) async {
  await tester.runAsync(
    () => precacheImage(
      const AssetImage('assets/branding/jivie/icon-master.png'),
      key.currentContext!,
    ),
  );
  await tester.pumpAndSettle();
  // flutter_tester has no system fallback: restore only unspecified renderer
  // font families to the platform font. Keep actual widgets/styles/layout intact.
  for (final element in find.byType(RichText).evaluate()) {
    final paragraph = element.findRenderObject() as RenderParagraph;
    final span = paragraph.text;
    if (span is TextSpan &&
        (span.style?.fontFamily == null || span.style?.fontFamily == 'Ahem')) {
      paragraph.text = TextSpan(
        text: span.text,
        style: (span.style ?? const TextStyle()).copyWith(
          fontFamily: ios ? 'CupertinoSystemText' : 'Roboto',
        ),
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
  // Re-evaluate flex intrinsic widths after restoring the test font fallback.
  // Tight paragraph relayout boundaries otherwise retain Ahem-era sibling widths.
  void relayout(RenderObject object) {
    object.visitChildren(relayout);
    object.markNeedsLayout();
  }

  relayout(key.currentContext!.findRenderObject()!);
  await tester.pump();
  expect(tester.takeException(), isNull);
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: ratio);
    expect(image.width, (size.width * ratio).round());
    expect(image.height, (size.height * ratio).round());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('$_out/$path.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  final enabled = Platform.environment['JIVIE_UI_CAPTURE'] == '1';
  for (final device in [
    (
      name: 'android-phone',
      size: const Size(360, 640),
      ratio: 2.0,
      top: 0.0,
      bottom: 0.0,
      ios: false,
    ),
    (
      name: 'ios-iphone',
      size: const Size(440, 956),
      ratio: 3.0,
      top: 62.0,
      bottom: 34.0,
      ios: true,
    ),
    (
      name: 'ios-ipad',
      size: const Size(1032, 1376),
      ratio: 2.0,
      top: 24.0,
      bottom: 20.0,
      ios: true,
    ),
  ]) {
    if (Platform.environment['JIVIE_ANDROID_CAPTURE_ONLY'] == '1' &&
        device.ios) {
      continue;
    }
    for (final locale in ['sl', 'en']) {
      testWidgets('upgrade projects and shopping ${device.name} $locale', (
        tester,
      ) async {
        final originalShadows = debugDisableShadows;
        debugDisableShadows = false;
        addTearDown(() => debugDisableShadows = originalShadows);
        debugDefaultTargetPlatformOverride = device.ios
            ? TargetPlatform.iOS
            : TargetPlatform.android;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        tester.view.padding = FakeViewPadding(
          top: device.top,
          bottom: device.bottom,
        );
        addTearDown(tester.view.resetPadding);
        await _fonts(tester, device.ios);
        final key = GlobalKey();
        final storage = MemoryOrganizerStorage();
        final controller = SharingUiController(
          initial: _fixture(locale, compact: !device.ios),
        );
        await pumpOrganizer(
          tester,
          storage,
          width: device.size.width,
          height: device.size.height,
          locale: locale,
          theme: 'light',
          repaintBoundaryKey: key,
          localSpacesController: _LocalCatalog(),
          collaborationController: controller,
          ideaController: NavigationIdeaController(),
          initialPreferences: const {
            'organizer_getting_started_seen_v1': true,
            'jivie_guide_seen_v1': true,
          },
        );
        final writes = storage.writes;
        await mobileTab(tester, _t(locale, 'Projekti', 'Projects'));
        expect(
          find.byKey(const ValueKey('projects-category-home')),
          findsNothing,
        );
        await tester.tap(
          find.text(_t(locale, 'Mali balkon', 'Our balcony')).first,
        );
        await tester.pumpAndSettle();
        await _capture(
          tester,
          key,
          '${device.name}/$locale/05-projects',
          device.ratio,
          device.size,
          device.ios,
        );
        await mobileTab(tester, _t(locale, 'Nakupi', 'Shopping'));
        await tester.enterText(
          find.byKey(const ValueKey('shopping-item-field')),
          _t(locale, 'Mleko', 'Milk'),
        );
        await tester.enterText(
          find.byKey(const ValueKey('shopping-quantity-field')),
          '2 l',
        );
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        final bought = find.text(_t(locale, 'Kupljeno (1)', 'Purchased (1)'));
        await tester.ensureVisible(bought);
        await tester.tap(bought);
        await tester.pumpAndSettle();
        // Restore the outer content scroll to its top so article and quantity
        // remain visible together with the populated list. No keyboard is drawn.
        for (final element in find.byType(Scrollable).evaluate()) {
          final state = (element as StatefulElement).state;
          if (state is ScrollableState &&
              state.position.axis == Axis.vertical &&
              state.position.hasContentDimensions) {
            state.position.jumpTo(state.position.minScrollExtent);
          }
        }
        await tester.pumpAndSettle();
        await _capture(
          tester,
          key,
          '${device.name}/$locale/06-shopping',
          device.ratio,
          device.size,
          device.ios,
        );
        expect(storage.writes, writes);
        expect(controller.calls, isEmpty);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        debugDefaultTargetPlatformOverride = null;
        debugDisableShadows = originalShadows;
      }, skip: !enabled);
    }
  }
}
