import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/l10n/app_localizations.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'package:kanban/organizer/presentation/finance/shared_finance_workspace.dart';
import 'package:kanban/organizer/presentation/finance/shared_finance_ledger.dart';
import 'package:kanban/organizer/presentation/finance/shared_finance_actions.dart';
import 'package:kanban/organizer/presentation/shared/sharing_workspace.dart';
import 'package:kanban/organizer/presentation/shared/collaboration_actions.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';
import 'package:kanban/organizer/state/linked_payments_provider.dart';
import 'sharing_ui_fixture.dart';
import 'all_spaces_ui_test.dart' show loadQaFonts;

const organization = SharedScope(
  id: 'org',
  name: 'TriparNA',
  kind: SharedScopeKind.organization,
  role: SharedRole.owner,
  accessPolicyVersion: 3,
);
const project = SharedScope(
  id: 'project',
  name: 'Dogodek',
  kind: SharedScopeKind.project,
  role: SharedRole.member,
  parentScopeId: 'org',
  accessPolicyVersion: 3,
);
const policy = SharedFinancePolicy(
  enabled: true,
  grant: SharedFinanceGrant.write,
  revision: 1,
  managedByOrganizationPolicy: true,
  organizationFinanceComplete: true,
  organizationFinanceScopeIds: ['project'],
  organizationFinanceSequences: {'org': 1, 'project': 1},
);

class FinanceController extends SharingUiController {
  FinanceController(CollaborationState initial) : super(initial: initial);
  SharedFinanceEntry? updatedEntry;
  @override
  Future<void> updateFinanceEntry(
    String scopeId,
    SharedFinanceEntry draft,
  ) async {
    updatedEntry = draft;
  }

  TaskCostDraft? savedCost;
  @override
  Future<void> saveTaskWithCost(
    String scopeId,
    LocalTask task, {
    bool isNew = false,
    TaskCostDraft? cost,
    bool removeCost = false,
    int? expectedFinanceRevision,
  }) async {
    savedCost = cost;
  }

  final accountsCreated = <(String, String)>[];
  final entriesCreated = <(String, String, String?, FinanceEntryKind, int)>[];
  @override
  Future<void> refreshFinanceAccountChoices(String scopeId) async {}
  @override
  Future<String> createFinanceAccount({
    required String scopeId,
    required String name,
    required String currency,
    int openingBalanceMinor = 0,
    String? ownerAccountId,
  }) async {
    accountsCreated.add((scopeId, name));
    return 'created';
  }

  @override
  Future<String> createFinanceEntry({
    required String scopeId,
    required String accountId,
    String? accountScopeId,
    String? projectId,
    required FinanceEntryKind kind,
    SharedFinanceStatus status = SharedFinanceStatus.posted,
    required int amountMinor,
    required String currency,
    required String title,
    String notes = '',
    String category = '',
    String? payerAccountId,
    String? recipientAccountId,
    required DateTime occurredAt,
  }) async {
    entriesCreated.add((scopeId, accountId, accountScopeId, kind, amountMinor));
    return 'created';
  }
}

SharedFinanceAccount account(String id, String name, {int opening = 100000}) =>
    SharedFinanceAccount(
      id: id,
      name: name,
      currency: 'EUR',
      openingBalanceMinor: opening,
      createdAt: sharingTestNow,
      updatedAt: sharingTestNow,
    );
SharedFinanceEntry entry(
  String id,
  String title,
  int amount, {
  String? accountScopeId,
  String accountId = 'bank',
}) => SharedFinanceEntry(
  id: id,
  accountId: accountId,
  accountScopeId: accountScopeId,
  kind: FinanceEntryKind.expense,
  currency: 'EUR',
  amountMinor: amount,
  title: title,
  occurredAt: sharingTestNow,
  createdAt: sharingTestNow,
  updatedAt: sharingTestNow,
);
CollaborationState fixture({
  bool projectOnly = false,
  bool modern = true,
  bool complete = true,
  bool empty = false,
}) => CollaborationState(
  session: sharingSession(),
  financeSupported: true,
  organizationFinanceSupported: modern,
  financeContractVersion: modern ? 3 : 2,
  selectedSpaceId: projectOnly ? project.id : organization.id,
  scopes: [if (!projectOnly) organization, if (!empty) project],
  financePolicies: {organization.id: policy, project.id: policy},
  financeSnapshotComplete: {organization.id: true, project.id: complete},
  financeSnapshotSequences: {organization.id: 1, project.id: 1},
  financeAccountChoices: {
    project.id: const [
      SharedFinanceAccountChoice(
        scopeId: 'org',
        id: 'bank',
        name: 'TRR prostora',
        currency: 'EUR',
      ),
    ],
  },
  data: {
    if (!projectOnly)
      organization.id: SharedScopeData(
        financeAccounts: empty ? [] : [account('bank', 'TRR prostora')],
        financeEntries: empty
            ? []
            : [entry('general', 'Splošen strošek', 5000)],
      ),
    if (!empty)
      project.id: SharedScopeData(
        financeEntries: [
          entry(
            'project-cost',
            'Strošek dogodka',
            30000,
            accountScopeId: 'org',
          ),
        ],
      ),
  },
);

final financeCaptureKey = GlobalKey();
Future<void> captureFinance(WidgetTester tester, String name) async {
  await tester.runAsync(() async {
    final image = await tester
        .renderObject<RenderRepaintBoundary>(find.byKey(financeCaptureKey))
        .toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('build/qa/organization-finance/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

Future<void> pumpFinance(
  WidgetTester tester,
  FinanceController controller, {
  String scopeId = 'org',
  double width = 390,
  double scale = 1,
  bool route = false,
  Widget Function(BuildContext, WidgetRef, CollaborationState)? content,
}) async {
  tester.view.physicalSize = Size(width, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await loadQaFonts(tester);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        collaborationProvider.overrideWith(() => controller),
        linkedPaymentsProvider.overrideWith(
          (ref, key) async => PaymentSnapshot(fresh: true),
        ),
      ],
      child: MaterialApp(
        locale: const Locale('sl'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => RepaintBoundary(
          key: financeCaptureKey,
          child: MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            child: Consumer(
              builder: (context, ref, _) {
                final state = ref.watch(collaborationProvider).valueOrNull;
                if (state == null) return const SizedBox.shrink();
                if (content != null) return content(context, ref, state);
                return route
                    ? SharingWorkspace(
                        view: SharingView.finances,
                        selectedScopeId: scopeId,
                        onScopeSelected: (_) {},
                        onConnect: () {},
                      )
                    : SharedFinanceWorkspace(
                        scope: state.scopes.firstWhere((s) => s.id == scopeId),
                        state: state,
                      );
              },
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder.first);
  await tester.pumpAndSettle();
  await tester.tap(finder.first);
  await tester.pumpAndSettle();
}

Future<void> fillEntry(WidgetTester tester, {bool income = false}) async {
  await tester.enterText(
    find.byKey(const ValueKey('sharing-title')),
    'Nov zapis',
  );
  await tester.enterText(find.byKey(const ValueKey('sharing-amount')), '12,00');
  if (income) {
    await tap(tester, find.byKey(const ValueKey('sharing-kind')));
    await tap(tester, find.text('Prihodek').last);
  }
  await tap(tester, find.byKey(const ValueKey('sharing-submit')));
}

void main() {
  testWidgets(
    'empty organization opens real account form directly without target loop',
    (tester) async {
      final controller = FinanceController(fixture(empty: true));
      await pumpFinance(tester, controller, route: true);
      expect(find.byType(SharedFinanceWorkspace), findsOneWidget);
      expect(find.text('Dodaj v prostor'), findsNothing);
      await tap(
        tester,
        find.descendant(
          of: find.byType(SharedFinanceLedger),
          matching: find.text('Dodaj račun'),
        ),
      );
      await tester.enterText(
        find.byKey(const ValueKey('sharing-name')),
        'Novi TRR',
      );
      await tap(tester, find.byKey(const ValueKey('sharing-submit')));
      expect(controller.accountsCreated, [('org', 'Novi TRR')]);
      expect(tester.takeException(), isNull);
    },
  );
  for (final width in [320.0, 1280.0]) {
    testWidgets(
      'parent includes canonical child once and project filter hides general cost $width',
      (tester) async {
        await pumpFinance(
          tester,
          FinanceController(fixture()),
          width: width,
          scale: width == 320 ? 2 : 1,
        );
        expect(find.text('Strošek dogodka'), findsOneWidget);
        expect(find.text('Splošen strošek'), findsOneWidget);
        expect(find.text('Odhodek: 350.00 EUR'), findsOneWidget);
        expect(find.text('Skupno stanje: 650.00 EUR'), findsOneWidget);
        final filter = find.byKey(const ValueKey('finance-filter-project-'));
        await tap(tester, filter);
        await tap(tester, find.text('Dogodek').last);
        expect(find.text('Strošek dogodka'), findsOneWidget);
        expect(find.text('Splošen strošek'), findsNothing);
        expect(find.textContaining('Celotno stanje:'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'project-only member sees parent choice and own movement without parent balance',
    (tester) async {
      final controller = FinanceController(fixture(projectOnly: true));
      await pumpFinance(tester, controller, scopeId: project.id);
      await captureFinance(tester, 'project-only-390');
      expect(find.text('Strošek dogodka'), findsOneWidget);
      expect(find.text('Splošen strošek'), findsNothing);
      expect(find.textContaining('1.000'), findsNothing);
      expect(find.text('Celoten finančni prostor'), findsNothing);
      await tap(tester, find.text('Dodaj zapis'));
      await fillEntry(tester);
      expect(controller.entriesCreated, [
        ('project', 'bank', 'org', FinanceEntryKind.expense, 1200),
      ]);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'parent add routes selected project income to its canonical scope',
    (tester) async {
      final controller = FinanceController(fixture());
      await pumpFinance(tester, controller);
      await tap(tester, find.text('Dodaj zapis'));
      await tap(tester, find.text('Dogodek').last);
      await fillEntry(tester, income: true);
      expect(controller.entriesCreated, [
        ('project', 'bank', 'org', FinanceEntryKind.income, 1200),
      ]);
    },
  );
  testWidgets('parent general manual expense remains in parent scope', (
    tester,
  ) async {
    final controller = FinanceController(fixture());
    await pumpFinance(tester, controller);
    await captureFinance(tester, 'parent-390');
    await tap(tester, find.text('Dodaj zapis'));
    await tap(tester, find.text('TriparNA · Brez projekta'));
    await fillEntry(tester);
    expect(controller.entriesCreated, [
      ('org', 'bank', null, FinanceEntryKind.expense, 1200),
    ]);
  });
  testWidgets(
    'project account management requires accessible parent permission',
    (tester) async {
      final controller = FinanceController(fixture(projectOnly: true));
      await pumpFinance(tester, controller, scopeId: project.id);
      await tap(tester, find.text('Računi prostora'));
      expect(
        find.textContaining('Nov račun ustvarite v nadrejenem prostoru.'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('sharing-name')), findsNothing);
      expect(controller.accountsCreated, isEmpty);
    },
  );
  testWidgets('missing child snapshot hides aggregate balance', (tester) async {
    await pumpFinance(tester, FinanceController(fixture(complete: false)));
    expect(
      find.textContaining('Pregled projektnih financ še ni popoln.'),
      findsOneWidget,
    );
    expect(find.textContaining('Celotno stanje:'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'older server explains parent linkage and preserves legacy project ledger',
    (tester) async {
      final initial = fixture(projectOnly: true, modern: false);
      final controller = FinanceController(
        CollaborationState(
          session: initial.session,
          scopes: initial.scopes,
          financeSupported: true,
          financeContractVersion: 2,
          financePolicies: initial.financePolicies,
          financeSnapshotComplete: initial.financeSnapshotComplete,
          data: {
            project.id: SharedScopeData(
              financeAccounts: [account('old-bank', 'Stari račun')],
              financeEntries: [
                entry('old-cost', 'Stari strošek', 500, accountId: 'old-bank'),
              ],
            ),
          },
        ),
      );
      await pumpFinance(tester, controller, scopeId: project.id);
      expect(
        find.textContaining('potrebna nadgradnja strežnika'),
        findsOneWidget,
      );
      expect(find.textContaining('Obstoječi projektni račun'), findsWidgets);
      expect(find.text('Stari strošek'), findsOneWidget);
      expect(find.textContaining('Celotno stanje:'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'account and project filters combine without inventing a project balance',
    (tester) async {
      final state = fixture();
      final controller = FinanceController(
        CollaborationState(
          session: state.session,
          scopes: state.scopes,
          financeSupported: true,
          organizationFinanceSupported: true,
          financeContractVersion: 3,
          financePolicies: state.financePolicies,
          financeSnapshotComplete: state.financeSnapshotComplete,
          financeSnapshotSequences: state.financeSnapshotSequences,
          financeAccountChoices: state.financeAccountChoices,
          data: {
            organization.id: SharedScopeData(
              financeAccounts: [
                account('bank', 'TRR prostora'),
                account('cash', 'Gotovina'),
              ],
              financeEntries: [
                entry(
                  'cash-cost',
                  'Gotovinski strošek',
                  1000,
                  accountId: 'cash',
                ),
              ],
            ),
            project.id: state.dataForScope(project.id),
          },
        ),
      );
      await pumpFinance(tester, controller);
      await tap(tester, find.byKey(const ValueKey('finance-filter-account-')));
      await tap(tester, find.text('Gotovina').last);
      expect(find.text('Gotovinski strošek'), findsOneWidget);
      expect(find.text('Strošek dogodka'), findsNothing);
      await tap(tester, find.byKey(const ValueKey('finance-filter-project-')));
      await tap(tester, find.text('Dogodek').last);
      expect(find.text('Gotovinski strošek'), findsNothing);
      expect(find.text('Strošek dogodka'), findsNothing);
      expect(find.textContaining('Celotno stanje:'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('project can create an account only in permitted parent', (
    tester,
  ) async {
    final controller = FinanceController(fixture());
    await pumpFinance(tester, controller, scopeId: project.id);
    await tap(tester, find.text('Računi prostora'));
    await tester.enterText(
      find.byKey(const ValueKey('sharing-name')),
      'Račun organizacije',
    );
    await tap(tester, find.byKey(const ValueKey('sharing-submit')));
    expect(controller.accountsCreated, [('org', 'Račun organizacije')]);
  });
  testWidgets('changing account closes project entry form before it can save', (
    tester,
  ) async {
    final controller = FinanceController(fixture(projectOnly: true));
    await pumpFinance(tester, controller, scopeId: project.id);
    await tap(tester, find.text('Dodaj zapis'));
    await tester.enterText(
      find.byKey(const ValueKey('sharing-title')),
      'Ne shrani',
    );
    controller.replace(
      CollaborationState(
        session: sharingSession(second: true),
        scopes: const [project],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('sharing-submit')), findsNothing);
    expect(controller.entriesCreated, isEmpty);
  });
  testWidgets(
    'standalone legacy project retains its same-scope account creation',
    (tester) async {
      const standalone = SharedScope(
        id: 'standalone',
        name: 'Samostojen projekt',
        kind: SharedScopeKind.project,
        role: SharedRole.owner,
      );
      final controller = FinanceController(
        CollaborationState(
          session: sharingSession(),
          scopes: const [standalone],
          financeSupported: true,
          financePolicies: {standalone.id: policy},
          financeSnapshotComplete: {standalone.id: true},
        ),
      );
      await pumpFinance(tester, controller, scopeId: standalone.id);
      await tap(
        tester,
        find.descendant(
          of: find.byType(SharedFinanceLedger),
          matching: find.text('Dodaj račun'),
        ),
      );
      await tester.enterText(
        find.byKey(const ValueKey('sharing-name')),
        'Samostojen račun',
      );
      await tap(tester, find.byKey(const ValueKey('sharing-submit')));
      expect(controller.accountsCreated, [('standalone', 'Samostojen račun')]);
    },
  );
  testWidgets(
    'editing linked task cost preserves the selected safe parent account',
    (tester) async {
      final task = LocalTask(
        id: 'task',
        projectId: null,
        title: 'Priprava dogodka',
        notes: '',
        dueAt: null,
        isCompleted: false,
        createdAt: sharingTestNow,
        updatedAt: sharingTestNow,
      );
      final state = fixture(projectOnly: true);
      final controller = FinanceController(
        CollaborationState(
          session: state.session,
          scopes: state.scopes,
          financeSupported: true,
          organizationFinanceSupported: true,
          financeContractVersion: 3,
          recordContractVersion: 3,
          financePolicies: state.financePolicies,
          financeSnapshotComplete: state.financeSnapshotComplete,
          financeSnapshotSequences: state.financeSnapshotSequences,
          financeAccountChoices: state.financeAccountChoices,
          data: {
            project.id: SharedScopeData(
              tasks: [task],
              financeEntries: [
                entry(
                  'task-cost',
                  'Cena priprave',
                  30000,
                  accountScopeId: 'org',
                ).copyWith(taskId: task.id, ledgerAccountId: 'bank'),
              ],
            ),
          },
        ),
      );
      await pumpFinance(
        tester,
        controller,
        scopeId: project.id,
        content: (context, ref, current) => TextButton(
          onPressed: () => CollaborationActions(
            context,
            ref,
            project,
            current.dataForScope(project.id),
          ).task(task: task),
          child: const Text('Uredi opravilo'),
        ),
      );
      await tap(tester, find.text('Uredi opravilo'));
      expect(
        find.byKey(const ValueKey('task-cost-account-EUR')),
        findsOneWidget,
      );
      expect(
        find.text('TRR prostora · Račun nadrejenega prostora'),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const ValueKey('organizer-title-field')),
        'Posodobljena priprava',
      );
      await tap(tester, find.byKey(const ValueKey('organizer-save')));
      expect(controller.savedCost?.ledgerAccountId, 'bank');
      expect(controller.savedCost?.accountScopeId, 'org');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'new project task cost selects a safe parent account without a parent finance snapshot',
    (tester) async {
      final state = fixture(projectOnly: true);
      final controller = FinanceController(
        CollaborationState(
          session: state.session,
          scopes: state.scopes,
          financeSupported: true,
          organizationFinanceSupported: true,
          financeContractVersion: 3,
          recordContractVersion: 3,
          financePolicies: state.financePolicies,
          financeSnapshotComplete: state.financeSnapshotComplete,
          financeSnapshotSequences: state.financeSnapshotSequences,
          financeAccountChoices: state.financeAccountChoices,
          data: {project.id: SharedScopeData()},
        ),
      );
      await pumpFinance(
        tester,
        controller,
        scopeId: project.id,
        content: (context, ref, current) => TextButton(
          onPressed: () => CollaborationActions(
            context,
            ref,
            project,
            current.dataForScope(project.id),
          ).task(),
          child: const Text('Novo opravilo'),
        ),
      );
      await tap(tester, find.text('Novo opravilo'));
      await tester.enterText(
        find.byKey(const ValueKey('organizer-title-field')),
        'Novo opravilo s stroškom',
      );
      await tap(tester, find.text('Strošek opravila'));
      await tap(tester, find.text('Dodaj strošek'));
      await tester.enterText(
        find.byKey(const ValueKey('task-cost-amount')),
        '25,00',
      );
      await tap(tester, find.byKey(const ValueKey('task-cost-account-EUR')));
      await tap(
        tester,
        find.text('TRR prostora · Račun nadrejenega prostora').last,
      );
      await tap(tester, find.byKey(const ValueKey('organizer-save')));
      expect(controller.savedCost?.ledgerAccountId, 'bank');
      expect(controller.savedCost?.accountScopeId, 'org');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'editing a historical parent-linked entry keeps its account when choices are unavailable',
    (tester) async {
      final old = entry(
        'historical',
        'Pretekli projektni zapis',
        30000,
        accountScopeId: 'org',
      );
      final controller = FinanceController(
        CollaborationState(
          session: sharingSession(),
          scopes: const [project],
          financeSupported: true,
          organizationFinanceSupported: true,
          financeContractVersion: 3,
          financePolicies: {project.id: policy},
          financeSnapshotComplete: {project.id: true},
          data: {
            project.id: SharedScopeData(financeEntries: [old]),
          },
        ),
      );
      await pumpFinance(
        tester,
        controller,
        scopeId: project.id,
        content: (context, ref, current) => TextButton(
          onPressed: () =>
              SharedFinanceActions(context, ref, project, current).entry(old),
          child: const Text('Uredi zgodovino'),
        ),
      );
      await tap(tester, find.text('Uredi zgodovino'));
      expect(find.byKey(const ValueKey('sharing-account')), findsOneWidget);
      await tap(tester, find.byKey(const ValueKey('sharing-submit')));
      expect(controller.updatedEntry?.accountId, 'bank');
      expect(controller.updatedEntry?.accountScopeId, 'org');
      expect(tester.takeException(), isNull);
    },
  );
}
