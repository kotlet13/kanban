import 'dart:async';
import 'dart:convert';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'package:kanban/organizer/domain/local_space_models.dart';
import 'package:kanban/organizer/domain/shared_finance_validation.dart';
import 'package:kanban/organizer/data/local_spaces_repository.dart';
import 'package:kanban/organizer/data/organizer_repository.dart';
import 'package:kanban/organizer/data/sqlite_organizer_storage.dart';
import 'package:kanban/organizer/data/portable_backup_repository.dart';
import 'local_space_publication_test.dart' show PublicationTransport;
import 'collaboration_repository_test.dart'
    show FakeServer, FakeTransport, MemorySessionStore, code;

final now = DateTime.utc(2026, 10, 17);
SharedFinanceEntry entry(
  String id,
  String account, {
  String? parent,
  String? project,
}) => SharedFinanceEntry(
  id: id,
  createdAt: now,
  updatedAt: now,
  accountId: account,
  accountScopeId: parent,
  projectId: project,
  kind: FinanceEntryKind.expense,
  amountMinor: 30000,
  currency: 'EUR',
  title: 'Project materials',
  occurredAt: now,
);

class OrganizationFinanceTransport extends FakeTransport {
  OrganizationFinanceTransport(super.server);
  final parent = newSharedId(),
      project = newSharedId(),
      account = newSharedId();
  bool supported = true, loseReply = false, archivedChoice = false;
  int revision = 1, sequence = 1, accountSequence = 5;
  String grant = 'write';
  bool organizationComplete = true;
  final requiredSequences = <String, int>{};
  Future<void> Function()? beforeChoices;
  final records = <String, Map<String, dynamic>>{};
  final recordScopes = <String, String>{};
  final replays = <String, Map<String, dynamic>>{};
  final pushes = <Map<String, Object?>>[];
  final compoundCalls = <Map<String, Object?>>[];
  void seed({bool parentAccess = false}) {
    server.scopes[project] = {
      'id': project,
      'name': 'Only allowed project',
      'kind': 'project',
      'sequence': 1,
      'parentScopeId': parent,
      'parentScopeKind': 'organization',
      'accessPolicyVersion': 3,
    };
    server.members[project] = {'alice': 'member'};
    final root =
        LocalProject(
            id: project,
            title: 'Only allowed project',
            description: '',
            createdAt: now,
            updatedAt: now,
          ).toJson()
          ..remove('id')
          ..remove('revision')
          ..remove('createdByAccountId')
          ..remove('updatedByAccountId');
    server.records[project] = {
      project: {
        'id': project,
        'type': 'project',
        'revision': 1,
        'deleted': false,
        'payload': root,
        'sequence': 1,
        'updatedAt': now.toIso8601String(),
      },
    };
    server.sequence[project] = 1;
    if (parentAccess) {
      server.scopes[parent] = {
        'id': parent,
        'name': 'Organization',
        'kind': 'organization',
        'sequence': 1,
        'accessPolicyVersion': 3,
      };
      server.members[parent] = {'alice': 'owner'};
      server.records[parent] = {};
      server.sequence[parent] = 0;
    }
  }

  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
    if (offline) throw const CollaborationException('network');
    if (operation == 'capabilities') {
      final old = await super.call(serverUrl: serverUrl, operation: operation);
      return {
        ...old,
        'recordContractVersions': [1, 2, 3],
        'financeContractVersions': supported ? [1, 2, 3] : [1, 2],
        if (supported) 'organizationFinanceContractVersions': [1],
        'features': {
          ...Map<String, dynamic>.from(old['features'] as Map),
          'finance': true,
          'organizationFinance': supported,
        },
      };
    }
    if (operation == 'scopes.members') return {'members': []};
    if (operation.endsWith('.policy') && operation.startsWith('finance')) {
      return {
        'enabled': true,
        'grant': grant,
        'revision': revision,
        'requiredContractVersion': records.isEmpty ? 1 : 3,
        'organizationFinanceComplete': organizationComplete,
        'organizationFinanceScopeIds': params['scopeId'] == parent
            ? requiredSequences.keys.toList()
            : <String>[],
        'organizationFinanceSequences': params['scopeId'] == parent
            ? Map<String, int>.of(requiredSequences)
            : <String, int>{},
      };
    }
    if (operation == 'finance4.accountChoices') {
      final reply = {
        'accounts': [
          {
            'scopeId': parent,
            'id': account,
            'name': 'Parent ledger',
            'currency': 'EUR',
            'archived': archivedChoice,
          },
        ],
        'accountScopeId': parent,
        'accountSequence': accountSequence,
        'accessRevision': revision,
      };
      await beforeChoices?.call();
      return reply;
    }
    if (operation.endsWith('.pull') && operation.startsWith('finance')) {
      final cursor = params['cursor'] as int;
      return {
        'records': cursor < sequence
            ? records.entries
                  .where((e) => recordScopes[e.key] == params['scopeId'])
                  .map((e) => e.value)
                  .toList()
            : [],
        'cursor': sequence,
        'hasMore': false,
        'accessRevision': revision,
        'organizationFinanceComplete': organizationComplete,
        'organizationFinanceScopeIds': params['scopeId'] == parent
            ? requiredSequences.keys.toList()
            : <String>[],
        'organizationFinanceSequences': params['scopeId'] == parent
            ? Map<String, int>.of(requiredSequences)
            : <String, int>{},
      };
    }
    if (operation == 'sync3.pushTaskWithCost') {
      compoundCalls.add(Map.of(params));
      final lose = loseReply;
      loseReply = false;
      final ordinary = await super.call(
        serverUrl: serverUrl,
        operation: 'sync.push',
        params: {
          'scopeId': params['scopeId'],
          'operation': params['operation'],
        },
        token: token,
      );
      final financial = await call(
        serverUrl: serverUrl,
        operation: 'finance4.push',
        params: {
          'scopeId': params['scopeId'],
          'operation': params['financeOperation'],
          'operationContractVersion': params['financeOperationContractVersion'],
        },
        token: token,
      );
      if (lose) throw const CollaborationException('network');
      return {...ordinary, 'finance': financial};
    }
    if (operation == 'finance4.push') {
      pushes.add(Map.of(params));
      final request = Map<String, dynamic>.from(params['operation'] as Map);
      final opId = request['opId'] as String;
      if (replays.containsKey(opId)) return replays[opId]!;
      final id = request['recordId'] as String;
      final canonical = <String, dynamic>{
        'id': id,
        'type': request['type'],
        'revision': (request['expectedRevision'] as int) + 1,
        'deleted': request['deleted'],
        'payload': request['payload'],
        'contractVersion': 3,
        'sequence': sequence + 1,
        'updatedAt': now.toIso8601String(),
      };
      records[id] = canonical;
      recordScopes[id] = params['scopeId'] as String;
      sequence++;
      final reply = {'status': 'applied', 'record': canonical};
      replays[opId] = reply;
      if (loseReply) {
        loseReply = false;
        throw const CollaborationException('network');
      }
      return reply;
    }
    return super.call(
      serverUrl: serverUrl,
      operation: operation.startsWith('sync3.')
          ? operation.replaceFirst('sync3.', 'sync.')
          : operation,
      params: params,
      token: token,
      allowLocalHttp: allowLocalHttp,
    );
  }
}

class OrganizationPublicationTransport extends PublicationTransport {
  OrganizationPublicationTransport(super.server) {
    scoped = true;
  }
  bool loseEntryReply = true;
  final financePushes = <({String scope, String body})>[];
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
        'financeContractVersions': [1, 2, 3],
        'organizationFinanceContractVersions': [1],
        'features': <String, dynamic>{
          ...caps['features'] as Map<String, dynamic>,
          'organizationFinance': true,
        },
      };
    }
    if (operation == 'finance4.accountChoices') {
      final child = server.scopes[params['scopeId']]!;
      final parent = child['parentScopeId'] ?? child['organizationId'];
      return {
        'accountScopeId': parent,
        'accountSequence': finances.sequence[parent] ?? 0,
        'accessRevision': 1,
        'accounts': [
          for (final row
              in finances.records[parent]?.values ?? <Map<String, dynamic>>[])
            if (row['type'] == 'financeAccount' && row['deleted'] == false)
              {
                'scopeId': parent,
                'id': row['id'],
                'name': (row['payload'] as Map)['name'],
                'currency': (row['payload'] as Map)['currency'],
                'archived': (row['payload'] as Map)['archived'] ?? false,
              },
        ],
      };
    }
    final finance = operation.startsWith('finance4.');
    if (operation == 'finance4.push') {
      financePushes.add((
        scope: params['scopeId'] as String,
        body: jsonEncode(params['operation']),
      ));
    }
    final reply = await super.call(
      serverUrl: serverUrl,
      operation: finance
          ? operation.replaceFirst('finance4.', 'finance2.')
          : operation,
      params: params,
      token: token,
      allowLocalHttp: allowLocalHttp,
    );
    if (finance) {
      for (final record in [
        if (reply['record'] != null) reply['record'],
        ...?reply['records'] as List?,
      ]) {
        (record as Map)['contractVersion'] = 3;
      }
      reply['organizationFinanceComplete'] = true;
      reply['organizationFinanceScopeIds'] = <String>[];
      if (operation == 'finance4.push' &&
          loseEntryReply &&
          ((params['operation'] as Map)['payload']
                  as Map?)?['accountScopeId'] !=
              null) {
        loseEntryReply = false;
        throw const CollaborationException('network');
      }
    }
    return reply;
  }
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  Future<
    ({
      CollaborationDatabase db,
      CollaborationRepository repo,
      OrganizationFinanceTransport transport,
      MemorySessionStore store,
    })
  >
  setup({bool supported = true, bool parentAccess = false}) async {
    final server = FakeServer();
    final transport = OrganizationFinanceTransport(server)
      ..supported = supported;
    transport.seed(parentAccess: parentAccess);
    final db = CollaborationDatabase(NativeDatabase.memory());
    final store = MemorySessionStore();
    final repo = CollaborationRepository(
      db,
      transport,
      store,
      ownsDatabase: false,
    );
    await repo.initialize();
    addTearDown(() async {
      await repo.close();
      await db.close();
    });
    await repo.login(
      serverUrl: 'https://example.test/',
      username: 'alice',
      password: 'fixture',
    );
    return (db: db, repo: repo, transport: transport, store: store);
  }

  test(
    'v3 exact parent and inline links round trip, old wire fails closed',
    () {
      final record = entry(newSharedId(), newSharedId(), parent: newSharedId());
      final payload = record.toPayload(contractVersion: 3);
      validateSharedFinancePayload(
        SharedFinanceRecordType.financeEntry,
        Map<String, dynamic>.from(payload),
        contractVersion: 3,
      );
      expect(
        SharedFinanceEntry.fromJson(record.toJson().cast()).accountScopeId,
        record.accountScopeId,
      );
      expect(record.copyWith(accountScopeId: null).accountScopeId, isNull);
      for (final version in [1, 2]) {
        expect(
          () => record.toPayload(contractVersion: version),
          throwsFormatException,
        );
        expect(
          () => validateSharedFinancePayload(
            SharedFinanceRecordType.financeEntry,
            Map<String, dynamic>.from(payload),
            contractVersion: version,
          ),
          throwsA(code('validation_error')),
        );
      }
      final inline = record.copyWith(
        accountScopeId: null,
        projectId: newSharedId(),
      );
      expect(
        SharedFinanceEntry.fromJson(inline.toJson().cast()).projectId,
        inline.projectId,
      );
      expect(() => inline.toPayload(contractVersion: 2), throwsFormatException);
      final legacy = record.copyWith(accountScopeId: null);
      expect(
        legacy.toPayload(contractVersion: 2).keys,
        isNot(contains('accountScopeId')),
      );
    },
  );

  test(
    'project-only read uses sanitized choices and no parent ledger/membership',
    () async {
      final f = await setup();
      expect(f.repo.state.organizationFinanceSupported, isTrue);
      expect(f.repo.state.financeContractVersion, 3);
      expect(f.repo.state.scopes.map((s) => s.id), [f.transport.project]);
      final choice =
          f.repo.state.financeAccountChoices[f.transport.project]!.single;
      expect(choice.scopeId, f.transport.parent);
      expect(choice.toJson().keys.toSet(), {
        'scopeId',
        'id',
        'name',
        'currency',
        'archived',
      });
      expect(f.repo.state.data.containsKey(f.transport.parent), isFalse);
      expect(
        () => SharedFinanceAccountChoice.fromJson({
          ...choice.toJson(),
          'openingBalanceMinor': 500000,
        }),
        throwsFormatException,
      );
      final cached = await f.db.rows(
        'SELECT value FROM local_meta WHERE name=?',
        [
          'finance_account_choices:${f.repo.state.session!.partition}:${f.transport.project}',
        ],
      );
      expect(cached, hasLength(1));
      expect(
        cached.single['value'].toString(),
        isNot(contains('openingBalance')),
      );
    },
  );

  test(
    'canonical project entry queues exact parent, retries lost reply once and reloads',
    () async {
      final f = await setup();
      final p = f.transport.project;
      final id = await f.repo.createFinanceEntry(
        scopeId: p,
        accountId: f.transport.account,
        accountScopeId: f.transport.parent,
        kind: FinanceEntryKind.expense,
        amountMinor: 30000,
        currency: 'EUR',
        title: 'Materials',
        occurredAt: now,
      );
      expect(f.repo.state.dataForScope(p).financeEntries.single.id, id);
      expect(f.repo.state.dataForScope(p).financeAccounts, isEmpty);
      final pending = await f.db.rows(
        'SELECT request,wire_version FROM finance_outbox',
      );
      expect(pending.single['wire_version'], 3);
      expect(
        (jsonDecode(pending.single['request'] as String)
            as Map)['payload']['accountScopeId'],
        f.transport.parent,
      );
      f.transport.loseReply = true;
      await f.repo.syncNow();
      expect(f.repo.state.financePendingCount, 1);
      await f.repo.syncNow();
      expect(f.repo.state.financePendingCount, 0);
      expect(f.transport.records, hasLength(1));
      expect(f.transport.pushes.last['operationContractVersion'], 3);
      expect(f.transport.pushes.last['linkedPaymentsAware'], isNull);
      await f.repo.refreshLocal();
      final saved = f.repo.state.dataForScope(p).financeEntries.single;
      expect(saved.accountScopeId, f.transport.parent);
      expect(saved.id, id);
    },
  );

  test(
    'parent exactness, archived choice, currency and project account creation are guarded',
    () async {
      final f = await setup();
      Future<String> create({String? parent, String currency = 'EUR'}) =>
          f.repo.createFinanceEntry(
            scopeId: f.transport.project,
            accountId: f.transport.account,
            accountScopeId: parent,
            kind: FinanceEntryKind.expense,
            amountMinor: 1,
            currency: currency,
            title: 'Guarded',
            occurredAt: now,
          );
      await expectLater(
        create(parent: newSharedId()),
        throwsA(code('finance_account_missing')),
      );
      await expectLater(
        create(parent: f.transport.parent, currency: 'USD'),
        throwsA(code('finance_account_missing')),
      );
      await expectLater(create(), throwsA(code('finance_account_missing')));
      await expectLater(
        f.repo.createFinanceAccount(
          scopeId: f.transport.project,
          name: 'Fake project ledger',
          currency: 'EUR',
        ),
        throwsA(code('finance_account_parent_required')),
      );
      f.transport.archivedChoice = true;
      f.transport.accountSequence++;
      await f.repo.refreshFinanceAccountChoices(f.transport.project);
      await expectLater(
        create(parent: f.transport.parent),
        throwsA(code('finance_account_missing')),
      );
      expect(f.repo.state.financePendingCount, 0);
    },
  );

  test(
    'old server cannot create new links or load safe parent choices',
    () async {
      final f = await setup(supported: false);
      expect(f.repo.state.organizationFinanceSupported, isFalse);
      await expectLater(
        f.repo.refreshFinanceAccountChoices(f.transport.project),
        throwsA(code('unsupported_version')),
      );
      await expectLater(
        f.repo.createFinanceEntry(
          scopeId: f.transport.project,
          accountId: f.transport.account,
          accountScopeId: f.transport.parent,
          kind: FinanceEntryKind.expense,
          amountMinor: 1,
          currency: 'EUR',
          title: 'Unsupported',
          occurredAt: now,
        ),
        throwsFormatException,
      );
      expect(f.repo.state.financePendingCount, 0);
    },
  );

  test(
    'late selector reply cannot restore choices after finance denial',
    () async {
      final f = await setup();
      final entered = Completer<void>(), release = Completer<void>();
      f.transport.beforeChoices = () async {
        entered.complete();
        await release.future;
      };
      final old = f.repo.refreshFinanceAccountChoices(f.transport.project);
      await entered.future;
      f.transport.grant = 'none';
      f.transport.revision++;
      f.transport.beforeChoices = null;
      await expectLater(
        f.repo.refreshFinanceAccountChoices(f.transport.project),
        throwsA(code('finance_forbidden')),
      );
      release.complete();
      await old;
      expect(f.repo.state.financeAccountChoices[f.transport.project], isEmpty);
      expect(
        await f.db.rows('SELECT value FROM local_meta WHERE name LIKE ?', [
          'finance_account_choices:%',
        ]),
        isEmpty,
      );
    },
  );
  test(
    'task and parent-account cost use one v3 compound operation through lost reply',
    () async {
      final f = await setup();
      final task = LocalTask(
        id: newSharedId(),
        title: 'Buy materials',
        notes: '',
        projectId: f.transport.project,
        dueAt: now.add(const Duration(days: 2)),
        isCompleted: false,
        createdAt: now,
        updatedAt: now,
      );
      await f.repo.saveTaskWithCost(
        f.transport.project,
        task,
        isNew: true,
        cost: TaskCostDraft(
          amountMinor: 5000,
          ledgerAccountId: f.transport.account,
          accountScopeId: f.transport.parent,
        ),
      );
      final draft = f.repo.state
          .dataForScope(f.transport.project)
          .financeEntries
          .single;
      expect(draft.accountScopeId, f.transport.parent);
      final queued = await f.db.rows(
        'SELECT request,wire_version FROM finance_outbox',
      );
      expect(queued.single['wire_version'], 3);
      final originalRequest = queued.single['request'];
      f.transport.loseReply = true;
      await f.repo.syncNow();
      expect(f.repo.state.financePendingCount, 1);
      expect(
        (await f.db.rows(
          'SELECT request FROM finance_outbox',
        )).single['request'],
        originalRequest,
      );
      await f.repo.syncNow();
      expect(f.repo.state.financePendingCount, 0);
      expect(f.repo.state.conflicts, isEmpty);
      expect(
        f.transport.compoundCalls.last['financeOperationContractVersion'],
        3,
      );
      expect(f.transport.records, hasLength(1));
      final savedTask = f.repo.state
          .dataForScope(f.transport.project)
          .tasks
          .single;
      final savedCost = f.repo.state
          .dataForScope(f.transport.project)
          .financeEntries
          .single;
      await f.repo.saveTaskWithCost(
        f.transport.project,
        savedTask.copyWith(title: 'Revised title'),
        cost: TaskCostDraft(
          amountMinor: 6000,
          ledgerAccountId: f.transport.account,
        ),
        expectedFinanceRevision: savedCost.revision,
      );
      expect(
        f.repo.state
            .dataForScope(f.transport.project)
            .financeEntries
            .single
            .accountScopeId,
        f.transport.parent,
      );
    },
  );
  test(
    'local organization publication keeps one parent account and exact retrying child expense',
    () async {
      final db = CollaborationDatabase(NativeDatabase.memory());
      final storage = SqliteOrganizerStorage(db);
      await storage.initialize();
      final local = OrganizerRepository(storage, clock: () => now);
      await local.initialize();
      final spaces = LocalSpacesRepository(db);
      final transport = OrganizationPublicationTransport(FakeServer());
      final shared = CollaborationRepository(
        db,
        transport,
        MemorySessionStore(),
        ownsDatabase: false,
      );
      await shared.initialize();
      addTearDown(() async {
        await local.close();
        await shared.close();
        await db.close();
      });
      await shared.login(
        serverUrl: 'https://example.test/',
        username: 'alice',
        password: 'fixture',
      );
      final org = await spaces.createSpace(
        kind: LocalSpaceKind.organization,
        name: 'Organization',
      );
      await spaces.selectSpace(org.id);
      await local.reload();
      await local.createProject(title: 'Event');
      final project = local.snapshot.projects.single;
      final account = LocalFinanceAccount(
        id: newSharedId(),
        name: 'Main ledger',
        currency: 'EUR',
        openingBalanceMinor: 100000,
        createdAt: now,
        updatedAt: now,
      );
      await local.saveFinancePlan(
        accounts: [account],
        rules: [],
        expectedRevision: local.snapshot.revision,
        expectedWorkspaceKey: org.id,
      );
      await local.createFinanceEntry(
        title: 'General',
        amountMinor: 5000,
        kind: FinanceEntryKind.expense,
        occurredAt: now,
        ledgerAccountId: account.id,
      );
      await local.createFinanceEntry(
        title: 'Project',
        amountMinor: 30000,
        kind: FinanceEntryKind.expense,
        occurredAt: now,
        ledgerAccountId: account.id,
        projectId: project.id,
      );
      await shared.publishLocalSpaces(
        await shared.previewLocalSpacesPublication([org.id]),
      );
      expect(shared.state.financePendingCount, 1);
      final queued = (await db.rows(
        'SELECT request FROM finance_outbox',
      )).single['request'];
      await shared.syncNow();
      expect(shared.state.lastError, isNull);
      expect(shared.state.financePendingCount, 0);
      final parent = shared.state.dataForScope(org.id),
          child = shared.state.dataForScope(project.id);
      expect(parent.financeAccounts.single.id, account.id);
      expect(parent.financeAccounts.single.openingBalanceMinor, 100000);
      expect(child.financeAccounts, isEmpty);
      expect(parent.financeEntries.single.amountMinor, 5000);
      expect(child.financeEntries.single.amountMinor, 30000);
      expect(child.financeEntries.single.accountScopeId, org.id);
      expect(child.financeEntries.single.accountId, account.id);
      final childWrites = transport.financePushes
          .where((p) => p.scope == project.id)
          .toList();
      expect(childWrites, hasLength(2));
      expect(childWrites.first.body, queued);
      expect(childWrites.last.body, childWrites.first.body);
      final accountPush = transport.financePushes.indexWhere(
        (p) => (jsonDecode(p.body) as Map)['type'] == 'financeAccount',
      );
      final expensePush = transport.financePushes.indexWhere(
        (p) => p.scope == project.id,
      );
      expect(accountPush, lessThan(expensePush));
    },
  );
  test(
    'safe choices reopen offline and a late old account list cannot unarchive a choice',
    () async {
      final f = await setup();
      final reopened = CollaborationRepository(
        f.db,
        f.transport,
        f.store,
        ownsDatabase: false,
      );
      addTearDown(reopened.close);
      f.transport.offline = true;
      await reopened.initialize();
      expect(
        reopened.state.financeAccountChoices[f.transport.project]!.single.id,
        f.transport.account,
      );
      expect(reopened.state.data.containsKey(f.transport.parent), isFalse);
      f.transport.offline = false;
      final entered = Completer<void>(), release = Completer<void>();
      f.transport.beforeChoices = () async {
        entered.complete();
        await release.future;
      };
      final old = f.repo.refreshFinanceAccountChoices(f.transport.project);
      await entered.future;
      f.transport.beforeChoices = null;
      f.transport.archivedChoice = true;
      f.transport.accountSequence++;
      await f.repo.refreshFinanceAccountChoices(f.transport.project);
      expect(
        f
            .repo
            .state
            .financeAccountChoices[f.transport.project]!
            .single
            .archived,
        isTrue,
      );
      release.complete();
      await old;
      expect(
        f
            .repo
            .state
            .financeAccountChoices[f.transport.project]!
            .single
            .archived,
        isTrue,
      );
    },
  );

  test(
    'encrypted v3 backup excludes choices and resume refuses server downgrade before mutation',
    () async {
      final f = await setup();
      await f.repo.createFinanceEntry(
        scopeId: f.transport.project,
        accountId: f.transport.account,
        accountScopeId: f.transport.parent,
        kind: FinanceEntryKind.expense,
        amountMinor: 30000,
        currency: 'EUR',
        title: 'Queued project backup',
        occurredAt: now,
      );
      final backup = PortableBackupRepository(
        f.db,
        SqliteOrganizerStorage(f.db),
        MemoryBackupUiPreferencesStore(),
        collaboration: () => f.repo,
      );
      const password = 'synthetic encrypted backup';
      final bytes = await backup.exportEncryptedBackup(password);
      final doc = await backup.crypto.decrypt(bytes, password);
      expect(doc['version'], 8);
      expect(jsonEncode(doc), isNot(contains('finance_account_choices:')));
      final queue = await f.db.rows('SELECT request FROM finance_outbox');
      f.transport.supported = false;
      await expectLater(
        f.repo.resumePortableBackup(doc),
        throwsA(code('unsupported_version')),
      );
      expect(await f.db.rows('SELECT request FROM finance_outbox'), queue);
      expect(f.transport.records, isEmpty);
      f.transport.supported = true;
      var choicesFetched = 0;
      f.transport.beforeChoices = () async {
        choicesFetched++;
      };
      await f.repo.resumePortableBackup(doc);
      expect(choicesFetched, greaterThanOrEqualTo(1));
      expect(f.transport.records, hasLength(1));
      expect(f.repo.state.financePendingCount, 0);
      expect(
        f.repo.state
            .dataForScope(f.transport.project)
            .financeEntries
            .single
            .accountScopeId,
        f.transport.parent,
      );
    },
  );
  test(
    'general sync pushes offline parent account before child entry even with child-first scope list',
    () async {
      final f = await setup(parentAccess: true);
      // Fake scopes.list deliberately preserves insertion order: child then parent.
      expect(f.transport.server.scopes.keys.first, f.transport.project);
      final accountId = await f.repo.createFinanceAccount(
        scopeId: f.transport.parent,
        name: 'New offline parent account',
        currency: 'EUR',
      );
      await f.repo.createFinanceEntry(
        scopeId: f.transport.project,
        accountId: accountId,
        accountScopeId: f.transport.parent,
        kind: FinanceEntryKind.expense,
        amountMinor: 30000,
        currency: 'EUR',
        title: 'First project cost',
        occurredAt: now,
      );
      expect(f.transport.records, isEmpty);
      await f.repo.syncNow();
      expect(f.repo.state.lastError, isNull);
      expect(f.repo.state.financePendingCount, 0);
      expect(f.repo.state.financeConflicts, isEmpty);
      final operations = f.transport.pushes
          .map((p) => p['operation'] as Map)
          .toList();
      expect(operations.map((p) => p['type']), [
        'financeAccount',
        'financeEntry',
      ]);
      expect(operations.first['recordId'], accountId);
      expect(
        (operations.last['payload'] as Map)['accountScopeId'],
        f.transport.parent,
      );
      expect(
        f.repo.state.dataForScope(f.transport.project).financeAccounts,
        isEmpty,
      );
      expect(
        f.repo.state.dataForScope(f.transport.parent).financeAccounts.single.id,
        accountId,
      );
    },
  );
  test(
    'composition metadata persists exact required child sequence separately from cached snapshot sequence',
    () async {
      final f = await setup(parentAccess: true);
      final required = f.transport.sequence + 5;
      f.transport.requiredSequences[f.transport.project] = required;
      await f.repo.syncNow();
      final policy = f.repo.state.financePolicyForScope(f.transport.parent);
      expect(policy.organizationFinanceComplete, isTrue);
      expect(policy.organizationFinanceScopeIds, [f.transport.project]);
      expect(policy.organizationFinanceSequences, {
        f.transport.project: required,
      });
      expect(
        f.repo.state.financeSnapshotSequences[f.transport.project],
        lessThan(required),
      );
      await f.repo.refreshLocal();
      expect(
        f.repo.state
            .financePolicyForScope(f.transport.parent)
            .organizationFinanceSequences,
        {f.transport.project: required},
      );
      final cached = await f.db.rows(
        'SELECT finance_policy FROM scopes WHERE id=?',
        [f.transport.parent],
      );
      final json =
          jsonDecode(cached.single['finance_policy'] as String)
              as Map<String, dynamic>;
      expect(json['organizationFinanceSequences'], {
        f.transport.project: required,
      });
      expect(
        () => SharedFinancePolicy.fromJson({
          ...json,
          'organizationFinanceSequences': {f.transport.project: -1},
        }),
        throwsFormatException,
      );
      expect(
        () => SharedFinancePolicy.fromJson({
          ...json,
          'organizationFinanceSequences': <String, int>{},
        }),
        throwsFormatException,
      );
    },
  );
  test(
    'explicit same-ID legacy account choice clears parent scope while old callers preserve it',
    () async {
      final f = await setup();
      final task = LocalTask(
        id: newSharedId(),
        title: 'Same ID choice',
        notes: '',
        dueAt: null,
        projectId: f.transport.project,
        isCompleted: false,
        createdAt: now,
        updatedAt: now,
      );
      await f.repo.saveTaskWithCost(
        f.transport.project,
        task,
        isNew: true,
        cost: TaskCostDraft(
          amountMinor: 5000,
          ledgerAccountId: f.transport.account,
          accountScopeId: f.transport.parent,
          accountScopeSpecified: true,
        ),
      );
      await f.repo.syncNow();
      final accountPayload = SharedFinanceAccount(
        id: f.transport.account,
        createdAt: now,
        updatedAt: now,
        name: 'Existing same-ID project account',
        currency: 'EUR',
      ).toPayload(contractVersion: 3);
      f.transport.sequence++;
      f.transport.records[f.transport.account] = {
        'id': f.transport.account,
        'type': 'financeAccount',
        'revision': 1,
        'deleted': false,
        'payload': accountPayload,
        'contractVersion': 3,
        'sequence': f.transport.sequence,
        'updatedAt': now.toIso8601String(),
      };
      f.transport.recordScopes[f.transport.account] = f.transport.project;
      await f.repo.syncNow();
      var snapshot = f.repo.state.dataForScope(f.transport.project);
      expect(snapshot.financeAccounts.single.id, f.transport.account);
      await f.repo.saveTaskWithCost(
        f.transport.project,
        snapshot.tasks.single,
        cost: TaskCostDraft(
          amountMinor: 6000,
          ledgerAccountId: f.transport.account,
        ),
        expectedFinanceRevision: snapshot.financeEntries.single.revision,
      );
      expect(
        f.repo.state
            .dataForScope(f.transport.project)
            .financeEntries
            .single
            .accountScopeId,
        f.transport.parent,
      );
      await f.repo.syncNow();
      snapshot = f.repo.state.dataForScope(f.transport.project);
      await f.repo.saveTaskWithCost(
        f.transport.project,
        snapshot.tasks.single,
        cost: TaskCostDraft(
          amountMinor: 7000,
          ledgerAccountId: f.transport.account,
          accountScopeId: null,
          accountScopeSpecified: true,
        ),
        expectedFinanceRevision: snapshot.financeEntries.single.revision,
      );
      final moved = f.repo.state
          .dataForScope(f.transport.project)
          .financeEntries
          .single;
      expect(moved.accountId, f.transport.account);
      expect(moved.accountScopeId, isNull);
      final operation =
          jsonDecode(
                (await f.db.rows(
                      'SELECT request FROM finance_outbox',
                    )).single['request']
                    as String,
              )
              as Map;
      expect((operation['payload'] as Map)['accountScopeId'], isNull);
      await f.repo.syncNow();
      expect(f.repo.state.financePendingCount, 0);
      expect(
        f.repo.state
            .dataForScope(f.transport.project)
            .financeEntries
            .single
            .accountScopeId,
        isNull,
      );
    },
  );
}
