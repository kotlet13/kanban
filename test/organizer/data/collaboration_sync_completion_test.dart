import 'dart:async';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/data/collaboration_transport.dart';
import '../support/synthetic_content_route_guard.dart';
import 'collaboration_repository_test.dart'
    show FakeServer, FakeTransport, MemorySessionStore;

class _Database extends CollaborationDatabase {
  _Database() : super(NativeDatabase.memory());
  bool failWork = false;
  @override
  Future<List<Map<String, dynamic>>> rows(
    String sql, [
    List<Object?> args = const [],
  ]) {
    if (failWork && sql.startsWith("SELECT 'record'")) {
      throw StateError('Synthetic bookkeeping failure');
    }
    return super.rows(sql, args);
  }
}

void main() {
  Future<
    ({
      CollaborationRepository repo,
      FakeServer server,
      void Function(Duration) advance,
    })
  >
  setup() async {
    var now = DateTime.utc(2026, 10, 19);
    final server = FakeServer();
    final repo = CollaborationRepository(
      _Database(),
      FakeTransport(server),
      MemorySessionStore(),
      contentRouteGuard: const SyntheticContentRouteGuard(),
      clock: () => now,
    );
    addTearDown(repo.close);
    await repo.initialize();
    await repo.login(
      serverUrl: 'https://example.test/',
      username: 'alice',
      password: 'synthetic',
    );
    return (
      repo: repo,
      server: server,
      advance: (duration) => now = now.add(duration),
    );
  }

  test(
    'full completion records swallowed error and automatic retry minimum',
    () async {
      final f = await setup();
      final events = <CollaborationSyncCompletion>[];
      final sub = f.repo.syncCompletions.listen(events.add);
      addTearDown(sub.cancel);
      f.server.beforeCall = (operation, _, _) async {
        if (operation == 'scopes.list')
          throw const CollaborationApiException(
            'rate_limited',
            details: {'retryAfter': 90},
          );
      };
      await f.repo.syncNow();
      await Future<void>.delayed(Duration.zero);
      expect(events, hasLength(1));
      expect(events.single.error, isA<CollaborationApiException>());
      expect(
        events.single.retryAt,
        events.single.at.add(const Duration(seconds: 90)),
      );
      final calls = f.server.calls.length;
      await f.repo.syncNow();
      expect(f.server.calls.length, calls);
      await f.repo.syncNow(manual: true);
      expect(f.server.calls.length, greaterThan(calls));
      await Future<void>.delayed(Duration.zero);
      expect(events, hasLength(2));
      expect(events[1].sequence, greaterThan(events[0].sequence));
      expect(f.repo.state.lastError?.code, 'rate_limited');
    },
  );
  for (final value in [null, 0, -1, 86401, '60', 1.5]) {
    test(
      'malformed retryAfter $value does not create automatic cooldown',
      () async {
        final f = await setup();
        f.server.beforeCall = (operation, _, _) async {
          if (operation == 'scopes.list')
            throw CollaborationApiException(
              'rate_limited',
              details: {'retryAfter': value},
            );
        };
        await f.repo.syncNow();
        expect(f.repo.lastSyncCompletion!.retryAt, isNull);
        final calls = f.server.calls.length;
        await f.repo.syncNow();
        expect(f.server.calls.length, greaterThan(calls));
      },
    );
  }
  test('unrelated error retry field cannot delay automatic sync', () async {
    final f = await setup();
    f.server.beforeCall = (operation, _, _) async {
      if (operation == 'scopes.list')
        throw const CollaborationApiException(
          'forbidden',
          details: {'retryAfter': 86400},
        );
    };
    await f.repo.syncNow();
    expect(f.repo.lastSyncCompletion!.retryAt, isNull);
  });
  test(
    'partial attempt and already busy call emit no full completion',
    () async {
      final f = await setup();
      final previous = f.repo.lastSyncCompletion;
      await f.repo.syncNow(resumePayments: false);
      expect(f.repo.lastSyncCompletion, same(previous));
      final entered = Completer<void>(), release = Completer<void>();
      f.server.beforeCall = (operation, _, _) async {
        if (operation == 'scopes.list') {
          entered.complete();
          await release.future;
        }
      };
      final running = f.repo.syncNow();
      await entered.future;
      await f.repo.syncNow();
      expect(f.repo.lastSyncCompletion, same(previous));
      release.complete();
      await running;
      expect(
        f.repo.lastSyncCompletion!.sequence,
        greaterThan(previous?.sequence ?? 0),
      );
      expect(f.repo.lastSyncCompletion!.error, isNull);
    },
  );
  test('retry minimum cannot leak into a new account epoch', () async {
    final f = await setup();
    f.server.beforeCall = (operation, _, _) async {
      if (operation == 'scopes.list')
        throw const CollaborationApiException(
          'rate_limited',
          details: {'retryAfter': 86400},
        );
    };
    await f.repo.syncNow();
    final old = f.repo.backgroundSyncIdentity;
    f.server.beforeCall = null;
    await f.repo.login(
      serverUrl: 'https://example.test/',
      username: 'bob',
      password: 'synthetic',
    );
    expect(f.repo.backgroundSyncIdentity, isNot(old));
    final calls = f.server.calls.length;
    await f.repo.syncNow();
    expect(f.server.calls.length, greaterThan(calls));
    expect(f.repo.lastSyncCompletion!.identity, f.repo.backgroundSyncIdentity);
    expect(f.repo.lastSyncCompletion!.error, isNull);
    expect(f.repo.lastSyncCompletion!.retryAt, isNull);
  });

  test(
    'bookkeeping failure publishes conservative full failure outcome',
    () async {
      final f = await setup();
      final events = <CollaborationSyncCompletion>[];
      final sub = f.repo.syncCompletions.listen(events.add);
      addTearDown(sub.cancel);
      final previousSuccess = f.repo.state.lastSuccessfulSyncAt;
      f.advance(const Duration(seconds: 1));
      (f.repo.database as _Database).failWork = true;
      await f.repo.syncNow();
      await Future<void>.delayed(Duration.zero);
      expect(events, hasLength(1));
      expect(events.single.error, isNotNull);
      expect(events.single.work.unresolved, isTrue);
      expect(f.repo.state.lastError, isNotNull);
      expect(f.repo.state.lastSuccessfulSyncAt, previousSuccess);
    },
  );

  test(
    'queue snapshot sees same-count replacement and retains payment transitions',
    () async {
      final f = await setup();
      final p = f.repo.state.session!.partition;
      await f.repo.database.execute(
        "INSERT INTO commands(id,partition,operation,params,entity_key) VALUES(?,?,?,?,?)",
        ['first', p, 'synthetic', '{}', 'first'],
      );
      final a = await f.repo.syncWork();
      await f.repo.database.execute('DELETE FROM commands');
      await f.repo.database.execute(
        "INSERT INTO commands(id,partition,operation,params,entity_key) VALUES(?,?,?,?,?)",
        ['second', p, 'synthetic', '{}', 'second'],
      );
      final b = await f.repo.syncWork();
      expect(a.unresolved, isTrue);
      expect(a.signature, isNot(b.signature));
      await f.repo.database.execute('DELETE FROM commands');
      await f.repo.database.execute(
        "INSERT INTO linked_payment_intents(id,data,state) VALUES('retained','{}','complete')",
      );
      final retained = await f.repo.syncWork();
      expect(retained.unresolved, isFalse);
      await f.repo.database.execute(
        "UPDATE linked_payment_intents SET state='waiting_source_publication'",
      );
      final waiting = await f.repo.syncWork();
      expect(waiting.unresolved, isTrue);
      expect(waiting.signature, isNot(retained.signature));
    },
  );
}
