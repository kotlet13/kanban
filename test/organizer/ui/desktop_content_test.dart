import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/l10n/app_localizations.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'package:kanban/organizer/domain/shared_finance_models.dart';
import 'package:kanban/organizer/presentation/desktop/desktop_finance_table.dart';
import 'package:kanban/organizer/presentation/finance/shared_finance_ledger.dart';
import 'package:kanban/organizer/presentation/planning/utrip_overview.dart';
import 'package:kanban/organizer/presentation/projects_page.dart';
import 'package:kanban/organizer/presentation/collection_actions.dart';
import 'organizer_ui_test.dart' show MemoryOrganizerStorage;
import 'finance_pending_ledger_ui_test.dart' show pumpLedger;
import 'utrip_overview_test.dart' show event, now, projection;

Future<void> pumpContent(
  WidgetTester tester,
  Widget child, {
  double width = 1000,
  double scale = 1,
  TargetPlatform platform = TargetPlatform.macOS,
}) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: ThemeData(platform: platform),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            child: Padding(padding: const EdgeInsets.all(20), child: child),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

DesktopFinanceRow row(
  String id, {
  String currency = 'EUR',
  int amount = 100,
  VoidCallback? onOpen,
}) => DesktopFinanceRow(
  id: id,
  title: id,
  date: DateTime(2026, 10, 12),
  typeStatus: 'Expense · Posted',
  amount: '$amount $currency',
  amountMinor: amount,
  currency: currency,
  account: 'Current account',
  onOpen: onOpen,
);

List<String> rowOrder(WidgetTester tester) => tester
    .widget<DataTable>(find.byKey(const ValueKey('desktop-finance-table')))
    .rows
    .map((row) => (row.key! as ValueKey<String>).value)
    .toList();

class _ProjectActions implements OrganizerCollectionActions {
  final projects = <LocalProject?>[];
  @override
  Future<void> project([
    LocalProject? project,
    ProjectArea area = ProjectArea.personal,
  ]) async => projects.add(project);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets(
    'desktop amount sorting groups currencies and preserves row identity',
    (tester) async {
      await pumpContent(
        tester,
        DesktopFinanceTable(
          rows: [
            row('Z', currency: 'USD', amount: 1),
            row('A', amount: 500),
            row('B', amount: 200),
          ],
        ),
      );
      await tester.tap(find.text('Amount'));
      await tester.pumpAndSettle();
      expect(rowOrder(tester), [
        'desktop-finance-row-B',
        'desktop-finance-row-A',
        'desktop-finance-row-Z',
      ]);
      await tester.tap(find.text('Amount'));
      await tester.pumpAndSettle();
      expect(rowOrder(tester), [
        'desktop-finance-row-Z',
        'desktop-finance-row-A',
        'desktop-finance-row-B',
      ]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'desktop title can activate with keyboard and right click resolves current authorization',
    (tester) async {
      var calls = 0;
      final mutable = ValueNotifier(true);
      addTearDown(mutable.dispose);
      await pumpContent(
        tester,
        ValueListenableBuilder<bool>(
          valueListenable: mutable,
          builder: (context, enabled, _) => DesktopFinanceTable(
            rows: [
              row('Keyboard entry', onOpen: enabled ? () => calls++ : null),
            ],
          ),
        ),
      );
      final button = find.byKey(
        const ValueKey('desktop-finance-open-Keyboard entry'),
      );
      final buttonContext = tester.element(find.text('Keyboard entry'));
      final focus = Focus.of(buttonContext);
      focus.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(calls, 1);
      await tester.tap(button, buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      expect(find.byType(PopupMenuItem<bool>), findsOneWidget);
      mutable.value = false;
      await tester.pump();
      await tester.tap(find.byType(PopupMenuItem<bool>));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(tester.takeException(), isNull);
    },
  );

  for (final platform in [
    TargetPlatform.macOS,
    TargetPlatform.windows,
    TargetPlatform.linux,
  ]) {
    testWidgets(
      'native $platform finance stays scrollable at narrow width and 2x text',
      (tester) async {
        await pumpContent(
          tester,
          DesktopFinanceTable(
            rows: [row('Long financial entry with a source', onOpen: () {})],
          ),
          width: 460,
          scale: 2,
          platform: platform,
        );
        expect(
          find.byKey(const ValueKey('desktop-finance-table')),
          findsOneWidget,
        );
        final horizontal = find.byWidgetPredicate(
          (widget) =>
              widget is SingleChildScrollView &&
              widget.scrollDirection == Axis.horizontal,
        );
        await tester.drag(horizontal, const Offset(-600, 0));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'read-only shared desktop ledger exposes audit but no entry editing and no invented balance',
    (tester) async {
      var edited = 0;
      final audit = <String>[];
      final date = DateTime(2026, 10, 12);
      await pumpContent(
        tester,
        SharedFinanceLedger(
          scopeName: 'Household',
          accounts: [
            SharedFinanceAccount(
              id: 'account',
              createdAt: date,
              updatedAt: date,
              name: 'Bank',
              currency: 'EUR',
              openingBalanceMinor: null,
            ),
          ],
          entries: [
            SharedFinanceEntry(
              id: 'entry',
              accountId: 'account',
              kind: FinanceEntryKind.expense,
              amountMinor: 1234,
              currency: 'EUR',
              title: 'Read-only payment',
              occurredAt: date,
              createdAt: date,
              updatedAt: date,
            ),
          ],
          transfers: const [],
          people: const [],
          canWrite: false,
          onAccount: (_) => edited++,
          onEntry: (_) => edited++,
          onTransfer: (_) => edited++,
          onAudit: audit.add,
        ),
        width: 500,
        scale: 2,
      );
      expect(
        find.byKey(const ValueKey('desktop-finance-table')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('desktop-finance-open-entry')),
        findsNothing,
      );
      expect(find.text('Total balance'), findsNothing);
      final auditButton = find.byTooltip('Change history').first;
      await tester.ensureVisible(auditButton);
      await tester.tap(auditButton);
      await tester.pumpAndSettle();
      expect(edited, 0);
      expect(audit, ['account']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('desktop overview exposes five real events, mobile keeps three', (
    tester,
  ) async {
    final snapshot = projection(
      OrganizerSnapshot(
        events: [for (var i = 0; i < 6; i++) event('Today $i')],
      ),
    );
    await pumpContent(
      tester,
      OrganizerUtripOverview(snapshot: snapshot, now: now),
    );
    expect(find.text('Today 4'), findsOneWidget);
    expect(find.text('Today 5'), findsNothing);
    final first = tester.getTopLeft(find.text('Today 0'));
    final projects = tester.getTopLeft(find.text('Projects in progress'));
    expect(projects.dx, greaterThan(first.dx));
    await pumpContent(
      tester,
      OrganizerUtripOverview(snapshot: snapshot, now: now),
      scale: 2,
    );
    expect(
      tester.getTopLeft(find.text('Projects in progress')).dy,
      greaterThan(tester.getTopLeft(find.text('Today 4')).dy),
    );
    expect(tester.takeException(), isNull);
    await pumpContent(
      tester,
      OrganizerUtripOverview(snapshot: snapshot, now: now),
      platform: TargetPlatform.android,
    );
    expect(find.text('Today 2'), findsOneWidget);
    expect(find.text('Today 3'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'desktop personal row edits and persists the exact finance record through existing action',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final date = DateTime(2026, 10, 12);
      final storage = MemoryOrganizerStorage()
        ..snapshot = OrganizerSnapshot(
          financeEntries: [
            FinanceEntry(
              id: 'exact-finance-id',
              title: 'Desktop groceries',
              amountMinor: 1234,
              currency: 'EUR',
              kind: FinanceEntryKind.expense,
              occurredAt: date,
              projectId: null,
              notes: 'Preserve notes',
              createdAt: date,
              updatedAt: date,
            ),
          ],
        );
      await pumpLedger(
        tester,
        storage: () async => storage,
        clock: date,
        width: 600,
      );
      final button = find.byKey(
        const ValueKey('desktop-finance-open-exact-finance-id'),
      );
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('organizer-title-field')),
        'Edited groceries',
      );
      await tester.tap(find.byKey(const ValueKey('organizer-save')));
      await tester.pumpAndSettle();
      expect(storage.snapshot.financeEntries.single.id, 'exact-finance-id');
      expect(storage.snapshot.financeEntries.single.title, 'Edited groceries');
      expect(storage.snapshot.financeEntries.single.notes, 'Preserve notes');
      expect(storage.snapshot.financeEntries.single.amountMinor, 1234);
      expect(tester.takeException(), isNull);
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    'desktop projects select exact record and adapt split detail to narrow window at 2x',
    (tester) async {
      final date = DateTime(2026, 10, 12);
      final project = LocalProject(
        id: 'selected-project',
        title: 'Desk project',
        description: 'Existing description',
        createdAt: date,
        updatedAt: date,
      );
      final selected = ValueNotifier<String?>(null);
      addTearDown(selected.dispose);
      final actions = _ProjectActions();
      Widget page() => ValueListenableBuilder<String?>(
        valueListenable: selected,
        builder: (context, value, _) => OrganizerProjectsPage(
          snapshot: OrganizerSnapshot(projects: [project]),
          actions: actions,
          selectedId: value,
          onSelection: (id) => selected.value = id,
        ),
      );
      await pumpContent(tester, page(), width: 1100);
      await tester.tap(
        find.byKey(const ValueKey('desktop-project-selected-project')),
      );
      await tester.pumpAndSettle();
      expect(selected.value, project.id);
      expect(
        find.byKey(const ValueKey('desktop-project-selected-project')),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Edit project'));
      expect(actions.projects.single, same(project));
      await pumpContent(tester, page(), width: 500, scale: 2);
      expect(
        find.byKey(const ValueKey('desktop-project-selected-project')),
        findsNothing,
      );
      expect(find.text('Desk project'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Projects'));
      await tester.pumpAndSettle();
      expect(selected.value, isNull);
      expect(
        find.byKey(const ValueKey('desktop-project-selected-project')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'desktop undated planned finance confirms same record with actual amount',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final date = DateTime(2026, 10, 12);
      final storage = MemoryOrganizerStorage()
        ..snapshot = OrganizerSnapshot(
          financeEntries: [
            FinanceEntry(
              id: 'desktop-undated',
              title: 'Undated estimate',
              amountMinor: 1000,
              currency: 'EUR',
              kind: FinanceEntryKind.expense,
              status: FinanceEntryStatus.planned,
              occurredAt: date,
              projectId: null,
              notes: 'Keep estimate note',
              createdAt: date,
              updatedAt: date,
            ),
          ],
        );
      await pumpLedger(
        tester,
        storage: () async => storage,
        clock: date,
        width: 600,
      );
      final button = find.byKey(
        const ValueKey('desktop-finance-open-desktop-undated'),
      );
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('sharing-actual-amount')),
        '12.50',
      );
      await tester.tap(find.byKey(const ValueKey('sharing-submit')));
      await tester.pumpAndSettle();
      final saved = storage.snapshot.financeEntries.single;
      expect(saved.id, 'desktop-undated');
      expect(saved.amountMinor, 1250);
      expect(saved.status, FinanceEntryStatus.posted);
      expect(saved.notes, 'Keep estimate note');
      expect(saved.paidAt!.isAtSameMomentAs(date), isTrue);
      expect(tester.takeException(), isNull);
      debugDefaultTargetPlatformOverride = null;
    },
  );
}
