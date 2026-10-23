import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/data/e2ee/crypto_invitation_display.dart';
import 'package:kanban/organizer/data/pending_invitation_store.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';

import '../../support/synthetic_content_route_guard.dart';
import '../collaboration_repository_test.dart'
    show FakeTransport, MemorySessionStore;
import '../email_invitation_repository_test.dart' show EmailServer;
import 'crypto_invitation_display_test.dart' show fixture, other;

class VerifiedEmailPreviewServer extends EmailServer {
  @override
  Map<String, dynamic> get preview {
    final display = fixture();
    final command = display['creatorAuthorization'] as Map;
    return {
      ...super.preview,
      ...display,
      'creatorAuthorization': command,
      'invitation': {...invitation, 'id': 'invitation', 'scopeId': 'scope'},
      'scope': {'id': 'scope', 'name': 'Encrypted space', 'kind': 'project'},
      'inviterEmail': 'owner@synthetic.invalid',
    };
  }
}

void main() {
  test('sender email remains optional account-bound host display metadata', () {
    final reply = fixture()..['inviterEmail'] = 'owner@synthetic.invalid';
    final display = parseCryptoInvitationDisplay(reply);
    expect(display['email'], 'owner@synthetic.invalid');
    expect(
      display.keys,
      unorderedEquals(['accountId', 'displayName', 'username', 'email']),
    );
  });
  test('email without creator account binding is never displayed', () {
    final reply = fixture()
      ..remove('inviterAccountId')
      ..['inviterEmail'] = 'unbound@synthetic.invalid';
    expect(parseCryptoInvitationDisplay(reply), isEmpty);
  });
  test('email cannot change the signed creator account binding', () {
    final reply = fixture()
      ..['inviterEmail'] = 'other@synthetic.invalid'
      ..['inviterAccountId'] = other;
    expect(() => parseCryptoInvitationDisplay(reply), throwsFormatException);
  });
  test('missing optional email preserves older host display labels', () {
    final display = parseCryptoInvitationDisplay(fixture());
    expect(display['email'], isNull);
    expect(display['username'], 'synthetic_owner');
  });
  test('malformed oversized or unsafe email metadata is rejected', () {
    for (final value in <Object>[
      '',
      'owner',
      '@synthetic.invalid',
      'owner@',
      'owner\nApproved@synthetic.invalid',
      'owner @synthetic.invalid',
      'owner@synthetic.invalid\u007f',
      'owner@synthetic.invalid\u202e',
      '${'x' * 255}@synthetic.invalid',
      12,
    ]) {
      expect(
        () => parseCryptoInvitationDisplay(fixture()..['inviterEmail'] = value),
        throwsFormatException,
      );
    }
  });
  test(
    'preview model carries optional email without changing admission state',
    () {
      final preview = SharedInvitationPreview(
        scopeName: 'Encrypted space',
        scopeId: 'scope',
        kind: SharedScopeKind.project,
        recipientUsername: 'recipient',
        role: SharedRole.member,
        expiresAt: DateTime.utc(2030),
        registrationAllowed: false,
        contractVersion: 4,
        inviterEmail: 'owner@synthetic.invalid',
      );
      expect(preview.inviterEmail, 'owner@synthetic.invalid');
      expect(preview.scopeNameAvailable, isFalse);
      expect(preview.awaitingApproval, isFalse);
    },
  );
  test(
    'public v4 preview parser carries bound sender email into review model',
    () async {
      final server = VerifiedEmailPreviewServer()..cryptoPreview = true;
      final repository = CollaborationRepository(
        CollaborationDatabase(NativeDatabase.memory()),
        FakeTransport(server),
        MemorySessionStore(),
        invitationStore: MemoryPendingInvitationStore(),
        contentRouteGuard: const SyntheticContentRouteGuard(),
      );
      try {
        await repository.initialize();
        final preview = await repository.previewInvitation(
          serverUrl: 'https://synthetic.invalid/kanboard',
          token: server.token,
        );
        expect(preview.inviterEmail, 'owner@synthetic.invalid');
        expect(preview.inviterUsername, 'synthetic_owner');
        expect(server.acceptCalls, 0);
        expect(server.registerCalls, 0);
      } finally {
        await repository.close();
      }
    },
  );
}
