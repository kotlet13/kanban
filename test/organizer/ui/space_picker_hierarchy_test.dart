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
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'package:kanban/organizer/state/organizer_provider.dart';
import 'sharing_ui_fixture.dart';
import 'all_spaces_ui_test.dart' show loadQaFonts;

class Catalog extends LocalSpacesController {
  Catalog(this.catalog);
  final LocalSpacesState catalog;
  @override
  Future<LocalSpacesState> build() async => catalog;
  void replace(LocalSpacesState value) => state = AsyncData(value);
}

class PickerOrganizer extends OrganizerController {
  PickerOrganizer(this.snapshot);
  final OrganizerSnapshot snapshot;
  @override
  Future<OrganizerSnapshot> build() async => snapshot;
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
  SharingUiController? controller,
  Catalog? catalogController,
  OrganizerSnapshot? snapshot,
  void Function(String spaceId, String projectId)? onLocalProjectSelected,
  void Function(String scopeId, String projectId)? onSharedProjectSelected,
  ValueChanged<String>? onLocalSelected,
  VoidCallback? onAllSelected,
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
          () => controller ?? SharingUiController(initial: shared),
        ),
        localSpacesProvider.overrideWith(
          () =>
              catalogController ??
              Catalog(
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
        organizerProvider.overrideWith(
          () => PickerOrganizer(snapshot ?? OrganizerSnapshot()),
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
              onLocalProjectSelected: onLocalProjectSelected,
              onSharedProjectSelected: onSharedProjectSelected,
              onLocalSelected: onLocalSelected,
              onAllSelected: onAllSelected,
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
      testWidgets('project-only global search fits $width/$scale', (
        tester,
      ) async {
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
        expect(find.byKey(const ValueKey('space-choice-home')), findsOneWidget);
        expect(
          find.byKey(const ValueKey('space-choice-project-0')),
          findsNothing,
        );
        if (scale == 1) await capture(tester, 'spaces-${width.toInt()}');
        await tester.enterText(
          find.byKey(const ValueKey('space-picker-search')),
          'Project 38',
        );
        await tester.pumpAndSettle();
        expect(find.text('secret-parent'), findsNothing);
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
        } else if (width == 320) {
          await capture(tester, 'hierarchy-global-search-320-2x');
        }
        await tester.tap(find.byKey(const ValueKey('space-choice-project-38')));
        await tester.pumpAndSettle();
        expect(selected, 'project-38');
        expect(tester.takeException(), isNull);
      });
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
        isA<MaterialPageRoute>().having(
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
  const organization = SharedScope(
    id: 'organization',
    name: 'Dostopna organizacija',
    kind: SharedScopeKind.organization,
    role: SharedRole.owner,
  );
  SharedScope child(
    String id, {
    SharedRole role = SharedRole.owner,
    String? parent = 'organization',
    bool archived = false,
    bool revoked = false,
    bool deleted = false,
    String accessSource = 'direct',
  }) => SharedScope(
    id: id,
    name: 'Projekt $id',
    kind: SharedScopeKind.project,
    role: role,
    parentScopeId: parent,
    parentScopeKind: SharedScopeKind.organization,
    archived: archived,
    revoked: revoked,
    deleted: deleted,
    accessSource: accessSource,
  );
  Finder choice(String id) => find.byKey(ValueKey('space-choice-$id'));
  Finder expand(String id) => find.byKey(ValueKey('space-picker-expand-$id'));
  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.byType(OrganizerSpacePickerButton));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> search(WidgetTester tester, String query) async {
    await tester.enterText(
      find.byKey(const ValueKey('space-picker-search')),
      query,
    );
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
  }

  testWidgets('branch arrow expands independently and name selects parent', (
    tester,
  ) async {
    final selected = <String?>[];
    await pump(
      tester,
      CollaborationState(
        session: sharingSession(),
        scopes: [organization, household, child('owned')],
      ),
      onSelected: selected.add,
    );
    await open(tester);
    expect(choice('owned'), findsNothing);
    expect(expand('home'), findsNothing);
    expect(expand('organization'), findsOneWidget);
    await tap(tester, expand('organization'));
    expect(choice('owned'), findsOneWidget);
    await capture(tester, 'hierarchy-expanded-390');
    expect(selected, isEmpty);
    expect(
      tester.getTopLeft(choice('owned')).dx,
      greaterThan(tester.getTopLeft(choice('organization')).dx),
    );
    await tap(tester, expand('organization'));
    expect(choice('owned'), findsNothing);
    expect(selected, isEmpty);
    await tap(tester, choice('organization'));
    expect(selected, ['organization']);
    expect(find.byKey(const ValueKey('space-picker-search')), findsNothing);
  });

  testWidgets(
    'current project ownership controls shared shortcuts, including inherited access',
    (tester) async {
      final selected = <String?>[];
      final scopes = [
        organization,
        child('owned'),
        child('inherited', role: SharedRole.member, accessSource: 'space'),
        child('direct', role: SharedRole.viewer, parent: 'secret-parent'),
        child('standalone-owned', parent: 'hidden-parent'),
      ];
      await pump(
        tester,
        CollaborationState(session: sharingSession(), scopes: scopes),
        onSelected: selected.add,
      );
      await open(tester);
      expect(choice('standalone-owned'), findsOneWidget);
      expect(choice('direct'), findsNothing);
      await tap(tester, expand('organization'));
      expect(choice('owned'), findsOneWidget);
      expect(choice('inherited'), findsOneWidget);
      await tap(tester, find.byKey(const ValueKey('space-picker-projects')));
      expect(choice('owned'), findsNothing);
      expect(choice('standalone-owned'), findsNothing);
      expect(choice('inherited'), findsOneWidget);
      expect(choice('direct'), findsOneWidget);
      expect(find.text('secret-parent'), findsNothing);
      expect(find.text('hidden-parent'), findsNothing);
      await tap(tester, choice('inherited'));
      expect(selected, ['inherited']);

      // Ownership can change independently from the parent's owner role.
      final updated = SharingUiController(
        initial: CollaborationState(
          session: sharingSession(),
          scopes: [
            organization,
            child('owned', role: SharedRole.member),
          ],
        ),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await pump(tester, updated.initial, controller: updated);
      await open(tester);
      await tap(tester, find.byKey(const ValueKey('space-picker-projects')));
      expect(choice('owned'), findsOneWidget);
    },
  );

  testWidgets(
    'global search reveals collapsed tree and direct-only matches from either tab',
    (tester) async {
      await pump(
        tester,
        CollaborationState(
          session: sharingSession(),
          scopes: [
            organization,
            child('needle-owned'),
            child('needle-foreign', role: SharedRole.member),
            child(
              'needle-direct',
              role: SharedRole.viewer,
              parent: 'secret-parent',
            ),
            child('unrelated'),
            child('needle-revoked', revoked: true),
            child('needle-deleted', deleted: true),
          ],
        ),
      );
      await open(tester);
      expect(choice('needle-owned'), findsNothing);
      await search(tester, '  needle  ');
      expect(choice('organization'), findsOneWidget);
      expect(choice('needle-owned'), findsOneWidget);
      expect(choice('needle-foreign'), findsOneWidget);
      expect(choice('needle-direct'), findsOneWidget);
      expect(choice('unrelated'), findsNothing);
      expect(choice('needle-revoked'), findsNothing);
      expect(choice('needle-deleted'), findsNothing);
      expect(find.text('secret-parent'), findsNothing);
      await tap(tester, find.byKey(const ValueKey('space-picker-projects')));
      expect(choice('needle-owned'), findsOneWidget);
      expect(choice('needle-direct'), findsOneWidget);
      await search(tester, '');
      expect(choice('needle-owned'), findsNothing);
      await tap(tester, find.byKey(const ValueKey('space-picker-spaces')));
      // Search expansion never replaces the user's collapsed preference.
      expect(choice('needle-owned'), findsNothing);
      await tap(tester, expand('organization'));
      await search(tester, 'needle-owned');
      await search(tester, '');
      expect(choice('needle-owned'), findsOneWidget);
    },
  );

  testWidgets('inaccessible parent and siblings never leak through search', (
    tester,
  ) async {
    const hidden = SharedScope(
      id: 'secret-parent',
      name: 'Private parent name',
      kind: SharedScopeKind.organization,
      role: SharedRole.viewer,
      revoked: true,
    );
    await pump(
      tester,
      CollaborationState(
        session: sharingSession(),
        scopes: [
          hidden,
          child('allowed', role: SharedRole.member, parent: hidden.id),
          child('private-sibling', parent: hidden.id, revoked: true),
        ],
      ),
    );
    await open(tester);
    await search(tester, 'allowed');
    expect(choice('allowed'), findsOneWidget);
    expect(choice(hidden.id), findsNothing);
    expect(choice('private-sibling'), findsNothing);
    expect(
      find
          .text(hidden.name, findRichText: false)
          .evaluate()
          .where((e) => e.widget is Text),
      isEmpty,
    );
    await search(tester, hidden.name);
    expect(choice('allowed'), findsNothing);
    expect(
      find
          .text(hidden.name, findRichText: false)
          .evaluate()
          .where((e) => e.widget is Text),
      isEmpty,
    );
  });

  for (final reason in [
    'account',
    'revoked',
    'deleted',
    'session',
    'access',
    'deletion',
  ]) {
    testWidgets('stale shared project tap cannot select after $reason change', (
      tester,
    ) async {
      final selected = <String?>[];
      final controller = SharingUiController(
        initial: CollaborationState(
          session: sharingSession(),
          scopes: [child('target', role: SharedRole.member, parent: null)],
        ),
      );
      await pump(
        tester,
        controller.initial,
        controller: controller,
        onSelected: selected.add,
      );
      await open(tester);
      await search(tester, 'target');
      final oldTap = tester.widget<ListTile>(choice('target')).onTap!;
      controller.replace(
        CollaborationState(
          session: sharingSession(second: reason == 'account'),
          sessionInvalid: reason == 'session',
          localAccessAllowed: reason != 'access',
          deletionPending: reason == 'deletion',
          scopes: [
            child(
              'target',
              role: SharedRole.member,
              parent: null,
              revoked: reason == 'revoked',
              deleted: reason == 'deleted',
            ),
          ],
        ),
      );
      oldTap();
      await tester.pumpAndSettle();
      expect(selected, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'local projects retain workspace identity and never enter shared shortcuts',
    (tester) async {
      final selected = <(String, String)>[];
      final localSelections = <String>[];
      final now = sharingTestNow;
      LocalProject project(String id, String title, {bool archived = false}) =>
          LocalProject(
            id: id,
            title: title,
            description: '',
            createdAt: now,
            updatedAt: now,
            archived: archived,
          );
      final catalog = LocalSpacesState(
        spaces: const [
          LocalSpace(id: 'local', kind: LocalSpaceKind.personal, name: ''),
          LocalSpace(
            id: 'local-org',
            kind: LocalSpaceKind.organization,
            name: 'Lokalna organizacija',
          ),
        ],
        snapshots: {
          'local-org': OrganizerSnapshot(
            workspaceKey: 'local-org',
            projects: [
              project('same-id', 'Ciljni lokalni projekt'),
              project(
                'archived-project',
                'Arhiviran lokalni projekt',
                archived: true,
              ),
            ],
          ),
        },
      );
      await pump(
        tester,
        CollaborationState(),
        local: catalog,
        snapshot: OrganizerSnapshot(
          projects: [project('same-id', 'Osebni projekt')],
        ),
        onLocalSelected: localSelections.add,
        onLocalProjectSelected: (spaceId, projectId) =>
            selected.add((spaceId, projectId)),
      );
      await open(tester);
      expect(choice('local-project:local-org:same-id'), findsNothing);
      await tap(tester, expand('local:local-org'));
      expect(choice('local-project:local-org:same-id'), findsOneWidget);
      expect(choice('local-project:local:same-id'), findsNothing);
      await tap(tester, find.byKey(const ValueKey('space-picker-projects')));
      expect(choice('local-project:local-org:same-id'), findsNothing);
      await search(tester, 'Ciljni lokalni');
      expect(choice('local:local-org'), findsOneWidget);
      await tap(tester, choice('local-project:local-org:same-id'));
      expect(selected, [('local-org', 'same-id')]);
      expect(localSelections, isEmpty);
    },
  );

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets(
      'expanded hierarchy has separate tap targets at 320/2x on $platform',
      (tester) async {
        final selected = <String?>[];
        await pump(
          tester,
          CollaborationState(
            session: sharingSession(),
            scopes: [organization, child('dolgo-ime-projekta-za-ozek-telefon')],
          ),
          width: 320,
          scale: 2,
          platform: platform,
          onSelected: selected.add,
        );
        await open(tester);
        final arrowRect = tester.getRect(expand('organization'));
        expect(arrowRect.width, greaterThanOrEqualTo(48));
        expect(arrowRect.height, greaterThanOrEqualTo(48));
        await tap(tester, expand('organization'));
        expect(selected, isEmpty);
        expect(choice('dolgo-ime-projekta-za-ozek-telefon'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await capture(tester, 'hierarchy-${platform.name}-320-2x');
        await tap(tester, choice('dolgo-ime-projekta-za-ozek-telefon'));
        expect(selected, ['dolgo-ime-projekta-za-ozek-telefon']);
      },
    );
  }

  testWidgets(
    'archived children need explicit archive expansion and remain globally searchable',
    (tester) async {
      final selected = <String?>[];
      await pump(
        tester,
        CollaborationState(
          session: sharingSession(),
          scopes: [organization, child('archived-owned', archived: true)],
        ),
        onSelected: selected.add,
      );
      await open(tester);
      await tap(tester, expand('organization'));
      expect(choice('archived-owned'), findsNothing);
      final archived = find.byKey(
        const ValueKey('space-picker-archived-organization'),
      );
      await tap(
        tester,
        find.descendant(of: archived, matching: find.text('Arhivirano')).first,
      );
      expect(choice('archived-owned'), findsOneWidget);
      await tap(
        tester,
        find.descendant(of: archived, matching: find.text('Arhivirano')).first,
      );
      expect(choice('archived-owned'), findsNothing);
      await search(tester, 'archived-owned');
      expect(choice('organization'), findsOneWidget);
      expect(choice('archived-owned'), findsOneWidget);
      await tap(tester, choice('archived-owned'));
      expect(selected, ['archived-owned']);
    },
  );

  for (final change in ['removed', 'bound', 'project-removed', 'account']) {
    testWidgets('stale local project tap is rejected after $change change', (
      tester,
    ) async {
      final selected = <(String, String)>[];
      final localProject = LocalProject(
        id: 'p',
        title: 'Lokalni cilj',
        description: '',
        createdAt: sharingTestNow,
        updatedAt: sharingTestNow,
      );
      const localSpace = LocalSpace(
        id: 'org',
        kind: LocalSpaceKind.organization,
        name: 'Lokalna veja',
      );
      final snapshot = OrganizerSnapshot(
        workspaceKey: 'org',
        projects: [localProject],
      );
      final catalog = Catalog(
        LocalSpacesState(
          spaces: const [localSpace],
          snapshots: {'org': snapshot},
        ),
      );
      final controller = SharingUiController(
        initial: CollaborationState(session: sharingSession()),
      );
      await pump(
        tester,
        controller.initial,
        controller: controller,
        catalogController: catalog,
        onLocalProjectSelected: (spaceId, projectId) =>
            selected.add((spaceId, projectId)),
      );
      await open(tester);
      await search(tester, localProject.title);
      final oldTap = tester
          .widget<ListTile>(choice('local-project:org:p'))
          .onTap!;
      if (change == 'account') {
        controller.switchAccount();
      } else {
        catalog.replace(
          LocalSpacesState(
            spaces: change == 'removed'
                ? []
                : [
                    LocalSpace(
                      id: localSpace.id,
                      kind: localSpace.kind,
                      name: localSpace.name,
                      binding: change == 'bound'
                          ? LocalSpaceBinding(
                              partition: sharingSession().partition,
                              scopeId: 'new-binding',
                            )
                          : null,
                    ),
                  ],
            snapshots: {
              'org': change == 'project-removed'
                  ? OrganizerSnapshot(workspaceKey: 'org')
                  : snapshot,
            },
          ),
        );
      }
      oldTap();
      await tester.pumpAndSettle();
      expect(selected, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Vsi and personal selection preserve their dedicated callbacks', (
    tester,
  ) async {
    var all = 0;
    final local = <String>[];
    await pump(
      tester,
      CollaborationState(),
      onAllSelected: () => all++,
      onLocalSelected: local.add,
    );
    await open(tester);
    await tap(tester, choice(OrganizerSpacePicker.allAction));
    expect(all, 1);
    await open(tester);
    await tap(tester, choice('local:local'));
    expect(local, ['local']);
  });
  testWidgets(
    'current private projects replace stale catalog and never appear under organization',
    (tester) async {
      LocalProject project(String id, String title) => LocalProject(
        id: id,
        title: title,
        description: '',
        createdAt: sharingTestNow,
        updatedAt: sharingTestNow,
      );
      final session = sharingSession();
      final private = OrganizerSnapshot(
        workspaceKey: 'private:${session.partition}',
        projects: [project('fresh', 'Aktualen zasebni projekt')],
      );
      final local = LocalSpacesState(
        spaces: const [
          LocalSpace(id: 'local', kind: LocalSpaceKind.personal, name: ''),
          LocalSpace(
            id: 'org',
            kind: LocalSpaceKind.organization,
            name: 'Lokalna organizacija',
          ),
        ],
        snapshots: {
          'local': OrganizerSnapshot(
            projects: [project('stale', 'Zastarel lokalni projekt')],
          ),
          'org': private,
        },
      );
      final selected = <(String, String)>[];
      await pump(
        tester,
        CollaborationState(session: session),
        local: local,
        snapshot: private,
        onLocalProjectSelected: (spaceId, projectId) =>
            selected.add((spaceId, projectId)),
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(OrganizerSpacePicker)),
      );
      await container.read(organizerProvider.future);
      await open(tester);
      await search(tester, 'projekt');
      expect(choice('local-project:local:fresh'), findsOneWidget);
      expect(choice('local-project:local:stale'), findsNothing);
      expect(choice('local-project:org:fresh'), findsNothing);
      await tap(tester, choice('local-project:local:fresh'));
      expect(selected, [('local', 'fresh')]);

      await tester.pumpWidget(const SizedBox.shrink());
      await pump(
        tester,
        CollaborationState(session: sharingSession(second: true)),
        local: LocalSpacesState(
          spaces: local.spaces,
          snapshots: {'local': private},
        ),
        snapshot: OrganizerSnapshot(),
      );
      await open(tester);
      await search(tester, 'Aktualen zasebni');
      expect(choice('local-project:local:fresh'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
