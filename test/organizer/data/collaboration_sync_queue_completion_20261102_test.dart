import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';

import '../support/synthetic_content_route_guard.dart';
import 'collaboration_repository_test.dart'
    show FakeServer, FakeTransport, MemorySessionStore;

class _MetadataDatabase extends CollaborationDatabase {
  _MetadataDatabase() : super(NativeDatabase.memory());
  int workReads = 0;
  @override
  Future<List<Map<String, dynamic>>> rows(
    String sql, [
    List<Object?> args = const [],
  ]) {
    if (sql.startsWith("SELECT 'record'")) workReads++;
    return super.rows(sql, args);
  }
}

void main() {
  var now = DateTime.utc(2026, 11, 2, 10);
  Future<CollaborationRepository> open() async {
    now = DateTime.utc(2026, 11, 2, 10);
    final repo = CollaborationRepository(
      _MetadataDatabase(),
      FakeTransport(FakeServer()),
      MemorySessionStore(),
      contentRouteGuard: const SyntheticContentRouteGuard(),
      clock: () => now,
    );
    addTearDown(repo.close);
    await repo.initialize();
    await repo.login(
      serverUrl: 'https://synthetic.invalid/',
      username: 'alice',
      password: 'synthetic',
    );
    return repo;
  }

  test(
    'new blocked crypto debt cannot advertise current full sync success',
    () async {
      final repo = await open();
      final prior = repo.state.lastSuccessfulSyncAt;
      final partition = repo.state.session!.partition;
      await repo.database.execute(
        "INSERT INTO crypto_outbox(partition,request_id,operation,signed_body,request_hash,state,response) VALUES(?,?,?,?,?,'blocked',?)",
        [
          partition,
          'retained',
          'crypto2.domain.checkpoint',
          '{}',
          'hash',
          '{"outcome":"unresolved","reason":"authority_pending"}',
        ],
      );
      final original = await repo.database.rows('SELECT * FROM crypto_outbox');
      now = now.add(const Duration(minutes: 1));
      await repo.syncNow(manual: true);
      expect(repo.state.lastError, isNull);
      expect(repo.state.pendingCount, 0);
      expect(repo.state.blockedCount, 0);
      expect(repo.state.financePendingCount, 0);
      expect(repo.state.hasUnresolvedSyncWork, isTrue);
      expect(repo.state.pendingSyncCommandCount, 0);
      expect(repo.state.blockedSyncCommandCount, 1);
      expect(repo.lastSyncCompletion!.work.unresolved, isTrue);
      expect(repo.state.lastSuccessfulSyncAt, prior);
      expect(await repo.database.rows('SELECT * FROM crypto_outbox'), original);
    },
  );

  test('new drained full sync still records current success', () async {
    final repo = await open();
    await repo.syncNow(manual: true);
    expect(repo.state.lastError, isNull);
    expect(repo.lastSyncCompletion!.work.unresolved, isFalse);
    expect(repo.state.lastSuccessfulSyncAt, DateTime.utc(2026, 11, 2, 10));
  });

  test(
    'new full success checks business debt using aggregate metadata only',
    () async {
      final repo = await open();
      final prior = repo.state.lastSuccessfulSyncAt;
      final db = repo.database as _MetadataDatabase;
      await db.execute(
        "INSERT INTO commands(id,partition,operation,params,entity_key,state) VALUES(?,?,?,?,?,'blocked')",
        [
          'preserved',
          repo.state.session!.partition,
          'synthetic',
          '{}',
          'preserved',
        ],
      );
      final original = await db.rows('SELECT * FROM commands');
      db.workReads = 0;
      now = now.add(const Duration(minutes: 1));
      await repo.syncNow(manual: true);
      expect(repo.state.lastError, isNull);
      expect(repo.state.lastSuccessfulSyncAt, prior);
      expect(repo.lastSyncCompletion!.work.unresolved, isTrue);
      expect(
        db.workReads,
        1,
        reason: 'Only final completion needs the queue signature',
      );
      expect(await db.rows('SELECT * FROM commands'), original);
    },
  );

  test(
    'new hidden queue counts preserve partition and terminal boundaries',
    () async {
      final repo = await open();
      final partition = repo.state.session!.partition;
      for (final entry in [
        ('pending', partition),
        ('blocked', partition),
        ('applied', partition),
        ('rejected', partition),
        ('pending', 'foreign'),
        ('blocked', 'foreign'),
      ]) {
        await repo.database.execute(
          'INSERT INTO crypto_outbox(partition,request_id,operation,signed_body,request_hash,state) VALUES(?,?,?,?,?,?)',
          [
            entry.$2,
            '${entry.$1}:${entry.$2}',
            'crypto2.domain.checkpoint',
            '{}',
            'hash',
            entry.$1,
          ],
        );
      }
      for (final entry in [
        ('pending', partition),
        ('waiting_source_publication', partition),
        ('quarantine', partition),
        ('complete', partition),
        ('local_only', partition),
        ('pending', 'foreign'),
        ('quarantine', 'foreign'),
      ]) {
        await repo.database.execute(
          'INSERT INTO linked_payment_intents(id,data,state) VALUES(?,?,?)',
          ['${entry.$1}:${entry.$2}', '{"partition":"${entry.$2}"}', entry.$1],
        );
      }
      final original = await repo.database.rows('SELECT * FROM crypto_outbox');
      final payments = await repo.database.rows(
        'SELECT * FROM linked_payment_intents',
      );
      await repo.refreshLocal();
      expect(repo.state.pendingCount, 0);
      expect(repo.state.financePendingCount, 0);
      expect(repo.state.pendingSyncCommandCount, 3);
      expect(repo.state.blockedSyncCommandCount, 2);
      expect(repo.state.hasUnresolvedSyncWork, isTrue);
      expect(await repo.database.rows('SELECT * FROM crypto_outbox'), original);
      expect(
        await repo.database.rows('SELECT * FROM linked_payment_intents'),
        payments,
      );
      final evidence = CollaborationState.withChangeCheckEvidence(
        repo.state,
        lastChangeCheckAttemptAt: now,
        lastSuccessfulChangeCheckAt: now,
        lastError: null,
        syncRequiresRefresh: false,
        hasUnresolvedSyncWork: true,
      );
      expect(evidence.pendingSyncCommandCount, 3);
      expect(evidence.blockedSyncCommandCount, 2);
    },
  );
}
