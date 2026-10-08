import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/organizer_repository.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'package:kanban/organizer/domain/finance_forecast.dart';
import 'package:kanban/organizer/domain/finance_reminder_plans.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'organizer_repository_test.dart' show MemoryStorage;

final clock = DateTime(2026, 10, 8, 12);
FinanceRecurrenceRule rule({
  FinanceRecurrenceKind kind = FinanceRecurrenceKind.salary,
  int day = 31,
  bool reminders = false,
}) => FinanceRecurrenceRule(
  id: 'rule',
  title: 'My income',
  kind: kind,
  currency: 'EUR',
  estimatedAmountMinor: 123456,
  startYear: 2026,
  startMonth: 10,
  monthDay: day,
  remindersEnabled: reminders,
  createdAt: clock.toUtc(),
  updatedAt: clock.toUtc(),
);
LocalFinanceAccount account({int? opening, DateTime? at}) =>
    LocalFinanceAccount(
      id: 'account',
      name: 'My ledger',
      currency: 'EUR',
      openingBalanceMinor: opening,
      openingBalanceAt: at,
      createdAt: clock.toUtc(),
      updatedAt: clock.toUtc(),
    );
FinanceEntry entry({
  String id = 'entry',
  int amount = 500,
  String currency = 'EUR',
  FinanceEntryStatus status = FinanceEntryStatus.planned,
  DateTime? at,
  String? accountId,
  String? ruleId,
  String? key,
}) => FinanceEntry(
  id: id,
  title: id,
  amountMinor: amount,
  currency: currency,
  kind: FinanceEntryKind.income,
  status: status,
  plannedAt: at,
  occurredAt: at ?? clock.toUtc(),
  ledgerAccountId: accountId,
  recurrenceRuleId: ruleId,
  occurrenceKey: key,
  projectId: null,
  notes: '',
  createdAt: clock.toUtc(),
  updatedAt: clock.toUtc(),
);
AccountSession profile() => AccountSession(
  serverUrl: 'https://example.test/',
  serverId: 'server',
  accountId: 'owner',
  userId: 1,
  username: 'owner',
  displayName: 'Owner',
  deviceId: 'device',
  expiresAt: DateTime.utc(2099),
);
void main() {
  test('monthly dates clamp 31 to leap/year-specific month end', () {
    final r = rule();
    expect(r.dateForMonth(2027, 2), DateTime(2027, 2, 28));
    expect(r.dateForMonth(2028, 2), DateTime(2028, 2, 29));
    expect(r.dateForMonth(2026, 11), DateTime(2026, 11, 30));
    expect(r.keyForMonth(2026, 11), '2026-11');
    expect(
      FinanceRecurrenceRule.fromJson(r.toJson().cast()).toJson(),
      r.toJson(),
    );
  });
  test('salary weekend checks are Friday and Monday of same occurrence', () {
    final r = rule();
    expect(salaryCheckDates(r, DateTime(2026, 10, 31)), [
      DateTime(2026, 10, 30, 9),
      DateTime(2026, 11, 2, 9),
    ]);
    expect(salaryCheckDates(r, DateTime(2026, 11, 1)), [
      DateTime(2026, 10, 30, 9),
      DateTime(2026, 11, 2, 9),
    ]);
    expect(salaryCheckDates(r, DateTime(2026, 10, 29)), [
      DateTime(2026, 10, 29, 9),
    ]);
  });
  test(
    'atomic plan, restart, repeated materialization, different actual amount and repeated confirmation',
    () async {
      final storage = MemoryStorage();
      var next = 0;
      final repo = OrganizerRepository(
        storage,
        clock: () => clock,
        idGenerator: () => 'id-${next++}',
      );
      addTearDown(repo.close);
      await repo.initialize();
      await repo.saveFinancePlan(
        accounts: [],
        rules: [rule()],
        expectedRevision: 0,
        expectedWorkspaceKey: 'local',
      );
      expect(repo.snapshot.financeEntries, hasLength(12));
      expect(repo.snapshot.exactBalanceForCurrency('EUR'), BigInt.zero);
      final ids = repo.snapshot.financeEntries.map((e) => e.id).toList();
      await repo.materializeFinanceOccurrences(expectedWorkspaceKey: 'local');
      expect(repo.snapshot.financeEntries.map((e) => e.id), ids);
      final expected = repo.snapshot.financeEntries.first;
      final paid = DateTime(2026, 10, 30, 17).toUtc();
      await repo.confirmFinanceOccurrence(
        entry: expected,
        amountMinor: 129900,
        paidAt: paid,
        expectedWorkspaceKey: 'local',
      );
      await repo.confirmFinanceOccurrence(
        entry: expected,
        amountMinor: 129900,
        paidAt: paid,
        expectedWorkspaceKey: 'local',
      );
      final posted = repo.snapshot.financeEntries.first;
      expect(posted.id, expected.id);
      expect(posted.plannedAt, expected.plannedAt);
      expect(posted.paidAt, paid);
      expect(posted.amountMinor, 129900);
      expect(repo.snapshot.exactBalanceForCurrency('EUR'), BigInt.from(129900));
      final old = repo.snapshot.financeRecurrenceRules.single;
      await repo.updateFinanceRecurrenceRule(
        old.copyWith(estimatedAmountMinor: 140000, monthDay: 15),
        expectedWorkspaceKey: 'local',
      );
      expect(repo.snapshot.financeEntries.first.amountMinor, 129900);
      expect(repo.snapshot.financeEntries.first.paidAt, paid);
      final restored = OrganizerRepository(storage, clock: () => clock);
      addTearDown(restored.close);
      await restored.initialize();
      expect(
        restored.snapshot.financeEntries.first.status,
        FinanceEntryStatus.posted,
      );
      expect(
        restored.snapshot.financeRecurrenceRules.single.estimatedAmountMinor,
        140000,
      );
      expect(restored.snapshot.financeEntries, hasLength(12));
    },
  );
  test(
    'workspace and stale revisions cannot mutate other account plan',
    () async {
      final repo = OrganizerRepository(MemoryStorage(), clock: () => clock);
      addTearDown(repo.close);
      await repo.initialize();
      await expectLater(
        repo.saveFinancePlan(
          accounts: [],
          rules: [rule()],
          expectedRevision: 0,
          expectedWorkspaceKey: 'private:other',
        ),
        throwsA(isA<OrganizerConflictException>()),
      );
      await repo.saveFinancePlan(
        accounts: [],
        rules: [rule()],
        expectedRevision: 0,
        expectedWorkspaceKey: 'local',
      );
      await expectLater(
        repo.saveFinancePlan(
          accounts: [],
          rules: [rule()],
          expectedRevision: 0,
          expectedWorkspaceKey: 'local',
        ),
        throwsA(isA<OrganizerConflictException>()),
      );
      await expectLater(
        repo.updateFinanceRecurrenceRule(
          rule().copyWith(currency: 'USD'),
          expectedWorkspaceKey: 'local',
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'forecast carries outstanding salary to opening date; booked prior money is already included',
    () {
      final monday = DateTime(2026, 11, 2).toUtc();
      final a = account(opening: 10000, at: monday);
      final s = OrganizerSnapshot(
        financeAccounts: [a],
        financeEntries: [
          entry(
            id: 'overdue',
            amount: 50000,
            at: DateTime(2026, 11, 1).toUtc(),
            accountId: a.id,
          ),
          entry(
            id: 'already-in-opening',
            amount: 30000,
            at: DateTime(2026, 10, 31).toUtc(),
            accountId: a.id,
            status: FinanceEntryStatus.posted,
          ),
        ],
      );
      final f = forecastFinance(
        s,
        currency: 'EUR',
        account: a,
        through: DateTime(2026, 12, 1).toUtc(),
      );
      expect(f.points, hasLength(1));
      expect(f.points.single.date, monday);
      expect(f.endMinor, BigInt.from(60000));
      expect(f.hasOpeningBalance, true);
    },
  );
  test(
    'no opening means net changes, currencies separate, undated planned cost excluded',
    () {
      final s = OrganizerSnapshot(
        financeEntries: [
          entry(amount: 123, at: clock.toUtc()),
          entry(id: 'usd', currency: 'USD', amount: 500, at: clock.toUtc()),
          entry(id: 'undated'),
        ],
      );
      final f = forecastFinance(
        s,
        currency: 'EUR',
        through: DateTime(2027).toUtc(),
      );
      expect(f.endMinor, BigInt.from(123));
      expect(f.hasOpeningBalance, false);
      expect(f.undatedCount, 1);
    },
  );
  test(
    'canonical posted recurrence suppresses stale planned projection by month key',
    () {
      final s = OrganizerSnapshot(
        financeEntries: [
          entry(
            id: 'stale',
            amount: 100,
            ruleId: 'rule',
            key: '2026-10',
            at: clock.toUtc(),
          ),
          entry(
            id: 'canonical',
            amount: 150,
            ruleId: 'rule',
            key: '2026-10',
            at: clock.toUtc(),
            status: FinanceEntryStatus.posted,
          ),
        ],
      );
      expect(
        forecastFinance(
          s,
          currency: 'EUR',
          through: DateTime(2027).toUtc(),
        ).endMinor,
        BigInt.from(150),
      );
    },
  );
  test(
    'salary reminder is opt-in and both checks disappear after actual confirmation',
    () {
      final r = rule(reminders: true);
      final expected = entry(
        ruleId: r.id,
        key: '2026-10',
        at: r.dateForMonth(2026, 10).toUtc(),
      );
      final s = OrganizerSnapshot(
        financeRecurrenceRules: [r],
        financeEntries: [expected],
      );
      final plans = desiredFinanceReminderPlans(
        personal: s,
        shared: CollaborationState(),
      );
      expect(plans, hasLength(2));
      expect(
        plans.map((p) => p.target.records.single.recordId),
        everyElement(expected.id),
      );
      expect(
        desiredFinanceReminderPlans(
          personal: s.copyWith(
            financeRecurrenceRules: [r.copyWith(remindersEnabled: false)],
          ),
          shared: CollaborationState(),
        ),
        isEmpty,
      );
      expect(
        desiredFinanceReminderPlans(
          personal: s.copyWith(
            financeEntries: [
              expected.copyWith(
                status: FinanceEntryStatus.posted,
                paidAt: clock.toUtc(),
              ),
            ],
          ),
          shared: CollaborationState(),
        ),
        isEmpty,
      );
    },
  );
  test(
    'BigInt forecast preserves amount beyond JavaScript safe integer with opening balance',
    () {
      final a = account(
        opening: 9000000000000,
        at: DateTime(2026, 10, 1).toUtc(),
      );
      final s = OrganizerSnapshot(
        financeAccounts: [a],
        financeEntries: [
          for (var i = 0; i < 1000; i++)
            entry(
              id: 'entry-$i',
              amount: 9000000000000,
              accountId: a.id,
              at: clock.toUtc(),
              status: FinanceEntryStatus.posted,
            ),
        ],
      );
      s.validate();
      expect(
        forecastFinance(
          s,
          currency: 'EUR',
          account: a,
          through: DateTime(2027).toUtc(),
        ).endMinor,
        BigInt.parse('9009000000000000'),
      );
    },
  );
  test(
    'loan principal is separate from installment estimate and invalid empty balances rejected',
    () {
      final r = rule(
        kind: FinanceRecurrenceKind.loanInstallment,
      ).copyWith(loanPrincipalMinor: 10000000);
      r.validate();
      expect(r.estimatedAmountMinor, 123456);
      expect(r.entryKind, FinanceEntryKind.expense);
      expect(() => account(at: clock).validate(), throwsFormatException);
      expect(
        () => rule().copyWith(estimatedAmountMinor: 0).validate(),
        throwsFormatException,
      );
    },
  );
  test(
    'legacy account name edit to v2 keeps date-null opening and all prior posted history',
    () {
      final created = DateTime.utc(2026, 10, 4);
      final old = SharedFinanceAccount(
        id: 'old',
        name: 'Actual old account',
        currency: 'EUR',
        openingBalanceMinor: 20000,
        createdAt: created,
        updatedAt: created,
      );
      final expense = SharedFinanceEntry(
        id: 'paid',
        createdAt: created,
        updatedAt: created,
        accountId: 'old',
        kind: FinanceEntryKind.expense,
        amountMinor: 5000,
        currency: 'EUR',
        title: 'Actual earlier expense',
        occurredAt: DateTime.utc(2026, 10, 1),
      );
      final renamed = old.copyWith(name: 'Actual new name');
      final p = renamed.toPayload(contractVersion: 2);
      expect(p['openingBalanceAt'], null);
      final reread = SharedFinanceAccount.fromJson({
        ...p,
        'id': old.id,
        'revision': 1,
      });
      final before = summarizeSharedFinance(
        accounts: [old],
        entries: [expense],
        transfers: [],
      );
      final after = summarizeSharedFinance(
        accounts: [reread],
        entries: [expense],
        transfers: [],
      );
      expect(after['EUR']!.balanceMinor, before['EUR']!.balanceMinor);
      expect(after['EUR']!.balanceMinor, BigInt.from(15000));
      final local = LocalFinanceAccount(
        id: 'old',
        name: reread.name,
        currency: 'EUR',
        openingBalanceMinor: reread.openingBalanceMinor,
        openingBalanceAt: reread.openingBalanceAt,
        createdAt: created,
        updatedAt: created,
      );
      local.validate();
      final snapshot = OrganizerSnapshot(
        financeAccounts: [local],
        financeEntries: [
          entry(
            amount: 5000,
            accountId: local.id,
            at: expense.occurredAt,
            status: FinanceEntryStatus.posted,
          ).copyWith(kind: FinanceEntryKind.expense),
        ],
      );
      expect(
        forecastFinance(
          snapshot,
          currency: 'EUR',
          account: local,
          through: DateTime.utc(2027),
        ).endMinor,
        BigInt.from(15000),
      );
    },
  );
  test(
    'account opening cutoffs independently exclude historic entries and transfer sides',
    () {
      final created = DateTime.utc(2026, 10, 4);
      final a = SharedFinanceAccount(
        id: 'a',
        name: 'A',
        currency: 'EUR',
        openingBalanceMinor: 10000,
        openingBalanceAt: DateTime.utc(2026, 9, 1),
        createdAt: created,
        updatedAt: created,
      );
      final b = SharedFinanceAccount(
        id: 'b',
        name: 'B',
        currency: 'EUR',
        openingBalanceMinor: 20000,
        openingBalanceAt: DateTime.utc(2026, 10, 1),
        createdAt: created,
        updatedAt: created,
      );
      final transfer = SharedFinanceTransfer(
        id: 'transfer',
        createdAt: created,
        updatedAt: created,
        fromAccountId: a.id,
        toAccountId: b.id,
        amountMinor: 5000,
        currency: 'EUR',
        title: 'Actual transfer',
        occurredAt: DateTime.utc(2026, 9, 15),
      );
      final balances = summarizeSharedFinance(
        accounts: [a, b],
        entries: [],
        transfers: [transfer],
      )['EUR']!.accountBalances;
      expect(balances[a.id], BigInt.from(5000));
      expect(balances[b.id], BigInt.from(20000));
    },
  );
  test(
    'hybrid local reminders survive private financial denial without wrong server targets',
    () {
      final session = profile(), localRule = rule(reminders: true);
      final privateRule = FinanceRecurrenceRule.fromJson({
        ...localRule.toJson(),
        'id': 'private-rule',
      });
      final localEntry = entry(
        id: 'local-entry',
        ruleId: localRule.id,
        key: '2026-10',
        at: localRule.dateForMonth(2026, 10).toUtc(),
      );
      final privateEntry = entry(
        id: 'private-entry',
        ruleId: privateRule.id,
        key: '2026-10',
        at: privateRule.dateForMonth(2026, 10).toUtc(),
      );
      final personal = OrganizerSnapshot(
        workspaceKey: 'private:${session.partition}',
        financeRecurrenceRules: [localRule, privateRule],
        financeEntries: [localEntry, privateEntry],
      );
      final state = CollaborationState(
        session: session,
        privateSync: const PrivateSyncState(
          enabled: true,
          scopeId: 'private-scope',
        ),
        privateRecordIds: {
          'private-entry': 'private-entry',
          'private-rule': 'private-rule',
        },
      );
      final plans = desiredFinanceReminderPlans(
        personal: personal,
        shared: state,
      );
      expect(plans, hasLength(2));
      expect(plans.every((p) => p.target.isPersonal), true);
      expect(
        plans.every((p) => p.target.records.single.recordId == localEntry.id),
        true,
      );
    },
  );
  test(
    'archived shared project has no finance reminders while history remains represented',
    () {
      final r = rule(reminders: true).copyWith(ledgerAccountId: 'account');
      final state = CollaborationState(
        session: profile(),
        scopes: [
          const SharedScope(
            id: 'project',
            name: 'Archived real project',
            kind: SharedScopeKind.project,
            role: SharedRole.owner,
            archived: true,
          ),
        ],
        financePolicies: {
          'project': const SharedFinancePolicy(
            enabled: true,
            grant: SharedFinanceGrant.write,
          ),
        },
        financeSnapshotComplete: {'project': true},
        data: {
          'project': SharedScopeData(
            financeRecurrenceRules: [r],
            financeEntries: [
              SharedFinanceEntry(
                id: 'planned',
                accountId: 'account',
                kind: FinanceEntryKind.income,
                status: SharedFinanceStatus.planned,
                amountMinor: 100,
                currency: 'EUR',
                title: 'Actual income',
                occurredAt: clock,
                plannedAt: clock,
                recurrenceRuleId: r.id,
                occurrenceKey: '2026-10',
                createdAt: clock,
                updatedAt: clock,
              ),
            ],
          ),
        },
      );
      expect(
        desiredFinanceReminderPlans(
          personal: OrganizerSnapshot(),
          shared: state,
        ),
        isEmpty,
      );
      expect(state.dataForScope('project').financeEntries, hasLength(1));
    },
  );
  test(
    'recurring delete is rejected; stopped rule remains stopped after restart and materialization',
    () async {
      final storage = MemoryStorage();
      final repo = OrganizerRepository(storage, clock: () => clock);
      addTearDown(repo.close);
      await repo.initialize();
      await repo.saveFinancePlan(
        accounts: [],
        rules: [rule()],
        expectedRevision: 0,
        expectedWorkspaceKey: 'local',
      );
      final first = repo.snapshot.financeEntries.first;
      await expectLater(
        repo.deleteFinanceEntry(first.id),
        throwsA(isA<Exception>()),
      );
      await repo.updateFinanceRecurrenceRule(
        repo.snapshot.financeRecurrenceRules.single.copyWith(active: false),
        expectedWorkspaceKey: 'local',
      );
      final restored = OrganizerRepository(storage, clock: () => clock);
      addTearDown(restored.close);
      await restored.initialize();
      await restored.materializeFinanceOccurrences(
        expectedWorkspaceKey: 'local',
      );
      expect(restored.snapshot.financeEntries, isEmpty);
      expect(restored.snapshot.financeRecurrenceRules.single.active, false);
    },
  );
}
