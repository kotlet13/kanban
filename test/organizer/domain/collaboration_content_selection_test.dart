import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/domain/collaboration_content_selection.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';

final _now = DateTime.utc(2026, 10, 24);
SharedScope _scope(String id, {int sequence = 0, bool revoked = false}) =>
    SharedScope(
      id: id,
      name: id,
      kind: SharedScopeKind.household,
      role: SharedRole.owner,
      sequence: sequence,
      revoked: revoked,
    );
LocalTask _task(String title) => LocalTask(
  id: 'task',
  title: title,
  notes: '',
  projectId: null,
  dueAt: null,
  isCompleted: false,
  createdAt: _now,
  updatedAt: _now,
);
CollaborationState _state({
  String title = 'One',
  int amount = 100,
  bool syncing = false,
  bool revoked = false,
  int sequence = 0,
}) => CollaborationState(
  scopes: [
    _scope('a', sequence: sequence, revoked: revoked),
    _scope('b'),
  ],
  isSyncing: syncing,
  lastSyncAttemptAt: syncing ? _now : null,
  data: {
    'a': SharedScopeData(
      tasks: [_task(title)],
      financeEntries: [
        SharedFinanceEntry(
          id: 'expense',
          accountId: 'account',
          kind: FinanceEntryKind.expense,
          status: SharedFinanceStatus.posted,
          amountMinor: amount,
          currency: 'EUR',
          title: 'Expense',
          occurredAt: _now,
          createdAt: _now,
          updatedAt: _now,
        ),
      ],
    ),
    'b': SharedScopeData(tasks: [_task('Unchanged')]),
  },
);

void main() {
  test('creator projection changes refresh only the affected record module', () {
    CollaborationState authors(String creator) => CollaborationState(
      scopes: [_scope('a')],
      data: {'a': SharedScopeData(
        tasks: [_task('Same payload')],
        recordCreators: {'content:task': creator},
      )},
    );
    expect(changedCollaborationContentDomains(authors('author-a'), authors('author-b')),
      {'organizer'});
  });
  test('cloud status and scope sequence do not reload content', () {
    expect(
      changedCollaborationContentDomains(
        _state(),
        _state(syncing: true, sequence: 2),
      ),
      isEmpty,
    );
  });
  test('finance change wakes organizer and payments only', () {
    expect(changedCollaborationContentDomains(_state(), _state(amount: 200)), {
      'organizer',
      'payments',
    });
  });
  test('task text does not wake finance, garden, ideas or catalog', () {
    expect(
      changedCollaborationContentDomains(_state(), _state(title: 'Edited')),
      {'organizer'},
    );
  });
  test('a changed scope cannot invalidate another shared module', () {
    expect(
      collaborationContentSignature(_state(), 'organizer', scopeId: 'b'),
      collaborationContentSignature(
        _state(title: 'Edited'),
        'organizer',
        scopeId: 'b',
      ),
    );
    expect(
      collaborationContentSignature(_state(), 'organizer', scopeId: 'a'),
      isNot(
        collaborationContentSignature(
          _state(title: 'Edited'),
          'organizer',
          scopeId: 'a',
        ),
      ),
    );
  });
  test('revocation invalidates content even without a record delta', () {
    expect(
      changedCollaborationContentDomains(_state(), _state(revoked: true)),
      collaborationContentDomains,
    );
  });
  test(
    'database publishes exact domains once and identity invalidates all',
    () async {
      final db = CollaborationDatabase(NativeDatabase.memory());
      final seen = <String>[];
      final subscriptions = [
        for (final domain in collaborationContentDomains)
          db.changesFor(domain).listen((_) => seen.add(domain)),
      ];
      db.personalChanged(domains: {'organizer'});
      await Future<void>.delayed(Duration.zero);
      expect(seen, ['organizer']);
      seen.clear();
      db.personalChanged(domains: {});
      await Future<void>.delayed(Duration.zero);
      expect(seen, isEmpty);
      db.activatePersonal(null);
      await Future<void>.delayed(Duration.zero);
      expect(seen.toSet(), collaborationContentDomains);
      expect(seen.length, collaborationContentDomains.length);
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
      await db.close();
    },
  );
}
