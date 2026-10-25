import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/data/device_session_store.dart';
import 'package:kanban/organizer/data/e2ee/crypto_domain_router.dart';
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
  }) async => throw StateError('Protected content is not part of this fixture');
}

class _TimedProbeTransport extends FakeTransport {
  _TimedProbeTransport(super.server, this.store);
  final MemorySessionStore store;
  final starts = <DateTime>[];
  final secondFinished = Completer<void>();
  bool measuring = false;

  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
    if (operation == 'account.changes') {
      if (measuring) {
        starts.add(DateTime.now());
        await Future<void>.delayed(const Duration(milliseconds: 200));
        if (starts.length == 2) secondFinished.complete();
      }
      final profile = store.value!.profile;
      return {
        'version': 1,
        'serverId': profile.serverId,
        'accountId': profile.accountId,
        'deviceId': profile.deviceId,
        'cursor': 'same-snapshot',
        'changed': params['cursor'] == null,
        'resetRequired': params['cursor'] == null,
        'hasMore': false,
        'accountDomains': <String>[],
        'scopes': <Map<String, dynamic>>[],
      };
    }
    final result = await super.call(
      serverUrl: serverUrl,
      operation: operation,
      params: params,
      token: token,
      allowLocalHttp: allowLocalHttp,
    );
    return operation == 'capabilities'
        ? {...result, 'accountChangeVersions': [1], 'accountChanges': true}
        : result;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('delayed metadata probe schedules next at completion plus30s, not60s',
      () async {
    final server = FakeServer(), store = MemorySessionStore();
    final transport = _TimedProbeTransport(server, store);
    final repo = CollaborationRepository(
      CollaborationDatabase(NativeDatabase.memory()),
      transport,
      store,
      cryptoRouter: _LegacyRouter(),
      contentRouteGuard: const SyntheticContentRouteGuard(),
    );
    await repo.initialize();
    await repo.login(
      serverUrl: 'https://example.test/',
      username: 'alice',
      password: 'synthetic',
    );
    await repo.syncNow();
    expect(repo.state.lastError, isNull);
    WidgetsBinding.instance.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    transport.measuring = true;
    final container = ProviderContainer(overrides: [
      collaborationRepositoryProvider.overrideWith((ref) async => repo),
    ]);
    addTearDown(() async {
      container.dispose();
      await repo.close();
    });
    await container.read(collaborationProvider.future);
    await transport.secondFinished.future.timeout(const Duration(seconds: 34));
    final elapsed = transport.starts[1].difference(transport.starts[0]);
    expect(elapsed, greaterThanOrEqualTo(const Duration(seconds: 30)));
    expect(elapsed, lessThan(const Duration(seconds: 33)));
    expect(transport.starts, hasLength(2));
  }, timeout: const Timeout(Duration(seconds: 45)));
}
