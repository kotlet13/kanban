import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/l10n/app_localizations.dart';
import 'package:kanban/organizer/domain/all_spaces_projection.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'package:kanban/organizer/presentation/all_spaces/all_spaces_page.dart';
import 'package:kanban/organizer/presentation/all_spaces/all_spaces_rows.dart';
import 'package:kanban/organizer/presentation/shared/space_picker.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';
import 'package:kanban/organizer/state/organizer_provider.dart';
import 'organizer_ui_test.dart'
    show pumpOrganizer, MemoryOrganizerStorage, mobileTab;
import 'personal_workspace_ui_test.dart' show WorkspaceController;
import 'sharing_ui_fixture.dart';

final now = DateTime(2026, 10, 9, 12);
const secondScope = SharedScope(
  id: 'second-scope',
  name: 'QA projekt prenove kuhinje',
  kind: SharedScopeKind.project,
  role: SharedRole.owner,
);
LocalTask task(String id, String title) => LocalTask(
  id: id,
  title: title,
  notes: 'QA: sintetični testni zapis',
  projectId: null,
  dueAt: now,
  isCompleted: false,
  createdAt: now,
  updatedAt: now,
);
LocalProject project(String id, String title) => LocalProject(
  id: id,
  title: title,
  description: '',
  area: ProjectArea.home,
  createdAt: now,
  updatedAt: now,
);
FinanceEntry money(
  String id,
  String title, {
  DateTime? plannedAt,
  FinanceEntryKind kind = FinanceEntryKind.expense,
}) => FinanceEntry(
  id: id,
  title: title,
  status: plannedAt == null
      ? FinanceEntryStatus.posted
      : FinanceEntryStatus.planned,
  amountMinor: 1599,
  currency: 'EUR',
  kind: kind,
  occurredAt: now,
  plannedAt: plannedAt,
  projectId: null,
  notes: '',
  createdAt: now,
  updatedAt: now,
);
OrganizerSnapshot localData() => OrganizerSnapshot(
  tasks: [
    task('same-task', 'QA osebno opravilo z daljšim slovenskim naslovom'),
  ],
  projects: [project('same-project', 'QA urejanje doma')],
  shoppingLists: [
    LocalShoppingList(
      id: 'same-list',
      title: 'QA tedenski nakup',
      createdAt: now,
      updatedAt: now,
    ),
  ],
  shoppingItems: [
    LocalShoppingItem(
      id: 'same-item',
      listId: 'same-list',
      title: 'QA jabolka',
      quantity: '2 kg',
      isChecked: false,
      createdAt: now,
      updatedAt: now,
    ),
  ],
  events: [
    LocalEvent(
      id: 'local-event',
      title: 'QA osebni dogodek',
      notes: '',
      startsAt: now,
      endsAt: null,
      projectId: null,
      createdAt: now,
      updatedAt: now,
    ),
  ],
  financeEntries: [money('local-money', 'QA osebni račun')],
);
CollaborationState sharedData({bool all = true, String? selected}) =>
    CollaborationState(
      session: sharingSession(),
      allSpacesSelected: all,
      selectedSpaceId: selected,
      scopes: [sharingScope(), secondScope],
      financePolicies: {
        sharingScopeId: const SharedFinancePolicy(
          enabled: true,
          grant: SharedFinanceGrant.write,
        ),
        secondScope.id: const SharedFinancePolicy(
          enabled: true,
          grant: SharedFinanceGrant.read,
        ),
      },
      financeSnapshotComplete: {sharingScopeId: true, secondScope.id: false},
      data: {
        sharingScopeId: SharedScopeData(
          tasks: [task('same-task', 'QA skupno opravilo')],
          projects: [project('same-project', 'QA skupna ureditev vrta')],
          events: [
            SharedEvent(
              id: 'shared-event',
              title: 'QA skupni dogodek',
              startAt: now,
              createdAt: now,
              updatedAt: now,
            ),
          ],
          shoppingLists: [
            LocalShoppingList(
              id: 'same-list',
              title: 'QA skupni nakup',
              createdAt: now,
              updatedAt: now,
            ),
          ],
          shoppingItems: [
            LocalShoppingItem(
              id: 'same-item',
              listId: 'same-list',
              title: 'QA skupno mleko',
              quantity: '1 l',
              isChecked: false,
              createdAt: now,
              updatedAt: now,
            ),
          ],
          financeEntries: [
            SharedFinanceEntry(
              id: 'shared-money',
              accountId: sharingSession().accountId,
              title: 'QA skupni račun',
              kind: FinanceEntryKind.expense,
              amountMinor: 4200,
              currency: 'EUR',
              occurredAt: now,
              createdAt: now,
              updatedAt: now,
            ),
          ],
        ),
        secondScope.id: SharedScopeData(
          tasks: [task('same-task', 'QA preveri izvajalca')],
          projects: [project('same-project', 'QA kuhinja')],
          financeEntries: [
            SharedFinanceEntry(
              id: 'other-money',
              accountId: sharingSession().accountId,
              title: 'QA nepopoln strošek',
              kind: FinanceEntryKind.expense,
              amountMinor: 900,
              currency: 'USD',
              occurredAt: now,
              createdAt: now,
              updatedAt: now,
            ),
          ],
        ),
      },
    );

class AllSpacesController extends SharingUiController {
  AllSpacesController({CollaborationState? initial})
    : super(initial: initial ?? sharedData());
  final opened = <NotificationTarget>[];
  Future<NotificationOpenResult> Function(NotificationTarget)? visibleRefresh;
  @override
  Future<NotificationOpenResult> refreshVisibleTaskTarget(
    NotificationTarget target,
  ) {
    if (visibleRefresh != null) {
      opened.add(target);
      return visibleRefresh!(target);
    }
    return openNotificationTarget(target);
  }

  @override
  Future<void> selectAllSpaces() async => replace(
    initial.session == null
        ? CollaborationState(allSpacesSelected: true)
        : sharedData(),
  );
  @override
  Future<void> selectSpace(String? id) async => replace(
    initial.session == null
        ? CollaborationState()
        : sharedData(all: false, selected: id),
  );
  @override
  Future<NotificationOpenResult> openNotificationTarget(
    NotificationTarget target,
  ) async {
    opened.add(target);
    return NotificationOpenResult(
      status: NotificationOpenStatus.offline,
      target: target,
    );
  }
}

Future<void> pumpAll(
  WidgetTester tester, {
  AllSpacesArea area = AllSpacesArea.today,
  double width = 390,
  bool dark = false,
  AllSpacesController? shared,
  WorkspaceController? personal,
  Future<void> Function(AllSpacesSource, AllSpacesArea, String?)? onSource,
}) async {
  tester.view.physicalSize = Size(width, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        organizerProvider.overrideWith(
          () => personal ?? WorkspaceController(localData()),
        ),
        collaborationProvider.overrideWith(
          () => shared ?? AllSpacesController(),
        ),
        organizerClockProvider.overrideWithValue(() => now),
      ],
      child: MaterialApp(
        locale: const Locale('sl'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: dark ? Brightness.dark : Brightness.light,
          ),
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: AllSpacesPage(
                area: area,
                onSource: onSource ?? (_, _, _) async {},
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> loadQaFonts(WidgetTester tester) async {
  await tester.runAsync(() async {
    final flutterRoot = Platform.resolvedExecutable.split('/bin/cache/').first;
    final fonts = '$flutterRoot/bin/cache/artifacts/material_fonts';
    final systemFont = File('/System/Library/Fonts/SFNS.ttf');
    final textBytes =
        await (await systemFont.exists()
                ? systemFont
                : File('$fonts/Roboto-Regular.ttf'))
            .readAsBytes();
    for (final family in [
      'CupertinoSystemText',
      'CupertinoSystemDisplay',
      'Roboto',
    ]) {
      await (FontLoader(
        family,
      )..addFont(Future.value(ByteData.sublistView(textBytes)))).load();
    }
    final icons = await File('$fonts/MaterialIcons-Regular.otf').readAsBytes();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(Future.value(ByteData.sublistView(icons)))).load();
  });
}

void main() {
  testWidgets(
    'mapped private task opens immediately and hides retained data during refresh',
    (tester) async {
      final gate = Completer<NotificationOpenResult>();
      final personal = WorkspaceController(
        localData().copyWith(
          workspaceKey: 'private:${sharingSession().partition}',
        ),
      );
      final shared = AllSpacesController(
        initial: CollaborationState(
          session: sharingSession(),
          allSpacesSelected: true,
          privateSync: const PrivateSyncState(scopeId: 'private'),
          privateRecordIds: const {'remote-task': 'same-task'},
          scopes: const [
            SharedScope(
              id: 'private',
              name: 'Zasebno',
              kind: SharedScopeKind.personal,
              role: SharedRole.owner,
            ),
          ],
        ),
      )..visibleRefresh = (_) => gate.future;
      await pumpAll(tester, shared: shared, personal: personal);
      await tester.tap(
        find.text('QA osebno opravilo z daljšim slovenskim naslovom'),
      );
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.text('Uredi opravilo'), findsOneWidget);
      expect(shared.opened.single.scopeId, 'private');
      expect(shared.opened.single.records.single.recordId, 'remote-task');
      personal.state = const AsyncLoading<OrganizerSnapshot>().copyWithPrevious(
        AsyncData(personal.snapshot),
      );
      await tester.pump();
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text(
            'QA osebno opravilo z daljšim slovenskim naslovom',
          ),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );
      personal.state = AsyncData(personal.snapshot);
      gate.complete(
        NotificationOpenResult(
          status: NotificationOpenStatus.available,
          target: shared.opened.single,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Uredi opravilo'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  for (final delayed in [true, false]) {
    testWidgets(
      'visible task opens on first frame with ${delayed ? '3s' : 'never completing'} refresh',
      (tester) async {
        final gate = Completer<NotificationOpenResult>();
        final shared = AllSpacesController()
          ..visibleRefresh = (target) => delayed
              ? Future.delayed(
                  const Duration(seconds: 3),
                  () => NotificationOpenResult(
                    status: NotificationOpenStatus.available,
                    target: target,
                  ),
                )
              : gate.future;
        await pumpAll(tester, shared: shared);
        await tester.tap(find.text('QA skupno opravilo'));
        await tester.pump(const Duration(milliseconds: 16));
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.text('Uredi opravilo'), findsOneWidget);
        expect(shared.opened, hasLength(1));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.text('Zapri'));
        await tester.pumpAndSettle();
        if (delayed) {
          await tester.pump(const Duration(seconds: 3));
        } else {
          gate.complete(
            NotificationOpenResult(
              status: NotificationOpenStatus.available,
              target: shared.opened.single,
            ),
          );
        }
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('rapid task taps create one dialog and one refresh', (
    tester,
  ) async {
    final gate = Completer<NotificationOpenResult>();
    final shared = AllSpacesController()..visibleRefresh = (_) => gate.future;
    await pumpAll(tester, shared: shared);
    final tile = tester.widget<ListTile>(
      find.ancestor(
        of: find.text('QA skupno opravilo'),
        matching: find.byType(ListTile),
      ),
    );
    tile.onTap!();
    tile.onTap!();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(shared.opened, hasLength(1));
    gate.complete(
      NotificationOpenResult(
        status: NotificationOpenStatus.offline,
        target: shared.opened.single,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Brez povezave'), findsWidgets);
  });
  for (final denial in [
    'revoked',
    'blocked',
    'archived',
    'account',
    'device',
  ]) {
    testWidgets(
      'visible task closes on $denial and late response cannot reopen it',
      (tester) async {
        final gate = Completer<NotificationOpenResult>();
        final shared = AllSpacesController()
          ..visibleRefresh = (_) => gate.future;
        await pumpAll(tester, shared: shared);
        await tester.tap(find.text('QA skupno opravilo'));
        await tester.pumpAndSettle();
        if (denial == 'account') {
          shared.switchAccount();
        } else if (denial == 'device') {
          shared.replace(
            CollaborationState(
              session: AccountSession.fromJson({
                ...sharingSession().toJson(),
                'deviceId': 'new-device',
              }),
              scopes: shared.initial.scopes,
              data: shared.initial.data,
            ),
          );
        } else {
          shared.replace(
            CollaborationState(
              session: sharingSession(),
              scopes: [
                SharedScope(
                  id: sharingScopeId,
                  name: 'Dom',
                  kind: SharedScopeKind.household,
                  role: SharedRole.owner,
                  revoked: denial == 'revoked',
                  blocked: denial == 'blocked',
                  archived: denial == 'archived',
                ),
              ],
              data: shared.initial.data,
            ),
          );
        }
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        gate.complete(
          NotificationOpenResult(
            status: NotificationOpenStatus.available,
            target: shared.opened.single,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final width in [320.0, 390.0, 1280.0]) {
    for (final dark in [false, true]) {
      testWidgets('all areas $width dark=$dark preserve source and fit', (
        tester,
      ) async {
        for (final area in AllSpacesArea.values) {
          await pumpAll(tester, area: area, width: width, dark: dark);
          expect(tester.takeException(), isNull);
          if (area == AllSpacesArea.today || area == AllSpacesArea.tasks) {
            expect(find.text('QA skupno opravilo'), findsOneWidget);
            expect(find.text('QA preveri izvajalca'), findsOneWidget);
            expect(find.textContaining('Lokalno · osebno'), findsWidgets);
            expect(find.textContaining(secondScope.name), findsWidgets);
          }
        }
      });
    }
  }
  testWidgets(
    'same ids open exact shared task without changing All selection',
    (tester) async {
      final shared = AllSpacesController();
      await pumpAll(tester, shared: shared);
      await tester.tap(find.text('QA skupno opravilo'));
      await tester.pumpAndSettle();
      expect(shared.opened.single.scopeId, sharingScopeId);
      expect(shared.opened.single.accountId, sharingSession().accountId);
      expect(shared.opened.single.records.single.recordId, 'same-task');
      expect(shared.state.value!.allSpacesSelected, isTrue);
      expect(find.text('Uredi opravilo'), findsOneWidget);
    },
  );
  testWidgets('finance exact source, incomplete status and posted totals', (
    tester,
  ) async {
    final shared = AllSpacesController();
    await pumpAll(tester, shared: shared, area: AllSpacesArea.finances);
    expect(find.text('Odhodek: 57.99 EUR'), findsOneWidget);
    expect(find.text('Odhodek: 0.00 USD'), findsNothing);
    expect(find.textContaining('Nekateri prostori'), findsOneWidget);
    await tester.ensureVisible(find.text('QA skupni račun'));
    await tester.tap(find.text('QA skupni račun'));
    await tester.pumpAndSettle();
    expect(shared.opened.single.scopeId, sharingScopeId);
    expect(shared.opened.single.records.single.type, 'financeEntry');
    expect(shared.state.value!.allSpacesSelected, isTrue);
    expect(tester.takeException(), isNull);
  });
  testWidgets('creating requires explicit concrete source choice', (
    tester,
  ) async {
    AllSpacesSource? selected;
    await pumpAll(
      tester,
      onSource: (source, _, _) async {
        selected = source;
      },
    );
    await tester.tap(find.text('Dodaj v prostor'));
    await tester.pumpAndSettle();
    expect(selected, isNull);
    expect(find.text('Izberi prostor za dodajanje'), findsOneWidget);
    await tester.tap(find.text(secondScope.name).last);
    await tester.pumpAndSettle();
    expect(selected!.scopeId, secondScope.id);
  });
  testWidgets(
    'private unsynced task stays local and closes on account change',
    (tester) async {
      final scope = SharedScope(
        id: 'private',
        name: 'Zasebno',
        kind: SharedScopeKind.personal,
        role: SharedRole.owner,
      );
      final personal = WorkspaceController(
        localData().copyWith(
          workspaceKey: 'private:${sharingSession().partition}',
        ),
      );
      final shared = AllSpacesController(
        initial: CollaborationState(
          session: sharingSession(),
          allSpacesSelected: true,
          privateSync: const PrivateSyncState(scopeId: 'private'),
          scopes: [scope],
        ),
      );
      await pumpAll(tester, shared: shared, personal: personal);
      await tester.tap(
        find.text('QA osebno opravilo z daljšim slovenskim naslovom'),
      );
      await tester.pumpAndSettle();
      expect(shared.opened, isEmpty);
      expect(find.text('Uredi opravilo'), findsOneWidget);
      await tester.tap(find.text('Uredi opravilo'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('organizer-save')), findsOneWidget);
      shared.switchAccount();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('organizer-save')), findsNothing);
      expect(
        find.text('QA osebno opravilo z daljšim slovenskim naslovom'),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );
  test('planned dates and multi-day local/shared events in Today', () {
    final tomorrow = DateTime(2026, 10, 10), yesterday = DateTime(2026, 10, 8);
    final local = localData().copyWith(
      financeEntries: [money('future', 'Future planned', plannedAt: tomorrow)],
      tasks: [
        task(
          'starttoday',
          'Starts today due tomorrow',
        ).copyWith(dueAt: tomorrow, startAt: now),
      ],
      events: [
        LocalEvent(
          id: 'ended',
          title: 'Ended at midnight',
          notes: '',
          startsAt: yesterday,
          endsAt: DateTime(2026, 10, 9),
          projectId: null,
          createdAt: now,
          updatedAt: now,
        ),
        LocalEvent(
          id: 'multi',
          title: 'Ongoing local',
          notes: '',
          startsAt: yesterday,
          endsAt: tomorrow,
          projectId: null,
          createdAt: now,
          updatedAt: now,
        ),
      ],
    );
    final shared = CollaborationState(
      session: sharingSession(),
      scopes: [sharingScope()],
      data: {
        sharingScopeId: SharedScopeData(
          events: [
            SharedEvent(
              id: 'multi',
              title: 'Ongoing shared',
              startAt: yesterday,
              endAt: tomorrow,
              createdAt: now,
              updatedAt: now,
            ),
          ],
        ),
      },
    );
    final projection = projectAllSpaces(personal: local, shared: shared);
    final rows = allSpacesRows(projection, AllSpacesArea.today, now: now);
    expect(
      rows.map((row) => row.title),
      containsAll([
        'Ongoing local',
        'Ongoing shared',
        'Starts today due tomorrow',
      ]),
    );
    expect(rows.map((row) => row.title), isNot(contains('Future planned')));
    expect(
      allSpacesRows(
        projection,
        AllSpacesArea.finances,
        now: now,
        month: DateTime(2026, 11),
      ),
      isEmpty,
    );
  });
  test(
    'posted effective payment dates differ from planned month, ongoing event spans month',
    () {
      final paid = DateTime(2026, 11, 7), plan = DateTime(2026, 9, 1);
      final posted = money(
        'paid',
        'Paid in November',
      ).copyWith(plannedAt: plan, paidAt: paid);
      final shared = CollaborationState(
        session: sharingSession(),
        scopes: [sharingScope()],
        financePolicies: {
          sharingScopeId: const SharedFinancePolicy(
            enabled: true,
            grant: SharedFinanceGrant.read,
          ),
        },
        financeSnapshotComplete: {sharingScopeId: true},
        data: {
          sharingScopeId: SharedScopeData(
            financeEntries: [
              SharedFinanceEntry(
                id: 'posted',
                accountId: sharingSession().accountId,
                title: 'Shared paid',
                kind: FinanceEntryKind.expense,
                status: SharedFinanceStatus.posted,
                amountMinor: 100,
                currency: 'EUR',
                occurredAt: now,
                plannedAt: plan,
                paidAt: paid,
                createdAt: now,
                updatedAt: now,
              ),
            ],
            events: [
              SharedEvent(
                id: 'span',
                title: 'Across months',
                startAt: DateTime(2026, 9, 30),
                endAt: DateTime(2026, 10, 2),
                createdAt: now,
                updatedAt: now,
              ),
            ],
          ),
        },
      );
      final projection = projectAllSpaces(
        personal: localData().copyWith(financeEntries: [posted], events: []),
        shared: shared,
      );
      expect(
        allSpacesRows(
          projection,
          AllSpacesArea.finances,
          now: now,
          month: DateTime(2026, 11),
        ).map((row) => row.title),
        containsAll(['Paid in November', 'Shared paid']),
      );
      expect(
        allSpacesRows(
          projection,
          AllSpacesArea.finances,
          now: now,
          month: DateTime(2026, 10),
        ),
        isEmpty,
      );
      expect(
        allSpacesRows(
          projection,
          AllSpacesArea.calendar,
          now: now,
          month: DateTime(2026, 10),
        ).map((row) => row.title),
        contains('Across months'),
      );
    },
  );
  testWidgets(
    'picker selects All without an account and source returns to personal',
    (tester) async {
      final store = MemoryOrganizerStorage()..snapshot = localData();
      await pumpOrganizer(
        tester,
        store,
        collaborationController: AllSpacesController(
          initial: CollaborationState(),
        ),
      );
      final picker = find.descendant(
        of: find.byType(OrganizerSpacePicker),
        matching: find.byType(DropdownButton<String>),
      );
      await tester.tap(picker);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Vsi').last);
      await tester.pumpAndSettle();
      expect(find.byType(AllSpacesPage), findsOneWidget);
      await tester.tap(picker);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lokalno · osebno').last);
      await tester.pumpAndSettle();
      expect(find.byType(AllSpacesPage), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  for (final width in [390.0, 1280.0]) {
    for (final theme in width == 390 ? ['light', 'dark'] : ['light']) {
      testWidgets('QA synthetic all spaces $width $theme', (tester) async {
        await loadQaFonts(tester);
        final key = GlobalKey();
        final store = MemoryOrganizerStorage()..snapshot = localData();
        await pumpOrganizer(
          tester,
          store,
          width: width,
          theme: theme,
          collaborationController: AllSpacesController(),
          repaintBoundaryKey: key,
        );
        expect(find.byType(AllSpacesPage), findsOneWidget);
        await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          image.dispose();
          final file = File(
            'build/qa/all-spaces-inbox/all-${width.toInt()}-$theme.png',
          );
          file.parent.createSync(recursive: true);
          file.writeAsBytesSync(bytes!.buffer.asUint8List());
        });
        if (width < 900) {
          await mobileTab(tester, 'Finance');
        } else {
          await tester.tap(find.widgetWithText(ListTile, 'Finance'));
          await tester.pumpAndSettle();
        }
        await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final financeImage = await boundary.toImage(pixelRatio: 1);
          final financeBytes = await financeImage.toByteData(
            format: ui.ImageByteFormat.png,
          );
          financeImage.dispose();
          File(
            'build/qa/all-spaces-inbox/finance-${width.toInt()}-$theme.png',
          ).writeAsBytesSync(financeBytes!.buffer.asUint8List());
        });
        expect(tester.takeException(), isNull);
      });
    }
  }
}
