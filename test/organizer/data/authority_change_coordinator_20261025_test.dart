import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/authority_reuse_controller.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/data/collaboration_transport.dart';
import 'package:kanban/organizer/data/device_session_store.dart';
import 'package:kanban/organizer/data/e2ee/crypto_domain_router.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';

import '../support/synthetic_content_route_guard.dart';
import 'collaboration_repository_test.dart'
    show FakeServer, FakeTransport, MemorySessionStore;

class _Router implements CryptoDomainRouter, CryptoAccountDirectoryChanges {
  bool semanticChanged = false;
  int directoryRefreshes = 0;
  Future<void> Function()? directoryGate;
  @override
  Future<bool> refreshAccountDirectory({required DeviceSession session}) async {
    directoryRefreshes++;
    await directoryGate?.call();
    return semanticChanged;
  }

  @override
  Future<Map<String, dynamic>> dispatch({
    required DeviceSession session,
    required String operation,
    required Map<String, Object?> params,
    required Set<String> protectedScopeIds,
  }) async => throw StateError('Unexpected protected dispatch');
}

class _Transport extends FakeTransport {
  _Transport(super.server, this.store);
  final MemorySessionStore store;
  final operations = <String>[];
  String cursor = 'authority-cursor';
  bool labelsV2 = false;
  List<String> domains = [];
  Map<String, List<String>> scopes = {};
  bool reset = false,
      invalidCursor = false,
      malformed = false,
      supported = true;
  Object? failure;
  Future<void> Function()? probeGate;
  void Function()? beforeScopeRead;

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
      if (failure != null) throw failure!;
      if (invalidCursor && params['cursor'] != null) {
        throw const CollaborationApiException('invalid_cursor');
      }
      await probeGate?.call();
      final p = store.value!.profile;
      final resetting = reset || params['cursor'] == null;
      return {
        'version': 1,
        'serverId': malformed ? 'foreign' : p.serverId,
        'accountId': p.accountId,
        'deviceId': p.deviceId,
        'cursor': cursor,
        'changed': resetting || domains.isNotEmpty || scopes.isNotEmpty,
        'resetRequired': resetting,
        'hasMore': false,
        'directoryHintsVersion': 1,
        'accountDomains': domains,
        'scopes': [
          for (final e in scopes.entries)
            {'scopeId': e.key, 'domains': e.value},
        ],
      };
    }
    if (labelsV2 && operation == 'scopes.members') {
      return {
        'members': [
          {
            'userId': store.value!.profile.userId,
            'accountId': store.value!.profile.accountId,
            'username': 'alice',
            'displayName': 'Alice',
            'role': 'owner',
            'active': true,
          },
        ],
      };
    }
    if (operation == 'scopes.list') beforeScopeRead?.call();
    if (operation == 'test.denial') throw failure!;
    final result = await super.call(
      serverUrl: serverUrl,
      operation: labelsV2 && operation == 'sync2.pull'
          ? 'sync.pull'
          : operation,
      params: params,
      token: token,
      allowLocalHttp: allowLocalHttp,
    );
    return operation == 'capabilities'
        ? {
            ...result,
            'accountChangeVersions': supported ? [1] : <int>[],
            if (labelsV2) 'recordContractVersions': [1, 2],
          }
        : result;
  }
}

class _Fixture {
  _Fixture(this.repo, this.transport, this.router, this.a, this.b);
  final CollaborationRepository repo;
  final _Transport transport;
  final _Router router;
  final String a, b;
  AuthorityReuseController get authority => repo.authorityReuse;
}

Future<_Fixture> _setup({bool labelsV2 = false}) async {
  final store = MemorySessionStore(), server = FakeServer();
  final transport = _Transport(server, store)..labelsV2 = labelsV2;
  final router = _Router();
  final repo = CollaborationRepository(
    CollaborationDatabase(NativeDatabase.memory()),
    transport,
    store,
    contentRouteGuard: const SyntheticContentRouteGuard(),
    cryptoRouter: router,
  );
  addTearDown(repo.close);
  await repo.initialize();
  await repo.login(
    serverUrl: 'https://example.test/',
    username: 'alice',
    password: 'synthetic',
  );
  final a = await repo.createScope('Authority A');
  final b = await repo.createScope('Independent B');
  await repo.syncNow();
  expect(repo.state.lastError, isNull);
  expect(repo.authorityReuse.enabled, isTrue);
  transport.operations.clear();
  return _Fixture(repo, transport, router, a, b);
}

void main() {
  test(
    'P6 targeted access selection leaves independent scope directory cached',
    () async {
      final f = await _setup(labelsV2: true);
      f.transport.cursor = 'targeted-label-change';
      f.transport.scopes = {
        f.a: ['access'],
      };
      await f.repo.syncNow();
      expect(f.repo.state.lastError, isNull);
      final reads = f.transport.operations.where(
        (op) => op == 'scopes.members',
      );
      expect(reads.length, 1);
      expect(f.repo.state.membersForScope(f.b), isNotEmpty);
    },
  );

  test(
    'P6 content hint leaves member reads and sharing generations alone',
    () async {
      final f = await _setup();
      final before = f.repo.state.sharingRefresh;
      await f.repo.database.execute(
        "UPDATE local_meta SET value='0' WHERE name LIKE 'member_directory_at:%'",
      );
      f.transport.cursor = 'content-only';
      f.transport.scopes = {
        f.a: ['content'],
      };
      await f.repo.syncNow();
      expect(f.repo.state.lastError, isNull);
      expect(
        f.transport.operations.where((op) => op == 'scopes.members'),
        isEmpty,
      );
      expect(f.repo.state.sharingRefresh.forScope(f.a), before.forScope(f.a));
      expect(f.repo.state.sharingRefresh.invitations, before.invitations);
      expect(f.repo.state.sharingRefresh.coordinated, true);
    },
  );
  test(
    'P6 scope access hint refreshes fresh labels and only affected display',
    () async {
      final f = await _setup(labelsV2: true);
      final before = f.repo.state.sharingRefresh;
      f.transport.cursor = 'access-a';
      f.transport.scopes = {
        f.a: ['access'],
      };
      await f.repo.syncNow();
      expect(f.repo.state.lastError, isNull);
      expect(
        f.transport.operations.where((op) => op == 'scopes.members'),
        isNotEmpty,
      );
      expect(
        f.repo.state.sharingRefresh.forScope(f.a),
        isNot(before.forScope(f.a)),
      );
      expect(f.repo.state.sharingRefresh.forScope(f.b), before.forScope(f.b));
      final after = f.repo.state.sharingRefresh;
      await f.repo
          .syncNow(); // same failed/stale hint must not amplify UI reloads
      expect(f.repo.state.sharingRefresh.forScope(f.a), after.forScope(f.a));
      f.transport.operations.clear();
      f.transport.cursor = 'v2-content';
      f.transport.scopes = {
        f.a: ['content'],
      };
      await f.repo.database.execute(
        "UPDATE local_meta SET value='0' WHERE name LIKE 'member_directory_at:%'",
      );
      await f.repo.syncNow();
      expect(f.repo.state.lastError, isNull);
      expect(
        f.transport.operations.where((op) => op == 'scopes.members'),
        isEmpty,
      );
    },
  );
  test(
    'P6 invitation hint wakes display without content or member fanout',
    () async {
      final f = await _setup();
      final before = f.repo.state.sharingRefresh.invitations;
      f.transport.cursor = 'invitation-arrival';
      f.transport.domains = ['invitations'];
      await f.repo.syncNow();
      expect(f.repo.state.lastError, isNull);
      expect(f.repo.state.sharingRefresh.invitations, before + 1);
      expect(
        f.transport.operations.where((op) => op == 'scopes.members'),
        isEmpty,
      );
      await f.repo.signOut();
      expect(f.repo.state.sharingRefresh.coordinated, false);
    },
  );

  test(
    'content and own journal preserve independent verified authority',
    () async {
      final f = await _setup();
      final own = f.authority.tokenForScope(null);
      final a = f.authority.tokenForScope(f.a);
      final b = f.authority.tokenForScope(f.b);
      final generation = f.authority.generation;
      f.transport.scopes = {
        f.a: ['content'],
      };
      await f.repo.syncNow();
      expect(f.repo.state.lastError, isNull);
      expect(f.authority.generation, generation);
      expect(identical(a, f.authority.tokenForScope(f.a)), isTrue);
      f.transport.scopes = {};
      f.transport.domains = ['directory'];
      await f.repo.syncNow();
      expect(f.router.directoryRefreshes, 1);
      expect(
        f.transport.operations.where((op) => op == 'scopes.list'),
        isEmpty,
      );
      expect(f.authority.generation, generation);
      expect(identical(own, f.authority.tokenForScope(null)), isTrue);
      expect(identical(b, f.authority.tokenForScope(f.b)), isTrue);
    },
  );

  test(
    'scope access retires affected proof before read and retains other space',
    () async {
      final f = await _setup();
      final a = f.authority.tokenForScope(f.a);
      final b = f.authority.tokenForScope(f.b);
      final own = f.authority.tokenForScope(null);
      f.transport.beforeScopeRead = () {
        expect(identical(a, f.authority.tokenForScope(f.a)), isFalse);
        expect(identical(b, f.authority.tokenForScope(f.b)), isTrue);
        expect(identical(own, f.authority.tokenForScope(null)), isTrue);
      };
      f.transport.scopes = {
        f.a: ['access'],
      };
      await f.repo.syncNow();
      expect(f.repo.state.lastError, isNull);
      expect(f.transport.operations, contains('scopes.list'));
    },
  );

  test(
    'child access retires known parent dependencies and keeps independent space',
    () async {
      final f = await _setup();
      final child = await f.repo.createScope('Child dependency');
      f.transport.server.scopes[child]!['parentScopeId'] = f.a;
      await f.repo.database.execute(
        "UPDATE scopes SET data=json_set(data,'\$.parentScopeId',?) WHERE partition=? AND id=?",
        [f.a, f.repo.state.session!.partition, child],
      );
      await f.repo.refreshLocal();
      final parentToken = f.authority.tokenForScope(f.a);
      final childToken = f.authority.tokenForScope(child);
      final otherToken = f.authority.tokenForScope(f.b);
      f.transport.beforeScopeRead = () {
        expect(identical(parentToken, f.authority.tokenForScope(f.a)), isFalse);
        expect(
          identical(childToken, f.authority.tokenForScope(child)),
          isFalse,
        );
        expect(identical(otherToken, f.authority.tokenForScope(f.b)), isTrue);
      };
      f.transport.scopes = {
        child: ['access'],
      };
      await f.repo.syncNow();
      expect(f.transport.operations, contains('scopes.list'));
      expect(f.repo.state.lastError, isNull);
    },
  );

  for (final trigger in [
    'reset',
    'account',
    'semantic',
    'unknown',
    'invalidCursor',
  ]) {
    test('$trigger retires global proof before access recovery', () async {
      final f = await _setup();
      final own = f.authority.tokenForScope(null);
      final b = f.authority.tokenForScope(f.b);
      f.transport.beforeScopeRead = () {
        expect(identical(own, f.authority.tokenForScope(null)), isFalse);
        expect(identical(b, f.authority.tokenForScope(f.b)), isFalse);
      };
      switch (trigger) {
        case 'reset':
          f.transport.reset = true;
        case 'account':
          f.transport.domains = ['metadata'];
        case 'semantic':
          f.transport.domains = ['directory'];
          f.router.semanticChanged = true;
        case 'unknown':
          f.transport.scopes = {
            '6eb7c934-9605-4bb7-b7af-9ecbc847346b': ['content'],
          };
        case 'invalidCursor':
          f.transport.invalidCursor = true;
      }
      await f.repo.syncNow();
      expect(f.transport.operations, contains('scopes.list'));
      expect(f.authority.enabled, isTrue);
    });
  }

  test(
    'late unchanged probe cannot enable after explicit cursor invalidation',
    () async {
      final f = await _setup();
      final entered = Completer<void>(), release = Completer<void>();
      f.transport.probeGate = () async {
        entered.complete();
        await release.future;
      };
      final pending = f.repo.syncNow();
      await entered.future;
      await f.repo.invalidateAccountChangesCursor();
      release.complete();
      await pending;
      expect(f.authority.enabled, isFalse);
      expect(f.transport.operations, ['account.changes']);
    },
  );

  test(
    'late semantic directory result cannot overwrite concurrent invalidation',
    () async {
      final f = await _setup();
      final entered = Completer<void>(), release = Completer<void>();
      f.transport.domains = ['directory'];
      f.router.semanticChanged = true;
      f.router.directoryGate = () async {
        entered.complete();
        await release.future;
      };
      final pending = f.repo.syncNow();
      await entered.future;
      f.authority.invalidate();
      release.complete();
      await pending;
      expect(f.transport.operations, contains('scopes.list'));
      expect(f.authority.enabled, isFalse);
      expect(f.repo.state.lastError, isNull);
    },
  );

  for (final malformed in [false, true]) {
    test(
      'failed probe disables reuse preserving exact local pending malformed=$malformed',
      () async {
        final f = await _setup();
        await f.repo.createTask(scopeId: f.a, title: 'Local draft retained');
        final before = await f.repo.database.rows('SELECT * FROM outbox');
        f.transport.malformed = malformed;
        if (!malformed) {
          f.transport.failure = const CollaborationApiException('network');
        }
        await expectLater(f.repo.syncNow(), throwsA(anything));
        expect(f.authority.enabled, isFalse);
        expect(await f.repo.database.rows('SELECT * FROM outbox'), before);
        expect(f.transport.operations, ['account.changes']);
      },
    );
  }

  test(
    'API denial retires scope but local document context does not',
    () async {
      final f = await _setup();
      Future<void> denial(Object error) async {
        f.transport.failure = error;
        final session = f.repo.state.session!;
        await expectLater(
          f.repo.transport.call(
            serverUrl: session.serverUrl,
            token: f.transport.store.value!.token,
            operation: 'test.denial',
            params: {'scopeId': f.a},
          ),
          throwsA(anything),
        );
      }

      final a = f.authority.tokenForScope(f.a);
      final b = f.authority.tokenForScope(f.b);
      await denial(const CollaborationException('document_context_changed'));
      expect(identical(a, f.authority.tokenForScope(f.a)), isTrue);
      for (final code in [
        'permission_revoked',
        'access_revoked',
        'scope_deleted',
        'crypto_scope_head_changed',
      ]) {
        final prior = f.authority.tokenForScope(f.a);
        await denial(CollaborationApiException(code));
        expect(identical(prior, f.authority.tokenForScope(f.a)), isFalse);
        expect(identical(b, f.authority.tokenForScope(f.b)), isTrue);
      }
      expect(f.authority.enabled, isTrue);
    },
  );

  test('sign out retires all proof and disables reuse', () async {
    final f = await _setup();
    final prior = f.authority.tokenForScope(f.a);
    await f.repo.signOut();
    expect(f.authority.enabled, isFalse);
    expect(identical(prior, f.authority.tokenForScope(f.a)), isFalse);
  });

  test(
    'legacy server fallback disables reuse before ordinary fresh sync',
    () async {
      final f = await _setup();
      f.transport.supported = false;
      await f.repo.database.execute(
        "UPDATE local_meta SET value=json_set(value,'\$.accountChangeVersions',json('[]')) WHERE name=?",
        ['capabilities:${f.repo.state.session!.partition}'],
      );
      f.transport.beforeScopeRead = () => expect(f.authority.enabled, isFalse);
      await f.repo.syncNow();
      expect(f.transport.operations, isNot(contains('account.changes')));
      expect(f.transport.operations, contains('scopes.list'));
      expect(f.authority.enabled, isFalse);
      expect(f.repo.state.lastError, isNull);
    },
  );
}
