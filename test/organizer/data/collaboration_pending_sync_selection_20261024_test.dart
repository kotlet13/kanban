import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart' show Sha256;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sodium/sodium.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/data/collaboration_transport.dart';
import 'package:kanban/organizer/data/collaboration_pending_sync_selection.dart';
import 'package:kanban/organizer/data/collaboration_sync_diagnostics.dart';
import 'package:kanban/organizer/data/device_session_store.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_store.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_v2_workflow.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_repository.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_v2.dart';
import 'package:kanban/organizer/data/e2ee/crypto_business_addresses.dart';
import 'package:kanban/organizer/data/e2ee/crypto_business_json.dart';
import 'package:kanban/organizer/data/e2ee/crypto_business_router.dart';
import 'package:kanban/organizer/data/e2ee/crypto_codec.dart';
import 'package:kanban/organizer/data/e2ee/crypto_domain_router.dart';
import 'package:kanban/organizer/data/e2ee/crypto_identity_store.dart';
import 'package:kanban/organizer/data/e2ee/crypto_json.dart';
import 'package:kanban/organizer/data/e2ee/crypto_record_address.dart';
import 'package:kanban/organizer/data/e2ee/crypto_sync_repository.dart';
import 'package:kanban/organizer/data/e2ee/session_crypto_access.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import '../support/synthetic_content_route_guard.dart';
import 'collaboration_repository_test.dart'
    show FakeServer, FakeTransport, MemorySessionStore;

// Structural selectors do not establish signatures/authority. The mock queue
// below deliberately supplies delivery/projection, while the production
// CryptoBusinessSession.push -> _writeRaw exact saved-intent route runs intact.
Future<String> _hash(List<int> bytes) async => (await Sha256().hash(
  bytes,
)).bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
Map<String, dynamic> _proof(Map<String, dynamic> body) => {
  'commandBase64': base64Encode(CryptoJson.encode(body)),
  'signatureBase64': base64Encode(Uint8List(64)),
};

class _Secure implements AccountCryptoStore {
  @override
  Future<String?> read(String key) async => null;
  @override
  Future<void> write(String key, String value) async {}
}

class _Access implements SessionCryptoAccess {
  @override
  Future<CryptoReadContext> readContext(String scopeId, String domain) async =>
      const CryptoReadContext(
        epoch: 1,
        accessRevision: 1,
        headHash: 'synthetic',
      );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Queue implements CryptoSyncRepository {
  _Queue(this.f);
  final _Fixture f;
  final resumed = <Set<String>?>[];
  @override
  Future<void> resumeUnresolved({Set<String>? requestIds}) async {
    resumed.add(requestIds);
    expect(requestIds, {f.requestId});
    final stored = (await f.db.rows(
      'SELECT * FROM crypto_outbox WHERE request_id=?',
      [f.requestId],
    )).single;
    expect(stored['signed_body'], f.savedBody);
    expect(stored['request_hash'], f.savedHash);
    await f.transport.call(
      serverUrl: f.session.profile.serverUrl,
      operation: 'crypto2.receipt.get',
      params: {'requestId': f.requestId, 'requestHash': f.savedHash},
      token: f.session.token,
    );
    final canonical = await f.server.call('sync.push', {
      'scopeId': f.a,
      'operation': f.operation,
    }, f.session.token);
    final proof = f.proofs.first;
    await f.db.execute(
      'UPDATE crypto_outbox SET state=\'applied\' WHERE request_id=?',
      [f.requestId],
    );
    await f.db.execute(
      '''INSERT OR REPLACE INTO crypto_business_records
      (partition,scope_id,domain,id,type,crypto_revision,legacy_revision,record_proof_hash,deleted,raw_payload,projection,history_basis)
      VALUES(?,?,'content',?,'shoppingList',1,0,?,0,?,?, 'currentEpoch')''',
      [
        f.p,
        f.a,
        f.record['id'],
        await _hash(CryptoJson.encode(proof)),
        jsonEncode(f.operation['payload']),
        jsonEncode(canonical['record']),
      ],
    );
  }

  @override
  Future<void> pull({
    required String scopeId,
    required String domain,
    required int accessRevision,
  }) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Business extends CryptoBusinessSession {
  _Business(super.account, super.access, super.db, this.testQueue);
  final _Queue testQueue;
  @override
  CryptoSyncRepository get queue => testQueue;
}

class _Router implements CryptoDomainRouter {
  _Router(this.f);
  final _Fixture f;
  @override
  Future<Map<String, dynamic>> dispatch({
    required DeviceSession session,
    required String operation,
    required Map<String, Object?> params,
    required Set<String> protectedScopeIds,
  }) {
    if (operation == 'sync.push' && f.business != null) {
      return f.business!.push(params['scopeId'] as String, 'content', params);
    }
    return f.transport.call(
      serverUrl: session.profile.serverUrl,
      operation: operation,
      params: params,
      token: session.token,
    );
  }
}

class _Transport extends FakeTransport {
  _Transport(super.server, this.sessions);
  final MemorySessionStore sessions;
  final calls = <({String operation, Map<String, Object?> params})>[];
  String? financeScope;
  final financeId = newSharedId();
  Map<String, List<String>> hints = {};
  Future<void> Function(String, Map<String, Object?>)? before;
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
    calls.add((operation: operation, params: params));
    await before?.call(operation, params);
    if (operation == 'account.changes') {
      final p = sessions.value!.profile;
      final reset = params['cursor'] == null;
      return {
        'version': 1,
        'directoryHintsVersion': 1,
        'serverId': p.serverId,
        'accountId': p.accountId,
        'deviceId': p.deviceId,
        'cursor': 'next',
        'changed': reset || hints.isNotEmpty,
        'resetRequired': reset,
        'hasMore': false,
        'accountDomains': <String>[],
        'scopes': [
          for (final e in hints.entries) {'scopeId': e.key, 'domains': e.value},
        ],
      };
    }
    if (operation == 'finance.policy') {
      return {'enabled': true, 'grant': 'read', 'revision': 1};
    }
    if (operation == 'finance.pull') {
      final now = DateTime.utc(2026, 10, 24);
      return {
        'records': [
          if (params['scopeId'] == financeScope && params['cursor'] == 0)
            {
              'id': financeId,
              'type': 'financeAccount',
              'revision': 1,
              'deleted': false,
              'payload': SharedFinanceAccount(
                id: financeId,
                createdAt: now,
                updatedAt: now,
                name: 'Unrelated ledger',
                currency: 'EUR',
              ).toPayload(),
              'sequence': 1,
              'updatedAt': now.toIso8601String(),
            },
        ],
        'cursor': 1,
        'hasMore': false,
        'accessRevision': 1,
      };
    }
    if (operation == 'crypto2.receipt.get') {
      return {'outcome': 'mock_delivery'};
    }
    final result = await super.call(
      serverUrl: serverUrl,
      operation: operation,
      params: params,
      token: token,
      allowLocalHttp: allowLocalHttp,
    );
    return operation == 'capabilities'
        ? {
            ...result,
            'accountChangeVersions': [1],
            'financeContractVersions': [1],
            'features': <String, dynamic>{
              ...result['features'] as Map,
              'finance': true,
            },
          }
        : result;
  }
}

class _Fixture {
  final server = FakeServer(), sessions = MemorySessionStore();
  late final db = CollaborationDatabase(NativeDatabase.memory());
  late final transport = _Transport(server, sessions);
  final diagnostics = CollaborationSyncDiagnostics();
  late final repo = CollaborationRepository(
    db,
    transport,
    sessions,
    contentRouteGuard: const SyntheticContentRouteGuard(),
    cryptoRouter: _Router(this),
    syncDiagnostics: diagnostics,
  );
  late String a, b, c, d, id, requestId, savedBody, savedHash;
  late Map<String, dynamic> operation, record;
  late List<Map<String, dynamic>> proofs;
  _Business? business;
  _Queue? queue;
  DeviceSession get session => sessions.value!;
  String get p => session.profile.partition;
  Future<void> initialize() async {
    await repo.initialize();
    await repo.login(
      serverUrl: 'https://synthetic.invalid/',
      username: 'alice',
      password: 'synthetic',
    );
    a = await repo.createScope('Affected');
    b = await repo.createScope('Unrelated');
    c = await repo.createScope('Remote hint');
    d = await repo.createScope('Local work');
    transport.financeScope = b;
    await repo.syncNow();
    expect(repo.state.lastError, isNull, reason: 'fixture baseline');
    expect(
      repo.state.dataForScope(b).financeAccounts.single.name,
      'Unrelated ledger',
    );
    id = await repo.createShoppingList(scopeId: a, title: 'New pending list');
    operation =
        jsonDecode(
              (await db.rows(
                    'SELECT request FROM outbox WHERE partition=? AND scope_id=?',
                    [p, a],
                  )).single['request']
                  as String,
            )
            as Map<String, dynamic>;
    requestId = newSharedId();
    final address = CryptoRecordAddress.forType(
      serverId: session.profile.serverId,
      scopeId: a,
      type: 'shoppingList',
      canonicalId: id,
    );
    record = {
      'version': 2,
      'operation': 'crypto2.record',
      'contentContract': 6,
      'serverId': session.profile.serverId,
      'accountId': session.profile.accountId,
      'deviceId': session.profile.deviceId,
      'batchId': newSharedId(),
      'scopeId': a,
      'domain': 'content',
      'id': address.wireId,
      'type': 'shoppingList',
      'expectedRevision': 0,
      'deleted': false,
      'operationId': operation['opId'],
      'metadata': {
        'identity': address.identity,
        'references': <Object>[],
        'referenceVersions': <Object>[],
        'blobIds': <String>[],
      },
    };
    proofs = [_proof(record)];
    await save();
    await db
        .execute('INSERT INTO crypto_business_requests VALUES(?,?,?,?,?,?,?)', [
          p,
          operation['opId'],
          a,
          'content',
          await CryptoBusinessJson.hash(operation),
          requestId,
          id,
        ]);
    await db.execute(
      'INSERT OR REPLACE INTO local_meta(name,value) VALUES(?,?)',
      ['account_changes_v1:$p:${session.profile.deviceId}', 'old'],
    );
    transport.calls.clear();
    server.calls.clear();
  }

  Future<void> save() async {
    final command = {
      'version': 2,
      'operation': 'crypto2.records.batch',
      'requestId': requestId,
      'serverId': session.profile.serverId,
      'accountId': session.profile.accountId,
      'deviceId': session.profile.deviceId,
      'signer': 'device',
      'payload': {
        'batchId': record['batchId'],
        'records': proofs,
        'commitment': _proof({'version': 2}),
      },
    };
    final signed = _proof(command);
    savedBody = jsonEncode(signed);
    savedHash = await _hash(cryptoBase64(signed['commandBase64']));
    await db.execute(
      'INSERT OR REPLACE INTO crypto_outbox(partition,request_id,operation,signed_body,request_hash) VALUES(?,?,\'crypto2.records.batch\',?,?)',
      [p, requestId, savedBody, savedHash],
    );
    await db.execute(
      'DELETE FROM crypto_outbox_records WHERE partition=? AND request_id=?',
      [p, requestId],
    );
    for (final proof in proofs) {
      final r = CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map;
      await db.execute(
        'INSERT INTO crypto_outbox_records VALUES(?,?,?,?,?,?)',
        [
          p,
          r['scopeId'],
          r['domain'],
          r['id'],
          r['expectedRevision'],
          requestId,
        ],
      );
    }
  }

  Future<CollaborationPendingSyncSelection> select({bool shared = true}) =>
      CollaborationPendingSyncSelection.read(
        database: db,
        session: session,
        scopes: repo.state.scopes,
        sharedUploadsAllowed: shared,
      );
  Future<Object?> cursor() async => (await db.rows(
    'SELECT value FROM local_meta WHERE name=?',
    ['account_changes_v1:$p:${session.profile.deviceId}'],
  )).firstOrNull?['value'];
  Future<void> enableBusiness() async {
    final crypto = CryptoCodec(await SodiumInit.init());
    final account = AccountCryptoV2Workflow(
      AccountDirectoryRepository(
        reducer: AccountDirectoryV2(crypto),
        session: session,
        transport: transport,
        store: CryptoIdentityStore(db, _Secure(), p),
        isCurrent: () => true,
      ),
    );
    queue = _Queue(this);
    business = _Business(account, _Access(), db, queue!);
    await CryptoBusinessAddresses(db, p, session.profile.serverId).install(
      CryptoRecordAddress.forType(
        serverId: session.profile.serverId,
        scopeId: a,
        type: 'shoppingList',
        canonicalId: id,
      ),
    );
    await db.execute(
      "INSERT INTO crypto_scope_state(partition,scope_id,domain,state,floor) VALUES(?,?,'content','active',1)",
      [p, a],
    );
  }
}

void main() {
  Future<_Fixture> setup() async {
    final f = _Fixture();
    addTearDown(f.repo.close);
    await f.initialize();
    return f;
  }

  test(
    'pending selection: exact ordinary request selects only declared domains',
    () async {
      final f = await setup();
      final refId = cryptoWireRecordId(
        f.session.profile.serverId,
        f.b,
        'financeAccount',
        newSharedId(),
      );
      (f.record['metadata'] as Map)['references'] = [
        {'scopeId': f.b, 'id': refId},
      ];
      (f.record['metadata'] as Map)['referenceVersions'] = [
        {
          'scopeId': f.b,
          'domain': 'finance',
          'id': refId,
          'revision': 2,
          'recordProofHash': 'a' * 64,
        },
      ];
      f.proofs = [_proof(f.record)];
      await f.save();
      final selected = await f.select();
      expect(selected.fallback, isNull);
      expect(selected.scopes, {
        f.a: {'content'},
        f.b: {'finance'},
      });
      expect(await f.db.rows('SELECT signed_body FROM crypto_outbox'), [
        {'signed_body': f.savedBody},
      ]);
    },
  );
  test(
    'pending selection: fixed task companion stays in exact source batch',
    () async {
      final f = await setup();
      f.operation['type'] = 'task';
      await f.db.execute('UPDATE outbox SET request=? WHERE op_id=?', [
        jsonEncode(f.operation),
        f.operation['opId'],
      ]);
      await f.db.execute('UPDATE crypto_business_requests SET request_hash=?', [
        await CryptoBusinessJson.hash(f.operation),
      ]);
      f.record['type'] = 'task';
      final address = CryptoRecordAddress.forType(
        serverId: f.session.profile.serverId,
        scopeId: f.a,
        type: 'task',
        canonicalId: f.id,
      );
      f.record['id'] = address.wireId;
      (f.record['metadata'] as Map)['identity'] = address.identity;
      final task = _proof(f.record);
      final sibling = {
        ...f.record,
        'type': 'taskDerivationIntent',
        'id': cryptoWireRecordId(
          f.session.profile.serverId,
          f.a,
          'taskDerivationIntent',
          newSharedId(),
        ),
        'metadata': {
          'references': <Object>[],
          'referenceVersions': <Object>[],
          'blobIds': <String>[],
          'recordPolicyCompanion': {
            'version': 1,
            'taskId': f.record['id'],
            'taskRevision': 1,
            'taskProofHash': await _hash(CryptoJson.encode(task)),
          },
        },
      };
      f.proofs = [task, _proof(sibling)];
      await f.save();
      expect((await f.select()).fallback, isNull);
      final childScopes = [
        for (final scope in f.repo.state.scopes)
          if (scope.id == f.a)
            SharedScope.fromJson({
              ...scope.toJson(),
              'kind': 'project',
              'parentScopeId': f.b,
              'parentScopeKind': 'household',
            })
          else
            scope,
      ];
      expect(
        (await CollaborationPendingSyncSelection.read(
          database: f.db,
          session: f.session,
          scopes: childScopes,
          sharedUploadsAllowed: true,
        )).fallback,
        CollaborationRecoveryFallback.unknownDependency,
      );
      (sibling['metadata'] as Map)['recordPolicyCompanion']['taskProofHash'] =
          '0' * 64;
      f.proofs = [task, _proof(sibling)];
      await f.save();
      expect(
        (await f.select()).fallback,
        CollaborationRecoveryFallback.unknownDependency,
      );
    },
  );
  test(
    'pending selection: broken provenance claims and unknown work fall back',
    () async {
      for (final fault in [
        'hash',
        'identity',
        'claim',
        'business',
        'logical',
        'reference',
        'blob',
        'command',
        'recordShape',
        'payloadShape',
      ]) {
        final f = await setup();
        switch (fault) {
          case 'hash':
            await f.db.execute('UPDATE crypto_outbox SET request_hash=?', [
              '0' * 64,
            ]);
          case 'identity':
            f.record['accountId'] = newSharedId();
            f.proofs = [_proof(f.record)];
            await f.save();
          case 'claim':
            await f.db.execute('DELETE FROM crypto_outbox_records');
          case 'business':
            await f.db.execute('DELETE FROM crypto_business_requests');
          case 'logical':
            await f.db.execute(
              'UPDATE crypto_business_requests SET request_hash=?',
              ['0' * 64],
            );
          case 'reference':
            (f.record['metadata'] as Map)['references'] = [
              {'scopeId': newSharedId(), 'id': f.record['id']},
            ];
            f.proofs = [_proof(f.record)];
            await f.save();
          case 'blob':
            (f.record['metadata'] as Map)['blobIds'] = [newSharedId()];
            f.proofs = [_proof(f.record)];
            await f.save();
          case 'recordShape':
            f.record['contentContract'] = 99;
            f.proofs = [_proof(f.record)];
            await f.save();
          case 'payloadShape':
            final signed = jsonDecode(f.savedBody) as Map;
            final cmd =
                CryptoJson.decode(cryptoBase64(signed['commandBase64']))
                    as Map<String, dynamic>;
            (cmd['payload'] as Map).remove('commitment');
            final replacement = _proof(cmd);
            await f.db.execute(
              'UPDATE crypto_outbox SET signed_body=?,request_hash=?',
              [
                jsonEncode(replacement),
                await _hash(cryptoBase64(replacement['commandBase64'])),
              ],
            );
          case 'command':
            await f.db.execute(
              "UPDATE crypto_outbox SET operation='crypto2.scope.origin'",
            );
        }
        expect((await f.select()).fallback, isNotNull, reason: fault);
        expect(
          (await f.db.rows('SELECT state FROM crypto_outbox')).single['state'],
          'pending',
        );
      }
    },
  );
  test(
    'pending selection: excluded queued operations keep conservative recovery',
    () async {
      for (final fault in [
        'reconciliation',
        'paused',
        'archived',
        'moderation',
        'pair',
        'projectDelete',
      ]) {
        final f = await setup();
        switch (fault) {
          case 'reconciliation':
            await f.db.execute(
              'INSERT INTO local_meta(name,value) VALUES(?,?)',
              ['scope_reconciliation:${f.p}:${f.a}', 'pending'],
            );
          case 'paused':
            await f.db.execute(
              "INSERT INTO personal_workspaces(id,partition,scope_id,enabled,paused) VALUES('fixture',?,?,1,1)",
              [f.p, f.a],
            );
          case 'archived':
            await f.db.execute(
              "UPDATE scopes SET data=json_set(data,'\$.archived',json('true')) WHERE id=?",
              [f.a],
            );
            await f.repo.refreshLocal();
            expect(
              f.repo.state.scopes
                  .singleWhere((scope) => scope.id == f.a)
                  .archived,
              isTrue,
            );
          case 'moderation':
            break;
          case 'pair':
            await f.db.execute(
              'INSERT INTO local_meta(name,value) VALUES(?,?)',
              ['task_cost_pair:${f.p}:${f.operation['opId']}', newSharedId()],
            );
          case 'projectDelete':
            f.record['type'] = 'project';
            f.operation['type'] = 'project';
            f.operation['deleted'] = true;
            f.record['deleted'] = true;
            await f.db.execute('UPDATE outbox SET request=?', [
              jsonEncode(f.operation),
            ]);
            await f.db.execute(
              'UPDATE crypto_business_requests SET request_hash=?',
              [await CryptoBusinessJson.hash(f.operation)],
            );
            f.proofs = [_proof(f.record)];
            await f.save();
        }
        expect(
          (await f.select(shared: fault != 'moderation')).fallback,
          isNotNull,
          reason: fault,
        );
      }
    },
  );
  test(
    'pending selection: inventory bound and blocked requests never become retries',
    () async {
      final f = await setup();
      await f.db.execute("UPDATE crypto_outbox SET state='blocked'");
      expect((await f.select()).scopes, isEmpty);
      expect(
        (await f.db.rows('SELECT state FROM crypto_outbox')).single['state'],
        'blocked',
      );
      await f.db.execute(
        "UPDATE crypto_outbox SET state='pending',signed_body=?",
        ['x' * 1048577],
      );
      expect(
        (await f.select()).fallback,
        CollaborationRecoveryFallback.inventoryLimit,
      );
    },
  );
  test(
    'pending coordinator: exact saved push and remote local union avoid unrelated pulls',
    () async {
      final f = await setup();
      await f.enableBusiness();
      f.transport.hints = {
        f.c: ['content'],
      };
      await f.repo.createShoppingList(scopeId: f.d, title: 'Independent');
      await f.repo.syncNow();
      expect(f.repo.state.lastError, isNull);
      expect(f.repo.state.financePolicyForScope(f.b).canRead, isTrue);
      expect(
        f.repo.state.dataForScope(f.b).financeAccounts.single.name,
        'Unrelated ledger',
      );
      expect(f.queue!.resumed, [
        {f.requestId},
      ]);
      expect(await f.cursor(), 'next');
      final pulls = f.transport.calls
          .where((c) => c.operation == 'sync.pull')
          .toList();
      expect(pulls.map((c) => c.params['scopeId']).toSet(), {f.a, f.c, f.d});
      expect(pulls, hasLength(3));
      expect(
        f.transport.calls.where((c) => c.operation.contains('finance')),
        isEmpty,
      );
      expect(
        f.transport.calls.where((c) => c.operation == 'scopes.list'),
        isEmpty,
      );
      expect(
        f.transport.calls.where((c) => c.operation == 'crypto2.receipt.get'),
        hasLength(1),
      );
      expect(
        (await f.db.rows(
          'SELECT signed_body FROM crypto_outbox',
        )).single['signed_body'],
        f.savedBody,
      );
    },
  );
  test(
    'pending coordinator: selected failure and invalidation cannot acknowledge old probe',
    () async {
      for (final invalidation in [false, true]) {
        final f = await setup();
        await f.enableBusiness();
        f.transport.before = (operation, params) async {
          if (operation == 'sync.pull' && params['scopeId'] == f.a) {
            f.transport.before = null;
            if (invalidation) {
              await f.repo.invalidateAccountChangesCursor();
            } else {
              throw const CollaborationApiException('synthetic_pull_failure');
            }
          }
        };
        await f.repo.syncNow();
        if (!invalidation) {
          expect(f.repo.state.lastError?.code, 'synthetic_pull_failure');
          expect(await f.cursor(), 'old');
        } else {
          // The next demand may complete normally, but the original CAS failed.
          expect(
            f.diagnostics.events.map((e) => e.kind),
            contains(CollaborationSyncDiagnosticKind.cursorInvalidated),
          );
        }
      }
    },
  );
  test(
    'pending coordinator: payment work retains explicit full fallback reason',
    () async {
      final f = await setup();
      await f.db.execute(
        "INSERT INTO linked_payment_intents VALUES(?,?,'complete')",
        [
          newSharedId(),
          jsonEncode({'partition': f.p}),
        ],
      );
      await f.repo.syncNow();
      expect(f.repo.state.lastError, isNull);
      expect(
        f.transport.calls.where((c) => c.operation == 'scopes.list'),
        hasLength(1),
      );
      expect(
        f.transport.calls
            .where((c) => c.operation == 'sync.pull')
            .map((c) => c.params['scopeId'])
            .toSet(),
        {f.a, f.b, f.c, f.d},
      );
      expect(
        f.transport.calls.where((c) => c.operation == 'finance.pull'),
        hasLength(4),
      );
      expect(
        f.diagnostics.events
            .where(
              (e) => e.kind == CollaborationSyncDiagnosticKind.recoveryFallback,
            )
            .single
            .recoveryFallback,
        CollaborationRecoveryFallback.payments,
      );
    },
  );
}
