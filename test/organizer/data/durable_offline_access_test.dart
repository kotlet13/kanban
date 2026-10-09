import 'dart:io';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/data/device_session_store.dart';
import 'package:kanban/organizer/data/sqlite_organizer_storage.dart';
import 'package:kanban/organizer/data/organizer_repository.dart';
import 'package:kanban/organizer/data/portable_backup_repository.dart';
import 'package:kanban/organizer/data/local_spaces_repository.dart';
import 'package:kanban/organizer/domain/local_space_models.dart';
import 'package:kanban/organizer/domain/all_spaces_projection.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'collaboration_repository_test.dart'
    show FakeServer, FakeTransport, MemorySessionStore;
import 'private_sync_test_support.dart' show PersonalTransport;

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  test(
    'expired session after restart retains private and shared reads edits and backup without network',
    () async {
      final directory = await Directory.systemTemp.createTemp('jivie-offline-');
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/local.sqlite');
      var db = CollaborationDatabase(NativeDatabase(file));
      final store = MemorySessionStore(),
          transport = PersonalTransport(FakeServer());
      var storage = SqliteOrganizerStorage(db);
      await storage.initialize();
      var personal = OrganizerRepository(storage);
      await personal.initialize();
      addTearDown(() => personal.close());
      addTearDown(() => db.close());
      var repo = CollaborationRepository(
        db,
        transport,
        store,
        ownsDatabase: false,
      );
      await repo.initialize();
      await repo.login(
        serverUrl: 'https://example.test',
        username: 'alice',
        password: 'secret',
      );
      await repo.enablePrivateSync(
        expectedRevision: (await storage.read()).revision,
      );
      await personal.reload();
      await personal.createTask(title: 'Saved private');
      final scope = await repo.createScope('Shared');
      await repo.createTask(scopeId: scope, title: 'Saved shared');
      await repo.syncNow();
      final spaces = LocalSpacesRepository(db);
      final home = await spaces.createSpace(
        kind: LocalSpaceKind.household,
        name: 'Local household',
      );
      await spaces.selectSpace(home.id);
      await personal.reload();
      await personal.createTask(title: 'Local household task');
      final all = projectAllSpaces(
        personal: await storage.read(),
        shared: repo.state,
        localSpaces: await spaces.read(),
      );
      expect(all.tasks.map((r) => r.value.title).toSet(), {
        'Saved private',
        'Saved shared',
        'Local household task',
      });
      expect(
        all.tasks.where((r) => r.value.title == 'Saved private'),
        hasLength(1),
      );
      expect(
        all.tasks
            .firstWhere((r) => r.value.title == 'Saved private')
            .source
            .isCurrent(
              await storage.read(),
              repo.state,
              localSpaces: await spaces.read(),
            ),
        true,
      );
      await spaces.selectSpace('local');
      await personal.reload();
      await repo.close();
      store.value = DeviceSession(
        AccountSession.fromJson({
          ...store.value!.profile.toJson(),
          'expiresAt': DateTime.utc(2020).toIso8601String(),
        }),
        store.value!.token,
      );
      transport.offline = true;
      repo = CollaborationRepository(db, transport, store, ownsDatabase: false);
      await repo.initialize();
      addTearDown(repo.close);
      expect(repo.state.localAccessAllowed, true);
      expect((await storage.read()).tasks.single.title, 'Saved private');
      expect(repo.state.dataForScope(scope).tasks.single.title, 'Saved shared');
      await repo.createTask(scopeId: scope, title: 'New offline');
      await personal.reload();
      await personal.createTask(title: 'Private offline');
      await repo.syncNow();
      expect(repo.state.localAccessAllowed, true);
      expect(repo.state.pendingCount, greaterThan(0));
      expect((await storage.read()).tasks.length, 2);
      await expectLater(
        repo.refreshFinancePolicy(scope),
        throwsA(
          isA<CollaborationException>().having(
            (e) => e.code,
            'code',
            'auth_required',
          ),
        ),
      );
      expect(repo.state.sessionInvalid, true);
      await repo.createTask(scopeId: scope, title: 'After persisted expiry');
      await personal.reload();
      await personal.createTask(title: 'Private after persisted expiry');
      await personal.close();
      await repo.close();
      await db.close();
      db = CollaborationDatabase(NativeDatabase(file));
      storage = SqliteOrganizerStorage(db);
      await storage.initialize();
      repo = CollaborationRepository(db, transport, store, ownsDatabase: false);
      await repo.initialize();
      personal = OrganizerRepository(storage);
      await personal.initialize();
      expect(repo.state.sessionInvalid, true);
      expect(repo.state.localAccessAllowed, true);
      await repo.createTask(scopeId: scope, title: 'After database restart');
      await personal.createTask(title: 'Private after database restart');
      expect((await storage.read()).tasks.length, 4);
      expect(repo.state.dataForScope(scope).tasks.length, 4);
      final backup = PortableBackupRepository(
        db,
        storage,
        MemoryBackupUiPreferencesStore(),
        collaboration: () => repo,
      );
      const password = 'a durable offline password';
      final bytes = await backup.exportEncryptedBackup(password);
      final preview = await backup.inspectEncryptedBackup(bytes, password);
      expect(preview.scopeCount, 2);
      expect(preview.pendingCount, greaterThan(0));
    },
  );
  test(
    'known server identity replacement blocks authenticated mutation after repository restart but keeps local edits',
    () async {
      final db = CollaborationDatabase(NativeDatabase.memory()),
          server = FakeServer(),
          store = MemorySessionStore();
      final transport = FakeTransport(server);
      var repo = CollaborationRepository(
        db,
        transport,
        store,
        ownsDatabase: false,
      );
      await repo.initialize();
      await repo.login(
        serverUrl: 'https://example.test',
        username: 'alice',
        password: 'secret',
      );
      final scope = await repo.createScope('Original');
      await repo.createTask(scopeId: scope, title: 'Saved');
      await repo.syncNow();
      server.serverId = newSharedId();
      await repo.syncNow();
      expect(repo.state.lastError?.code, 'server_identity_changed');
      expect(repo.state.localAccessAllowed, true);
      await repo.close();
      repo = CollaborationRepository(db, transport, store, ownsDatabase: false);
      await repo.initialize();
      addTearDown(repo.close);
      addTearDown(db.close);
      server.calls.clear();
      await expectLater(
        repo.createScope('Must not send'),
        throwsA(
          isA<CollaborationException>().having(
            (e) => e.code,
            'code',
            'server_identity_changed',
          ),
        ),
      );
      await repo.createTask(scopeId: scope, title: 'Local only');
      await repo.syncNow();
      expect(repo.state.dataForScope(scope).tasks.length, 2);
      expect(server.calls.where((c) => c.token != null), isEmpty);
    },
  );
  test(
    'empty same-server scope list preserves local copy and never sends pending work',
    () async {
      final db = CollaborationDatabase(NativeDatabase.memory()),
          server = FakeServer(),
          transport = FakeTransport(server);
      final repo = CollaborationRepository(
        db,
        transport,
        MemorySessionStore(),
        ownsDatabase: false,
      );
      await repo.initialize();
      addTearDown(repo.close);
      addTearDown(db.close);
      await repo.login(
        serverUrl: 'https://example.test',
        username: 'alice',
        password: 'secret',
      );
      final scope = await repo.createScope('Saved');
      transport.offline = true;
      await repo.createShoppingList(scopeId: scope, title: 'Only copy');
      final original = (await db.rows(
        'SELECT op_id,request FROM outbox',
      )).single;
      server.scopes.clear();
      server.members.clear();
      server.calls.clear();
      transport.offline = false;
      await repo.syncNow();
      expect(repo.state.scopes.single.revoked, false);
      expect(
        repo.state.dataForScope(scope).shoppingLists.single.title,
        'Only copy',
      );
      expect(repo.state.pendingCount, 1);
      expect(
        (await db.rows('SELECT op_id,request FROM outbox')).single,
        original,
      );
      expect(
        server.calls.where(
          (c) =>
              c.operation.startsWith('sync.') ||
              c.operation.startsWith('sync2.') ||
              c.operation.startsWith('sync3.'),
        ),
        isEmpty,
      );
      expect(
        await db.rows('SELECT value FROM local_meta WHERE name=?', [
          'scope_reconciliation:${repo.state.session!.partition}:$scope',
        ]),
        isNotEmpty,
      );
    },
  );
}
