import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/data/device_session_store.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:kanban/organizer/data/e2ee/crypto_domain_router.dart';
import '../support/synthetic_content_route_guard.dart';
import 'collaboration_repository_test.dart'
    show FakeServer, FakeTransport, MemorySessionStore;

class _LegacyRouter implements CryptoDomainRouter {
  @override
  Future<Map<String, dynamic>> dispatch({
    required DeviceSession session,
    required String operation,
    required Map<String, Object?> params,
    required Set<String> protectedScopeIds,
  }) async => throw StateError('Protected dispatch unexpected');
}

class _RestoreRouter extends _LegacyRouter implements CryptoRecordRestores {
  int preparations = 0;
  Future<void> Function()? beforeResult;
  @override
  Future<Map<String, dynamic>> prepareRecordRestore({
    required DeviceSession session,
    required String scopeId,
    required String domain,
    required String type,
    required String recordId,
    required int expectedRevision,
  }) async {
    preparations++;
    await beforeResult?.call();
    return {
      'version': 1,
      'scopeId': scopeId,
      'domain': domain,
      'type': type,
      'recordId': recordId,
      'expectedRevision': expectedRevision,
      'createdByAccountId': session.profile.accountId,
      'recordRestore': {
        'version': 1,
        'tombstoneProofHash': 'a' * 64,
        'previousLiveProofHash': 'b' * 64,
      },
    };
  }
}

void main() {
  Future<
    ({
      CollaborationRepository repo,
      FakeServer server,
      String scope,
      String task,
    })
  >
  setup({CryptoDomainRouter? router}) async {
    final server = FakeServer();
    final repo = CollaborationRepository(
      CollaborationDatabase(NativeDatabase.memory()),
      FakeTransport(server),
      MemorySessionStore(),
      contentRouteGuard: const SyntheticContentRouteGuard(),
      cryptoRouter: router ?? _LegacyRouter(),
    );
    addTearDown(repo.close);
    await repo.initialize();
    await repo.login(
      serverUrl: 'https://example.test/',
      username: 'alice',
      password: 'synthetic',
    );
    final scope = await repo.createScope('Merge');
    final task = await repo.createTask(
      scopeId: scope,
      title: 'Task',
      notes: 'Base',
    );
    await repo.syncNow();
    expect(repo.state.lastError, isNull);
    return (repo: repo, server: server, scope: scope, task: task);
  }

  void remote(
    FakeServer server,
    String scope,
    String id,
    Map<String, dynamic> change,
  ) {
    final old = server.records[scope]![id]!;
    server.records[scope]![id] = {
      ...old,
      'revision': (old['revision'] as int) + 1,
      'sequence': server.sequence[scope] = server.sequence[scope]! + 1,
      'payload': {...old['payload'] as Map<String, dynamic>, ...change},
    };
  }

  Future<void> deletionConflict(dynamic f) async {
    final CollaborationRepository repo = f.repo;
    final task = repo.state.data[f.scope]!.tasks.single;
    await repo.updateTask(f.scope, task.copyWith(notes: 'Local draft'));
    remote(f.server, f.scope, f.task, {});
    f.server.records[f.scope]![f.task]!.addAll({
      'deleted': true,
      'payload': null,
      'createdByAccountId': repo.state.session!.accountId,
    });
    f.server.scopes[f.scope]!['recordPolicyVersion'] = 1;
    await repo.syncNow();
    final p = repo.state.session!.partition;
    await repo.database.execute(
      'INSERT INTO crypto_business_records(partition,scope_id,domain,id,type,crypto_revision,record_proof_hash,deleted,raw_payload,projection,history_basis) VALUES(?,?,?,?,?,?,?,?,?,?,?)',
      [
        p,
        f.scope,
        'content',
        'synthetic-wire-id',
        'task',
        2,
        'a' * 64,
        1,
        null,
        jsonEncode({'id': f.task, 'revision': 2}),
        'verifiedCheckpoint',
      ],
    );
    expect(repo.state.conflicts.single.remoteDeleted, isTrue);
  }

  test(
    'explicit restore repo preserves original draft and durably binds new intent',
    () async {
      final router = _RestoreRouter();
      final f = await setup(router: router);
      await deletionConflict(f);
      final p = f.repo.state.session!.partition;
      final old = (await f.repo.database.rows(
        'SELECT * FROM outbox WHERE partition=? AND record_id=?',
        [p, f.task],
      )).single;
      final conflict = f.repo.state.conflicts.single;
      expect(conflict.createdByAccountId, f.repo.state.session!.accountId);
      await f.repo.resolveConflict(conflictId: conflict.id, keepLocal: true);
      expect(router.preparations, 1);
      final current = (await f.repo.database.rows(
        'SELECT * FROM outbox WHERE partition=? AND record_id=?',
        [p, f.task],
      )).single;
      expect(current['op_id'], isNot(old['op_id']));
      final archive = (await f.repo.database.rows(
        'SELECT value FROM local_meta WHERE name=?',
        ['record_resolved_op:$p:${old['op_id']}'],
      )).single;
      expect(
        (jsonDecode(archive['value'] as String) as Map)['request'],
        old['request'],
      );
      final marker = (await f.repo.database.rows(
        'SELECT value FROM local_meta WHERE name=?',
        ['record_restore_intent:$p:${current['op_id']}'],
      )).single;
      final binding = jsonDecode(marker['value'] as String) as Map;
      expect(binding['recordRestore'], {
        'version': 1,
        'tombstoneProofHash': 'a' * 64,
        'previousLiveProofHash': 'b' * 64,
      });
      expect(binding['expectedRevision'], 2);
      expect(f.repo.state.data[f.scope]!.tasks.single.notes, 'Local draft');
      expect(f.server.records[f.scope]![f.task]!['deleted'], isTrue);
    },
  );

  test(
    'explicit restore repo rejects changed proof before archive or queue replacement',
    () async {
      final router = _RestoreRouter();
      final f = await setup(router: router);
      await deletionConflict(f);
      final p = f.repo.state.session!.partition;
      final old = (await f.repo.database.rows(
        'SELECT request FROM outbox WHERE partition=? AND record_id=?',
        [p, f.task],
      )).single['request'];
      router.beforeResult = () => f.repo.database.execute(
        "UPDATE crypto_business_records SET record_proof_hash=? WHERE partition=? AND scope_id=?",
        ['c' * 64, p, f.scope],
      );
      await expectLater(
        f.repo.resolveConflict(
          conflictId: f.repo.state.conflicts.single.id,
          keepLocal: true,
        ),
        throwsA(
          isA<CollaborationException>().having(
            (e) => e.code,
            'code',
            'stale_edit',
          ),
        ),
      );
      expect(
        (await f.repo.database.rows(
          'SELECT request FROM outbox WHERE partition=? AND record_id=?',
          [p, f.task],
        )).single['request'],
        old,
      );
      expect(
        await f.repo.database.rows(
          "SELECT name FROM local_meta WHERE name LIKE 'record_restore_intent:%' OR name LIKE 'record_resolved_op:%'",
        ),
        isEmpty,
      );
    },
  );

  test(
    'explicit restore repo paired deletion remains pending without partial effects',
    () async {
      final router = _RestoreRouter();
      final f = await setup(router: router);
      await deletionConflict(f);
      final p = f.repo.state.session!.partition,
          conflict = f.repo.state.conflicts.single;
      await f.repo.database.execute(
        'INSERT INTO local_meta(name,value) VALUES(?,?)',
        ['task_cost_pair:$p:${conflict.id}', 'synthetic-finance-op'],
      );
      final old = (await f.repo.database.rows(
        'SELECT request FROM outbox WHERE partition=? AND record_id=?',
        [p, f.task],
      )).single['request'];
      await expectLater(
        f.repo.resolveConflict(conflictId: conflict.id, keepLocal: true),
        throwsA(
          isA<CollaborationException>().having(
            (e) => e.code,
            'code',
            'crypto_record_restore_paired_pending',
          ),
        ),
      );
      expect(router.preparations, 0);
      expect(
        (await f.repo.database.rows(
          'SELECT request FROM outbox WHERE partition=? AND record_id=?',
          [p, f.task],
        )).single['request'],
        old,
      );
      expect(
        await f.repo.database.rows(
          "SELECT name FROM local_meta WHERE name LIKE 'record_restore_intent:%' OR name LIKE 'record_resolved_op:%'",
        ),
        isEmpty,
      );
    },
  );

  test(
    'independent task fields create fresh successor and archive original exact intent',
    () async {
      final f = await setup();
      final t = f.repo.state.data[f.scope]!.tasks.single;
      await f.repo.updateTask(f.scope, t.copyWith(notes: 'Local'));
      final original = (await f.repo.database.rows(
        'SELECT * FROM outbox',
      )).single;
      remote(f.server, f.scope, f.task, {'title': 'Remote'});
      await f.repo.syncNow();
      expect(f.repo.state.lastError, isNull);
      expect(f.repo.state.data[f.scope]!.tasks.single.notes, 'Local');
      expect(f.repo.state.data[f.scope]!.tasks.single.title, 'Remote');
      expect(f.repo.state.conflicts, isEmpty);
      expect((await f.repo.syncWork()).unresolved, isFalse);
      final archived = await f.repo.database.rows(
        'SELECT value FROM local_meta WHERE name=?',
        [
          'record_rebased_op:${f.repo.state.session!.partition}:${original['op_id']}',
        ],
      );
      expect(archived, hasLength(1));
      expect(
        (jsonDecode(archived.single['value'] as String) as Map)['request'],
        original['request'],
      );
      expect(f.server.records[f.scope]![f.task]!['revision'], 3);
      expect(f.server.replay.keys, isNot(contains(original['op_id'])));
    },
  );
  test(
    'opposing task field preserves both versions and independent second task delivers',
    () async {
      final f = await setup();
      final t = f.repo.state.data[f.scope]!.tasks.single;
      await f.repo.updateTask(f.scope, t.copyWith(notes: 'Local'));
      final another = await f.repo.createTask(
        scopeId: f.scope,
        title: 'Independent',
      );
      remote(f.server, f.scope, f.task, {'notes': 'Remote'});
      await f.repo.syncNow();
      expect(f.repo.state.lastError, isNull);
      expect(f.repo.state.conflicts, hasLength(1));
      expect(f.repo.state.conflicts.single.localPayload!['notes'], 'Local');
      expect(f.repo.state.conflicts.single.remotePayload!['notes'], 'Remote');
      expect(f.server.records[f.scope]!.containsKey(another), isTrue);
    },
  );
  test(
    'equal edits accept canonical without extra successor revision',
    () async {
      final f = await setup();
      final t = f.repo.state.data[f.scope]!.tasks.single;
      await f.repo.updateTask(f.scope, t.copyWith(notes: 'Same'));
      remote(f.server, f.scope, f.task, {'notes': 'Same'});
      await f.repo.syncNow();
      expect(f.repo.state.conflicts, isEmpty);
      expect((await f.repo.syncWork()).unresolved, isFalse);
      expect(f.server.records[f.scope]![f.task]!['revision'], 2);
    },
  );
  test(
    'remote deletion retains local draft and never recreates deleted record',
    () async {
      final f = await setup();
      final t = f.repo.state.data[f.scope]!.tasks.single;
      await f.repo.updateTask(f.scope, t.copyWith(notes: 'Local'));
      remote(f.server, f.scope, f.task, {});
      f.server.records[f.scope]![f.task]!.addAll({
        'deleted': true,
        'payload': null,
      });
      await f.repo.syncNow();
      expect(f.repo.state.conflicts, hasLength(1));
      expect(f.repo.state.conflicts.single.remoteDeleted, isTrue);
      expect(f.repo.state.data[f.scope]!.tasks.single.notes, 'Local');
      expect(f.server.records[f.scope]![f.task]!['deleted'], isTrue);
    },
  );
  test(
    'new queued edits bind contiguous revisions to same accepted base',
    () async {
      final f = await setup();
      var t = f.repo.state.data[f.scope]!.tasks.single;
      await f.repo.updateTask(f.scope, t.copyWith(notes: 'First'));
      t = f.repo.state.data[f.scope]!.tasks.single;
      await f.repo.updateTask(f.scope, t.copyWith(notes: 'Final'));
      remote(f.server, f.scope, f.task, {'title': 'Remote'});
      await f.repo.syncNow();
      expect(f.repo.state.lastError, isNull);
      expect(f.repo.state.conflicts, isEmpty);
      expect(f.repo.state.data[f.scope]!.tasks.single.notes, 'Final');
      expect(f.repo.state.data[f.scope]!.tasks.single.title, 'Remote');
      expect((await f.repo.syncWork()).unresolved, isFalse);
    },
  );
  test(
    'new malformed base revision never authorizes automatic replacement',
    () async {
      final f = await setup();
      final t = f.repo.state.data[f.scope]!.tasks.single;
      await f.repo.updateTask(f.scope, t.copyWith(notes: 'Local'));
      final p = f.repo.state.session!.partition;
      final original = (await f.repo.database.rows(
        'SELECT op_id,request FROM outbox',
      )).single;
      final key = 'record_op_base:$p:${original['op_id']}';
      final stored = (await f.repo.database.rows(
        'SELECT value FROM local_meta WHERE name=?',
        [key],
      )).single;
      final base = Map<String, dynamic>.from(
        jsonDecode(stored['value'] as String) as Map,
      )..['serverRevision'] = 99;
      await f.repo.database.execute(
        'UPDATE local_meta SET value=? WHERE name=?',
        [jsonEncode(base), key],
      );
      remote(f.server, f.scope, f.task, {'title': 'Remote'});
      await f.repo.syncNow();
      expect(f.repo.state.conflicts, hasLength(1));
      expect(
        (await f.repo.database.rows('SELECT op_id,request FROM outbox')).single,
        original,
      );
    },
  );
}
