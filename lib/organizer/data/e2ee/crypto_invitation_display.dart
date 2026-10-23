import 'crypto_json.dart';
import 'crypto_record_address.dart';

/// Optional host-authenticated labels, bound to the invitation creator account.
/// This does not verify an invitation, establish identity trust, or grant keys.
/// Older hosts omit these fields and retain the explicit unnamed fallback.
Map<String, String> parseCryptoInvitationDisplay(Map<String, dynamic> reply) {
  final id = reply['inviterAccountId'];
  if (id == null) return const {};
  final name = reply['inviterName'], username = reply['inviterUsername'];
  final email = reply['inviterEmail'];
  bool label(Object? value, int maximum, {bool empty = false}) =>
      value is String &&
      (empty || value.isNotEmpty) &&
      value.length <= maximum &&
      !value.contains(RegExp(r'[\x00-\x1f\x7f]'));
  if (!isCryptoCanonicalUuid(id) ||
      !label(name, 200, empty: true) ||
      !label(username, 100) ||
      email != null &&
          (!label(email, 254) ||
              !RegExp(r'^[\x21-\x7e]+$').hasMatch(email as String) ||
              email.indexOf('@') <= 0 ||
              email.lastIndexOf('@') == email.length - 1)) {
    throw const FormatException('crypto_invitation_display');
  }
  final proof = reply['creatorAuthorization'];
  if (proof is! Map) {
    throw const FormatException('crypto_invitation_display_binding');
  }
  final creator = CryptoJson.decode(cryptoBase64(proof['commandBase64']));
  final invitation = reply['invitation'];
  if (creator is! Map ||
      creator['accountId'] != id ||
      creator['version'] != 2 ||
      !const {
        'crypto2.invitations.create',
        'crypto2.invitations.resend',
        'crypto2.invitations.bridgeLegacy',
      }.contains(creator['operation']) ||
      invitation is! Map ||
      creator['operation'] != 'crypto2.invitations.bridgeLegacy' &&
          (creator['payload'] is! Map ||
              creator['payload']['invitationId'] != invitation['id'] ||
              creator['payload']['scopeId'] != invitation['scopeId'])) {
    throw const FormatException('crypto_invitation_display_binding');
  }
  return {
    'accountId': id as String,
    'displayName': name as String,
    'username': username as String,
    if (email != null) 'email': email as String,
  };
}
