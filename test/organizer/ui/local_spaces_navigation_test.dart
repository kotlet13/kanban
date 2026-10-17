import 'dart:io';
import 'package:drift/native.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kanban/app.dart';
import 'package:kanban/app_router.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/sqlite_organizer_storage.dart';
import 'package:kanban/organizer/data/local_spaces_repository.dart';
import 'package:kanban/organizer/data/pending_invitation_store.dart';
import 'package:kanban/organizer/state/local_database_provider.dart';
import 'package:kanban/organizer/state/organizer_provider.dart';
import 'package:kanban/organizer/state/notification_local_spaces_provider.dart';
import 'package:kanban/organizer/state/portable_backup_provider.dart';
import 'package:kanban/organizer/platform/backup_preferences_replay.dart';
import 'package:kanban/organizer/platform/invitation_links/invitation_link_providers.dart';
import 'backup_ui_fixture.dart';
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
          matching: find.byType(OrganizerSpacePickerButton),
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
        await mobileTab(tester, 'Prostor');
        expect(find.byKey(const ValueKey('organizer-hub-home')), findsNothing);
        for (final area in ['shopping', 'people', 'garden']) {
          expect(
            find.byKey(ValueKey('organizer-hub-$area')),
            kind == LocalSpaceKind.household ? findsOneWidget : findsNothing,
          );
        }
        await mobileTab(tester, 'Opravila');
        expect(
          find.byKey(const ValueKey('planner-view-plans')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('planner-view-calendar')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('planner-view-ideas')),
          findsOneWidget,
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
          matching: find.byType(OrganizerSpacePickerButton),
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
        await mobileTab(tester, 'Opravila');
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
          await mobileTab(tester, 'Koledar');
        }
        expect(find.text('Projekti organizacije'), findsNothing);
        expect(find.byType(SharingWorkspace), findsOneWidget);
        await capture(tester, key, 'organization-calendar-${width.toInt()}');
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final width in [390.0, 1280.0]) {
    testWidgets(
      'picker opens exact project from another SQLite local workspace at $width',
      (tester) async {
        const projectId = '10000000-0000-4000-8000-000000000011';
        final db = CollaborationDatabase(NativeDatabase.memory());
        addTearDown(() async => await db.close());
        late LocalSpace organization;
        late LocalSpace other;
        final now = sharingTestNow;
        LocalProject project(String title, String description) => LocalProject(
          id: projectId,
          title: title,
          description: description,
          createdAt: now,
          updatedAt: now,
        );
        await tester.runAsync(() async {
          final personal = SqliteOrganizerStorage(db);
          await personal.initialize();
          final spaces = LocalSpacesRepository(db);
          organization = await spaces.createSpace(
            kind: LocalSpaceKind.organization,
            name: 'Ciljna lokalna organizacija',
          );
          other = await spaces.createSpace(
            kind: LocalSpaceKind.household,
            name: 'Drugi lokalni prostor',
          );
          final organizationStorage = SqliteOrganizerStorage(
            db,
            workspaceId: organization.id,
          );
          final organizationSnapshot = await organizationStorage.read();
          await organizationStorage.write(
            organizationSnapshot.copyWith(
              revision: organizationSnapshot.revision + 1,
              projects: [
                project('Ciljni projekt', 'Podrobnosti ciljnega projekta'),
              ],
            ),
          );
          final otherStorage = SqliteOrganizerStorage(
            db,
            workspaceId: other.id,
          );
          final otherSnapshot = await otherStorage.read();
          await otherStorage.write(
            otherSnapshot.copyWith(
              revision: otherSnapshot.revision + 1,
              projects: [
                project('Drugi projekt z istim ID', 'Ne odpri teh podrobnosti'),
              ],
            ),
          );
          await spaces.selectSpace(other.id);
        });
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        SharedPreferences.setMockInitialValues({'app_locale_code': 'sl'});
        appRouter.go('/');
        final shared = SharingUiController(initial: CollaborationState());
        final container = ProviderContainer(
          overrides: [
            localDatabaseProvider.overrideWith((ref) async => db),
            organizerStorageProvider.overrideWithValue(
              () async => SqliteOrganizerStorage(db),
            ),
            collaborationProvider.overrideWith(() => shared),
            invitationLinkSourceProvider.overrideWithValue(null),
            pendingInvitationStoreProvider.overrideWithValue(
              MemoryPendingInvitationStore(),
            ),
            portableBackupProvider.overrideWith(EmptyBackupUiController.new),
            backupPreferencesReplayProvider.overrideWith((ref) async => {}),
            notificationLocalSnapshotsProvider.overrideWith(
              (ref) async => [await ref.watch(organizerProvider.future)],
            ),
          ],
        );
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const JivieApp(),
          ),
        );
        await tester.runAsync(() async {
          await container.read(organizerProvider.future);
          await container.read(localSpacesProvider.future);
        });
        await tester.pumpAndSettle();
        await mobileTab(tester, 'Koledar');
        await tester.tap(find.byType(OrganizerSpacePickerButton));
        await tester.pumpAndSettle();
        final arrow = find.byKey(
          ValueKey('space-picker-expand-local:${organization.id}'),
        );
        await tester.ensureVisible(arrow);
        await tester.tap(arrow);
        await tester.pumpAndSettle();
        final target = find.byKey(
          ValueKey('space-choice-local-project:${organization.id}:$projectId'),
        );
        await tester.ensureVisible(target);
        await tester.tap(target);
        // Workspace selection reads SQLite and updates the organizer asynchronously.
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await tester.pumpAndSettle();
        expect(
          container.read(localSpacesProvider).requireValue.selectedSpaceId,
          organization.id,
        );
        expect(
          container.read(organizerProvider).requireValue.workspaceKey,
          organization.id,
        );
        expect(find.text('Podrobnosti ciljnega projekta'), findsWidgets);
        expect(find.text('Ne odpri teh podrobnosti'), findsNothing);
        expect(
          find.byKey(const ValueKey('content-_Area.projects')),
          findsOneWidget,
        );
        expect(shared.loginAttempts, isEmpty);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        container.dispose();
      },
    );

    testWidgets('picker opens shared project detail from calendar at $width', (
      tester,
    ) async {
      const root = SharedScope(
        id: 'shared-organization',
        name: 'Skupna organizacija',
        kind: SharedScopeKind.organization,
        role: SharedRole.member,
      );
      final data = sharingData();
      final shared = SharingUiController(
        initial: CollaborationState(
          session: sharingSession(),
          scopes: [root],
          data: {root.id: data},
        ),
      );
      await pumpOrganizer(
        tester,
        MemoryOrganizerStorage(),
        width: width,
        collaborationController: shared,
        localSpacesController: LocalSpaceUiController(LocalSpaceKind.personal),
      );
      await mobileTab(tester, 'Koledar');
      await tester.tap(find.byType(OrganizerSpacePickerButton));
      await tester.pumpAndSettle();
      final arrow = find.byKey(ValueKey('space-picker-expand-${root.id}'));
      await tester.ensureVisible(arrow);
      await tester.tap(arrow);
      await tester.pumpAndSettle();
      final target = find.byKey(
        ValueKey('space-choice-shared-project:${root.id}:project'),
      );
      await tester.ensureVisible(target);
      await tester.tap(target);
      await tester.pumpAndSettle();
      expect(shared.state.requireValue.selectedSpaceId, root.id);
      expect(
        find.byKey(const ValueKey('content-_Area.projects')),
        findsOneWidget,
      );
      expect(find.text('Pripravi zemljo'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'modern child project scope opens exact root detail from another area',
    (tester) async {
      const organization = SharedScope(
        id: 'parent-org',
        name: 'Organizacija s projekti',
        kind: SharedScopeKind.organization,
        role: SharedRole.owner,
      );
      const child = SharedScope(
        id: 'child-scope',
        name: 'Dovoljen projekt drugega lastnika',
        kind: SharedScopeKind.project,
        role: SharedRole.member,
        parentScopeId: 'parent-org',
        projectRootId: 'project',
      );
      final data = sharingData();
      final shared = SharingUiController(
        initial: CollaborationState(
          session: sharingSession(),
          scopes: [organization, child],
          data: {child.id: data},
        ),
      );
      await pumpOrganizer(
        tester,
        MemoryOrganizerStorage(),
        collaborationController: shared,
        localSpacesController: LocalSpaceUiController(LocalSpaceKind.personal),
      );
      await mobileTab(tester, 'Koledar');
      await tester.tap(find.byType(OrganizerSpacePickerButton));
      await tester.pumpAndSettle();
      final arrow = find.byKey(
        ValueKey('space-picker-expand-${organization.id}'),
      );
      await tester.ensureVisible(arrow);
      await tester.pumpAndSettle();
      await tester.tap(arrow);
      await tester.pumpAndSettle();
      final target = find.byKey(ValueKey('space-choice-${child.id}'));
      await tester.ensureVisible(target);
      await tester.pumpAndSettle();
      await tester.tap(target);
      await tester.pumpAndSettle();
      expect(shared.state.requireValue.selectedSpaceId, child.id);
      expect(
        find.byKey(const ValueKey('content-_Area.projects')),
        findsOneWidget,
      );
      expect(find.text('Pripravi zemljo'), findsOneWidget);
      expect(find.text('Skupni vrt'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );
}
