import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/local_spaces_repository.dart';
import 'package:kanban/organizer/data/organizer_repository.dart';
import 'package:kanban/organizer/data/sqlite_organizer_storage.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:kanban/organizer/domain/local_space_models.dart';

class _HookedDatabase extends CollaborationDatabase {
  _HookedDatabase() : super(NativeDatabase.memory());

  Future<void> Function(String, List<Object?>)? afterRows;
  Future<void> Function(String, List<Object?>)? afterExecute;

  @override
  Future<List<Map<String, dynamic>>> rows(
    String sql, [
    List<Object?> args = const [],
  ]) async {
    final result = await super.rows(sql, args);
    await afterRows?.call(sql, args);
    return result;
  }

  @override
  Future<void> execute(String sql, [List<Object?> args = const []]) async {
    await super.execute(sql, args);
    await afterExecute?.call(sql, args);
  }
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  const taskId = '11111111-1111-4111-a111-111111111111';
  late _HookedDatabase db;
  late LocalSpacesRepository spaces;
  late LocalSpace target;
  late LocalSpace sibling;

  Future<void> seed(String workspace, String title) async {
    final storage = SqliteOrganizerStorage(db, workspaceId: workspace);
    await storage.initialize();
    final repo = OrganizerRepository(storage, idGenerator: () => taskId);
    try {
      await repo.initialize();
      await repo.createTask(title: title);
    } finally {
      await repo.close();
    }
  }

  Future<List<Map<String, dynamic>>> records() =>
      db.rows('SELECT * FROM personal_records ORDER BY workspace,id');

  Future<bool> completed(String workspace) async {
    final rows = await db.rows(
      'SELECT payload FROM personal_records WHERE workspace=? AND id=?',
      [workspace, taskId],
    );
    return (jsonDecode(rows.single['payload'] as String)
            as Map<String, dynamic>)['isCompleted']
        as bool;
  }

  setUp(() async {
    db = _HookedDatabase();
    await SqliteOrganizerStorage(db).initialize();
    spaces = LocalSpacesRepository(db);
    target = await spaces.createSpace(
      kind: LocalSpaceKind.household,
      name: 'Nonselected household',
    );
    sibling = await spaces.createSpace(
      kind: LocalSpaceKind.organization,
      name: 'Other source',
    );
    await seed('local', 'Personal same ID');
    await seed(target.id, 'Target same ID');
    await seed(sibling.id, 'Sibling same ID');
  });

  tearDown(() async {
    db.afterRows = null;
    db.afterExecute = null;
    await db.close();
  });

  test(
    'completion and reopening target the nonselected SQLite source only',
    () async {
      final before = await records();
      final identity = db.personalIdentityGeneration;
      expect(db.selectedLocalWorkspaceId, 'local');
      await spaces.setTaskCompleted(
        target.id,
        taskId,
        true,
        expectedWorkspaceKey: target.id,
      );
      expect(await completed(target.id), true);
      expect(await completed('local'), false);
      expect(await completed(sibling.id), false);
      expect(
        (await records()).where((r) => r['workspace'] != target.id),
        before.where((r) => r['workspace'] != target.id),
      );
      await spaces.setTaskCompleted(
        target.id,
        taskId,
        false,
        expectedWorkspaceKey: target.id,
      );
      expect(await completed(target.id), false);
      expect(db.selectedLocalWorkspaceId, 'local');
      expect(db.personalIdentityGeneration, identity);
      expect(
        await db.rows(
          "SELECT * FROM local_meta WHERE name='selected_local_space'",
        ),
        isEmpty,
      );
    },
  );

  test(
    'wrong captured workspace cannot change the same ID in another source',
    () async {
      final before = await records();
      await expectLater(
        spaces.setTaskCompleted(
          sibling.id,
          taskId,
          true,
          expectedWorkspaceKey: target.id,
        ),
        throwsA(isA<OrganizerConflictException>()),
      );
      expect(await records(), before);
    },
  );

  for (final state in ['archived', 'bound']) {
    test('$state target denies completion without changing any task', () async {
      final before = await records();
      final value = target.toJson();
      if (state == 'archived') {
        value['archived'] = true;
      } else {
        value['binding'] = {
          'partition': 'another-account',
          'scopeId': target.id,
        };
      }
      await db.execute('UPDATE local_spaces SET data=? WHERE id=?', [
        jsonEncode(value),
        target.id,
      ]);
      await expectLater(
        spaces.setTaskCompleted(
          target.id,
          taskId,
          true,
          expectedWorkspaceKey: target.id,
        ),
        throwsA(isA<OrganizerConflictException>()),
      );
      expect(await records(), before);
      expect(await db.rows('SELECT * FROM outbox'), isEmpty);
    });
  }

  for (final state in ['archived', 'bound']) {
    test(
      'late $state change is rechecked after the captured source read',
      () async {
        final before = await records();
        final entered = Completer<void>();
        final release = Completer<void>();
        db.afterRows = (sql, args) async {
          if (sql == 'SELECT data FROM local_spaces WHERE id=?' &&
              args.single == target.id) {
            db.afterRows = null;
            entered.complete();
            await release.future;
          }
        };
        final write = spaces.setTaskCompleted(
          target.id,
          taskId,
          true,
          expectedWorkspaceKey: target.id,
        );
        final rejected = expectLater(
          write,
          throwsA(isA<OrganizerConflictException>()),
        );
        await entered.future;
        final value = target.toJson();
        if (state == 'archived') {
          value['archived'] = true;
        } else {
          value['binding'] = {'partition': 'new-account', 'scopeId': target.id};
        }
        await db.execute('UPDATE local_spaces SET data=? WHERE id=?', [
          jsonEncode(value),
          target.id,
        ]);
        release.complete();
        await rejected;
        expect(await records(), before);
      },
    );
  }

  for (final lost in ['identity', 'visibility']) {
    test(
      'late $lost change rolls back a task row already written inside SQLite',
      () async {
        final before = await records();
        final generations = await db.rows(
          "SELECT * FROM local_meta WHERE name='organizer_generation'",
        );
        var visible = true;
        var injected = false;
        db.afterExecute = (sql, args) async {
          if (sql.startsWith('INSERT INTO personal_records(') &&
              args[0] == target.id &&
              args[1] == taskId) {
            injected = true;
            db.afterExecute = null;
            if (lost == 'identity') {
              db.activatePersonal(
                AccountSession(
                  serverUrl: 'https://new-account.invalid',
                  serverId: 'new-server',
                  accountId: 'new-account',
                  userId: 2,
                  username: 'new-account',
                  displayName: 'New account',
                  deviceId: 'new-device',
                  expiresAt: DateTime.utc(2030),
                ),
              );
            } else {
              visible = false;
            }
          }
        };
        await expectLater(
          spaces.setTaskCompleted(
            target.id,
            taskId,
            true,
            expectedWorkspaceKey: target.id,
            stillVisible: () => visible,
          ),
          throwsA(isA<OrganizerConflictException>()),
        );
        expect(injected, true);
        expect(await records(), before);
        expect(
          await db.rows(
            "SELECT * FROM local_meta WHERE name='organizer_generation'",
          ),
          generations,
        );
        expect(db.selectedLocalWorkspaceId, 'local');
      },
    );
  }

  test(
    'private workspace IDs cannot masquerade as device-owned sources',
    () async {
      const privateWorkspace = 'private:another-account';
      await db.execute('INSERT INTO personal_workspaces(id) VALUES(?)', [
        privateWorkspace,
      ]);
      await db.execute(
        'INSERT INTO personal_records(workspace,id,type,payload) SELECT ?,id,type,payload FROM personal_records WHERE workspace=?',
        [privateWorkspace, target.id],
      );
      final before = await records();
      await expectLater(
        spaces.setTaskCompleted(
          privateWorkspace,
          taskId,
          true,
          expectedWorkspaceKey: privateWorkspace,
        ),
        throwsA(isA<OrganizerConflictException>()),
      );
      expect(await records(), before);
      expect(await db.rows('SELECT * FROM outbox'), isEmpty);
    },
  );

  test('missing target record never falls back to the selected copy', () async {
    final empty = await spaces.createSpace(
      kind: LocalSpaceKind.household,
      name: 'Empty target',
    );
    final before = await records();
    await expectLater(
      spaces.setTaskCompleted(
        empty.id,
        taskId,
        true,
        expectedWorkspaceKey: empty.id,
      ),
      throwsA(isA<OrganizerConflictException>()),
    );
    expect(await records(), before);
    expect(db.selectedLocalWorkspaceId, 'local');
  });

  const privateTaskId = '22222222-2222-4222-a222-222222222222';
  const privateScopeId = '33333333-3333-4333-a333-333333333333';
  final profile = AccountSession(
    serverUrl: 'https://private.invalid',
    serverId: 'private-server',
    accountId: 'owner',
    userId: 1,
    username: 'owner',
    displayName: 'Owner',
    deviceId: 'owner-device',
    expiresAt: DateTime.utc(2030),
  );

  Future<String> bindPrivate({SharedRole role = SharedRole.owner}) async {
    final partition = profile.partition,
        workspace = 'private:${profile.partition}';
    await db.execute('INSERT INTO accounts(partition,profile) VALUES(?,?)', [
      partition,
      jsonEncode(profile.toJson()),
    ]);
    await db.execute('INSERT INTO scopes(partition,id,data) VALUES(?,?,?)', [
      partition,
      privateScopeId,
      jsonEncode(
        SharedScope(
          id: privateScopeId,
          name: 'Private Personal',
          kind: SharedScopeKind.personal,
          role: role,
        ).toJson(),
      ),
    ]);
    await db.execute(
      'INSERT INTO personal_workspaces(id,partition,scope_id) VALUES(?,?,?)',
      [workspace, partition, privateScopeId],
    );
    final payload =
        jsonDecode(
              (await db.rows(
                    'SELECT payload FROM personal_records WHERE workspace=? AND id=?',
                    ['local', taskId],
                  )).single['payload']
                  as String,
            )
            as Map<String, dynamic>;
    await queuePrivateRecord(
      db,
      {'id': workspace, 'partition': partition, 'scope_id': privateScopeId},
      privateTaskId,
      'task',
      {...payload, 'id': privateTaskId, 'title': 'Private task'},
    );
    await db.execute('DELETE FROM outbox');
    db.activatePersonal(profile);
    await spaces.selectSpace(target.id);
    return workspace;
  }

  test(
    'nonselected bound Personal completes privately and queues exact source',
    () async {
      final workspace = await bindPrivate();
      final before = await records();
      final identity = db.personalIdentityGeneration;
      await spaces.setTaskCompleted(
        'local',
        privateTaskId,
        true,
        expectedWorkspaceKey: workspace,
      );
      final row = (await db.rows('SELECT * FROM records')).single;
      expect(row['partition'], profile.partition);
      expect(row['scope_id'], privateScopeId);
      expect(
        (jsonDecode(row['payload'] as String) as Map)['isCompleted'],
        true,
      );
      final queued = (await db.rows('SELECT * FROM outbox')).single;
      expect(queued['partition'], profile.partition);
      expect(queued['scope_id'], privateScopeId);
      expect(queued['record_id'], privateTaskId);
      expect(await records(), before);
      expect(db.selectedLocalWorkspaceId, target.id);
      expect(db.personalIdentityGeneration, identity);
      expect(
        (await SqliteOrganizerStorage(db, workspaceId: 'local').read()).tasks
            .singleWhere((task) => task.id == privateTaskId)
            .isCompleted,
        true,
      );
    },
  );

  test('late private identity change rolls back record and outbox', () async {
    final workspace = await bindPrivate();
    final before = await db.rows('SELECT * FROM records');
    final local = await records();
    final generations = await db.rows(
      "SELECT * FROM local_meta WHERE name='organizer_generation'",
    );
    var injected = false;
    db.afterExecute = (sql, args) async {
      if (sql.startsWith('INSERT INTO outbox(')) {
        db.afterExecute = null;
        injected = true;
        db.activatePersonal(null);
      }
    };
    await expectLater(
      spaces.setTaskCompleted(
        'local',
        privateTaskId,
        true,
        expectedWorkspaceKey: workspace,
      ),
      throwsA(isA<OrganizerConflictException>()),
    );
    expect(injected, true);
    expect(await db.rows('SELECT * FROM records'), before);
    expect(await db.rows('SELECT * FROM outbox'), isEmpty);
    expect(await records(), local);
    expect(
      await db.rows(
        "SELECT * FROM local_meta WHERE name='organizer_generation'",
      ),
      generations,
    );
    expect(db.selectedLocalWorkspaceId, target.id);
  });

  test(
    'bound Personal viewer cannot complete even without a UI callback',
    () async {
      final workspace = await bindPrivate(role: SharedRole.viewer);
      final before = await db.rows('SELECT * FROM records');
      await expectLater(
        spaces.setTaskCompleted(
          'local',
          privateTaskId,
          true,
          expectedWorkspaceKey: workspace,
        ),
        throwsA(isA<CollaborationException>()),
      );
      expect(await db.rows('SELECT * FROM records'), before);
      expect(await db.rows('SELECT * FROM outbox'), isEmpty);
    },
  );

  test('private expected key requires an enabled active binding', () async {
    final workspace = await bindPrivate();
    await db.execute('UPDATE personal_workspaces SET enabled=0 WHERE id=?', [
      workspace,
    ]);
    final before = await records();
    await expectLater(
      spaces.setTaskCompleted(
        'local',
        taskId,
        true,
        expectedWorkspaceKey: workspace,
      ),
      throwsA(isA<OrganizerConflictException>()),
    );
    expect(await records(), before);
    expect(await db.rows('SELECT * FROM outbox'), isEmpty);
  });

  test('already hidden source is rejected before any mutation', () async {
    final before = await records();
    await expectLater(
      spaces.setTaskCompleted(
        target.id,
        taskId,
        true,
        expectedWorkspaceKey: target.id,
        stillVisible: () => false,
      ),
      throwsA(isA<CollaborationException>()),
    );
    expect(await records(), before);
  });
}
