import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/l10n/app_localizations.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'package:kanban/organizer/presentation/finance/finance_entry_editing.dart';
import 'package:kanban/organizer/presentation/finance/finance_planning_panel.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';
import 'package:kanban/organizer/state/organizer_provider.dart';

import 'sharing_ui_fixture.dart';

final _now = DateTime.utc(2026, 10, 18);
final _bank = LocalFinanceAccount(
  id: 'bank',
  name: 'Ledger',
  currency: 'EUR',
  openingBalanceMinor: 6789,
  createdAt: _now,
  updatedAt: _now,
);
final _rule = FinanceRecurrenceRule(
  id: 'rule',
  title: 'Future rule',
  kind: FinanceRecurrenceKind.expense,
  currency: 'EUR',
  ledgerAccountId: 'bank',
  estimatedAmountMinor: 123,
  startYear: 2027,
  startMonth: 9,
  monthDay: 20,
  active: false,
  createdAt: _now,
  updatedAt: _now,
);
final _entry = FinanceEntry(
  notes: '',
  projectId: null,
  id: 'entry',
  title: 'Future occurrence',
  amountMinor: 123,
  currency: 'EUR',
  kind: FinanceEntryKind.expense,
  status: FinanceEntryStatus.planned,
  occurredAt: DateTime.utc(2027, 9, 20),
  ledgerAccountId: 'bank',
  recurrenceRuleId: 'rule',
  occurrenceKey: '2027-09',
  createdAt: _now,
  updatedAt: _now,
);

class _Organizer extends OrganizerController {
  _Organizer(this.snapshot);
  final OrganizerSnapshot snapshot;
  @override
  Future<OrganizerSnapshot> build() async => snapshot;
}

Future<void> _pump(
  WidgetTester tester,
  int version, {
  bool private = false,
  bool write = true,
  bool complete = true,
}) async {
  final session = sharingSession();
  final snapshot = OrganizerSnapshot(
    workspaceKey: private
        ? 'private:${session.partition}'
        : 'shared:${session.partition}:$sharingScopeId',
    financeAccounts: [_bank],
    financeRecurrenceRules: [_rule],
    financeEntries: [_entry],
  );
  final controller = SharingUiController(
    initial: CollaborationState(
      session: session,
      scopes: [sharingScope()],
      financeContractVersion: version,
      financeSupported: true,
      privateSync: PrivateSyncState(
        enabled: private,
        scopeId: sharingScopeId,
        partition: session.partition,
      ),
      privateRecordIds: private
          ? {'bank': 'bank', 'rule': 'rule', 'entry': 'entry'}
          : {},
      financeSnapshotComplete: {sharingScopeId: complete},
      financePolicies: {
        sharingScopeId: SharedFinancePolicy(
          enabled: true,
          grant: write ? SharedFinanceGrant.write : SharedFinanceGrant.read,
          revision: 1,
        ),
      },
    ),
  );
  final infrastructure = await sharingUiInfrastructureOverrides(
    tester,
    controller,
  );
  tester.view.physicalSize = const Size(1280, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...infrastructure,
        collaborationProvider.overrideWith(() => controller),
        organizerProvider.overrideWith(() => _Organizer(snapshot)),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                FinancePlanningPanel(
                  snapshot: snapshot,
                  sharedScopeId: private ? null : sharingScopeId,
                ),
                Consumer(
                  builder: (context, ref, child) {
                    ref.watch(organizerProvider);
                    return TextButton(
                      onPressed:
                          canConfirmPersonalFinanceEntry(
                            context,
                            ref,
                            snapshot,
                            _entry,
                          )
                          ? () {}
                          : null,
                      child: const Text('Confirm occurrence'),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void _expectControls(WidgetTester tester, bool enabled) {
  final add = find.widgetWithText(TextButton, 'Add monthly rule');
  expect(add, findsOneWidget);
  expect(tester.widget<TextButton>(add).onPressed != null, enabled);
  for (final title in ['Ledger', 'Future rule']) {
    final tile = find
        .ancestor(of: find.text(title).first, matching: find.byType(ListTile))
        .first;
    expect(tester.widget<ListTile>(tile).onTap != null, enabled);
  }
}

void main() {
  for (final version in [2, 3, 1, 4]) {
    testWidgets(
      'shared contract$version planning controls retain supported-version guard',
      (tester) async {
        await _pump(tester, version);
        _expectControls(tester, version == 2 || version == 3);
      },
    );
    testWidgets(
      'private contract$version planning and confirmation retain supported-version guard',
      (tester) async {
        await _pump(tester, version, private: true);
        final enabled = version == 2 || version == 3;
        _expectControls(tester, enabled);
        expect(
          tester
                  .widget<TextButton>(
                    find.widgetWithText(TextButton, 'Confirm occurrence'),
                  )
                  .onPressed !=
              null,
          enabled,
        );
      },
    );
  }
  for (final complete in [true, false]) {
    testWidgets(
      'contract3 preserves ${complete ? 'write permission' : 'complete snapshot'} guard',
      (tester) async {
        await _pump(
          tester,
          3,
          private: true,
          write: !complete,
          complete: complete,
        );
        _expectControls(tester, false);
        expect(
          tester
              .widget<TextButton>(
                find.widgetWithText(TextButton, 'Confirm occurrence'),
              )
              .onPressed,
          isNull,
        );
      },
    );
  }
}
