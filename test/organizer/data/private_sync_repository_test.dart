import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/data/organizer_repository.dart';
import 'package:kanban/organizer/data/organizer_storage.dart';
import 'package:kanban/organizer/data/sqlite_organizer_storage.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'collaboration_repository_test.dart' show FakeServer, MemorySessionStore;
import 'private_sync_test_support.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  Future<
    ({
      CollaborationDatabase db,
      SqliteOrganizerStorage storage,
      OrganizerRepository personal,
      CollaborationRepository shared,
      MemorySessionStore session,
    })
  >
  client(
    PersonalTransport transport, {
    File? file,
    MemorySessionStore? session,
  }) async {
    final db = CollaborationDatabase(
      file == null ? NativeDatabase.memory() : NativeDatabase(file),
    );
    final storage = SqliteOrganizerStorage(db);
    await storage.initialize();
    final personal = OrganizerRepository(storage);
    await personal.initialize();
    final store = session ?? MemorySessionStore();
    final shared = CollaborationRepository(
      db,
      transport,
      store,
      ownsDatabase: false,
    );
    await shared.initialize();
    addTearDown(() async {
      await personal.close();
      await shared.close();
      await db.close();
    });
    return (
      db: db,
      storage: storage,
      personal: personal,
      shared: shared,
      session: store,
    );
  }

  Future<void> login(CollaborationRepository repo, [String user = 'alice']) =>
      repo.login(
        serverUrl: 'https://test.invalid',
        username: user,
        password: 'test',
      );
  test(
    'real Hive migration abort/retry/reopen preserves original frame and rejects newer or corrupt input',
    () async {
      final dir = await Directory.systemTemp.createTemp('real-hive-migration-');
      addTearDown(() => dir.delete(recursive: true));
      final hive = await HiveOrganizerStorage.open(directory: dir.path),
          repo = OrganizerRepository(hive);
      await repo.initialize();
      await repo.createTask(title: 'Actual Hive record');
      final original = OrganizerBackupCodec.encode(repo.snapshot);
      await repo.close();
      final file = File('${dir.path}/sqlite.db'),
          db = CollaborationDatabase(NativeDatabase(file));
      await db.rows('SELECT name FROM local_meta');
      await db.execute(
        "CREATE TRIGGER fail_hive BEFORE INSERT ON personal_records BEGIN SELECT RAISE(ABORT,'test abort'); END",
      );
      final storage = SqliteOrganizerStorage(
        db,
        legacyFactory: () => HiveOrganizerStorage.open(directory: dir.path),
      );
      await expectLater(storage.initialize(), throwsA(anything));
      expect(await db.rows('SELECT * FROM personal_workspaces'), isEmpty);
      expect(await db.rows('SELECT * FROM personal_records'), isEmpty);
      await db.execute('DROP TRIGGER fail_hive');
      await storage.initialize();
      await db.close();
      final reopened = CollaborationDatabase(NativeDatabase(file));
      expect(
        (await SqliteOrganizerStorage(reopened).read()).tasks.single.title,
        'Actual Hive record',
      );
      await reopened.close();
      final retained = await HiveOrganizerStorage.open(directory: dir.path);
      expect(OrganizerBackupCodec.encode(await retained.read()), original);
      await retained.close();
      for (final frame in [
        'corrupt-json',
        jsonEncode({
          'format': 'vsakdan-personal-backup',
          'schemaVersion': 999,
          'workspace': 'personal',
          'data': {},
        }),
      ]) {
        final box = await Hive.openBox<String>(
          HiveOrganizerStorage.boxName,
          path: dir.path,
        );
        await box.put('committed_snapshot', frame);
        await box.close();
        final failed = CollaborationDatabase(NativeDatabase.memory());
        await expectLater(
          SqliteOrganizerStorage(
            failed,
            legacyFactory: () => HiveOrganizerStorage.open(directory: dir.path),
          ).initialize(),
          throwsA(isA<FormatException>()),
        );
        expect(await failed.rows('SELECT * FROM personal_workspaces'), isEmpty);
        await failed.close();
        final untouched = await Hive.openBox<String>(
          HiveOrganizerStorage.boxName,
          path: dir.path,
        );
        expect(untouched.get('committed_snapshot'), frame);
        await untouched.close();
      }
    },
  );
  test(
    'Hive migration rows and marker atomic, retains source; stale other connection cannot overwrite',
    () async {
      final directory = await Directory.systemTemp.createTemp('personal-cas-');
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/local.sqlite');
      final now = DateTime.utc(2026, 10, 5),
          legacy = LegacyMemory(
            OrganizerSnapshot(
              revision: 7,
              projects: [
                LocalProject(
                  id: 'old-non-uuid',
                  title: 'Original',
                  description: '',
                  createdAt: now,
                  updatedAt: now,
                ),
              ],
            ),
          );
      final db = CollaborationDatabase(NativeDatabase(file));
      addTearDown(db.close);
      final storage = SqliteOrganizerStorage(
        db,
        legacyFactory: () async => legacy,
      );
      await storage.initialize();
      expect(legacy.closed, true);
      expect(legacy.snapshot.projects.single.title, 'Original');
      final stale = await storage.read();
      final other = CollaborationDatabase(NativeDatabase(file));
      addTearDown(other.close);
      final otherStorage = SqliteOrganizerStorage(other);
      await otherStorage.initialize();
      await otherStorage.write(
        stale.copyWith(
          revision: 8,
          projects: [stale.projects.single.copyWith(title: 'Other writer')],
        ),
      );
      await expectLater(
        storage.write(stale.copyWith(revision: 8, projects: [])),
        throwsA(isA<OrganizerConflictException>()),
      );
      expect((await storage.read()).projects.single.title, 'Other writer');
      expect(
        (await db.rows(
          'SELECT migration_snapshot FROM personal_workspaces',
        )).single['migration_snapshot'],
        isNotNull,
      );
    },
  );
  test(
    'explicit private opt-in preserves links, finance and legacy IDs, no upload by login; two SQLite clients sync',
    () async {
      final transport = PersonalTransport(FakeServer());
      final a = await client(transport), b = await client(transport);
      await a.personal.createProject(title: 'Local project');
      final project = a.personal.snapshot.projects.single.id;
      await a.personal.createTask(title: 'Task', projectId: project);
      await a.personal.createFinanceEntry(
        title: 'Expense',
        amountMinor: 1299,
        currency: 'EUR',
        kind: FinanceEntryKind.expense,
        occurredAt: DateTime.utc(2026),
        projectId: project,
      );
      await login(a.shared);
      expect(transport.privateScopes, isEmpty);
      expect(transport.server.records, isEmpty);
      await a.personal.reload();
      final preview = await a.shared.previewPrivateSync();
      expect(preview.recordCounts['financeEntries'], 1);
      await a.shared.enablePrivateSync(expectedRevision: preview.revision);
      await a.personal.reload();
      expect(a.personal.snapshot.financeEntries.single.amountMinor, 1299);
      expect(a.personal.snapshot.tasks.single.projectId, project);
      await login(b.shared);
      final bPreview = await b.shared.previewPrivateSync();
      await b.shared.enablePrivateSync(expectedRevision: bPreview.revision);
      await b.personal.reload();
      expect(b.personal.snapshot.projects.single.title, 'Local project');
      expect(b.personal.snapshot.financeEntries.single.projectId, project);
      transport.offline = true;
      await a.shared.pausePrivateSync();
      await a.personal.updateTask(
        a.personal.snapshot.tasks.single.copyWith(title: 'Offline paused'),
      );
      expect((await a.db.rows('SELECT * FROM outbox')).length, 1);
      transport.offline = false;
      await a.shared.syncNow();
      expect(
        transport.server.records.values.single.values
            .where((r) => r['type'] == 'task')
            .single['payload'],
        isNot(containsPair('title', 'Offline paused')),
      );
      await a.shared.resumePrivateSync();
      await b.shared.syncNow();
      await b.personal.reload();
      expect(b.personal.snapshot.tasks.single.title, 'Offline paused');
    },
  );
  test(
    'offline project + finance create then delete waits immutable financial unlink ACK',
    () async {
      final transport = PersonalTransport(FakeServer());
      // This test uses its own transport and account to inspect wire dependencies.
      final c = await client(transport);
      await login(c.shared);
      await c.personal.reload();
      await c.shared.enablePrivateSync(
        expectedRevision: (await c.shared.previewPrivateSync()).revision,
      );
      await c.personal.reload();
      transport.offline = true;
      await c.personal.createProject(title: 'Temporary');
      final id = c.personal.snapshot.projects.single.id;
      await c.personal.createFinanceEntry(
        title: 'Keep expense',
        amountMinor: 400,
        currency: 'EUR',
        kind: FinanceEntryKind.expense,
        occurredAt: DateTime.utc(2026),
        projectId: id,
      );
      await c.personal.deleteProject(id);
      final request = await c.db.rows(
        'SELECT request FROM finance_outbox ORDER BY sequence',
      );
      expect(
        jsonDecode(request.first['request'] as String)['payload']['projectId'],
        id,
      );
      transport.offline = false;
      await c.shared.syncNow();
      await c.shared.syncNow();
      await c.personal.reload();
      expect(c.shared.state.lastError, isNull);
      expect(await c.db.rows('SELECT * FROM outbox'), isEmpty);
      expect(await c.db.rows('SELECT * FROM finance_outbox'), isEmpty);
      expect(c.personal.snapshot.projects, isEmpty);
      expect(c.personal.snapshot.financeEntries.single.projectId, isNull);
    },
  );
  test(
    'known revoked session never reopens private after restart; observer hides old snapshot',
    () async {
      final transport = PersonalTransport(FakeServer());
      final directory = await Directory.systemTemp.createTemp(
        'revoked-reopen-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/client.sqlite');
      final c = await client(transport, file: file);
      await login(c.shared);
      await c.personal.createTask(title: 'Private');
      await c.personal.reload();
      await c.shared.enablePrivateSync(
        expectedRevision: (await c.shared.previewPrivateSync()).revision,
      );
      await c.personal.reload();
      expect(c.personal.snapshot.tasks.single.title, 'Private');
      transport.server.tokens.clear();
      await c.shared.syncNow();
      await c.personal.reload();
      expect(c.personal.snapshot.tasks, isEmpty);
      await c.personal.close();
      await c.shared.close();
      await c.db.close();
      final reopened = await client(transport, file: file, session: c.session);
      expect(reopened.shared.state.sessionInvalid, true);
      expect(reopened.db.personalProfile, isNull);
      expect((await reopened.storage.read()).tasks, isEmpty);
    },
  );
  test(
    'late public reset cannot invalidate new account; bad email step-up does not revoke session',
    () async {
      final transport = PersonalTransport(FakeServer()),
          a = await client(transport);
      await login(a.shared);
      final entered = Completer<void>(), release = Completer<void>();
      transport.beforeReset = () async {
        entered.complete();
        await release.future;
      };
      final reset = a.shared.confirmPasswordReset(
        serverUrl: 'https://test.invalid',
        token: 'test',
        password: 'new password',
      );
      await entered.future;
      await login(a.shared, 'bob');
      release.complete();
      await reset;
      expect(a.shared.state.session!.username, 'bob');
      expect(a.shared.state.sessionInvalid, false);
      await expectLater(
        a.shared.requestEmailVerification(
          email: 'x@test.invalid',
          password: 'bad',
        ),
        throwsA(isA<CollaborationException>()),
      );
      expect(a.shared.state.sessionInvalid, false);
    },
  );
  test(
    'migration and private mutation SQL abort roll back every row and immutable operation',
    () async {
      final db = CollaborationDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.rows('SELECT name FROM local_meta');
      final now = DateTime.utc(2026),
          original = OrganizerSnapshot(
            projects: [
              LocalProject(
                id: 'legacy',
                title: 'Retained',
                description: '',
                createdAt: now,
                updatedAt: now,
              ),
            ],
          );
      await db.execute(
        "CREATE TRIGGER fail_import BEFORE INSERT ON personal_records BEGIN SELECT RAISE(ABORT,'test rollback'); END",
      );
      final storage = SqliteOrganizerStorage(
        db,
        legacyFactory: () async => LegacyMemory(original),
      );
      await expectLater(storage.initialize(), throwsA(anything));
      expect(await db.rows('SELECT * FROM personal_workspaces'), isEmpty);
      await db.execute('DROP TRIGGER fail_import');
      await storage.initialize();
      expect((await storage.read()).projects.single.id, 'legacy');
      final transport = PersonalTransport(FakeServer()),
          c = await client(transport);
      await login(c.shared);
      await c.personal.reload();
      await c.shared.enablePrivateSync(
        expectedRevision: (await c.shared.previewPrivateSync()).revision,
      );
      await c.personal.reload();
      await c.db.execute(
        "CREATE TRIGGER fail_outbox BEFORE INSERT ON outbox BEGIN SELECT RAISE(ABORT,'test rollback'); END",
      );
      await expectLater(
        c.personal.createShoppingList(title: 'Must rollback'),
        throwsA(anything),
      );
      expect(await c.db.rows('SELECT * FROM outbox'), isEmpty);
      expect(await c.db.rows('SELECT * FROM records'), isEmpty);
    },
  );
  test(
    'observable reload failure clears old private snapshot and emits error',
    () async {
      final storage = FailingObservableStorage(),
          repo = OrganizerRepository(storage);
      await repo.initialize();
      final errors = <Object>[];
      final sub = repo.changes.listen(
        (_) {},
        onError: (Object e) {
          errors.add(e);
        },
      );
      storage.fail = true;
      storage.events.add(null);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(errors, isNotEmpty);
      expect(() => repo.snapshot, throwsStateError);
      await sub.cancel();
      await repo.close();
    },
  );
  test(
    'private legacy task server reference maps to exact personal ID after authorized navigation',
    () async {
      final transport = PersonalTransport(FakeServer()),
          c = await client(transport);
      final now = DateTime.utc(2026),
          task = LocalTask(
            id: 'legacy-task-id',
            title: 'Mapped',
            notes: '',
            projectId: null,
            dueAt: null,
            isCompleted: false,
            createdAt: now,
            updatedAt: now,
          );
      final initial = await c.storage.read();
      await c.storage.write(
        initial.copyWith(revision: initial.revision + 1, tasks: [task]),
      );
      await c.personal.reload();
      await login(c.shared);
      await c.shared.enablePrivateSync(
        expectedRevision: (await c.shared.previewPrivateSync()).revision,
      );
      await c.personal.reload();
      final remote =
          (await c.db.rows(
                'SELECT remote_id FROM personal_record_map WHERE id=?',
                ['legacy-task-id'],
              )).single['remote_id']
              as String;
      final profile = c.shared.state.session!;
      final target = NotificationTarget(
        serverUrl: profile.serverUrl,
        serverId: profile.serverId,
        accountId: profile.accountId,
        scopeId: c.shared.state.privateSync.scopeId,
        records: [NotificationRecordTarget(type: 'task', recordId: remote)],
      );
      final result = await c.shared.openNotificationTarget(target);
      expect(result.status, NotificationOpenStatus.available);
      expect(result.target.records.single.recordId, remote);
      expect(c.shared.state.personalRecordId(remote), 'legacy-task-id');
      expect(c.personal.snapshot.tasks.single.id, 'legacy-task-id');
    },
  );
}

class FailingObservableStorage
    implements OrganizerStorage, ObservableOrganizerStorage {
  final events = StreamController<void>.broadcast();
  bool fail = false;
  @override
  Stream<void> get changes => events.stream;
  @override
  Future<OrganizerSnapshot> read() async {
    if (fail) throw StateError('identity changed');
    return OrganizerSnapshot();
  }

  @override
  Future<void> write(OrganizerSnapshot value) async {}
  @override
  Future<void> close() => events.close();
}
