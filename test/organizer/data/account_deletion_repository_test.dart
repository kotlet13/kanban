import 'dart:async';
import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/account_deletion_store.dart';
import 'package:kanban/organizer/data/organizer_repository.dart';
import 'package:kanban/organizer/data/organizer_storage.dart';
import 'package:kanban/organizer/data/sqlite_organizer_storage.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'collaboration_repository_test.dart'
    show FakeServer, FakeTransport, MemorySessionStore, code;

class DeletionServer extends FakeServer {
  bool supported = true, loseAck = false, cleanupPending = false;
  String? reject;
  String? lastCancelBearer;
  final receipts = <String, String>{};
  final cancelled = <String, String>{};
  Map<String, Object?>? confirmed;
  Completer<void>? paused, entered;
  @override
  Future<Map<String, dynamic>> call(
    String operation,
    Map<String, Object?> params,
    String? token,
  ) async {
    if (operation == 'capabilities') {
      final caps = await super.call(operation, params, token);
      (caps['features'] as Map)['accountDeletion'] = supported;
      return caps;
    }
    if (operation == 'account.deletion.cancelPending') {
      lastCancelBearer = token;
      if (!receipts.containsKey(params['operationId']) &&
          !cancelled.containsKey(params['operationId'])) {
        if (tokens[token] != 'alice') {
          throw const CollaborationException('auth_required');
        }
        cancelled[params['operationId'] as String] =
            params['receiptToken'] as String;
      }
      return {
        'serverId': serverId,
        'deleted':
            receipts[params['operationId']] == params['receiptToken'] &&
            !cleanupPending,
        'cleanupPending':
            receipts[params['operationId']] == params['receiptToken'] &&
            cleanupPending,
        'cancelled': cancelled[params['operationId']] == params['receiptToken'],
      };
    }
    if (operation == 'account.deletion.status') {
      expect(token, isNull);
      return {
        'serverId': serverId,
        'deleted':
            receipts[params['operationId']] == params['receiptToken'] &&
            !cleanupPending,
        'cleanupPending':
            receipts[params['operationId']] == params['receiptToken'] &&
            cleanupPending,
        'cancelled': cancelled[params['operationId']] == params['receiptToken'],
      };
    }
    if (operation == 'account.deletion.preview') {
      return {
        'serverId': serverId,
        'accountId': accountIds[tokens[token]],
        'policyVersion': 1,
        'previewHash': 'a' * 64,
        'canDelete': true,
        'blockers': [],
        'impact': {'personalRecords': 2},
        'sharedScopes': [],
        'ownedScopes': [],
        'resolutions': [],
      };
    }
    if (operation == 'account.deletion.confirm') {
      entered?.complete();
      await paused?.future;
      if (cancelled[params['operationId']] == params['receiptToken']) {
        throw const CollaborationException('deletion_cancelled');
      }
      if (reject != null) throw CollaborationException(reject!);
      confirmed = Map.of(params);
      receipts[params['operationId'] as String] =
          params['receiptToken'] as String;
      final user = tokens[token];
      tokens.removeWhere((_, u) => u == user);
      if (loseAck) throw const CollaborationException('network');
      return {
        'deleted': !cleanupPending,
        'cleanupPending': cleanupPending,
        'serverId': serverId,
      };
    }
    return super.call(operation, params, token);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DeletionServer server;
  late CollaborationRepository repo;
  late MemorySessionStore sessions;
  late MemoryAccountDeletionStore receipts;
  setUp(() async {
    server = DeletionServer();
    sessions = MemorySessionStore();
    receipts = MemoryAccountDeletionStore();
    repo = CollaborationRepository(
      CollaborationDatabase(NativeDatabase.memory()),
      FakeTransport(server),
      sessions,
      deletionStore: receipts,
    );
    await repo.initialize();
    await repo.login(
      serverUrl: 'https://example.invalid',
      username: 'alice',
      password: 'login',
    );
  });
  tearDown(() => repo.close());

  test('unsupported and offline previews do not submit deletion', () async {
    server.supported = false;
    await expectLater(
      repo.previewAccountDeletion(),
      throwsA(code('deletion_unavailable')),
    );
    expect(receipts.requests, isEmpty);
    expect(server.confirmed, null);
  });
  test(
    'confirmed deletion removes only server partition and recovery, preserves local work',
    () async {
      final profile = repo.state.session!;
      final scope = await repo.createScope('Shared');
      await repo.createTask(scopeId: scope, title: 'Pending shared task');
      await repo.database.execute(
        "INSERT INTO personal_records(workspace,id,type,payload) VALUES('local','local-task','task','{}')",
      );
      await repo.database.execute(
        'INSERT INTO personal_workspaces(id,partition,scope_id) VALUES(?,?,?)',
        ['private:${profile.partition}', profile.partition, scope],
      );
      await repo.database.execute(
        "INSERT INTO personal_records(workspace,id,type,payload) VALUES(?, 'private-reminder','reminder','{}')",
        ['private:${profile.partition}'],
      );
      await repo.database.execute(
        "INSERT INTO restored_backups(id,created_at,source_partition,data) VALUES('old','now',?,'{}')",
        [profile.partition],
      );
      final oldSession = sessions.value;
      final preview = await repo.previewAccountDeletion();
      await repo.confirmAccountDeletion(
        previewHash: preview['previewHash'] as String,
        password: 'step-up',
        review: preview,
      );
      expect(repo.state.session, null);
      expect(sessions.value, null);
      expect(receipts.requests, isEmpty);
      for (final table in [
        'accounts',
        'scopes',
        'records',
        'outbox',
        'personal_workspaces',
        'restored_backups',
      ]) {
        expect(
          await repo.database.rows('SELECT * FROM $table'),
          isEmpty,
          reason: table,
        );
      }
      expect(
        await repo.database.rows(
          "SELECT id FROM personal_records WHERE workspace='local'",
        ),
        hasLength(1),
      );
      expect(
        await repo.database.rows('SELECT value FROM local_meta WHERE name=?', [
          'deleted_account:${profile.partition}',
        ]),
        hasLength(1),
      );
      // A crash or old secure-store image cannot reopen the deleted identity.
      sessions.value = oldSession;
      final restarted = CollaborationRepository(
        repo.database,
        FakeTransport(server),
        sessions,
        deletionStore: receipts,
        ownsDatabase: false,
      );
      await restarted.initialize();
      expect(restarted.state.session, null);
      expect(sessions.value, null);
      await restarted.close();
    },
  );
  test(
    'lost ACK keeps receipt without credentials, freezes sync, status survives restart',
    () async {
      final profile = repo.state.session!;
      final preview = await repo.previewAccountDeletion();
      server.loseAck = true;
      await expectLater(
        repo.confirmAccountDeletion(
          previewHash: preview['previewHash'] as String,
          password: 'secret-password',
          otp: '123456',
          review: preview,
        ),
        throwsA(code('network')),
      );
      expect(repo.state.deletionPending, true);
      expect(repo.database.personalProfile, null);
      final pending = receipts.requests.single;
      expect(jsonEncode(pending.toJson()), isNot(contains('secret-password')));
      expect(jsonEncode(pending.toJson()), isNot(contains('123456')));
      expect(pending.receiptToken, hasLength(64));
      final restarted = CollaborationRepository(
        repo.database,
        FakeTransport(server),
        sessions,
        deletionStore: receipts,
        ownsDatabase: false,
      );
      await restarted.initialize();
      expect(restarted.state.deletionPending, true);
      expect(await restarted.checkAccountDeletion(pending), true);
      expect(restarted.state.session, null);
      expect(
        await repo.database.rows('SELECT value FROM local_meta WHERE name=?', [
          'deleted_account:${profile.partition}',
        ]),
        hasLength(1),
      );
      await restarted.close();
    },
  );
  test('invalid step-up does not sign out or leave a sync barrier', () async {
    final preview = await repo.previewAccountDeletion();
    server.reject = 'invalid_credentials';
    await expectLater(
      repo.confirmAccountDeletion(
        previewHash: preview['previewHash'] as String,
        password: 'bad',
        review: preview,
      ),
      throwsA(code('invalid_credentials')),
    );
    expect(repo.state.session, isNotNull);
    expect(repo.state.sessionInvalid, false);
    expect(repo.state.deletionPending, false);
    expect(receipts.requests, isEmpty);
  });
  test(
    'file cleanup acceptance purges local account but retains receipt until completed',
    () async {
      final preview = await repo.previewAccountDeletion();
      server.cleanupPending = true;
      await repo.confirmAccountDeletion(
        previewHash: preview['previewHash'] as String,
        password: 'pass',
        review: preview,
      );
      expect(repo.state.session, null);
      expect(receipts.requests.single.serverAccepted, true);
      final pending = receipts.requests.single;
      expect(await repo.checkAccountDeletion(pending), false);
      server.cleanupPending = false;
      expect(await repo.checkAccountDeletion(pending), true);
      expect(receipts.requests, isEmpty);
    },
  );

  test(
    'feature-disabled on first request is a safe precommit rejection',
    () async {
      final preview = await repo.previewAccountDeletion();
      server.reject = 'feature_disabled';
      await expectLater(
        repo.confirmAccountDeletion(
          previewHash: preview['previewHash'] as String,
          password: 'pass',
          review: preview,
        ),
        throwsA(code('feature_disabled')),
      );
      expect(receipts.requests, isEmpty);
      expect(repo.state.deletionPending, false);
      expect(repo.state.session, isNotNull);
    },
  );
  test(
    'retry rejection retains unknown receipt; confirmed cancellation alone unfreezes work',
    () async {
      final preview = await repo.previewAccountDeletion();
      // Simulate an unacknowledged request without asserting a server outcome.
      final request = PendingAccountDeletion(
        profile: repo.state.session!,
        operationId: newSharedId(),
        previewHash: preview['previewHash'] as String,
        receiptToken: 'b' * 64,
        review: preview,
      );
      receipts.requests = [request];
      await repo.database.execute(
        'INSERT INTO local_meta(name,value) VALUES(?,?)',
        ['deletion_pending:${request.profile.partition}', '1'],
      );
      server.reject = 'rate_limited';
      await expectLater(
        repo.confirmAccountDeletion(
          previewHash: request.previewHash,
          password: 'fresh',
          review: preview,
        ),
        throwsA(code('rate_limited')),
      );
      expect(receipts.requests.single.operationId, request.operationId);
      expect(repo.state.deletionPending, true);
      expect(await repo.cancelPendingAccountDeletion(request), true);
      expect(receipts.requests, isEmpty);
      expect(repo.state.deletionPending, false);
      expect(repo.state.session, isNotNull);
      // A delayed original is terminally rejected by the cancellation receipt.
      await expectLater(
        server.call('account.deletion.confirm', {
          'operationId': request.operationId,
          'receiptToken': request.receiptToken,
        }, sessions.value!.token),
        throwsA(code('deletion_cancelled')),
      );
    },
  );
  test(
    'new cancellation requires login to original account and never sends B bearer',
    () async {
      final preview = await repo.previewAccountDeletion();
      final request = PendingAccountDeletion(
        profile: repo.state.session!,
        operationId: newSharedId(),
        previewHash: preview['previewHash'] as String,
        receiptToken: 'c' * 64,
        review: preview,
      );
      receipts.requests = [request];
      await repo.database.execute(
        'INSERT INTO local_meta(name,value) VALUES(?,?)',
        ['deletion_pending:${request.profile.partition}', '1'],
      );
      await repo.signOut();
      await expectLater(
        repo.cancelPendingAccountDeletion(request),
        throwsA(code('auth_required')),
      );
      expect(server.lastCancelBearer, null);
      expect(receipts.requests, hasLength(1));
      await repo.login(
        serverUrl: 'https://example.invalid',
        username: 'bob',
        password: 'login',
      );
      await expectLater(
        repo.cancelPendingAccountDeletion(request),
        throwsA(code('auth_required')),
      );
      expect(server.lastCancelBearer, null);
      expect(repo.state.session!.username, 'bob');
      await repo.login(
        serverUrl: 'https://example.invalid',
        username: 'alice',
        password: 'login',
      );
      expect(await repo.cancelPendingAccountDeletion(request), true);
      expect(server.lastCancelBearer, sessions.value!.token);
      expect(receipts.requests, isEmpty);
      expect(repo.state.deletionPending, false);
    },
  );

  test(
    'cancellation after original commit reports deletion and never revives account',
    () async {
      final preview = await repo.previewAccountDeletion();
      server.loseAck = true;
      await expectLater(
        repo.confirmAccountDeletion(
          previewHash: preview['previewHash'] as String,
          password: 'pass',
          review: preview,
        ),
        throwsA(code('network')),
      );
      expect(
        await repo.cancelPendingAccountDeletion(receipts.requests.single),
        false,
      );
      expect(repo.state.session, null);
      expect(receipts.requests, isEmpty);
    },
  );
  test(
    'explicit personal JSON export survives deletion and imports locally without uploads',
    () async {
      final storage = SqliteOrganizerStorage(repo.database);
      await storage.initialize();
      final profile = repo.state.session!,
          scope = await repo.createScope('Private');
      final task = await repo.createTask(
        scopeId: scope,
        title: 'Keep this private task',
      );
      final row = (await repo.database.rows(
        'SELECT data FROM scopes WHERE partition=? AND id=?',
        [profile.partition, scope],
      )).single;
      final data = jsonDecode(row['data'] as String) as Map<String, dynamic>;
      data['kind'] = 'personal';
      await repo.database.execute(
        'UPDATE scopes SET data=? WHERE partition=? AND id=?',
        [jsonEncode(data), profile.partition, scope],
      );
      await repo.database.execute(
        'INSERT INTO personal_workspaces(id,partition,scope_id,enabled) VALUES(?,?,?,1)',
        ['private:${profile.partition}', profile.partition, scope],
      );
      await repo.database.execute(
        "INSERT INTO personal_record_map(workspace,id,remote_id,type) VALUES(?,?,?,'task')",
        ['private:${profile.partition}', task, task],
      );
      repo.database.activatePersonal(profile);
      final personal = OrganizerRepository(storage);
      await personal.initialize();
      final json = await personal.exportBackup();
      expect(
        OrganizerBackupCodec.decode(json).tasks.single.title,
        'Keep this private task',
      );
      final preview = await repo.previewAccountDeletion();
      await repo.confirmAccountDeletion(
        previewHash: preview['previewHash'] as String,
        password: 'pass',
        review: preview,
      );
      await personal.reload();
      expect(personal.snapshot.tasks, isEmpty);
      await personal.importBackup(json);
      expect(personal.snapshot.tasks.single.title, 'Keep this private task');
      expect(personal.snapshot.workspaceKey, 'local');
      expect(await repo.database.rows('SELECT * FROM outbox'), isEmpty);
      expect(
        await repo.database.rows('SELECT * FROM personal_record_map'),
        isEmpty,
      );
      await personal.close();
    },
  );
  test(
    'late confirm after account switch cannot clear the new account; receipt cleanup stays scoped',
    () async {
      final alice = repo.state.session!;
      final scope = await repo.createScope('Alice space');
      final preview = await repo.previewAccountDeletion();
      server.paused = Completer<void>();
      server.entered = Completer<void>();
      final future = repo.confirmAccountDeletion(
        previewHash: preview['previewHash'] as String,
        password: 'pass',
        review: preview,
      );
      final assertion = expectLater(future, throwsA(code('session_changed')));
      await server.entered!.future;
      await repo.login(
        serverUrl: 'https://example.invalid',
        username: 'bob',
        password: 'login',
      );
      final bob = repo.state.session!;
      server.paused!.complete();
      await assertion;
      expect(repo.state.session!.accountId, bob.accountId);
      expect(sessions.value!.profile.accountId, bob.accountId);
      expect(
        await repo.database.rows('SELECT id FROM scopes WHERE partition=?', [
          alice.partition,
        ]),
        hasLength(1),
      );
      expect(await repo.checkAccountDeletion(receipts.requests.single), true);
      expect(repo.state.session!.accountId, bob.accountId);
      expect(sessions.value!.profile.accountId, bob.accountId);
      expect(
        await repo.database.rows(
          'SELECT id FROM scopes WHERE partition=? AND id=?',
          [alice.partition, scope],
        ),
        isEmpty,
      );
    },
  );
}
