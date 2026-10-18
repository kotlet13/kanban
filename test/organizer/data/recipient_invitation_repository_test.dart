import '../support/synthetic_content_route_guard.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'collaboration_repository_test.dart'
    show FakeServer, FakeTransport, MemorySessionStore;

class _RecipientServer extends FakeServer {
  bool enabled = true;
  final wire = <(String, Map<String, Object?>)>[];
  late String scopeId;
  Map<String, dynamic> invitation(String id) => {
    'id': id,
    'scopeId': scopeId,
    'recipientUsername': 'bob',
    'recipientEmail': null,
    'role': 'member',
    'expiresAt': 4102444800,
    'contractVersion': 3,
    'accessScope': 'space',
  };
  @override
  Future<Map<String, dynamic>> call(
    String op,
    Map<String, Object?> params,
    String? token,
  ) async {
    wire.add((op, params));
    if (op == 'capabilities') {
      final caps = await super.call(op, params, token);
      return {
        ...caps,
        'invitationContractVersions': [1, 3],
        'spaceAccessPolicyVersions': [3],
        'features': <String, dynamic>{
          ...caps['features'] as Map,
          'scopedInvitations': true,
          'spaceProjectMembership': true,
          'usernameInvitations': enabled,
          'invitationResend': enabled,
          'emailInvitations': false,
        },
      };
    }
    if (op == 'scopes.create') {
      final result = await super.call(op, params, token);
      scopeId = params['id'] as String;
      scopes[scopeId]!['accessPolicyVersion'] = 3;
      return {
        ...result,
        'scope': {...scopes[scopeId]!, 'role': 'owner'},
      };
    }
    if (op == 'invitations3.create' || op == 'invitations3.resend') {
      return {'invitation': invitation('invite-one'), 'deliveryQueued': false};
    }
    if (op == 'invitations3.pending') {
      return {
        'invitations': [
          {
            'invitation': invitation('invite-one'),
            'scope': scopes[scopeId],
            'registrationAllowed': false,
            'requiresExplicitAcceptance': true,
          },
        ],
      };
    }
    return super.call(op, params, token);
  }
}

void main() {
  late _RecipientServer server;
  late CollaborationRepository repo;
  setUp(() async {
    server = _RecipientServer();
    repo = CollaborationRepository(
      CollaborationDatabase(NativeDatabase.memory()),
      FakeTransport(server),
      MemorySessionStore(),
      contentRouteGuard: const SyntheticContentRouteGuard(),
    );
    await repo.initialize();
    await repo.login(
      serverUrl: 'https://synthetic.invalid',
      username: 'alice',
      password: 'synthetic',
    );
    await repo.createScope('Home', address: 'Street 1');
  });
  tearDown(() => repo.close());
  test(
    'existing username uses explicit scoped contract with stable request and no mail',
    () async {
      final invite = await repo.createRecipientInvitation(
        scopeId: server.scopeId,
        recipient: 'bob',
        requestId: 'same-request',
        accessScope: 'space',
      );
      expect(invite.deliveryQueued, false);
      expect(invite.recipientEmail, isNull);
      expect(repo.state.usernameInvitationsSupported, true);
      expect(repo.state.emailInvitationsSupported, false);
      final create = server.wire
          .lastWhere((c) => c.$1 == 'invitations3.create')
          .$2;
      expect(create['recipient'], 'bob');
      expect(create['requestId'], 'same-request');
      expect(create.containsKey('recipientEmail'), false);
      expect(server.wire.any((c) => c.$1 == 'invitations.create'), false);
      expect(
        server.wire.lastWhere((c) => c.$1 == 'scopes.create').$2['address'],
        'Street 1',
      );
    },
  );
  test(
    'SMTP-off username inbox loads scoped pending without legacy email request',
    () async {
      final pending = await repo.pendingInvitations();
      expect(pending.single.recipientUsername, 'bob');
      expect(pending.single.contractVersion, 3);
      expect(server.wire.any((c) => c.$1 == 'invitations2.pending'), false);
    },
  );
  test('resend uses one atomic endpoint and caller request ID', () async {
    await repo.resendInvitation(
      scopeId: server.scopeId,
      invitationId: 'old',
      requestId: 'retry',
    );
    await repo.resendInvitation(
      scopeId: server.scopeId,
      invitationId: 'old',
      requestId: 'retry',
    );
    final wire = server.wire
        .where((c) => c.$1 == 'invitations3.resend')
        .toList();
    expect(wire, hasLength(2));
    expect(wire.first.$2, wire.last.$2);
    expect(server.wire.any((c) => c.$1.contains('revoke')), false);
  });
  test(
    'older capabilities never fall back to unsafe legacy username invitation',
    () async {
      server.enabled = false;
      await expectLater(
        repo.createRecipientInvitation(
          scopeId: server.scopeId,
          recipient: 'bob',
        ),
        throwsA(
          isA<CollaborationException>().having(
            (e) => e.code,
            'code',
            'username_invitations_unavailable',
          ),
        ),
      );
      expect(
        server.wire.any(
          (c) => c.$1 == 'invitations.create' || c.$1 == 'invitations3.create',
        ),
        false,
      );
    },
  );
}
