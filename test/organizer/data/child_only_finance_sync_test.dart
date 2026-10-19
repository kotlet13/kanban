import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/data/e2ee/crypto_sync_repository.dart';
import 'package:kanban/organizer/data/e2ee/crypto_domain_router.dart';
import 'package:kanban/organizer/data/device_session_store.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';

import '../support/synthetic_content_route_guard.dart';
import 'collaboration_repository_test.dart' show FakeServer, MemorySessionStore;
import 'organization_finance_client_test.dart'
    show OrganizationFinanceTransport;

// Explicit synthetic legacy transport fixture; there is no crypto cursor
// migration or live authority in these repository scheduling/error assertions.
class _LegacyRouter implements CryptoDomainRouter {
  @override
  Future<Map<String, dynamic>> dispatch({
    required DeviceSession session,
    required String operation,
    required Map<String, Object?> params,
    required Set<String> protectedScopeIds,
  }) async =>
      throw StateError('Synthetic guard must retain the legacy fixture route');
}

class _Transport extends OrganizationFinanceTransport {
  _Transport(super.server);
  Object? selectorError = const CryptoAuthorityPending(
    'crypto_account_choices_parent_unavailable',
  );
  final operations = <String>[];
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
    operations.add(operation);
    if (operation == 'finance4.accountChoices' && selectorError != null) {
      throw selectorError!;
    }
    if (operation == 'finance3.payments') {
      return {
        'accessRevision': revision,
        'scopeSequence': 0,
        'events': <Object>[],
        'cashMovements': <Object>[],
        'projections': <Object>[],
      };
    }
    final result = await super.call(
      serverUrl: serverUrl,
      operation: operation,
      params: params,
      token: token,
      allowLocalHttp: allowLocalHttp,
    );
    if (operation == 'capabilities') {
      return {
        ...result,
        'features': <String, dynamic>{
          ...result['features'] as Map,
          'linkedPayments': true,
        },
      };
    }
    if (operation.startsWith('finance') && operation.endsWith('.policy')) {
      return {...result, 'linkedPaymentsRequired': true};
    }
    return result;
  }
}

void main() {
  Future<
    ({
      CollaborationRepository repo,
      CollaborationDatabase db,
      _Transport transport,
    })
  >
  open({bool hiddenParent = true}) async {
    final server = FakeServer();
    final transport = _Transport(server)..organizationComplete = false;
    transport.seed();
    if (hiddenParent) {
      server.scopes[transport.project]!['parentScopeId'] = null;
      server.scopes[transport.project]!['parentScopeKind'] = null;
    }
    final db = CollaborationDatabase(NativeDatabase.memory());
    final repo = CollaborationRepository(
      db,
      transport,
      MemorySessionStore(),
      ownsDatabase: false,
      contentRouteGuard: const SyntheticContentRouteGuard(),
      cryptoRouter: _LegacyRouter(),
    );
    addTearDown(() async {
      await repo.close();
      await db.close();
    });
    await repo.initialize();
    await repo.login(
      serverUrl: 'https://example.test/',
      username: 'alice',
      password: 'fixture',
    );
    return (repo: repo, db: db, transport: transport);
  }

  test(
    'hidden-parent optional selector leaves content, finance and payment sync running without certifying coverage',
    () async {
      final f = await open();
      f.transport.operations.clear();
      await f.repo.syncNow();
      expect(f.repo.state.lastError, isNull);
      expect(
        f.transport.operations,
        containsAllInOrder([
          'sync3.pull',
          'finance4.policy',
          'finance4.pull',
          'finance4.accountChoices',
          'finance3.payments',
        ]),
      );
      final project = f.repo.state.scopes.singleWhere(
        (s) => s.id == f.transport.project,
      );
      expect(project.parentSpaceId, isNull);
      expect(
        f.repo.state.dataForScope(project.id).projects.single.id,
        project.id,
      );
      expect(
        f.repo.state
            .financePolicyForScope(project.id)
            .organizationFinanceComplete,
        isFalse,
      );
      expect(
        await f.db.rows('SELECT value FROM local_meta WHERE name LIKE ?', [
          'finance_account_choices:%',
        ]),
        isEmpty,
      );
      // The ordinary access-change stream still marks a confirmed lost scope.
      final original = newSharedId();
      final retained = SharedScope(
        id: original,
        name: 'Retained revoked data',
        kind: SharedScopeKind.organization,
        role: SharedRole.member,
      );
      final partition = f.repo.state.session!.partition;
      await f.db.execute(
        'INSERT INTO scopes(partition,id,data) VALUES(?,?,?)',
        [partition, original, jsonEncode(retained.toJson())],
      );
      f.transport.server.scopes[original] = retained.toJson();
      f.transport.server.members[original] = {};
      f.transport.server.confirmedRevocations['alice'] = {original};
      await f.repo.syncNow();
      expect(
        f.repo.state.scopes.singleWhere((s) => s.id == original).revoked,
        isTrue,
      );
      expect(f.repo.state.lastError, isNull);
    },
  );

  test(
    'malformed selector target is not suppressed by optional availability handling',
    () async {
      final f = await open();
      f.transport.selectorError = const FormatException(
        'crypto_account_choices_target',
      );
      await f.repo.syncNow();
      expect(f.repo.state.lastError?.code, 'invalid_response');
    },
  );

  test('unrelated authority pending remains visible', () async {
    final f = await open();
    f.transport.selectorError = const CryptoAuthorityPending(
      'directory_proof_pending',
    );
    await f.repo.syncNow();
    expect(f.repo.state.lastError?.code, 'crypto_reconciliation_required');
  });

  test(
    'known-parent selector still refreshes the normal received choices',
    () async {
      final f = await open(hiddenParent: false);
      f.transport.selectorError = null;
      await f.repo.syncNow();
      expect(f.repo.state.lastError, isNull);
      expect(
        await f.db.rows('SELECT value FROM local_meta WHERE name LIKE ?', [
          'finance_account_choices:%',
        ]),
        hasLength(1),
      );
    },
  );
}
