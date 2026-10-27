import 'dart:async';
import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/data/device_session_store.dart';
import 'package:kanban/organizer/data/e2ee/crypto_domain_router.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'collaboration_repository_test.dart'
    show FakeServer, FakeTransport, MemorySessionStore;

// Target reader is an explicit verified-crypto seam. Real repository SQL,
// lease, merge, session/CAS checks run here; this is not signature/HTTP proof.
class _Reader
    implements
        CryptoDomainRouter,
        CryptoAcceptedScopeReader,
        CryptoProjectionCursorTransition {
  _Reader(this.scope);
  Map<String, dynamic> scope;
  CryptoProjectionCursorOrigin origin =
      CryptoProjectionCursorOrigin.nativeOrigin;
  final cursors = <int>[];
  @override
  Future<CryptoProjectionCursorOrigin?> verifyProjectionCursorOrigin({
    required DeviceSession session,
    required String scopeId,
  }) async => origin;
  bool current = true;
  Object? failure;
  Completer<void>? gate, entered, unrelatedGate, unrelatedEntered;
  final targets = <String>[];
  List<Map<String, dynamic>> records = [];
  @override
  Future<CryptoAcceptedScopeRead> prepareAcceptedScope({
    required DeviceSession session,
    required String scopeId,
    required int cursor,
  }) async {
    targets.add(scopeId);
    cursors.add(cursor);
    entered?.complete();
    await gate?.future;
    if (failure != null) throw failure!;
    return CryptoAcceptedScopeRead(
      scope: scope,
      records: records,
      cursor: cursor + records.length,
      isCurrent: () async => current,
    );
  }

  @override
  Future<Map<String, dynamic>> dispatch({
    required DeviceSession session,
    required String operation,
    required Map<String, Object?> params,
    required Set<String> protectedScopeIds,
  }) async {
    if (operation == 'scopes.list' && unrelatedGate != null) {
      unrelatedEntered!.complete();
      await unrelatedGate!.future;
      throw const CollaborationException('network');
    }
    throw StateError('unexpected encrypted dispatch $operation');
  }
}

class _Fixture {
  _Fixture(this.repo, this.reader, this.p, this.id);
  final CollaborationRepository repo;
  final _Reader reader;
  final String p, id;
}

Future<_Fixture> _fixture() async {
  final server = FakeServer()..moderationSupported = false;
  final id = newSharedId();
  final profile = AccountSession(
    serverUrl: 'https://example.test/',
    serverId: server.serverId,
    accountId: server.accountIds['alice']!,
    userId: 1,
    username: 'alice',
    displayName: 'A',
    deviceId: newSharedId(),
    expiresAt: DateTime.utc(2030),
  );
  final store = MemorySessionStore()..value = DeviceSession(profile, 'token');
  server.tokens['token'] = 'alice';
  final scope = SharedScope(
    id: id,
    name: 'Accepted',
    kind: SharedScopeKind.household,
    role: SharedRole.member,
    accessPolicyVersion: 1,
    sequence: 3,
    metadataRevision: 1,
  ).toJson();
  final reader = _Reader(Map.from(scope));
  final db = CollaborationDatabase(NativeDatabase.memory());
  await db.rows('SELECT name FROM local_meta LIMIT 1');
  await db.execute('INSERT INTO accounts(partition,profile) VALUES(?,?)', [
    profile.partition,
    jsonEncode(profile.toJson()),
  ]);
  final repo = CollaborationRepository(
    db,
    FakeTransport(server),
    store,
    cryptoRouter: reader,
  );
  addTearDown(repo.close);
  await repo.initialize();
  await db.execute('INSERT INTO local_meta(name,value) VALUES(?,?)', [
    'account_changes_v1:${profile.partition}:${profile.deviceId}',
    'retained-account-cursor',
  ]);
  return _Fixture(repo, reader, profile.partition, id);
}

Future<List<Map<String, Object?>>> _scopes(_Fixture f) =>
    f.repo.database.rows('SELECT * FROM scopes WHERE partition=?', [f.p]);
void main() {
  test(
    'accepted target selects while unrelated coordinator remains blocked and keeps its lease/cursor',
    () async {
      final f = await _fixture();
      f.reader.unrelatedGate = Completer<void>();
      f.reader.unrelatedEntered = Completer<void>();
      final work = f.repo.syncNow();
      final failed = expectLater(work, throwsA(isA<CollaborationException>()));
      await f.reader.unrelatedEntered!.future;
      final lease = await f.repo.database.rows(
        'SELECT owner FROM sync_leases WHERE partition=?',
        [f.p],
      );
      await f.repo.prepareAcceptedScope(f.id);
      await f.repo.selectSpace(f.id);
      expect(f.repo.state.selectedSpaceId, f.id);
      expect(
        await f.repo.database.rows(
          'SELECT owner FROM sync_leases WHERE partition=?',
          [f.p],
        ),
        lease,
      );
      expect(f.repo.lastSyncCompletion, isNull);
      expect(
        (await f.repo.database.rows(
          'SELECT finance_complete FROM scopes WHERE id=?',
          [f.id],
        )).single['finance_complete'],
        0,
      );
      expect(
        await f.repo.database.rows(
          "SELECT value FROM local_meta WHERE name LIKE 'account_changes_v1:%'",
        ),
        [
          {'value': 'retained-account-cursor'},
        ],
      );
      expect(f.reader.targets, [f.id]);
      f.reader.unrelatedGate!.complete();
      await failed;
      expect(f.repo.state.selectedSpaceId, f.id);
    },
  );
  test(
    'target pending content/key error leaves scope and selection absent',
    () async {
      final f = await _fixture();
      f.reader.failure = const CollaborationException(
        'crypto_reconciliation_required',
      );
      await expectLater(
        f.repo.prepareAcceptedScope(f.id),
        throwsA(isA<CollaborationException>()),
      );
      expect(await _scopes(f), isEmpty);
      expect(f.repo.state.selectedSpaceId, isNull);
    },
  );
  for (final invalid in [
    'metadata',
    'blocked',
    'revoked',
    'deleted',
    'policy',
  ]) {
    test(
      'accepted target refuses $invalid projection before local application',
      () async {
        final f = await _fixture();
        f.reader.scope = {
          ...f.reader.scope,
          if (invalid == 'metadata') 'metadataRevision': 0,
          if (invalid == 'blocked') 'blocked': true,
          if (invalid == 'revoked') 'revoked': true,
          if (invalid == 'deleted') 'deleted': true,
          if (invalid == 'policy') 'accessPolicyVersion': 99,
        };
        await expectLater(
          f.repo.prepareAcceptedScope(f.id),
          throwsA(isA<CollaborationException>()),
        );
        expect(await _scopes(f), isEmpty);
      },
    );
  }
  test('late target after session signout cannot install or select', () async {
    final f = await _fixture();
    f.reader.gate = Completer<void>();
    f.reader.entered = Completer<void>();
    final pending = f.repo.prepareAcceptedScope(f.id);
    final rejected = expectLater(
      pending,
      throwsA(isA<CollaborationException>()),
    );
    await f.reader.entered!.future;
    await f.repo.signOut();
    f.reader.gate!.complete();
    await rejected;
    expect(await _scopes(f), isEmpty);
    expect(f.repo.state.session, isNull);
  });
  test(
    'concurrent confirmed revoke cannot be overwritten by late target',
    () async {
      final f = await _fixture();
      f.reader.gate = Completer<void>();
      f.reader.entered = Completer<void>();
      final pending = f.repo.prepareAcceptedScope(f.id);
      final rejected = expectLater(
        pending,
        throwsA(isA<CollaborationException>()),
      );
      await f.reader.entered!.future;
      await f.repo.database.execute(
        'INSERT INTO scopes(partition,id,data,blocked) VALUES(?,?,?,1)',
        [
          f.p,
          f.id,
          jsonEncode({...f.reader.scope, 'revoked': true}),
        ],
      );
      final denied = await _scopes(f);
      f.reader.gate!.complete();
      await rejected;
      expect(await _scopes(f), denied);
    },
  );
  test(
    'expired authority refuses atomic commit without marking complete',
    () async {
      final f = await _fixture();
      f.reader.current = false;
      await expectLater(
        f.repo.prepareAcceptedScope(f.id),
        throwsA(isA<CollaborationException>()),
      );
      expect(await _scopes(f), isEmpty);
      expect(f.repo.lastSyncCompletion, isNull);
    },
  );
  test('foreign live sync lease is not stolen or released', () async {
    final f = await _fixture();
    await f.repo.database.execute('INSERT INTO sync_leases VALUES(?,?,?)', [
      f.p,
      'other-owner',
      DateTime.now().millisecondsSinceEpoch + 60000,
    ]);
    await expectLater(
      f.repo.prepareAcceptedScope(f.id),
      throwsA(isA<CollaborationException>()),
    );
    expect(await _scopes(f), isEmpty);
    expect(
      (await f.repo.database.rows(
        'SELECT owner FROM sync_leases WHERE partition=?',
        [f.p],
      )).single['owner'],
      'other-owner',
    );
  });
  test(
    'legacy ordinary cursor transitions without skipping encrypted target or altering queued tombstone',
    () async {
      final f = await _fixture();
      f.reader.origin = CryptoProjectionCursorOrigin.legacyMigration;
      await f.repo.database.execute(
        'INSERT INTO scopes(partition,id,data,cursor,finance_cursor,finance_complete) VALUES(?,?,?,999,888,1)',
        [f.p, f.id, jsonEncode(f.reader.scope)],
      );
      final record = newSharedId(), operation = newSharedId();
      await f.repo.database.execute(
        "INSERT INTO records(partition,scope_id,id,type,local_revision,server_revision,payload,deleted) VALUES(?,?,?,'task',4,1,NULL,1)",
        [f.p, f.id, record],
      );
      await f.repo.database.execute(
        "INSERT INTO outbox(op_id,partition,scope_id,record_id,request,state) VALUES(?,?,?,?,?,'blocked')",
        [
          operation,
          f.p,
          f.id,
          record,
          jsonEncode({
            'id': operation,
            'type': 'task',
            'recordId': record,
            'deleted': true,
            'expectedRevision': 1,
            'payload': null,
          }),
        ],
      );
      final original = await f.repo.database.rows('SELECT * FROM outbox');
      f.reader.records = [
        {
          'id': record,
          'type': 'task',
          'revision': 2,
          'deleted': true,
          'payload': null,
        },
      ];
      await f.repo.prepareAcceptedScope(f.id);
      expect(f.reader.cursors, [0]);
      expect(await f.repo.database.rows('SELECT * FROM outbox'), original);
      final row = (await f.repo.database.rows(
        'SELECT deleted,local_revision,server_revision,remote FROM records WHERE id=?',
        [record],
      )).single;
      expect(row['deleted'], 1);
      expect(row['local_revision'], 4);
      expect(jsonDecode(row['remote'] as String)['revision'], 2);
      final scope = (await f.repo.database.rows(
        'SELECT cursor,finance_cursor,finance_complete FROM scopes WHERE id=?',
        [f.id],
      )).single;
      expect(scope, {'cursor': 1, 'finance_cursor': 0, 'finance_complete': 0});
      expect(
        (await f.repo.database.rows(
          "SELECT value FROM local_meta WHERE name LIKE 'crypto_projection_cursor_v1:%'",
        )).map((r) => r['value']),
        everyElement('legacyMigration'),
      );
    },
  );
  test(
    'newfinance27 concurrent finance progress and cursor marker survive late target',
    () async {
      final f = await _fixture();
      f.reader.origin = CryptoProjectionCursorOrigin.legacyMigration;
      await f.repo.database.execute(
        'INSERT INTO scopes(partition,id,data,cursor,finance_cursor,finance_complete) VALUES(?,?,?,999,888,0)',
        [f.p, f.id, jsonEncode(f.reader.scope)],
      );
      f.reader.gate = Completer<void>();
      f.reader.entered = Completer<void>();
      final pending = f.repo.prepareAcceptedScope(f.id);
      final rejected = expectLater(
        pending,
        throwsA(isA<CollaborationException>()),
      );
      await f.reader.entered!.future;
      await f.repo.database.execute(
        'UPDATE scopes SET finance_cursor=1001,finance_access_revision=5,finance_complete=1 WHERE id=?',
        [f.id],
      );
      await f.repo.database.execute(
        'INSERT INTO local_meta(name,value) VALUES(?,?)',
        [
          'crypto_projection_cursor_v1:${f.p}:${f.id}:finance',
          'legacyMigration',
        ],
      );
      final before = await _scopes(f);
      f.reader.gate!.complete();
      await rejected;
      expect(await _scopes(f), before);
      expect(
        (await f.repo.database.rows(
          'SELECT value FROM local_meta WHERE name=?',
          ['crypto_projection_cursor_v1:${f.p}:${f.id}:finance'],
        )).single['value'],
        'legacyMigration',
      );
    },
  );
  test(
    'acceptnewguard27 dirty live candidate and immutable queued request survive remote target preparation',
    () async {
      final f = await _fixture();
      await f.repo.database.execute(
        'INSERT INTO scopes(partition,id,data) VALUES(?,?,?)',
        [f.p, f.id, jsonEncode(f.reader.scope)],
      );
      final record = newSharedId(), operation = newSharedId();
      final local = {
        'title': 'Unsaved local candidate',
        'createdAt': '2026-10-27T10:00:00.000Z',
        'updatedAt': '2026-10-27T10:00:00.000Z',
      };
      await f.repo.database.execute(
        "INSERT INTO records(partition,scope_id,id,type,local_revision,server_revision,payload,deleted) VALUES(?,?,?,'shoppingList',7,1,?,0)",
        [f.p, f.id, record, jsonEncode(local)],
      );
      final request = jsonEncode({
        'id': operation,
        'type': 'shoppingList',
        'recordId': record,
        'deleted': false,
        'expectedRevision': 1,
        'payload': local,
      });
      await f.repo.database.execute(
        "INSERT INTO outbox(op_id,partition,scope_id,record_id,request,state) VALUES(?,?,?,?,?,'pending')",
        [operation, f.p, f.id, record, request],
      );
      final queued = await f.repo.database.rows('SELECT * FROM outbox');
      f.reader.records = [
        {
          'id': record,
          'type': 'shoppingList',
          'revision': 2,
          'deleted': false,
          'payload': {...local, 'title': 'Remote updated'},
        },
      ];
      await f.repo.prepareAcceptedScope(f.id);
      expect(await f.repo.database.rows('SELECT * FROM outbox'), queued);
      final row = (await f.repo.database.rows(
        'SELECT payload,deleted,local_revision,server_revision,remote FROM records WHERE id=?',
        [record],
      )).single;
      expect(row['payload'], jsonEncode(local));
      expect(row['local_revision'], 7);
      expect(row['server_revision'], 2);
      expect(row['deleted'], 0);
      expect(
        jsonDecode(row['remote'] as String)['payload']['title'],
        'Remote updated',
      );
      expect(
        f.repo.state.dataForScope(f.id).shoppingLists.single.title,
        'Unsaved local candidate',
      );
    },
  );
  test(
    'acceptnewguard27 independently installed namespace marker cannot be reset by stale transition',
    () async {
      final f = await _fixture();
      f.reader.origin = CryptoProjectionCursorOrigin.legacyMigration;
      f.reader.gate = Completer<void>();
      f.reader.entered = Completer<void>();
      final pending = f.repo.prepareAcceptedScope(f.id);
      final rejected = expectLater(
        pending,
        throwsA(isA<CollaborationException>()),
      );
      await f.reader.entered!.future;
      await f.repo.database.execute(
        'INSERT INTO local_meta(name,value) VALUES(?,?)',
        ['crypto_projection_cursor_v1:${f.p}:${f.id}:finance', 'nativeOrigin'],
      );
      f.reader.gate!.complete();
      await rejected;
      expect(await _scopes(f), isEmpty);
      expect(
        (await f.repo.database.rows(
          'SELECT value FROM local_meta WHERE name=?',
          ['crypto_projection_cursor_v1:${f.p}:${f.id}:finance'],
        )).single['value'],
        'nativeOrigin',
      );
    },
  );
  test(
    'acceptsessionguard27 persisted revoked device refuses target before crypto reads',
    () async {
      final f = await _fixture();
      await f.repo.database
          .execute('INSERT INTO local_meta(name,value) VALUES(?,?)', [
            'invalid_session:${f.p}:${f.repo.state.session!.deviceId}',
            'device_revoked',
          ]);
      await expectLater(
        f.repo.prepareAcceptedScope(f.id),
        throwsA(
          isA<CollaborationException>().having(
            (e) => e.code,
            'code',
            'device_revoked',
          ),
        ),
      );
      expect(f.reader.targets, isEmpty);
      expect(await _scopes(f), isEmpty);
    },
  );
  test(
    'acceptsessionguard27 deletion starting during target read prevents local commit',
    () async {
      final f = await _fixture();
      f.reader.gate = Completer<void>();
      f.reader.entered = Completer<void>();
      final pending = f.repo.prepareAcceptedScope(f.id);
      final rejected = expectLater(
        pending,
        throwsA(
          isA<CollaborationException>().having(
            (e) => e.code,
            'code',
            'deletion_pending',
          ),
        ),
      );
      await f.reader.entered!.future;
      await f.repo.database.execute(
        'INSERT INTO local_meta(name,value) VALUES(?,?)',
        ['deletion_pending:${f.p}', '1'],
      );
      f.reader.gate!.complete();
      await rejected;
      expect(await _scopes(f), isEmpty);
    },
  );
  test(
    'acceptsessionguard27 newer reconciliation marker is not cleared by late verified result',
    () async {
      final f = await _fixture();
      await f.repo.database.execute(
        'INSERT INTO scopes(partition,id,data) VALUES(?,?,?)',
        [f.p, f.id, jsonEncode(f.reader.scope)],
      );
      f.reader.gate = Completer<void>();
      f.reader.entered = Completer<void>();
      final pending = f.repo.prepareAcceptedScope(f.id);
      final rejected = expectLater(
        pending,
        throwsA(isA<CollaborationException>()),
      );
      await f.reader.entered!.future;
      await f.repo.database.execute(
        'INSERT INTO local_meta(name,value) VALUES(?,?)',
        ['scope_reconciliation:${f.p}:${f.id}', 'crypto_pending'],
      );
      f.reader.gate!.complete();
      await rejected;
      expect(
        (await f.repo.database.rows(
          'SELECT value FROM local_meta WHERE name=?',
          ['scope_reconciliation:${f.p}:${f.id}'],
        )).single['value'],
        'crypto_pending',
      );
    },
  );
  test(
    'acceptrestoreguard27 unresolved restore fence prevents direct target read',
    () async {
      final f = await _fixture();
      await f.repo.database.execute(
        'INSERT INTO crypto_restore_fences(partition,minimum_transport,backup_id,state) VALUES(?,2,?,?)',
        [f.p, 'retained-backup', 'requires_reconciliation'],
      );
      await expectLater(
        f.repo.prepareAcceptedScope(f.id),
        throwsA(
          isA<CollaborationException>().having(
            (e) => e.code,
            'code',
            'crypto_reconciliation_required',
          ),
        ),
      );
      expect(f.reader.targets, isEmpty);
      expect(await _scopes(f), isEmpty);
    },
  );
}
