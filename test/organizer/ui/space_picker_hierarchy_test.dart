import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/l10n/app_localizations.dart';
import 'package:kanban/organizer/presentation/shared/space_picker.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';
import 'package:kanban/organizer/state/local_spaces_provider.dart';
import 'sharing_ui_fixture.dart';
import 'all_spaces_ui_test.dart' show loadQaFonts;

class Catalog extends LocalSpacesController {
  Catalog(this.catalog);
  final LocalSpacesState catalog;
  @override
  Future<LocalSpacesState> build() async => catalog;
}

const household = SharedScope(
  id: 'home',
  name: 'Shared household',
  kind: SharedScopeKind.household,
  role: SharedRole.member,
);
SharedScope project(int i, {bool archived = false}) => SharedScope(
  id: 'project-$i',
  name: 'Project $i',
  kind: SharedScopeKind.project,
  role: SharedRole.viewer,
  parentScopeId: 'secret-parent',
  parentScopeKind: SharedScopeKind.organization,
  archived: archived,
);
final key = GlobalKey();
Future<void> capture(WidgetTester tester, String name) async {
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(key),
    );
    final image = await boundary.toImage(pixelRatio: 1);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('build/qa/upgrade-navigation/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
}

Future<void> pump(
  WidgetTester tester,
  CollaborationState shared, {
  double width = 390,
  double scale = 1,
  ValueChanged<String?>? onSelected,
  LocalSpacesState? local,
  TargetPlatform platform = TargetPlatform.android,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await loadQaFonts(tester);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        collaborationProvider.overrideWith(
          () => SharingUiController(initial: shared),
        ),
        localSpacesProvider.overrideWith(
          () => Catalog(
            local ??
                LocalSpacesState(
                  spaces: const [
                    LocalSpace(
                      id: 'local',
                      kind: LocalSpaceKind.personal,
                      name: '',
                    ),
                  ],
                ),
          ),
        ),
      ],
      child: RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(platform: platform),
          locale: const Locale('sl'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(
            body: OrganizerSpacePicker(
              compact: true,
              onSelected: onSelected ?? (_) {},
              onConnect: () {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final width in [320.0, 390.0, 1280.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'main choices contain spaces, projects separately searchable at $width/$scale',
        (tester) async {
          String? selected;
          await pump(
            tester,
            CollaborationState(
              session: sharingSession(),
              selectedSpaceId: household.id,
              scopes: [household, for (var i = 0; i < 40; i++) project(i)],
            ),
            width: width,
            scale: scale,
            onSelected: (id) => selected = id,
          );
          await tester.tap(find.byType(OrganizerSpacePickerButton));
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('space-choice-home')),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('space-choice-project-0')),
            findsNothing,
          );
          if (scale == 1) await capture(tester, 'spaces-${width.toInt()}');
          await tester.tap(find.byKey(const ValueKey('space-picker-projects')));
          await tester.pumpAndSettle();
          expect(find.byKey(const ValueKey('space-choice-home')), findsNothing);
          expect(
            find.byKey(const ValueKey('space-choice-project-0')),
            findsOneWidget,
          );
          expect(find.text('secret-parent'), findsNothing);
          await tester.enterText(
            find.byKey(const ValueKey('space-picker-search')),
            'Project 38',
          );
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('space-choice-project-38')),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('space-choice-project-0')),
            findsNothing,
          );
          tester.testTextInput.hide();
          await tester.pumpAndSettle();
          if (scale == 1) {
            await capture(tester, 'shared-project-search-${width.toInt()}');
          }
          await tester.tap(
            find.byKey(const ValueKey('space-choice-project-38')),
          );
          await tester.pumpAndSettle();
          expect(selected, 'project-38');
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  testWidgets(
    'project-only access opens project list directly without granting or showing parent',
    (tester) async {
      String? selected;
      final p = project(0);
      await pump(
        tester,
        CollaborationState(
          session: sharingSession(),
          selectedSpaceId: p.id,
          scopes: [p],
        ),
        onSelected: (id) => selected = id,
      );
      expect(find.text(p.name), findsOneWidget);
      await tester.tap(find.byType(OrganizerSpacePickerButton));
      await tester.pumpAndSettle();
      expect(find.text('Neposredno deljen projekt'), findsOneWidget);
      expect(find.text('secret-parent'), findsNothing);
      await tester.tap(find.byKey(ValueKey('space-choice-${p.id}')));
      await tester.pumpAndSettle();
      expect(selected, p.id);
    },
  );
  testWidgets(
    'archived local spaces and shared projects stay collapsed until explicit expansion',
    (tester) async {
      await pump(
        tester,
        CollaborationState(
          session: sharingSession(),
          scopes: [household, project(2, archived: true)],
        ),
        local: LocalSpacesState(
          spaces: const [
            LocalSpace(id: 'local', kind: LocalSpaceKind.personal, name: ''),
            LocalSpace(
              id: 'archived-home',
              kind: LocalSpaceKind.household,
              name: 'Archived local home',
              archived: true,
            ),
          ],
        ),
      );
      await tester.tap(find.byType(OrganizerSpacePickerButton));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('space-choice-local:archived-home')),
        findsNothing,
      );
      await tester.tap(find.text('Arhivirano'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('space-choice-local:archived-home')),
        findsOneWidget,
      );
      await capture(tester, 'archived-spaces-390');
      await tester.tap(find.byKey(const ValueKey('space-picker-projects')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('space-choice-project-2')),
        findsNothing,
      );
      await tester.tap(find.text('Arhivirano'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('space-choice-project-2')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'iOS picker opens safe fullscreen page, searches, closes and backs at 320/2x',
    (tester) async {
      final state = CollaborationState(
        session: sharingSession(),
        scopes: [household, project(0)],
      );
      await pump(
        tester,
        state,
        width: 320,
        scale: 2,
        platform: TargetPlatform.iOS,
      );
      await tester.tap(find.byType(OrganizerSpacePickerButton));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(find.byType(SafeArea), findsWidgets);
      await capture(tester, 'ios-picker-320-2x');
      final route = ModalRoute.of(
        tester.element(find.byKey(const ValueKey('space-picker-search'))),
      )!;
      expect(
        route,
        isA<MaterialPageRoute<String>>().having(
          (r) => r.fullscreenDialog,
          'fullscreenDialog',
          true,
        ),
      );
      await tester.enterText(
        find.byKey(const ValueKey('space-picker-search')),
        'absent',
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('space-choice-home')), findsNothing);
      await tester.tap(find.byTooltip('Zapri'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('space-picker-search')), findsNothing);
      await tester.tap(find.byType(OrganizerSpacePickerButton));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('space-picker-search')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
