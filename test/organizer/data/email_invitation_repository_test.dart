import 'dart:io';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/data/collaboration_transport.dart';
import 'package:kanban/organizer/data/pending_invitation_store.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'collaboration_repository_test.dart'
    show FakeServer, FakeTransport, MemorySessionStore;

class EmailServer extends FakeServer {
  bool supported = true,
      loseAccept = false,
      loseRegister = false,
      changeRegisterIdentity = false;
  String? lastPreviewBearer;
  String? recipient, scopeId;
  final token = 'fhi2_${'a' * 64}';
  final invitationId = newSharedId();
  int registerCalls = 0, acceptCalls = 0, previewCalls = 0;
  Map<String, dynamic> get invitation => {
    'id': invitationId,
    'scopeId': scopeId,
    'recipientUsername': '',
    'recipientEmail': 'synthetic@example.invalid',
    'role': 'member',
    'expiresAt': 4102444800,
    'contractVersion': 2,
  };
  Map<String, dynamic> get preview => {
    'invitation': invitation,
    'scope': scopes[scopeId],
    'registrationAllowed': true,
    'requiresExplicitAcceptance': true,
    'inviterName': 'Synthetic owner',
  };
  @override
  Future<Map<String, dynamic>> call(
    String operation,
    Map<String, Object?> params,
    String? bearer,
  ) async {
    if (operation == 'capabilities') {
      final caps = await super.call(operation, params, bearer);
      return {
        ...caps,
        'invitationContractVersions': [1, if (supported) 2],
        'features': <String, dynamic>{
          ...caps['features'] as Map<String, dynamic>,
          'emailInvitations': supported,
        },
      };
    }
    if (operation == 'invitations2.create') {
      return {'invitation': invitation, 'deliveryQueued': true};
    }
    if (operation == 'invitations2.preview') {
      previewCalls++;
      lastPreviewBearer = bearer;
      if (recipient != null &&
          members[scopeId]!.containsKey(recipient) &&
          tokens[bearer] != recipient) {
        throw const CollaborationApiException('invitation_invalid');
      }
      return preview;
    }
    if (operation == 'auth.registerInvitation2') {
      registerCalls++;
      if (recipient != null) {
        throw const CollaborationApiException(
          'invitation_authentication_required',
        );
      }
      recipient = params['username'] as String;
      accountIds[recipient!] = newSharedId();
      final response = await super.call('auth.login', {
        'username': recipient,
      }, null);
      if (changeRegisterIdentity) response['serverId'] = newSharedId();
      if (loseRegister) {
        loseRegister = false;
        throw const CollaborationException('network');
      }
      return response;
    }
    if (operation == 'invitations2.pending') {
      return {
        'invitations': tokens[bearer] == recipient
            ? [
                {...preview, 'registrationAllowed': false},
              ]
            : [],
      };
    }
    if (operation == 'invitations2.accept') {
      acceptCalls++;
      if (tokens[bearer] != recipient) {
        throw const CollaborationApiException('invitation_invalid');
      }
      members[scopeId]![recipient!] = 'member';
      if (loseAccept) {
        loseAccept = false;
        throw const CollaborationException('network');
      }
      return {
        'scope': {...scopes[scopeId]!, 'role': 'member'},
      };
    }
    return super.call(operation, params, bearer);
  }
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late Directory directory;
  late EmailServer server;
  late MemoryPendingInvitationStore pending;
  final repositories = <CollaborationRepository>[];
  Future<CollaborationRepository> open(
    String name,
    MemorySessionStore sessions,
  ) async {
    final repo = CollaborationRepository(
      CollaborationDatabase(
        NativeDatabase(File('${directory.path}/$name.sqlite')),
      ),
      FakeTransport(server),
      sessions,
      invitationStore: pending,
    );
    await repo.initialize();
    repositories.add(repo);
    return repo;
  }

  Future<void> login(CollaborationRepository repo, String username) =>
      repo.login(
        serverUrl: 'https://synthetic.invalid/kanboard',
        username: username,
        password: 'synthetic-password',
      );
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('email-invites-');
    server = EmailServer();
    pending = MemoryPendingInvitationStore();
    final owner = await open('owner', MemorySessionStore());
    await login(owner, 'alice');
    server.scopeId = await owner.createScope('Synthetic household');
  });
  tearDown(() async {
    for (final repo in repositories) {
      await repo.close();
    }
    repositories.clear();
    await directory.delete(recursive: true);
  });
  Matcher failure(String code) => throwsA(
    isA<CollaborationException>().having((e) => e.code, 'code', code),
  );

  test(
    'create exposes queued delivery but never token or existing recipient',
    () async {
      final result = await repositories.first.createEmailInvitation(
        scopeId: server.scopeId!,
        recipientEmail: 'synthetic@example.invalid',
      );
      expect(result.isEmailInvitation, true);
      expect(result.token, isNull);
      expect(result.deliveryQueued, true);
      expect(result.recipientUsername, '');
    },
  );
  test(
    'older server gates creation and inbox without unsupported calls',
    () async {
      server.supported = false;
      await expectLater(
        repositories.first.createEmailInvitation(
          scopeId: server.scopeId!,
          recipientEmail: 'synthetic@example.invalid',
        ),
        failure('email_invitations_unavailable'),
      );
      expect(await repositories.first.pendingInvitations(), isEmpty);
    },
  );
  test(
    'registration signs in without membership; explicit ID acceptance joins',
    () async {
      final repo = await open('recipient', MemorySessionStore());
      await repo.registerWithInvitation(
        serverUrl: 'https://synthetic.invalid/kanboard',
        invitationToken: server.token,
        username: 'charlie',
        name: 'Synthetic recipient',
        password: 'synthetic-password',
      );
      expect(repo.state.session?.username, 'charlie');
      expect(repo.state.scopes, isEmpty);
      expect(server.acceptCalls, 0);
      expect(pending.value?.serverId, server.serverId);
      final invitations = await repo.pendingInvitations();
      expect(invitations.single.invitationId, server.invitationId);
      expect(invitations.single.isEmailInvitation, true);
      await repo.acceptEmailInvitation(
        invitationId: invitations.single.invitationId,
      );
      expect(repo.state.scopes.single.id, server.scopeId);
    },
  );
  test('ID acceptance clears only its matching saved link', () async {
    final repo = await open('recipient', MemorySessionStore());
    server.recipient = 'bob';
    await repo.previewInvitation(
      serverUrl: 'https://synthetic.invalid/kanboard',
      token: server.token,
    );
    expect(pending.value?.invitationId, server.invitationId);
    await login(repo, 'bob');
    await repo.acceptEmailInvitation(invitationId: server.invitationId);
    expect(pending.value, isNull);
  });
  test(
    'lost registration response preserves invitation, retry requires login',
    () async {
      final sessions = MemorySessionStore();
      var repo = await open('recipient', sessions);
      server.loseRegister = true;
      await expectLater(
        repo.registerWithInvitation(
          serverUrl: 'https://synthetic.invalid/kanboard',
          invitationToken: server.token,
          username: 'charlie',
          name: 'Synthetic recipient',
          password: 'synthetic-password',
        ),
        failure('network'),
      );
      expect(pending.value?.token, server.token);
      expect(server.members[server.scopeId]!.containsKey('charlie'), false);
      await repo.close();
      repositories.remove(repo);
      repo = await open('recipient', sessions);
      await expectLater(
        repo.registerWithInvitation(
          serverUrl: 'https://synthetic.invalid/kanboard',
          invitationToken: server.token,
          username: 'charlie',
          name: 'Synthetic recipient',
          password: 'synthetic-password',
        ),
        failure('invitation_authentication_required'),
      );
      expect(pending.value?.token, server.token);
      await login(repo, 'charlie');
      expect(repo.state.scopes, isEmpty);
      await repo.acceptInvitation(server.token);
      expect(repo.state.scopes.single.id, server.scopeId);
      expect(pending.value, isNull);
    },
  );
  test(
    'lost acceptance reply survives restart and cannot cross account identity',
    () async {
      final sessions = MemorySessionStore();
      var repo = await open('recipient', sessions);
      server.recipient = 'bob';
      await repo.previewInvitation(
        serverUrl: 'https://synthetic.invalid/kanboard',
        token: server.token,
      );
      await login(repo, 'bob');
      server.loseAccept = true;
      await expectLater(
        repo.acceptInvitation(server.token),
        failure('network'),
      );
      expect(pending.value?.accountPartition, repo.state.session!.partition);
      await repo.close();
      repositories.remove(repo);
      repo = await open('recipient', sessions);
      expect((await repo.pendingInvitation())?.token, server.token);
      await repo.previewInvitation(
        serverUrl: 'https://synthetic.invalid/kanboard',
        token: server.token,
      );
      expect(server.tokens[server.lastPreviewBearer], 'bob');
      await login(repo, 'alice');
      expect(await repo.pendingInvitation(), isNull);
      await expectLater(
        repo.acceptInvitation(server.token),
        failure('invitation_identity_mismatch'),
      );
      expect(server.acceptCalls, 1);
      await login(repo, 'bob');
      await repo.acceptInvitation(server.token);
      expect(pending.value, isNull);
      expect(server.acceptCalls, 2);
    },
  );
  test(
    'wrong recipient rejection preserves invitation for correct login',
    () async {
      final repo = await open('recipient', MemorySessionStore());
      server.recipient = 'bob';
      await repo.previewInvitation(
        serverUrl: 'https://synthetic.invalid/kanboard',
        token: server.token,
      );
      await login(repo, 'alice');
      await expectLater(
        repo.acceptInvitation(server.token),
        failure('invitation_invalid'),
      );
      expect(pending.value?.accountPartition, isNull);
      await login(repo, 'bob');
      await repo.acceptInvitation(server.token);
      expect(pending.value, isNull);
    },
  );
  test(
    'registration response from a different server identity never activates a session',
    () async {
      final sessions = MemorySessionStore(),
          repo = await open('recipient', sessions);
      server.changeRegisterIdentity = true;
      await expectLater(
        repo.registerWithInvitation(
          serverUrl: 'https://synthetic.invalid/kanboard',
          invitationToken: server.token,
          username: 'charlie',
          name: 'Synthetic recipient',
          password: 'synthetic-password',
        ),
        failure('server_identity_changed'),
      );
      expect(sessions.value, isNull);
      expect(repo.state.session, isNull);
      expect(pending.value?.serverId, server.serverId);
    },
  );
  test(
    'dismissal from an older dialog cannot remove a newer invitation',
    () async {
      final repo = await open('recipient', MemorySessionStore());
      await repo.rememberInvitation(
        serverUrl: 'https://synthetic.invalid/kanboard',
        token: server.token,
      );
      final newer = 'fhi2_${'b' * 64}';
      await repo.rememberInvitation(
        serverUrl: 'https://synthetic.invalid/kanboard',
        token: newer,
      );
      await repo.clearPendingInvitation(expectedToken: server.token);
      expect(pending.value?.token, newer);
    },
  );
  test(
    'server identity change and token retargeting are blocked before preview',
    () async {
      final repo = await open('recipient', MemorySessionStore());
      await repo.previewInvitation(
        serverUrl: 'https://synthetic.invalid/kanboard',
        token: server.token,
      );
      server.serverId = newSharedId();
      await expectLater(
        repo.previewInvitation(
          serverUrl: 'https://synthetic.invalid/kanboard',
          token: server.token,
        ),
        failure('server_identity_changed'),
      );
      expect(server.previewCalls, 1);
      await expectLater(
        repo.previewInvitation(
          serverUrl: 'https://other.invalid/',
          token: server.token,
        ),
        failure('invitation_identity_mismatch'),
      );
      expect(server.previewCalls, 1);
    },
  );
  test(
    'pending capability is stored before connectivity and requires HTTPS',
    () async {
      final repo = await open('recipient', MemorySessionStore());
      await repo.rememberInvitation(
        serverUrl: 'https://synthetic.invalid/kanboard',
        token: server.token,
      );
      expect(pending.value?.token, server.token);
      expect(server.previewCalls, 0);
      await expectLater(
        repo.rememberInvitation(
          serverUrl: 'http://127.0.0.1:18380',
          token: server.token,
          allowLocalHttp: true,
        ),
        failure('invalid_server_url'),
      );
    },
  );
}
