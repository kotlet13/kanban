import 'dart:convert';

import 'crypto_capture_v3.dart';
import 'crypto_record_address.dart';

/// Private source facts only. This decoder grants no invitation authority and
/// deliberately does not emit a public plaintext digest or resend mail. The
/// original typed row remains in the recovery-wrapped account archive.
class CryptoMigrationInvitationSource {
  CryptoMigrationInvitationSource._({
    required this.context,
    required this.id,
    required this.scopeId,
    required this.facts,
    required this.typedRow,
  });
  final CryptoCaptureSourceContext context;
  final String id;
  final String? scopeId;
  final Map<String, dynamic> facts, typedRow;
  bool get isMail => context.sourceTable == 'familyhub_invitation_mail';

  /// Expiry is a read-time status, never a changing input to the immutable
  /// migration selection root. Mail's accepted_at is SMTP acceptance only.
  String statusAt(int epochSeconds) {
    if (isMail) return facts['state'] as String;
    if (facts['acceptedAtEpoch'] != null) return 'accepted';
    if (facts['revokedAtEpoch'] != null) return 'revoked';
    return (facts['expiresAtEpoch'] as int) <= epochSeconds
        ? 'expired'
        : 'pending';
  }
}

CryptoMigrationInvitationSource decodeCryptoMigrationInvitationSource({
  required CryptoCaptureSourceContext context,
  required Map<String, dynamic> row,
}) {
  if (!const {
        'familyhub_invitations',
        'familyhub_invitation_mail',
      }.contains(context.sourceTable) ||
      context.domain != 'private' ||
      context.scopeId != null ||
      !RegExp(r'^row:(0|[1-9][0-9]{0,14})$').hasMatch(context.sourceId)) {
    throw const FormatException('crypto_migration_invitation_context');
  }
  String? cell(String column, {bool nullable = false}) {
    final value = row[column];
    if (value is! Map ||
        value.length != 2 ||
        value['type'] is! String ||
        (value['type'] as String).isEmpty ||
        (value['type'] as String).length > 128 ||
        value['valueBase64'] != null && value['valueBase64'] is! String) {
      throw const FormatException('crypto_migration_invitation_cell');
    }
    if (value['valueBase64'] == null) {
      if (!nullable) {
        throw const FormatException('crypto_migration_invitation_null');
      }
      return null;
    }
    final encoded = value['valueBase64'] as String,
        bytes = base64Decode(encoded);
    if (base64Encode(bytes) != encoded) {
      throw const FormatException('crypto_migration_invitation_cell');
    }
    return utf8.decode(bytes, allowMalformed: false);
  }

  int? integer(String column, {bool nullable = false, bool positive = false}) {
    final text = cell(column, nullable: nullable);
    if (text == null) return null;
    final value = int.tryParse(text);
    if (value == null ||
        '$value' != text ||
        value < (positive ? 1 : 0) ||
        value > 9007199254740991) {
      throw const FormatException('crypto_migration_invitation_integer');
    }
    return value;
  }

  String? uuid(String column, {bool nullable = false}) {
    final value = cell(column, nullable: nullable);
    if (value != null && !isCryptoCanonicalUuid(value)) {
      throw const FormatException('crypto_migration_invitation_identity');
    }
    return value;
  }

  final mail = context.sourceTable == 'familyhub_invitation_mail';
  final id = uuid(mail ? 'invitation_id' : 'id')!;
  late final String? scope;
  late final Map<String, dynamic> facts;
  if (mail) {
    scope = null;
    final state = cell('state')!;
    // Retain a future mail state without treating it as permission to send.
    if (state.isEmpty || state.length > 20) {
      throw const FormatException('crypto_migration_invitation_mail_state');
    }
    final language = cell('language')!;
    if (!const ['sl', 'en'].contains(language)) {
      throw const FormatException('crypto_migration_invitation_mail_language');
    }
    facts = {
      'id': id,
      'state': state,
      'language': language,
      'tokenCipher': cell('token_cipher', nullable: true),
      'attempts': integer('attempts'),
      'nextAttemptEpoch': integer('next_attempt'),
      'leaseToken': cell('lease_token', nullable: true),
      'leaseUntilEpoch': integer('lease_until', nullable: true),
      'smtpAcceptedAtEpoch': integer('accepted_at', nullable: true),
    };
  } else {
    scope = uuid('scope_id')!;
    final role = cell('role')!, tokenHash = cell('token_hash')!;
    if (!const ['member', 'viewer'].contains(role) ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(tokenHash)) {
      throw const FormatException('crypto_migration_invitation_fields');
    }
    final contract = integer('invitation_contract', positive: true)!;
    if (contract > 3) {
      throw const FormatException('crypto_migration_invitation_contract');
    }
    facts = {
      'id': id,
      'scopeId': scope,
      'creatorUserId': integer('creator_id', positive: true),
      'creatorAccountId': uuid('creator_account_id'),
      'recipientUsername': cell('recipient_username'),
      'recipientEmail': cell('recipient_email', nullable: true),
      'recipientAccountId': uuid('recipient_account_id', nullable: true),
      'role': role,
      'tokenHash': tokenHash,
      'createdAtEpoch': integer('created_at'),
      'expiresAtEpoch': integer('expires_at'),
      'acceptedAtEpoch': integer('accepted_at', nullable: true),
      'acceptedByUserId': integer(
        'accepted_by',
        nullable: true,
        positive: true,
      ),
      'acceptedAccountId': uuid('accepted_account_id', nullable: true),
      'revokedAtEpoch': integer('revoked_at', nullable: true),
      'contractVersion': contract,
      'accessScope': cell('access_scope', nullable: true),
    };
    if ((facts['expiresAtEpoch'] as int) < (facts['createdAtEpoch'] as int)) {
      throw const FormatException('crypto_migration_invitation_expiry');
    }
  }
  return CryptoMigrationInvitationSource._(
    context: context,
    id: id,
    scopeId: scope,
    facts: Map.unmodifiable(facts),
    typedRow: Map.unmodifiable(row),
  );
}

/// Closed minimal token-holder routing facts. Full row and mail state stay in
/// the private source archive, and no manager authority follows from this map.
Map<String, dynamic> cryptoLegacyInvitationMetadata(
  CryptoMigrationInvitationSource source,
) {
  if (source.isMail) {
    throw const FormatException('crypto_migration_invitation_kind');
  }
  final f = source.facts;
  return {
    'version': 3,
    'invitationId': source.id,
    'scopeId': source.scopeId,
    'recipient': {
      'kind': f['recipientEmail'] == null ? 'username' : 'email',
      'value': f['recipientEmail'] ?? f['recipientUsername'],
      'accountId': f['recipientAccountId'],
    },
    'role': f['role'],
    'expiresAtEpoch': f['expiresAtEpoch'],
    'acceptedAtEpoch': f['acceptedAtEpoch'],
    'revokedAtEpoch': f['revokedAtEpoch'],
    'legacyContractVersion': f['contractVersion'],
    'tokenHash': f['tokenHash'],
  };
}
