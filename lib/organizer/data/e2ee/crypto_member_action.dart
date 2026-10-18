import 'dart:convert';
import 'crypto_json.dart';

/// Local review correlation only. These signatures never replace scope or
/// account authority, and never imply approval of recovered historical data.
class CryptoMemberAction {
  static const domain = 'JivieE2EE/memberAction/v2\n';
  static const fields = {
    'version',
    'operation',
    'serverId',
    'accountId',
    'deviceId',
    'scopeId',
    'requestId',
    'reviewId',
    'sourceHeadHash',
    'targetAccountId',
    'membersHash',
    'authorDirectoryHeadHash',
  };

  static void requireBinding(Map body, Map expected) {
    if (body.length != fields.length ||
        !body.keys.every(fields.contains) ||
        expected.length != fields.length ||
        !expected.keys.every(fields.contains) ||
        body['version'] != 2 ||
        body['operation'] != 'removeMember' ||
        base64Encode(CryptoJson.encode(body)) !=
            base64Encode(CryptoJson.encode(expected))) {
      throw const FormatException('crypto_member_action_binding');
    }
  }

  static Map<String, dynamic> anchor(
    Map value, {
    required String actionProofHash,
    required String requestId,
    required String reviewId,
  }) {
    const shape = {
      'version',
      'actionProofHash',
      'requestId',
      'reviewId',
      'acceptedCandidateHistory',
    };
    if (value.length != shape.length ||
        !value.keys.every(shape.contains) ||
        value['version'] != 2 ||
        value['actionProofHash'] != actionProofHash ||
        value['requestId'] != requestId ||
        value['reviewId'] != reviewId ||
        value['acceptedCandidateHistory'] is! bool) {
      throw const FormatException('crypto_member_action_anchor');
    }
    return Map<String, dynamic>.from(value);
  }
}
