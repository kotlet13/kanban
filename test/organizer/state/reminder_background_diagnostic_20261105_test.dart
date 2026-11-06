import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/data/device_session_store.dart';
import 'package:kanban/organizer/data/e2ee/crypto_domain_router.dart';
import 'package:kanban/organizer/presentation/shared/sync_failure_panel.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';

import '../data/collaboration_repository_test.dart'
    show FakeServer, FakeTransport, MemorySessionStore;
import '../support/synthetic_content_route_guard.dart';

class _LegacyRouter implements CryptoDomainRouter {
  @override
  Future<Map<String, dynamic>> dispatch({
    required DeviceSession session,
    required String operation,
    required Map<String, Object?> params,
    required Set<String> protectedScopeIds,
  }) async => throw StateError('This fixture has no protected content');
}

/// Synthetic protocol seam only: one probe fails, later probes return the same
/// snapshot. The real repository/controller own failure capture and recovery.
/// This does not reproduce a crypto guard, signed HTTP, reminder delivery or
/// the reported phone's underlying failure.
class _ProbeTransport extends FakeTransport {
  _ProbeTransport(super.server, this.store);
  final MemorySessionStore store;
  bool failNextProbe = false;
  int probes = 0;

  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
    if (operation == 'account.changes') {
      probes++;
      if (failNextProbe) {
        failNextProbe = false;
        throw const CollaborationException('crypto_reconciliation_required');
      }
      final profile = store.value!.profile;
      return {
        'version': 1,
        'serverId': profile.serverId,
        'accountId': profile.accountId,
        'deviceId': profile.deviceId,
        'cursor': 'synthetic-unchanged-snapshot',
        'changed': params['cursor'] == null,
        'resetRequired': params['cursor'] == null,
        'hasMore': false,
        'accountDomains': <String>[],
        'scopes': <Map<String, dynamic>>[],
      };
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    '20261105 reproduces stale unknown after manual unchanged recovery; automatic probe clears it',
    () async {
      final binding = WidgetsBinding.instance;
      final previousLifecycle = binding.lifecycleState;
      binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      final store = MemorySessionStore();
      final transport = _ProbeTransport(FakeServer(), store);
      final repository = CollaborationRepository(
        CollaborationDatabase(NativeDatabase.memory()),
        transport,
        store,
        cryptoRouter: _LegacyRouter(),
        contentRouteGuard: const SyntheticContentRouteGuard(),
      );
      ProviderContainer? container;
      addTearDown(() async {
        container?.dispose();
        await repository.close();
        binding.handleAppLifecycleStateChanged(
          previousLifecycle ?? AppLifecycleState.resumed,
        );
      });
      await repository.initialize();
      await repository.login(
        serverUrl: 'https://synthetic.invalid/',
        username: 'alice',
        password: 'synthetic-password',
      );
      final baselineCompletion = repository.lastSyncCompletion!.sequence;
      expect(repository.state.lastError, isNull);
      expect(repository.state.syncFailures, isEmpty);
      expect((await repository.syncWork()).unresolved, isFalse);

      final activeContainer = ProviderContainer(
        overrides: [
          collaborationRepositoryProvider.overrideWith(
            (ref) async => repository,
          ),
        ],
      );
      container = activeContainer;
      await activeContainer.read(collaborationProvider.future);
      final controller = activeContainer.read(collaborationProvider.notifier);
      final baselineProbes = transport.probes;
      transport.failNextProbe = true;

      await expectLater(
        controller.syncNow(),
        throwsA(
          isA<CollaborationException>().having(
            (error) => error.code,
            'code',
            'crypto_reconciliation_required',
          ),
        ),
      );
      final originalError = activeContainer.read(
        collaborationBackgroundErrorProvider,
      );
      expect(originalError, isA<CollaborationException>());
      expect(
        repository.state.syncFailures.single.stage,
        SyncFailureStage.accountCheck,
      );
      expect(repository.state.syncFailures.single.occurredAt, isNotNull);
      expect(transport.probes, baselineProbes + 1);

      // Actual successful probe, not a directly assigned state: it clears the
      // repository's probe diagnostics but emits no full-sync completion.
      await controller.syncNow();
      expect(transport.probes, baselineProbes + 2);
      expect(repository.lastSyncCompletion!.sequence, baselineCompletion);
      expect(repository.state.lastError, isNull);
      expect(repository.state.syncFailures, isEmpty);
      expect(repository.state.isSyncing, isFalse);
      expect((await repository.syncWork()).unresolved, isFalse);
      expect(
        activeContainer.read(collaborationBackgroundErrorProvider),
        same(originalError),
      );
      final reported = sharingSyncFailures(
        activeContainer.read(collaborationProvider).requireValue,
        activeContainer.read(collaborationBackgroundErrorProvider),
      );
      expect(jsonDecode(syncFailureDiagnosticsJson(reported)), {
        'version': 1,
        'syncFailures': [
          {'stage': 'unknown', 'reason': 'crypto_reconciliation_required'},
        ],
      });

      // The real lifecycle observer triggers the automatic no-completion path,
      // which does clear an old background error once lastError is null.
      final cleared = Completer<void>();
      final subscription = activeContainer.listen<Object?>(
        collaborationBackgroundErrorProvider,
        (previous, next) {
          if (previous != null && next == null && !cleared.isCompleted) {
            cleared.complete();
          }
        },
      );
      addTearDown(subscription.close);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await cleared.future.timeout(const Duration(seconds: 2));
      expect(transport.probes, baselineProbes + 3);
      expect(repository.lastSyncCompletion!.sequence, baselineCompletion);
      expect(
        sharingSyncFailures(
          activeContainer.read(collaborationProvider).requireValue,
          activeContainer.read(collaborationBackgroundErrorProvider),
        ),
        isEmpty,
      );
    },
  );
}
