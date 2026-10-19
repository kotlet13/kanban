import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/data/e2ee/crypto_domain_router.dart';
import 'package:kanban/organizer/data/e2ee/crypto_business_router.dart';
import 'package:kanban/organizer/data/device_session_store.dart';

import '../support/synthetic_content_route_guard.dart';
import 'collaboration_repository_test.dart' show FakeServer, MemorySessionStore;
import 'organization_finance_client_test.dart'
    show OrganizationFinanceTransport;

// This legacy scheduling fixture exercises the repository queue/policy path.
// The separately counted HTTP fixture exercises the real encrypted router.
class _NoCryptoRouter
    implements CryptoDomainRouter, CryptoFinancePolicyReadContext {
  @override
  Future<CryptoFinancePolicyReadResult<T>> withFinancePolicyOnly<T>(
    Future<T> Function() read,
  ) async => CryptoFinancePolicyReadResult(await read(), policyOnly: false);
  @override
  Future<Map<String, dynamic>> dispatch({
    required DeviceSession session,
    required String operation,
    required Map<String, Object?> params,
    required Set<String> protectedScopeIds,
  }) async => throw StateError('Unexpected protected synthetic operation');
}

class _Transport extends OrganizationFinanceTransport {
  _Transport(super.server);
  final events = <String>[];
  Future<void> Function()? beforeContentPull;
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
    if (operation.startsWith('finance') && operation.endsWith('.policy')) {
      events.add('policy:${params['scopeId']}');
    }
    if (operation == 'finance4.push') events.add('push:${params['scopeId']}');
    if (operation == 'sync3.pull' || operation == 'sync.pull') {
      events.add('content');
      final callback = beforeContentPull;
      beforeContentPull = null;
      await callback?.call();
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
  Future<({CollaborationRepository repo, _Transport transport})> setup() async {
    final transport = _Transport(FakeServer())..seed(parentAccess: true);
    final repository = CollaborationRepository(
      CollaborationDatabase(NativeDatabase.memory()),
      transport,
      MemorySessionStore(),
      contentRouteGuard: const SyntheticContentRouteGuard(),
      cryptoRouter: _NoCryptoRouter(),
    );
    addTearDown(repository.close);
    await repository.initialize();
    await repository.login(
      serverUrl: 'https://example.test/',
      username: 'alice',
      password: 'synthetic',
    );
    transport.events.clear();
    return (repo: repository, transport: transport);
  }

  test(
    'policy-only fallback retains the full legacy changed-coverage response',
    () async {
      final f = await setup();
      expect(
        f.repo.state
            .financePolicyForScope(f.transport.parent)
            .organizationFinanceComplete,
        isTrue,
      );
      f.transport.organizationComplete = false;
      await f.repo.syncNow();
      expect(
        f.repo.state
            .financePolicyForScope(f.transport.parent)
            .organizationFinanceComplete,
        isFalse,
      );
      expect(f.repo.state.lastError, isNull);
    },
  );

  test(
    'policy-only actual adapter ignores wire markers without crypto dispatch',
    () async {
      final db = CollaborationDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final router = CryptoBusinessRouter(
        database: db,
        accountFor: (_) async =>
            throw StateError('No crypto dispatch expected'),
      );
      final result = await router.withFinancePolicyOnly(
        () async => {'policyOnly': true},
      );
      expect(result.value['policyOnly'], isTrue);
      expect(result.policyOnly, isFalse);
    },
  );

  test(
    'empty dependency queue fetches policy only for the ordinary finance pass',
    () async {
      final f = await setup();
      await f.repo.syncNow();
      expect(f.repo.state.lastError, isNull);
      expect(
        f.transport.events.where((e) => e.startsWith('policy:')),
        hasLength(2),
      );
      expect(f.transport.pushes, isEmpty);
    },
  );

  for (final allowed in [true, false]) {
    test(
      'queued dependency keeps fresh policy authorization allowed=$allowed',
      () async {
        final f = await setup();
        await f.repo.createFinanceAccount(
          scopeId: f.transport.parent,
          name: 'Synthetic dependency',
          currency: 'EUR',
        );
        f.transport.events.clear();
        f.transport.grant = allowed ? 'write' : 'none';
        await f.repo.syncNow();
        final policy = f.transport.events.indexOf(
          'policy:${f.transport.parent}',
        );
        expect(policy, greaterThanOrEqualTo(0));
        if (allowed) {
          final push = f.transport.events.indexOf('push:${f.transport.parent}');
          expect(push, greaterThan(policy));
          expect(push, lessThan(f.transport.events.indexOf('content')));
          expect(
            await f.repo.database.rows('SELECT 1 FROM finance_outbox'),
            isEmpty,
          );
        } else {
          expect(f.transport.pushes, isEmpty);
          expect(
            await f.repo.database.rows('SELECT 1 FROM finance_outbox'),
            isNotEmpty,
          );
        }
      },
    );
  }

  test(
    'dependency enqueued after empty preflight still needs later fresh policy',
    () async {
      final f = await setup();
      f.transport.beforeContentPull = () async {
        await f.repo.createFinanceAccount(
          scopeId: f.transport.parent,
          name: 'Late dependency',
          currency: 'EUR',
        );
        // Revoke permission after local enqueue, before the finance pass.
        f.transport.grant = 'none';
      };
      await f.repo.syncNow();
      final content = f.transport.events.indexOf('content');
      expect(content, greaterThanOrEqualTo(0));
      expect(
        f.transport.events.lastIndexOf('policy:${f.transport.parent}'),
        greaterThan(content),
      );
      expect(f.transport.pushes, isEmpty);
      expect(
        await f.repo.database.rows('SELECT 1 FROM finance_outbox'),
        isNotEmpty,
      );
    },
  );
}
