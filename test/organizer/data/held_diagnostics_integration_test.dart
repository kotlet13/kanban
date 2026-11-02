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

  Future<String> held(_Fixture f, {String mode = 'unknown'}) async {
    final id = await f.held(mode: mode);
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
    'partial shopping download and held reason both survive final full-pass diagnostics',
    () async {
      final f = await fixture();
      f.transport.financeEnabled = true;
      final scope = await f.repo.createScope('Synthetic');
      final list = await f.repo.createShoppingList(
        scopeId: scope,
        title: 'Before',
      );
      await f.repo.syncNow();
      final remote = f.server.records[scope]![list]!;
      remote['payload'] = {
        ...remote['payload'] as Map,
        'title': 'Remote change',
      };
      remote['sequence'] = f.server.sequence[scope] =
          f.server.sequence[scope]! + 1;
      remote['revision'] = (remote['revision'] as int) + 1;
      final id = await held(f);
      final before = (await f.rows()).single;
      final success = f.repo.state.lastSuccessfulSyncAt;
      await f.repo.syncNow(manual: true);
      expect(
        f.repo.state.dataForScope(scope).shoppingLists.single.title,
        'Remote change',
      );
      final detail = f.repo.state.syncFailures
          .singleWhere((x) => x.reason == 'crypto_command_receipt_pending')
          .heldDiagnostics!;
      expect(detail.remaining, 1);
      expect(detail.samples.single.receipt, HeldReceiptResult.unknown);
      expect(detail.samples.single.resume, HeldResumeResult.ineligible);
      expect(
        detail.samples.single.retainedReason,
        'scope_reauthorization_required',
      );
      expect(f.repo.state.syncTransfer!.contentRecords, 1);
      expect(f.repo.state.syncTransfer!.contentPages, greaterThan(0));
      expect(f.repo.state.syncTransfer!.financePages, greaterThan(0));
      expect(f.repo.state.lastSuccessfulSyncAt, success);
      expect((await f.rows()).single, before);
      final export = syncFailureDiagnosticsJson(
        f.repo.state.syncFailures,
        transfer: f.repo.state.syncTransfer,
      );
      expect(export, contains('appliedContentRecords'));
      expect(export, isNot(contains(id)));
      expect(export, isNot(contains('Remote change')));
      // A later unchanged probe must not carry old success counts into its attempt.
      await f.repo.syncNow();
      expect(f.repo.state.syncTransfer!.contentPages, 0);
      await f.repo.signOut();
      expect(f.repo.state.syncTransfer, isNull);
      expect(f.repo.state.syncFailures, isEmpty);
    },
  );
  for (final mode in ['denied', 'rejected']) {
    test(
      'final pass preserves current $mode outcome separately from retained rotation',
      () async {
        final f = await fixture();
        await held(f, mode: mode);
        await f.repo.syncNow(manual: true);
        final sample = f.repo.state.syncFailures
            .singleWhere((x) => x.heldDiagnostics != null)
            .heldDiagnostics!
            .samples
            .single;
        expect(
          sample.receipt,
          mode == 'denied'
              ? HeldReceiptResult.denied
              : HeldReceiptResult.rejected,
        );
        expect(sample.retainedReason, 'scope_reauthorization_required');
        if (mode == 'denied') {
          expect(sample.currentReason, 'crypto_receipt_scope_required');
        }
        expect(f.repo.state.blockedSyncCommandCount, 1);
      },
    );
  }
  test(
    'failed content transaction is not reported as a received page',
    () async {
      final f = await fixture();
      final scope = await f.repo.createScope('Synthetic');
      await f.repo.syncNow();
      await held(f);
      f.db.beforeExecute = (sql, args) async {
        if (sql == 'UPDATE scopes SET cursor=? WHERE partition=? AND id=?' &&
            args.last == scope) {
          throw StateError('synthetic transaction failure');
        }
      };
      await f.repo.syncNow(manual: true);
      expect(f.repo.state.syncTransfer!.contentPages, 0);
      expect(f.repo.state.lastError, isNotNull);
    },
  );
  test(
    'diagnostic database failure retains blocker without aborting valid content pass',
    () async {
      final f = await fixture();
      await held(f);
      f.db.beforeRows = (sql, args) async {
        if (sql.startsWith('SELECT COUNT(*) AS n FROM crypto_outbox')) {
          throw StateError('diagnostic only');
        }
      };
      await f.repo.syncNow(manual: true);
      expect(f.repo.state.blockedSyncCommandCount, 1);
      final failure = f.repo.state.syncFailures.singleWhere(
        (x) => x.reason == 'crypto_command_receipt_pending',
      );
      expect(failure.heldDiagnostics, isNull);
    },
  );
  test(
    'settled neighbour does not leak its reason into the remaining held sample',
    () async {
      final f = await fixture();
      final settled = await held(f, mode: 'applied');
      final pending = await held(f, mode: 'denied');
      await f.repo.syncNow(manual: true);
      final detail = f.repo.state.syncFailures
          .singleWhere((x) => x.heldDiagnostics != null)
          .heldDiagnostics!;
      expect(detail.remaining, 1);
      expect(detail.samples, hasLength(1));
      expect(detail.samples.single.receipt, HeldReceiptResult.denied);
      expect(
        detail.samples.single.currentReason,
        'crypto_receipt_scope_required',
      );
      final rows = await f.rows();
      expect(
        rows.singleWhere((r) => r['request_id'] == settled)['state'],
        'applied',
      );
      expect(
        rows.singleWhere((r) => r['request_id'] == pending)['state'],
        'blocked',
      );
    },
  );
  test('changed command hash cannot inherit a prior observation', () async {
    final f = await fixture();
    final id = await held(f, mode: 'denied');
    f.transport.beforeScopes = () async {
      f.transport.beforeScopes = null;
      await f.db.execute(
        'UPDATE crypto_outbox SET request_hash=? WHERE request_id=?',
        ['0' * 64, id],
      );
    };
    await f.repo.syncNow(manual: true);
    final sample = f.repo.state.syncFailures
        .singleWhere((x) => x.heldDiagnostics != null)
        .heldDiagnostics!
        .samples
        .single;
    expect(sample.receipt, HeldReceiptResult.notChecked);
    expect(sample.currentReason, isNull);
    expect(f.repo.state.blockedSyncCommandCount, 1);
  });
  test(
    'over-limit inventory exports a bounded unattempted sample without receipt traffic',
    () async {
      final f = await fixture();
      for (var i = 0; i < 65; i++) {
        await f.held();
      }
      f.transport.calls.clear();
      await f.repo.syncNow(manual: true);
      final details = f.repo.state.syncFailures
          .firstWhere((x) => x.heldDiagnostics != null)
          .heldDiagnostics!;
      expect(details.remaining, 65);
      expect(details.samples, hasLength(20));
      expect(
        details.samples.every(
          (x) =>
              x.receipt == HeldReceiptResult.notChecked &&
              x.resume == HeldResumeResult.notAttempted,
        ),
        true,
      );
      expect(
        f.transport.calls.where((x) => x == 'crypto2.receipt.get'),
        isEmpty,
      );
      expect(f.repo.state.blockedSyncCommandCount, 65);
    },
  );
}
