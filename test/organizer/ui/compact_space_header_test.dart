import 'dart:io';
import 'dart:ui' as ui;

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
      find.textContaining('Na začetku vidi prostor samo ustvarjalec.'),
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
  testWidgets('signed out action opens connection and stays local', (
    tester,
  ) async {
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
    expect(connections, 1);
    expect(selected, isNull);
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.widget<DropdownButton<String>>(spaceButton()).value, '');
  });
  testWidgets('revoking the current session closes an open creation form', (
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
    expect(find.byType(AlertDialog), findsNothing);
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
  for (final kind in ['household', 'project', 'organization']) {
    testWidgets('new space explicitly creates $kind with retry identity', (
      tester,
    ) async {
      final controller = SpaceCreationController()..loseFirst = true;
      String? selected;
      await pumpPanel(
        tester,
        controller,
        OrganizerSpacePicker(
          onSelected: (id) => selected = id,
          onConnect: () {},
        ),
      );
      await openNewSpace(tester);
      if (kind != 'household') {
        await tester.tap(
          find.widgetWithText(DropdownButtonFormField<String>, 'Gospodinjstvo'),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find
              .text(kind == 'project' ? 'Deljeni projekt' : 'Organizacija')
              .last,
        );
        await tester.pumpAndSettle();
      }
      await tester.enterText(find.byType(TextField).first, 'Explicit $kind');
      await tester.tap(find.byKey(const ValueKey('sharing-submit')));
      await tester.pumpAndSettle();
      expect(selected, isNull);
      await tester.enterText(
        find.byType(TextField).first,
        'Changed after lost reply',
      );
      await tester.tap(find.byKey(const ValueKey('sharing-kind')));
      await tester.pumpAndSettle();
      await tester.tap(
        find
            .text(kind == 'household' ? 'Deljeni projekt' : 'Gospodinjstvo')
            .last,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('sharing-submit')));
      await tester.pumpAndSettle();
      expect(controller.requests.length, 2);
      expect(controller.requests.first, controller.requests.last);
      expect(controller.requests.first['kind'], kind);
      expect(controller.requests.first['name'], 'Explicit $kind');
      expect(selected, controller.requests.first['id']);
    });
  }
  testWidgets(
    'older capabilities offer household and project without organization',
    (tester) async {
      await pumpPanel(
        tester,
        SpaceCreationController(organizations: false),
        OrganizerSpacePicker(onSelected: (_) {}, onConnect: () {}),
      );
      await openNewSpace(tester);
      final kinds = tester.widget<DropdownButtonFormField<String>>(
        find.widgetWithText(DropdownButtonFormField<String>, 'Gospodinjstvo'),
      );
      await tester.tap(
        find.widgetWithText(DropdownButtonFormField<String>, 'Gospodinjstvo'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Deljeni projekt'), findsOneWidget);
      expect(find.text('Organizacija'), findsNothing);
      expect(kinds.enabled, isTrue);
    },
  );
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
}
