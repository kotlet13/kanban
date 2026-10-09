import 'dart:convert';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/data/local_spaces_repository.dart';
import 'package:kanban/organizer/data/organizer_repository.dart';
import 'package:kanban/organizer/data/garden_storage.dart';
import 'package:kanban/organizer/data/garden_repository.dart';
import 'package:kanban/organizer/data/sqlite_organizer_storage.dart';
import 'package:kanban/organizer/data/portable_backup_repository.dart';
import 'package:kanban/organizer/domain/local_space_models.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'package:kanban/organizer/domain/all_spaces_projection.dart';
import 'collaboration_repository_test.dart' show FakeServer, MemorySessionStore;
import 'private_sync_test_support.dart' show PersonalTransport;

class PublicationTransport extends PersonalTransport {
  PublicationTransport(super.server);
  bool modern = true, loseCreateReply = false;
  final createReplay = <String, Map<String, dynamic>>{};
  final wireCalls = <String>[];
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
    wireCalls.add(operation);
    if (operation == 'capabilities') {
      final caps = await super.call(serverUrl: serverUrl, operation: operation);
      return {
        ...caps,
        'recordContractVersions': [1, 2, 3, 4],
        'financeContractVersions': [1, 2],
        'organizationAccessPolicyVersions': [1, 2],
        'features': <String, dynamic>{
          ...caps['features'] as Map,
          'organizations': true,
          'householdPeople': true,
          'scopeMetadata': modern,
          'stableScopePublication': modern,
        },
      };
    }
    if (operation == 'scopes.create') {
      final requestId = params['requestId'] as String;
      if (createReplay.containsKey(requestId)) {
        return jsonDecode(jsonEncode(createReplay[requestId]))
            as Map<String, dynamic>;
      }
      final result = await super.call(
        serverUrl: serverUrl,
        operation: operation,
        params: params,
        token: token,
      );
      final id = params['id'] as String;
      server.scopes[id]!.addAll({
        'organizationId': params['organizationId'],
        'projectRootId': params['organizationId'] == null ? null : id,
        'requiredRecordContractVersion': params['organizationId'] == null
            ? 1
            : 3,
      });
      result['scope'] = {...server.scopes[id]!, 'role': 'owner'};
      if (params['projectPayload'] != null) {
        final root = {
          'id': id,
          'type': 'project',
          'revision': 1,
          'deleted': false,
          'payload': params['projectPayload'],
          'sequence': 1,
          'updatedAt': (params['projectPayload'] as Map)['updatedAt'],
        };
        server.records[id]![id] = root;
        server.sequence[id] = 1;
        result['projectRoot'] = root;
      }
      createReplay[requestId] =
          jsonDecode(jsonEncode(result)) as Map<String, dynamic>;
      if (loseCreateReply) {
        loseCreateReply = false;
        throw const CollaborationException('network');
      }
      return result;
    }
    final reply = await super.call(
      serverUrl: serverUrl,
      operation: operation == 'sync4.push' || operation == 'sync3.push'
          ? 'sync2.push'
          : operation == 'sync4.pull' || operation == 'sync3.pull'
          ? 'sync2.pull'
          : operation.startsWith('finance2.')
          ? operation.replaceFirst('finance2.', 'finance.')
          : operation,
      params: params,
      token: token,
      allowLocalHttp: allowLocalHttp,
    );
    if (operation.startsWith('finance2.')) {
      for (final record in [
        if (reply['record'] != null) reply['record'],
        ...?reply['records'] as List?,
      ]) {
        (record as Map)['contractVersion'] = 2;
      }
    }
    return reply;
  }
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  Future<
    (
      CollaborationDatabase,
      LocalSpacesRepository,
      OrganizerRepository,
      CollaborationRepository,
      PublicationTransport,
    )
  >
  client() async {
    final db = CollaborationDatabase(NativeDatabase.memory()),
        storage = SqliteOrganizerStorage(db);
    await storage.initialize();
    final local = OrganizerRepository(storage);
    await local.initialize();
    final transport = PublicationTransport(FakeServer()),
        shared = CollaborationRepository(
          db,
          transport,
          MemorySessionStore(),
          ownsDatabase: false,
        );
    await shared.initialize();
    await shared.login(
      serverUrl: 'https://example.test',
      username: 'alice',
      password: 'secret',
    );
    addTearDown(() async {
      await local.close();
      await shared.close();
      await db.close();
    });
    return (db, LocalSpacesRepository(db), local, shared, transport);
  }

  test(
    'offline recovery uses current bound rows and preserves exact original recovery archive',
    () async {
      final (db, spaces, local, shared, transport) = await client();
      final home = await spaces.createSpace(
        kind: LocalSpaceKind.household,
        name: 'Home',
      );
      await spaces.selectSpace(home.id);
      await local.reload();
      await local.createTask(title: 'Before publication');
      final garden = GardenRepository(GardenStorage(db));
      await garden.initialize();
      await garden.createGarden(name: 'Shared garden');
      await garden.close();
      await shared.publishLocalSpaces(
        await shared.previewLocalSpacesPublication([home.id]),
      );
      transport.offline = true;
      await shared.updateTask(
        home.id,
        shared.state
            .dataForScope(home.id)
            .tasks
            .single
            .copyWith(title: 'Authoritative offline edit'),
      );
      final backup = PortableBackupRepository(
        db,
        SqliteOrganizerStorage(db),
        MemoryBackupUiPreferencesStore(),
        collaboration: () => shared,
      );
      const password = 'restore without the old server';
      final bytes = await backup.exportEncryptedBackup(password),
          original = await backup.crypto.decrypt(bytes, password);
      final target = CollaborationDatabase(NativeDatabase.memory()),
          storage = SqliteOrganizerStorage(target);
      await storage.initialize();
      addTearDown(target.close);
      final restore = PortableBackupRepository(
        target,
        storage,
        MemoryBackupUiPreferencesStore(),
      );
      await restore.restoreEncryptedBackup(
        bytes,
        password,
        mode: BackupRestoreMode.replace,
        expectedPersonalRevision: (await storage.read()).revision,
      );
      final archiveBefore = await target.rows('SELECT * FROM restored_backups');
      await target.execute('INSERT INTO local_meta(name,value) VALUES(?,?)', [
        'invalid_session:${shared.state.session!.partition}:${shared.state.session!.deviceId}',
        'device_revoked',
      ]);
      expect(
        (await restore.reviewRestoredSpacesAsLocal(
          original['id'] as String,
          password,
        )).blockedScopeIds,
        contains(home.id),
      );
      await target.execute('UPDATE local_meta SET value=? WHERE name=?', [
        'auth_required',
        'invalid_session:${shared.state.session!.partition}:${shared.state.session!.deviceId}',
      ]);
      final preview = await restore.reviewRestoredSpacesAsLocal(
        original['id'] as String,
        password,
      );
      expect(preview.canRecover, true);
      expect(
        preview.limitations,
        isNot(contains('linked_payments_require_reconciliation')),
      );
      final copies = await restore.recoverRestoredSpacesAsLocal(
        preview,
        password: password,
      );
      expect(copies.single.id, isNot(home.id));
      await LocalSpacesRepository(target).selectSpace(copies.single.id);
      expect(
        (await storage.read()).tasks.single.title,
        'Authoritative offline edit',
      );
      expect(
        (await storage.read()).tasks.single.id,
        isNot(shared.state.dataForScope(home.id).tasks.single.id),
      );
      expect(
        (await GardenStorage(target).read()).gardens.single.name,
        'Shared garden',
      );
      expect(
        await target.rows('SELECT * FROM restored_backups'),
        archiveBefore,
      );
      expect(await target.rows('SELECT * FROM outbox'), isEmpty);
      expect(
        (await restore.recoverRestoredSpacesAsLocal(
          preview,
          password: password,
        )).single.id,
        copies.single.id,
      );
    },
  );
  test(
    'offline recovery honors newer finance denial while keeping ordinary tasks',
    () async {
      final (db, spaces, local, shared, transport) = await client();
      final home = await spaces.createSpace(
        kind: LocalSpaceKind.household,
        name: 'Home',
      );
      await spaces.selectSpace(home.id);
      await local.reload();
      await local.createTask(title: 'Ordinary work');
      await local.createFinanceEntry(
        title: 'Hidden later',
        amountMinor: 3000,
        kind: FinanceEntryKind.expense,
        occurredAt: DateTime.now(),
      );
      await shared.publishLocalSpaces(
        await shared.previewLocalSpacesPublication([home.id]),
      );
      final storage = SqliteOrganizerStorage(db),
          backup = PortableBackupRepository(
            db,
            SqliteOrganizerStorage(db),
            MemoryBackupUiPreferencesStore(),
            collaboration: () => shared,
          );
      const password = 'finance rights recovery password';
      final bytes = await backup.exportEncryptedBackup(password),
          doc = await backup.crypto.decrypt(bytes, password);
      await db.execute(
        'UPDATE scopes SET finance_blocked=1 WHERE partition=? AND id=?',
        [shared.state.session!.partition, home.id],
      );
      transport.offline = true;
      await backup.restoreEncryptedBackup(
        bytes,
        password,
        mode: BackupRestoreMode.replace,
        expectedPersonalRevision: (await storage.read()).revision,
      );
      final preview = await backup.reviewRestoredSpacesAsLocal(
        doc['id'] as String,
        password,
      );
      expect(preview.limitations, contains('finance_access_unavailable'));
      final copies = await backup.recoverRestoredSpacesAsLocal(
        preview,
        password: password,
      );
      await spaces.selectSpace(copies.single.id);
      final copy = await storage.read();
      expect(copy.tasks.single.title, 'Ordinary work');
      expect(copy.financeEntries, isEmpty);
      expect(copy.financeAccounts, isEmpty);
      expect(copies.single.financeRecoveryIncomplete, true);
      expect(
        projectAllSpaces(
          personal: copy,
          shared: CollaborationState(),
          localSpaces: await spaces.read(),
        ).financeComplete,
        false,
      );
    },
  );
  test(
    'household publication reuses stable scope request after lost response and keeps one current source',
    () async {
      final (db, spaces, local, shared, transport) = await client();
      final home = await spaces.createSpace(
        kind: LocalSpaceKind.household,
        name: 'Our house',
        address: 'Real address',
      );
      await spaces.selectSpace(home.id);
      await local.reload();
      await local.createTask(title: 'Before sync');
      final garden = GardenRepository(GardenStorage(db));
      await garden.initialize();
      final gardenId = await garden.createGarden(name: 'Real garden');
      await garden.close();
      final preview = await shared.previewLocalSpacesPublication([home.id]);
      expect(preview.canPublish, true);
      transport.loseCreateReply = true;
      await expectLater(
        shared.publishLocalSpaces(preview),
        throwsA(isA<CollaborationException>()),
      );
      await shared.publishLocalSpaces(preview);
      expect(transport.server.scopes.length, 1);
      expect(transport.server.scopes.keys.single, home.id);
      expect(transport.createReplay.length, 1);
      expect(
        shared.state.dataForScope(home.id).tasks.single.title,
        'Before sync',
      );
      expect(shared.state.dataForScope(home.id).gardens.single.id, gardenId);
      final linked = (await spaces.read()).spaces
          .where((s) => s.id == home.id)
          .single;
      expect(linked.binding!.partition, shared.state.session!.partition);
      final all = projectAllSpaces(
        personal: await SqliteOrganizerStorage(db).read(),
        shared: shared.state,
        localSpaces: await spaces.read(),
      );
      expect(all.tasks.length, 1);
      await expectLater(
        local.createTask(title: 'Old twin'),
        throwsA(isA<OrganizerConflictException>()),
      );
      await shared.createTask(scopeId: home.id, title: 'After garden');
      await shared.syncNow();
      expect(shared.state.dataForScope(home.id).tasks.length, 2);
      expect(transport.wireCalls, contains('sync4.push'));
    },
  );
  test(
    'preview protects local edits, old server capability and account switch before creating',
    () async {
      final (_, spaces, local, shared, transport) = await client();
      final home = await spaces.createSpace(
        kind: LocalSpaceKind.household,
        name: 'Home',
      );
      await spaces.selectSpace(home.id);
      await local.reload();
      final preview = await shared.previewLocalSpacesPublication([home.id]);
      await local.createTask(title: 'Changed after review');
      await expectLater(
        shared.publishLocalSpaces(preview),
        throwsA(
          isA<CollaborationException>().having(
            (e) => e.code,
            'code',
            'backup_stale',
          ),
        ),
      );
      expect(transport.server.scopes, isEmpty);
      transport.modern = false;
      final unsupported = await shared.previewLocalSpacesPublication([home.id]);
      expect(unsupported.issues, contains('server_upgrade_required'));
      expect(unsupported.canPublish, false);
      transport.modern = true;
      final own = await shared.previewLocalSpacesPublication([home.id]);
      await shared.login(
        serverUrl: 'https://example.test',
        username: 'bob',
        password: 'secret',
      );
      await expectLater(
        shared.publishLocalSpaces(own),
        throwsA(
          isA<CollaborationException>().having(
            (e) => e.code,
            'code',
            'backup_wrong_account',
          ),
        ),
      );
      expect(transport.server.scopes, isEmpty);
    },
  );
  test(
    'organization projects retain UUID root, names but no unrelated private person notes or accounts',
    () async {
      final (db, spaces, local, shared, transport) = await client();
      final org = await spaces.createSpace(
        kind: LocalSpaceKind.organization,
        name: 'Organization',
      );
      await spaces.selectSpace(org.id);
      await local.reload();
      await local.createPerson(
        name: 'Private person',
        notes: 'Confidential unrelated note',
      );
      await local.createProject(title: 'Project');
      final project = local.snapshot.projects.single;
      await local.createTask(title: 'Project work', projectId: project.id);
      final now = DateTime.now().toUtc(),
          account = LocalFinanceAccount(
            id: newLocalId(),
            name: 'Unrelated account',
            currency: 'EUR',
            createdAt: now,
            updatedAt: now,
          );
      await local.saveFinancePlan(
        accounts: [account],
        rules: [],
        expectedRevision: local.snapshot.revision,
        expectedWorkspaceKey: org.id,
      );
      final preview = await shared.previewLocalSpacesPublication([org.id]);
      expect(preview.spaces.single.projects.single.personCount, 0);
      expect(preview.spaces.single.projects.single.accountCount, 0);
      await shared.publishLocalSpaces(preview);
      final published = shared.state.dataForScope(project.id);
      expect(published.projects.single.id, project.id);
      expect(published.projects.single.createdAt, project.createdAt);
      expect(published.tasks.single.projectId, project.id);
      expect(published.people, isEmpty);
      expect(published.financeAccounts, isEmpty);
      expect(
        shared.state.dataForScope(org.id).people.single.notes,
        'Confidential unrelated note',
      );
      expect(transport.server.scopes.keys.toSet(), {org.id, project.id});
      expect(shared.state.lastError, isNull);
      expect(await db.rows('SELECT * FROM outbox'), isEmpty);
    },
  );
}
