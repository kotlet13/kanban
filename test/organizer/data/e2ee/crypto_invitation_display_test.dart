import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/e2ee/crypto_invitation_display.dart';
import 'package:kanban/organizer/data/e2ee/crypto_json.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';

const creator = '00000000-0000-4000-a000-000000000001';
const other = '00000000-0000-4000-a000-000000000002';
Map<String, dynamic> fixture() => {
  'inviterAccountId': creator,
  'inviterUsername': 'synthetic_owner',
  'inviterName': 'Synthetic owner',
  'invitation': {'id': 'invitation', 'scopeId': 'scope'},
  'creatorAuthorization': {
    'commandBase64': base64Encode(
      CryptoJson.encode({
        'version': 2,
        'accountId': creator,
        'operation': 'crypto2.invitations.create',
        'payload': {'invitationId': 'invitation', 'scopeId': 'scope'},
      }),
    ),
  },
};

void main() {
  test('bound inviter labels expose display fields only', () {
    final reply = fixture()..['role'] = 'owner';
    expect(parseCryptoInvitationDisplay(reply), {
      'accountId': creator,
      'displayName': 'Synthetic owner',
      'username': 'synthetic_owner',
    });
  });
  test('old host missing account binding uses honest empty fallback', () {
    expect(
      parseCryptoInvitationDisplay({'inviterName': 'Unbound display'}),
      isEmpty,
    );
  });
  test('different creator account is rejected', () {
    expect(
      () =>
          parseCryptoInvitationDisplay(fixture()..['inviterAccountId'] = other),
      throwsFormatException,
    );
  });
  test('different invitation scope is rejected', () {
    final reply = fixture();
    (reply['invitation'] as Map)['scopeId'] = 'other-scope';
    expect(() => parseCryptoInvitationDisplay(reply), throwsFormatException);
  });
  test('oversized or multiline labels are rejected', () {
    for (final change in [
      {'inviterName': 'x' * 201},
      {'inviterUsername': 'x' * 101},
      {'inviterName': 'Owner\nApproved'},
      {'inviterUsername': ''},
    ]) {
      expect(
        () => parseCryptoInvitationDisplay(fixture()..addAll(change)),
        throwsFormatException,
      );
    }
  });
  test('malformed creator proof cannot label an invitation', () {
    expect(
      () => parseCryptoInvitationDisplay(
        fixture()..remove('creatorAuthorization'),
      ),
      throwsFormatException,
    );
  });
  test(
    'v4 model explicitly defaults to unavailable title, old previews retain title',
    () {
      SharedInvitationPreview preview(int version) => SharedInvitationPreview(
        scopeName: 'Encrypted space',
        scopeId: 'scope',
        kind: SharedScopeKind.project,
        recipientUsername: 'recipient',
        role: SharedRole.member,
        expiresAt: DateTime.utc(2030),
        registrationAllowed: false,
        contractVersion: version,
      );
      expect(preview(4).scopeNameAvailable, isFalse);
      expect(preview(3).scopeNameAvailable, isTrue);
    },
  );
}
