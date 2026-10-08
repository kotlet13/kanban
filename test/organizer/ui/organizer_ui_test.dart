import 'package:kanban/organizer/state/portable_backup_provider.dart';
import 'backup_ui_fixture.dart';
import 'package:kanban/organizer/platform/backup_preferences_replay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kanban/app.dart';
import 'package:kanban/features/auth/connect_page.dart';
import 'package:kanban/app_router.dart';
import 'package:kanban/organizer/data/organizer_storage.dart';
import 'package:kanban/organizer/data/garden_repository.dart';
import 'package:kanban/organizer/state/garden_provider.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'package:kanban/organizer/state/organizer_provider.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';
import 'package:kanban/organizer/platform/invitation_links/invitation_link_providers.dart';

class MemoryOrganizerStorage implements OrganizerStorage {
  OrganizerSnapshot snapshot = OrganizerSnapshot();
  int writes = 0;
  @override
  Future<OrganizerSnapshot> read() async => snapshot;
  @override
  Future<void> write(OrganizerSnapshot next) async {
    snapshot = next;
    writes++;
  }

  @override
  Future<void> close() async {}
}

Future<void> pumpOrganizer(
  WidgetTester tester,
  MemoryOrganizerStorage storage, {
  double width = 390,
  double height = 1000,
  GardenRepository? gardenRepository,
  String locale = 'sl',
  String theme = 'light',
  Future<Map<String, Object?>> Function()? replayPreferences,
  CollaborationController? collaborationController,
  GlobalKey? repaintBoundaryKey,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues({
    'app_locale_code': locale,
    'app_theme_mode': theme,
  });
  appRouter.go('/');
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        if (repaintBoundaryKey != null)
          invitationLinkSourceProvider.overrideWithValue(null),
        if (collaborationController != null)
          collaborationProvider.overrideWith(() => collaborationController),
        if (gardenRepository != null)
          gardenRepositoryProvider.overrideWith(
            (ref) async => gardenRepository,
          ),
        portableBackupProvider.overrideWith(EmptyBackupUiController.new),
        backupPreferencesReplayProvider.overrideWith(
          (ref) async => replayPreferences == null
              ? <String, Object?>{}
              : await replayPreferences(),
        ),
        organizerStorageProvider.overrideWithValue(() async => storage),
      ],
      child: repaintBoundaryKey == null
          ? const KanbanApp()
          : RepaintBoundary(key: repaintBoundaryKey, child: const KanbanApp()),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> mobileTab(WidgetTester tester, String text) async {
  final destination = find.widgetWithText(NavigationDestination, text);
  if (destination.evaluate().isNotEmpty) {
    await tester.tap(destination);
  } else {
    if (find
        .byKey(const ValueKey('organizer-mobile-menu'))
        .evaluate()
        .isEmpty) {
      await tester.tap(find.byKey(const ValueKey('organizer-menu-open')));
      await tester.pumpAndSettle();
    }
    // Older scenario helpers enter More then select a module. On a phone the
    // same intermediate step opens the real drawer; there is no More screen.
    if (text == 'Več' || text == 'More') return;
    final item = find.widgetWithText(ListTile, text).first;
    await tester.ensureVisible(item);
    await tester.tap(item);
  }
  await tester.pumpAndSettle();
}

Future<void> saveTitle(WidgetTester tester, String title) async {
  await tester.enterText(
    find.byKey(const ValueKey('organizer-title-field')),
    title,
  );
  await tester.tap(find.byKey(const ValueKey('organizer-save')));
  await tester.pumpAndSettle();
}

void main() {
  for (final width in [320.0, 390.0, 1280.0]) {
    for (final locale in ['sl', 'en']) {
      for (final theme in ['light', 'dark']) {
        testWidgets('empty navigation $width $locale $theme has no overflow', (
          tester,
        ) async {
          final store = MemoryOrganizerStorage();
          await pumpOrganizer(
            tester,
            store,
            width: width,
            locale: locale,
            theme: theme,
          );
          expect(
            find.text('Jivie'),
            width < 600 ? findsNothing : findsOneWidget,
          );
          expect(
            find.text(
              locale == 'sl'
                  ? 'Začni z enim opravilom.'
                  : 'Start with one task.',
            ),
            findsOneWidget,
          );
          expect(store.writes, 0);
          final areas = locale == 'sl'
              ? ['Načrti', 'Nakupi', 'Več']
              : ['Plans', 'Shopping', 'More'];
          if (width < 900) {
            for (final area in areas) {
              await mobileTab(tester, area);
              expect(tester.takeException(), isNull);
            }
            await tester.tap(
              find.widgetWithText(
                ListTile,
                locale == 'sl' ? 'Nastavitve' : 'Settings',
              ),
            );
            await tester.pumpAndSettle();
          } else {
            for (final area
                in locale == 'sl'
                    ? [
                        'Koledar',
                        'Projekti',
                        'Nakupi',
                        'Finance',
                        'Dom',
                        'Nastavitve',
                      ]
                    : [
                        'Calendar',
                        'Projects',
                        'Shopping',
                        'Finances',
                        'Home',
                        'Settings',
                      ]) {
              await tester.tap(find.widgetWithText(ListTile, area));
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull);
            }
          }
          expect(
            find.text(locale == 'sl' ? 'Varnostna kopija' : 'Backup'),
            findsOneWidget,
          );
          final aboutLabel = locale == 'sl'
              ? 'O aplikaciji Jivie'
              : 'About Jivie';
          await tester.ensureVisible(find.text(aboutLabel));
          await tester.tap(find.text(aboutLabel));
          await tester.pumpAndSettle();
          expect(find.byType(AboutDialog), findsOneWidget);
          expect(find.text('Jivie'), findsNWidgets(width < 600 ? 1 : 2));
          expect(tester.takeException(), isNull);
        });
      }
    }
  }

  testWidgets(
    'local project task and shopping CRUD survives navigation and app recreation',
    (tester) async {
      final store = MemoryOrganizerStorage();
      await pumpOrganizer(tester, store);
      await tester.ensureVisible(
        find.widgetWithText(TextButton, 'Dodaj opravilo').first,
      );
      await tester.tap(find.widgetWithText(TextButton, 'Dodaj opravilo').first);
      await tester.pumpAndSettle();
      await saveTitle(tester, 'Pripravi vrt');
      expect(store.snapshot.tasks.single.title, 'Pripravi vrt');
      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();
      expect(store.snapshot.tasks.single.isCompleted, true);
      await mobileTab(tester, 'Načrti');
      await tester.tap(find.text('Projekti').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nov projekt').first);
      await tester.pumpAndSettle();
      await saveTitle(tester, 'Prenova');
      expect(store.snapshot.projects.single.title, 'Prenova');
      await tester.tap(find.text('Prenova'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Dodaj opravilo'));
      await tester.pumpAndSettle();
      await saveTitle(tester, 'Izmeri sobo');
      expect(
        store.snapshot.tasks.last.projectId,
        store.snapshot.projects.single.id,
      );
      await tester.tap(find.text('Izmeri sobo'));
      await tester.pumpAndSettle();
      await saveTitle(tester, 'Izmeri kuhinjo');
      expect(store.snapshot.tasks.last.title, 'Izmeri kuhinjo');
      await mobileTab(tester, 'Nakupi');
      await tester.tap(find.text('Nov seznam').first);
      await tester.pumpAndSettle();
      await saveTitle(tester, 'Trgovina');
      expect(find.byKey(const ValueKey('shopping-item-field')), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('shopping-item-field')),
        'Mleko',
      );
      await tester.tap(find.byTooltip('Dodaj izdelek'));
      await tester.pumpAndSettle();
      expect(store.snapshot.shoppingItems.single.title, 'Mleko');
      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();
      expect(store.snapshot.shoppingItems.single.isChecked, true);
      await mobileTab(tester, 'Danes');
      await mobileTab(tester, 'Nakupi');
      expect(find.text('Trgovina'), findsOneWidget);
      expect(find.text('Kupljeno (1)'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await pumpOrganizer(tester, store);
      expect(store.snapshot.tasks.length, 2);
      await mobileTab(tester, 'Načrti');
      expect(find.text('Izmeri kuhinjo'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    '320px editor validates title and uses scrollable keyboard layout',
    (tester) async {
      final store = MemoryOrganizerStorage();
      await pumpOrganizer(tester, store, width: 320);
      await tester.ensureVisible(
        find.widgetWithText(TextButton, 'Dodaj opravilo').first,
      );
      await tester.tap(find.widgetWithText(TextButton, 'Dodaj opravilo').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('organizer-save')));
      await tester.pumpAndSettle();
      expect(find.text('Vpiši naslov.'), findsOneWidget);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      await saveTitle(
        tester,
        'Dolg naslov opravila, ki se mora lepo preliti tudi na majhnem telefonu',
      );
      tester.view.resetViewInsets();
      expect(store.snapshot.tasks, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'existing Kanboard stays explicitly reachable without local synchronization',
    (tester) async {
      await pumpOrganizer(tester, MemoryOrganizerStorage());
      await mobileTab(tester, 'Več');
      await tester.tap(find.widgetWithText(ListTile, 'Nastavitve'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Obstoječi Kanboard'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Poveži račun'));
      await tester.tap(find.text('Poveži račun'));
      await tester.pumpAndSettle();
      expect(find.byType(ConnectPage), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'populated 320px screens handle long records and home categorization',
    (tester) async {
      final now = DateTime.now().toUtc();
      final store = MemoryOrganizerStorage();
      store.snapshot = OrganizerSnapshot(
        projects: [
          LocalProject(
            id: 'p1',
            title: 'Osebni načrt za naslednji mesec',
            description: '',
            createdAt: now,
            updatedAt: now,
          ),
          LocalProject(
            id: 'p2',
            title: 'Domača prenova z dolgim naslovom',
            description: '',
            area: ProjectArea.home,
            createdAt: now,
            updatedAt: now,
          ),
        ],
        tasks: [
          LocalTask(
            id: 't1',
            projectId: null,
            isCompleted: false,
            title: 'Daljše opravilo s pomembnimi podrobnostmi za majhen zaslon',
            notes: '',
            dueAt: now.add(const Duration(days: 2)),
            createdAt: now,
            updatedAt: now,
          ),
        ],
        events: [
          LocalEvent(
            id: 'e1',
            projectId: null,
            endsAt: null,
            title: 'Dogodek z dolgim naslovom in podrobnostmi o obisku',
            notes: 'Daljša opomba z informacijami za uporabnika.',
            startsAt: now.add(const Duration(days: 1)),
            createdAt: now,
            updatedAt: now,
          ),
        ],
        financeEntries: [
          FinanceEntry(
            id: 'f1',
            projectId: null,
            title: 'Nakup za domači projekt z daljšim opisom',
            notes: '',
            amountMinor: 12345678,
            currency: 'EUR',
            kind: FinanceEntryKind.expense,
            occurredAt: now,
            createdAt: now,
            updatedAt: now,
          ),
        ],
      );
      await pumpOrganizer(tester, store, width: 320);
      await mobileTab(tester, 'Načrti');
      await tester.tap(find.text('Koledar').first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await mobileTab(tester, 'Več');
      await tester.tap(find.widgetWithText(ListTile, 'Finance'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(ListTile),
          matching: find.text('−123456.78 EUR'),
        ),
        findsNWidgets(2), // The recorded ledger and its dated cash-flow view.
      );
      expect(
        find.descendant(
          of: find.byType(Card),
          matching: find.text('−123456.78 EUR'),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await mobileTab(tester, 'Več');
      await tester.tap(find.widgetWithText(ListTile, 'Dom'));
      await tester.pumpAndSettle();
      expect(find.text('Domača prenova z dolgim naslovom'), findsOneWidget);
      expect(find.text('Osebni načrt za naslednji mesec'), findsNothing);
      await tester.tap(find.text('Domača prenova z dolgim naslovom'));
      await tester.pumpAndSettle();
      await mobileTab(tester, 'Danes');
      await mobileTab(tester, 'Več');
      await tester.tap(find.widgetWithText(ListTile, 'Dom'));
      await tester.pumpAndSettle();
      expect(find.text('V tem projektu še ni opravil.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('home creates an explicitly categorized local project', (
    tester,
  ) async {
    final store = MemoryOrganizerStorage();
    await pumpOrganizer(tester, store);
    await mobileTab(tester, 'Več');
    await tester.tap(find.widgetWithText(ListTile, 'Dom'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nov projekt'));
    await tester.pumpAndSettle();
    await saveTitle(tester, 'Vrt');
    expect(store.snapshot.projects.single.area, ProjectArea.home);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'imported far-future date opens a bounded picker without changing its value',
    (tester) async {
      final store = MemoryOrganizerStorage();
      final now = DateTime.now().toUtc();
      final due = DateTime.utc(2500, 6, 12);
      store.snapshot = OrganizerSnapshot(
        tasks: [
          LocalTask(
            id: 'far',
            title: 'Daljni rok',
            notes: '',
            projectId: null,
            dueAt: due,
            isCompleted: false,
            createdAt: now,
            updatedAt: now,
          ),
        ],
      );
      await pumpOrganizer(tester, store);
      await tester.ensureVisible(find.text('Daljni rok'));
      await tester.tap(find.text('Daljni rok'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.descendant(
          of: find.byKey(const ValueKey('task-due-date')),
          matching: find.byType(OutlinedButton),
        ),
      );
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('task-due-date')),
          matching: find.byType(OutlinedButton),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Prekliči').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('organizer-save')));
      await tester.pumpAndSettle();
      expect(store.snapshot.tasks.single.dueAt, due);
    },
  );
}
