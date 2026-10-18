import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/e2ee/crypto_capture_v3.dart';
import 'package:kanban/organizer/data/e2ee/crypto_migration_invitations.dart';

void main() {
  const id = '11111111-1111-4111-8111-111111111111';
  const scope = '22222222-2222-4222-8222-222222222222';
  const account = '33333333-3333-4333-8333-333333333333';
  Map<String, dynamic> cell(Object? value) => {
    'type': 'text',
    'valueBase64': value == null ? null : base64Encode(utf8.encode('$value')),
  };
  CryptoCaptureSourceContext context(
    String table, {
    String ordinal = 'row:0',
  }) => CryptoCaptureSourceContext(
    serverId: id,
    captureId: scope,
    migrationId: account,
    accountId: account,
    scopeId: null,
    domain: 'private',
    sourceTable: table,
    sourceId: ordinal,
  );
  Map<String, dynamic> invite() => {
    'id': cell(id),
    'scope_id': cell(scope),
    'creator_id': cell(12),
    'creator_account_id': cell(account),
    'recipient_username': cell(''),
    'recipient_email': cell('recipient@example.invalid'),
    'recipient_account_id': cell(null),
    'role': cell('viewer'),
    'token_hash': cell('a' * 64),
    'created_at': cell(10),
    'expires_at': cell(100),
    'accepted_at': cell(null),
    'accepted_by': cell(null),
    'accepted_account_id': cell(null),
    'revoked_at': cell(null),
    'invitation_contract': cell(3),
    'access_scope': cell('space'),
    'future_sql': cell('preserve exact bytes'),
  };
  test(
    'private ordinal is distinct from native invitation identity and expiry is read-time only',
    () {
      final row = invite();
      final decoded = decodeCryptoMigrationInvitationSource(
        context: context('familyhub_invitations'),
        row: row,
      );
      expect(decoded.id, id);
      expect(decoded.scopeId, scope);
      expect(decoded.context.sourceId, 'row:0');
      expect(decoded.facts['recipientEmail'], 'recipient@example.invalid');
      expect(decoded.statusAt(99), 'pending');
      expect(decoded.statusAt(100), 'expired');
      expect(decoded.typedRow, row);
      expect(decoded.typedRow['future_sql'], row['future_sql']);
      expect(decoded.facts.containsKey('rawToken'), false);
      row['accepted_at'] = cell(50);
      row['accepted_by'] = cell(23);
      row['accepted_account_id'] = cell(account);
      final accepted = decodeCryptoMigrationInvitationSource(
        context: context('familyhub_invitations'),
        row: row,
      );
      expect(accepted.statusAt(1000), 'accepted');
      expect(accepted.facts['acceptedAtEpoch'], 50);
    },
  );
  test(
    'mail SMTP acceptance and pending lease state do not imply recipient membership or resend',
    () {
      final row = {
        'invitation_id': cell(id),
        'token_cipher': cell('OPAQUE_MAIL_CIPHER'),
        'language': cell('sl'),
        'state': cell('accepted'),
        'attempts': cell(2),
        'next_attempt': cell(90),
        'lease_token': cell(null),
        'lease_until': cell(null),
        'accepted_at': cell(45),
      };
      final decoded = decodeCryptoMigrationInvitationSource(
        context: context('familyhub_invitation_mail', ordinal: 'row:7'),
        row: row,
      );
      expect(decoded.facts['smtpAcceptedAtEpoch'], 45);
      expect(decoded.facts.containsKey('acceptedAccountId'), false);
      expect(decoded.facts['attempts'], 2);
      expect(decoded.facts['tokenCipher'], 'OPAQUE_MAIL_CIPHER');
      expect(decoded.typedRow, row);
      expect(decoded.scopeId, isNull);
    },
  );
  test(
    'numeric Kanboard invitations and malformed native coordinates never become native bridge facts',
    () {
      expect(
        () => decodeCryptoMigrationInvitationSource(
          context: context('familyhub_project_invitations'),
          row: {'id': cell('f' * 32), 'project_id': cell(12)},
        ),
        throwsFormatException,
      );
      expect(
        () => decodeCryptoMigrationInvitationSource(
          context: context('familyhub_invitations', ordinal: id),
          row: invite(),
        ),
        throwsFormatException,
      );
      final row = invite()..['id'] = cell('f' * 32);
      expect(
        () => decodeCryptoMigrationInvitationSource(
          context: context('familyhub_invitations'),
          row: row,
        ),
        throwsFormatException,
      );
      row['id'] = cell(id);
      row['expires_at'] = cell('0100');
      expect(
        () => decodeCryptoMigrationInvitationSource(
          context: context('familyhub_invitations'),
          row: row,
        ),
        throwsFormatException,
      );
      row['expires_at'] = cell(100);
      row['accepted_at'] = {'type': 'text', 'valueBase64': '=='};
      expect(
        () => decodeCryptoMigrationInvitationSource(
          context: context('familyhub_invitations'),
          row: row,
        ),
        throwsFormatException,
      );
    },
  );
}
