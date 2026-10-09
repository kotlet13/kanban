import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/domain/all_spaces_projection.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';

final now = DateTime.utc(2026, 10, 9);
AccountSession session(String account, {String device = 'device'}) =>
    AccountSession(
      serverUrl: 'https://synthetic.invalid/',
      serverId: 'server',
      accountId: account,
      userId: 1,
      username: account,
      displayName: account,
      deviceId: device,
      expiresAt: now.add(const Duration(days: 1)),
    );
SharedScope scope(
  String id, {
  bool revoked = false,
  bool archived = false,
  bool blocked = false,
  SharedScopeKind kind = SharedScopeKind.household,
}) => SharedScope(
  id: id,
  name: id,
  kind: kind,
  role: SharedRole.member,
  revoked: revoked,
  archived: archived,
  blocked: blocked,
);
LocalTask task(String id) => LocalTask(
  id: id,
  title: id,
  notes: '',
  projectId: null,
  dueAt: now,
  isCompleted: false,
  createdAt: now,
  updatedAt: now,
);
FinanceEntry localMoney(String id, {String currency = 'EUR'}) => FinanceEntry(
  id: id,
  title: id,
  amountMinor: 100,
  currency: currency,
  kind: FinanceEntryKind.income,
  occurredAt: now,
  projectId: null,
  notes: '',
  createdAt: now,
  updatedAt: now,
);
SharedFinanceEntry money(
  String id, {
  String currency = 'EUR',
  SharedFinanceStatus status = SharedFinanceStatus.posted,
}) => SharedFinanceEntry(
  id: id,
  createdAt: now,
  updatedAt: now,
  accountId: 'ledger',
  kind: FinanceEntryKind.expense,
  status: status,
  taskId: 'linked-task',
  amountMinor: 200,
  currency: currency,
  title: id,
  occurredAt: now,
);
const read = SharedFinancePolicy(enabled: true, grant: SharedFinanceGrant.read);

void main() {
  test('local only has true source and no account requirement', () {
    final projection = projectAllSpaces(
      personal: OrganizerSnapshot(tasks: [task('local')]),
      shared: CollaborationState(),
    );
    expect(projection.tasks.single.value.id, 'local');
    expect(projection.tasks.single.source.workspaceKey, 'local');
    expect(
      projection.tasks.single.source.target('task', 'local').isPersonal,
      true,
    );
    expect(
      projection.sources.single.isCurrent(
        OrganizerSnapshot(),
        CollaborationState(),
      ),
      true,
    );
  });

  test(
    'same record IDs retain independent sources, revoked/archived omitted',
    () {
      final shared = CollaborationState(
        session: session('alice'),
        scopes: [
          scope('first'),
          scope('second'),
          scope('revoked', revoked: true),
          scope('archived', archived: true),
          scope('blocked', blocked: true),
        ],
        data: {
          for (final id in [
            'first',
            'second',
            'revoked',
            'archived',
            'blocked',
          ])
            id: SharedScopeData(tasks: [task('same')]),
        },
      );
      final result = projectAllSpaces(
        personal: OrganizerSnapshot(tasks: [task('same')]),
        shared: shared,
      );
      expect(result.tasks.length, 3);
      expect(result.tasks.map((r) => r.source.scopeId), [
        null,
        'first',
        'second',
      ]);
      final target = result.tasks[1].source.target('task', 'same');
      expect(target.scopeId, 'first');
      expect(target.accountId, 'alice');
      expect(target.serverId, 'server');
    },
  );

  test(
    'active private presentation included once; mismatched and logged out hidden',
    () {
      final account = session('alice');
      final personal = OrganizerSnapshot(
        workspaceKey: 'private:${account.partition}',
        tasks: [task('mapped-local-id')],
        financeEntries: [localMoney('mapped-money')],
      );
      final shared = CollaborationState(
        session: account,
        privateSync: PrivateSyncState(
          enabled: true,
          scopeId: 'private',
          partition: account.partition,
        ),
        privateRecordIds: {
          'server-id': 'mapped-local-id',
          'server-money': 'mapped-money',
        },
        scopes: [
          scope('private', kind: SharedScopeKind.personal),
          scope('home'),
        ],
        data: {
          'private': SharedScopeData(tasks: [task('server-id')]),
          'home': SharedScopeData(tasks: [task('home-task')]),
        },
        financePolicies: {'private': read},
        financeSnapshotComplete: {'private': true},
      );
      final result = projectAllSpaces(personal: personal, shared: shared);
      expect(result.tasks.map((r) => r.value.id), [
        'mapped-local-id',
        'home-task',
      ]);
      expect(result.localFinanceEntries.length, 1);
      expect(result.sources.first.isCurrent(personal, shared), true);
      final taskTarget = result.tasks.first.source.target(
        'task',
        'mapped-local-id',
      );
      expect(taskTarget.isPersonal, false);
      expect(taskTarget.scopeId, 'private');
      expect(taskTarget.records.single.recordId, 'server-id');
      final financialTarget = result.localFinanceEntries.single.source.target(
        'financeEntry',
        'mapped-money',
      );
      expect(financialTarget.accountId, 'alice');
      expect(financialTarget.records.single.type, 'personalFinanceEntry');
      expect(financialTarget.records.single.recordId, 'server-money');
      expect(
        result.sources.first.target('task', 'unsynced-local').isPersonal,
        true,
      );
      expect(
        projectAllSpaces(
          personal: personal,
          shared: CollaborationState(),
        ).sources,
        isEmpty,
      );
      expect(
        projectAllSpaces(
          personal: personal,
          shared: CollaborationState(session: session('bob')),
        ).sources,
        isEmpty,
      );
      expect(
        projectAllSpaces(
          personal: personal,
          shared: CollaborationState(
            session: account,
            sessionInvalid: true,
            localAccessAllowed: false,
          ),
        ).sources,
        isEmpty,
      );
    },
  );

  test(
    'private stale financial projection hidden after denial or incomplete refresh',
    () {
      final account = session('alice');
      final personal = OrganizerSnapshot(
        workspaceKey: 'private:${account.partition}',
        tasks: [task('task')],
        financeEntries: [localMoney('sensitive')],
      );
      CollaborationState shared({bool complete = false, bool allowed = true}) =>
          CollaborationState(
            session: account,
            scopes: [scope('private', kind: SharedScopeKind.personal)],
            privateSync: PrivateSyncState(enabled: true, scopeId: 'private'),
            financePolicies: {
              'private': allowed ? read : const SharedFinancePolicy(),
            },
            financeSnapshotComplete: {'private': complete},
          );
      final partial = projectAllSpaces(personal: personal, shared: shared());
      expect(partial.localFinanceEntries, isEmpty);
      expect(partial.financeComplete, false);
      expect(partial.tasks.single.value.id, 'task');
      final denied = projectAllSpaces(
        personal: personal,
        shared: shared(allowed: false),
      );
      expect(denied.localFinanceEntries, isEmpty);
      expect(denied.sources.single.canReadFinance, false);
      final oldSource = projectAllSpaces(
        personal: personal,
        shared: shared(complete: true),
      ).sources.single;
      expect(
        oldSource.isCurrent(personal, shared(allowed: false), financial: true),
        false,
      );
      expect(oldSource.isCurrent(personal, shared(), financial: true), false);
    },
  );

  test(
    'finance checks independent policy, partial coverage, currency, planned and transfers',
    () {
      final result = projectAllSpaces(
        personal: OrganizerSnapshot(financeEntries: [localMoney('local')]),
        shared: CollaborationState(
          session: session('alice'),
          scopes: [scope('read'), scope('denied')],
          financePolicies: {'read': read},
          financeSnapshotComplete: {'read': false},
          data: {
            'read': SharedScopeData(
              financeEntries: [
                money('cost'),
                money('usd', currency: 'USD'),
                money('planned', status: SharedFinanceStatus.planned),
              ],
              tasks: [task('linked-task')],
              financeTransfers: [
                SharedFinanceTransfer(
                  id: 'transfer',
                  createdAt: now,
                  updatedAt: now,
                  fromAccountId: 'a',
                  toAccountId: 'b',
                  amountMinor: 10000,
                  currency: 'EUR',
                  title: 'Transfer',
                  occurredAt: now,
                ),
              ],
            ),
            'denied': SharedScopeData(financeEntries: [money('secret')]),
          },
        ),
      );
      expect(result.sharedFinanceEntries.length, 3);
      expect(result.financeTransfers.length, 1);
      expect(result.financeComplete, false);
      expect(result.incompleteFinanceSources.single.scopeId, 'read');
      expect(
        result.financeTotalsByCurrency['EUR']!.incomeMinor,
        BigInt.from(100),
      );
      expect(result.financeTotalsByCurrency['EUR']!.expenseMinor, BigInt.zero);
      expect(result.financeTotalsByCurrency.containsKey('USD'), false);
      final complete = projectAllSpaces(
        personal: OrganizerSnapshot(),
        shared: CollaborationState(
          session: session('alice'),
          scopes: [scope('read')],
          financePolicies: {'read': read},
          financeSnapshotComplete: {'read': true},
          data: {
            'read': result.sources.lastWhere((s) => s.scopeId == 'read').data!,
          },
        ),
      );
      expect(
        complete.financeTotalsByCurrency['EUR']!.expenseMinor,
        BigInt.from(200),
      );
      expect(
        complete.financeTotalsByCurrency['USD']!.expenseMinor,
        BigInt.from(200),
      );
    },
  );

  test('saved shared source rejects changed account and revoked source', () {
    final personal = OrganizerSnapshot();
    final shared = CollaborationState(
      session: session('alice'),
      scopes: [scope('home')],
    );
    final source = projectAllSpaces(
      personal: personal,
      shared: shared,
    ).sources.last;
    expect(source.isCurrent(personal, shared), true);
    expect(
      source.isCurrent(
        personal,
        CollaborationState(
          session: session('alice', device: 'new-device'),
          scopes: [scope('home')],
        ),
      ),
      false,
    );
    expect(
      source.isCurrent(
        personal,
        CollaborationState(
          session: session('alice'),
          scopes: [scope('home', blocked: true)],
        ),
      ),
      false,
    );
    expect(source.isCurrent(personal, CollaborationState()), false);
    expect(
      source.isCurrent(
        personal,
        CollaborationState(session: session('bob'), scopes: [scope('home')]),
      ),
      false,
    );
    expect(
      source.isCurrent(
        personal,
        CollaborationState(
          session: session('alice'),
          scopes: [scope('home', revoked: true)],
        ),
      ),
      false,
    );
  });
}
