import 'dart:convert';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/organizer_repository.dart';
import 'package:kanban/organizer/data/organizer_storage.dart';
import 'package:kanban/organizer/data/sqlite_organizer_storage.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:kanban/organizer/data/portable_backup_repository.dart';
import 'package:kanban/organizer/data/portable_backup_crypto.dart';
import 'package:kanban/organizer/data/portable_backup_document.dart';
import 'package:kanban/organizer/domain/finance_reminder_plans.dart';
import 'organizer_repository_test.dart' show MemoryStorage;

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  var now = DateTime.utc(2026, 10, 8, 12);
  LocalTask task({String id = 'task', DateTime? dueAt}) => LocalTask(
    id: id,
    title: 'Nakup zemlje',
    notes: '  preserve\n    spacing  ',
    projectId: null,
    dueAt: dueAt,
    isCompleted: false,
    createdAt: now,
    updatedAt: now,
    estimateMinutes: 30,
  );
  OrganizerRepository repo(OrganizerStorage storage) {
    var next = 0;
    return OrganizerRepository(
      storage,
      clock: () => now,
      idGenerator: () => 'id-${next++}',
    );
  }

  setUp(() => now = DateTime.utc(2026, 10, 8, 12));

  test(
    'linked cost is one record; due changes and removal preserve payment and deletion detaches',
    () async {
      final store = MemoryStorage(), r = repo(MemoryStorage());
      final repository = repo(store);
      await r.close();
      await repository.initialize();
      await repository.saveTaskWithCost(
        task: task(dueAt: now),
        isNew: true,
        cost: const TaskCostDraft(amountMinor: 1250),
        expectedWorkspaceKey: 'local',
      );
      expect(store.writes, 1);
      expect(
        repository.snapshot.tasks.single.notes,
        '  preserve\n    spacing  ',
      );
      final id = repository.snapshot.financeEntries.single.id;
      expect(repository.snapshot.balanceForCurrency('EUR'), 0);
      var edited = repository.snapshot.tasks.single.copyWith(
        dueAt: now.add(const Duration(days: 3)),
      );
      await repository.updateTask(edited);
      expect(repository.snapshot.financeEntries.single.plannedAt, edited.dueAt);
      final entry = repository.snapshot.financeEntries.single;
      final paidAt = now.add(const Duration(hours: 2));
      await repository.confirmFinanceOccurrence(
        entry: entry,
        amountMinor: 1350,
        paidAt: paidAt,
        expectedWorkspaceKey: 'local',
      );
      expect(repository.snapshot.balanceForCurrency('EUR'), -1350);
      edited = repository.snapshot.tasks.single.copyWith(dueAt: null);
      await repository.updateTask(edited);
      final paid = repository.snapshot.financeEntries.single;
      expect(paid.id, id);
      expect(paid.plannedAt, isNull);
      expect(paid.paidAt, paidAt);
      expect(paid.occurredAt, paidAt);
      await repository.deleteTask(edited.id);
      expect(repository.snapshot.financeEntries.single.taskId, isNull);
      expect(repository.snapshot.financeEntries.single.id, id);
      expect(
        repository.snapshot.exactBalanceForCurrency('EUR'),
        BigInt.from(-1350),
      );
      await repository.close();
    },
  );

  test(
    'atomic task/cost failure preserves both collections and stale finance edit is rejected',
    () async {
      final store = MemoryStorage(), repository = repo(MemoryStorage());
      await repository.close();
      final r = repo(store);
      await r.initialize();
      store.failWrite = true;
      await expectLater(
        r.saveTaskWithCost(
          task: task(),
          isNew: true,
          cost: const TaskCostDraft(amountMinor: 1000),
          expectedWorkspaceKey: 'local',
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(r.snapshot.tasks, isEmpty);
      expect(r.snapshot.financeEntries, isEmpty);
      store.failWrite = false;
      await r.saveTaskWithCost(
        task: task(),
        isNew: true,
        cost: const TaskCostDraft(amountMinor: 1000),
        expectedWorkspaceKey: 'local',
      );
      final original = r.snapshot.financeEntries.single;
      await r.updateFinanceEntry(original.copyWith(amountMinor: 1100));
      await expectLater(
        r.saveTaskWithCost(
          task: r.snapshot.tasks.single,
          cost: const TaskCostDraft(amountMinor: 1200),
          expectedFinanceRevision: original.revision,
          expectedWorkspaceKey: 'local',
        ),
        throwsA(isA<OrganizerConflictException>()),
      );
      expect(r.snapshot.financeEntries.single.amountMinor, 1100);
      await r.close();
    },
  );

  test(
    'one timer in workspace; pause is idempotent, restart preserves running time, expiry never completes',
    () async {
      final store = MemoryStorage(), r = repo(MemoryStorage());
      await r.close();
      var repository = repo(store);
      await repository.initialize();
      await repository.saveTaskWithCost(
        task: task(),
        isNew: true,
        expectedWorkspaceKey: 'local',
      );
      await repository.saveTaskWithCost(
        task: task(id: 'second'),
        isNew: true,
        expectedWorkspaceKey: 'local',
      );
      await repository.startTaskTimer(
        'task',
        expectedRevision: 0,
        expectedWorkspaceKey: 'local',
      );
      final run = repository.snapshot.tasks.first.timer.runId!;
      final writes = store.writes;
      now = now.add(const Duration(minutes: 5));
      expect(repository.snapshot.tasks.first.timer.elapsedAt(now), 300);
      expect(store.writes, writes);
      await repository.close();
      repository = repo(store);
      await repository.initialize();
      expect(repository.snapshot.tasks.first.timer.running, isTrue);
      await repository.pauseTaskTimer(
        'task',
        runId: run,
        expectedWorkspaceKey: 'local',
      );
      final pausedWrites = store.writes;
      await repository.pauseTaskTimer(
        'task',
        runId: run,
        expectedWorkspaceKey: 'local',
      );
      expect(store.writes, pausedWrites);
      expect(repository.snapshot.tasks.first.timer.elapsedSeconds, 300);
      await repository.startTaskTimer(
        'task',
        expectedRevision: repository.snapshot.tasks.first.revision,
        expectedWorkspaceKey: 'local',
      );
      now = now.add(const Duration(hours: 1));
      expect(repository.snapshot.tasks.first.timer.remainingAt(30, now), 0);
      expect(repository.snapshot.tasks.first.isCompleted, isFalse);
      await repository.startTaskTimer(
        'second',
        expectedRevision: repository.snapshot.tasks.last.revision,
        expectedWorkspaceKey: 'local',
      );
      expect(
        repository.snapshot.tasks.where((t) => t.timer.running),
        hasLength(1),
      );
      expect(repository.snapshot.tasks.first.timer.elapsedSeconds, 3900);
      await repository.close();
    },
  );

  test(
    'phases metadata and new collections round-trip JSON4; old JSON import preserves them',
    () async {
      final store = MemoryStorage(), r = repo(MemoryStorage());
      await r.close();
      final repository = repo(store);
      await repository.initialize();
      await repository.createProject(
        title: 'Vrt',
        phases: const [
          ProjectPhase(
            id: 'phase',
            title: 'Priprava',
            milestone: 'Greda pripravljena',
          ),
        ],
        availabilityMinutes: 180,
        availabilityPeriod: AvailabilityPeriod.week,
      );
      await repository.createPerson(name: 'Oseba brez računa');
      await repository.saveTaskWithCost(
        task: task().copyWith(
          projectId: repository.snapshot.projects.single.id,
          phaseId: 'phase',
          assigneePersonId: repository.snapshot.people.single.id,
        ),
        isNew: true,
        expectedWorkspaceKey: 'local',
      );
      final doc =
          jsonDecode(await repository.exportBackup()) as Map<String, dynamic>;
      expect(doc['schemaVersion'], 4);
      final decoded = OrganizerBackupCodec.decode(jsonEncode(doc));
      expect(decoded.tasks.single.phaseId, 'phase');
      expect(decoded.projects.single.availabilityMinutes, 180);
      expect(decoded.people.single.name, 'Oseba brez računa');
      final legacy = OrganizerSnapshot().toJson()
        ..remove('people')
        ..remove('financeAccounts')
        ..remove('financeRecurrenceRules');
      await repository.importBackup(
        jsonEncode({
          'format': 'vsakdan-personal-backup',
          'schemaVersion': 2,
          'workspace': 'personal',
          'data': legacy,
        }),
      );
      expect(repository.snapshot.people, hasLength(1));
      expect(repository.snapshot.projects.single.phases, hasLength(1));
      await repository.updateProject(
        repository.snapshot.projects.single.copyWith(phases: []),
      );
      expect(repository.snapshot.tasks.single.phaseId, isNull);
      await repository.close();
    },
  );

  test(
    'SQLite disk reopen preserves task timer, phase, cost and rollback cancels both rows',
    () async {
      final directory = await Directory.systemTemp.createTemp('jivie-planning');
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/organizer.sqlite');
      var db = CollaborationDatabase(NativeDatabase(file));
      var storage = SqliteOrganizerStorage(db);
      await storage.initialize();
      var repository = repo(storage);
      await repository.initialize();
      await repository.createProject(
        title: 'Projekt',
        phases: const [ProjectPhase(id: 'p', title: 'Faza')],
      );
      await repository.saveTaskWithCost(
        task: task().copyWith(
          projectId: repository.snapshot.projects.single.id,
          phaseId: 'p',
        ),
        isNew: true,
        cost: const TaskCostDraft(amountMinor: 1400),
        expectedWorkspaceKey: 'local',
      );
      await repository.startTaskTimer(
        'task',
        expectedRevision: 0,
        expectedWorkspaceKey: 'local',
      );
      await repository.close();
      await db.close();
      db = CollaborationDatabase(NativeDatabase(file));
      storage = SqliteOrganizerStorage(db);
      await storage.initialize();
      repository = repo(storage);
      await repository.initialize();
      expect(repository.snapshot.tasks.single.timer.running, isTrue);
      expect(repository.snapshot.tasks.single.phaseId, 'p');
      expect(repository.snapshot.financeEntries.single.amountMinor, 1400);
      await db.execute(
        "CREATE TRIGGER fail_cost BEFORE INSERT ON personal_records WHEN NEW.type='financeEntry' BEGIN SELECT RAISE(ABORT,'test rollback'); END",
      );
      final old = repository.snapshot;
      await expectLater(
        repository.saveTaskWithCost(
          task: repository.snapshot.tasks.single.copyWith(title: 'Changed'),
          cost: const TaskCostDraft(amountMinor: 1500),
          expectedFinanceRevision:
              repository.snapshot.financeEntries.single.revision,
          expectedWorkspaceKey: 'local',
        ),
        throwsA(anything),
      );
      expect((await storage.read()).tasks.single.title, old.tasks.single.title);
      expect((await storage.read()).financeEntries.single.amountMinor, 1400);
      await repository.close();
      await db.close();
    },
  );
  test(
    'schema 5 migration preserves gardens and immutable finance operation body',
    () async {
      final directory = await Directory.systemTemp.createTemp('jivie-schema5');
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/database.sqlite');
      var db = CollaborationDatabase(NativeDatabase(file));
      await db.execute(
        "INSERT INTO device_gardens(id,payload) VALUES('garden','{}')",
      );
      await db.execute('ALTER TABLE finance_outbox DROP COLUMN wire_version');
      const body = '{"opId":"old-op","unchanged":"original\\nbody"}';
      await db.execute(
        "INSERT INTO finance_outbox(op_id,partition,scope_id,record_id,request) VALUES('old-op','p','s','r',?)",
        [body],
      );
      await db.execute('PRAGMA user_version=5');
      await db.close();
      db = CollaborationDatabase(NativeDatabase(file));
      expect(
        (await db.rows('SELECT * FROM device_gardens')).single['id'],
        'garden',
      );
      final operation = (await db.rows('SELECT * FROM finance_outbox')).single;
      expect(operation['request'], body);
      expect(operation['wire_version'], 1);
      expect((await db.rows('PRAGMA user_version')).single['user_version'], 6);
      await db.close();
    },
  );
  test(
    'private rich rows remap people/account/task references, pair outboxes and retain portable backup operation IDs',
    () async {
      const scopeId = '00000000-0000-4000-8000-000000000010';
      final profile = AccountSession(
        serverUrl: 'https://test.invalid',
        serverId: '00000000-0000-4000-8000-000000000001',
        accountId: '00000000-0000-4000-8000-000000000002',
        userId: 1,
        username: 'test',
        displayName: 'test',
        deviceId: '00000000-0000-4000-8000-000000000003',
        expiresAt: now.add(const Duration(days: 1)),
      );
      final db = CollaborationDatabase(NativeDatabase.memory());
      final local = SqliteOrganizerStorage(db);
      await local.initialize();
      await db.execute('INSERT INTO accounts(partition,profile) VALUES(?,?)', [
        profile.partition,
        jsonEncode(profile.toJson()),
      ]);
      await db.execute(
        'INSERT INTO scopes(partition,id,data,cursor,finance_policy,finance_complete) VALUES(?,?,?,1,?,1)',
        [
          profile.partition,
          scopeId,
          jsonEncode(
            const SharedScope(
              id: scopeId,
              name: 'Private',
              kind: SharedScopeKind.personal,
              role: SharedRole.owner,
            ).toJson(),
          ),
          jsonEncode({'enabled': true, 'grant': 'write', 'revision': 1}),
        ],
      );
      await db.execute(
        'INSERT INTO personal_workspaces(id,partition,scope_id,enabled) VALUES(?,?,?,1)',
        ['private:${profile.partition}', profile.partition, scopeId],
      );
      db.activatePersonal(profile);
      final initial = await local.read();
      await local.write(
        initial.copyWith(
          revision: initial.revision + 1,
          people: [
            HouseholdPerson(
              id: 'local-person',
              name: 'Mati',
              createdAt: now,
              updatedAt: now,
            ),
          ],
          financeAccounts: [
            LocalFinanceAccount(
              id: 'local-account',
              name: 'Račun',
              currency: 'EUR',
              createdAt: now,
              updatedAt: now,
            ),
          ],
          projects: [
            LocalProject(
              id: 'local-project',
              title: 'Projekt',
              description: '',
              createdAt: now,
              updatedAt: now,
              phases: const [ProjectPhase(id: 'phase', title: 'Faza')],
            ),
          ],
        ),
      );
      final repository = repo(local);
      await repository.initialize();
      await repository.saveTaskWithCost(
        task: task(dueAt: now).copyWith(
          projectId: 'local-project',
          phaseId: 'phase',
          assigneePersonId: 'local-person',
          subjectPersonIds: ['local-person'],
        ),
        isNew: true,
        cost: const TaskCostDraft(
          amountMinor: 1500,
          ledgerAccountId: 'local-account',
          payerPersonId: 'local-person',
        ),
        expectedWorkspaceKey: initial.workspaceKey,
      );
      final maps = {
        for (final row in await db.rows(
          'SELECT id,remote_id FROM personal_record_map',
        ))
          row['id']: row['remote_id'],
      };
      final generic = (await db.rows("SELECT * FROM outbox WHERE record_id=?", [
        maps['task'],
      ])).single;
      final finance = (await db.rows(
        "SELECT * FROM finance_outbox WHERE record_id=?",
        [maps[repository.snapshot.financeEntries.single.id]],
      )).single;
      final taskPayload =
          (jsonDecode(generic['request'] as String) as Map)['payload'] as Map;
      final financePayload =
          (jsonDecode(finance['request'] as String) as Map)['payload'] as Map;
      expect(generic['wire_version'], 3);
      expect(finance['wire_version'], 2);
      expect(taskPayload['assigneePersonId'], maps['local-person']);
      expect(taskPayload['subjectPersonIds'], [maps['local-person']]);
      expect(taskPayload['phaseId'], 'phase');
      expect(financePayload['taskId'], maps['task']);
      expect(financePayload['ledgerAccountId'], maps['local-account']);
      expect(financePayload['payerPersonId'], maps['local-person']);
      expect(financePayload.containsKey('createdByAccountId'), isFalse);
      expect(
        (await db.rows('SELECT value FROM local_meta WHERE name=?', [
          'task_cost_pair:${profile.partition}:${generic['op_id']}',
        ])).single['value'],
        finance['op_id'],
      );
      await db.execute(
        'UPDATE finance_records SET remote=? WHERE partition=? AND scope_id=? AND id=?',
        [
          jsonEncode({
            'id': finance['record_id'],
            'type': 'personalFinanceEntry',
            'revision': 1,
            'deleted': false,
            'payload': financePayload,
            'sequence': 1,
            'updatedAt': now.toUtc().toIso8601String(),
            'createdByAccountId': profile.accountId,
            'updatedByAccountId': profile.accountId,
            'contractVersion': 2,
          }),
          profile.partition,
          scopeId,
          finance['record_id'],
        ],
      );
      final backup = PortableBackupRepository(
        db,
        local,
        MemoryBackupUiPreferencesStore(),
      );
      final bytes = await backup.exportEncryptedBackup('a long test password');
      final doc = await PortableBackupCrypto().decrypt(
        bytes,
        'a long test password',
      );
      validateBackupDocument(doc);
      expect(doc['version'], 3);
      expect(doc['databaseVersion'], 6);
      expect(doc['operationPairs'], [
        {'genericOpId': generic['op_id'], 'financeOpId': finance['op_id']},
      ]);
      expect(
        (await local.read()).tasks.single.assigneePersonId,
        'local-person',
      );
      expect(
        (await local.read()).financeEntries.single.ledgerAccountId,
        'local-account',
      );
      await repository.close();
      await db.close();
    },
  );
  test(
    'SQLite delete and JSON restore retain revision fence against an old open editor',
    () async {
      final db = CollaborationDatabase(NativeDatabase.memory());
      final storage = SqliteOrganizerStorage(db);
      await storage.initialize();
      final repository = repo(storage);
      await repository.initialize();
      await repository.saveTaskWithCost(
        task: task(),
        isNew: true,
        expectedWorkspaceKey: 'local',
      );
      final oldEditor = repository.snapshot.tasks.single;
      final backup = await repository.exportBackup();
      await repository.deleteTask(oldEditor.id);
      await repository.importBackup(backup);
      expect(
        repository.snapshot.tasks.single.revision,
        greaterThan(oldEditor.revision),
      );
      await expectLater(
        repository.updateTask(oldEditor.copyWith(title: 'Stale edit')),
        throwsA(isA<OrganizerConflictException>()),
      );
      expect(repository.snapshot.tasks.single.title, oldEditor.title);
      await repository.close();
      await db.close();
    },
  );

  test(
    'replacing with old portable backup preserves new people, account, rules and confirmed financial history',
    () async {
      final db = CollaborationDatabase(NativeDatabase.memory());
      final local = SqliteOrganizerStorage(db);
      await local.initialize();
      final repository = repo(local);
      await repository.initialize();
      final portable = PortableBackupRepository(
        db,
        local,
        MemoryBackupUiPreferencesStore(),
      );
      const password = 'a long test password';
      final initial = await portable.exportEncryptedBackup(password),
          crypto = PortableBackupCrypto();
      final legacy = await crypto.decrypt(initial, password);
      legacy['version'] = 2;
      legacy['databaseVersion'] = 5;
      legacy.remove('operationPairs');
      legacy.remove('financeInboxReads');
      final json =
          jsonDecode(legacy['personal'] as String) as Map<String, dynamic>;
      json['schemaVersion'] = 2;
      (json['data'] as Map)
        ..remove('people')
        ..remove('financeAccounts')
        ..remove('financeRecurrenceRules');
      legacy['personal'] = jsonEncode(json);
      final oldBytes = await crypto.encrypt(legacy, password);
      await repository.createPerson(name: 'Mati');
      await repository.saveFinancePlan(
        accounts: [
          LocalFinanceAccount(
            id: 'account',
            name: 'Račun',
            currency: 'EUR',
            createdAt: now,
            updatedAt: now,
          ),
        ],
        rules: [
          FinanceRecurrenceRule(
            id: 'rule',
            title: 'Plača',
            kind: FinanceRecurrenceKind.salary,
            ledgerAccountId: 'account',
            currency: 'EUR',
            estimatedAmountMinor: 100000,
            startYear: 2026,
            startMonth: 10,
            monthDay: 15,
            createdAt: now,
            updatedAt: now,
          ),
        ],
        expectedRevision: repository.snapshot.revision,
        expectedWorkspaceKey: 'local',
      );
      final occurrence = repository.snapshot.financeEntries.first;
      await repository.confirmFinanceOccurrence(
        entry: occurrence,
        amountMinor: 110000,
        paidAt: now,
        expectedWorkspaceKey: 'local',
      );
      final before = await local.read();
      await portable.restoreEncryptedBackup(
        oldBytes,
        password,
        mode: BackupRestoreMode.replace,
        expectedPersonalRevision: before.revision,
      );
      final restored = await local.read();
      expect(restored.people.single.name, 'Mati');
      expect(restored.financeAccounts.single.id, 'account');
      expect(restored.financeRecurrenceRules.single.id, 'rule');
      expect(
        restored.financeEntries.firstWhere((e) => e.id == occurrence.id).status,
        FinanceEntryStatus.posted,
      );
      expect(restored.exactBalanceForCurrency('EUR'), BigInt.from(110000));
      expect(
        restored.financeEntries
            .firstWhere((e) => e.id == occurrence.id)
            .revision,
        greaterThan(
          before.financeEntries
              .firstWhere((e) => e.id == occurrence.id)
              .revision,
        ),
      );
      await repository.close();
      await db.close();
    },
  );
  test(
    'hybrid local task gets local cost; foreign parents are rejected and logout/export stays valid without upload',
    () async {
      final db = CollaborationDatabase(NativeDatabase.memory());
      final storage = SqliteOrganizerStorage(db);
      await storage.initialize();
      var initial = await storage.read();
      await storage.write(
        initial.copyWith(
          revision: initial.revision + 1,
          tasks: [task(id: 'local-task')],
          people: [
            HouseholdPerson(
              id: 'local-person',
              name: 'Local person',
              createdAt: now,
              updatedAt: now,
            ),
          ],
          financeAccounts: [
            LocalFinanceAccount(
              id: 'local-account',
              name: 'Local ledger',
              currency: 'EUR',
              createdAt: now,
              updatedAt: now,
            ),
          ],
        ),
      );
      const scopeId = '00000000-0000-4000-8000-000000000010';
      final profile = AccountSession(
        serverUrl: 'https://test.invalid',
        serverId: '00000000-0000-4000-8000-000000000001',
        accountId: '00000000-0000-4000-8000-000000000002',
        userId: 1,
        username: 'test',
        displayName: 'test',
        deviceId: '00000000-0000-4000-8000-000000000003',
        expiresAt: now.add(const Duration(days: 1)),
      );
      await db.execute('INSERT INTO accounts(partition,profile) VALUES(?,?)', [
        profile.partition,
        jsonEncode(profile.toJson()),
      ]);
      await db.execute(
        'INSERT INTO scopes(partition,id,data,cursor,finance_policy,finance_complete) VALUES(?,?,?,1,?,1)',
        [
          profile.partition,
          scopeId,
          jsonEncode(
            const SharedScope(
              id: scopeId,
              name: 'Private',
              kind: SharedScopeKind.personal,
              role: SharedRole.owner,
            ).toJson(),
          ),
          jsonEncode({'enabled': true, 'grant': 'write', 'revision': 1}),
        ],
      );
      final binding = <String, dynamic>{
        'id': 'private:${profile.partition}',
        'partition': profile.partition,
        'scope_id': scopeId,
      };
      await db.execute(
        'INSERT INTO personal_workspaces(id,partition,scope_id,enabled) VALUES(?,?,?,1)',
        [binding['id'], profile.partition, scopeId],
      );
      db.activatePersonal(profile);
      await db.transaction(() async {
        await queuePrivateRecord(
          db,
          binding,
          'private-person',
          'householdPerson',
          HouseholdPerson(
            id: 'private-person',
            name: 'Private person',
            createdAt: now,
            updatedAt: now,
          ).toJson(),
        );
        await queuePrivateRecord(
          db,
          binding,
          'private-account',
          'financeAccount',
          LocalFinanceAccount(
            id: 'private-account',
            name: 'Private ledger',
            currency: 'EUR',
            createdAt: now,
            updatedAt: now,
          ).toJson(),
        );
      });
      final repository = repo(storage);
      await repository.initialize();
      final beforeGeneric = await db.rows('SELECT op_id FROM outbox'),
          beforeFinance = await db.rows('SELECT op_id FROM finance_outbox');
      await repository.saveTaskWithCost(
        task: repository.snapshot.tasks.single,
        cost: const TaskCostDraft(
          amountMinor: 1250,
          ledgerAccountId: 'local-account',
          payerPersonId: 'local-person',
        ),
        expectedWorkspaceKey: repository.snapshot.workspaceKey,
      );
      expect(await db.rows('SELECT op_id FROM outbox'), beforeGeneric);
      expect(await db.rows('SELECT op_id FROM finance_outbox'), beforeFinance);
      expect(
        (await storage.localSnapshot()).financeEntries.single.taskId,
        'local-task',
      );
      final entry = repository.snapshot.financeEntries.single;
      await expectLater(
        repository.updateFinanceEntry(
          entry.copyWith(ledgerAccountId: 'private-account'),
        ),
        throwsA(isA<FormatException>()),
      );
      expect(
        (await storage.localSnapshot()).financeEntries.single.ledgerAccountId,
        'local-account',
      );
      db.activatePersonal(null);
      await repository.reload();
      expect(
        repository.snapshot.financeEntries.single.ledgerAccountId,
        'local-account',
      );
      expect(repository.snapshot.people.single.id, 'local-person');
      final copy = OrganizerBackupCodec.decode(await repository.exportBackup());
      expect(copy.financeEntries.single.taskId, 'local-task');
      expect(copy.financeAccounts.single.id, 'local-account');
      copy.validate();
      await repository.close();
      await db.close();
    },
  );

  test(
    'portable backup preserves permitted finance read receipts without booking or another account receipts',
    () async {
      final db = CollaborationDatabase(NativeDatabase.memory());
      final storage = SqliteOrganizerStorage(db);
      await storage.initialize();
      final repository = repo(storage);
      await repository.initialize();
      await repository.saveFinancePlan(
        accounts: [],
        rules: [
          FinanceRecurrenceRule(
            id: 'read-rule',
            title: 'Salary',
            kind: FinanceRecurrenceKind.salary,
            currency: 'EUR',
            estimatedAmountMinor: 100000,
            startYear: 2026,
            startMonth: 10,
            monthDay: 25,
            remindersEnabled: true,
            createdAt: now,
            updatedAt: now,
          ),
        ],
        expectedRevision: repository.snapshot.revision,
        expectedWorkspaceKey: 'local',
      );
      final allowed = allowedFinanceInboxReadNames(
        personal: repository.snapshot,
        shared: CollaborationState(),
      );
      final name = allowed.first, value = now.toUtc().toIso8601String();
      await db.execute('INSERT INTO local_meta(name,value) VALUES(?,?)', [
        name,
        value,
      ]);
      await db.execute('INSERT INTO local_meta(name,value) VALUES(?,?)', [
        'finance_inbox_read:another-account:secret-id',
        value,
      ]);
      final portable = PortableBackupRepository(
        db,
        storage,
        MemoryBackupUiPreferencesStore(),
      );
      const password = 'a long test password';
      final bytes = await portable.exportEncryptedBackup(password),
          doc = await PortableBackupCrypto().decrypt(bytes, password);
      expect(doc['financeInboxReads'], [
        {'name': name, 'value': value},
      ]);
      expect(repository.snapshot.balanceForCurrency('EUR'), 0);
      await db.execute('DELETE FROM local_meta WHERE name=?', [name]);
      await portable.restoreEncryptedBackup(
        bytes,
        password,
        mode: BackupRestoreMode.replace,
        expectedPersonalRevision: (await storage.read()).revision,
      );
      expect(
        (await db.rows('SELECT value FROM local_meta WHERE name=?', [
          name,
        ])).single['value'],
        value,
      );
      expect(
        (await storage.read()).financeEntries.every(
          (e) => e.status == FinanceEntryStatus.planned,
        ),
        isTrue,
      );
      await repository.close();
      await db.close();
    },
  );
}
