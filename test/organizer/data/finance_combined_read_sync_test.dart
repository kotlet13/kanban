import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/data/device_session_store.dart';
import 'package:kanban/organizer/data/e2ee/crypto_domain_router.dart';
import 'package:kanban/organizer/data/e2ee/crypto_sync_repository.dart';
import 'package:kanban/organizer/domain/linked_payment_models.dart';

import '../support/synthetic_content_route_guard.dart';
import 'collaboration_repository_test.dart' show FakeServer, MemorySessionStore;
import 'organization_finance_client_test.dart'
    show OrganizationFinanceTransport;

// These tests check the repository's bounded context contract. Crypto evidence
// and actual pull reuse are tested through the real encrypted adapter elsewhere.
class _ReadWindow {
  _ReadWindow(this.session);
  final DeviceSession session;
  bool closed = false;
}

class _ReadRouter implements CryptoDomainRouter, CryptoFinanceReadContext {
  static final key = Object();
  final windows = <_ReadWindow>[];

  @override
  Future<T> withFinanceRead<T>({
    required DeviceSession session,
    required Future<T> Function() read,
  }) async {
    final window = _ReadWindow(session);
    windows.add(window);
    try {
      return await runZoned(read, zoneValues: {key: window});
    } finally {
      window.closed = true;
    }
  }

  @override
  Future<Map<String, dynamic>> dispatch({
    required DeviceSession session,
    required String operation,
    required Map<String, Object?> params,
    required Set<String> protectedScopeIds,
  }) async => throw StateError('Explicit synthetic guard retains legacy route');
}

class _ReadCall {
  _ReadCall(this.operation, this.scope, this.window);
  final String operation;
  final String? scope;
  final _ReadWindow? window;
}

class _Transport extends OrganizationFinanceTransport {
  _Transport(super.server);
  final calls = <_ReadCall>[];
  Object? choicesError;
  Object? paymentsError;

  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
    calls.add(
      _ReadCall(
        operation,
        params['scopeId'] as String?,
        Zone.current[_ReadRouter.key] as _ReadWindow?,
      ),
    );
    if (operation == 'finance4.accountChoices' && choicesError != null) {
      throw choicesError!;
    }
    if (operation == 'finance3.payments') {
      if (paymentsError != null) throw paymentsError!;
      return {
        'accessRevision': revision,
        'scopeSequence': 0,
        'events': <Object>[],
        'cashMovements': <Object>[],
        'projections': <Object>[],
      };
    }
    final reply = await super.call(
      serverUrl: serverUrl,
      operation: operation,
      params: params,
      token: token,
      allowLocalHttp: allowLocalHttp,
    );
    if (operation == 'capabilities') {
      return {
        ...reply,
        'features': <String, dynamic>{
          ...reply['features'] as Map,
          'linkedPayments': true,
        },
      };
    }
    if (operation.startsWith('finance') && operation.endsWith('.policy')) {
      return {...reply, 'linkedPaymentsRequired': true};
    }
    return reply;
  }
}

void main() {
  Future<
    ({CollaborationRepository repo, _Transport transport, _ReadRouter router})
  >
  open() async {
    final transport = _Transport(FakeServer())..seed(parentAccess: true);
    final router = _ReadRouter();
    final repo = CollaborationRepository(
      CollaborationDatabase(NativeDatabase.memory()),
      transport,
      MemorySessionStore(),
      contentRouteGuard: const SyntheticContentRouteGuard(),
      cryptoRouter: router,
    );
    addTearDown(repo.close);
    await repo.initialize();
    await repo.login(
      serverUrl: 'https://example.test/',
      username: 'alice',
      password: 'synthetic',
    );
    transport.calls.clear();
    router.windows.clear();
    return (repo: repo, transport: transport, router: router);
  }

  test(
    'ordinary finance consumers share one context per scope and finish it',
    () async {
      final f = await open();
      await f.repo.syncNow();
      expect(f.repo.state.lastError, isNull);
      expect(f.router.windows, hasLength(2));
      for (final window in f.router.windows) {
        final calls = f.transport.calls.where(
          (c) => identical(c.window, window),
        );
        expect(
          calls.map((c) => c.scope).whereType<String>().toSet(),
          hasLength(1),
        );
        expect(
          calls.map((c) => c.operation),
          containsAllInOrder([
            'finance4.policy',
            'finance4.pull',
            'finance4.policy',
            'finance3.payments',
          ]),
        );
        expect(
          window.session.profile.partition,
          f.repo.state.session!.partition,
        );
        expect(window.closed, isTrue);
      }
      final choices = f.transport.calls.singleWhere(
        (c) => c.operation == 'finance4.accountChoices',
      );
      final projectPull = f.transport.calls.singleWhere(
        (c) => c.operation == 'finance4.pull' && c.scope == f.transport.project,
      );
      expect(identical(choices.window, projectPull.window), isTrue);
      expect(
        f.transport.calls
            .where((c) => c.operation == 'sync3.pull')
            .every((c) => c.window == null),
        isTrue,
      );
    },
  );

  test(
    'later sync and standalone finance actions cannot inherit a context',
    () async {
      final f = await open();
      await f.repo.syncNow();
      final first = f.router.windows.toSet();
      await f.repo.syncNow();
      expect(f.router.windows, hasLength(4));
      expect(f.router.windows.skip(2).any(first.contains), isFalse);
      f.transport.calls.clear();
      await f.repo.refreshFinanceAccountChoices(f.transport.project);
      await f.repo.fetchLinkedPayments(
        PaymentSpaceRef(
          f.transport.project,
          partition: f.repo.state.session!.partition,
        ),
      );
      expect(f.transport.calls.every((c) => c.window == null), isTrue);
      expect(f.router.windows.every((w) => w.closed), isTrue);
    },
  );

  test(
    'caught authority failure closes only its scope and next pass starts fresh',
    () async {
      final f = await open();
      f.transport.choicesError = const CryptoAuthorityPending(
        'directory_proof_pending',
      );
      await f.repo.syncNow();
      expect(f.repo.state.lastError?.code, 'crypto_reconciliation_required');
      expect(f.router.windows, hasLength(2));
      expect(f.router.windows.every((w) => w.closed), isTrue);
      f.transport.choicesError = null;
      await f.repo.syncNow();
      expect(f.repo.state.lastError, isNull);
      expect(f.router.windows, hasLength(4));
      expect(f.router.windows.every((w) => w.closed), isTrue);
    },
  );

  test(
    'uncaught malformed payment response disposes context before next pass',
    () async {
      final f = await open();
      f.transport.paymentsError = const FormatException(
        'synthetic malformed payment',
      );
      await f.repo.syncNow();
      expect(f.repo.state.lastError?.code, 'invalid_response');
      final failedWindows = f.router.windows.toSet();
      expect(failedWindows, isNotEmpty);
      expect(failedWindows.every((w) => w.closed), isTrue);
      f.transport.paymentsError = null;
      await f.repo.syncNow();
      expect(f.repo.state.lastError, isNull);
      expect(
        f.router.windows.skip(failedWindows.length).any(failedWindows.contains),
        isFalse,
      );
      expect(f.router.windows.every((w) => w.closed), isTrue);
    },
  );
}
