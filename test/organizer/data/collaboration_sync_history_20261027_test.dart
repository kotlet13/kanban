import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/data/collaboration_transport.dart';
import 'package:kanban/organizer/data/e2ee/crypto_domain_router.dart';
import 'package:kanban/organizer/data/device_session_store.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:kanban/organizer/presentation/shared/sharing_status_projection.dart';

import '../support/synthetic_content_route_guard.dart';
import 'collaboration_repository_test.dart'
    show FakeServer, FakeTransport, MemorySessionStore;

class _StatusDatabase extends CollaborationDatabase {
  _StatusDatabase(super.executor);
  bool failHistoryWrite = false, failHistoryRead = false;
  bool Function()? failFinalHistoryEvidenceRead;
  @override
  Future<void> execute(String sql, [List<Object?> args = const []]) {
    if (failHistoryWrite &&
        args.firstOrNull is String &&
        (args.first as String).startsWith('sync_success_history:')) {
      throw StateError('synthetic history write failure');
    }
    return super.execute(sql, args);
  }

  final reads = <String>[];
  @override
  Future<List<Map<String, dynamic>>> rows(
    String sql, [
    List<Object?> args = const [],
  ]) {
    reads.add(sql);
    if (sql.startsWith('SELECT EXISTS(SELECT 1 FROM crypto_outbox') &&
        failFinalHistoryEvidenceRead?.call() == true) {
      throw StateError('synthetic final history evidence read failure');
    }
    if (failHistoryRead &&
        args.firstOrNull is String &&
        (args.first as String).startsWith('sync_success_history:')) {
      throw StateError('synthetic history read failure');
    }
    return super.rows(sql, args);
  }
}

class _Router implements CryptoDomainRouter {
  @override
  Future<Map<String, dynamic>> dispatch({
    required DeviceSession session,
    required String operation,
    required Map<String, Object?> params,
    required Set<String> protectedScopeIds,
  }) async => throw StateError('Unexpected crypto dispatch');
}

class _Transport extends FakeTransport {
  _Transport(super.server, this.store);
  final MemorySessionStore store;
  final operations = <String>[];
  CollaborationApiException? failure;
  bool wrongIdentity = false;
  String? hintScope;
  Completer<void>? held, started;
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
      final profile = store.value!.profile;
      started?.complete();
      await held?.future;
      if (failure != null) throw failure!;
      final reset = params['cursor'] == null;
      return {
        'version': 1,
        'serverId': profile.serverId,
        'accountId': wrongIdentity ? 'other' : profile.accountId,
        'deviceId': profile.deviceId,
        'cursor': 'check-status-snapshot',
        'changed': reset || hintScope != null,
        'resetRequired': reset,
        'hasMore': false,
        'accountDomains': <String>[],
        'scopes': [
          if (hintScope != null)
            {
              'scopeId': hintScope,
              'domains': ['content'],
            },
        ],
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
            'accountChanges': true,
          }
        : reply;
  }
}

void main() {
  late Directory directory;
  late CollaborationRepository repo;
  late MemorySessionStore store;
  late _Transport transport;
  late DateTime now, success;
  late String scope, historyKey;
  CollaborationRepository open({bool failRead = false}) =>
      CollaborationRepository(
        _StatusDatabase(
          NativeDatabase(File('${directory.path}/history.sqlite')),
        )..failHistoryRead = failRead,
        transport,
        store,
        clock: () => now,
        contentRouteGuard: const SyntheticContentRouteGuard(),
        cryptoRouter: _Router(),
      );
  Future<void> reopen({bool failRead = false}) async {
    await repo.close();
    repo = open(failRead: failRead);
    await repo.initialize();
  }

  Future<String> saved() async =>
      (await repo.database.rows('SELECT value FROM local_meta WHERE name=?', [
            historyKey,
          ])).single['value']
          as String;
  SharingSyncStatus status() =>
      SharingStatusProjection.fromState(repo.state, now: now).status;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('sync-history-');
    store = MemorySessionStore();
    transport = _Transport(FakeServer(), store);
    now = DateTime.utc(2026, 10, 27, 9);
    repo = open();
    await repo.initialize();
    await repo.login(
      serverUrl: 'https://synthetic.invalid/',
      username: 'alice',
      password: 'synthetic',
    );
    scope = await repo.createScope('History');
    await repo.syncNow();
    success = now;
    final profile = repo.state.session!;
    historyKey =
        'sync_success_history:${profile.partition}:${Uri.encodeComponent(profile.deviceId)}';
    now = now.add(const Duration(minutes: 1));
    await reopen();
    transport.operations.clear();
  });
  tearDown(() async {
    await repo.close();
    await directory.delete(recursive: true);
  });

  test(
    'persisted history reopens neutral; unchanged check stays a cheap current check',
    () async {
      expect(repo.state.previousSuccessfulSyncAt, success);
      expect(repo.state.lastSuccessfulSyncAt, isNull);
      expect(repo.state.lastSuccessfulChangeCheckAt, isNull);
      expect(status(), SharingSyncStatus.historical);
      expect(transport.operations, isEmpty);
      final data = repo.state.data[scope];
      final history = await saved();
      await repo.syncNow();
      expect(status(), SharingSyncStatus.checked);
      expect(repo.state.lastSuccessfulChangeCheckAt, now);
      expect(repo.state.lastSuccessfulSyncAt, isNull);
      expect(repo.state.previousSuccessfulSyncAt, success);
      expect(await saved(), history);
      expect(
        transport.operations.where((o) => o == 'account.changes'),
        hasLength(1),
      );
      expect(transport.operations.where((o) => o.endsWith('.pull')), isEmpty);
      expect(identical(data, repo.state.data[scope]), isTrue);
      expect(repo.lastSyncCompletion, isNull);
    },
  );

  test(
    'offline failure and queued edits override historical status and preserve history',
    () async {
      final history = await saved();
      transport.failure = const CollaborationApiException('network');
      await expectLater(repo.syncNow(), throwsA(isA<CollaborationException>()));
      expect(status(), SharingSyncStatus.offline);
      expect(repo.state.previousSuccessfulSyncAt, success);
      expect(await saved(), history);
      transport.failure = null;
      await repo.syncNow();
      await repo.createTask(scopeId: scope, title: 'Durable pending');
      expect(status(), SharingSyncStatus.pending);
      expect(repo.state.previousSuccessfulSyncAt, success);
      expect(await saved(), history);
    },
  );

  for (final fixture in <String, Object?>{
    'malformed JSON': '{',
    'wrong shape': '[]',
    'unsupported version': {'version': 2},
    'wrong partition': {'partition': 'another-account-server'},
    'wrong device': {'deviceId': 'another-device'},
    'future timestamp': {'at': '2099-01-01T00:00:00.000Z'},
    'missing timestamp': {'at': null},
    'ambiguous local timestamp': {'at': '2026-10-27T08:00:00'},
  }.entries) {
    test('restore ignores ${fixture.key}', () async {
      final baseline = jsonDecode(await saved()) as Map<String, dynamic>;
      final value = fixture.value is Map
          ? jsonEncode({...baseline, ...fixture.value as Map})
          : fixture.value;
      await repo.database.execute(
        'UPDATE local_meta SET value=? WHERE name=?',
        [value, historyKey],
      );
      await reopen();
      expect(repo.state.previousSuccessfulSyncAt, isNull);
      expect(status(), SharingSyncStatus.unknown);
    });
  }

  for (final field in ['serverId', 'accountId', 'deviceId']) {
    test(
      'session with different $field cannot restore another identity history',
      () async {
        final session = store.value!;
        store.value = DeviceSession(
          AccountSession.fromJson({
            ...session.profile.toJson(),
            field: 'different-$field',
          }),
          session.token,
        );
        await reopen();
        expect(repo.state.previousSuccessfulSyncAt, isNull);
        expect(status(), SharingSyncStatus.unknown);
      },
    );
  }

  test(
    'optional history read failure cannot prevent local initialization',
    () async {
      await reopen(failRead: true);
      expect(repo.state.session, isNotNull);
      expect(repo.state.previousSuccessfulSyncAt, isNull);
      expect(repo.state.lastError, isNull);
      expect(repo.state.data[scope], isNotNull);
    },
  );

  test(
    'optional final history evidence read failure preserves verified completion',
    () async {
      final history = await saved();
      var injected = false;
      (repo.database as _StatusDatabase).failFinalHistoryEvidenceRead = () {
        if (!injected && repo.state.lastSuccessfulSyncAt == now) {
          injected = true;
          return true;
        }
        return false;
      };
      await repo.createTask(
        scopeId: scope,
        title: 'Delivery before optional read',
      );
      await repo.syncNow();
      expect(injected, isTrue);
      expect(repo.lastSyncCompletion, isNotNull);
      expect(repo.lastSyncCompletion!.error, isNull);
      expect(repo.lastSyncCompletion!.work.unresolved, isFalse);
      expect(repo.state.lastSuccessfulSyncAt, now);
      expect(await saved(), history);
      expect(status(), SharingSyncStatus.synced);
    },
  );

  test(
    'optional history write failure preserves verified completion and previous atomic row',
    () async {
      final history = await saved();
      (repo.database as _StatusDatabase).failHistoryWrite = true;
      await repo.createTask(scopeId: scope, title: 'Successful delivery');
      await repo.syncNow();
      expect(repo.lastSyncCompletion, isNotNull);
      expect(repo.lastSyncCompletion!.error, isNull);
      expect(repo.lastSyncCompletion!.work.unresolved, isFalse);
      expect(await saved(), history);
      expect(repo.state.lastSuccessfulSyncAt, now);
      expect(status(), SharingSyncStatus.synced);
      await reopen();
      expect(repo.state.previousSuccessfulSyncAt, success);
      expect(status(), SharingSyncStatus.historical);
    },
  );

  test(
    'signout clears visible history without exposing the prior account',
    () async {
      expect(repo.state.previousSuccessfulSyncAt, success);
      await repo.signOut();
      expect(repo.state.previousSuccessfulSyncAt, isNull);
      expect(status(), SharingSyncStatus.local);
    },
  );
}
