import 'dart:async';
import 'package:drift/native.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/data/collaboration_transport.dart';
import '../support/synthetic_content_route_guard.dart';
import 'package:kanban/organizer/data/device_session_store.dart';
import 'package:kanban/organizer/data/e2ee/crypto_domain_router.dart';
import 'collaboration_repository_test.dart'
    show FakeServer, FakeTransport, MemorySessionStore;

// This fixture exercises legacy seams only; protected crypto dispatch fails closed.
class _LegacyRouter implements CryptoDomainRouter {
  @override
  Future<Map<String, dynamic>> dispatch({
    required DeviceSession session,
    required String operation,
    required Map<String, Object?> params,
    required Set<String> protectedScopeIds,
  }) async => throw StateError('Unexpected protected dispatch');
}

class _Transport extends FakeTransport {
  _Transport(super.server, this.store);
  final MemorySessionStore store;
  final operations = <String>[];
  final probes = <Object?>[];
  String cursor = 'snapshot-1';
  Map<String, List<String>> hints = {};
  List<String> accountDomains = [];
  CollaborationApiException? probeFailure;
  bool rejectSavedCursor = false;
  bool wrongIdentity = false;
  List<String> pendingCryptoScopes = [];
  Future<void> Function()? gate;
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
    operations.add(operation);
    if (operation == 'account.changes') {
      probes.add(params['cursor']);
      if (probeFailure != null) throw probeFailure!;
      if (rejectSavedCursor && params['cursor'] != null)
        throw const CollaborationApiException('invalid_cursor');
      await gate?.call();
      final profile = store.value!.profile;
      final reset = params['cursor'] == null;
      return {
        'version': 1,
        'serverId': profile.serverId,
        'accountId': wrongIdentity ? 'other' : profile.accountId,
        'deviceId': profile.deviceId,
        'cursor': cursor,
        'changed': reset || hints.isNotEmpty || accountDomains.isNotEmpty,
        'resetRequired': reset,
        'hasMore': false,
        'accountDomains': accountDomains,
        'scopes': [
          for (final e in hints.entries) {'scopeId': e.key, 'domains': e.value},
        ],
      };
    }
    final result = await super.call(
      serverUrl: serverUrl,
      operation: operation,
      params: params,
      token: token,
      allowLocalHttp: allowLocalHttp,
    );
    if (operation == 'scopes.list' && pendingCryptoScopes.isNotEmpty) {
      return {...result, 'pendingCryptoScopeIds': pendingCryptoScopes};
    }
    if (operation == 'capabilities') {
      return {
        ...result,
        'accountChangeVersions': [1],
        'accountChanges': true,
      };
    }
    return result;
  }
}

void main() {
  Future<
    ({
      CollaborationRepository repo,
      FakeServer server,
      _Transport transport,
      String a,
      String b,
    })
  >
  setup() async {
    final server = FakeServer(), store = MemorySessionStore();
    final transport = _Transport(server, store);
    final repo = CollaborationRepository(
      CollaborationDatabase(NativeDatabase.memory()),
      transport,
      store,
      contentRouteGuard: const SyntheticContentRouteGuard(),
      cryptoRouter: _LegacyRouter(),
    );
    addTearDown(repo.close);
    await repo.initialize();
    await repo.login(
      serverUrl: 'https://example.test/',
      username: 'alice',
      password: 'synthetic',
    );
    final a = await repo.createScope('A'), b = await repo.createScope('B');
    await repo.syncNow();
    expect(repo.state.lastError, isNull);
    transport.operations.clear();
    transport.probes.clear();
    server.calls.clear();
    return (repo: repo, server: server, transport: transport, a: a, b: b);
  }

  Future<String?> saved(CollaborationRepository repo) async {
    final p = repo.state.session!;
    final rows = await repo.database.rows(
      'SELECT value FROM local_meta WHERE name=?',
      ['account_changes_v1:${p.partition}:${p.deviceId}'],
    );
    return rows.firstOrNull?['value'] as String?;
  }

  test(
    'unchanged probe publishes only check evidence without content refresh or full sync',
    () async {
      final f = await setup();
      final beforeState = f.repo.state,
          beforeCompletion = f.repo.lastSyncCompletion;
      var changes = 0, personal = 0;
      final sub = f.repo.changes.listen((_) => changes++);
      final ps = f.repo.database.personalChanges.stream.listen(
        (_) => personal++,
      );
      addTearDown(sub.cancel);
      addTearDown(ps.cancel);
      await f.repo.syncNow();
      await Future<void>.delayed(Duration.zero);
      expect(f.transport.operations, ['account.changes']);
      expect(identical(beforeState, f.repo.state), isFalse);
      expect(f.repo.state.lastSuccessfulChangeCheckAt, isNotNull);
      expect(
        f.repo.state.lastSuccessfulSyncAt,
        beforeState.lastSuccessfulSyncAt,
      );
      expect(f.repo.state.lastSyncAttemptAt, beforeState.lastSyncAttemptAt);
      expect(identical(beforeState.data[f.a], f.repo.state.data[f.a]), isTrue);
      expect(identical(beforeState.data[f.b], f.repo.state.data[f.b]), isTrue);
      expect(identical(beforeCompletion, f.repo.lastSyncCompletion), isTrue);
      expect(changes, 1);
      expect(personal, 0);
      expect(f.transport.probes, ['snapshot-1']);
    },
  );

  test(
    'content hint pulls affected scope and reuses unrelated local projection',
    () async {
      final f = await setup();
      final unrelated = f.repo.state.data[f.b];
      f.transport.hints = {
        f.a: ['content'],
      };
      f.transport.cursor = 'snapshot-2';
      await f.repo.syncNow();
      expect(f.repo.state.lastError, isNull);
      final pulls = f.server.calls
          .where((c) => c.operation.endsWith('.pull'))
          .toList();
      expect(pulls.map((c) => c.params['scopeId']), [f.a]);
      expect(
        f.transport.operations.where((o) => o.startsWith('finance')),
        isEmpty,
      );
      expect(f.transport.operations, isNot(contains('scopes.list')));
      expect(identical(unrelated, f.repo.state.data[f.b]), isTrue);
      expect(await saved(f.repo), 'snapshot-2');
    },
  );

  test(
    'pending local save delivers immediately even on unchanged account hint',
    () async {
      final f = await setup();
      final id = await f.repo.createTask(scopeId: f.a, title: 'Durable local');
      expect((await f.repo.syncWork()).unresolved, isTrue);
      await f.repo.syncNow();
      expect(f.server.records[f.a]![id]!['payload']['title'], 'Durable local');
      expect((await f.repo.syncWork()).unresolved, isFalse);
      expect(
        f.server.calls
            .where((c) => c.operation == 'sync.pull')
            .map((c) => c.params['scopeId']),
        [f.a],
      );
    },
  );

  test('partial verification failure retains checkpoint for retry', () async {
    final f = await setup();
    f.transport.hints = {
      f.a: ['content'],
    };
    f.transport.cursor = 'snapshot-2';
    f.server.beforeCall = (op, _, __) async {
      if (op == 'sync.pull') {
        throw const CollaborationApiException('synthetic_pull_failure');
      }
    };
    await f.repo.syncNow();
    expect(f.repo.lastSyncCompletion!.error, isNotNull);
    expect(await saved(f.repo), 'snapshot-1');
    f.server.beforeCall = null;
    await f.repo.syncNow(manual: true);
    expect(f.repo.state.lastError, isNull);
    expect(await saved(f.repo), 'snapshot-2');
  });

  test(
    'lost reply retains exact request and receipt retry has one business effect',
    () async {
      final f = await setup();
      final id = await f.repo.createTask(scopeId: f.a, title: 'Once');
      final before = await f.repo.database.rows(
        'SELECT op_id,request FROM outbox',
      );
      f.server.loseNextPushReply = true;
      await f.repo.syncNow();
      expect(f.repo.state.lastError?.code, 'network');
      expect(
        await f.repo.database.rows('SELECT op_id,request FROM outbox'),
        before,
      );
      await f.repo.syncNow(manual: true);
      expect(f.repo.state.lastError, isNull);
      expect(
        f.server.records[f.a]!.keys.where((key) => key == id),
        hasLength(1),
      );
      expect(f.server.replay, hasLength(1));
      expect((await f.repo.syncWork()).unresolved, isFalse);
    },
  );

  test(
    'overlapping requests coalesce and midflight demand receives next probe',
    () async {
      final f = await setup();
      final entered = Completer<void>(), release = Completer<void>();
      var calls = 0, active = 0, maximum = 0;
      f.transport.gate = () async {
        active++;
        if (active > maximum) maximum = active;
        if (++calls == 1) {
          entered.complete();
          await release.future;
        }
        active--;
      };
      final first = f.repo.syncNow();
      await entered.future;
      final rest = List.generate(12, (_) => f.repo.syncNow());
      release.complete();
      await Future.wait([first, ...rest]);
      expect(maximum, 1);
      expect(calls, 2);
      expect(f.transport.operations, ['account.changes', 'account.changes']);
    },
  );

  test('foreign account hint cannot advance cursor or fetch content', () async {
    final f = await setup();
    f.transport.wrongIdentity = true;
    await expectLater(f.repo.syncNow(), throwsA(isA<FormatException>()));
    expect(await saved(f.repo), 'snapshot-1');
    expect(f.transport.operations, ['account.changes']);
  });

  test(
    'access hint reconciles confirmed revoked scope without pulling its content',
    () async {
      final f = await setup();
      f.server.confirmRevocation(f.a, 'alice');
      f.transport.accountDomains = ['access'];
      f.transport.cursor = 'snapshot-2';
      await f.repo.syncNow();
      expect(
        f.repo.state.scopes.singleWhere((s) => s.id == f.a).revoked,
        isTrue,
      );
      expect(f.repo.state.data.containsKey(f.a), isFalse);
      expect(f.transport.operations, contains('scopes.list'));
      expect(
        f.transport.operations.where((op) => op.endsWith('.pull')),
        isEmpty,
      );
      expect(await saved(f.repo), 'snapshot-2');
    },
  );

  test(
    'same raw local projection refresh reuses content and avoids module signal',
    () async {
      final f = await setup();
      final before = f.repo.state.data[f.a];
      var signals = 0;
      final sub = f.repo.database.personalChanges.stream.listen(
        (_) => signals++,
      );
      addTearDown(sub.cancel);
      await f.repo.refreshLocal();
      await Future<void>.delayed(Duration.zero);
      expect(identical(before, f.repo.state.data[f.a]), isTrue);
      expect(signals, 0);
    },
  );
  test(
    'unknown scope hint discovers membership before content checkpoint',
    () async {
      final f = await setup();
      final id = newSharedId();
      f.server.scopes[id] = {
        ...f.server.scopes[f.a]!,
        'id': id,
        'name': 'New membership',
      };
      f.server.members[id] = {'alice': 'owner'};
      f.server.records[id] = {};
      f.server.sequence[id] = 0;
      f.transport.hints = {
        id: ['content'],
      };
      f.transport.cursor = 'snapshot-new';
      await f.repo.syncNow();
      expect(f.repo.state.lastError, isNull);
      expect(f.transport.operations, contains('scopes.list'));
      expect(f.repo.state.scopes.any((s) => s.id == id), isTrue);
      expect(
        f.server.calls
            .where((c) => c.operation == 'sync.pull')
            .map((c) => c.params['scopeId']),
        [id],
      );
      expect(await saved(f.repo), 'snapshot-new');
    },
  );

  test(
    'pending crypto scope retains checkpoint while independent scope pulls',
    () async {
      final f = await setup();
      f.transport.hints = {
        f.a: ['content'],
        f.b: ['content'],
      };
      f.transport.accountDomains = ['access'];
      f.transport.cursor = 'snapshot-pending';
      f.transport.pendingCryptoScopes = [f.a];
      await f.repo.syncNow();
      expect(f.repo.state.lastError?.code, 'crypto_reconciliation_required');
      expect(
        f.server.calls
            .where((c) => c.operation == 'sync.pull')
            .map((c) => c.params['scopeId']),
        [f.b],
      );
      expect(await saved(f.repo), 'snapshot-1');
    },
  );
  test(
    'rotated cursor resets exactly once and retains verified recovery',
    () async {
      final f = await setup();
      f.transport.rejectSavedCursor = true;
      f.transport.cursor = 'rotated';
      await f.repo.syncNow();
      expect(f.transport.probes, ['snapshot-1', null]);
      expect(f.repo.state.lastError, isNull);
      expect(f.transport.operations, contains('scopes.list'));
      expect(await saved(f.repo), 'rotated');
    },
  );
  test('probe failure publishes current status without content pull', () async {
    final f = await setup();
    final projection = f.repo.state.data[f.a];
    f.transport.probeFailure = const CollaborationApiException('network');
    await expectLater(
      f.repo.syncNow(),
      throwsA(isA<CollaborationApiException>()),
    );
    expect(f.repo.state.lastError?.code, 'network');
    expect(f.repo.state.lastSyncAttemptAt, isNotNull);
    expect(identical(projection, f.repo.state.data[f.a]), isTrue);
    expect(f.transport.operations, ['account.changes']);
    expect(await saved(f.repo), 'snapshot-1');
  });
  test('pending exact crypto work is not suppressed by unchanged hint', () async {
    final f = await setup();
    final p = f.repo.state.session!.partition;
    await f.repo.database.execute(
      'INSERT INTO crypto_outbox(partition,request_id,operation,signed_body,request_hash,state) VALUES(?,?,?,?,?,?)',
      [p, newSharedId(), 'synthetic_pending', '{}', 'synthetic', 'pending'],
    );
    await f.repo.syncNow();
    expect(f.transport.operations, contains('scopes.list'));
    expect(f.repo.lastSyncCompletion!.work.unresolved, isTrue);
    // This legacy fixture cannot deliver a crypto proof; the exact row survives.
    expect(
      await f.repo.database.rows(
        "SELECT state FROM crypto_outbox WHERE partition=?",
        [p],
      ),
      [
        {'state': 'pending'},
      ],
    );
  });
  test(
    'pending linked payment is attempted and failed intent remains visible',
    () async {
      final f = await setup();
      final p = f.repo.state.session!.partition;
      await f.repo.database.execute(
        'INSERT INTO linked_payment_intents(id,data,state) VALUES(?,?,?)',
        [newSharedId(), '{"partition":"$p"}', 'waiting_source_publication'],
      );
      await f.repo.syncNow();
      expect(f.transport.operations, contains('scopes.list'));
      expect(f.repo.state.lastError, isNotNull);
      expect(f.repo.lastSyncCompletion!.work.unresolved, isTrue);
      expect(await saved(f.repo), 'snapshot-1');
    },
  );
  test(
    'new probe error recovery clears only probe status without content pull',
    () async {
      final f = await setup();
      final success = f.repo.state.lastSuccessfulSyncAt;
      f.transport.probeFailure = const CollaborationApiException('network');
      await expectLater(
        f.repo.syncNow(),
        throwsA(isA<CollaborationApiException>()),
      );
      f.transport.probeFailure = null;
      await f.repo.syncNow(manual: true);
      expect(f.repo.state.lastError, isNull);
      expect(f.repo.state.lastSuccessfulSyncAt, success);
      expect(f.transport.operations, ['account.changes', 'account.changes']);
    },
  );
  test(
    'new cursor invalidation during apply cannot be overwritten by old acknowledgement',
    () async {
      final f = await setup();
      f.transport.hints = {
        f.a: ['content'],
      };
      f.transport.cursor = 'snapshot-new';
      final entered = Completer<void>(), release = Completer<void>();
      var held = false;
      f.server.beforeCall = (op, _, __) async {
        if (op == 'sync.pull' && !held) {
          held = true;
          entered.complete();
          await release.future;
        }
      };
      final first = f.repo.syncNow();
      await entered.future;
      await f.repo.invalidateAccountChangesCursor();
      final resumed = f.repo.syncNow();
      release.complete();
      await Future.wait([first, resumed]);
      expect(f.transport.probes, ['snapshot-1', null]);
      expect(await saved(f.repo), 'snapshot-new');
    },
  );
  test(
    'new unchanged hint cannot erase unrelated full sync failure evidence',
    () async {
      final f = await setup();
      f.transport.hints = {
        f.a: ['content'],
      };
      f.server.beforeCall = (op, _, __) async {
        if (op == 'sync.pull')
          throw const CollaborationApiException('synthetic_full_failure');
      };
      await f.repo.syncNow();
      expect(f.repo.state.lastError?.code, 'synthetic_full_failure');
      f.server.beforeCall = null;
      f.transport.hints = {};
      await f.repo.syncNow();
      expect(f.repo.state.lastError?.code, 'synthetic_full_failure');
    },
  );
  for (final mode in [
    'task',
    'shoppingList',
    'remote',
    'revoked',
    'offline',
    'unknown',
  ]) {
    test(
      'known visible content uses coordinator without separate preparation: $mode',
      () async {
        final f = await setup();
        final type = mode == 'shoppingList' ? 'shoppingList' : 'task';
        final id = type == 'shoppingList'
            ? await f.repo.createShoppingList(
                scopeId: f.a,
                title: 'Visible list',
              )
            : await f.repo.createTask(scopeId: f.a, title: 'Visible task');
        await f.repo.syncNow();
        expect(f.repo.state.lastError, isNull);
        final session = f.repo.state.session!;
        final target = NotificationTarget(
          serverUrl: session.serverUrl,
          serverId: session.serverId,
          accountId: session.accountId,
          scopeId: f.a,
          records: [
            NotificationRecordTarget(
              type: type,
              recordId: mode == 'unknown' ? newSharedId() : id,
            ),
          ],
        );
        if (mode == 'remote') {
          final old = f.server.records[f.a]![id]!;
          f.server.records[f.a]![id] = {
            ...old,
            'revision': (old['revision'] as int) + 1,
            'sequence': f.server.sequence[f.a] = f.server.sequence[f.a]! + 1,
            'payload': {...old['payload'] as Map, 'title': 'Changed remotely'},
          };
          f.transport.hints = {
            f.a: ['content'],
          };
        }
        if (mode == 'revoked') {
          f.server.confirmRevocation(f.a, 'alice');
          f.transport.accountDomains = ['access'];
        }
        if (mode == 'offline') {
          f.transport.probeFailure = const CollaborationApiException('network');
        }
        f.transport.operations.clear();
        f.server.calls.clear();
        final result = mode == 'shoppingList' || mode == 'unknown'
            ? await f.repo.openNotificationTarget(target)
            : await f.repo.refreshVisibleTaskTarget(target);
        if (mode == 'task' || mode == 'shoppingList') {
          expect(result.status, NotificationOpenStatus.available);
          expect(f.transport.operations, ['account.changes']);
        } else if (mode == 'remote') {
          expect(result.status, NotificationOpenStatus.available);
          expect(
            f.repo.state.dataForScope(f.a).tasks.single.title,
            'Changed remotely',
          );
          expect(
            f.server.calls
                .where((c) => c.operation == 'sync.pull')
                .map((c) => c.params['scopeId']),
            [f.a],
          );
          expect(
            f.server.calls.where((c) => c.operation == 'scopes.list'),
            isEmpty,
          );
        } else if (mode == 'revoked') {
          expect(result.status, NotificationOpenStatus.permissionDenied);
          expect(
            f.repo.state.scopes.singleWhere((s) => s.id == f.a).canRead,
            isFalse,
          );
        } else if (mode == 'offline') {
          expect(result.status, NotificationOpenStatus.offline);
          expect(
            f.repo.state.dataForScope(f.a).tasks.single.title,
            'Visible task',
          );
          expect(f.transport.operations, ['account.changes']);
        } else {
          expect(result.status, NotificationOpenStatus.requiresConnection);
          expect(f.transport.operations, contains('scopes.list'));
          expect(f.transport.operations, contains('capabilities'));
        }
      },
    );
  }
}
