import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/data/remote_push_store.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'collaboration_repository_test.dart'
    show FakeServer, MemorySessionStore, code;
import 'remote_push_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late Directory dir;
  late FakeServer server;
  late PushTransport transport;
  late MemoryPushStore pushStore;
  late MemorySessionStore sessionStore;
  final repos = <CollaborationRepository>[];
  Future<CollaborationRepository> open({String file = 'a'}) async {
    final repo = CollaborationRepository(
      CollaborationDatabase(NativeDatabase(File('${dir.path}/$file.sqlite'))),
      transport,
      sessionStore,
      pushStore: pushStore,
    );
    await repo.initialize();
    repos.add(repo);
    return repo;
  }

  Future<void> login(CollaborationRepository r, [String user = 'alice']) =>
      r.login(
        serverUrl: 'https://synthetic.invalid/kanboard',
        username: user,
        password: 'synthetic-password',
      );
  Future<RemotePushRegistrationState> configure(
    CollaborationRepository r, [
    String token = 'synthetic-fcm-token-A',
  ]) => r.configureRemotePush(
    identity: r.remotePushIdentity!,
    token: token,
    platform: 'android',
    language: 'sl',
    projectId: 'test-project',
  );
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('push-tests-');
    server = FakeServer();
    transport = PushTransport(server);
    pushStore = MemoryPushStore();
    sessionStore = MemorySessionStore();
  });
  tearDown(() async {
    for (final r in repos) {
      await r.close();
    }
    repos.clear();
    await dir.delete(recursive: true);
  });

  test(
    'disabled or mismatched server is truthful and resumes when capability returns',
    () async {
      transport.enabled = false;
      final r = await open();
      await login(r);
      expect(
        (await configure(r)).status,
        RemotePushRegistrationStatus.unavailable,
      );
      expect(
        transport.calls.where((c) => c.operation == 'push.register'),
        isEmpty,
      );
      final generation = pushStore.value!.generation;
      transport.enabled = true;
      transport.projectId = 'other-project';
      await r.syncNow();
      expect(r.state.remotePushRegistration.errorCode, 'push_project_mismatch');
      expect(
        transport.calls.where((c) => c.operation == 'push.register'),
        isEmpty,
      );
      transport.projectId = 'test-project';
      await r.syncNow();
      expect(
        r.state.remotePushRegistration.status,
        RemotePushRegistrationStatus.registered,
      );
      expect(pushStore.value!.generation, generation);
    },
  );

  test(
    'lost ACK and identical SDK retry survive restart with exact prepared CAS',
    () async {
      var r = await open();
      await login(r);
      transport.loseRegisterReply = true;
      expect(
        (await configure(r)).status,
        RemotePushRegistrationStatus.pendingRegistration,
      );
      final generation = pushStore.value!.generation;
      final first = transport.calls.singleWhere(
        (c) => c.operation == 'push.register',
      );
      await r.close();
      repos.remove(r);
      r = await open();
      expect(pushStore.value!.expectedRevision, 0);
      expect(
        (await configure(r)).status,
        RemotePushRegistrationStatus.registered,
      );
      final sent = transport.calls
          .where((c) => c.operation == 'push.register')
          .toList();
      expect(sent.length, 2);
      expect(jsonEncode(sent.last.params) == jsonEncode(first.params), isTrue);
      expect(pushStore.value!.generation, generation);
      expect(transport.registration(sessionStore.value!.token)['revision'], 1);
      final rows = await r.database.rows('SELECT value FROM local_meta');
      expect(jsonEncode(rows).contains('synthetic-fcm-token-A'), isFalse);
      expect(
        (await r.exportUnsentWork()).contains('synthetic-fcm-token-A'),
        isFalse,
      );
    },
  );

  test(
    'secure-store failure never claims registration or falls back to database',
    () async {
      final r = await open();
      await login(r);
      pushStore.failWrite = true;
      await expectLater(configure(r), throwsA(code('secure_storage')));
      expect(
        r.state.remotePushRegistration.status,
        RemotePushRegistrationStatus.disabled,
      );
      expect(
        transport.calls.where((c) => c.operation == 'push.register'),
        isEmpty,
      );
    },
  );

  test(
    'token rotation cannot apply obsolete ACK over newer secure intent',
    () async {
      final r = await open();
      await login(r);
      final entered = Completer<void>(), release = Completer<void>();
      transport.before = (operation, token, params) async {
        if (operation == 'push.register' &&
            params['token'] == 'synthetic-fcm-token-A') {
          entered.complete();
          await release.future;
        }
      };
      final first = configure(r);
      await entered.future;
      final newer = configure(r, 'synthetic-fcm-token-B');
      await newer;
      expect(pushStore.value!.token == 'synthetic-fcm-token-B', isTrue);
      release.complete();
      await first;
      expect(pushStore.value!.token == 'synthetic-fcm-token-B', isTrue);
      expect(
        r.state.remotePushRegistration.status,
        RemotePushRegistrationStatus.registered,
      );
      expect(
        transport.registration(sessionStore.value!.token)['token'] ==
            'synthetic-fcm-token-B',
        isTrue,
      );
    },
  );

  test('late SDK token cannot register after account switch', () async {
    final r = await open();
    await login(r);
    final old = r.remotePushIdentity!;
    await login(r, 'bob');
    final calls = transport.calls.length;
    await expectLater(
      r.configureRemotePush(
        identity: old,
        token: 'late-token',
        platform: 'ios',
        language: 'en',
        projectId: 'test-project',
      ),
      throwsA(code('session_changed')),
    );
    expect(transport.calls.length, calls);
  });

  test(
    'secure write finishing after logout is cleared and cannot register',
    () async {
      final r = await open();
      await login(r);
      final entered = Completer<void>(), release = Completer<void>();
      var delayed = false;
      pushStore.beforeWrite = () async {
        if (!delayed) {
          delayed = true;
          entered.complete();
          await release.future;
        }
      };
      final configuring = configure(r);
      final checked = expectLater(
        configuring,
        throwsA(code('session_changed')),
      );
      await entered.future;
      final logout = r.signOut();
      await Future<void>.delayed(Duration.zero);
      expect(r.state.session, isNull);
      release.complete();
      await checked;
      await logout;
      expect(pushStore.value, isNull);
      expect(pushStore.cleanups, isEmpty);
      expect(
        transport.calls.where((c) => c.operation == 'push.register'),
        isEmpty,
      );
    },
  );

  test(
    'offline logout cleanup survives restart and uses only the old bearer',
    () async {
      var r = await open();
      await login(r);
      await configure(r);
      final old = sessionStore.value!;
      transport.offline = true;
      expect(await r.signOut(), isFalse);
      expect(sessionStore.value, isNull);
      expect(pushStore.value, isNull);
      expect(pushStore.cleanups.single.deviceId, old.profile.deviceId);
      await r.close();
      repos.remove(r);
      r = await open();
      transport.offline = false;
      await login(r, 'bob');
      final newer = sessionStore.value!;
      await configure(r, 'synthetic-fcm-token-B');
      expect(pushStore.cleanups, isEmpty);
      expect(server.tokens.containsKey(old.token), isFalse);
      expect(server.tokens.containsKey(newer.token), isTrue);
      final cleanups = transport.calls
          .where((c) => c.operation == 'push.unregister')
          .toList();
      expect(cleanups.isNotEmpty, isTrue);
      expect(cleanups.every((c) => c.token == old.token), isTrue);
      expect(transport.registration(newer.token)['registered'], isTrue);
    },
  );

  test(
    'obsolete unregister CAS never removes a newer active registration',
    () async {
      final r = await open();
      await login(r);
      await configure(r);
      transport.loseUnregisterReply = true;
      final identity = r.remotePushIdentity!;
      expect(
        (await r.disableRemotePush(identity: identity)).status,
        RemotePushRegistrationStatus.pendingUnregistration,
      );
      final pending = pushStore.value!, bearer = sessionStore.value!.token;
      final current = transport.registration(bearer);
      transport.registrations[bearer] = {
        ...current,
        'registered': true,
        'token': 'newer-external-token',
        'platform': 'android',
        'language': 'sl',
        'revision': 3,
      };
      expect(
        (await r.disableRemotePush(identity: identity)).status,
        RemotePushRegistrationStatus.blocked,
      );
      expect(pushStore.value!.generation, pending.generation);
      expect(transport.registration(bearer)['registered'], isTrue);
      expect(r.state.remotePushRegistration.errorCode, 'push_conflict');
    },
  );

  test(
    'in-flight old registration cannot borrow a new account token',
    () async {
      final r = await open();
      await login(r);
      final old = sessionStore.value!,
          entered = Completer<void>(),
          release = Completer<void>();
      transport.before = (operation, token, params) async {
        if (operation == 'push.register' && token == old.token) {
          entered.complete();
          await release.future;
        }
      };
      final first = configure(r);
      final rejected = expectLater(first, throwsA(code('session_changed')));
      await entered.future;
      await login(r, 'bob');
      final newer = sessionStore.value!;
      await configure(r, 'synthetic-fcm-token-B');
      release.complete();
      await rejected;
      await r.syncNow();
      expect(
        transport.calls
            .where(
              (c) =>
                  c.operation == 'push.register' &&
                  c.params['token'] == 'synthetic-fcm-token-A',
            )
            .every((c) => c.token == old.token),
        isTrue,
      );
      expect(pushStore.value!.identity.matches(newer.profile), isTrue);
      expect(transport.registration(newer.token)['registered'], isTrue);
      expect(server.tokens.containsKey(old.token), isFalse);
    },
  );
  test('prepared logout marker suppresses crashed session restore', () async {
    var r = await open();
    await login(r);
    final prior = sessionStore.value!;
    pushStore.cleanups = [RemotePushCleanup(prior)];
    await r.close();
    repos.remove(r);
    r = await open();
    expect(r.state.session, isNull);
    expect(sessionStore.value, isNull);
    expect(pushStore.cleanups.single.matches(prior.profile), isTrue);
    expect(
      transport.calls.where((c) => c.operation == 'push.register'),
      isEmpty,
    );
  });

  test(
    'cleanup persistence failure still revokes captured bearer and reports storage error',
    () async {
      final r = await open();
      await login(r);
      await configure(r);
      final prior = sessionStore.value!;
      pushStore.failWrite = true;
      await expectLater(r.signOut(), throwsA(code('secure_storage')));
      expect(r.state.session, isNull);
      expect(sessionStore.value, isNull);
      expect(server.tokens.containsKey(prior.token), isFalse);
      expect(
        transport.calls.where((c) => c.operation == 'auth.revoke').last.token ==
            prior.token,
        isTrue,
      );
    },
  );
  test(
    'remote unregister is noticed on same-token resume without blind registration',
    () async {
      final r = await open();
      await login(r);
      await configure(r);
      final bearer = sessionStore.value!.token;
      transport.registrations[bearer] = {
        'registered': false,
        'platform': null,
        'language': null,
        'revision': 2,
        'updatedAt': '2026-10-05T12:00:00Z',
      };
      final count = transport.calls
          .where((c) => c.operation == 'push.register')
          .length;
      expect((await configure(r)).status, RemotePushRegistrationStatus.blocked);
      expect(
        r.state.remotePushRegistration.errorCode,
        'push_registration_lost',
      );
      expect(
        transport.calls.where((c) => c.operation == 'push.register').length,
        count,
      );
      await configure(r, 'explicit-fresh-token');
      expect(
        r.state.remotePushRegistration.status,
        RemotePushRegistrationStatus.registered,
      );
    },
  );

  test(
    'known device revoke stays sticky offline and through restart until new login',
    () async {
      var r = await open();
      await login(r);
      await configure(r);
      final bearer = sessionStore.value!.token;
      server.tokens.remove(bearer);
      await r.syncNow();
      expect(r.state.sessionInvalid, isTrue);
      expect(
        r.state.remotePushRegistration.status,
        RemotePushRegistrationStatus.blocked,
      );
      expect(r.state.remotePushRegistration.errorCode, 'device_revoked');
      transport.offline = true;
      await r.syncNow();
      expect(r.state.sessionInvalid, isTrue);
      await r.close();
      repos.remove(r);
      r = await open();
      expect(r.state.sessionInvalid, isTrue);
      await expectLater(configure(r), throwsA(code('device_revoked')));
      transport.offline = false;
      await login(r);
      expect(r.state.sessionInvalid, isFalse);
      await configure(r, 'fresh-valid-token');
      expect(
        r.state.remotePushRegistration.status,
        RemotePushRegistrationStatus.registered,
      );
    },
  );

  test(
    'cleanup never submits old bearer to replaced installation at the same URL',
    () async {
      var r = await open();
      await login(r);
      await configure(r);
      final prior = sessionStore.value!;
      transport.offline = true;
      await r.signOut();
      await r.close();
      repos.remove(r);
      r = await open();
      transport.offline = false;
      server.serverId = newSharedId();
      await login(r, 'bob');
      expect(pushStore.cleanups, isEmpty);
      expect(
        transport.calls.where(
          (c) =>
              c.token == prior.token &&
              (c.operation == 'push.unregister' ||
                  c.operation == 'auth.revoke'),
        ),
        isEmpty,
      );
    },
  );
}
