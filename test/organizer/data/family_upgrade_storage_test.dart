import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/data/collaboration_transport.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'collaboration_repository_test.dart'
    show FakeServer, FakeTransport, MemorySessionStore;

/// Deliberately returns an entry before its account, then drops page two.
class PaginatedFinanceTransport extends FakeTransport {
  PaginatedFinanceTransport(super.server);
  final account = newSharedId(), entry = newSharedId();
  final membersCalls = <String>[];
  bool failSecondPage = false;
  bool populate = false;
  int policyRevision = 1;
  String grant = 'write';
  final grantsByScope = <String, String>{};
  final revisionsByScope = <String, int>{};
  Future<void> Function(String scope)? beforePolicy;
  bool denyInboxOpen = false;
  Completer<void>? auditEntered, auditRelease;
  final date = DateTime.utc(2026, 10, 4);
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
    if (operation == 'capabilities') {
      final caps = await super.call(serverUrl: serverUrl, operation: operation);
      return {
        ...caps,
        'recordContractVersions': [1, 2],
        'features': {
          'recordSync': true,
          'finance': true,
          'scopeAccessChanges': true,
        },
      };
    }
    if (operation == 'scopes.members') {
      final scope = params['scopeId'] as String;
      membersCalls.add(scope);
      return {
        'members': [
          for (final entry in server.members[scope]!.entries)
            {
              'userId': entry.key == 'alice' ? 1 : 2,
              'accountId': server.accountIds[entry.key],
              'username': entry.key,
              'displayName': entry.key,
              'role': entry.value,
              'active': true,
            },
        ],
      };
    }
    if (operation == 'scopes.removeMember') {
      server.members[params['scopeId']]!.remove(
        params['userId'] == 1 ? 'alice' : 'bob',
      );
      return {'removed': true};
    }
    if (operation == 'finance.policy') {
      final scope = params['scopeId'] as String;
      final snapshot = {
        'enabled': true,
        'grant': grantsByScope[scope] ?? grant,
        'revision': revisionsByScope[scope] ?? policyRevision,
      };
      await beforePolicy?.call(scope);
      return snapshot;
    }
    if (operation == 'inbox.open' && denyInboxOpen) {
      throw const CollaborationApiException('finance_forbidden');
    }
    if (operation == 'finance.audit') {
      auditEntered?.complete();
      await auditRelease?.future;
      return {'entries': []};
    }
    if (operation == 'finance.pull') {
      final cursor = params['cursor'] as int;
      if (!populate || cursor >= 2) {
        return {
          'records': [],
          'cursor': cursor,
          'hasMore': false,
          'accessRevision': policyRevision,
        };
      }
      if (cursor == 1 && failSecondPage) {
        throw const CollaborationException('network');
      }
      final record = cursor == 0
          ? SharedFinanceEntry(
              id: entry,
              accountId: account,
              kind: FinanceEntryKind.expense,
              amountMinor: 25,
              currency: 'EUR',
              title: 'Entry before account',
              occurredAt: date,
              createdAt: date,
              updatedAt: date,
            ).toPayload()
          : SharedFinanceAccount(
              id: account,
              name: 'Later parent',
              currency: 'EUR',
              openingBalanceMinor: 100,
              createdAt: date,
              updatedAt: date,
            ).toPayload();
      return {
        'records': [
          {
            'id': cursor == 0 ? entry : account,
            'type': cursor == 0 ? 'financeEntry' : 'financeAccount',
            'revision': 1,
            'sequence': cursor + 1,
            'deleted': false,
            'payload': record,
            'updatedAt': date.toIso8601String(),
          },
        ],
        'cursor': cursor + 1,
        'hasMore': cursor == 0,
        'accessRevision': policyRevision,
      };
    }
    return super.call(
      serverUrl: serverUrl,
      operation: operation == 'sync2.pull' ? 'sync.pull' : operation,
      params: params,
      token: token,
      allowLocalHttp: allowLocalHttp,
    );
  }
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  test(
    'schema one upgrade preserves exact queued bytes, revisions and cursors; new transaction rolls back',
    () async {
      final dir = await Directory.systemTemp.createTemp('shared-v1-migration-');
      final file = File('${dir.path}/cache.sqlite');
      final old = sqlite3.open(file.path);
      final request =
          '{ "opId" : "legacy-operation", "payload" : { "title" : "untouched" } }';
      // Independent fixture of the previous public SQL schema, not current migration output.
      for (final sql in [
        'CREATE TABLE accounts(partition TEXT PRIMARY KEY,profile TEXT NOT NULL)',
        'CREATE TABLE local_meta(name TEXT PRIMARY KEY,value TEXT NOT NULL)',
        'CREATE TABLE scopes(partition TEXT,id TEXT,data TEXT,cursor INTEGER DEFAULT 0,blocked INTEGER DEFAULT 0,PRIMARY KEY(partition,id))',
        'CREATE TABLE records(partition TEXT,scope_id TEXT,id TEXT,type TEXT,local_revision INTEGER,server_revision INTEGER,payload TEXT,deleted INTEGER,remote TEXT,PRIMARY KEY(partition,scope_id,id))',
        "CREATE TABLE outbox(sequence INTEGER PRIMARY KEY AUTOINCREMENT,op_id TEXT UNIQUE,partition TEXT,scope_id TEXT,record_id TEXT,request TEXT,state TEXT DEFAULT 'pending')",
        'CREATE INDEX outbox_partition ON outbox(partition,sequence)',
        'CREATE TABLE conflicts(id TEXT PRIMARY KEY,partition TEXT,scope_id TEXT,record_id TEXT,type TEXT,reason TEXT,remote TEXT)',
        'CREATE TABLE sync_leases(partition TEXT PRIMARY KEY,owner TEXT,expires_at INTEGER)',
        "INSERT INTO accounts VALUES('legacy','{}')",
        "INSERT INTO scopes VALUES('legacy','scope','{}',73,0)",
        "INSERT INTO records VALUES('legacy','scope','record','task',9,4,'{}',0,'{}')",
        'PRAGMA user_version=1',
      ]) {
        old.execute(sql);
      }
      old.execute(
        'INSERT INTO outbox(op_id,partition,scope_id,record_id,request) VALUES(?,?,?,?,?)',
        ['legacy-operation', 'legacy', 'scope', 'record', request],
      );
      old.close();
      final db = CollaborationDatabase(NativeDatabase(file));
      try {
        expect(
          (await db.rows('SELECT request,wire_version FROM outbox')).single,
          {'request': request, 'wire_version': 1},
        );
        expect(
          (await db.rows('SELECT cursor FROM scopes')).single['cursor'],
          73,
        );
        expect(
          (await db.rows(
            'SELECT local_revision,server_revision FROM records',
          )).single,
          {'local_revision': 9, 'server_revision': 4},
        );
        await expectLater(
          db.transaction(() async {
            await db.execute(
              "INSERT INTO commands(id,partition,operation,params,entity_key) VALUES('x','legacy','inbox.read','{}','inbox:1')",
            );
            await db.execute('INSERT INTO table_that_does_not_exist VALUES(1)');
          }),
          throwsA(anything),
        );
        expect(await db.rows('SELECT * FROM commands'), isEmpty);
        expect(
          (await db.rows('SELECT request FROM outbox')).single['request'],
          request,
        );
      } finally {
        await db.close();
        await dir.delete(recursive: true);
      }
    },
  );

  test(
    'finance paged backfill hides incomplete ledger and resumes durable cursor after restart',
    () async {
      final dir = await Directory.systemTemp.createTemp('finance-pages-');
      final file = File('${dir.path}/cache.sqlite');
      final transport = PaginatedFinanceTransport(FakeServer());
      final store = MemorySessionStore();
      var repo = CollaborationRepository(
        CollaborationDatabase(NativeDatabase(file)),
        transport,
        store,
      );
      try {
        await repo.initialize();
        await repo.login(
          serverUrl: 'https://example.test/',
          username: 'alice',
          password: 'synthetic',
        );
        final scope = await repo.createScope('Pages');
        transport.populate = true;
        transport.failSecondPage = true;
        await repo.syncNow();
        expect(
          repo.state.lastError,
          isA<CollaborationException>().having(
            (e) => e.code,
            'code',
            'network',
          ),
        );
        expect(repo.state.financeSnapshotComplete[scope], false);
        expect(repo.state.dataForScope(scope).financeEntries, isEmpty);
        expect(
          (await repo.database.rows(
            'SELECT finance_cursor FROM scopes',
          )).single['finance_cursor'],
          1,
        );
        await repo.close();
        transport.failSecondPage = false;
        repo = CollaborationRepository(
          CollaborationDatabase(NativeDatabase(file)),
          transport,
          store,
        );
        await repo.initialize();
        expect(repo.state.financeSupported, true);
        expect(repo.state.dataForScope(scope).financeEntries, isEmpty);
        await repo.syncNow();
        expect(repo.state.financeSnapshotComplete[scope], true);
        final data = repo.state.dataForScope(scope);
        expect(data.financeAccounts.single.id, transport.account);
        expect(data.financeEntries.single.id, transport.entry);
        expect(
          summarizeSharedFinance(
            accounts: data.financeAccounts,
            entries: data.financeEntries,
            transfers: data.financeTransfers,
          )['EUR']!.balanceMinor,
          BigInt.from(75),
        );
        final taskId = newSharedId();
        final taskPayload =
            LocalTask(
                id: taskId,
                title: 'Wire date',
                notes: '',
                projectId: null,
                dueAt: null,
                isCompleted: false,
                createdAt: transport.date,
                updatedAt: transport.date,
              ).toJson()
              ..remove('id')
              ..remove('revision')
              ..remove('createdByAccountId')
              ..remove('updatedByAccountId');
        taskPayload['createdAt'] = '2026-10-04T00:00:00Z';
        await repo.database.execute(
          'INSERT INTO records(partition,scope_id,id,type,local_revision,server_revision,payload,deleted) VALUES(?,?,?,?,?,?,?,?)',
          [
            repo.state.session!.partition,
            scope,
            taskId,
            'task',
            1,
            1,
            jsonEncode(taskPayload),
            0,
          ],
        );
        await repo.refreshLocal();
        await repo.updateTask(
          scope,
          repo.state
              .dataForScope(scope)
              .tasks
              .single
              .copyWith(title: 'Edited wire task'),
        );
        final taskQueued =
            jsonDecode(
                  (await repo.database.rows(
                        'SELECT request FROM outbox',
                      )).single['request']
                      as String,
                )
                as Map;
        expect(taskQueued['payload']['createdAt'], '2026-10-04T00:00:00Z');
        // Models normalize no-fraction UTC timestamps, but immutable creation
        // timestamps remain wire-equivalent when the user edits their title.
        final raw = data.financeAccounts.single.toPayload();
        raw['createdAt'] = '2026-10-04T00:00:00Z';
        await repo.database.execute(
          'UPDATE finance_records SET payload=? WHERE id=?',
          [jsonEncode(raw), transport.account],
        );
        await repo.refreshLocal();
        await repo.updateFinanceAccount(
          scope,
          repo.state
              .dataForScope(scope)
              .financeAccounts
              .single
              .copyWith(name: 'Edited'),
        );
        final queued =
            jsonDecode(
                  (await repo.database.rows(
                        'SELECT request FROM finance_outbox',
                      )).single['request']
                      as String,
                )
                as Map;
        expect(queued['payload']['createdAt'], '2026-10-04T00:00:00Z');
      } finally {
        await repo.close();
        await dir.delete(recursive: true);
      }
    },
  );
  Future<
    ({
      CollaborationRepository repo,
      PaginatedFinanceTransport transport,
      String scope,
    })
  >
  fixture() async {
    final transport = PaginatedFinanceTransport(FakeServer());
    final repo = CollaborationRepository(
      CollaborationDatabase(NativeDatabase.memory()),
      transport,
      MemorySessionStore(),
    );
    await repo.initialize();
    await repo.login(
      serverUrl: 'https://example.test/',
      username: 'alice',
      password: 'synthetic',
    );
    final scope = await repo.createScope('Policy races');
    await repo.syncNow();
    return (repo: repo, transport: transport, scope: scope);
  }

  test(
    'known read-to-read access epoch hides stale ledger even if reconnect fails; pending intent stays unblocked',
    () async {
      final f = await fixture();
      try {
        f.transport.populate = true;
        await f.repo.syncNow();
        expect(f.repo.state.dataForScope(f.scope).financeAccounts.length, 1);
        await f.repo.createFinanceEntry(
          scopeId: f.scope,
          accountId: f.transport.account,
          kind: FinanceEntryKind.expense,
          amountMinor: 3,
          currency: 'EUR',
          title: 'Authorized pending',
          occurredAt: f.transport.date,
        );
        f.transport.policyRevision = 2;
        await f.repo.refreshFinancePolicy(f.scope);
        expect(f.repo.state.financeSnapshotComplete[f.scope], false);
        expect(f.repo.state.dataForScope(f.scope).financeAccounts, isEmpty);
        expect(
          (await f.repo.database.rows(
            'SELECT finance_cursor FROM scopes',
          )).single['finance_cursor'],
          0,
        );
        expect(
          (await f.repo.database.rows(
            'SELECT state FROM finance_outbox',
          )).single['state'],
          'pending',
        );
        f.transport.offline = true;
        await f.repo.syncNow();
        expect(f.repo.state.dataForScope(f.scope).financeEntries, isEmpty);
        expect(f.repo.state.financeBlockedCount, 0);
      } finally {
        await f.repo.close();
      }
    },
  );

  test(
    'delayed audit cannot return financial history after known same-account revocation',
    () async {
      final f = await fixture();
      try {
        f.transport.auditEntered = Completer<void>();
        f.transport.auditRelease = Completer<void>();
        final pending = f.repo.financeAudit(
          scopeId: f.scope,
          recordId: newSharedId(),
        );
        final assertion = expectLater(
          pending,
          throwsA(
            isA<CollaborationException>().having(
              (e) => e.code,
              'code',
              'finance_forbidden',
            ),
          ),
        );
        await f.transport.auditEntered!.future;
        f.transport.grant = 'none';
        f.transport.policyRevision = 2;
        await f.repo.refreshFinancePolicy(f.scope);
        f.transport.auditRelease!.complete();
        await assertion;
      } finally {
        await f.repo.close();
      }
    },
  );

  test(
    'recovery export rechecks scope A rights after delayed scope B policy request',
    () async {
      final f = await fixture();
      try {
        final secondScope = await f.repo.createScope('Second scope');
        await f.repo.syncNow();
        final accountA = await f.repo.createFinanceAccount(
          scopeId: f.scope,
          name: 'Hidden A draft',
          currency: 'EUR',
        );
        await f.repo.createFinanceAccount(
          scopeId: secondScope,
          name: 'Visible B draft',
          currency: 'EUR',
        );
        final plannedEntry = await f.repo.createFinanceEntry(
          scopeId: f.scope,
          accountId: accountA,
          kind: FinanceEntryKind.expense,
          status: SharedFinanceStatus.planned,
          amountMinor: 10,
          currency: 'EUR',
          title: 'Private planned draft',
          occurredAt: f.transport.date,
        );
        await f.repo.putReminder(
          scopeId: f.scope,
          targetType: 'financeEntry',
          targetId: plannedEntry,
          remindAt: DateTime.utc(2099),
        );
        final entered = Completer<void>(), release = Completer<void>();
        f.transport.beforePolicy = (scope) async {
          if (scope == secondScope) {
            entered.complete();
            await release.future;
          }
        };
        final pending = f.repo.exportUnsentWork();
        await entered.future;
        f.transport.grantsByScope[f.scope] = 'none';
        f.transport.revisionsByScope[f.scope] = 2;
        await f.repo.refreshFinancePolicy(f.scope);
        release.complete();
        final exported = await pending;
        expect(exported, isNot(contains('Hidden A draft')));
        expect(exported, contains('Visible B draft'));
        expect((jsonDecode(exported) as Map)['commands'], isEmpty);
        expect(
          (await f.repo.database.rows(
            'SELECT state FROM commands',
          )).single['state'],
          'blocked',
        );
        expect(
          (await f.repo.database.rows(
            'SELECT COUNT(*) AS n FROM finance_outbox',
          )).single['n'],
          3,
        );
      } finally {
        await f.repo.close();
      }
    },
  );

  test(
    'successful policy reply begun before explicit denial cannot re-enable the grant',
    () async {
      final f = await fixture();
      try {
        f.transport.policyRevision = 5;
        await f.repo.refreshFinancePolicy(f.scope);
        final entered = Completer<void>(), release = Completer<void>();
        var first = true;
        f.transport.beforePolicy = (_) async {
          if (first) {
            first = false;
            entered.complete();
            await release.future;
          }
        };
        final pending = f.repo.refreshFinancePolicy(f.scope);
        await entered.future;
        f.transport.denyInboxOpen = true;
        final session = f.repo.state.session!;
        final target = NotificationTarget(
          serverUrl: session.serverUrl,
          serverId: session.serverId,
          accountId: session.accountId,
          scopeId: f.scope,
          records: [
            NotificationRecordTarget(
              type: 'financeEntry',
              recordId: newSharedId(),
            ),
          ],
          inboxIds: [1],
        );
        expect(
          (await f.repo.openNotificationTarget(target)).status,
          NotificationOpenStatus.permissionDenied,
        );
        release.complete();
        expect((await pending).canRead, false);
        expect(f.repo.state.financePolicyForScope(f.scope).canRead, false);
        expect(f.repo.state.financePolicyForScope(f.scope).revision, 5);
      } finally {
        await f.repo.close();
      }
    },
  );
  test(
    'membership directory is bounded to one fetch per minute, explicit refresh/actions bypass it and ACL stays immediate',
    () async {
      var clock = DateTime.utc(2026, 10, 4);
      final server = FakeServer();
      // Use one server for both transport records and membership policy.
      final activeTransport = PaginatedFinanceTransport(server);
      final repo = CollaborationRepository(
        CollaborationDatabase(NativeDatabase.memory()),
        activeTransport,
        MemorySessionStore(),
        clock: () => clock,
      );
      try {
        await repo.initialize();
        await repo.login(
          serverUrl: 'https://example.test/',
          username: 'alice',
          password: 'synthetic',
        );
        final scope = await repo.createScope('Directory cache');
        await repo.syncNow();
        expect(
          activeTransport.membersCalls.where((id) => id == scope).length,
          1,
        );
        server.members[scope]!['bob'] = 'member';
        for (var n = 0; n < 4; n++) {
          clock = clock.add(const Duration(seconds: 12));
          await repo.syncNow();
        }
        expect(
          activeTransport.membersCalls.where((id) => id == scope).length,
          1,
        );
        expect(repo.state.membersForScope(scope).length, 1);
        expect((await repo.members(scope)).length, 2);
        expect(
          activeTransport.membersCalls.where((id) => id == scope).length,
          2,
        );
        await repo.revokeMember(scopeId: scope, userId: 2);
        expect(repo.state.membersForScope(scope).length, 1);
        expect(
          activeTransport.membersCalls.where((id) => id == scope).length,
          3,
        );
        clock = clock.add(const Duration(seconds: 60));
        await repo.syncNow();
        expect(
          activeTransport.membersCalls.where((id) => id == scope).length,
          4,
        );
        final newScope = await repo.createScope('New scope immediately loads');
        await repo.syncNow();
        expect(
          activeTransport.membersCalls.where((id) => id == newScope).length,
          1,
        );
        server.confirmRevocation(scope, 'alice');
        clock = clock.add(const Duration(seconds: 12));
        await repo.syncNow();
        expect(
          repo.state.scopes.singleWhere((s) => s.id == scope).revoked,
          true,
        );
        expect(repo.state.membersForScope(scope), isEmpty);
        expect(
          activeTransport.membersCalls.where((id) => id == scope).length,
          4,
        );
        server.members[newScope]!['bob'] = 'member';
        await repo.signOut();
        await repo.login(
          serverUrl: 'https://example.test/',
          username: 'bob',
          password: 'synthetic',
        );
        expect(
          activeTransport.membersCalls.where((id) => id == newScope).length,
          2,
        );
        expect(repo.state.membersForScope(newScope).length, 2);
      } finally {
        await repo.close();
      }
    },
  );
}
