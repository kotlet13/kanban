import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'collaboration_repository_test.dart'
    show FakeServer, FakeTransport, MemorySessionStore, code;

class RichServer extends FakeServer {
  int version = 3;
  @override
  Future<Map<String, dynamic>> call(
    String operation,
    Map<String, Object?> params,
    String? token,
  ) async {
    if (operation == 'scopes.members') {
      final scope = params['scopeId'] as String, user = tokens[token];
      if (user == null || members[scope]?[user] == null) {
        throw const CollaborationException('permission_revoked');
      }
      return {
        'members': [
          for (final entry in members[scope]!.entries)
            {
              'userId': entry.key == 'alice' ? 1 : 2,
              'accountId': accountIds[entry.key],
              'username': entry.key,
              'displayName': entry.key,
              'role': entry.value,
              'active': true,
            },
        ],
      };
    }
    final result = await super.call(
      operation == 'sync3.push' || operation == 'sync2.push'
          ? 'sync.push'
          : (operation == 'sync3.pull' || operation == 'sync2.pull'
                ? 'sync.pull'
                : operation),
      params,
      token,
    );
    if (operation == 'capabilities') {
      result['recordContractVersions'] = [1, 2, if (version >= 3) 3];
      result['features'] = <String, dynamic>{
        ...result['features'] as Map<String, dynamic>,
        'householdPeople': version >= 3,
        'organizations': version >= 3,
      };
    }
    if (operation == 'scopes.create') {
      (result['scope'] as Map)['organizationId'] = params['organizationId'];
      (result['scope'] as Map)['requiredRecordContractVersion'] =
          params['kind'] == 'organization' ? 3 : 1;
    }
    return result;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late Directory dir;
  late RichServer server;
  late FakeTransport transport;
  late MemorySessionStore store;
  final repositories = <CollaborationRepository>[];
  final now = DateTime.utc(2026, 10, 8, 6);
  Future<CollaborationRepository> open() async {
    final repo = CollaborationRepository(
      CollaborationDatabase(NativeDatabase(File('${dir.path}/data.sqlite'))),
      transport,
      store,
      clock: () => now,
    );
    repositories.add(repo);
    await repo.initialize();
    return repo;
  }

  Future<CollaborationRepository> login() async {
    await server.call('capabilities', {}, null);
    final repo = await open();
    await repo.login(
      serverUrl: 'https://synthetic.invalid/',
      username: 'alice',
      password: 'synthetic',
    );
    expect(repo.state.lastError, isNull);
    return repo;
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('rich-contract-');
    server = RichServer();
    transport = FakeTransport(server);
    store = MemorySessionStore();
  });
  tearDown(() async {
    for (final repo in repositories) {
      await repo.close();
    }
    repositories.clear();
    await dir.delete(recursive: true);
  });
  test(
    'scoped people keep references and never confer account membership',
    () async {
      final repo = await login();
      final org = await repo.createScope(
        'Organization',
        kind: SharedScopeKind.organization,
      );
      final child = await repo.createScope(
        'Project',
        kind: SharedScopeKind.project,
        organizationId: org,
      );
      expect(
        repo.state.scopes.firstWhere((s) => s.id == child).organizationId,
        org,
      );
      expect(server.members[org]!.keys.toList(), ['alice']);
      expect(server.members[child]!.keys.toList(), ['alice']);
    },
  );
  test(
    'person archive retains existing task, rejects new assignment and other scope',
    () async {
      final repo = await login();
      final scope = await repo.createScope('Home'),
          other = await repo.createScope('Other');
      final person = await repo.createPerson(
        scopeId: scope,
        name: 'Synthetic person',
      );
      final task = await repo.createTask(
        scopeId: scope,
        title: 'Task',
        assigneePersonId: person,
        subjectPersonIds: [person],
      );
      final profile = repo.state.dataForScope(scope).people.single;
      await repo.archivePerson(scope, profile);
      await repo.updateTask(
        scope,
        repo.state.dataForScope(scope).tasks.single.copyWith(notes: 'Retained'),
      );
      await expectLater(
        repo.createTask(
          scopeId: scope,
          title: 'Invalid',
          assigneePersonId: person,
        ),
        throwsA(code('person_archived')),
      );
      await expectLater(
        repo.createTask(
          scopeId: other,
          title: 'Other scope',
          assigneePersonId: person,
        ),
        throwsA(code('record_missing')),
      );
      await repo.syncNow();
      expect(repo.state.dataForScope(scope).tasks.single.id, task);
      expect(server.members[scope]!.length, 1);
      expect(repo.state.dataForScope(scope).people.single.archived, isTrue);
    },
  );
  test(
    'rich explicit copy remaps phases and people, pauses timer and excludes finance',
    () async {
      final repo = await login();
      final scope = await repo.createScope('Destination');
      final person = HouseholdPerson(
        id: newSharedId(),
        name: 'Source profile',
        archived: true,
        createdAt: now,
        updatedAt: now,
      );
      final project = LocalProject(
        id: newSharedId(),
        title: 'Source',
        description: 'Rich',
        phases: [
          const ProjectPhase(id: 'phase-A', title: 'Phase', milestone: 'Goal'),
        ],
        availabilityMinutes: 120,
        availabilityPeriod: AvailabilityPeriod.week,
        createdAt: now,
        updatedAt: now,
      );
      final task = LocalTask(
        id: newSharedId(),
        title: 'Timed',
        notes: '',
        projectId: project.id,
        dueAt: null,
        isCompleted: false,
        phaseId: 'phase-A',
        estimateMinutes: 30,
        assigneePersonId: person.id,
        subjectPersonIds: [person.id],
        timer: TaskTimerState(
          elapsedSeconds: 5,
          runningSince: now.subtract(const Duration(seconds: 10)),
          runId: 'source-run',
        ),
        createdAt: now,
        updatedAt: now,
      );
      final copied = await repo.publishProject(
        scopeId: scope,
        project: project,
        tasks: [task],
        people: [person],
      );
      final data = repo.state.dataForScope(scope),
          copiedTask = repo.state.dataForScope(scope).tasks.single;
      expect(copied, isNot(project.id));
      expect(data.projects.single.phases.single.id, isNot('phase-A'));
      expect(copiedTask.phaseId, data.projects.single.phases.single.id);
      expect(copiedTask.assigneePersonId, data.people.single.id);
      expect(data.people.single.id, isNot(person.id));
      expect(data.people.single.archived, isTrue);
      expect(copiedTask.timer.running, isFalse);
      expect(copiedTask.timer.elapsedSeconds, 15);
      expect(data.projects.single.availabilityMinutes, 120);
      expect(copiedTask.estimateMinutes, 30);
      expect(await repo.database.rows('SELECT * FROM finance_outbox'), isEmpty);
      await repo.syncNow();
      expect(repo.state.pendingCount, 0);
      expect(
        server.records[scope]![copiedTask.id]!['payload']['subjectPersonIds'],
        [data.people.single.id],
      );
    },
  );
  test(
    'selected space persists per account and lost scope never falls back to another',
    () async {
      final repo = await login();
      final first = await repo.createScope('First');
      await repo.createScope('Second');
      await repo.selectSpace(first);
      await repo.close();
      final restarted = await open();
      expect(restarted.state.selectedSpaceId, first);
      server.members[first]!.remove('alice');
      await restarted.syncNow();
      expect(restarted.state.selectedSpaceId, first);
      expect(
        restarted.state.scopes.firstWhere((s) => s.id == first).revoked,
        isTrue,
      );
      await expectLater(
        restarted.selectSpace(first),
        throwsA(code('permission_revoked')),
      );
      await restarted.selectSpace(null);
      expect(restarted.state.selectedSpaceId, isNull);
    },
  );
  test(
    'legacy conflict keeps local title and freshest canonical rich fields',
    () async {
      server.version = 2;
      final repo = await login();
      final scope = await repo.createScope('Legacy');
      final id = await repo.createProject(scopeId: scope, title: 'Initial');
      await repo.syncNow();
      transport.offline = true;
      await repo.updateProject(
        scope,
        repo.state
            .dataForScope(scope)
            .projects
            .single
            .copyWith(title: 'Local title'),
      );
      final original = (await repo.database.rows(
        'SELECT * FROM outbox',
      )).single;
      final originalBody = original['request'];
      server.version = 3;
      transport.offline = false;
      final record = server.records[scope]![id]!;
      record['revision'] = 2;
      record['sequence'] = server.sequence[scope] = 2;
      record['payload'] = {
        ...record['payload'] as Map<String, dynamic>,
        'phases': [
          const ProjectPhase(
            id: 'server-phase',
            title: 'First upgrade',
          ).toJson(),
        ],
        'availabilityMinutes': 120,
        'availabilityPeriod': 'week',
      };
      await repo.syncNow();
      expect(repo.state.conflicts.length, 1);
      // A second remote change occurs after the historical conflict was saved.
      record['revision'] = 3;
      record['sequence'] = server.sequence[scope] = 3;
      record['payload'] = {
        ...record['payload'] as Map<String, dynamic>,
        'phases': [
          const ProjectPhase(
            id: 'newest-phase',
            title: 'Fresh canonical',
            milestone: 'Preserve me',
          ).toJson(),
        ],
        'availabilityMinutes': 240,
      };
      await repo.resolveConflict(
        conflictId: original['op_id'] as String,
        keepLocal: true,
      );
      final replacement = (await repo.database.rows(
        'SELECT * FROM outbox',
      )).single;
      final body =
          jsonDecode(replacement['request'] as String) as Map<String, dynamic>;
      expect(replacement['op_id'], isNot(original['op_id']));
      expect(replacement['wire_version'], 3);
      expect(body['expectedRevision'], 3);
      expect(body['payload']['title'], 'Local title');
      expect(body['payload']['phases'][0]['id'], 'newest-phase');
      expect(body['payload']['availabilityMinutes'], 240);
      expect(
        jsonDecode(originalBody as String)['payload'].containsKey('phases'),
        isFalse,
      );
      await repo.syncNow();
      expect(repo.state.pendingCount, 0);
      expect(
        repo.state.dataForScope(scope).projects.single.phases.single.milestone,
        'Preserve me',
      );
    },
  );
  test(
    'explicit phase removal detaches tasks before parent without changing effort or cost',
    () async {
      final repo = await login();
      final scope = await repo.createScope('Shared');
      final project = await repo.createProject(
        scopeId: scope,
        title: 'Project',
        phases: [const ProjectPhase(id: 'phase-A', title: 'Phase A')],
      );
      final first = await repo.createTask(
        scopeId: scope,
        title: 'First',
        projectId: project,
        phaseId: 'phase-A',
        estimateMinutes: 30,
      );
      await repo.createTask(
        scopeId: scope,
        title: 'Second',
        projectId: project,
        phaseId: 'phase-A',
        estimateMinutes: 60,
      );
      await repo.syncNow();
      final costId = newSharedId(),
          cost = jsonEncode({
            'amountMinor': 1234,
            'taskId': first,
            'paidAt': '2026-10-07T00:00:00.000Z',
          });
      await repo.database.execute(
        'INSERT INTO finance_records(partition,scope_id,id,type,local_revision,server_revision,payload,deleted) VALUES(?,?,?,\'financeEntry\',1,1,?,0)',
        [repo.state.session!.partition, scope, costId, cost],
      );
      await repo.updateProject(
        scope,
        repo.state.dataForScope(scope).projects.single.copyWith(phases: []),
      );
      final operations = await repo.database.rows(
        'SELECT request FROM outbox ORDER BY sequence',
      );
      expect(
        operations
            .map((row) => (jsonDecode(row['request'] as String) as Map)['type'])
            .toList(),
        ['task', 'task', 'project'],
      );
      expect(
        repo.state
            .dataForScope(scope)
            .tasks
            .every((task) => task.phaseId == null),
        isTrue,
      );
      expect(
        repo.state
            .dataForScope(scope)
            .tasks
            .map((task) => task.estimateMinutes)
            .toSet(),
        {30, 60},
      );
      expect(
        (await repo.database.rows(
          'SELECT payload FROM finance_records WHERE id=?',
          [costId],
        )).single['payload'],
        cost,
      );
      await repo.syncNow();
      expect(repo.state.pendingCount, 0);
      expect(repo.state.conflicts, isEmpty);
    },
  );
}
