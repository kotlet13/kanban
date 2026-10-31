import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/data/collaboration_transport.dart';
import 'package:kanban/organizer/data/device_session_store.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_v2.dart';
import 'package:kanban/organizer/data/e2ee/crypto_domain_router.dart';
import 'package:kanban/organizer/data/e2ee/crypto_sync_repository.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';

import '../support/synthetic_content_route_guard.dart';
import 'collaboration_repository_test.dart'
    show FakeServer, FakeTransport, MemorySessionStore;
import 'organization_finance_client_test.dart'
    show OrganizationFinanceTransport;

// Explicit legacy fake transport seam. These controls verify repository error
// provenance/lifecycle only, without claiming signed HTTP/native/E2EE coverage.
class _LegacyRouter implements CryptoDomainRouter {
  @override
  Future<Map<String, dynamic>> dispatch({
    required DeviceSession session,
    required String operation,
    required Map<String, Object?> params,
    required Set<String> protectedScopeIds,
  }) async => throw StateError('Synthetic guard must retain legacy route');
}

class _UnreadablePending extends CryptoAuthorityPending {
  const _UnreadablePending() : super('synthetic');
  @override
  String get reason =>
      throw StateError('Synthetic optional diagnostic read failure');
}

class _Transport extends FakeTransport {
  _Transport(super.server, this.store);
  final MemorySessionStore store;
  final hints = <String, List<String>>{};
  bool memberDirectory = false;
  Object? Function(String, Map<String, Object?>)? failOn;
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
    final error = failOn?.call(operation, params);
    if (error != null) throw error;
    if (operation == 'account.changes') {
      final profile = store.value!.profile;
      return {
        'version': 1,
        'serverId': profile.serverId,
        'accountId': profile.accountId,
        'deviceId': profile.deviceId,
        'cursor': 'synthetic-cursor',
        'changed': params['cursor'] == null || hints.isNotEmpty,
        'resetRequired': params['cursor'] == null,
        'hasMore': false,
        'accountDomains': <String>[],
        'scopes': [
          for (final e in hints.entries) {'scopeId': e.key, 'domains': e.value},
        ],
      };
    }
    if (memberDirectory && operation == 'scopes.members') {
      return {'members': <Object>[]};
    }
    final reply = await super.call(
      serverUrl: serverUrl,
      operation: operation == 'sync2.pull' ? 'sync.pull' : operation,
      params: params,
      token: token,
      allowLocalHttp: allowLocalHttp,
    );
    return operation == 'capabilities'
        ? {
            ...reply,
            'accountChangeVersions': [1],
            if (memberDirectory) 'recordContractVersions': [1, 2],
          }
        : reply;
  }
}

class _Fixture {
  _Fixture(this.repo, this.transport, this.scopes);
  final CollaborationRepository repo;
  final _Transport transport;
  final List<String> scopes;
  var now = DateTime.utc(2026, 10, 31, 14);
  DateTime clock() => now;

  void selectAll() {
    transport.hints.clear();
    for (final scope in scopes) {
      transport.hints[scope] = ['content'];
    }
  }
}

class _FinanceTransport extends OrganizationFinanceTransport {
  _FinanceTransport(super.server);
  String? failedOperation;
  Object? failure;
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
    if (operation == failedOperation && failure != null) throw failure!;
    return super.call(
      serverUrl: serverUrl,
      operation: operation,
      params: params,
      token: token,
      allowLocalHttp: allowLocalHttp,
    );
  }
}

void main() {
  Future<_Fixture> setup({int count = 2, bool memberDirectory = false}) async {
    final server = FakeServer(), store = MemorySessionStore();
    final scopes = List.generate(count, (_) => newSharedId());
    for (final scope in scopes) {
      server.scopes[scope] = {
        'id': scope,
        'name': 'Private local display name',
        'kind': 'household',
        'sequence': 0,
      };
      server.members[scope] = {'alice': 'owner'};
      server.records[scope] = {};
      server.sequence[scope] = 0;
    }
    final transport = _Transport(server, store)
      ..memberDirectory = memberDirectory;
    late _Fixture fixture;
    final repo = CollaborationRepository(
      CollaborationDatabase(NativeDatabase.memory()),
      transport,
      store,
      contentRouteGuard: const SyntheticContentRouteGuard(),
      cryptoRouter: _LegacyRouter(),
      clock: () => fixture.clock(),
    );
    fixture = _Fixture(repo, transport, scopes);
    addTearDown(repo.close);
    await repo.initialize();
    await repo.login(
      serverUrl: 'https://example.test/',
      username: 'alice',
      password: 'synthetic',
    );
    expect(repo.state.lastError, isNull);
    expect(repo.state.syncFailures, isEmpty);
    return fixture;
  }

  test(
    'diagnostic schema excludes local IDs and arbitrary text, bounds output and preserves immutable cheap clone',
    () {
      final at = DateTime.utc(2026, 10, 31);
      final failures = List.generate(
        23,
        (i) => SyncFailureDetails(
          stage: SyncFailureStage.download,
          occurredAt: at.add(Duration(seconds: i)),
          reason: i == 22
              ? 'https://private.test/key=secret'
              : 'scope_key_recovery_required',
          scopeId: 'private-scope-$i',
        ),
      );
      final encoded = syncFailureDiagnosticsJson(failures);
      final decoded = jsonDecode(encoded) as Map;
      expect(decoded.keys, unorderedEquals(['version', 'syncFailures']));
      final entries = decoded['syncFailures'] as List;
      expect(entries, hasLength(20));
      expect(entries.last['reason'], 'unknown');
      expect(
        entries.every(
          (e) => (e as Map).keys.toSet().difference({
            'stage',
            'reason',
            'occurredAt',
          }).isEmpty,
        ),
        isTrue,
      );
      expect(encoded, isNot(contains('private')));
      expect(encoded, isNot(contains('secret')));
      final state = CollaborationState(syncFailures: failures);
      failures.clear();
      expect(state.syncFailures, hasLength(23));
      expect(() => state.syncFailures.clear(), throwsUnsupportedError);
      final clone = CollaborationState.withChangeCheckEvidence(
        state,
        lastChangeCheckAttemptAt: at,
        lastSuccessfulChangeCheckAt: at,
        lastError: null,
        syncRequiresRefresh: false,
        hasUnresolvedSyncWork: false,
      );
      expect(identical(clone.syncFailures, state.syncFailures), isTrue);
      final fallback = SyncFailureDetails(
        stage: SyncFailureStage.unknown,
        occurredAt: null,
        reason: 'network',
      );
      expect(fallback.toSafeDiagnosticJson(), {
        'stage': 'unknown',
        'reason': 'network',
      });
    },
  );

  test(
    'same canonical crypto error in two scopes retains both exact reasons, then retry and signout clear',
    () async {
      final f = await setup();
      const error = CryptoAuthorityPending('scope_key_recovery_required');
      f.selectAll();
      f.transport.failOn = (operation, _) =>
          operation == 'sync.pull' ? error : null;
      await f.repo.syncNow(manual: true);
      expect(f.repo.state.lastError?.code, 'crypto_reconciliation_required');
      expect(
        f.repo.state.syncFailures.map((e) => e.scopeId),
        unorderedEquals(f.scopes),
      );
      expect(
        f.repo.state.syncFailures.every(
          (e) =>
              e.reason == error.reason && e.stage == SyncFailureStage.download,
        ),
        isTrue,
      );
      expect(
        f.repo.state.syncFailures.every((e) => e.occurredAt == f.now),
        isTrue,
      );
      f.transport.failOn = null;
      await f.repo.syncNow(manual: true);
      expect(f.repo.state.lastError, isNull);
      expect(f.repo.state.syncFailures, isEmpty);
      f.transport.failOn = (operation, _) =>
          operation == 'sync.pull' ? error : null;
      await f.repo.syncNow(manual: true);
      expect(f.repo.state.syncFailures, hasLength(2));
      await f.repo.signOut();
      expect(f.repo.state.session, isNull);
      expect(f.repo.state.syncFailures, isEmpty);
    },
  );

  test(
    'probe failure and cheap recovery preserve scoped failure; same const probe error can recur',
    () async {
      final f = await setup();
      f.selectAll();
      f.transport.failOn = (operation, _) => operation == 'sync.pull'
          ? const CryptoAuthorityPending('scope_key_recovery_required')
          : null;
      await f.repo.syncNow(manual: true);
      f.transport.hints.clear();
      const probe = CryptoAuthorityPending('crypto_stale_identity');
      f.transport.failOn = (operation, _) =>
          operation == 'account.changes' ? probe : null;
      await expectLater(f.repo.syncNow(manual: true), throwsA(same(probe)));
      expect(f.repo.state.lastError?.code, 'invalid_response');
      expect(
        f.repo.state.syncFailures.where((e) => e.scopeId == null).single.reason,
        probe.reason,
      );
      f.transport.failOn = null;
      await f.repo.syncNow(manual: true);
      expect(
        f.repo.state.syncFailures.map((e) => e.scopeId),
        unorderedEquals(f.scopes),
      );
      f.now = f.now.add(const Duration(minutes: 1));
      f.transport.failOn = (operation, _) =>
          operation == 'account.changes' ? probe : null;
      await expectLater(f.repo.syncNow(manual: true), throwsA(same(probe)));
      final recurrent = f.repo.state.syncFailures
          .where((e) => e.scopeId == null)
          .single;
      expect(recurrent.reason, probe.reason);
      expect(recurrent.occurredAt, f.now);
    },
  );

  test(
    'selected unrelated transfer preserves old scoped issue until its own retry',
    () async {
      final f = await setup();
      final a = f.scopes.first, b = f.scopes.last;
      f.transport.hints[a] = ['content'];
      f.transport.failOn = (operation, params) =>
          operation == 'sync.pull' && params['scopeId'] == a
          ? const CryptoAuthorityPending('scope_key_recovery_required')
          : null;
      await f.repo.syncNow(manual: true);
      expect(f.repo.state.syncFailures.single.scopeId, a);
      f.transport.failOn = null;
      f.transport.hints
        ..clear()
        ..[b] = ['access'];
      await f.repo.syncNow(manual: true);
      expect(f.repo.state.lastError, isNull);
      expect(f.repo.state.syncFailures.single.scopeId, a);
      f.transport.hints
        ..clear()
        ..[a] = ['content'];
      await f.repo.syncNow(manual: true);
      expect(f.repo.state.syncFailures, isEmpty);
    },
  );

  test('member metadata clears only on its actual access retry', () async {
    final f = await setup(memberDirectory: true);
    final a = f.scopes.first, b = f.scopes.last;
    f.transport.hints[a] = ['access'];
    f.transport.failOn = (operation, params) =>
        operation == 'scopes.members' && params['scopeId'] == a
        ? const CryptoAuthorityPending('scope_key_recovery_required')
        : null;
    await f.repo.syncNow(manual: true);
    expect(f.repo.state.syncFailures.single.scopeId, a);
    expect(f.repo.state.syncFailures.single.stage, SyncFailureStage.metadata);
    f.transport.failOn = null;
    f.transport.hints
      ..clear()
      ..[b] = ['access'];
    await f.repo.syncNow(manual: true);
    expect(f.repo.state.lastError, isNull);
    expect(f.repo.state.syncFailures.single.scopeId, a);
    f.transport.hints
      ..clear()
      ..[a] = ['access'];
    await f.repo.syncNow(manual: true);
    expect(f.repo.state.syncFailures, isEmpty);
  });

  test(
    'retained local failure list is bounded and safe export omits real scope and account metadata',
    () async {
      final f = await setup(count: 23);
      f.selectAll();
      f.transport.failOn = (operation, _) => operation == 'sync.pull'
          ? const CryptoAuthorityPending('scope_key_recovery_required')
          : null;
      await f.repo.syncNow(manual: true);
      expect(f.repo.state.syncFailures, hasLength(20));
      final report = syncFailureDiagnosticsJson(f.repo.state.syncFailures);
      for (final secret in [
        ...f.scopes,
        f.repo.state.session!.accountId,
        'Private local display name',
        'https://example.test/',
      ]) {
        expect(report, isNot(contains(secret)));
      }
    },
  );

  test(
    'directory code survives generic conversion and optional diagnostic failure cannot alter sync outcome',
    () async {
      final f = await setup();
      f.selectAll();
      f.transport.failOn = (operation, _) => operation == 'sync.pull'
          ? const CryptoDirectoryException('directory_anchor_fork')
          : null;
      await f.repo.syncNow(manual: true);
      expect(f.repo.state.lastError?.code, 'invalid_response');
      expect(f.repo.state.syncFailures.single.reason, 'directory_anchor_fork');
      f.transport.failOn = (operation, _) =>
          operation == 'sync.pull' ? const _UnreadablePending() : null;
      await f.repo.syncNow(manual: true);
      expect(f.repo.state.lastError?.code, 'crypto_reconciliation_required');
      expect(f.repo.state.syncFailures, isEmpty);
      expect(
        f.repo.lastSyncCompletion?.error,
        isA<CollaborationException>().having(
          (e) => e.code,
          'code',
          'crypto_reconciliation_required',
        ),
      );
    },
  );

  test(
    'finance crypto download retains original scoped reason and ordinary policy denial stays quiet',
    () async {
      final server = FakeServer();
      final transport = _FinanceTransport(server)..seed();
      final repo = CollaborationRepository(
        CollaborationDatabase(NativeDatabase.memory()),
        transport,
        MemorySessionStore(),
        contentRouteGuard: const SyntheticContentRouteGuard(),
        cryptoRouter: _LegacyRouter(),
      );
      addTearDown(repo.close);
      await repo.initialize();
      await repo.login(
        serverUrl: 'https://example.test/',
        username: 'alice',
        password: 'synthetic',
      );
      expect(repo.state.lastError, isNull);
      transport.failedOperation = 'finance4.pull';
      transport.failure = const CryptoAuthorityPending(
        'finance_key_contribution_required',
      );
      await repo.syncNow(manual: true);
      expect(repo.state.lastError?.code, 'crypto_reconciliation_required');
      final failure = repo.state.syncFailures.single;
      expect(failure.scopeId, transport.project);
      expect(failure.stage, SyncFailureStage.financeDownload);
      expect(failure.reason, 'finance_key_contribution_required');
      transport.failedOperation = 'finance4.policy';
      transport.failure = const CollaborationApiException('finance_forbidden');
      await repo.syncNow(manual: true);
      expect(repo.state.lastError, isNull);
      expect(repo.state.syncFailures, isEmpty);
    },
  );
}
