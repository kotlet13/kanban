import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:kanban/organizer/domain/all_spaces_projection.dart';
import 'package:kanban/organizer/domain/linked_payment_models.dart';
import 'package:kanban/organizer/domain/organization_finance_projection.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';

final now = DateTime.utc(2026, 10, 17);
final session = AccountSession(
  serverUrl: 'https://test.invalid',
  serverId: 'server',
  accountId: 'user',
  userId: 1,
  username: 'alice',
  displayName: 'Alice',
  deviceId: 'device',
  expiresAt: now.add(const Duration(days: 1)),
);
const parent = SharedScope(
  id: 'org',
  name: 'Organization',
  kind: SharedScopeKind.organization,
  role: SharedRole.owner,
);
SharedScope child({bool archived = false, bool revoked = false}) => SharedScope(
  id: 'project',
  name: 'Project',
  kind: SharedScopeKind.project,
  role: SharedRole.member,
  parentScopeId: 'org',
  archived: archived,
  revoked: revoked,
);
const policy = SharedFinancePolicy(
  enabled: true,
  grant: SharedFinanceGrant.write,
);
SharedFinanceAccount account(
  String id, {
  int opening = 100000,
  String currency = 'EUR',
}) => SharedFinanceAccount(
  id: id,
  createdAt: now,
  updatedAt: now,
  name: 'Ledger',
  currency: currency,
  openingBalanceMinor: opening,
);
SharedFinanceEntry entry(
  String id, {
  String accountId = 'bank',
  String? parentId,
  int amount = 30000,
  String currency = 'EUR',
  bool income = false,
}) => SharedFinanceEntry(
  id: id,
  createdAt: now,
  updatedAt: now,
  accountId: accountId,
  accountScopeId: parentId,
  kind: income ? FinanceEntryKind.income : FinanceEntryKind.expense,
  amountMinor: amount,
  currency: currency,
  title: 'Movement',
  occurredAt: now,
);
CollaborationState state({
  SharedScope? project,
  bool loggedIn = true,
  bool childComplete = true,
  bool childAllowed = true,
  List<SharedFinanceAccount>? parentAccounts,
  List<SharedFinanceAccount> childAccounts = const [],
  List<SharedFinanceEntry> parentEntries = const [],
  List<SharedFinanceEntry>? childEntries,
  bool linkedRequired = false,
  bool organizationSupported = false,
  SharedFinancePolicy parentPolicy = policy,
  int childCursor = 1,
}) => CollaborationState(
  session: loggedIn ? session : null,
  organizationFinanceSupported: organizationSupported,
  scopes: [parent, project ?? child()],
  financePolicies: {
    'org': parentPolicy,
    'project': childAllowed
        ? SharedFinancePolicy(
            enabled: true,
            grant: SharedFinanceGrant.write,
            linkedPaymentsRequired: linkedRequired,
          )
        : const SharedFinancePolicy(),
  },
  financeSnapshotComplete: {'org': true, 'project': childComplete},
  financeSnapshotSequences: {'org': 1, 'project': childCursor},
  data: {
    'org': SharedScopeData(
      financeAccounts: parentAccounts ?? [account('bank')],
      financeEntries: parentEntries,
    ),
    'project': SharedScopeData(
      financeAccounts: childAccounts,
      financeEntries: childEntries ?? [entry('expense', parentId: 'org')],
    ),
  },
);
Map<String, SharedFinanceTotals> totals(OrganizationFinanceProjection p) =>
    summarizeSharedFinance(
      accounts: p.accounts,
      entries: p.entries,
      transfers: p.transfers,
      payments: p.payments,
    );

void main() {
  test(
    'parent requires refreshed child sequence even when old snapshot is complete',
    () {
      const rootPolicy = SharedFinancePolicy(
        enabled: true,
        grant: SharedFinanceGrant.write,
        organizationFinanceComplete: true,
        organizationFinanceScopeIds: ['project'],
        organizationFinanceSequences: {'project': 2},
      );
      expect(
        projectOrganizationFinance(
          scopeId: 'org',
          state: state(organizationSupported: true, parentPolicy: rootPolicy),
        ).complete,
        false,
      );
      expect(
        projectOrganizationFinance(
          scopeId: 'org',
          state: state(
            organizationSupported: true,
            parentPolicy: rootPolicy,
            childCursor: 2,
          ),
        ).complete,
        true,
      );
    },
  );
  test(
    'deleted last parent link cannot reuse stale child rows as a full balance',
    () {
      const rootPolicy = SharedFinancePolicy(
        enabled: true,
        grant: SharedFinanceGrant.write,
        organizationFinanceComplete: true,
      );
      expect(
        projectOrganizationFinance(
          scopeId: 'org',
          state: state(organizationSupported: true, parentPolicy: rootPolicy),
        ).complete,
        false,
      );
      expect(
        projectOrganizationFinance(
          scopeId: 'org',
          state: state(
            organizationSupported: true,
            parentPolicy: rootPolicy,
            childEntries: [],
          ),
        ).complete,
        true,
      );
    },
  );
  test(
    'All spaces movement sums each canonical entry once and keeps its child source',
    () {
      final all = projectAllSpaces(
        personal: OrganizerSnapshot(),
        shared: state(parentEntries: [entry('space', amount: 5000)]),
      );
      expect(
        all.financeTotalsByCurrency['EUR']!.expenseMinor,
        BigInt.from(35000),
      );
      expect(
        all.sharedFinanceEntries
            .singleWhere((row) => row.value.id == 'expense')
            .source
            .scopeId,
        'project',
      );
    },
  );
  test(
    'server contributor inventory fails closed for hidden or not-yet-listed children',
    () {
      for (final parentPolicy in [
        policy,
        const SharedFinancePolicy(
          enabled: true,
          grant: SharedFinanceGrant.write,
          organizationFinanceComplete: true,
          organizationFinanceScopeIds: ['missing'],
        ),
      ]) {
        expect(
          projectOrganizationFinance(
            scopeId: 'org',
            state: state(
              organizationSupported: true,
              parentPolicy: parentPolicy,
            ),
          ).complete,
          false,
        );
      }
      expect(
        projectOrganizationFinance(
          scopeId: 'org',
          state: state(
            organizationSupported: true,
            parentPolicy: const SharedFinancePolicy(
              enabled: true,
              grant: SharedFinanceGrant.write,
              organizationFinanceComplete: true,
              organizationFinanceScopeIds: ['project'],
              organizationFinanceSequences: {'project': 1},
            ),
          ),
        ).complete,
        true,
      );
    },
  );
  test(
    'parent and child cash share one balance and keep original edit targets',
    () {
      final p = projectOrganizationFinance(
        scopeId: 'org',
        state: state(parentEntries: [entry('expense', amount: 5000)]),
      );
      expect(p.complete, true);
      expect(totals(p)['EUR']!.expenseMinor, BigInt.from(35000));
      expect(totals(p)['EUR']!.accountBalances['org:bank'], BigInt.from(65000));
      expect(
        p.entries.length,
        2,
      ); // Same UUID in different scopes is not a duplicate.
      expect(p.entryScopeIds['project:expense'], 'project');
      expect(p.originalEntries['project:expense']!.accountScopeId, 'org');
      expect(p.originalEntries['project:expense']!.id, 'expense');
      expect(p.entries.last.accountScopeId, null);
      expect(p.entryProjectKeys['project:expense'], 'project');
    },
  );
  test(
    'legacy same-name and same-ID child accounts retain separate balances',
    () {
      final p = projectOrganizationFinance(
        scopeId: 'org',
        state: state(
          childAccounts: [account('bank', opening: 20000)],
          childEntries: [
            entry('legacy', amount: 1000),
            entry('linked', parentId: 'org'),
          ],
        ),
      );
      expect(p.complete, true);
      expect(totals(p)['EUR']!.accountBalances, {
        'org:bank': BigInt.from(70000),
        'project:bank': BigInt.from(19000),
      });
    },
  );
  test('currencies remain independent', () {
    final p = projectOrganizationFinance(
      scopeId: 'org',
      state: state(
        parentAccounts: [
          account('bank'),
          account('usd', currency: 'USD', opening: 0),
        ],
        childEntries: [
          entry('euro', parentId: 'org'),
          entry(
            'dollar',
            parentId: 'org',
            accountId: 'usd',
            currency: 'USD',
            income: true,
            amount: 50,
          ),
        ],
      ),
    );
    expect(totals(p)['EUR']!.expenseMinor, BigInt.from(30000));
    expect(totals(p)['USD']!.incomeMinor, BigInt.from(50));
  });
  test('archived project history still contributes cash', () {
    final p = projectOrganizationFinance(
      scopeId: 'org',
      state: state(project: child(archived: true)),
    );
    expect(p.complete, true);
    expect(totals(p)['EUR']!.accountBalances['org:bank'], BigInt.from(70000));
  });
  test('missing or forbidden child data disables balance certainty', () {
    for (final s in [
      state(childComplete: false),
      state(childAllowed: false),
      state(project: child(revoked: true)),
    ]) {
      expect(
        projectOrganizationFinance(scopeId: 'org', state: s).complete,
        false,
      );
    }
  });
  test(
    'missing and wrong-currency account links cannot produce a false total',
    () {
      for (final e in [
        entry('missing', accountId: 'missing', parentId: 'org'),
        entry('currency', parentId: 'org', currency: 'USD'),
        entry('foreign', parentId: 'other'),
      ]) {
        final p = projectOrganizationFinance(
          scopeId: 'org',
          state: state(childEntries: [e]),
        );
        expect(p.complete, false);
        expect(p.entries, isEmpty);
      }
    },
  );
  test(
    'required payment sidecar gates totals; personal paid and cash refund count once',
    () {
      final s = state(
        linkedRequired: true,
        childAccounts: [account('legacy', opening: 0)],
        childEntries: [entry('paid', accountId: 'legacy')],
      );
      expect(
        projectOrganizationFinance(scopeId: 'org', state: s).complete,
        false,
      );
      final p = projectOrganizationFinance(
        scopeId: 'org',
        state: s,
        paymentsByScope: {
          'project': PaymentSnapshot(
            fresh: true,
            events: [
              PaymentEvent(
                eventId: 'event',
                sourceScopeId: 'project',
                sourceEntryId: 'paid',
                sourceRevision: 1,
                payerAccountId: 'payer',
                amountMinor: 30000,
                currency: 'EUR',
                paidAt: now,
                expectReimbursement: true,
                revision: 1,
              ),
            ],
            cashMovements: [
              PaymentCashMovement(
                id: 'refund',
                accountId: 'legacy',
                amountMinor: -10000,
                currency: 'EUR',
                paidAt: now,
              ),
            ],
          ),
        },
      );
      expect(p.complete, true);
      expect(totals(p)['EUR']!.expenseMinor, BigInt.from(30000));
      expect(
        totals(p)['EUR']!.accountBalances['project:legacy'],
        BigInt.from(-10000),
      );
    },
  );
  test('no session reveals no cached finance content', () {
    final p = projectOrganizationFinance(
      scopeId: 'org',
      state: state(loggedIn: false),
    );
    expect(p.complete, false);
    expect(p.accounts, isEmpty);
    expect(p.entries, isEmpty);
  });
}
