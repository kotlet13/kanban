import 'dart:async';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/account_work_coordinator.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import '../support/synthetic_content_route_guard.dart';
import 'collaboration_repository_test.dart'
    show FakeTransport, MemorySessionStore;
import 'collaboration_session_renewal_test.dart' show RenewalServer;

class _Transport extends FakeTransport {
  _Transport(super.server);
  Completer<Map<String, dynamic>>? hold;
  final attempts =
      <({String operation, String? token, Map<String, Object?> params})>[];
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
    attempts.add((operation: operation, token: token, params: params));
    if (operation == 'crypto2.directory.status') return hold!.future;
    if (operation == 'crypto2.scope.headGet') return {'synthetic': true};
    if (operation == 'account.status') {
      return {
        'email': 'synthetic@example.test',
        'pendingEmail': null,
        'emailVerified': true,
        'resetAvailable': true,
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
      _Transport transport,
      RenewalServer server,
      MemorySessionStore sessions,
    })
  >
  setup() async {
    final server = RenewalServer(), sessions = MemorySessionStore();
    final transport = _Transport(server);
    final repo = CollaborationRepository(
      CollaborationDatabase(NativeDatabase.memory()),
      transport,
      sessions,
      clock: () => server.now,
      accountWork: AccountWorkCoordinator(
        clock: () => server.now,
        maxConcurrentReads: 1,
      ),
      contentRouteGuard: const SyntheticContentRouteGuard(),
    );
    addTearDown(repo.close);
    await repo.initialize();
    await repo.login(
      serverUrl: 'https://synthetic.invalid/',
      username: 'alice',
      password: 'synthetic',
    );
    expect(repo.state.lastError, isNull, reason: 'legacy setup must finish');
    transport.attempts.clear();
    return (
      repo: repo,
      transport: transport,
      server: server,
      sessions: sessions,
    );
  }

  test(
    'actual repository keeps queued and in-flight owner valid through same-bearer renewal',
    () async {
      final f = await setup();
      final wrapper = f.repo.transport as CoordinatedCollaborationTransport;
      expect(identical(wrapper.inner, f.transport), isTrue);
      expect(identical(wrapper.coordinator, f.repo.accountWork), isTrue);
      final original = f.sessions.value!;
      final release = Completer<Map<String, dynamic>>();
      f.transport.hold = release;
      final active = f.repo.transport.call(
        serverUrl: original.profile.serverUrl,
        operation: 'crypto2.directory.status',
        token: original.token,
      );
      final queued = f.repo.transport.call(
        serverUrl: original.profile.serverUrl,
        operation: 'crypto2.scope.headGet',
        token: original.token,
      );
      final renewed = Completer<void>();
      final sub = f.repo.changes.listen((state) {
        if (!renewed.isCompleted &&
            state.session?.expiresAt.isAfter(original.profile.expiresAt) ==
                true) {
          renewed.complete();
        }
      });
      addTearDown(sub.cancel);
      f.server.now = f.server.now.add(const Duration(days: 24));
      final status = f.repo.accountStatus();
      await renewed.future.timeout(const Duration(seconds: 5));
      expect(identical(f.sessions.value, original), isFalse);
      expect(f.sessions.value!.token, original.token);
      expect(f.server.renewals, 1);
      release.complete({'synthetic': true});
      await Future.wait<Object?>([active, queued, status]);
      expect(
        f.transport.attempts.where(
          (a) => a.operation == 'crypto2.scope.headGet',
        ),
        hasLength(1),
      );
      expect(f.repo.state.lastError, isNull);
    },
  );

  test(
    'actual logout fences old work while captured and failed-enrollment cleanup still sends',
    () async {
      final f = await setup();
      final original = f.sessions.value!;
      final release = Completer<Map<String, dynamic>>();
      f.transport.hold = release;
      final active = f.repo.transport.call(
        serverUrl: original.profile.serverUrl,
        operation: 'crypto2.directory.status',
        token: original.token,
      );
      final queued = f.repo.transport.call(
        serverUrl: original.profile.serverUrl,
        operation: 'crypto2.scope.headGet',
        token: original.token,
      );
      final activeFailure = expectLater(
        active,
        throwsA(isA<CollaborationException>()),
      );
      final queuedFailure = expectLater(
        queued,
        throwsA(isA<CollaborationException>()),
      );
      final logout = f.repo.signOut();
      release.complete({});
      await Future.wait([activeFailure, queuedFailure]);
      expect(await logout, isTrue);
      expect(f.sessions.value, isNull);
      expect(
        f.transport.attempts.where(
          (a) => a.operation == 'crypto2.scope.headGet',
        ),
        isEmpty,
      );
      expect(
        f.transport.attempts
            .where((a) => a.operation == 'auth.revoke')
            .map((a) => a.token),
        contains(original.token),
      );
      await expectLater(
        Future.sync(
          () => f.repo.transport.call(
            serverUrl: original.profile.serverUrl,
            operation: 'crypto2.scope.headGet',
            token: original.token,
          ),
        ),
        throwsA(isA<CollaborationException>()),
      );
      final before = f.transport.attempts
          .where((a) => a.operation == 'auth.revoke')
          .length;
      f.sessions.failWrite = true;
      await expectLater(
        f.repo.enroll(
          serverUrl: 'https://synthetic.invalid/',
          code: 'synthetic',
          username: 'alice',
          password: 'synthetic',
          name: 'Alice',
        ),
        throwsA(
          isA<CollaborationException>().having(
            (e) => e.code,
            'code',
            'account_created_session_not_saved',
          ),
        ),
      );
      final revocations = f.transport.attempts
          .where((a) => a.operation == 'auth.revoke')
          .toList();
      expect(revocations, hasLength(before + 1));
      expect(revocations.last.token, isNot(original.token));
      expect(
        revocations.last.params['deviceId'],
        f.server.session!['device']['id'],
      );
      expect(f.sessions.value, isNull);
      expect(f.repo.state.session, isNull);
    },
  );
}
