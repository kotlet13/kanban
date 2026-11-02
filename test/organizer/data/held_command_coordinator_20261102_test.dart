import 'dart:convert';

import 'package:cryptography/cryptography.dart' show Sha256;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sodium/sodium.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/data/collaboration_transport.dart';
import 'package:kanban/organizer/data/device_session_store.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_store.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_v2_workflow.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_repository.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_v2.dart';
import 'package:kanban/organizer/data/e2ee/crypto_business_router.dart';
import 'package:kanban/organizer/data/e2ee/crypto_codec.dart';
import 'package:kanban/organizer/data/e2ee/crypto_identity_store.dart';
import 'package:kanban/organizer/data/e2ee/crypto_json.dart';
import 'package:kanban/organizer/data/e2ee/crypto_domain_router.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import '../support/synthetic_content_route_guard.dart';
import 'package:kanban/organizer/data/e2ee/crypto_active_outbox.dart';
import 'package:kanban/organizer/data/e2ee/crypto_sync_store.dart';
import 'collaboration_repository_test.dart'
    show FakeServer, FakeTransport, MemorySessionStore;

class _Secure implements AccountCryptoStore {
  final writes = <String>[];
  @override
  Future<String?> read(String key) async => null;
  @override
  Future<void> write(String key, String value) async => writes.add(key);
}

// Hooks wrap actual SQLite operations and inherited real transactions. They
// target only final generation-CAS/aggregate boundaries in the two tests below.
class _FaultDatabase extends CollaborationDatabase {
  _FaultDatabase() : super(NativeDatabase.memory());
  Future<void> Function(String sql, List<Object?> args)? beforeExecute;
  Future<void> Function(String sql, List<Object?> args)? afterExecute;
  Future<void> Function(String sql, List<Object?> args)? beforeRows;
  @override
  Future<void> execute(String sql, [List<Object?> args = const []]) async {
    await beforeExecute?.call(sql, args);
    await super.execute(sql, args);
    await afterExecute?.call(sql, args);
  }

  @override
  Future<List<Map<String, dynamic>>> rows(
    String sql, [
    List<Object?> args = const [],
  ]) async {
    await beforeRows?.call(sql, args);
    return super.rows(sql, args);
  }
}

class _LegacyRouter implements CryptoDomainRouter {
  @override
  Future<Map<String, dynamic>> dispatch({
    required DeviceSession session,
    required String operation,
    required Map<String, Object?> params,
    required Set<String> protectedScopeIds,
  }) async => throw StateError('Unexpected crypto dispatch');
}

// Full content/finance projection uses the established synthetic legacy route;
// the receipt sweep itself remains the inherited production router and queue.
class _ScopedRouter extends CryptoBusinessRouter {
  _ScopedRouter({required super.database, required super.accountFor});
  Future<void> Function()? duringResume;
  @override
  Future<Set<String>> resumeHeldCommands({
    required DeviceSession session,
    required Set<String> requestIds,
    required Future<void> Function() checkCurrent,
  }) async {
    await checkCurrent();
    await duringResume?.call();
    return {};
  }

  @override
  Future<void> ensureRecordPolicy({
    required DeviceSession session,
    required String scopeId,
  }) async {}
  @override
  Future<CryptoProjectionCursorOrigin?> verifyProjectionCursorOrigin({
    required DeviceSession session,
    required String scopeId,
  }) async => null;
}

class _Transport extends FakeTransport {
  _Transport(super.server, this.sessions);
  final MemorySessionStore sessions;
  final calls = <String>[];
  final outcomes = <String, String>{};
  final requests = <String, Map<String, Object?>>{};
  Future<void> Function()? beforeReceipt, beforeScopes;
  bool hints = false, financeEnabled = false;
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
    calls.add(operation);
    if (operation == 'scopes.list') await beforeScopes?.call();
    if (operation == 'account.changes') {
      final s = sessions.value!.profile;
      final reset = params['cursor'] == null;
      return {
        'version': 1,
        'directoryHintsVersion': 1,
        'serverId': s.serverId,
        'accountId': s.accountId,
        'deviceId': s.deviceId,
        'cursor': 'current',
        'changed': reset || hints,
        'resetRequired': reset,
        'hasMore': false,
        'accountDomains': <String>[if (hints) 'inbox'],
        'scopes': <Object>[],
      };
    }
    if (operation == 'crypto2.receipt.get') {
      await beforeReceipt?.call();
      final id = params['requestId'] as String;
      final mode = outcomes[id] ?? 'unknown';
      if (mode == 'denied') {
        throw const CollaborationApiException('crypto_receipt_scope_required');
      }
      if (mode == 'unknown') return {'outcome': 'unknown'};
      final row = requests[id]!;
      return {
        'outcome': 'recorded',
        'requestId': id,
        'requestHash': mode == 'substituted' ? '0' * 64 : row['request_hash'],
        'authorization': jsonDecode(row['signed_body'] as String),
        'status': mode == 'malformed_status'
            ? '200'
            : (mode == 'rejected' ? 409 : 200),
        'response': {'status': mode == 'rejected' ? 'rejected' : 'applied'},
      };
    }
    if (financeEnabled && operation == 'finance.policy') {
      return {'enabled': true, 'grant': 'read', 'revision': 1};
    }
    if (financeEnabled && operation == 'finance.pull') {
      return {
        'records': <Object>[],
        'cursor': 0,
        'hasMore': false,
        'accessRevision': 1,
      };
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
            if (financeEnabled) 'financeContractVersions': [1],
            if (financeEnabled)
              'features': <String, dynamic>{
                ...result['features'] as Map,
                'finance': true,
              },
          }
        : result;
  }
}

class _Fixture {
  _Fixture(this.crypto);
  final CryptoCodec crypto;
  final sessions = MemorySessionStore(),
      server = FakeServer(),
      secure = _Secure();
  late final db = _FaultDatabase();
  late final transport = _Transport(server, sessions);
  late CollaborationRepository repo;
  DateTime now = DateTime.utc(2026, 11, 2, 10);
  DeviceSession get session => sessions.value!;
  String get p => session.profile.partition;
  Future<AccountCryptoV2Workflow> account(DeviceSession s) async =>
      AccountCryptoV2Workflow(
        AccountDirectoryRepository(
          reducer: AccountDirectoryV2(crypto),
          session: s,
          transport: transport,
          store: CryptoIdentityStore(db, secure, s.profile.partition),
          isCurrent: () => identical(sessions.value, s),
        ),
      );
  Future<void> open({bool router = true, bool scoped = false}) async {
    repo = CollaborationRepository(
      db,
      transport,
      sessions,
      clock: () => now,
      contentRouteGuard: const SyntheticContentRouteGuard(),
      cryptoRouter: router
          ? (scoped
                ? _ScopedRouter(database: db, accountFor: account)
                : CryptoBusinessRouter(database: db, accountFor: account))
          : _LegacyRouter(),
    );
    await repo.initialize();
    await repo.login(
      serverUrl: 'https://synthetic.invalid/',
      username: 'alice',
      password: 'synthetic',
    );
    await repo.syncNow();
    expect(repo.state.lastError, isNull, reason: 'baseline');
    transport.calls.clear();
    server.calls.clear();
    now = now.add(const Duration(minutes: 2));
  }

  Future<String> held({String mode = 'unknown'}) async {
    final id = crypto.randomId();
    final keys = crypto.sodium.crypto.sign.keyPair();
    final signed = crypto.sign({
      'version': 2,
      'operation': 'crypto2.domain.checkpoint',
      'requestId': id,
      'serverId': session.profile.serverId,
      'accountId': session.profile.accountId,
      'deviceId': session.profile.deviceId,
      'signer': 'device',
      'payload': {'scopeId': crypto.randomId(), 'domain': 'content'},
    }, keys.secretKey);
    keys.secretKey.dispose();
    final hash = (await Sha256().hash(
      cryptoBase64(signed['commandBase64']),
    )).bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    await db.execute(
      'INSERT INTO crypto_outbox(partition,request_id,operation,signed_body,request_hash,state,response) VALUES(?,?,?,?,?,?,?)',
      [
        p,
        id,
        'crypto2.domain.checkpoint',
        jsonEncode(signed),
        hash,
        'blocked',
        jsonEncode({
          'outcome': 'unresolved',
          'reason': 'authority_pending',
          'code': 'crypto_domain_operation_pending',
        }),
      ],
    );
    transport.outcomes[id] = mode;
    transport.requests[id] = (await db.rows(
      'SELECT * FROM crypto_outbox WHERE partition=? AND request_id=?',
      [p, id],
    )).single;
    return id;
  }

  Future<List<Map<String, Object?>>> rows() =>
      db.rows('SELECT * FROM crypto_outbox ORDER BY sequence');
  List<String> get reasons =>
      repo.state.syncFailures.map((f) => f.reason).toList();
}

// Projection and completed domain supersession are explicit seams here; their
// cryptographic admission is covered by the new core/helper suites. These tests
// exercise the actual coordinator, SQL accounting and final success boundary.
Future<void> _retire(_Fixture f, String id, {bool audit = true}) async {
  final old = (await f.db.rows(
    'SELECT * FROM crypto_outbox WHERE request_id=?',
    [id],
  )).single;
  final replacement = await f.held();
  await f.db.execute(
    "UPDATE crypto_outbox SET state='applied' WHERE request_id=?",
    [replacement],
  );
  final next = (await f.db.rows(
    'SELECT * FROM crypto_outbox WHERE request_id=?',
    [replacement],
  )).single;
  final details = jsonEncode({
    'version': 1,
    'oldRequestHash': old['request_hash'],
    'newRequestId': replacement,
    'newRequestHash': next['request_hash'],
  });
  await f.db.execute('INSERT INTO local_meta(name,value) VALUES(?,?)', [
    'crypto_checkpoint_superseded_v1:${f.p}:$id',
    details,
  ]);
  if (audit) {
    await f.db.execute(
      'INSERT INTO crypto_outbox_attempts(partition,request_id,event,details) VALUES(?,?,?,?)',
      [f.p, id, 'checkpoint_superseded_locally', details],
    );
  }
}

void main() {
  late CryptoCodec crypto;
  setUpAll(() async {
    crypto = CryptoCodec(await SodiumInit.init());
  });
  Future<_Fixture> fixture() async {
    final f = _Fixture(crypto);
    await f.open(scoped: true);
    addTearDown(f.repo.close);
    return f;
  }

  Future<String> rotation(_Fixture f) async {
    final id = await f.held();
    await f.db.execute(
      'UPDATE crypto_outbox SET response=? WHERE request_id=?',
      [
        jsonEncode({
          'outcome': 'unresolved',
          'reason': 'authority_pending',
          'code': 'scope_reauthorization_required',
        }),
        id,
      ],
    );
    return id;
  }

  test(
    'manual rotated checkpoint triggers full pass and closes proved derived debt once',
    () async {
      final f = await fixture();
      f.transport.financeEnabled = true;
      await f.repo.createScope('Target');
      await f.repo.syncNow();
      final id = await rotation(f);
      final old = (await f.db.rows(
        'SELECT * FROM crypto_outbox WHERE request_id=?',
        [id],
      )).single;
      f.transport.beforeScopes = () async {
        f.transport.beforeScopes = null;
        await _retire(f, id);
      };
      f.transport.calls.clear();
      await f.repo.syncNow(manual: true);
      expect(f.transport.calls, containsAll(['sync.pull', 'finance.pull']));
      expect(
        f.transport.calls.where((op) => op == 'scopes.list'),
        hasLength(1),
      );
      expect(f.repo.state.lastError, isNull);
      expect(f.repo.state.blockedSyncCommandCount, 0);
      expect(f.repo.state.lastSuccessfulSyncAt, f.now);
      expect(
        (await f.db.rows('SELECT * FROM crypto_outbox WHERE request_id=?', [
          id,
        ])).single,
        old,
      );
      expect(
        await f.db.rows(
          "SELECT 1 FROM local_meta WHERE name LIKE 'held_receipt_refresh_v1:%'",
        ),
        isEmpty,
      );
      f.transport.calls.clear();
      await f.repo.syncNow();
      expect(f.transport.calls, ['account.changes']);
    },
  );
  test(
    'unresolved rotation full pass cannot invent completion or auto repeat',
    () async {
      final f = await fixture();
      final before = f.repo.state.lastSuccessfulSyncAt;
      await rotation(f);
      await f.repo.syncNow(manual: true);
      expect(f.transport.calls, contains('scopes.list'));
      expect(f.repo.state.blockedSyncCommandCount, 1);
      expect(f.repo.state.lastSuccessfulSyncAt, before);
      expect(f.repo.state.lastError, isNotNull);
      f.transport.calls.clear();
      await f.repo.syncNow();
      expect(f.transport.calls, ['account.changes']);
    },
  );
  test(
    'derived marker never clears debt without audit or for record claim',
    () async {
      final f = await fixture();
      final id = await f.held();
      await _retire(f, id, audit: false);
      expect(
        await f.db.rows(
          'SELECT request_id FROM crypto_outbox WHERE state=\'blocked\' AND ${cryptoActiveOutboxPredicate()}',
        ),
        hasLength(1),
      );
      final meta = (await f.db.rows(
        "SELECT value FROM local_meta WHERE name LIKE 'crypto_checkpoint_superseded_v1:%'",
      )).single['value'];
      await f.db.execute(
        'INSERT INTO crypto_outbox_attempts(partition,request_id,event,details) VALUES(?,?,?,?)',
        [f.p, id, 'checkpoint_superseded_locally', meta],
      );
      expect(
        await CryptoSyncStore(f.db, f.p).blockedDelivery().toList(),
        isEmpty,
      );
      await f.db.execute(
        'INSERT INTO crypto_outbox_records VALUES(?,?,?,?,?,?)',
        [f.p, crypto.randomId(), 'content', crypto.randomId(), 0, id],
      );
      expect(
        await CryptoSyncStore(f.db, f.p).blockedDelivery().toList(),
        hasLength(1),
      );
    },
  );
  test(
    'corrupt marker stays active and projection failure preserves refresh debt',
    () async {
      final f = await fixture();
      final id = await rotation(f);
      final before = f.repo.state.lastSuccessfulSyncAt;
      await f.db.execute('INSERT INTO local_meta(name,value) VALUES(?,?)', [
        'crypto_checkpoint_superseded_v1:${f.p}:$id',
        'broken-json',
      ]);
      expect(
        await CryptoSyncStore(f.db, f.p).blockedDelivery().toList(),
        hasLength(1),
      );
      f.transport.beforeScopes = () async {
        throw const CollaborationException('network');
      };
      await f.repo.syncNow(manual: true);
      expect(f.repo.state.lastSuccessfulSyncAt, before);
      expect(
        await f.db.rows(
          "SELECT 1 FROM local_meta WHERE name LIKE 'held_receipt_refresh_v1:%'",
        ),
        hasLength(1),
      );
      expect(f.repo.state.blockedSyncCommandCount, 1);
    },
  );
  test(
    'removed held row cannot be mistaken for verified supersession',
    () async {
      final f = await fixture();
      final id = await f.held();
      final success = f.repo.state.lastSuccessfulSyncAt;
      (f.repo.cryptoRouter as _ScopedRouter).duringResume = () async {
        await f.db.execute('DELETE FROM crypto_outbox WHERE request_id=?', [
          id,
        ]);
      };
      await expectLater(
        f.repo.syncNow(manual: true),
        throwsA(
          isA<CollaborationException>().having(
            (e) => e.code,
            'code',
            'invalid_response',
          ),
        ),
      );
      expect(f.repo.state.lastSuccessfulSyncAt, success);
    },
  );
  test(
    'new checkpoint generation gets one bounded full continuation in same click',
    () async {
      final f = await fixture();
      final id = await rotation(f);
      var calls = 0;
      f.transport.beforeScopes = () async {
        calls++;
        if (calls == 1) {
          await _retire(f, id);
          await f.db.execute(
            'INSERT OR REPLACE INTO local_meta(name,value) VALUES(?,?)',
            ['held_receipt_refresh_v1:${f.p}', 'proved-new-generation'],
          );
        }
      };
      await f.repo.syncNow(manual: true);
      expect(calls, 2);
      expect(f.repo.state.lastError, isNull);
      expect(f.repo.state.lastSuccessfulSyncAt, f.now);
      expect(f.repo.state.blockedSyncCommandCount, 0);
      expect(
        await f.db.rows('SELECT value FROM local_meta WHERE name=?', [
          'held_receipt_refresh_v1:${f.p}',
        ]),
        isEmpty,
      );
    },
  );
  test(
    'concurrent checkpoint generations cannot loop or report false completion',
    () async {
      final f = await fixture();
      final id = await rotation(f);
      final before = f.repo.state.lastSuccessfulSyncAt;
      var calls = 0;
      f.transport.beforeScopes = () async {
        calls++;
        if (calls == 1) await _retire(f, id);
        await f.db.execute(
          'INSERT OR REPLACE INTO local_meta(name,value) VALUES(?,?)',
          ['held_receipt_refresh_v1:${f.p}', 'concurrent-$calls'],
        );
      };
      await f.repo.syncNow(manual: true);
      expect(calls, 2);
      expect(f.repo.state.lastSuccessfulSyncAt, before);
      expect(
        (await f.db.rows('SELECT value FROM local_meta WHERE name=?', [
          'held_receipt_refresh_v1:${f.p}',
        ])).single['value'],
        'concurrent-2',
      );
      f.transport.calls.clear();
      await f.repo.syncNow();
      expect(f.transport.calls, ['account.changes']);
    },
  );
}
