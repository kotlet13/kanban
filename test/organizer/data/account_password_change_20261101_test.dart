import 'dart:convert';
import '../support/synthetic_content_route_guard.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'collaboration_repository_test.dart' show FakeServer, MemorySessionStore;
import 'private_sync_test_support.dart';

class PasswordTransport extends PersonalTransport {
  PasswordTransport(super.server);
  bool supported = true;
  String? failure;
  bool wrongReply = false;
  Future<void> Function()? beforePassword;
  final devices = <String, String>{};
  final passwordCalls = <Map<String, Object?>>[];
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
    if (operation == 'auth.login') {
      final reply = await super.call(
        serverUrl: serverUrl,
        operation: operation,
        params: params,
      );
      devices[reply['token'] as String] =
          (reply['device'] as Map)['id'] as String;
      return reply;
    }
    if (operation == 'capabilities') {
      final caps = await super.call(serverUrl: serverUrl, operation: operation);
      return {
        ...caps,
        'features': <String, dynamic>{
          ...caps['features'] as Map,
          'passwordChange': supported,
        },
      };
    }
    if (operation == 'account.password.change' ||
        operation == 'auth.reset.confirm' ||
        operation == 'auth.reset.request') {
      passwordCalls.add({
        'operation': operation,
        'serverUrl': serverUrl,
        'token': token,
        'params': {...params},
      });
      final user = server.tokens[token];
      await beforePassword?.call();
      if (failure != null) throw CollaborationException(failure!);
      if (operation == 'auth.reset.confirm') return {'reset': true};
      if (operation == 'auth.reset.request') return {'accepted': true};
      return {
        'changed': true,
        'sessionPreserved': true,
        'accountId': wrongReply ? newSharedId() : server.accountIds[user],
        'deviceId': devices[token],
      };
    }
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
  Future<
    ({
      CollaborationRepository repo,
      CollaborationDatabase db,
      MemorySessionStore store,
      PasswordTransport transport,
    })
  >
  client() async {
    final db = CollaborationDatabase(NativeDatabase.memory());
    final store = MemorySessionStore();
    final transport = PasswordTransport(FakeServer());
    final repo = CollaborationRepository(
      db,
      transport,
      store,
      ownsDatabase: false,
      contentRouteGuard: const SyntheticContentRouteGuard(),
    );
    addTearDown(() async {
      try {
        await repo.close();
      } finally {
        await db.close();
      }
    });
    await repo.initialize();
    await repo.login(
      serverUrl: 'https://test.invalid',
      username: 'alice',
      password: 'old',
    );
    return (repo: repo, db: db, store: store, transport: transport);
  }

  test(
    'literal password bytes and initiating bearer survive change without SQL or secure-session writes',
    () async {
      final c = await client();
      final original = c.store.value!;
      final before = await c.db.rows(
        'SELECT name,value FROM local_meta ORDER BY name',
      );
      c.store.failWrite = true;
      await c.repo.changeAccountPassword(
        currentPassword: ' old password ',
        newPassword: ' new password 123 ',
        otp: '123456',
      );
      final call = c.transport.passwordCalls.single;
      expect(call['token'], original.token);
      expect(call['params'], {
        'currentPassword': ' old password ',
        'newPassword': ' new password 123 ',
        'otp': '123456',
      });
      expect(identical(c.store.value, original), isTrue);
      expect(c.repo.state.session!.deviceId, original.profile.deviceId);
      final after = await c.db.rows(
        'SELECT name,value FROM local_meta ORDER BY name',
      );
      expect(after, before);
      expect(jsonEncode(after), isNot(contains('password 123')));
    },
  );
  test(
    'incorrect step-up password does not invalidate bearer while device revocation still does',
    () async {
      final c = await client();
      c.transport.failure = 'invalid_credentials';
      await expectLater(
        c.repo.changeAccountPassword(
          currentPassword: 'wrong',
          newPassword: 'new password 123',
        ),
        throwsA(
          isA<CollaborationException>().having(
            (e) => e.code,
            'code',
            'invalid_credentials',
          ),
        ),
      );
      expect(
        await c.db.rows(
          "SELECT name FROM local_meta WHERE name LIKE 'invalid_session:%'",
        ),
        isEmpty,
      );
      expect(c.repo.state.session, isNotNull);
      c.transport.failure = 'device_revoked';
      await expectLater(
        c.repo.changeAccountPassword(
          currentPassword: 'old',
          newPassword: 'new password 123',
        ),
        throwsA(
          isA<CollaborationException>().having(
            (e) => e.code,
            'code',
            'device_revoked',
          ),
        ),
      );
      expect(
        await c.db.rows(
          "SELECT value FROM local_meta WHERE name LIKE 'invalid_session:%'",
        ),
        [
          {'value': 'device_revoked'},
        ],
      );
    },
  );
  test(
    'old server blocks direct change and bound reset before sending credentials',
    () async {
      final c = await client();
      c.transport.supported = false;
      for (final action in [
        () => c.repo.changeAccountPassword(
          currentPassword: 'old',
          newPassword: 'new password 123',
        ),
        () => c.repo.requestSignedInPasswordReset(),
        () => c.repo.confirmSignedInPasswordReset(
          token: 'code',
          password: 'new password 123',
        ),
      ]) {
        await expectLater(
          action(),
          throwsA(
            isA<CollaborationException>().having(
              (e) => e.code,
              'code',
              'password_change_unsupported',
            ),
          ),
        );
      }
      expect(c.transport.passwordCalls, isEmpty);
    },
  );
  test('wrong response account cannot report change success', () async {
    final c = await client();
    c.transport.wrongReply = true;
    await expectLater(
      c.repo.changeAccountPassword(
        currentPassword: 'old',
        newPassword: 'new password 123',
      ),
      throwsA(
        isA<CollaborationException>().having(
          (e) => e.code,
          'code',
          'invalid_response',
        ),
      ),
    );
    expect(c.repo.state.session, isNotNull);
  });
  test(
    'account switch during request rejects completion without invalidating next account',
    () async {
      final c = await client();
      c.transport.beforePassword = () async {
        c.transport.beforePassword = null;
        await c.repo.login(
          serverUrl: 'https://test.invalid',
          username: 'bob',
          password: 'old',
        );
      };
      await expectLater(
        c.repo.changeAccountPassword(
          currentPassword: 'old',
          newPassword: 'new password 123',
        ),
        throwsA(
          isA<CollaborationException>().having(
            (e) => e.code,
            'code',
            'session_changed',
          ),
        ),
      );
      expect(c.repo.state.session!.username, 'bob');
      expect(
        await c.db.rows(
          "SELECT name FROM local_meta WHERE name LIKE 'invalid_session:%'",
        ),
        isEmpty,
      );
    },
  );
  test(
    'email reset uses fixed account and server binding then marks only confirmed session expired',
    () async {
      final c = await client();
      final session = c.store.value!;
      await c.repo.requestSignedInPasswordReset(language: 'en');
      expect(c.transport.passwordCalls.single['params'], {
        'username': 'alice',
        'language': 'en',
      });
      await c.repo.confirmSignedInPasswordReset(
        token: 'reset-code',
        password: ' new password 123 ',
      );
      expect(c.transport.passwordCalls.last['params'], {
        'token': 'reset-code',
        'password': ' new password 123 ',
        'expectedAccountId': session.profile.accountId,
        'expectedServerId': session.profile.serverId,
      });
      expect(identical(c.store.value, session), isTrue);
      expect(
        await c.db.rows(
          "SELECT value FROM local_meta WHERE name LIKE 'invalid_session:%'",
        ),
        [
          {'value': 'session_expired'},
        ],
      );
    },
  );
  test(
    'foreign reset token error preserves current session and key metadata',
    () async {
      final c = await client();
      c.transport.failure = 'password_reset_identity_mismatch';
      await c.db.execute('INSERT INTO local_meta(name,value) VALUES(?,?)', [
        'test-key-marker',
        'same-key',
      ]);
      await expectLater(
        c.repo.confirmSignedInPasswordReset(
          token: 'foreign-code',
          password: 'new password 123',
        ),
        throwsA(
          isA<CollaborationException>().having(
            (e) => e.code,
            'code',
            'password_reset_identity_mismatch',
          ),
        ),
      );
      expect(c.transport.passwordCalls, hasLength(1));
      expect(
        await c.db.rows(
          "SELECT name FROM local_meta WHERE name LIKE 'invalid_session:%'",
        ),
        isEmpty,
      );
      expect(
        await c.db.rows(
          "SELECT value FROM local_meta WHERE name='test-key-marker'",
        ),
        [
          {'value': 'same-key'},
        ],
      );
    },
  );
  test(
    'lost change response is not retried and preserves current bearer',
    () async {
      final c = await client();
      final session = c.store.value!;
      c.transport.failure = 'network';
      await expectLater(
        c.repo.changeAccountPassword(
          currentPassword: 'old',
          newPassword: 'new password 123',
        ),
        throwsA(
          isA<CollaborationException>().having(
            (e) => e.code,
            'code',
            'network',
          ),
        ),
      );
      expect(c.transport.passwordCalls, hasLength(1));
      expect(identical(c.store.value, session), isTrue);
      expect(
        await c.db.rows(
          "SELECT name FROM local_meta WHERE name LIKE 'invalid_session:%'",
        ),
        isEmpty,
      );
    },
  );
  test(
    'password change bypasses content crypto floors and unfinished restore fence',
    () async {
      final c = await client();
      final partition = c.repo.state.session!.partition;
      await c.db.execute(
        "INSERT INTO crypto_scope_state(partition,scope_id,domain,state,floor) VALUES(?,?,'content','active',2)",
        [partition, newSharedId()],
      );
      await c.db.execute(
        "INSERT INTO crypto_restore_fences(partition,minimum_transport,backup_id,state) VALUES(?,2,?,'requires_reconciliation')",
        [partition, newSharedId()],
      );
      await c.repo.changeAccountPassword(
        currentPassword: 'old',
        newPassword: 'new password 123',
      );
      expect(c.transport.passwordCalls, hasLength(1));
      expect(await c.db.rows('SELECT state FROM crypto_restore_fences'), [
        {'state': 'requires_reconciliation'},
      ]);
      expect(await c.db.rows('SELECT floor FROM crypto_scope_state'), [
        {'floor': 2},
      ]);
    },
  );
}
