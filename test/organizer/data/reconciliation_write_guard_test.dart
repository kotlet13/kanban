import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/data/device_session_store.dart';
import 'package:kanban/organizer/data/e2ee/crypto_domain_router.dart';

import '../support/synthetic_content_route_guard.dart';
import 'collaboration_repository_test.dart'
    show FakeServer, MemorySessionStore, code;
import 'organization_finance_client_test.dart'
    show OrganizationFinanceTransport;

class _LegacyRouter implements CryptoDomainRouter {
  @override
  Future<Map<String, dynamic>> dispatch({
    required DeviceSession session,
    required String operation,
    required Map<String, Object?> params,
    required Set<String> protectedScopeIds,
  }) async => throw StateError('Synthetic legacy fixture route only');
}

void main() {
  test(
    'missing discovery blocks cached task and finance edits reversibly while retaining exact queued work',
    () async {
      final transport = OrganizationFinanceTransport(FakeServer());
      // One explicit synthetic server owns both the transport and its records.
      final actual = transport.server;
      transport.seed();
      final direct = newSharedId();
      actual.scopes[direct] = {
        'id': direct,
        'kind': 'household',
        'name': 'Independent direct share',
        'sequence': 0,
      };
      actual.members[direct] = {'alice': 'member'};
      actual.records[direct] = {};
      actual.sequence[direct] = 0;
      final db = CollaborationDatabase(NativeDatabase.memory());
      final repo = CollaborationRepository(
        db,
        transport,
        MemorySessionStore(),
        ownsDatabase: false,
        cryptoRouter: _LegacyRouter(),
        contentRouteGuard: const SyntheticContentRouteGuard(),
      );
      addTearDown(() async {
        await repo.close();
        await db.close();
      });
      await repo.initialize();
      await repo.login(
        serverUrl: 'https://example.test/',
        username: 'alice',
        password: 'fixture',
      );
      expect(repo.state.lastError, isNull);
      final partition = repo.state.session!.partition;
      final task = await repo.createTask(
        scopeId: transport.project,
        projectId: transport.project,
        title: 'Retained offline draft',
      );
      final original = (await db.rows(
        'SELECT * FROM outbox WHERE partition=? AND record_id=?',
        [partition, task],
      )).single;
      final originalRecord = (await db.rows(
        'SELECT * FROM records WHERE partition=? AND id=?',
        [partition, task],
      )).single;
      actual.members[transport.project]!.remove(
        'alice',
      ); // No signed revocation proof.
      actual.calls.clear();
      await repo.syncNow();
      final cached = repo.state.scopes.singleWhere(
        (s) => s.id == transport.project,
      );
      expect(cached.revoked, isFalse);
      expect(cached.canRead, isTrue);
      expect(cached.canEdit, isFalse);
      expect(cached.blocked, isTrue);
      expect(
        repo.state.scopes.singleWhere((s) => s.id == direct).canEdit,
        isTrue,
      );
      expect(
        repo.state
            .dataForScope(cached.id)
            .tasks
            .singleWhere((t) => t.id == task)
            .title,
        'Retained offline draft',
      );
      expect(repo.state.pendingCount, 1);
      expect(repo.state.blockedCount, 1);
      expect(
        (await db.rows(
          'SELECT blocked FROM scopes WHERE partition=? AND id=?',
          [partition, cached.id],
        )).single['blocked'],
        0,
      );
      expect(actual.calls.where((c) => c.operation.endsWith('.push')), isEmpty);
      final draft = repo.state
          .dataForScope(cached.id)
          .tasks
          .singleWhere((t) => t.id == task);
      await expectLater(
        repo.updateTask(
          cached.id,
          draft.copyWith(title: 'Must not replace draft'),
        ),
        throwsA(code('changes_blocked')),
      );
      await expectLater(
        repo.createFinanceAccount(
          scopeId: cached.id,
          name: 'Must not queue financial edit',
          currency: 'EUR',
        ),
        throwsA(code('changes_blocked')),
      );
      expect(
        await db.rows(
          'SELECT * FROM outbox WHERE partition=? AND record_id=?',
          [partition, task],
        ),
        [original],
      );
      expect(
        await db.rows('SELECT * FROM records WHERE partition=? AND id=?', [
          partition,
          task,
        ]),
        [originalRecord],
      );
      expect(await db.rows('SELECT 1 FROM finance_outbox'), isEmpty);
      // A verified normal scope response clears only the reversible marker. The
      // original request is delivered as-is; no new edit or operation is created.
      actual.members[transport.project]!['alice'] = 'member';
      await repo.syncNow();
      final restored = repo.state.scopes.singleWhere(
        (s) => s.id == transport.project,
      );
      expect(restored.canEdit, isTrue);
      expect(restored.revoked, isFalse);
      expect(repo.state.blockedCount, 0);
      expect(
        await db.rows(
          'SELECT * FROM outbox WHERE partition=? AND record_id=?',
          [partition, task],
        ),
        isEmpty,
      );
      final delivered = actual.calls.singleWhere(
        (c) => c.operation == 'sync.push',
      );
      expect(jsonEncode(delivered.params['operation']), original['request']);
      expect(
        actual.records[transport.project]![task]!['payload']['title'],
        'Retained offline draft',
      );
    },
  );

  test(
    'reconciliation blocked counts are derived once for regular finance and scoped command rows',
    () async {
      final db = CollaborationDatabase(NativeDatabase.memory());
      final transport = OrganizationFinanceTransport(FakeServer())..seed();
      final repo = CollaborationRepository(
        db,
        transport,
        MemorySessionStore(),
        ownsDatabase: false,
        cryptoRouter: _LegacyRouter(),
        contentRouteGuard: const SyntheticContentRouteGuard(),
      );
      addTearDown(() async {
        await repo.close();
        await db.close();
      });
      await repo.initialize();
      await repo.login(
        serverUrl: 'https://example.test/',
        username: 'alice',
        password: 'fixture',
      );
      final partition = repo.state.session!.partition,
          scope = transport.project;
      await db.execute('INSERT INTO local_meta(name,value) VALUES(?,?)', [
        'scope_reconciliation:$partition:$scope',
        'missing',
      ]);
      await db.execute(
        'INSERT INTO finance_outbox(op_id,partition,scope_id,record_id,request,state) VALUES(?,?,?,?,?,?)',
        [newSharedId(), partition, scope, newSharedId(), '{}', 'pending'],
      );
      await db.execute(
        'INSERT INTO commands(id,partition,operation,params,entity_key,state) VALUES(?,?,?,?,?,?)',
        [
          newSharedId(),
          partition,
          'reminders.put',
          jsonEncode({'scopeId': scope}),
          'fixture',
          'pending',
        ],
      );
      await repo.refreshLocal();
      expect(repo.state.financeBlockedCount, 1);
      expect(repo.state.blockedCount, 1);
      expect(repo.state.pendingCount, 2);
      final stored = await db.rows(
        'SELECT state FROM finance_outbox UNION ALL SELECT state FROM commands',
      );
      expect(stored.map((r) => r['state']), everyElement('pending'));
      await db.execute('DELETE FROM local_meta WHERE name=?', [
        'scope_reconciliation:$partition:$scope',
      ]);
      await repo.refreshLocal();
      expect(repo.state.financeBlockedCount, 0);
      expect(repo.state.blockedCount, 0);
      expect(
        await db.rows(
          'SELECT state FROM finance_outbox UNION ALL SELECT state FROM commands',
        ),
        stored,
      );
    },
  );
}
