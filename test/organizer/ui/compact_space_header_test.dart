import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/presentation/shared/space_picker.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';
import 'package:kanban/widgets/jivie_brand_mark.dart';

import 'onboarding_ui_test.dart' show pumpPanel;
import 'organizer_ui_test.dart'
    show pumpOrganizer, mobileTab, MemoryOrganizerStorage;
import 'sharing_ui_fixture.dart';
import 'local_spaces_navigation_test.dart' show LocalSpaceUiController;
import 'package:kanban/organizer/state/local_spaces_provider.dart';

const selectedId = '70000000-0000-4000-8000-000000000001';
const archivedId = '70000000-0000-4000-8000-000000000002';
const revokedId = '70000000-0000-4000-8000-000000000003';
const personalId = '70000000-0000-4000-8000-000000000004';
const longName =
    'Naše gospodinjstvo z zelo dolgim imenom, ki ostane v svojem prostoru';
const selectedScope = SharedScope(
  id: selectedId,
  name: longName,
  kind: SharedScopeKind.household,
  role: SharedRole.owner,
);
CollaborationState spaces({
  String? chosen = selectedId,
  bool organizations = true,
}) => CollaborationState(
  session: sharingSession(),
  selectedSpaceId: chosen,
  organizationsSupported: organizations,
  scopes: [
    selectedScope,
    const SharedScope(
      id: archivedId,
      name: 'Arhiviran projekt',
      kind: SharedScopeKind.project,
      role: SharedRole.owner,
      archived: true,
    ),
    const SharedScope(
      id: revokedId,
      name: 'Preklican dom',
      kind: SharedScopeKind.household,
      role: SharedRole.viewer,
      revoked: true,
    ),
    const SharedScope(
      id: personalId,
      name: 'Hidden personal server scope',
      kind: SharedScopeKind.personal,
      role: SharedRole.owner,
    ),
  ],
);

class SpaceCreationController extends SharingUiController {
  SpaceCreationController({bool organizations = true})
    : super(initial: spaces(organizations: organizations));
  final requests = <Map<String, String>>[];
  bool loseFirst = false;
  void revokeSession() {
    state = AsyncData(
      CollaborationState(
        session: sharingSession(),
        sessionInvalid: true,
        selectedSpaceId: selectedId,
        scopes: [selectedScope],
      ),
    );
  }

  @override
  Future<String> createScope(
    String name, {
    SharedScopeKind kind = SharedScopeKind.household,
    String? organizationId,
    String? id,
    String? requestId,
  }) async {
    requests.add({
      'name': name,
      'kind': kind.name,
      'id': id!,
      'requestId': requestId!,
    });
    if (loseFirst && requests.length == 1) {
      throw const CollaborationException('network');
    }
    return id;
  }
}

Finder spaceButton() => find
    .descendant(
      of: find.byType(OrganizerSpacePicker),
      matching: find.byType(DropdownButton<String>),
    )
    .first;

Future<void> openNewSpace(WidgetTester tester) async {
  await tester.tap(spaceButton());
  await tester.pumpAndSettle();
  await tester.tap(find.text('Nov prostor').last);
  await tester.pumpAndSettle();
}

void main() {
  for (final width in [320.0, 390.0]) {
    for (final language in ['sl', 'en']) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
          'space is only in phone appbar $width $language ${scale}x',
          (tester) async {
            tester.platformDispatcher.textScaleFactorTestValue = scale;
            addTearDown(
              tester.platformDispatcher.clearTextScaleFactorTestValue,
            );
            await pumpOrganizer(
              tester,
              MemoryOrganizerStorage(),
              width: width,
              height: 844,
              locale: language,
              collaborationController: SharingUiController(initial: spaces()),
            );
            final picker = find.byType(OrganizerSpacePicker);
            expect(picker, findsOneWidget);
            expect(
              find.descendant(of: find.byType(AppBar), matching: picker),
              findsOneWidget,
            );
            expect(tester.widget<OrganizerSpacePicker>(picker).compact, isTrue);
            expect(find.text('Jivie'), findsNothing);
            expect(find.byType(JivieBrandMark), findsOneWidget);
            expect(
              find.text(language == 'sl' ? 'Prostor' : 'Space'),
              findsNothing,
            );
            expect(
              tester.getSize(spaceButton()).height,
              greaterThanOrEqualTo(48),
            );
            final headerCenter = tester
                .getCenter(find.byType(JivieBrandMark))
                .dy;
            expect(
              tester
                  .getCenter(
                    find.descendant(
                      of: spaceButton(),
                      matching: find.text(longName),
                    ),
                  )
                  .dy,
              closeTo(headerCenter, 1),
              reason: 'The closed label must align with the header controls.',
            );
            expect(
              tester.getCenter(find.byIcon(Icons.expand_more)).dy,
              closeTo(headerCenter, 1),
              reason: 'The chevron and label share the header center.',
            );
            expect(
              tester
                  .getCenter(
                    find.descendant(
                      of: spaceButton(),
                      matching: find.byIcon(Icons.home_outlined),
                    ),
                  )
                  .dy,
              closeTo(headerCenter, 1),
              reason: 'The selected space icon shares the header center.',
            );
            expect(
              tester
                  .getCenter(find.byIcon(Icons.notifications_none_outlined))
                  .dy,
              closeTo(headerCenter, 1),
            );
            expect(find.byIcon(Icons.add_business_outlined), findsNothing);
            expect(tester.takeException(), isNull);
            await tester.tap(spaceButton());
            await tester.pumpAndSettle();
            expect(
              find.text(language == 'sl' ? 'Nov prostor' : 'New space'),
              findsOneWidget,
            );
            expect(find.text('Hidden personal server scope'), findsNothing);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
  testWidgets('closed phone picker identifies every selected space kind', (
    tester,
  ) async {
    for (final choice in [
      (chosen: null, all: false, scope: null, icon: Icons.person_outline),
      (chosen: null, all: true, scope: null, icon: Icons.dashboard_outlined),
      for (final kind in [
        SharedScopeKind.household,
        SharedScopeKind.project,
        SharedScopeKind.organization,
      ])
        (
          chosen: selectedId,
          all: false,
          scope: SharedScope(
            id: selectedId,
            name: 'Selected ${kind.name}',
            kind: kind,
            role: SharedRole.owner,
          ),
          icon: switch (kind) {
            SharedScopeKind.household => Icons.home_outlined,
            SharedScopeKind.project => Icons.folder_outlined,
            _ => Icons.business_outlined,
          },
        ),
      (
        chosen: archivedId,
        all: false,
        scope: spaces().scopes.singleWhere((scope) => scope.id == archivedId),
        icon: Icons.inventory_2_outlined,
      ),
      (
        chosen: revokedId,
        all: false,
        scope: spaces().scopes.singleWhere((scope) => scope.id == revokedId),
        icon: Icons.lock_outline,
      ),
      (
        chosen: 'missing-space',
        all: false,
        scope: null,
        icon: Icons.lock_outline,
      ),
    ]) {
      await tester.pumpWidget(const SizedBox.shrink());
      await pumpOrganizer(
        tester,
        MemoryOrganizerStorage(),
        collaborationController: SharingUiController(
          initial: CollaborationState(
            session: sharingSession(),
            selectedSpaceId: choice.chosen,
            allSpacesSelected: choice.all,
            scopes: [if (choice.scope != null) choice.scope!],
          ),
        ),
      );
      expect(
        find.descendant(of: spaceButton(), matching: find.byIcon(choice.icon)),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    }
  });
  for (final width in [600.0, 1280.0]) {
    testWidgets(
      'wide picker keeps body placement without separate plus at $width',
      (tester) async {
        await pumpOrganizer(tester, MemoryOrganizerStorage(), width: width);
        final picker = find.byType(OrganizerSpacePicker);
        expect(picker, findsOneWidget);
        expect(tester.widget<OrganizerSpacePicker>(picker).compact, isFalse);
        expect(
          find.descendant(of: find.byType(AppBar), matching: picker),
          findsNothing,
        );
        expect(find.byIcon(Icons.add_business_outlined), findsNothing);
        await tester.tap(spaceButton());
        await tester.pumpAndSettle();
        expect(find.text('Nov prostor'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('new space canceled keeps selected value and does not write', (
    tester,
  ) async {
    final controller = SpaceCreationController();
    String? selected;
    await pumpPanel(
      tester,
      controller,
      OrganizerSpacePicker(
        compact: true,
        onSelected: (id) => selected = id,
        onConnect: () {},
      ),
    );
    await openNewSpace(tester);
    expect(
      find.textContaining('Prostor in njegove zapise hrani ta naprava.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Prekliči'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<DropdownButton<String>>(spaceButton()).value,
      selectedId,
    );
    expect(find.text(longName), findsOneWidget);
    expect(controller.requests, isEmpty);
    expect(selected, isNull);
  });
  testWidgets(
    'signed out action opens local creation and stays on selected space',
    (tester) async {
      var connections = 0;
      String? selected;
      final controller = SharingUiController(initial: CollaborationState());
      await pumpPanel(
        tester,
        controller,
        OrganizerSpacePicker(
          onSelected: (id) => selected = id,
          onConnect: () => connections++,
        ),
      );
      await openNewSpace(tester);
      expect(connections, 0);
      expect(selected, isNull);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        tester.widget<DropdownButton<String>>(spaceButton()).value,
        'local:local',
      );
    },
  );
  testWidgets('revoking server session retains local space creation form', (
    tester,
  ) async {
    final controller = SpaceCreationController();
    String? selected;
    await pumpPanel(
      tester,
      controller,
      OrganizerSpacePicker(onSelected: (id) => selected = id, onConnect: () {}),
    );
    await openNewSpace(tester);
    expect(find.byType(AlertDialog), findsOneWidget);
    controller.revokeSession();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(controller.requests, isEmpty);
    expect(selected, isNull);
    expect(tester.takeException(), isNull);
  });
  for (final chosen in [revokedId, 'missing-space']) {
    testWidgets(
      'revoked and missing choices remain visibly selected: $chosen',
      (tester) async {
        await pumpPanel(
          tester,
          SharingUiController(initial: spaces(chosen: chosen)),
          OrganizerSpacePicker(
            compact: true,
            onSelected: (_) {},
            onConnect: () {},
          ),
        );
        final button = tester.widget<DropdownButton<String>>(spaceButton());
        expect(button.value, chosen);
        expect(
          button.items!.singleWhere((item) => item.value == chosen).enabled,
          isFalse,
        );
        expect(find.textContaining('Dostop'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('archive stays selectable and private server scope is hidden', (
    tester,
  ) async {
    await pumpPanel(
      tester,
      SharingUiController(initial: spaces(chosen: archivedId)),
      OrganizerSpacePicker(onSelected: (_) {}, onConnect: () {}),
    );
    final button = tester.widget<DropdownButton<String>>(spaceButton());
    expect(button.value, archivedId);
    expect(
      button.items!.singleWhere((item) => item.value == archivedId).enabled,
      isTrue,
    );
    expect(button.items!.where((item) => item.value == personalId), isEmpty);
    expect(find.text('Arhiviran projekt'), findsOneWidget);
  });
  for (final kind in [LocalSpaceKind.household, LocalSpaceKind.organization]) {
    testWidgets(
      'picker creates local ${kind.name} regardless of server capabilities',
      (tester) async {
        final local = LocalSpaceUiController(LocalSpaceKind.personal);
        String? selected;
        final remote = SpaceCreationController(organizations: false);
        await pumpPanel(
          tester,
          remote,
          ProviderScope(
            overrides: [localSpacesProvider.overrideWith(() => local)],
            child: OrganizerSpacePicker(
              onSelected: (_) {},
              onLocalSelected: (id) => selected = id,
              onConnect: () {},
            ),
          ),
        );
        await openNewSpace(tester);
        if (kind != LocalSpaceKind.household) {
          await tester.tap(find.byKey(const ValueKey('sharing-kind')));
          await tester.pumpAndSettle();
          await tester.tap(
            find
                .text(
                  kind == LocalSpaceKind.personal ? 'Osebno' : 'Organizacija',
                )
                .last,
          );
          await tester.pumpAndSettle();
        }
        await tester.enterText(find.byType(TextField).first, 'QA ${kind.name}');
        await tester.tap(find.byKey(const ValueKey('sharing-submit')));
        await tester.pumpAndSettle();
        expect(local.created.single.kind, kind);
        expect(selected, local.created.single.id);
        expect(remote.requests, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('render actual phone header and space menus', (tester) async {
    // Widget tests use the square Ahem font by default. Load the app's actual
    // Cupertino families and Material glyphs for a readable review artifact.
    await tester.runAsync(() async {
      final flutterRoot = Platform.resolvedExecutable
          .split('/bin/cache/')
          .first;
      final fonts = '$flutterRoot/bin/cache/artifacts/material_fonts';
      final systemFont = File('/System/Library/Fonts/SFNS.ttf');
      final textBytes =
          await (await systemFont.exists()
                  ? systemFont
                  : File('$fonts/Roboto-Regular.ttf'))
              .readAsBytes();
      for (final family in ['CupertinoSystemText', 'CupertinoSystemDisplay']) {
        await (FontLoader(
          family,
        )..addFont(Future.value(ByteData.sublistView(textBytes)))).load();
      }
      final icons = await File(
        '$fonts/MaterialIcons-Regular.otf',
      ).readAsBytes();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(Future.value(ByteData.sublistView(icons)))).load();
    });
    final capture = GlobalKey();
    await pumpOrganizer(
      tester,
      MemoryOrganizerStorage(),
      width: 390,
      height: 844,
      repaintBoundaryKey: capture,
    );
    await mobileTab(tester, 'Koledar');
    expect(find.byType(OrganizerSpacePicker), findsOneWidget);
    expect(find.text('Jivie'), findsNothing);
    await tester.runAsync(() async {
      final boundary =
          capture.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('build/qa/jivie-compact-header/header-mobile.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
    for (final theme in ['light', 'dark']) {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await pumpOrganizer(
        tester,
        MemoryOrganizerStorage(),
        width: 390,
        height: 844,
        theme: theme,
        repaintBoundaryKey: capture,
        collaborationController: SharingUiController(
          initial: CollaborationState(
            session: sharingSession(),
            allSpacesSelected: true,
            scopes: const [
              SharedScope(
                id: selectedId,
                name: 'preizkus obvestil',
                kind: SharedScopeKind.project,
                role: SharedRole.owner,
              ),
              SharedScope(
                id: archivedId,
                name: 'Doma',
                kind: SharedScopeKind.household,
                role: SharedRole.owner,
              ),
            ],
          ),
        ),
      );
      await tester.tap(spaceButton());
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final boundary =
            capture.currentContext!.findRenderObject() as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File('build/qa/jivie-space-picker/menu-phone-$theme.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
      expect(tester.takeException(), isNull);
    }
    expect(tester.takeException(), isNull);
  });
  testWidgets('render closed Android picker and preserved menus', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
    addTearDown(tester.view.resetPadding);
    await tester.runAsync(() async {
      final flutterRoot = Platform.resolvedExecutable
          .split('/bin/cache/')
          .first;
      final fonts = '$flutterRoot/bin/cache/artifacts/material_fonts';
      final loader = FontLoader('Roboto');
      for (final weight in ['Regular', 'Medium', 'Bold']) {
        final bytes = await File('$fonts/Roboto-$weight.ttf').readAsBytes();
        loader.addFont(Future.value(ByteData.sublistView(bytes)));
      }
      await loader.load();
      final icons = await File(
        '$fonts/MaterialIcons-Regular.otf',
      ).readAsBytes();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(Future.value(ByteData.sublistView(icons)))).load();
    });
    final capture = GlobalKey();
    Future<void> saveArtifact(String name) => tester.runAsync(() async {
      final boundary =
          capture.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('build/qa/jivie-space-picker-closed/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
    for (final scenario in [
      (width: 390.0, scale: 1.0, name: 'phone', title: 'preizkus obvestil'),
      (width: 320.0, scale: 2.0, name: 'longname-320-2x', title: longName),
    ]) {
      tester.platformDispatcher.textScaleFactorTestValue = scenario.scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      for (final theme in ['light', 'dark']) {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await pumpOrganizer(
          tester,
          MemoryOrganizerStorage(),
          width: scenario.width,
          height: 844,
          theme: theme,
          repaintBoundaryKey: capture,
          collaborationController: SharingUiController(
            initial: CollaborationState(
              session: sharingSession(),
              selectedSpaceId: selectedId,
              scopes: [
                SharedScope(
                  id: selectedId,
                  name: scenario.title,
                  kind: SharedScopeKind.project,
                  role: SharedRole.owner,
                ),
                const SharedScope(
                  id: archivedId,
                  name: 'Doma',
                  kind: SharedScopeKind.household,
                  role: SharedRole.owner,
                ),
              ],
            ),
          ),
        );
        final label = find.descendant(
          of: spaceButton(),
          matching: find.text(scenario.title),
        );
        expect(
          tester.getCenter(label).dy,
          closeTo(tester.getCenter(find.byType(JivieBrandMark)).dy, 1),
        );
        expect(
          find.descendant(
            of: find.byType(OrganizerSpacePicker),
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Tooltip &&
                  widget.message == 'Prostor: ${scenario.title}',
            ),
          ),
          findsOneWidget,
        );
        await saveArtifact('closed-${scenario.name}-$theme');
        await tester.tap(spaceButton());
        await tester.pumpAndSettle();
        expect(find.text('Nov prostor'), findsOneWidget);
        expect(find.text('Deljeni projekt'), findsOneWidget);
        expect(find.byIcon(Icons.check), findsOneWidget);
        await saveArtifact('menu-${scenario.name}-$theme');
        expect(tester.takeException(), isNull);
      }
    }
    debugDefaultTargetPlatformOverride = null;
  }, skip: !const bool.fromEnvironment('JIVIE_RENDER_QA'));
}
