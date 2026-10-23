import 'dart:convert';

import 'crypto_json.dart';
import 'crypto_record_address.dart';

bool samePreauthorizationValue(Object? a, Object? b) =>
    base64Encode(CryptoJson.encode(a)) == base64Encode(CryptoJson.encode(b));

Map<String, dynamic> preauthorizedIdentity(Map member) => {
  for (final field in const {
    'accountId',
    'rootSigningKeyBase64',
    'rootEncryptionKeyBase64',
    'recoveryRootEpochId',
    'identityEpochId',
    'deviceSnapshotHash',
  })
    field: member[field],
};

/// Prepare/lifecycle metadata; authority is the owner's signed member roster.
void validateInvitationPreauthorizationMarker(Map value) {
  const fields = {
    'accountId',
    'invitationId',
    'preauthorizationProofHash',
    'invitationScopeId',
  };
  if (value.length != fields.length ||
      !fields.every(value.containsKey) ||
      !isCryptoCanonicalUuid(value['accountId']) ||
      !isCryptoCanonicalUuid(value['invitationId']) ||
      !isCryptoCanonicalUuid(value['invitationScopeId']) ||
      value['preauthorizationProofHash'] is! String ||
      !RegExp(r'^[a-f0-9]{64}$').hasMatch(value['preauthorizationProofHash'])) {
    throw const FormatException('crypto_invitation_preauthorization_marker');
  }
}
