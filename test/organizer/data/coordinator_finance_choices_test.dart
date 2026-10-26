import 'dart:async';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:kanban/organizer/data/device_session_store.dart';
import 'package:kanban/organizer/data/e2ee/crypto_domain_router.dart';
import '../support/synthetic_content_route_guard.dart';
import 'collaboration_repository_test.dart'
    show FakeServer, MemorySessionStore, code;
import 'organization_finance_client_test.dart'
    show OrganizationFinanceTransport;

class _Legacy implements CryptoDomainRouter {
  @override
  Future<Map<String, dynamic>> dispatch({
    required DeviceSession session,
    required String operation,
    required Map<String, Object?> params,
    required Set<String> protectedScopeIds,
  }) => throw StateError('No synthetic crypto authority');
}

class _Transport extends OrganizationFinanceTransport {
  _Transport() : super(FakeServer());
  int policies = 0, choices = 0;
  Future<void> Function()? gate;
  bool failChoices = false;
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
    if (operation.startsWith('finance') && operation.endsWith('.policy')) {
      policies++;
    }
    if (operation == 'finance4.accountChoices') {
      choices++;
      await gate?.call();
      if (failChoices) throw const CollaborationException('network');
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

Future<({CollaborationRepository repo, _Transport transport})>
_fixture() async {
  final transport = _Transport()..seed();
  final repo = CollaborationRepository(
    CollaborationDatabase(NativeDatabase.memory()),
    transport,
    MemorySessionStore(),
    contentRouteGuard: const SyntheticContentRouteGuard(),
    cryptoRouter: _Legacy(),
  );
  addTearDown(repo.close);
  await repo.initialize();
  await repo.login(
    serverUrl: 'https://synthetic.invalid',
    username: 'alice',
    password: 'synthetic',
  );
  await repo.refreshFinancePolicy(transport.project);
  transport.policies = transport.choices = 0;
  return (repo: repo, transport: transport);
}

Future<void> _flush() async {
  for (var i = 0; i < 30; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  test(
    'compatible concurrent finance preparations share work but subsequent opens are fresh',
    () async {
      final f = await _fixture();
      final entered = Completer<void>(), release = Completer<void>();
      f.transport.gate = () async {
        if (!entered.isCompleted) entered.complete();
        await release.future;
      };
      final first = f.repo.refreshFinanceAccountChoices(f.transport.project);
      await entered.future;
      final second = f.repo.refreshFinanceAccountChoices(f.transport.project);
      await _flush();
      expect(f.transport.choices, 1);
      expect(f.transport.policies, 1);
      release.complete();
      await Future.wait([first, second]);
      f.transport.gate = null;
      await f.repo.refreshFinanceAccountChoices(f.transport.project);
      expect(f.transport.choices, 2);
      expect(f.transport.policies, 2);
    },
  );
  for (final distinction in ['editor', 'authority', 'finance-generation']) {
    test(
      'different finance preparation snapshot cannot join: $distinction',
      () async {
        final f = await _fixture();
        final firstEntered = Completer<void>(),
            bothEntered = Completer<void>(),
            release = Completer<void>();
        f.transport.gate = () async {
          if (!firstEntered.isCompleted) {
            firstEntered.complete();
          } else if (!bothEntered.isCompleted) {
            bothEntered.complete();
          }
          await release.future;
        };
        // Start with editor mode: no full-policy update can mask the generation seam.
        final first = f.repo.refreshFinanceAccountChoices(
          f.transport.project,
          refreshPolicy: false,
        );
        final firstOutcome = first.then<Object?>(
          (_) => null,
          onError: (Object e) => e,
        );
        await firstEntered.future;
        if (distinction == 'authority') {
          f.repo.authorityReuse.invalidateScopes({f.transport.project});
        }
        if (distinction == 'finance-generation') {
          await f.repo.database.execute(
            "INSERT INTO local_meta(name,value) VALUES(?,1) ON CONFLICT(name) DO UPDATE SET value=CAST(value AS INTEGER)+1",
            [
              'finance_access_generation:${f.repo.state.session!.partition}:${f.transport.project}',
            ],
          );
        }
        final second = f.repo.refreshFinanceAccountChoices(
          f.transport.project,
          refreshPolicy: distinction == 'editor',
        );
        final secondOutcome = second.then<Object?>(
          (_) => null,
          onError: (Object e) => e,
        );
        await bothEntered.future.timeout(const Duration(seconds: 5));
        expect(f.transport.choices, 2);
        release.complete();
        final outcomes = await Future.wait([firstOutcome, secondOutcome]);
        if (distinction == 'finance-generation') {
          expect(
            outcomes.first,
            isNotNull,
          ); // Existing generation guard rejects old reply.
        } else {
          expect(outcomes, [null, null]);
        }
      },
    );
  }
  test(
    'failed coalesced finance preparation is removed for a later retry',
    () async {
      final f = await _fixture();
      final entered = Completer<void>(), release = Completer<void>();
      f.transport.failChoices = true;
      f.transport.gate = () async {
        if (!entered.isCompleted) entered.complete();
        await release.future;
      };
      final first = f.repo.refreshFinanceAccountChoices(f.transport.project);
      final checkedFirst = expectLater(first, throwsA(code('network')));
      await entered.future;
      final second = f.repo.refreshFinanceAccountChoices(f.transport.project);
      final checkedSecond = expectLater(second, throwsA(code('network')));
      await _flush();
      expect(f.transport.choices, 1);
      release.complete();
      await Future.wait([checkedFirst, checkedSecond]);
      f.transport.failChoices = false;
      f.transport.gate = null;
      await f.repo.refreshFinanceAccountChoices(f.transport.project);
      expect(f.transport.choices, 2);
    },
  );
}
