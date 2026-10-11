import 'dart:convert';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/data/pending_invitation_store.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';
import 'collaboration_repository_test.dart'
    show FakeServer, FakeTransport, MemorySessionStore;

class SpaceServer extends FakeServer {
  bool loseApply = false, corruptApply = false;
  final applies = <Map<String, Object?>>[];
  final replies = <String, Map<String, dynamic>>{};
  String? invitationOperation;
  final createRequests = <Map<String, Object?>>[];
  @override
  Future<Map<String, dynamic>> call(
    String operation,
    Map<String, Object?> params,
    String? token,
  ) async {
    if (operation == 'scopes.projectSharingPreview') {
      final p = params['projectId'] as String;
      final s = params['scopeId'] as String;
      return {
        'scopeId': s,
        'projectId': p,
        'projectName': 'Project',
        'canApply': true,
        'blockers': [],
        'movedRecordIds': records[s]!.values
            .where(
              (r) => r['id'] == p || (r['payload'] as Map?)?['projectId'] == p,
            )
            .map((r) => r['id'])
            .toList(),
        'movedFinanceRecordIds': [],
        'movedReminderIds': [],
        'previewHash': 'a' * 64,
      };
    }
    if (operation == 'scopes.projectSharingApply') {
      applies.add(Map.of(params));
      final request = params['requestId'] as String;
      if (replies[request] case final saved?) return saved;
      final parent = params['scopeId'] as String,
          project = params['projectId'] as String;
      final ids = records[parent]!.values
          .where(
            (r) =>
                r['id'] == project ||
                (r['payload'] as Map?)?['projectId'] == project,
          )
          .map((r) => r['id'] as String)
          .toList();
      scopes[project] = {
        'id': project,
        'name': 'Project',
        'kind': 'project',
        'parentScopeId': parent,
        'parentScopeKind': 'household',
        'projectRootId': project,
        'role': 'owner',
        'accessPolicyVersion': 3,
        'sequence': ids.length,
      };
      members[project] = {'alice': 'owner'};
      records[project] = {
        for (final id in ids) id: records[parent]!.remove(id)!,
      };
      sequence[project] = ids.length;
      final reply = replies[request] = {
        'scope': scopes[project],
        'projectRoot': records[project]![project],
        'movedRecordIds': ids,
        'movedFinanceRecordIds': [],
        'movedReminderIds': [],
      };
      if (corruptApply) {
        corruptApply = false;
        return {
          ...reply,
          'scope': {...scopes[project]!, 'kind': 'unknown'},
        };
      }
      if (loseApply) {
        loseApply = false;
        throw const CollaborationException('network');
      }
      return reply;
    }
    if (operation == 'invitations3.create') {
      invitationOperation = operation;
      return {
        'invitation': {
          'id': newSharedId(),
          'scopeId': params['scopeId'],
          'recipientUsername': '',
          'recipientEmail': params['recipientEmail'],
          'role': params['role'],
          'expiresAt': 4102444800,
          'contractVersion': 3,
          'accessScope': params['accessScope'],
        },
        'deliveryQueued': true,
      };
    }
    final reply = await super.call(operation, params, token);
    if (operation == 'capabilities') {
      reply['spaceAccessPolicyVersions'] = [3];
      reply['invitationContractVersions'] = [1, 2, 3];
      reply['features'] = <String, dynamic>{
        ...reply['features'] as Map,
        'spaceProjectMembership': true,
        'scopedInvitations': true,
        'emailInvitations': true,
      };
    }
    if (operation == 'scopes.create') {
      createRequests.add(Map.of(params));
      final scope = reply['scope'] as Map<String, dynamic>;
      scope['accessPolicyVersion'] = params['accessPolicyVersion'] ?? 3;
      scopes[scope['id']]!.addAll(scope);
    }
    return reply;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late SpaceServer server;
  late FakeTransport transport;
  late CollaborationRepository repo;
  late ProviderContainer providers;
  setUp(() async {
    server = SpaceServer();
    transport = FakeTransport(server);
    repo = CollaborationRepository(
      CollaborationDatabase(NativeDatabase.memory()),
      transport,
      MemorySessionStore(),
      invitationStore: MemoryPendingInvitationStore(),
    );
    await repo.initialize();
    await repo.login(
      serverUrl: 'https://synthetic.invalid/',
      username: 'alice',
      password: 'synthetic',
    );
    providers = ProviderContainer(
      overrides: [
        collaborationRepositoryProvider.overrideWith((ref) async => repo),
      ],
    );
    await providers.read(collaborationProvider.future);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    while (repo.state.isSyncing) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
  });
  tearDown(() async {
    providers.dispose();
    await repo.close();
  });
  Matcher failure(String code) => throwsA(
    isA<CollaborationException>().having((e) => e.code, 'code', code),
  );

  test(
    'policy3 member administers only concrete scope and unknown policy is blocked',
    () {
      final scope = SharedScope(
        id: newSharedId(),
        name: 'Household',
        kind: SharedScopeKind.household,
        role: SharedRole.member,
        accessPolicyVersion: 3,
      );
      expect(scope.canManage, true);
      expect(scope.isOwner, false);
      expect(
        SharedScope.fromJson({
          ...scope.toJson(),
          'accessPolicyVersion': 2,
        }).canManage,
        false,
      );
      final future = SharedScope.fromJson({
        ...scope.toJson(),
        'accessPolicyVersion': 4,
      });
      expect(future.canManage, false);
      expect(future.canEdit, false);
      final child = SharedScope.fromJson({
        ...scope.toJson(),
        'kind': 'project',
        'parentScopeId': scope.id,
        'parentScopeKind': 'household',
      });
      expect(child.parentSpaceId, scope.id);
      expect(child.parentScopeKind, SharedScopeKind.household);
    },
  );
  test(
    'real controller chooses invitation3 and concrete space target',
    () async {
      final controller = providers.read(collaborationProvider.notifier);
      final id = await controller.createScope('Household');
      final invitation = await controller.createEmailInvitation(
        scopeId: id,
        recipientEmail: 'synthetic@example.invalid',
      );
      expect(invitation.contractVersion, 3);
      expect(invitation.accessScope, 'space');
      expect(invitation.isEmailInvitation, true);
      expect(server.invitationOperation, 'invitations3.create');
      expect(
        providers
            .read(collaborationProvider)
            .requireValue
            .scopedInvitationsSupported,
        true,
      );
    },
  );
  test(
    'pending immutable operation blocks extraction without rewriting any queue fields',
    () async {
      final id = await repo.createScope('Household');
      transport.offline = true;
      final project = await repo.createProject(scopeId: id, title: 'Project');
      final before = await repo.database.rows('SELECT * FROM outbox');
      expect(before, isNotEmpty);
      await expectLater(
        repo.previewProjectSharing(id, project),
        failure('project_sharing_pending_changes'),
      );
      final after = await repo.database.rows('SELECT * FROM outbox');
      expect(jsonEncode(after), jsonEncode(before));
      expect(repo.state.dataForScope(id).projects.single.id, project);
    },
  );
  test(
    'lost extraction reply blocks local edits then replays same durable request through real controller',
    () async {
      final id = await repo.createScope('Household');
      final project = await repo.createProject(scopeId: id, title: 'Project');
      await repo.syncNow();
      final controller = providers.read(collaborationProvider.notifier);
      final preview = await controller.previewProjectSharing(id, project);
      server.loseApply = true;
      await expectLater(
        controller.applyProjectSharing(preview),
        failure('network'),
      );
      await Future<void>.delayed(Duration.zero);
      expect(
        providers
            .read(collaborationProvider)
            .requireValue
            .projectSharingPendingScopeIds,
        contains(id),
      );
      await expectLater(
        repo.createShoppingList(scopeId: id, title: 'Blocked'),
        failure('project_sharing_pending_changes'),
      );
      final child = await controller.resumeProjectSharing(id);
      expect(child?.id, project);
      expect(child?.parentSpaceId, id);
      expect(server.applies.length, 2);
      expect(jsonEncode(server.applies.first), jsonEncode(server.applies.last));
      expect(repo.state.dataForScope(project).projects.single.id, project);
      expect(repo.state.dataForScope(id).projects, isEmpty);
      expect(repo.state.projectSharingPendingScopeIds, isEmpty);
    },
  );
  test(
    'malformed committed extraction keeps visible durable recovery and can resume without restarting',
    () async {
      final id = await repo.createScope('Household');
      final project = await repo.createProject(scopeId: id, title: 'Project');
      await repo.syncNow();
      final controller = providers.read(collaborationProvider.notifier);
      final preview = await controller.previewProjectSharing(id, project);
      server.corruptApply = true;
      await expectLater(
        controller.applyProjectSharing(preview),
        throwsArgumentError,
      );
      await Future<void>.delayed(Duration.zero);
      expect(
        providers
            .read(collaborationProvider)
            .requireValue
            .projectSharingPendingScopeIds,
        contains(id),
      );
      expect(repo.state.dataForScope(id).projects.single.id, project);
      final child = await controller.resumeProjectSharing(id);
      expect(child?.id, project);
      expect(repo.state.projectSharingPendingScopeIds, isEmpty);
      expect(
        server.applies.first['requestId'],
        server.applies.last['requestId'],
      );
    },
  );
  test(
    'new server preserves legacy parent project creation and requests policy3 only for an aligned parent',
    () async {
      final legacy = await repo.createScope('Legacy organization');
      final partition = repo.state.session!.partition;
      final original = repo.state.scopes.singleWhere((s) => s.id == legacy);
      final old = {
        ...original.toJson(),
        'kind': 'organization',
        'accessPolicyVersion': 2,
      };
      server.scopes[legacy]!.addAll(old);
      await repo.database.execute(
        'UPDATE scopes SET data=? WHERE partition=? AND id=?',
        [jsonEncode(old), partition, legacy],
      );
      await repo.refreshLocal();
      await repo.createScope(
        'Legacy child',
        kind: SharedScopeKind.project,
        parentScopeId: legacy,
      );
      expect(
        server.createRequests.last.containsKey('accessPolicyVersion'),
        false,
      );
      final modern = await repo.createScope('Modern household');
      await repo.createScope(
        'Modern child',
        kind: SharedScopeKind.project,
        parentScopeId: modern,
      );
      expect(server.createRequests.last['accessPolicyVersion'], 3);
    },
  );
}
