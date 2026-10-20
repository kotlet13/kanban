import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';

import '../support/synthetic_content_route_guard.dart';
import 'collaboration_repository_test.dart'
    show FakeServer, FakeTransport, MemorySessionStore;
import 'collaboration_sync_status_test.dart' show SyncStatusDatabase;

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late FakeServer server;
  late SyncStatusDatabase database;
  late CollaborationRepository repository;

  setUp(() async {
    server = FakeServer();
    database = SyncStatusDatabase(NativeDatabase.memory());
    repository = CollaborationRepository(
      database,
      FakeTransport(server),
      MemorySessionStore(),
      contentRouteGuard: const SyntheticContentRouteGuard(),
    );
    await repository.initialize();
    await repository.login(
      serverUrl: 'https://synthetic.invalid/',
      username: 'alice',
      password: 'synthetic-password',
    );
    expect(repository.state.lastError, isNull);
    server.calls.clear();
  });
  tearDown(() => repository.close());

  int capabilityCalls() =>
      server.calls.where((call) => call.operation == 'capabilities').length;

  test('sync discovery preserves durable server identity rejection', () async {
    final session = repository.state.session!;
    server.serverId = newSharedId();
    await repository.syncNow();
    expect(repository.state.lastError?.code, 'server_identity_changed');
    expect(capabilityCalls(), 1);
    expect(server.calls.any((call) => call.operation == 'scopes.list'), false);
    expect(
      await database.rows('SELECT value FROM local_meta WHERE name=?', [
        'invalid_session:${session.partition}:${session.deviceId}',
      ]),
      [
        {'value': 'server_identity_changed'},
      ],
    );

    server.calls.clear();
    await repository.syncNow();
    expect(repository.state.lastError?.code, 'server_identity_changed');
    expect(server.calls, isEmpty);
  });

  test('sync discovery ends at nested and later cycle boundaries', () async {
    var resumeCalls = 0;
    database.beforePaymentResume = () async {
      resumeCalls++;
      // Both use the outer cycle's anonymous negotiation result.
      expect(await repository.accountCryptoPreview(), isNull);
      expect(await repository.accountCryptoPreview(), isNull);
      expect(capabilityCalls(), 1);
      await repository.syncNow(resumePayments: false);
      expect(capabilityCalls(), 2);
      // Returning from a nested cycle restores the still active outer scope.
      expect(await repository.accountCryptoPreview(), isNull);
      expect(capabilityCalls(), 2);
    };
    await repository.syncNow();
    expect(repository.state.lastError, isNull);
    expect(resumeCalls, 1);
    expect(capabilityCalls(), 2);

    database.beforePaymentResume = null;
    server.calls.clear();
    await repository.syncNow();
    expect(repository.state.lastError, isNull);
    expect(capabilityCalls(), 1);

    // Independent preview workflows keep their original fresh reads.
    expect(await repository.accountCryptoPreview(), isNull);
    expect(await repository.accountCryptoPreview(), isNull);
    expect(capabilityCalls(), 3);
  });
}
