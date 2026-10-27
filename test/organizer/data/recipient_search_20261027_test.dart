import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import '../support/synthetic_content_route_guard.dart';
import 'collaboration_repository_test.dart'
    show FakeServer, FakeTransport, MemorySessionStore;

const targetId = '00000000-0000-4000-a000-000000000777';

class SearchServer extends FakeServer {
  SearchServer({this.supported = true});
  bool supported;
  final searches = <Map<String, Object?>>[];
  final invitations = <Map<String, Object?>>[];
  int capabilityReads = 0;
  Map<String, dynamic> response = {
    'recipients': [
      {
        'accountId': targetId,
        'username': 'bob_example',
        'displayName': 'Bob Example',
      },
    ],
  };
  Completer<Map<String, dynamic>>? pending;
  @override
  Future<Map<String, dynamic>> call(
    String op,
    Map<String, Object?> params,
    String? token,
  ) async {
    if (op == 'capabilities') {
      capabilityReads++;
      final caps = await super.call(op, params, token);
      return {
        ...caps,
        'invitationContractVersions': [1, 3],
        'spaceAccessPolicyVersions': [3],
        'features': <String, dynamic>{
          ...caps['features'] as Map,
          'scopedInvitations': true,
          'spaceProjectMembership': true,
          'usernameInvitations': true,
          'recipientSearch': supported,
          'emailInvitations': false,
        },
      };
    }
    if (op == 'scopes.create') {
      final reply = await super.call(op, params, token);
      final id = params['id'] as String;
      scopes[id]!['accessPolicyVersion'] = 3;
      return {
        ...reply,
        'scope': {...scopes[id]!, 'role': 'owner'},
      };
    }
    if (op == 'recipients.search') {
      searches.add(params);
      return pending == null ? response : pending!.future;
    }
    if (op == 'invitations3.create') {
      invitations.add(params);
      return {
        'invitation': {
          'id': 'invite-search',
          'scopeId': params['scopeId'],
          'recipientUsername': params['recipient'],
          'recipientEmail': null,
          'role': params['role'],
          'expiresAt': 4102444800,
          'contractVersion': 3,
          'accessScope': 'space',
        },
        'deliveryQueued': false,
      };
    }
    return super.call(op, params, token);
  }
}

Future<(CollaborationRepository, SearchServer, String)> fixture({
  bool supported = true,
}) async {
  final server = SearchServer(supported: supported);
  final repo = CollaborationRepository(
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
  await repo.createScope('Search household', address: 'Street 1');
  return (repo, server, repo.state.scopes.single.id);
}

void main() {
  test(
    'search sends one bounded same-scope metadata call; selection binds exact account to ordinary invite',
    () async {
      final (repo, server, scope) = await fixture();
      addTearDown(repo.close);
      final reads = server.capabilityReads;
      final result = await repo.searchInvitationRecipients(
        scopeId: scope,
        query: '  Bo  ',
      );
      expect(server.searches, [
        {'scopeId': scope, 'query': 'Bo'},
      ]);
      expect(server.capabilityReads, reads);
      expect(result.single.accountId, targetId);
      expect(result.single.displayName, 'Bob Example');
      await repo.createRecipientInvitation(
        scopeId: scope,
        recipient: result.single.username,
        recipientAccountId: result.single.accountId,
        requestId: 'stable-invite-request',
      );
      expect(server.invitations.single['recipient'], 'bob_example');
      expect(server.invitations.single['recipientAccountId'], targetId);
      expect(server.invitations.single['requestId'], 'stable-invite-request');
    },
  );
  test(
    'old server disables search while exact username invitation stays compatible',
    () async {
      final (repo, server, scope) = await fixture(supported: false);
      addTearDown(repo.close);
      expect(repo.state.recipientSearchSupported, isFalse);
      expect(
        await repo.searchInvitationRecipients(scopeId: scope, query: 'Bo'),
        isEmpty,
      );
      expect(server.searches, isEmpty);
      await repo.createRecipientInvitation(
        scopeId: scope,
        recipient: 'exact_bob',
      );
      expect(server.invitations.single['recipient'], 'exact_bob');
      expect(
        server.invitations.single.containsKey('recipientAccountId'),
        isFalse,
      );
    },
  );
  test(
    'short oversized and email queries produce no directory requests',
    () async {
      final (repo, server, scope) = await fixture();
      addTearDown(repo.close);
      for (final value in ['', 'a', 'x' * 65, 'bob@example.invalid']) {
        expect(
          await repo.searchInvitationRecipients(scopeId: scope, query: value),
          isEmpty,
        );
      }
      expect(server.searches, isEmpty);
    },
  );
  test('malformed private directory response is rejected', () async {
    final (repo, server, scope) = await fixture();
    addTearDown(repo.close);
    server.response = {
      'recipients': [
        {
          'accountId': targetId,
          'username': 'bob',
          'displayName': 'Bob',
          'email': 'private@example.invalid',
        },
      ],
    };
    await expectLater(
      repo.searchInvitationRecipients(scopeId: scope, query: 'Bo'),
      throwsA(
        isA<CollaborationException>().having(
          (e) => e.code,
          'code',
          'invalid_response',
        ),
      ),
    );
  });
  test(
    'deleted local scope refuses recipient lookup before any transport',
    () async {
      final (repo, server, scope) = await fixture();
      addTearDown(repo.close);
      final rows = await repo.database.rows(
        'SELECT data FROM scopes WHERE id=?',
        [scope],
      );
      final data = Map<String, dynamic>.from(
        jsonDecode(rows.single['data'] as String) as Map,
      );
      await repo.database.execute('UPDATE scopes SET data=? WHERE id=?', [
        jsonEncode({...data, 'deleted': true}),
        scope,
      ]);
      await repo.refreshLocal();
      await expectLater(
        repo.searchInvitationRecipients(scopeId: scope, query: 'Bo'),
        throwsA(
          isA<CollaborationException>().having(
            (error) => error.code,
            'code',
            'permission_revoked',
          ),
        ),
      );
      expect(server.searches, isEmpty);
    },
  );
  test(
    'logout prevents a pending recipient result from crossing accounts',
    () async {
      final (repo, server, scope) = await fixture();
      addTearDown(repo.close);
      server.pending = Completer<Map<String, dynamic>>();
      final result = repo.searchInvitationRecipients(
        scopeId: scope,
        query: 'Bo',
      );
      final rejected = expectLater(
        result,
        throwsA(isA<CollaborationException>()),
      );
      while (server.searches.isEmpty) {
        await Future<void>.delayed(Duration.zero);
      }
      await repo.signOut();
      server.pending!.complete(server.response);
      await rejected;
    },
  );
}
