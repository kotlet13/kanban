import 'dart:async';
import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/data/garden_repository.dart';
import 'package:kanban/organizer/data/garden_storage.dart';
import 'package:kanban/organizer/data/idea_repository.dart';
import 'package:kanban/organizer/data/idea_storage.dart';
import 'package:kanban/organizer/data/organizer_repository.dart';
import 'package:kanban/organizer/data/sqlite_organizer_storage.dart';
import 'package:kanban/organizer/domain/garden_models.dart';
import 'package:kanban/organizer/domain/idea_models.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';
import '../support/synthetic_content_route_guard.dart';
import 'collaboration_repository_test.dart'
    show FakeServer, FakeTransport, MemorySessionStore;

class _Transport extends FakeTransport {
  _Transport(super.server);
  final operations = <String>[];
  AccountSession? account;
  int probes = 0;
  Future<void> Function()? beforeProbe;
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
      probes++;
      await beforeProbe?.call();
      return {
        'version': 1,
        'serverId': account!.serverId,
        'accountId': account!.accountId,
        'deviceId': account!.deviceId,
        'cursor': 'stable',
        'changed': false,
        'resetRequired': false,
        'hasMore': false,
        'accountDomains': <String>[],
        'scopes': <Object>[],
      };
    }
    final result = await super.call(
      serverUrl: serverUrl,
      operation: operation.replaceFirst('sync6.', 'sync.'),
      params: params,
      token: token,
      allowLocalHttp: allowLocalHttp,
    );
    return operation == 'capabilities'
        ? {
            ...result,
            'recordContractVersions': [1, 2, 3, 4, 5, 6],
            'accountChangeVersions': [1],
            'features': <String, dynamic>{
              ...Map<String, dynamic>.from(result['features'] as Map),
              'ideas': true,
              'gardens': true,
            },
          }
        : result;
  }
}

class _Fixture {
  final db = CollaborationDatabase(NativeDatabase.memory());
  final sessions = MemorySessionStore();
  final transport = _Transport(FakeServer());
  late final repo = CollaborationRepository(
    db,
    transport,
    sessions,
    ownsDatabase: false,
    contentRouteGuard: const SyntheticContentRouteGuard(),
  );
  late String scope;
  AccountSession get profile => repo.state.session!;
  Future<void> initialize() async {
    await repo.initialize();
    await repo.login(
      serverUrl: 'https://synthetic.invalid/',
      username: 'alice',
      password: 'synthetic',
    );
    scope = await repo.createScope('Work wake');
    transport.account = profile;
    transport.operations.clear();
  }

  Future<void> close() async {
    await repo.close();
    await db.close();
  }
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  Future<void> flush() async {
    for (var i = 0; i < 8; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<_Fixture> fixture() async {
    final f = _Fixture();
    addTearDown(f.close);
    await f.initialize();
    return f;
  }

  final now = DateTime.utc(2026, 10, 24);
  IdeaBoard idea(String id) =>
      IdeaBoard(id: id, title: 'Idea', createdAt: now, updatedAt: now);
  Garden garden(String id) =>
      Garden(id: id, name: 'Garden', notes: '', createdAt: now, updatedAt: now);

  test(
    'local wake: shared idea commits once; equal read and draft stay silent',
    () async {
      final f = await fixture();
      final storage = SharedIdeaStorage(f.repo, f.profile.partition, f.scope);
      final seen = <LocalSyncWorkIdentity>[];
      final sub = f.db.committedLocalWork.listen(seen.add);
      addTearDown(sub.cancel);
      final previous = await storage.read();
      await f.db.transaction(() async {
        await storage.write(
          IdeaSnapshot(boards: [idea(newSharedId()), idea(newSharedId())]),
          expectedRevision: previous.revision,
        );
        await flush();
        expect(seen, isEmpty);
      });
      await flush();
      expect(seen, hasLength(1));
      expect(
        (await f.db.rows('SELECT * FROM outbox WHERE partition=?', [
          f.profile.partition,
        ])).length,
        2,
      );
      final saved = await storage.read();
      await storage.write(saved, expectedRevision: saved.revision);
      final ideas = IdeaRepository(storage);
      await ideas.initialize();
      await ideas.saveDraft(saved.boards.first, base: saved.boards.first);
      await ideas.close();
      await flush();
      expect(seen, hasLength(1));
      expect(f.transport.operations, isEmpty);
    },
  );

  test(
    'local wake: shared garden commits once and equal snapshot stays silent',
    () async {
      final f = await fixture();
      final storage = SharedGardenStorage(f.repo, f.profile.partition, f.scope);
      final seen = <LocalSyncWorkIdentity>[];
      final sub = f.db.committedLocalWork.listen(seen.add);
      addTearDown(sub.cancel);
      final previous = await storage.read();
      await storage.write(
        GardenSnapshot(gardens: [garden(newSharedId())]),
        expectedRevision: previous.revision,
      );
      await flush();
      expect(seen, hasLength(1));
      expect(
        (await f.db.rows('SELECT * FROM outbox WHERE partition=?', [
          f.profile.partition,
        ])).length,
        1,
      );
      final saved = await storage.read();
      await storage.write(saved, expectedRevision: saved.revision);
      await flush();
      expect(seen, hasLength(1));
      expect(f.transport.operations, isEmpty);
    },
  );

  test(
    'local wake: outer rollback drops real shared operation and event',
    () async {
      final f = await fixture();
      final storage = SharedIdeaStorage(f.repo, f.profile.partition, f.scope);
      final seen = <LocalSyncWorkIdentity>[];
      final sub = f.db.committedLocalWork.listen(seen.add);
      addTearDown(sub.cancel);
      final previous = await storage.read();
      await expectLater(
        f.db.transaction(() async {
          await storage.write(
            IdeaSnapshot(boards: [idea(newSharedId())]),
            expectedRevision: previous.revision,
          );
          throw StateError('later outer failure');
        }),
        throwsStateError,
      );
      await flush();
      expect(seen, isEmpty);
      expect(await f.db.rows('SELECT * FROM outbox'), isEmpty);
      expect((await storage.read()).boards, isEmpty);
    },
  );

  test(
    'local wake: caught nested rollback cannot leak into successful parent',
    () async {
      final f = await fixture();
      final seen = <LocalSyncWorkIdentity>[];
      final sub = f.db.committedLocalWork.listen(seen.add);
      addTearDown(sub.cancel);
      final identity = f.db.captureLocalWorkIdentity(f.profile)!;
      await f.db.transaction(() async {
        try {
          await f.db.transaction(() async {
            await f.db.execute(
              "INSERT INTO local_meta(name,value) VALUES('nested-work','1')",
            );
            f.db.localWorkQueued(identity);
            throw StateError('savepoint failure');
          }, requireNew: true);
        } on StateError {
          /* Parent is deliberately permitted to commit. */
        }
        await f.db.execute(
          "INSERT INTO local_meta(name,value) VALUES('parent-kept','1')",
        );
      });
      await flush();
      expect(seen, isEmpty);
      expect(
        await f.db.rows("SELECT name FROM local_meta WHERE name='nested-work'"),
        isEmpty,
      );
      expect(
        await f.db.rows("SELECT name FROM local_meta WHERE name='parent-kept'"),
        hasLength(1),
      );
    },
  );

  test(
    'local wake: connected personal actual outbox writes signal; no-op read and local reminder do not',
    () async {
      final f = await fixture();
      final workspace = 'private:${f.profile.partition}';
      await f.db.execute(
        'INSERT INTO personal_workspaces(id,partition,scope_id) VALUES(?,?,?)',
        [workspace, f.profile.partition, f.scope],
      );
      final storage = SqliteOrganizerStorage(f.db);
      await storage.initialize();
      final organizer = OrganizerRepository(storage);
      await organizer.initialize();
      addTearDown(organizer.close);
      final seen = <LocalSyncWorkIdentity>[];
      final sub = f.db.committedLocalWork.listen(seen.add);
      addTearDown(sub.cancel);
      await organizer.createTask(title: 'Private');
      await flush();
      expect(seen, hasLength(1));
      expect(
        await f.db.rows('SELECT * FROM outbox WHERE partition=?', [
          f.profile.partition,
        ]),
        hasLength(1),
      );
      final saved = await storage.read();
      await storage.write(saved.copyWith(revision: saved.revision + 1));
      await organizer.refreshReminders();
      await storage.read();
      await flush();
      expect(seen, hasLength(1));
      expect(f.transport.operations, isEmpty);
    },
  );

  test(
    'local wake: accountless organizer ideas and garden never open transport or emit work',
    () async {
      final db = CollaborationDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final seen = <LocalSyncWorkIdentity>[];
      final sub = db.committedLocalWork.listen(seen.add);
      addTearDown(sub.cancel);
      final storage = SqliteOrganizerStorage(db);
      await storage.initialize();
      final organizer = OrganizerRepository(storage);
      final ideas = IdeaRepository(IdeaStorage(db));
      final gardens = GardenRepository(GardenStorage(db));
      addTearDown(organizer.close);
      addTearDown(ideas.close);
      addTearDown(gardens.close);
      await organizer.initialize();
      await ideas.initialize();
      await gardens.initialize();
      await organizer.createTask(title: 'Only local');
      await ideas.createBoard(title: 'Only local');
      await gardens.createGarden(name: 'Only local');
      await flush();
      expect(seen, isEmpty);
      expect(await db.rows('SELECT * FROM outbox'), isEmpty);
      // A local-only stack has no collaboration transport or account provider.
      expect(db.personalProfile, isNull);
    },
  );

  test(
    'local wake: binding switch fences delayed work but workspace switch preserves demand',
    () async {
      final f = await fixture();
      final seen = <LocalSyncWorkIdentity>[];
      final sub = f.db.committedLocalWork.listen(seen.add);
      addTearDown(sub.cancel);
      final old = f.db.captureLocalWorkIdentity(f.profile)!;
      await f.db.transaction(() async {
        f.db.localWorkQueued(old);
        f.db.activatePersonal(f.profile);
      });
      await flush();
      expect(seen, isEmpty);
      expect(f.db.isCurrentLocalWorkIdentity(old), isFalse);
      final fresh = f.db.captureLocalWorkIdentity(f.profile)!;
      await f.db.transaction(() async {
        f.db.localWorkQueued(fresh);
        f.db.activateLocalWorkspace('another-local');
      });
      await flush();
      expect(seen, [fresh]);
    },
  );

  test(
    'local wake: active provider latches busy and background demand without overlapping attempts',
    () async {
      final f = await fixture();
      final repo = f.repo;
      await f.db.execute('INSERT INTO local_meta(name,value) VALUES(?,?)', [
        'account_changes_v1:${f.profile.partition}:${f.profile.deviceId}',
        'stable',
      ]);
      final container = ProviderContainer(
        overrides: [
          collaborationRepositoryProvider.overrideWith((ref) async => repo),
        ],
      );
      var disposed = false;
      addTearDown(() {
        if (!disposed) container.dispose();
      });
      await container.read(collaborationProvider.future);
      await flush();
      expect(f.transport.probes, 1);
      final hold = Completer<void>();
      f.transport.beforeProbe = () => hold.future;
      Future<void> committed() => f.db.transaction(
        () async => f.db.localWorkQueued(
          f.db.captureLocalWorkIdentity(repo.state.session)!,
        ),
      );
      await committed();
      await flush();
      expect(f.transport.probes, 2);
      await committed();
      await flush();
      expect(f.transport.probes, 2);
      f.transport.beforeProbe = null;
      hold.complete();
      await flush();
      expect(f.transport.probes, 3);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await committed();
      await flush();
      expect(f.transport.probes, 3);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await flush();
      expect(f.transport.probes, 4);
      container.dispose();
      disposed = true;
      f.transport.operations.clear();
      await committed();
      await flush();
      expect(f.transport.probes, 4);
      expect(f.transport.operations, isEmpty);
    },
  );
}
