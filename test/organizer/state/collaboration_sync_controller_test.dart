import 'dart:async';
import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/data/collaboration_transport.dart';
import 'package:kanban/organizer/data/device_session_store.dart';
import 'package:kanban/organizer/data/e2ee/crypto_domain_router.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';
import '../support/synthetic_content_route_guard.dart';
import '../data/collaboration_repository_test.dart'
    show FakeServer, FakeTransport, MemorySessionStore;

class _LegacyRouter implements CryptoDomainRouter {
  @override
  Future<Map<String, dynamic>> dispatch({
    required DeviceSession session,
    required String operation,
    required Map<String, Object?> params,
    required Set<String> protectedScopeIds,
  }) async => throw StateError('Unexpected legacy protected dispatch');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Future<
    ({
      CollaborationRepository repo,
      FakeServer server,
      ProviderContainer container,
      String scope,
      void Function(Duration) advance,
    })
  >
  setup() async {
    var now = DateTime.utc(2026, 10, 19);
    final server = FakeServer();
    final repo = CollaborationRepository(
      CollaborationDatabase(NativeDatabase.memory()),
      FakeTransport(server),
      MemorySessionStore(),
      contentRouteGuard: const SyntheticContentRouteGuard(),
      clock: () => now,
      cryptoRouter: _LegacyRouter(),
    );
    addTearDown(repo.close);
    await repo.initialize();
    await repo.login(
      serverUrl: 'https://example.test/',
      username: 'alice',
      password: 'synthetic',
    );
    final scope = await repo.createScope('Synthetic scope');
    await repo.syncNow();
    expect(repo.state.lastError, isNull);
    expect((await repo.syncWork()).unresolved, isFalse);
    final container = ProviderContainer(
      overrides: [
        collaborationRepositoryProvider.overrideWith((ref) async => repo),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await repo.close();
    });
    await container.read(collaborationProvider.future);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    return (
      repo: repo,
      server: server,
      container: container,
      scope: scope,
      advance: (duration) => now = now.add(duration),
    );
  }

  Future<void> resume(CollaborationRepository repo) async {
    final refreshed = repo.changes.first;
    WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.inactive,
    );
    WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
    await refreshed;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }

  test(
    'controller external completions and Mac focus retain original drained deadline',
    () async {
      final f = await setup();
      await f.repo.syncNow(); // outside the controller timer
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final before = f.server.calls.length;
      for (var i = 0; i < 10; i++) {
        f.advance(const Duration(seconds: 3));
        await resume(f.repo);
      }
      expect(
        f.server.calls.length,
        before,
        reason: f.server.calls
            .skip(before)
            .map((c) => c.operation)
            .toList()
            .toString(),
      );
      f.advance(const Duration(seconds: 30));
      final completed = f.repo.syncCompletions.first;
      await resume(f.repo);
      await completed;
      expect(f.server.calls.length, greaterThan(before));
    },
  );

  test(
    'controller retains queued edit while busy and delivers after full completion',
    () async {
      final f = await setup();
      final entered = Completer<void>(), release = Completer<void>();
      var held = false;
      f.server.beforeCall = (operation, _, _) async {
        if ((operation == 'sync.pull' || operation == 'sync1.pull') && !held) {
          held = true;
          entered.complete();
          await release.future;
        }
      };
      final completions = f.repo.syncCompletions.take(2).toList();
      final running = f.repo.syncNow();
      await entered.future.timeout(const Duration(seconds: 3));
      await f.container
          .read(collaborationProvider.notifier)
          .createTask(scopeId: f.scope, title: 'Queued during pull');
      expect(
        await f.repo.database.rows('SELECT op_id FROM outbox'),
        isNotEmpty,
      );
      release.complete();
      await running;
      final results = await completions.timeout(const Duration(seconds: 3));
      expect(results.first.work.unresolved, isTrue);
      expect(results.last.work.unresolved, isFalse);
      expect(await f.repo.database.rows('SELECT op_id FROM outbox'), isEmpty);
    },
  );

  test(
    'controller observes two external errors and local-only refresh preserves error',
    () async {
      final f = await setup();
      f.server.beforeCall = (operation, _, _) async {
        if (operation == 'scopes.list')
          throw const CollaborationApiException(
            'rate_limited',
            details: {'retryAfter': 90},
          );
      };
      await f.repo.syncNow(manual: true);
      await f.repo.syncNow(manual: true);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(
        f.container.read(collaborationBackgroundErrorProvider),
        isA<CollaborationApiException>(),
      );
      final before = f.server.calls.length;
      f.advance(const Duration(seconds: 3));
      await resume(f.repo);
      expect(f.server.calls.length, before);
      expect(
        f.container.read(collaborationBackgroundErrorProvider),
        isA<CollaborationApiException>(),
      );
    },
  );
  test(
    'outside-timer failures without retryAfter keep15 then30 backoff',
    () async {
      final f = await setup();
      f.server.beforeCall = (operation, _, _) async {
        if (operation == 'scopes.list')
          throw const CollaborationException('network');
      };
      await f.repo.syncNow(manual: true);
      await f.repo.syncNow(manual: true);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final before = f.server.calls.length;
      f.advance(const Duration(seconds: 3));
      await resume(f.repo);
      expect(f.server.calls.length, before);
      expect(
        (f.container.read(collaborationBackgroundErrorProvider)
                as CollaborationException)
            .code,
        'network',
      );
      f.advance(const Duration(seconds: 27));
      final completion = f.repo.syncCompletions.first;
      await resume(f.repo);
      await completion;
      expect(f.server.calls.length, greaterThan(before));
    },
  );
  test(
    'redesign external busy resume yields event loop and waits completion',
    () async {
      final f = await setup();
      final entered = Completer<void>(), release = Completer<void>();
      var gated = false;
      f.server.beforeCall = (operation, _, __) async {
        if (operation == 'scopes.list' && !gated) {
          gated = true;
          entered.complete();
          await release.future;
        }
      };
      final outside = f.repo.syncNow(manual: true);
      await entered.future;
      f.advance(const Duration(seconds: 31));
      WidgetsBinding.instance.handleAppLifecycleStateChanged(
        AppLifecycleState.inactive,
      );
      WidgetsBinding.instance.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      );
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(f.repo.state.isSyncing, isTrue);
      release.complete();
      await outside;
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(f.repo.state.lastError, isNull);
    },
  );
  test(
    'redesign already consumed failed completion preserves15s retry',
    () async {
      final f = await setup();
      var attempts = 0;
      f.server.beforeCall = (operation, _, __) async {
        if (operation == 'scopes.list') {
          attempts++;
          throw const CollaborationException('network');
        }
      };
      await f.container
          .read(collaborationProvider.notifier)
          .createTask(scopeId: f.scope, title: 'Queued');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(attempts, 1);
      f.advance(const Duration(seconds: 16));
      WidgetsBinding.instance.handleAppLifecycleStateChanged(
        AppLifecycleState.inactive,
      );
      WidgetsBinding.instance.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(attempts, 2);
    },
  );
}
