import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/data/collaboration_sync_diagnostics.dart';
import 'package:kanban/organizer/data/collaboration_transport.dart';
import 'package:kanban/organizer/data/device_session_store.dart';
import 'package:kanban/organizer/data/e2ee/crypto_domain_router.dart';

import '../support/synthetic_content_route_guard.dart';
import 'collaboration_repository_test.dart' show FakeServer, MemorySessionStore;
import 'organization_finance_client_test.dart'
    show OrganizationFinanceTransport;

// Real repository/SQLite selection and durable cursor handling, with explicit
// legacy transport seams. This does not verify a server cursor HMAC or E2EE.
class _LegacyRouter implements CryptoDomainRouter {
  @override
  Future<Map<String, dynamic>> dispatch({
    required DeviceSession session,
    required String operation,
    required Map<String, Object?> params,
    required Set<String> protectedScopeIds,
  }) async =>
      throw StateError('Protected dispatch is not part of this fixture');
}

class _Transport extends OrganizationFinanceTransport {
  _Transport(super.server, this.store);
  final MemorySessionStore store;
  final calls = <({String op, Map<String, Object?> params})>[];
  final probes = <Object?>[];
  Map<String, List<String>> hints = {};
  List<String> accountHints = [];
  String cursor = 'warm-v1';
  bool rejectSaved = false, failPull = false, throwDiagnostics = false;
  Future<void> Function()? onNullProbe;

  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
    calls.add((op: operation, params: Map.of(params)));
    if (operation == 'account.changes') {
      probes.add(params['cursor']);
      if (rejectSaved && params['cursor'] != null) {
        throw const CollaborationApiException('invalid_cursor');
      }
      if (params['cursor'] == null) await onNullProbe?.call();
      final profile = store.value!.profile;
      final reset = params['cursor'] == null;
      return {
        'version': 1,
        'directoryHintsVersion': 1,
        'serverId': profile.serverId,
        'accountId': profile.accountId,
        'deviceId': profile.deviceId,
        'cursor': cursor,
        'changed': reset || hints.isNotEmpty || accountHints.isNotEmpty,
        'resetRequired': reset,
        'hasMore': false,
        'accountDomains': accountHints,
        'scopes': [
          for (final e in hints.entries) {'scopeId': e.key, 'domains': e.value},
        ],
      };
    }
    if (failPull &&
        operation.startsWith('sync') &&
        operation.endsWith('.pull')) {
      throw const CollaborationApiException('network');
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
          }
        : reply;
  }
}

class _Fixture {
  _Fixture(this.db, this.store, this.transport, this.repo, this.events);
  final CollaborationDatabase db;
  final MemorySessionStore store;
  final _Transport transport;
  CollaborationRepository repo;
  final List<CollaborationSyncDiagnostic> events;
  String get cursorKey {
    final p = store.value!.profile;
    return 'account_changes_v1:${p.partition}:${p.deviceId}';
  }

  Future<String?> saved() async =>
      (await db.rows('SELECT value FROM local_meta WHERE name=?', [
            cursorKey,
          ])).firstOrNull?['value']
          as String?;

  Set<String> pulls(String domain) => transport.calls
      .where(
        (c) =>
            c.op.endsWith('.pull') &&
            (domain == 'finance'
                ? c.op.startsWith('finance')
                : c.op.startsWith('sync')),
      )
      .map((c) => c.params['scopeId'] as String)
      .toSet();
  List<CollaborationSyncDiagnosticKind> get reasons => events
      .map((e) => e.kind)
      .where((k) => k.name.startsWith('selection'))
      .toList();
  CollaborationSyncDiagnostic get selected => events.lastWhere(
    (e) => e.kind == CollaborationSyncDiagnosticKind.selectedWork,
  );
  void clear() {
    transport.calls.clear();
    transport.probes.clear();
    events.clear();
  }

  Future<void> reopen() async {
    await repo.close();
    repo = _repository(db, transport, store, events);
    await repo.initialize();
    clear();
  }
}

CollaborationRepository _repository(
  CollaborationDatabase db,
  _Transport transport,
  MemorySessionStore store,
  List<CollaborationSyncDiagnostic> events,
) => CollaborationRepository(
  db,
  transport,
  store,
  ownsDatabase: false,
  contentRouteGuard: const SyntheticContentRouteGuard(),
  cryptoRouter: _LegacyRouter(),
  syncDiagnostics: CollaborationSyncDiagnostics(
    onEvent: (event) {
      events.add(event);
      if (transport.throwDiagnostics) throw StateError('Observer failure');
    },
  ),
);

Future<_Fixture> _open() async {
  final db = CollaborationDatabase(NativeDatabase.memory());
  final store = MemorySessionStore();
  final transport = _Transport(FakeServer(), store)..seed(parentAccess: true);
  final events = <CollaborationSyncDiagnostic>[];
  final f = _Fixture(
    db,
    store,
    transport,
    _repository(db, transport, store, events),
    events,
  );
  addTearDown(() async {
    await f.repo.close();
    await db.close();
  });
  await f.repo.initialize();
  await f.repo.login(
    serverUrl: 'https://example.test/',
    username: 'alice',
    password: 'synthetic',
  );
  await f.repo.syncNow();
  expect(f.repo.state.lastError, isNull);
  expect(await f.saved(), 'warm-v1');
  expect(f.repo.state.scopes, hasLength(2));
  expect(f.repo.state.financeSupported, isTrue);
  f.clear();
  return f;
}

void main() {
  test(
    'warm repository resume keeps one content scope and zero finance despite enabled finance',
    () async {
      final f = await _open();
      await f.reopen();
      f.transport.throwDiagnostics = true;
      f.transport.hints = {
        f.transport.project: ['content'],
      };
      f.transport.cursor = 'content-v1';
      await f.repo.syncNow();
      expect(f.repo.state.lastError, isNull);
      expect(f.transport.probes, ['warm-v1']);
      expect(f.pulls('content'), {f.transport.project});
      expect(f.pulls('finance'), isEmpty);
      expect(f.transport.calls.any((c) => c.op == 'scopes.list'), isFalse);
      expect(f.selected.contentScopeCount, 1);
      expect(f.selected.financeScopeCount, 0);
      expect(f.reasons, [CollaborationSyncDiagnosticKind.selectionContentHint]);
      expect(await f.saved(), 'content-v1');
      f.clear();
      f.transport.hints = {};
      await f.repo.syncNow();
      expect(f.transport.calls.map((c) => c.op), ['account.changes']);
      expect(
        f.events.map((e) => e.kind),
        contains(CollaborationSyncDiagnosticKind.unchanged),
      );
      expect(f.reasons, isEmpty);
    },
  );

  test(
    'missing device cursor reset retains all content and finance selection after explicit invalidation',
    () async {
      final f = await _open();
      await f.repo.invalidateAccountChangesCursor();
      await f.reopen();
      f.transport.cursor = 'reset-v1';
      await f.repo.syncNow();
      expect(f.repo.state.lastError, isNull);
      expect(f.transport.probes, [null]);
      expect(f.selected.contentScopeCount, 2);
      expect(f.selected.financeScopeCount, 2);
      expect(f.pulls('content'), {f.transport.parent, f.transport.project});
      expect(f.pulls('finance'), {f.transport.parent, f.transport.project});
      expect(
        f.reasons,
        containsAll([
          CollaborationSyncDiagnosticKind.selectionMissingCursor,
          CollaborationSyncDiagnosticKind.selectionReset,
          CollaborationSyncDiagnosticKind.selectionParentFinanceDependency,
        ]),
      );
      expect(await f.saved(), 'reset-v1');
    },
  );

  test(
    'accepted old cursor plus conservative access hints stays broad and emits each reason once',
    () async {
      final f = await _open();
      await f.reopen();
      f.transport.accountHints = ['access'];
      f.transport.hints = {
        f.transport.parent: ['access'],
        f.transport.project: ['access'],
      };
      f.transport.cursor = 'semantic-vector-v1';
      await f.repo.syncNow();
      expect(f.repo.state.lastError, isNull);
      expect(f.transport.probes, ['warm-v1']);
      expect(f.selected.contentScopeCount, 2);
      expect(f.selected.financeScopeCount, 2);
      expect(
        f.reasons,
        containsAll([
          CollaborationSyncDiagnosticKind.selectionAccountAccess,
          CollaborationSyncDiagnosticKind.selectionScopeAccess,
        ]),
      );
      expect(
        f.reasons.where(
          (k) => k == CollaborationSyncDiagnosticKind.selectionScopeAccess,
        ),
        hasLength(1),
      );
      expect(
        f.reasons,
        isNot(contains(CollaborationSyncDiagnosticKind.selectionReset)),
      );
      expect(
        f.reasons,
        isNot(
          contains(CollaborationSyncDiagnosticKind.selectionRejectedCursor),
        ),
      );
      expect(await f.saved(), 'semantic-vector-v1');
    },
  );

  test(
    'invalid cursor recovery preserves old durable cursor through failed apply then acknowledges successful recovery',
    () async {
      final f = await _open();
      f.transport.rejectSaved = true;
      f.transport.failPull = true;
      f.transport.cursor = 'replacement-v1';
      var oldObserved = 0;
      f.transport.onNullProbe = () async {
        expect(await f.saved(), 'warm-v1');
        oldObserved++;
      };
      await f.repo.syncNow();
      expect(f.repo.state.lastError, isNotNull);
      expect(f.transport.probes, ['warm-v1', null]);
      expect(await f.saved(), 'warm-v1');
      expect(
        f.reasons,
        containsAll([
          CollaborationSyncDiagnosticKind.selectionRejectedCursor,
          CollaborationSyncDiagnosticKind.selectionReset,
        ]),
      );
      f.clear();
      f.transport.failPull = false;
      await f.repo.syncNow(manual: true);
      expect(f.repo.state.lastError, isNull);
      expect(f.transport.probes, ['warm-v1', null]);
      expect(oldObserved, 2);
      expect(await f.saved(), 'replacement-v1');
    },
  );

  test(
    'access keyset hint still reconciles revocation before any domain pull',
    () async {
      final f = await _open();
      f.transport.server.confirmRevocation(f.transport.project, 'alice');
      f.transport.accountHints = ['access'];
      f.transport.cursor = 'revoked-v1';
      await f.repo.syncNow();
      expect(f.repo.state.lastError, isNull);
      expect(
        f.repo.state.scopes
            .singleWhere((s) => s.id == f.transport.project)
            .revoked,
        isTrue,
      );
      expect(f.repo.state.data.containsKey(f.transport.project), isFalse);
      expect(f.transport.calls.any((c) => c.op == 'scopes.list'), isTrue);
      expect(f.pulls('content'), isEmpty);
      expect(f.pulls('finance'), isEmpty);
      expect(f.reasons, [
        CollaborationSyncDiagnosticKind.selectionAccountAccess,
      ]);
      expect(await f.saved(), 'revoked-v1');
    },
  );

  test(
    'unknown scope content hint discovers current scope without adding unrelated finance',
    () async {
      final f = await _open();
      final id = newSharedId();
      f.transport.server.scopes[id] = {
        'id': id,
        'name': 'New scope',
        'kind': 'household',
        'sequence': 0,
      };
      f.transport.server.members[id] = {'alice': 'owner'};
      f.transport.server.records[id] = {};
      f.transport.server.sequence[id] = 0;
      f.transport.hints = {
        id: ['content'],
      };
      f.transport.cursor = 'discovered-v1';
      await f.repo.syncNow();
      expect(f.repo.state.lastError, isNull);
      expect(f.transport.calls.any((c) => c.op == 'scopes.list'), isTrue);
      expect(f.pulls('content'), {id});
      expect(f.pulls('finance'), isEmpty);
      expect(
        f.reasons,
        containsAll([
          CollaborationSyncDiagnosticKind.selectionContentHint,
          CollaborationSyncDiagnosticKind.selectionUnknownScope,
        ]),
      );
      expect(await f.saved(), 'discovered-v1');
    },
  );
}
