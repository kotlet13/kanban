import 'dart:convert';
import 'dart:async';

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
  Future<void> Function()? beforeReceipt;
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

void main() {
  late CryptoCodec crypto;
  setUpAll(() async {
    crypto = CryptoCodec(await SodiumInit.init());
  });
  Future<_Fixture> fixture({bool router = true, bool scoped = false}) async {
    final f = _Fixture(crypto);
    await f.open(router: router, scoped: scoped);
    addTearDown(f.repo.close);
    return f;
  }

  test(
    'held sync manual 19 unknown requests rechecks production queue without mutation or success',
    () async {
      final f = await fixture();
      for (var i = 0; i < 19; i++) {
        await f.held();
      }
      final before = await f.rows(),
          success = f.repo.state.lastSuccessfulSyncAt;
      final attempts = await f.db.rows('SELECT * FROM crypto_outbox_attempts');
      await f.repo.syncNow(manual: true);
      expect(
        f.transport.calls.where((op) => op == 'crypto2.receipt.get'),
        hasLength(19),
      );
      expect(f.transport.calls.where((op) => op != 'crypto2.receipt.get'), [
        'account.changes',
      ]);
      expect(await f.rows(), before);
      expect(await f.db.rows('SELECT * FROM crypto_outbox_attempts'), attempts);
      expect(f.repo.state.blockedSyncCommandCount, 19);
      expect(f.repo.state.pendingCount, 0);
      expect(f.repo.state.lastSyncAttemptAt, f.now);
      expect(f.repo.state.lastSuccessfulSyncAt, success);
      expect(
        f.reasons,
        containsAll([
          'crypto_command_receipt_pending',
          'crypto_domain_operation_pending',
        ]),
      );
      expect(f.secure.writes, isEmpty);
      f.transport.calls.clear();
      await f.repo.syncNow();
      expect(f.transport.calls, ['account.changes']);
      expect(await f.rows(), before);
      expect(f.repo.state.lastError, isNotNull);
    },
  );

  test(
    'held sync applied exact receipt verifies once and clears sweep-owned guard errors',
    () async {
      final f = await fixture();
      final id = await f.held();
      await f.repo.syncNow(manual: true);
      f.transport.outcomes[id] = 'applied';
      f.transport.calls.clear();
      f.now = f.now.add(const Duration(minutes: 2));
      await f.repo.syncNow(manual: true);
      expect((await f.rows()).single['state'], 'applied');
      expect(
        f.transport.calls.where((op) => op == 'scopes.list'),
        hasLength(1),
      );
      expect(f.repo.state.lastError, isNull);
      expect(f.reasons, isNot(contains('crypto_domain_operation_pending')));
      expect(f.repo.state.lastSuccessfulSyncAt, f.now);
      expect(f.repo.state.blockedSyncCommandCount, 0);
      f.transport.calls.clear();
      await f.repo.syncNow();
      expect(f.transport.calls, ['account.changes']);
    },
  );

  test(
    'held sync rejected exact receipt remains blocked for operation-owned resolution',
    () async {
      final f = await fixture();
      await f.held(mode: 'rejected');
      final before = await f.rows(),
          success = f.repo.state.lastSuccessfulSyncAt;
      await f.repo.syncNow(manual: true);
      expect(await f.rows(), before);
      expect(f.reasons, contains('crypto_command_rejected'));
      expect(f.repo.state.lastSuccessfulSyncAt, success);
      await f.repo.syncNow(manual: true);
      expect(await f.rows(), before);
      expect(f.reasons, contains('crypto_command_rejected'));
      expect(f.repo.state.blockedSyncCommandCount, 1);
    },
  );

  test(
    'held sync denied first request preserves it and continues later exact receipt',
    () async {
      final f = await fixture();
      final denied = await f.held(mode: 'denied');
      final applied = await f.held(mode: 'applied');
      final original = f.transport.requests[denied];
      await f.repo.syncNow(manual: true);
      final rows = await f.rows();
      expect(rows.firstWhere((r) => r['request_id'] == denied), original);
      expect(
        rows.firstWhere((r) => r['request_id'] == applied)['state'],
        'applied',
      );
      expect(f.reasons, contains('crypto_command_receipt_pending'));
      expect(f.repo.state.lastError, isNotNull);
      expect(f.repo.state.blockedSyncCommandCount, 1);
    },
  );

  test('held sync substituted receipt cannot change retained rows', () async {
    final f = await fixture();
    await f.held(mode: 'substituted');
    final before = await f.rows();
    await expectLater(f.repo.syncNow(manual: true), throwsFormatException);
    expect(await f.rows(), before);
    expect(f.repo.state.blockedSyncCommandCount, 1);
    expect(f.repo.state.lastError, isNotNull);
  });

  test(
    'held sync lost lease after lookup cannot consume an exact receipt',
    () async {
      final f = await fixture();
      await f.held(mode: 'applied');
      final before = await f.rows();
      f.transport.beforeReceipt = () async {
        await f.db.execute('UPDATE sync_leases SET owner=? WHERE partition=?', [
          'other',
          f.p,
        ]);
      };
      await expectLater(
        f.repo.syncNow(manual: true),
        throwsA(isA<CollaborationException>()),
      );
      expect(await f.rows(), before);
      expect(
        (await f.db.rows('SELECT owner FROM sync_leases')).single['owner'],
        'other',
      );
    },
  );

  test(
    'held sync inventory limit preserves all requests without receipt calls',
    () async {
      final f = await fixture();
      for (var i = 0; i < 65; i++) {
        await f.held();
      }
      final before = await f.rows();
      await f.repo.syncNow(manual: true);
      expect(f.transport.calls, ['account.changes']);
      expect(await f.rows(), before);
      expect(f.reasons, contains('crypto_held_sync_inventory_limit'));
    },
  );

  test(
    'held sync unavailable receipt router reports retained work truthfully',
    () async {
      final f = await fixture(router: false);
      await f.held();
      final before = await f.rows();
      await f.repo.syncNow(manual: true);
      expect(f.transport.calls, ['account.changes']);
      expect(await f.rows(), before);
      expect(f.reasons, contains('crypto_command_receipt_pending'));
    },
  );
  test('held sync publishes busy state while receipt lookup waits', () async {
    final f = await fixture();
    await f.held();
    final entered = Completer<void>(), release = Completer<void>();
    f.transport.beforeReceipt = () async {
      entered.complete();
      await release.future;
    };
    final run = f.repo.syncNow(manual: true);
    await entered.future;
    expect(f.repo.state.isSyncing, isTrue);
    expect(f.repo.state.lastSyncAttemptAt, f.now);
    release.complete();
    await run;
    expect(f.repo.state.isSyncing, isFalse);
  });

  test(
    'held sync quarantined payment reports separate preserved debt without receipt request',
    () async {
      final f = await fixture();
      await f.db.execute('INSERT INTO linked_payment_intents VALUES(?,?,?)', [
        'retained-payment',
        jsonEncode({'partition': f.p}),
        'quarantine',
      ]);
      final before = await f.db.rows('SELECT * FROM linked_payment_intents');
      final success = f.repo.state.lastSuccessfulSyncAt;
      await f.repo.syncNow(manual: true);
      expect(f.transport.calls, ['account.changes']);
      expect(await f.db.rows('SELECT * FROM linked_payment_intents'), before);
      expect(f.reasons, contains('crypto_payment_quarantined'));
      expect(f.repo.state.lastSuccessfulSyncAt, success);
      expect(f.repo.state.blockedSyncCommandCount, 1);
    },
  );

  test(
    'held sync exact queue selection skips unrelated oversized ciphertext',
    () async {
      final f = await fixture();
      final id = await f.held();
      await f.db.execute(
        'INSERT INTO crypto_outbox(partition,request_id,operation,signed_body,request_hash) VALUES(?,?,?,?,?)',
        [
          f.p,
          crypto.randomId(),
          'crypto2.domain.checkpoint',
          'x' * (3 * 1024 * 1024),
          '0' * 64,
        ],
      );
      final before = await f.rows();
      final router = f.repo.cryptoRouter as CryptoTerminalReceiptReconciliation;
      final rejected = await router.reconcileTerminalReceipts(
        session: f.session,
        requestIds: {id},
        checkCurrent: () async {},
      );
      expect(rejected, isEmpty);
      expect(f.transport.calls, ['crypto2.receipt.get']);
      expect(await f.rows(), before);
    },
  );
  test(
    'held sync actual applied progress refreshes content and finance before success once',
    () async {
      final f = await fixture(scoped: true);
      f.transport.financeEnabled = true;
      final scope = await f.repo.createScope('Projection verification');
      await f.repo.syncNow();
      expect(f.repo.state.lastError, isNull);
      await f.held(mode: 'applied');
      f.transport.calls.clear();
      f.now = f.now.add(const Duration(minutes: 2));
      await f.repo.syncNow(manual: true);
      expect(
        f.transport.calls.where((op) => op == 'scopes.list'),
        hasLength(1),
      );
      expect(
        f.transport.calls,
        containsAll(['sync.pull', 'finance.policy', 'finance.pull']),
      );
      expect(f.repo.state.lastError, isNull);
      expect(f.repo.state.lastSuccessfulSyncAt, f.now);
      expect(f.repo.state.scopes.any((s) => s.id == scope), isTrue);
      f.transport.calls.clear();
      await f.repo.syncNow();
      expect(f.transport.calls, ['account.changes']);
    },
  );

  test(
    'held sync corrupted or foreign saved command never reaches receipt lookup',
    () async {
      final f = await fixture();
      for (final key in [
        'serverId',
        'accountId',
        'requestId',
        'operation',
        'hash',
      ]) {
        final id = await f.held();
        final row = f.transport.requests[id]!;
        final signed = Map<String, dynamic>.from(
          jsonDecode(row['signed_body'] as String),
        );
        final body = Map<String, dynamic>.from(
          CryptoJson.decode(cryptoBase64(signed['commandBase64'])) as Map,
        );
        if (key != 'hash') body[key] = crypto.randomId();
        signed['commandBase64'] = base64Encode(CryptoJson.encode(body));
        final hash = key == 'hash'
            ? '0' * 64
            : (await Sha256().hash(
                cryptoBase64(signed['commandBase64']),
              )).bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
        await f.db.execute(
          'UPDATE crypto_outbox SET signed_body=?,request_hash=? WHERE request_id=?',
          [jsonEncode(signed), hash, id],
        );
        final before = await f.rows();
        final router =
            f.repo.cryptoRouter as CryptoTerminalReceiptReconciliation;
        await expectLater(
          router.reconcileTerminalReceipts(
            session: f.session,
            requestIds: {id},
            checkCurrent: () async {},
          ),
          throwsFormatException,
        );
        expect(await f.rows(), before);
        expect(f.transport.calls, isEmpty);
      }
    },
  );
  test(
    'held sync substituted receipt fault remains preflight after cheap automatic probe',
    () async {
      final f = await fixture();
      await f.held(mode: 'substituted');
      await expectLater(f.repo.syncNow(manual: true), throwsFormatException);
      f.transport.calls.clear();
      await f.repo.syncNow();
      expect(f.transport.calls, ['account.changes']);
      expect(f.repo.state.lastError, isNotNull);
      expect(
        f.repo.state.syncFailures.any((d) => d.stage.name == 'preflight'),
        isTrue,
      );
      expect(f.repo.state.blockedSyncCommandCount, 1);
    },
  );

  test(
    'held sync ordinary pass recomputes remaining generic debt without stale original cause',
    () async {
      final f = await fixture();
      final settled = await f.held();
      await f.held();
      f.transport.hints = true;
      f.server.beforeCall = (op, token, params) async {
        if (op == 'capabilities') {
          await f.db.execute(
            "UPDATE crypto_outbox SET state='applied' WHERE request_id=?",
            [settled],
          );
        }
      };
      await f.repo.syncNow(manual: true);
      expect(f.repo.state.blockedSyncCommandCount, 1);
      expect(f.reasons, contains('crypto_command_receipt_pending'));
      expect(f.reasons, isNot(contains('crypto_domain_operation_pending')));
    },
  );

  test(
    'held sync applied receipt failed verification retains manual refresh debt until later full success',
    () async {
      final f = await fixture();
      await f.held(mode: 'applied');
      final success = f.repo.state.lastSuccessfulSyncAt;
      f.server.beforeCall = (op, token, params) async {
        if (op == 'scopes.list') {
          throw const CollaborationException('crypto_reconciliation_required');
        }
      };
      await f.repo.syncNow(manual: true);
      expect((await f.rows()).single['state'], 'applied');
      expect(f.repo.state.lastSuccessfulSyncAt, success);
      expect(
        await f.db.rows('SELECT value FROM local_meta WHERE name=?', [
          'held_receipt_refresh_v1:${f.p}',
        ]),
        hasLength(1),
      );
      expect(f.repo.state.syncRequiresRefresh, isTrue);
      f.transport.calls.clear();
      await f.repo.syncNow();
      expect(f.transport.calls, ['account.changes']);
      expect(f.repo.state.syncRequiresRefresh, isTrue);
      f.server.beforeCall = null;
      f.transport.calls.clear();
      f.now = f.now.add(const Duration(minutes: 2));
      await f.repo.syncNow(manual: true);
      expect(
        f.transport.calls.where((op) => op == 'scopes.list'),
        hasLength(1),
      );
      expect(f.transport.calls, isNot(contains('crypto2.receipt.get')));
      expect(f.repo.state.lastError, isNull);
      expect(f.repo.state.lastSuccessfulSyncAt, f.now);
      expect(
        await f.db.rows('SELECT value FROM local_meta WHERE name=?', [
          'held_receipt_refresh_v1:${f.p}',
        ]),
        isEmpty,
      );
      expect(f.repo.state.syncRequiresRefresh, isFalse);
    },
  );

  test(
    'held sync malformed terminal status cannot settle request or create refresh debt',
    () async {
      final f = await fixture();
      await f.held(mode: 'malformed_status');
      final before = await f.rows();
      await expectLater(f.repo.syncNow(manual: true), throwsFormatException);
      expect(await f.rows(), before);
      expect(
        await f.db.rows('SELECT 1 FROM local_meta WHERE name=?', [
          'held_receipt_refresh_v1:${f.p}',
        ]),
        isEmpty,
      );
      expect(f.repo.state.lastError, isNotNull);
    },
  );
  test(
    'held sync historical success cannot close receipt debt while current conflict guard remains',
    () async {
      final f = await fixture(scoped: true);
      final scope = await f.repo.createScope('Guarded projection');
      final record = await f.repo.createShoppingList(
        scopeId: scope,
        title: 'Retained conflict',
      );
      await f.repo.syncNow();
      expect(f.repo.state.lastError, isNull);
      final prior = f.repo.state.lastSuccessfulSyncAt;
      await f.db.execute(
        'INSERT INTO conflicts(id,partition,scope_id,record_id,type,reason) VALUES(?,?,?,?,?,?)',
        [crypto.randomId(), f.p, scope, record, 'shoppingList', 'conflict'],
      );
      await f.held(mode: 'applied');
      f.now = f.now.add(const Duration(minutes: 2));
      await f.repo.syncNow(manual: true);
      expect(f.repo.state.conflicts, isNotEmpty);
      expect(f.repo.state.lastError, isNull);
      expect(f.repo.state.lastSuccessfulSyncAt, prior);
      expect(
        await f.db.rows('SELECT value FROM local_meta WHERE name=?', [
          'held_receipt_refresh_v1:${f.p}',
        ]),
        hasLength(1),
      );
      expect(f.repo.state.syncRequiresRefresh, isTrue);
      await f.db.execute('DELETE FROM conflicts WHERE partition=?', [f.p]);
      f.now = f.now.add(const Duration(minutes: 2));
      await f.repo.syncNow(manual: true);
      expect(f.repo.state.lastSuccessfulSyncAt, f.now);
      expect(
        await f.db.rows('SELECT value FROM local_meta WHERE name=?', [
          'held_receipt_refresh_v1:${f.p}',
        ]),
        isEmpty,
      );
      expect(f.repo.state.syncRequiresRefresh, isFalse);
    },
  );
  test(
    'held sync final CAS preserves newer receipt generation and previous success timestamp',
    () async {
      final f = await fixture();
      final previous = f.repo.state.lastSuccessfulSyncAt;
      final original = await f.held(mode: 'applied');
      final newer = crypto.randomId();
      final key = 'held_receipt_refresh_v1:${f.p}';
      final historyKey =
          'sync_success_history:${f.p}:${Uri.encodeComponent(f.session.profile.deviceId)}';
      final history = await f.db.rows('SELECT * FROM local_meta WHERE name=?', [
        historyKey,
      ]);
      var casCalls = 0;
      f.db.beforeExecute = (sql, args) async {
        if (sql == 'DELETE FROM local_meta WHERE name=? AND value=?' &&
            args.first == key) {
          casCalls++;
          expect(args, [key, original]);
          await f.db.execute(
            'INSERT OR REPLACE INTO local_meta(name,value) VALUES(?,?)',
            [key, newer],
          );
        }
      };
      await f.repo.syncNow(manual: true);
      expect(casCalls, 1);
      expect(
        (await f.db.rows('SELECT value FROM local_meta WHERE name=?', [
          key,
        ])).single['value'],
        newer,
      );
      expect(f.repo.state.lastSuccessfulSyncAt, previous);
      expect(f.repo.state.syncRequiresRefresh, isTrue);
      expect(f.repo.state.lastError, isNull);
      expect(f.repo.state.isSyncing, isFalse);
      expect((await f.rows()).single['state'], 'applied');
      expect(
        await f.db.rows('SELECT * FROM local_meta WHERE name=?', [historyKey]),
        history,
      );
    },
  );

  test(
    'held sync final publish read fault after CAS restores exact old generation and previous success',
    () async {
      final f = await fixture();
      final previous = f.repo.state.lastSuccessfulSyncAt;
      final original = await f.held(mode: 'applied');
      final key = 'held_receipt_refresh_v1:${f.p}';
      final historyKey =
          'sync_success_history:${f.p}:${Uri.encodeComponent(f.session.profile.deviceId)}';
      final history = await f.db.rows('SELECT * FROM local_meta WHERE name=?', [
        historyKey,
      ]);
      var casCalls = 0, injectedFaults = 0;
      var failFinalAggregate = false;
      f.db.afterExecute = (sql, args) async {
        if (sql == 'DELETE FROM local_meta WHERE name=? AND value=?' &&
            args.first == key) {
          casCalls++;
          expect(args, [key, original]);
          failFinalAggregate = true;
        }
      };
      f.db.beforeRows = (sql, args) async {
        if (failFinalAggregate &&
            sql.startsWith('SELECT EXISTS(SELECT 1 FROM crypto_outbox')) {
          failFinalAggregate = false;
          injectedFaults++;
          throw StateError('injected_final_status_read_fault');
        }
      };
      await expectLater(f.repo.syncNow(manual: true), throwsStateError);
      expect(casCalls, 1);
      expect(injectedFaults, 1);
      expect(
        (await f.db.rows('SELECT value FROM local_meta WHERE name=?', [
          key,
        ])).single['value'],
        original,
      );
      expect(f.repo.state.lastSuccessfulSyncAt, previous);
      expect(f.repo.state.syncRequiresRefresh, isTrue);
      expect(f.repo.state.lastError, isNotNull);
      expect(f.repo.state.isSyncing, isFalse);
      expect((await f.rows()).single['state'], 'applied');
      expect(
        await f.db.rows('SELECT * FROM local_meta WHERE name=?', [historyKey]),
        history,
      );
      f.db.afterExecute = null;
      f.db.beforeRows = null;
      f.transport.calls.clear();
      f.now = f.now.add(const Duration(minutes: 2));
      await f.repo.syncNow(manual: true);
      expect(f.transport.calls, isNot(contains('crypto2.receipt.get')));
      expect(
        await f.db.rows('SELECT value FROM local_meta WHERE name=?', [key]),
        isEmpty,
      );
      expect(f.repo.state.lastSuccessfulSyncAt, f.now);
      expect(f.repo.state.lastError, isNull);
      expect(f.repo.state.syncRequiresRefresh, isFalse);
    },
  );
}
