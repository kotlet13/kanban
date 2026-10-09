import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'collaboration_repository_test.dart'
    show FakeTransport, MemorySessionStore, code;
import 'collaboration_rich_planning_test.dart' show RichServer;

class OrganizationServer extends RichServer {
  bool loseNextApply = false;
  int applies = 0;
  Completer<void>? previewStarted, releasePreview;
  Completer<void>? applyCommitted, releaseApply;
  final operations = <String, Map<String, dynamic>>{};
  final mutationRequests = <Map<String, Object?>>[];
  static final hash = 'a' * 64;

  @override
  Future<Map<String, dynamic>> call(
    String operation,
    Map<String, Object?> params,
    String? token,
  ) async {
    if (operation == 'scopes.accessMigrationPreview') {
      previewStarted?.complete();
      await releasePreview?.future;
      return {
        'scopeId': params['scopeId'],
        'fromVersion': scopes[params['scopeId']]?['accessPolicyVersion'] ?? 1,
        'toVersion': 2,
        'projects': <Object?>[],
        'previewHash': hash,
      };
    }
    if (const {
      'scopes.accessMigrationApply',
      'scopes.setLeader',
      'scopes.updateMetadata',
    }.contains(operation)) {
      mutationRequests.add(Map.of(params));
      final scopeId = params['scopeId'] as String;
      final user = tokens[token];
      if (members[scopeId]?[user] != 'owner') {
        throw const CollaborationException('permission_revoked');
      }
      final id = params['requestId'] as String;
      if (operations[id] case final reply?) return reply;
      late Map<String, dynamic> reply;
      if (operation == 'scopes.accessMigrationApply') {
        if (params['previewHash'] != hash) {
          throw const CollaborationException('access_preview_changed');
        }
        scopes[scopeId]!['accessPolicyVersion'] = 2;
        sequence[scopeId] = sequence[scopeId]! + 1;
        scopes[scopeId]!['sequence'] = sequence[scopeId];
        applies++;
        reply = {'scope': Map<String, dynamic>.of(scopes[scopeId]!)};
      } else if (operation == 'scopes.updateMetadata') {
        final scope = scopes[scopeId]!;
        if ((scope['metadataRevision'] ?? 0) != params['expectedRevision']) {
          throw const CollaborationException('metadata_conflict');
        }
        sequence[scopeId] = sequence[scopeId]! + 1;
        scope.addAll({
          'name': params['name'],
          'address': params['address'],
          'metadataRevision': (scope['metadataRevision'] as int? ?? 0) + 1,
          'sequence': sequence[scopeId],
        });
        reply = {'scope': Map<String, dynamic>.of(scope)};
      } else {
        reply = {
          'members': [
            for (final entry in members[scopeId]!.entries)
              {
                'userId': entry.key == 'alice' ? 1 : 2,
                'accountId': accountIds[entry.key],
                'username': entry.key,
                'displayName': entry.key,
                'role': entry.value,
                'active': true,
                'organizationLeader':
                    entry.value == 'owner' ||
                    (accountIds[entry.key] == params['accountId'] &&
                        params['enabled'] == true),
              },
          ],
          'accessRevision': 1,
        };
      }
      operations[id] = jsonDecode(jsonEncode(reply)) as Map<String, dynamic>;
      if (operation == 'scopes.accessMigrationApply') {
        applyCommitted?.complete();
        await releaseApply?.future;
      }
      if (operation == 'scopes.accessMigrationApply' && loseNextApply) {
        loseNextApply = false;
        throw const CollaborationException('network');
      }
      return reply;
    }
    final reply = await super.call(operation, params, token);
    if (operation == 'capabilities') {
      (reply['features'] as Map<String, dynamic>).addAll({
        'organizationLeadership': true,
        'accessMigrationPreview': true,
        'scopeMetadata': true,
      });
    }
    if (operation == 'scopes.create') {
      final scope = reply['scope'] as Map<String, dynamic>;
      scope['accessPolicyVersion'] = params['accessPolicyVersion'] ?? 1;
      scope['address'] = params['address'];
      scope['metadataRevision'] = 0;
      scopes[scope['id']]!.addAll(scope);
    }
    return reply;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late Directory dir;
  late OrganizationServer server;
  late FakeTransport transport;
  late MemorySessionStore store;
  final repositories = <CollaborationRepository>[];
  Future<CollaborationRepository> open() async {
    final repo = CollaborationRepository(
      CollaborationDatabase(NativeDatabase(File('${dir.path}/db.sqlite'))),
      transport,
      store,
      clock: () => DateTime.utc(2026, 10, 9),
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
    expect(
      repo.state.lastError,
      isNull,
      reason: server.calls.map((c) => c.operation).join(', '),
    );
    return repo;
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('organization-access-');
    server = OrganizationServer();
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
    'access metadata and membership flags survive JSON roundtrip and legacy defaults',
    () {
      final scope = SharedScope(
        id: newSharedId(),
        name: 'Org',
        kind: SharedScopeKind.organization,
        role: SharedRole.owner,
        accessPolicyVersion: 2,
        accessRevision: 7,
        organizationLeader: true,
        address: 'Address',
        metadataRevision: 3,
      );
      final restored = SharedScope.fromJson(scope.toJson());
      expect(restored.accessPolicyVersion, 2);
      expect(restored.accessRevision, 7);
      expect(restored.organizationLeader, isTrue);
      expect(restored.address, 'Address');
      expect(restored.metadataRevision, 3);
      final member = SharedMember(
        userId: 1,
        accountId: newSharedId(),
        username: 'alice',
        displayName: 'Alice',
        role: SharedRole.member,
        active: true,
        organizationLeader: true,
      );
      expect(SharedMember.fromJson(member.toJson()).organizationLeader, isTrue);
      final old = scope.toJson()
        ..remove('accessPolicyVersion')
        ..remove('organizationLeader');
      expect(SharedScope.fromJson(old).accessPolicyVersion, 1);
      expect(SharedScope.fromJson(old).organizationLeader, isFalse);
      final policy = SharedFinancePolicy(
        enabled: true,
        grant: SharedFinanceGrant.read,
        revision: 4,
        managedByOrganizationPolicy: true,
        readAccessFromMembership: true,
      );
      expect(
        SharedFinancePolicy.fromJson(
          policy.toJson(),
        ).managedByOrganizationPolicy,
        isTrue,
      );
    },
  );
  test(
    'reviewed organization apply survives lost reply and restart with exact request',
    () async {
      var repo = await login();
      final org = await repo.createScope(
        'Org',
        kind: SharedScopeKind.organization,
      );
      final preview = await repo.previewOrganizationAccess(org);
      expect(preview.scopeId, org);
      server.loseNextApply = true;
      await expectLater(
        repo.applyOrganizationAccess(org, preview.previewHash),
        throwsA(code('network')),
      );
      final first = server.mutationRequests.single;
      await repo.close();
      repositories.remove(repo);
      repo = await open();
      await repo.resumeOrganizationAccessChange(org);
      expect(server.applies, 1);
      expect(server.mutationRequests.last, first);
      expect(repo.state.scopes.single.accessPolicyVersion, 2);
      expect(
        await repo.database.rows(
          "SELECT name FROM local_meta WHERE name LIKE 'organization_access_pending:%'",
        ),
        isEmpty,
      );
    },
  );
  test(
    'member cannot start owner-only access change or mutate cached memberships',
    () async {
      final repo = await login();
      final org = await repo.createScope(
        'Org',
        kind: SharedScopeKind.organization,
      );
      server.members[org]!['alice'] = 'member';
      await repo.syncNow();
      await expectLater(
        repo.previewOrganizationAccess(org),
        throwsA(code('permission_revoked')),
      );
      expect(server.mutationRequests, isEmpty);
    },
  );
  test('late preview cannot cross signout identity boundary', () async {
    final repo = await login();
    final org = await repo.createScope(
      'Org',
      kind: SharedScopeKind.organization,
    );
    server.previewStarted = Completer<void>();
    server.releasePreview = Completer<void>();
    final pending = repo.previewOrganizationAccess(org);
    final check = expectLater(pending, throwsA(code('session_changed')));
    await server.previewStarted!.future;
    await repo.signOut();
    server.releasePreview!.complete();
    await check;
    expect(repo.state.session, isNull);
  });
  test(
    'late apply keeps its receipt intent without changing signed out cache',
    () async {
      final repo = await login();
      final org = await repo.createScope(
        'Org',
        kind: SharedScopeKind.organization,
      );
      final partition = repo.state.session!.partition;
      final cachedPolicy = repo.state.scopes.single.accessPolicyVersion;
      final preview = await repo.previewOrganizationAccess(org);
      server.applyCommitted = Completer<void>();
      server.releaseApply = Completer<void>();
      final pending = repo.applyOrganizationAccess(org, preview.previewHash);
      final check = expectLater(pending, throwsA(code('session_changed')));
      await server.applyCommitted!.future;
      await repo.signOut();
      server.releaseApply!.complete();
      await check;
      final cached = await repo.database.rows(
        'SELECT data FROM scopes WHERE partition=? AND id=?',
        [partition, org],
      );
      expect(
        (jsonDecode(cached.single['data'] as String)
            as Map)['accessPolicyVersion'],
        cachedPolicy,
      );
      expect(
        await repo.database.rows('SELECT value FROM local_meta WHERE name=?', [
          'organization_access_pending:$partition:$org',
        ]),
        hasLength(1),
      );
      expect(server.applies, 1);
    },
  );
  test(
    'owner metadata uses exact revision and keeps address in scoped projection',
    () async {
      final repo = await login();
      final house = await repo.createScope('Home');
      final updated = await repo.updateScopeMetadata(
        house,
        'Renamed',
        'Saved address',
        expectedRevision: 0,
      );
      expect(updated.address, 'Saved address');
      expect(updated.metadataRevision, 1);
      expect(repo.state.scopes.single.address, 'Saved address');
      await expectLater(
        repo.updateScopeMetadata(house, 'Stale', 'Wrong', expectedRevision: 0),
        throwsA(code('metadata_conflict')),
      );
      expect(repo.state.scopes.single.address, 'Saved address');
    },
  );
}
