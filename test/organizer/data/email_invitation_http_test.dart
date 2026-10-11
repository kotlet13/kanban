// Opt-in private loopback TLS+SMTP fixture. No external mail or production data.
// KANBAN_EMAIL_HTTP_FIXTURE=/absolute/private/fixture.json flutter test ...
import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/io_client.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/data/collaboration_transport.dart';
import 'package:kanban/organizer/data/pending_invitation_store.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'collaboration_repository_test.dart' show MemorySessionStore;

class LostReplyHttpTransport implements CollaborationTransport {
  LostReplyHttpTransport(String certificatePath)
    : inner = HttpCollaborationTransport(
        client: IOClient(
          HttpClient(
            context: SecurityContext(withTrustedRoots: false)
              ..setTrustedCertificates(certificatePath),
          ),
        ),
      );
  final HttpCollaborationTransport inner;
  String? loseNextOperation;
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
    final result = await inner.call(
      serverUrl: serverUrl,
      operation: operation,
      params: params,
      token: token,
      allowLocalHttp: allowLocalHttp,
    );
    if (operation == loseNextOperation) {
      loseNextOperation = null;
      throw const CollaborationException('network');
    }
    return result;
  }

  @override
  void close() => inner.close();
}

void main() {
  final fixturePath = Platform.environment['KANBAN_EMAIL_HTTP_FIXTURE'];
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  test(
    'actual TLS HTTP+SMTP invitation: lost registration/acceptance, disk restart and verified existing recipient',
    () async {
      final fixture =
          jsonDecode(await File(fixturePath!).readAsString())
              as Map<String, dynamic>;
      final server = fixture['server'] as String,
          certificate = fixture['certificatePath'] as String;
      if (fixture['synthetic'] != true ||
          Uri.parse(server).scheme != 'https' ||
          Uri.parse(server).host != 'localhost') {
        throw StateError('Synthetic localhost TLS fixture required');
      }
      final container = fixture['container'] as String,
          capturePath = fixture['capturePath'] as String;
      if (!container.startsWith('kanban-familyhub-account-email-') ||
          !capturePath.startsWith('/tmp/familyhub-smtp-')) {
        throw StateError('Dedicated synthetic SMTP container required');
      }
      final owner = fixture['owner'] as Map<String, dynamic>,
          directory = await Directory.systemTemp.createTemp(
            'email-http-sqlite-',
          );
      final repositories = <CollaborationRepository>[];
      final pending = MemoryPendingInvitationStore(),
          sessions = MemorySessionStore();
      Future<CollaborationRepository> open(
        String name,
        MemorySessionStore store,
        LostReplyHttpTransport transport,
      ) async {
        final repo = CollaborationRepository(
          CollaborationDatabase(
            NativeDatabase(File('${directory.path}/$name.sqlite')),
          ),
          transport,
          store,
          invitationStore: name == 'recipient'
              ? pending
              : MemoryPendingInvitationStore(),
        );
        repositories.add(repo);
        await repo.initialize();
        return repo;
      }

      Future<String> deliveredToken(String recipient) async {
        if (!recipient.endsWith('@capture.invalid')) {
          throw StateError('Synthetic recipient required');
        }
        final result = await Process.run('docker', [
          'exec',
          container,
          'php',
          '-r',
          r'require "/var/www/app/app/common.php"; if(session_status()===PHP_SESSION_ACTIVE){session_abort();} $r=(new \Kanboard\Plugin\FamilyHub\Model\NativeAccountMailQueue($container))->run(20); if($r["accepted"]<1){exit(3);} $j=json_decode(file_get_contents($argv[1]),true); $tokens=[]; foreach($j["messages"] as $m){if(in_array($argv[2],$m["recipients"],true)){preg_match_all("/fhi2_[a-f0-9]{64}/",quoted_printable_decode($m["body"]),$found);$tokens=array_merge($tokens,$found[0]);}} echo json_encode($tokens);',
          capturePath,
          recipient,
        ]);
        if (result.exitCode != 0) {
          throw StateError('Synthetic SMTP dispatch failed');
        }
        final tokens = (jsonDecode(result.stdout as String) as List)
            .cast<String>();
        expect(
          tokens,
          isNotEmpty,
          reason: 'Actual SMTP must contain an invitation token',
        );
        return tokens.last;
      }

      Matcher failure(String code) => throwsA(
        isA<CollaborationException>().having((e) => e.code, 'code', code),
      );
      try {
        final a = await open(
          'owner',
          MemorySessionStore(),
          LostReplyHttpTransport(certificate),
        );
        await a.enroll(
          serverUrl: server,
          code:
              (fixture['bootstrap'] as Map<String, dynamic>)['code'] as String,
          username: owner['username'] as String,
          password: owner['password'] as String,
          name: owner['displayName'] as String,
        );
        expect(a.state.emailInvitationsSupported, true);
        final scope = await a.createScope('Synthetic email household');
        final username =
                'email_${newSharedId().replaceAll('-', '').substring(0, 16)}',
            email = '$username@capture.invalid',
            password = 'Synthetic-${newSharedId()}';
        final invite = await a.createEmailInvitation(
          scopeId: scope,
          recipientEmail: email,
        );
        expect(invite.token, isNull);
        expect(invite.deliveryQueued, true);
        final token = await deliveredToken(email);
        var transport = LostReplyHttpTransport(certificate),
            b = await open('recipient', sessions, transport);
        transport.loseNextOperation = 'auth.registerInvitation2';
        await expectLater(
          b.registerWithInvitation(
            serverUrl: server,
            invitationToken: token,
            username: username,
            name: 'Synthetic recipient',
            password: password,
          ),
          failure('network'),
        );
        expect(pending.value?.token, token);
        await b.close();
        repositories.remove(b);
        transport = LostReplyHttpTransport(certificate);
        b = await open('recipient', sessions, transport);
        await expectLater(
          b.registerWithInvitation(
            serverUrl: server,
            invitationToken: token,
            username: username,
            name: 'Synthetic recipient',
            password: password,
          ),
          failure('invitation_authentication_required'),
        );
        await b.login(
          serverUrl: server,
          username: username,
          password: password,
        );
        expect(
          b.state.scopes.any((s) => s.id == scope),
          false,
          reason: 'Registration and login must not join the invited space',
        );
        expect((await b.accountStatus()).emailVerified, true);
        expect((await b.pendingInvitations()).single.invitationId, invite.id);
        transport.loseNextOperation = 'invitations2.accept';
        await expectLater(b.acceptInvitation(token), failure('network'));
        expect(pending.value?.accountPartition, b.state.session!.partition);
        await b.close();
        repositories.remove(b);
        b = await open(
          'recipient',
          sessions,
          LostReplyHttpTransport(certificate),
        );
        final recovered = await b.previewInvitation(
          serverUrl: server,
          token: token,
        );
        expect(recovered.scopeId, scope);
        await b.acceptInvitation(token);
        expect(b.state.scopes.any((s) => s.id == scope), true);
        expect(pending.value, isNull);
        final secondScope = await a.createScope(
          'Synthetic existing recipient household',
        );
        final second = await a.createEmailInvitation(
          scopeId: secondScope,
          recipientEmail: email,
        );
        final secondToken = await deliveredToken(email);
        await expectLater(
          a.acceptEmailInvitation(invitationId: second.id),
          failure('invitation_invalid'),
        );
        final outsider = await open(
          'outsider',
          MemorySessionStore(),
          LostReplyHttpTransport(certificate),
        );
        await expectLater(
          outsider.registerWithInvitation(
            serverUrl: server,
            invitationToken: secondToken,
            username: '${username}_other',
            name: 'Must not create another account',
            password: password,
          ),
          failure('invitation_authentication_required'),
        );
        await b.signOut();
        await b.login(
          serverUrl: server,
          username: username,
          password: password,
        );
        final inbox = await b.pendingInvitations();
        expect(inbox.single.invitationId, second.id);
        await b.acceptEmailInvitation(invitationId: inbox.single.invitationId);
        expect(b.state.scopes.any((s) => s.id == secondScope), true);
        await b.acceptEmailInvitation(
          invitationId: second.id,
        ); // Idempotent repeat.
        expect(b.state.lastError, isNull);
      } finally {
        for (final repo in repositories) {
          await repo.close();
        }
        await directory.delete(recursive: true);
      }
    },
    skip: fixturePath == null
        ? 'Private opt-in loopback TLS/SMTP fixture required'
        : false,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
