import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/data/collaboration_transport.dart';
import 'package:kanban/organizer/data/e2ee/crypto_domain_router.dart';
import 'package:kanban/organizer/data/device_session_store.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:kanban/organizer/presentation/shared/sharing_status_projection.dart';

import '../support/synthetic_content_route_guard.dart';
import 'collaboration_repository_test.dart'
    show FakeServer, FakeTransport, MemorySessionStore;

class _StatusDatabase extends CollaborationDatabase {
  _StatusDatabase(super.executor);
  final reads = <String>[];
  @override
  Future<List<Map<String, dynamic>>> rows(
    String sql, [
    List<Object?> args = const [],
  ]) {
    reads.add(sql);
    return super.rows(sql, args);
  }
}

class _Router implements CryptoDomainRouter {
  @override
  Future<Map<String, dynamic>> dispatch({
    required DeviceSession session,
    required String operation,
    required Map<String, Object?> params,
    required Set<String> protectedScopeIds,
  }) async => throw StateError('Unexpected crypto dispatch');
}

class _Transport extends FakeTransport {
  _Transport(super.server, this.store);
  final MemorySessionStore store;
  final operations = <String>[];
  CollaborationApiException? failure;
  bool wrongIdentity = false;
  String? hintScope;
  Completer<void>? held, started;
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
    operations.add(operation);
    if (operation == 'account.changes') {
      final profile = store.value!.profile;
      started?.complete();
      await held?.future;
      if (failure != null) throw failure!;
      final reset = params['cursor'] == null;
      return {
        'version': 1,
        'serverId': profile.serverId,
        'accountId': wrongIdentity ? 'other' : profile.accountId,
        'deviceId': profile.deviceId,
        'cursor': 'check-status-snapshot',
        'changed': reset || hintScope != null,
        'resetRequired': reset,
        'hasMore': false,
        'accountDomains': <String>[],
        'scopes': [
          if (hintScope != null)
            {
              'scopeId': hintScope,
              'domains': ['content'],
            },
        ],
      };
    }
    final reply = await super.call(
      serverUrl: serverUrl,
      operation: operation,
      params: params,
      token: token,
      allowLocalHttp: allowLocalHttp,
    );
    return operation == 'capabilities'
        ? {
            ...reply,
            'accountChangeVersions': [1],
            'accountChanges': true,
          }
        : reply;
  }
}

void main() {
  late Directory directory;
  late CollaborationRepository repo;
  late MemorySessionStore store;
  late _Transport transport;
  late DateTime now;
  late String scope;
  CollaborationRepository open() => CollaborationRepository(
    _StatusDatabase(NativeDatabase(File('${directory.path}/status.sqlite'))),
    transport,
    store,
    clock: () => now,
    contentRouteGuard: const SyntheticContentRouteGuard(),
    cryptoRouter: _Router(),
  );
  SharingSyncStatus status() =>
      SharingStatusProjection.fromState(repo.state, now: now).status;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('change-check-status-');
    store = MemorySessionStore();
    transport = _Transport(FakeServer(), store);
    now = DateTime.utc(2026, 10, 27, 9);
    repo = open();
    await repo.initialize();
    await repo.login(
      serverUrl: 'https://synthetic.invalid/',
      username: 'alice',
      password: 'synthetic',
    );
    scope = await repo.createScope('Check status');
    await repo.syncNow();
    await repo.close();
    now = now.add(const Duration(minutes: 1));
    repo = open();
    await repo.initialize();
    transport.operations.clear();
  });
  tearDown(() async {
    await repo.close();
    await directory.delete(recursive: true);
  });

  test(
    'cold reopen unchanged records successful check without manufacturing a transfer',
    () async {
      expect(repo.state.lastSyncAttemptAt, isNull);
      expect(repo.state.lastSuccessfulSyncAt, isNull);
      expect(status(), SharingSyncStatus.unknown);
      final data = repo.state.data[scope];
      await repo.syncNow();
      expect(
        transport.operations.where((o) => o == 'account.changes'),
        hasLength(1),
      );
      expect(transport.operations.where((o) => o.endsWith('.pull')), isEmpty);
      expect(repo.lastSyncCompletion, isNull);
      expect(repo.state.lastChangeCheckAttemptAt, now);
      expect(repo.state.lastSuccessfulChangeCheckAt, now);
      expect(repo.state.lastSyncAttemptAt, isNull);
      expect(repo.state.lastSuccessfulSyncAt, isNull);
      expect(identical(repo.state.data[scope], data), isTrue);
      expect(status(), SharingSyncStatus.checked);
    },
  );

  test(
    'failed check keeps its own previous success and never claims a sync attempt',
    () async {
      await repo.syncNow();
      final checked = now;
      now = now.add(const Duration(minutes: 1));
      transport.failure = const CollaborationApiException('network');
      await expectLater(repo.syncNow(), throwsA(isA<CollaborationException>()));
      expect(repo.state.lastChangeCheckAttemptAt, now);
      expect(repo.state.lastSuccessfulChangeCheckAt, checked);
      expect(repo.state.lastSyncAttemptAt, isNull);
      expect(status(), SharingSyncStatus.offline);
      transport.failure = null;
      now = now.add(const Duration(minutes: 1));
      await repo.syncNow();
      expect(repo.state.lastSuccessfulChangeCheckAt, now);
      expect(repo.state.lastError, isNull);
      expect(status(), SharingSyncStatus.checked);
    },
  );

  test('invalid account identity cannot publish successful check', () async {
    transport.wrongIdentity = true;
    await expectLater(repo.syncNow(), throwsA(isA<FormatException>()));
    expect(repo.state.lastChangeCheckAttemptAt, now);
    expect(repo.state.lastSuccessfulChangeCheckAt, isNull);
    expect(repo.state.lastSuccessfulSyncAt, isNull);
    expect(status(), SharingSyncStatus.problem);
  });

  test(
    'cold reconciliation debt for undiscovered scope cannot become confirmed',
    () async {
      final partition = repo.state.session!.partition;
      await repo.database.execute(
        'INSERT INTO local_meta(name,value) VALUES(?,?)',
        [
          'scope_reconciliation:$partition:10000000-0000-4000-8000-000000000099',
          'crypto_pending',
        ],
      );
      await repo.syncNow();
      expect(repo.state.lastSuccessfulChangeCheckAt, now);
      expect(repo.state.syncRequiresRefresh, isTrue);
      expect(status(), SharingSyncStatus.unknown);
    },
  );

  test(
    'session switch during held check cannot publish previous account evidence',
    () async {
      transport.started = Completer<void>();
      transport.held = Completer<void>();
      final pending = repo.syncNow();
      final failure = expectLater(
        pending,
        throwsA(isA<CollaborationException>()),
      );
      await transport.started!.future;
      await repo.signOut();
      transport.held!.complete();
      await failure;
      expect(repo.state.session, isNull);
      expect(repo.state.lastChangeCheckAttemptAt, isNull);
      expect(repo.state.lastSuccessfulChangeCheckAt, isNull);
    },
  );
  test(
    'selected content with occupied lease remains unconfirmed despite successful check',
    () async {
      await repo.syncNow(); // Complete the independent startup access review.
      now = now.add(const Duration(minutes: 1));
      transport.operations.clear();
      transport.hintScope = scope;
      await repo.database.execute(
        'INSERT INTO sync_leases(partition,owner,expires_at) VALUES(?,?,?)',
        [
          repo.state.session!.partition,
          'other-worker',
          now.add(const Duration(minutes: 1)).millisecondsSinceEpoch,
        ],
      );
      await repo.syncNow();
      expect(repo.state.lastSuccessfulChangeCheckAt, now);
      expect(repo.state.lastSuccessfulSyncAt, isNull);
      expect(repo.state.syncRequiresRefresh, isTrue);
      expect(status(), SharingSyncStatus.unknown);
      expect(transport.operations.where((o) => o.endsWith('.pull')), isEmpty);
    },
  );

  test(
    'blocked immutable crypto work remains pending without changing payload',
    () async {
      final partition = repo.state.session!.partition;
      await repo.database.execute(
        'INSERT INTO crypto_outbox(partition,request_id,operation,signed_body,request_hash,state) VALUES(?,?,?,?,?,?)',
        [
          partition,
          'synthetic-request',
          'crypto2.records.batch',
          'immutable-synthetic-body',
          'synthetic-hash',
          'blocked',
        ],
      );
      await repo.syncNow();
      expect(repo.state.lastSuccessfulChangeCheckAt, now);
      expect(repo.state.hasUnresolvedSyncWork, isTrue);
      expect(status(), SharingSyncStatus.pending);
      expect(
        (await repo.database.rows(
          'SELECT signed_body,state FROM crypto_outbox',
        )).single,
        {'signed_body': 'immutable-synthetic-body', 'state': 'blocked'},
      );
    },
  );

  test(
    'finance readiness follows readable snapshots and ignores denied finance',
    () async {
      final partition = repo.state.session!.partition;
      final caps =
          jsonDecode(
                (await repo.database.rows(
                      'SELECT value FROM local_meta WHERE name=?',
                      ['capabilities:$partition'],
                    )).single['value']
                    as String,
              )
              as Map<String, dynamic>;
      caps['features'] = {...caps['features'] as Map, 'finance': true};
      await repo.database.execute(
        'UPDATE local_meta SET value=? WHERE name=?',
        [jsonEncode(caps), 'capabilities:$partition'],
      );
      await repo.database.execute(
        'UPDATE scopes SET finance_complete=0,finance_policy=? WHERE partition=? AND id=?',
        [
          jsonEncode(
            const SharedFinancePolicy(
              enabled: true,
              grant: SharedFinanceGrant.read,
            ).toJson(),
          ),
          partition,
          scope,
        ],
      );
      await repo.close();
      repo = open();
      await repo.initialize();
      expect(repo.state.syncRequiresRefresh, isTrue);
      await repo.database.execute(
        'UPDATE scopes SET finance_complete=1 WHERE partition=? AND id=?',
        [partition, scope],
      );
      await repo.refreshLocal(scopeIds: const {});
      expect(repo.state.syncRequiresRefresh, isFalse);
      await repo.database.execute(
        'UPDATE scopes SET finance_complete=0,finance_policy=? WHERE partition=? AND id=?',
        [
          jsonEncode(const SharedFinancePolicy(enabled: true).toJson()),
          partition,
          scope,
        ],
      );
      await repo.refreshLocal(scopeIds: const {});
      expect(repo.state.syncRequiresRefresh, isFalse);
    },
  );
  test(
    'indicator uses bounded presence and excludes retained payment history and foreign work',
    () async {
      final partition = repo.state.session!.partition;
      for (final item in [
        ('done', 'complete', partition),
        ('local', 'local_only', partition),
        ('foreign', 'pending', 'other-partition'),
      ]) {
        await repo.database.execute(
          'INSERT INTO linked_payment_intents(id,state,data) VALUES(?,?,?)',
          [
            item.$1,
            item.$2,
            jsonEncode({'partition': item.$3}),
          ],
        );
      }
      final database = repo.database as _StatusDatabase;
      database.reads.clear();
      await repo.refreshLocal(scopeIds: const {});
      expect(repo.state.hasUnresolvedSyncWork, isFalse);
      final evidenceReads = database.reads
          .where((sql) => sql.contains('crypto_outbox'))
          .toList();
      expect(evidenceReads, hasLength(1));
      expect(evidenceReads.single, contains('EXISTS(SELECT 1'));
      expect(evidenceReads.single, isNot(contains('UNION')));
      expect(evidenceReads.single, isNot(contains('ORDER BY')));
      expect(evidenceReads.single, isNot(contains('signed_body')));
      await repo.database.execute(
        'INSERT INTO linked_payment_intents(id,state,data) VALUES(?,?,?)',
        ['legacy', 'quarantine', '{}'],
      );
      await repo.refreshLocal(scopeIds: const {});
      expect(repo.state.hasUnresolvedSyncWork, isTrue);
    },
  );

  test(
    'reconciliation prefix treats encoded partition percent signs literally',
    () async {
      final partition = repo.state.session!.partition;
      expect(partition, contains('%'));
      final foreign = partition.replaceAll('%', 'x');
      await repo.database.execute(
        'INSERT INTO local_meta(name,value) VALUES(?,?)',
        ['scope_reconciliation:$foreign:foreign-scope', 'crypto_pending'],
      );
      await repo.refreshLocal(scopeIds: const {});
      expect(repo.state.syncRequiresRefresh, isFalse);
      await repo.database.execute(
        'INSERT INTO local_meta(name,value) VALUES(?,?)',
        ['scope_reconciliation:$partition:own-scope', 'crypto_pending'],
      );
      await repo.refreshLocal(scopeIds: const {});
      expect(repo.state.syncRequiresRefresh, isTrue);
    },
  );
  test(
    'second unchanged check publishes evidence without account projection reads or transfer',
    () async {
      await repo.syncNow();
      final before = repo.state;
      final database = repo.database as _StatusDatabase;
      database.reads.clear();
      transport.operations.clear();
      now = now.add(const Duration(minutes: 1));
      var personalChanges = 0;
      final sub = database.personalChanges.stream.listen(
        (_) => personalChanges++,
      );
      addTearDown(sub.cancel);
      await repo.syncNow();
      await Future<void>.delayed(Duration.zero);
      expect(transport.operations, ['account.changes']);
      expect(repo.state.lastSuccessfulChangeCheckAt, now);
      expect(repo.state.lastSuccessfulSyncAt, before.lastSuccessfulSyncAt);
      expect(identical(repo.state.data, before.data), isTrue);
      expect(identical(repo.state.members, before.members), isTrue);
      expect(identical(repo.state.inbox, before.inbox), isTrue);
      expect(identical(repo.state.scopes, before.scopes), isTrue);
      expect(
        identical(
          repo.state.financeAccountChoices,
          before.financeAccountChoices,
        ),
        isTrue,
      );
      expect(
        database.reads.where(
          (sql) =>
              sql.contains('FROM inbox') ||
              sql.contains('FROM members') ||
              sql.contains('FROM notification_preferences') ||
              sql.contains('SELECT * FROM records') ||
              sql.contains('SELECT s.data,s.blocked'),
        ),
        isEmpty,
      );
      expect(personalChanges, 0);
    },
  );
}
