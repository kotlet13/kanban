import 'dart:async';
import 'dart:io';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'collaboration_repository_test.dart'
    show FakeServer, FakeTransport, MemorySessionStore, code;

class RenewalServer extends FakeServer {
  DateTime now = DateTime.utc(2026, 10, 8);
  bool supported = true, loseReply = false;
  String? renewalError;
  Map<String, dynamic>? session;
  int renewals = 0;
  Completer<void>? entered, release;
  Map<String, dynamic> Function(Map<String, dynamic>)? alter;
  @override
  Future<Map<String, dynamic>> call(
    String operation,
    Map<String, Object?> params,
    String? token,
  ) async {
    if (operation == 'auth.renew' || operation == 'auth.me') {
      calls.add((operation: operation, token: token, params: params));
      if (operation == 'auth.renew') {
        renewals++;
        entered?.complete();
        await release?.future;
        if (renewalError != null) {
          throw CollaborationException(renewalError!);
        }
        if (tokens[token] == null) {
          throw const CollaborationException('device_revoked');
        }
        final device = session!['device'] as Map<String, dynamic>;
        final expiry = DateTime.fromMillisecondsSinceEpoch(
          (device['expiresAt'] as int) * 1000,
          isUtc: true,
        );
        if (!expiry.isAfter(now)) {
          throw const CollaborationException('device_revoked');
        }
        if (expiry.difference(now) <= const Duration(days: 7)) {
          device['expiresAt'] =
              now.add(const Duration(days: 30)).millisecondsSinceEpoch ~/ 1000;
        }
        if (loseReply) {
          loseReply = false;
          throw const CollaborationException('network');
        }
      } else if (renewalError != null) {
        throw CollaborationException(renewalError!);
      }
      final result = {...session!}..remove('token');
      return alter?.call(result) ?? result;
    }
    final result = await super.call(
      operation == 'auth.enroll' || operation == 'auth.register'
          ? 'auth.login'
          : operation,
      params,
      token,
    );
    if (operation == 'capabilities') {
      (result['features'] as Map)['sessionRenewal'] = supported;
    }
    if (operation == 'auth.login' ||
        operation == 'auth.enroll' ||
        operation == 'auth.register') {
      (result['device'] as Map)['expiresAt'] =
          now.add(const Duration(days: 30)).millisecondsSinceEpoch ~/ 1000;
      session = result;
    }
    return result;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late Directory directory;
  late RenewalServer server;
  late MemorySessionStore store;
  late FakeTransport transport;
  final repositories = <CollaborationRepository>[];
  Future<CollaborationRepository> open() async {
    final repository = CollaborationRepository(
      CollaborationDatabase(
        NativeDatabase(File('${directory.path}/data.sqlite')),
      ),
      transport,
      store,
      clock: () => server.now,
    );
    repositories.add(repository);
    await repository.initialize();
    return repository;
  }

  Future<CollaborationRepository> loggedIn() async {
    final repo = await open();
    await repo.login(
      serverUrl: 'https://synthetic.invalid/',
      username: 'alice',
      password: 'synthetic',
    );
    return repo;
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('renewal-test-');
    server = RenewalServer();
    store = MemorySessionStore();
    transport = FakeTransport(server);
  });
  tearDown(() async {
    for (final repo in repositories) {
      await repo.close();
    }
    repositories.clear();
    await directory.delete(recursive: true);
  });
  test(
    'active use renews at window, preserves device token and consent',
    () async {
      final repo = await loggedIn(), original = store.value!;
      final generation = repo.database.personalIdentityGeneration;
      server.now = server.now.add(const Duration(days: 24));
      await repo.syncNow();
      expect(server.renewals, 1);
      expect(store.value!.token, original.token);
      expect(store.value!.profile.deviceId, original.profile.deviceId);
      expect(
        store.value!.profile.expiresAt,
        server.now.add(const Duration(days: 30)),
      );
      expect(repo.state.sessionRenewalSupported, isTrue);
      expect(repo.database.personalIdentityGeneration, generation);
      expect(repo.state.privateSync.enabled, isFalse);
      await repo.syncNow();
      expect(server.renewals, 1);
    },
  );
  test('older server never gets unsupported renewal', () async {
    server.supported = false;
    final repo = await loggedIn();
    server.now = server.now.add(const Duration(days: 24));
    await repo.syncNow();
    expect(server.renewals, 0);
    expect(repo.state.sessionRenewalSupported, isFalse);
  });
  test('expiry cannot revive expired device', () async {
    final repo = await loggedIn();
    server.now = server.now.add(const Duration(days: 31));
    await repo.syncNow();
    expect(server.renewals, 1);
    expect(repo.state.sessionInvalid, isTrue);
  });
  test(
    'offline and lost reply preserve local queued work and retry after restart',
    () async {
      final repo = await loggedIn();
      final scope = await repo.createScope('Test');
      final item = await repo.createShoppingList(
        scopeId: scope,
        title: 'Unsent',
      );
      server.now = server.now.add(const Duration(days: 24));
      transport.offline = true;
      await repo.syncNow();
      expect(repo.state.pendingCount, 1);
      expect(repo.state.dataForScope(scope).shoppingLists.single.id, item);
      expect(repo.state.sessionInvalid, isFalse);
      transport.offline = false;
      server.loseReply = true;
      await repo.syncNow();
      expect(repo.state.pendingCount, 1);
      final oldExpiry = store.value!.profile.expiresAt;
      server.now = server.now.add(const Duration(days: 7));
      await repo.close();
      final restarted = await open();
      await restarted.syncNow();
      expect(server.renewals, 2);
      expect(store.value!.profile.expiresAt.isAfter(oldExpiry), isTrue);
      expect(restarted.state.pendingCount, 0);
      expect(restarted.state.dataForScope(scope).shoppingLists.single.id, item);
    },
  );
  test(
    'secure write failure retains original session and allows safe retry',
    () async {
      final repo = await loggedIn(), original = store.value!;
      server.now = server.now.add(const Duration(days: 24));
      store.failWrite = true;
      await repo.syncNow();
      expect(store.value, same(original));
      expect(repo.state.sessionInvalid, isFalse);
      expect(repo.state.lastError!.code, 'secure_storage');
      store.failWrite = false;
      await repo.syncNow();
      expect(
        store.value!.profile.expiresAt.isAfter(original.profile.expiresAt),
        isTrue,
      );
    },
  );
  test(
    'concurrent authorized requests share renewal and current expiry',
    () async {
      final repo = await loggedIn();
      server.now = server.now.add(const Duration(days: 24));
      server.entered = Completer();
      server.release = Completer();
      final first = repo.members('foreign');
      final firstCheck = expectLater(
        first,
        throwsA(code('permission_revoked')),
      );
      await server.entered!.future;
      final second = repo.members('foreign');
      final secondCheck = expectLater(
        second,
        throwsA(code('permission_revoked')),
      );
      server.release!.complete();
      await Future.wait([firstCheck, secondCheck]);
      expect(server.renewals, 1);
    },
  );
  test('renewal response after signout cannot restore session', () async {
    final repo = await loggedIn();
    server.now = server.now.add(const Duration(days: 24));
    server.entered = Completer();
    server.release = Completer();
    final pending = repo.syncNow();
    await server.entered!.future;
    await repo.signOut();
    server.release!.complete();
    await pending;
    expect(store.value, isNull);
    expect(repo.state.session, isNull);
  });
  test('late renewal cannot overwrite a different account or device', () async {
    final repo = await loggedIn();
    server.now = server.now.add(const Duration(days: 24));
    server.entered = Completer();
    server.release = Completer();
    final pending = repo.syncNow();
    await server.entered!.future;
    await repo.login(
      serverUrl: 'https://synthetic.invalid/',
      username: 'bob',
      password: 'synthetic',
    );
    final bob = store.value!;
    server.release!.complete();
    await pending;
    expect(store.value, same(bob));
    expect(repo.state.session!.accountId, server.accountIds['bob']);
    await repo.close();
    final restarted = await open();
    expect(restarted.state.session!.deviceId, bob.profile.deviceId);
    expect(restarted.state.sessionInvalid, isFalse);
  });

  test(
    'revocation is durable across restart and retains queued work',
    () async {
      final repo = await loggedIn();
      final scope = await repo.createScope('Test');
      await repo.createShoppingList(scopeId: scope, title: 'Unsent');
      server.now = server.now.add(const Duration(days: 24));
      server.renewalError = 'device_revoked';
      await repo.syncNow();
      expect(repo.state.sessionInvalid, isTrue);
      expect(repo.state.pendingCount, 1);
      await repo.close();
      server.renewalError = null;
      final restarted = await open();
      await restarted.syncNow();
      expect(restarted.state.sessionInvalid, isTrue);
      expect(restarted.state.pendingCount, 1);
      expect(server.renewals, 1);
    },
  );
  test('known invalidation during secure write rejects late renewal', () async {
    final repo = await loggedIn();
    server.now = server.now.add(const Duration(days: 24));
    final writing = Completer<void>(), release = Completer<void>();
    store.beforeWrite = () async {
      writing.complete();
      await release.future;
    };
    final pending = repo.syncNow();
    await writing.future;
    // auth.me does not initiate a second renewal while renewal is pending.
    // Persist the same marker used by a concurrent server rejection/restart.
    await repo.database.execute(
      'INSERT INTO local_meta(name,value) VALUES(?,?)',
      [
        'invalid_session:${store.value!.profile.partition}:${store.value!.profile.deviceId}',
        'device_revoked',
      ],
    );
    release.complete();
    await pending;
    await repo.close();
    store.beforeWrite = null;
    final restarted = await open();
    expect(restarted.state.sessionInvalid, isTrue);
  });
  test('mismatched renewal identity never updates secure session', () async {
    final repo = await loggedIn(), original = store.value!;
    server.now = server.now.add(const Duration(days: 24));
    server.alter = (reply) => {...reply, 'serverId': 'another-server'};
    await repo.syncNow();
    expect(store.value, same(original));
    expect(repo.state.lastError!.code, 'invalid_response');
  });
  for (final operation in ['enroll', 'register']) {
    test(
      '$operation created but secure session failed reports login recovery',
      () async {
        final repo = await open();
        store.failWrite = true;
        final Future<void> pending = operation == 'enroll'
            ? repo.enroll(
                serverUrl: 'https://synthetic.invalid/',
                code: 'synthetic',
                username: 'alice',
                password: 'synthetic',
                name: 'Alice',
              )
            : repo.registerWithInvitation(
                serverUrl: 'https://synthetic.invalid/',
                invitationToken: 'synthetic',
                username: 'alice',
                password: 'synthetic',
                name: 'Alice',
              );
        await expectLater(
          pending,
          throwsA(code('account_created_session_not_saved')),
        );
        expect(repo.state.session, isNull);
        expect(store.value, isNull);
      },
    );
  }
}
