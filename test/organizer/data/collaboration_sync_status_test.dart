import 'dart:async';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'collaboration_repository_test.dart'
    show FakeServer, FakeTransport, MemorySessionStore;

class SyncStatusDatabase extends CollaborationDatabase {
  SyncStatusDatabase(super.executor);
  Future<void> Function()? beforePaymentResume;
  @override
  Future<List<Map<String, dynamic>>> rows(
    String sql, [
    List<Object?> args = const [],
  ]) async {
    if (sql ==
        "SELECT id,data FROM linked_payment_intents WHERE state='complete' ORDER BY rowid") {
      await beforePaymentResume?.call();
    }
    return super.rows(sql, args);
  }
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late FakeServer server;
  late FakeTransport transport;
  late SyncStatusDatabase database;
  late MemorySessionStore store;
  late CollaborationRepository repository;
  late DateTime now;
  setUp(() async {
    now = DateTime.utc(2026, 10, 10, 12);
    server = FakeServer();
    transport = FakeTransport(server);
    store = MemorySessionStore();
    database = SyncStatusDatabase(NativeDatabase.memory());
    repository = CollaborationRepository(
      database,
      transport,
      store,
      clock: () => now,
    );
    await repository.initialize();
  });
  tearDown(() async {
    await repository.close();
  });
  Future<void> login(String username) => repository.login(
    serverUrl: 'https://synthetic.invalid/',
    username: username,
    password: 'synthetic-password',
  );

  test(
    'first successful full sync records UTC times; later offline failure preserves last success',
    () async {
      expect(repository.state.lastSyncAttemptAt, isNull);
      expect(repository.state.lastSuccessfulSyncAt, isNull);
      await login('alice');
      final successful = now;
      expect(repository.state.lastSyncAttemptAt, successful);
      expect(repository.state.lastSuccessfulSyncAt, successful);
      now = now.add(const Duration(minutes: 5));
      transport.offline = true;
      await repository.syncNow();
      expect(repository.state.lastSyncAttemptAt, now);
      expect(repository.state.lastSuccessfulSyncAt, successful);
      expect(repository.state.lastError?.code, 'network');
      expect(repository.state.isSyncing, false);
      now = now.add(const Duration(minutes: 1));
      transport.offline = false;
      await repository.syncNow();
      expect(repository.state.lastSuccessfulSyncAt, now);
      expect(repository.state.lastError, isNull);
    },
  );
  test(
    'first sync failure and a partial sync cannot manufacture success evidence',
    () async {
      server.beforeCall = (operation, _, __) async {
        if (operation == 'capabilities') {
          throw const CollaborationException('network');
        }
      };
      await login('alice');
      expect(repository.state.lastSuccessfulSyncAt, isNull);
      expect(repository.state.lastSyncAttemptAt, now);
      server.beforeCall = null;
      now = now.add(const Duration(minutes: 1));
      await repository.syncNow(resumePayments: false);
      expect(repository.state.lastSuccessfulSyncAt, isNull);
      expect(repository.state.lastSyncAttemptAt, now);
      expect(repository.state.isSyncing, false);
      await repository.syncNow();
      expect(repository.state.lastSuccessfulSyncAt, now);
    },
  );
  test(
    'new account and signout clear sync history; reopen begins with unknown timestamps',
    () async {
      await login('alice');
      expect(repository.state.lastSuccessfulSyncAt, now);
      now = now.add(const Duration(minutes: 1));
      server.beforeCall = (operation, _, __) async {
        if (operation == 'capabilities') {
          throw const CollaborationException('network');
        }
      };
      await login('bob');
      expect(repository.state.session?.username, 'bob');
      expect(repository.state.lastSuccessfulSyncAt, isNull);
      expect(repository.state.lastSyncAttemptAt, now);
      server.beforeCall = null;
      await repository.close();
      database = SyncStatusDatabase(NativeDatabase.memory());
      repository = CollaborationRepository(
        database,
        FakeTransport(server),
        store,
        clock: () => now,
      );
      await repository.initialize();
      expect(repository.state.session?.username, 'bob');
      expect(repository.state.lastSyncAttemptAt, isNull);
      expect(repository.state.lastSuccessfulSyncAt, isNull);
      await repository.syncNow();
      expect(repository.state.lastSuccessfulSyncAt, now);
      await repository.signOut();
      expect(repository.state.session, isNull);
      expect(repository.state.lastSyncAttemptAt, isNull);
      expect(repository.state.lastSuccessfulSyncAt, isNull);
    },
  );
  test(
    'lease not claimed does not set success or leave the full-sync marker busy',
    () async {
      await login('alice');
      final first = now;
      now = now.add(const Duration(minutes: 1));
      await database.execute(
        'INSERT INTO sync_leases(partition,owner,expires_at) VALUES(?,?,?)',
        [
          repository.state.session!.partition,
          'other-process',
          now.add(const Duration(minutes: 1)).millisecondsSinceEpoch,
        ],
      );
      await repository.syncNow();
      expect(repository.state.lastSuccessfulSyncAt, first);
      expect(repository.state.isSyncing, false);
      await database.execute('DELETE FROM sync_leases');
      now = now.add(const Duration(seconds: 1));
      await repository.syncNow();
      expect(repository.state.lastSuccessfulSyncAt, now);
      expect(repository.state.isSyncing, false);
    },
  );
  test(
    'payment resume remains busy and its failure cannot update last successful sync',
    () async {
      await login('alice');
      final first = now;
      now = now.add(const Duration(minutes: 1));
      final started = Completer<void>(), release = Completer<void>();
      database.beforePaymentResume = () async {
        started.complete();
        await release.future;
        throw const CollaborationException('network');
      };
      final sync = repository.syncNow();
      await started.future;
      expect(repository.state.isSyncing, true);
      expect(repository.state.lastSuccessfulSyncAt, first);
      release.complete();
      await sync;
      expect(repository.state.isSyncing, false);
      expect(repository.state.lastSuccessfulSyncAt, first);
      expect(repository.state.lastError?.code, 'network');
      database.beforePaymentResume = null;
      await repository.syncNow();
      expect(repository.state.lastSuccessfulSyncAt, now);
    },
  );
  test(
    'nested partial sync from payment resume preserves busy state until full completion',
    () async {
      await login('alice');
      final first = now;
      now = now.add(const Duration(minutes: 1));
      var nested = 0;
      database.beforePaymentResume = () async {
        nested++;
        now = now.add(const Duration(seconds: 1));
        await repository.syncNow(resumePayments: false);
        expect(repository.state.isSyncing, true);
        expect(repository.state.lastSuccessfulSyncAt, first);
      };
      await repository.syncNow();
      expect(nested, 1);
      expect(repository.state.isSyncing, false);
      expect(repository.state.lastSuccessfulSyncAt, now);
      database.beforePaymentResume = null;
      now = now.add(const Duration(seconds: 1));
      await repository.syncNow();
      expect(repository.state.lastSuccessfulSyncAt, now);
    },
  );
  test(
    'nested partial failure keeps the outer resume busy until completion',
    () async {
      await login('alice');
      final first = now;
      now = now.add(const Duration(minutes: 1));
      final started = Completer<void>(), release = Completer<void>();
      database.beforePaymentResume = () async {
        server.beforeCall = (operation, _, __) async {
          if (operation == 'capabilities') {
            throw const CollaborationException('network');
          }
        };
        await repository.syncNow(resumePayments: false);
        server.beforeCall = null;
        expect(repository.state.isSyncing, true);
        expect(repository.state.lastError?.code, 'network');
        started.complete();
        await release.future;
      };
      final sync = repository.syncNow();
      await started.future;
      final calls = server.calls.length;
      await repository.syncNow();
      expect(server.calls.length, calls);
      expect(repository.state.isSyncing, true);
      release.complete();
      await sync;
      expect(repository.state.isSyncing, false);
      expect(repository.state.lastError?.code, 'network');
      expect(repository.state.lastSuccessfulSyncAt, first);
      database.beforePaymentResume = null;
      await repository.syncNow();
      expect(repository.state.lastSuccessfulSyncAt, now);
    },
  );
  test(
    'late sync completion cannot restore timestamps after switching accounts',
    () async {
      await login('alice');
      now = now.add(const Duration(minutes: 1));
      final started = Completer<void>(), release = Completer<void>();
      var delayed = false;
      server.beforeCall = (operation, _, __) async {
        if (operation == 'capabilities' && !delayed) {
          delayed = true;
          started.complete();
          await release.future;
        }
      };
      final sync = repository.syncNow();
      await started.future;
      await login('bob');
      expect(repository.state.session?.username, 'bob');
      expect(repository.state.lastSyncAttemptAt, isNull);
      expect(repository.state.lastSuccessfulSyncAt, isNull);
      expect(repository.state.isSyncing, false);
      release.complete();
      await sync;
      expect(repository.state.lastSyncAttemptAt, isNull);
      expect(repository.state.lastSuccessfulSyncAt, isNull);
      expect(repository.state.isSyncing, false);
      server.beforeCall = null;
      await repository.syncNow();
      expect(repository.state.lastSuccessfulSyncAt, now);
    },
  );
  test(
    'signout during payment resume rejects late success for the old identity',
    () async {
      await login('alice');
      now = now.add(const Duration(minutes: 1));
      final started = Completer<void>(), release = Completer<void>();
      database.beforePaymentResume = () async {
        started.complete();
        await release.future;
      };
      final sync = repository.syncNow();
      await started.future;
      await repository.signOut();
      expect(repository.state.lastSyncAttemptAt, isNull);
      expect(repository.state.lastSuccessfulSyncAt, isNull);
      expect(repository.state.isSyncing, false);
      release.complete();
      await sync;
      expect(repository.state.session, isNull);
      expect(repository.state.lastSuccessfulSyncAt, isNull);
      expect(repository.state.isSyncing, false);
    },
  );
}
