import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/state/local_spaces_provider.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'package:kanban/organizer/presentation/shared/space_picker.dart';
import 'package:kanban/organizer/presentation/navigation/organizer_navigation.dart';
import 'package:kanban/organizer/presentation/shared/sharing_workspace.dart';
import 'organizer_ui_test.dart'
    show pumpOrganizer, mobileTab, MemoryOrganizerStorage;
import 'sharing_ui_fixture.dart';

class LocalSpaceUiController extends LocalSpacesController {
  LocalSpaceUiController(this.kind);
  final LocalSpaceKind kind;
  String get initialId =>
      kind == LocalSpaceKind.personal ? 'local' : 'qa-${kind.name}';
  final created = <LocalSpace>[];
  @override
  Future<LocalSpacesState> build() async => LocalSpacesState(
    selectedSpaceId: initialId,
    spaces: [
      LocalSpace(
        id: initialId,
        name: kind == LocalSpaceKind.personal
            ? ''
            : 'QA ${kind.name} z daljšim imenom',
        kind: kind,
      ),
    ],
  );
  @override
  Future<LocalSpace> createSpace({
    required LocalSpaceKind kind,
    required String name,
    String address = '',
  }) async {
    final space = LocalSpace(
      id: 'created',
      kind: kind,
      name: name,
      address: address,
    );
    created.add(space);
    final current = state.requireValue;
    state = AsyncData(
      LocalSpacesState(
        spaces: [...current.spaces, space],
        selectedSpaceId: current.selectedSpaceId,
      ),
    );
    return space;
  }

  @override
  Future<void> selectSpace(String id) async {
    state = AsyncData(
      LocalSpacesState(spaces: state.requireValue.spaces, selectedSpaceId: id),
    );
  }
}

bool _fontsLoaded = false;
Future<void> loadCaptureFonts(WidgetTester tester) async {
  if (_fontsLoaded || Platform.environment['JIVIE_UI_CAPTURE'] != '1') return;
  await tester.runAsync(() async {
    final flutterRoot = Platform.resolvedExecutable.split('/bin/cache/').first;
    final fonts = '$flutterRoot/bin/cache/artifacts/material_fonts';
    final systemFont = File('/System/Library/Fonts/SFNS.ttf');
    final bytes =
        await (await systemFont.exists()
                ? systemFont
                : File('$fonts/Roboto-Regular.ttf'))
            .readAsBytes();
    for (final family in ['CupertinoSystemText', 'CupertinoSystemDisplay']) {
      await (FontLoader(
        family,
      )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    }
    final icons = await File('$fonts/MaterialIcons-Regular.otf').readAsBytes();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(Future.value(ByteData.sublistView(icons)))).load();
    _fontsLoaded = true;
  });
}

Future<void> capture(WidgetTester tester, GlobalKey key, String name) async {
  if (Platform.environment['JIVIE_UI_CAPTURE'] != '1') return;
  await tester.pumpAndSettle();
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final directory = Directory('build/qa/spaces-next-ui');
    await directory.create(recursive: true);
    await File(
      '${directory.path}/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  for (final size in [const Size(320, 640), const Size(390, 844)]) {
    testWidgets('create organization fits keyboard and 1.5x at $size', (
      tester,
    ) async {
      await loadCaptureFonts(tester);
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final local = LocalSpaceUiController(LocalSpaceKind.personal);
      final key = GlobalKey();
      await pumpOrganizer(
        tester,
        MemoryOrganizerStorage(),
        width: size.width,
        height: size.height,
        localSpacesController: local,
        collaborationController: SharingUiController(
          initial: CollaborationState(),
        ),
        repaintBoundaryKey: key,
      );
      await tester.tap(
        find.descendant(
          of: find.byType(OrganizerSpacePicker),
          matching: find.byType(DropdownButton<String>),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nov prostor').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('sharing-kind')));
      await tester.tap(find.byKey(const ValueKey('sharing-kind')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Organizacija').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('sharing-name')));
      await tester.enterText(
        find.byKey(const ValueKey('sharing-name')),
        'QA organizacija z izredno dolgim imenom za telefon',
      );
      tester.view.viewInsets = const FakeViewPadding(bottom: 260);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('sharing-address')));
      await tester.enterText(
        find.byKey(const ValueKey('sharing-address')),
        'QA naslov z dolgo vrstico',
      );
      await tester.ensureVisible(find.byKey(const ValueKey('sharing-submit')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('sharing-submit')).hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await capture(tester, key, 'space-create-keyboard-${size.width.toInt()}');
      await tester.tap(find.byKey(const ValueKey('sharing-submit')));
      await tester.pumpAndSettle();
      expect(local.created.single.kind, LocalSpaceKind.organization);
      expect(local.created.single.address, 'QA naslov z dolgo vrstico');
      expect(tester.takeException(), isNull);
    });
  }

  for (final width in [320.0, 390.0, 700.0, 1280.0]) {
    for (final kind in LocalSpaceKind.values) {
      testWidgets('local $kind menu and direct tasks at $width', (
        tester,
      ) async {
        await loadCaptureFonts(tester);
        final local = LocalSpaceUiController(kind);
        final shared = SharingUiController(initial: CollaborationState());
        final key = GlobalKey();
        await pumpOrganizer(
          tester,
          MemoryOrganizerStorage()
            ..snapshot = OrganizerSnapshot(workspaceKey: local.initialId),
          width: width,
          height: 1000,
          localSpacesController: local,
          collaborationController: shared,
          repaintBoundaryKey: key,
        );
        await capture(tester, key, 'local-${kind.name}-${width.toInt()}');
        if (width < 600) {
          await tester.tap(find.byKey(const ValueKey('organizer-menu-open')));
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('organizer-menu-home')),
            findsNothing,
          );
          expect(
            find.byKey(const ValueKey('organizer-menu-shopping')),
            kind == LocalSpaceKind.household ? findsOneWidget : findsNothing,
          );
          expect(
            find.byKey(const ValueKey('organizer-menu-people')),
            kind == LocalSpaceKind.household ? findsOneWidget : findsNothing,
          );
          expect(
            find.byKey(const ValueKey('organizer-menu-garden')),
            kind == LocalSpaceKind.household ? findsOneWidget : findsNothing,
          );
          await tester.tap(find.byKey(const ValueKey('organizer-menu-plans')));
          await tester.pumpAndSettle();
        } else if (width < 900) {
          await mobileTab(tester, 'Opravila');
        } else {
          expect(find.widgetWithText(ListTile, 'Dom'), findsNothing);
          await tester.tap(find.widgetWithText(ListTile, 'Opravila'));
          await tester.pumpAndSettle();
        }
        expect(find.byType(SegmentedButton<OrganizerArea>), findsNothing);
        expect(
          find.text('Projekti').hitTestable(),
          width >= 900 || (width == 700 && kind != LocalSpaceKind.household)
              ? findsOneWidget
              : findsNothing,
        );
        expect(
          find.byKey(const ValueKey('content-_Area.plans')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });
    }
    testWidgets('new household is created without an account at $width', (
      tester,
    ) async {
      await loadCaptureFonts(tester);
      final local = LocalSpaceUiController(LocalSpaceKind.personal);
      final shared = SharingUiController(initial: CollaborationState());
      final key = GlobalKey();
      await pumpOrganizer(
        tester,
        MemoryOrganizerStorage(),
        width: width,
        height: 1000,
        localSpacesController: local,
        collaborationController: shared,
        repaintBoundaryKey: key,
      );
      await tester.tap(
        find.descendant(
          of: find.byType(OrganizerSpacePicker),
          matching: find.byType(DropdownButton<String>),
        ),
      );
      await tester.pumpAndSettle();
      await capture(tester, key, 'space-picker-${width.toInt()}');
      await tester.tap(find.text('Nov prostor').last);
      await tester.pumpAndSettle();
      await capture(tester, key, 'space-create-${width.toInt()}');
      await tester.enterText(
        find.byType(TextFormField).first,
        'QA novo gospodinjstvo',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Ustvari prostor'));
      await tester.pumpAndSettle();
      expect(local.created.single.kind, LocalSpaceKind.household);
      expect(local.created.single.name, 'QA novo gospodinjstvo');
      expect(shared.loginAttempts, isEmpty);
      expect(find.text('QA novo gospodinjstvo'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  }

  for (final width in [320.0, 390.0, 700.0, 1280.0]) {
    testWidgets(
      'organization today and calendar contain permitted child sources at $width',
      (tester) async {
        await loadCaptureFonts(tester);
        const org = 'organization';
        final session = sharingSession();
        final data = sharingData();
        final shared = SharingUiController(
          initial: CollaborationState(
            session: session,
            selectedSpaceId: org,
            scopes: [
              const SharedScope(
                id: org,
                name: 'QA organizacija z daljšim imenom',
                kind: SharedScopeKind.organization,
                role: SharedRole.owner,
              ),
              const SharedScope(
                id: sharingScopeId,
                name: 'QA dovoljen projekt',
                kind: SharedScopeKind.project,
                organizationId: org,
                role: SharedRole.member,
              ),
              const SharedScope(
                id: 'foreign',
                name: 'QA druga organizacija',
                kind: SharedScopeKind.project,
                organizationId: 'other',
                role: SharedRole.member,
              ),
            ],
            data: {sharingScopeId: data, 'foreign': data},
          ),
        );
        final key = GlobalKey();
        await pumpOrganizer(
          tester,
          MemoryOrganizerStorage(),
          width: width,
          height: 1000,
          collaborationController: shared,
          localSpacesController: LocalSpaceUiController(
            LocalSpaceKind.personal,
          ),
          repaintBoundaryKey: key,
        );
        expect(find.text('Pripravi zemljo'), findsOneWidget);
        expect(find.textContaining('QA dovoljen projekt'), findsWidgets);
        expect(find.textContaining('QA druga organizacija'), findsNothing);
        expect(find.text('Projekti organizacije'), findsNothing);
        await capture(tester, key, 'organization-today-${width.toInt()}');
        if (width < 900) {
          await mobileTab(tester, 'Koledar');
          if (width >= 600) {
            // Calendar is available through More on tablets.
          }
        } else {
          await tester.tap(find.widgetWithText(ListTile, 'Koledar'));
          await tester.pumpAndSettle();
        }
        expect(find.text('Projekti organizacije'), findsNothing);
        expect(find.byType(SharingWorkspace), findsOneWidget);
        await capture(tester, key, 'organization-calendar-${width.toInt()}');
        expect(tester.takeException(), isNull);
      },
    );
  }
}
