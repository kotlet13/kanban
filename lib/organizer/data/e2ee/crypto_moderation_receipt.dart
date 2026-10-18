import 'dart:convert';

import 'account_directory_v2.dart' show cryptoSha256;
import 'crypto_json.dart';

/// Matches a retention card against an already signed, immutable LOCAL request.
/// A card is outcome evidence only; it never supplies a signing key, new scope
/// authority, consent, or permission to import a quarantined backup request.
class CryptoModerationReceipt {
  static const operations = {
    'crypto2.moderation.report',
    'crypto2.moderation.disclosure.begin',
    'crypto2.moderation.disclosure.chunk',
    'crypto2.moderation.disclosure.complete',
    'crypto2.moderation.disclosure.abort',
  };
  static const _fields = {
    'format',
    'operation',
    'commandHash',
    'signatureBase64',
    'replayPayload',
  };

  static Future<bool> matches({
    required Map<String, dynamic> signed,
    required String operation,
    required String requestHash,
    required Map<String, dynamic> receipt,
  }) async {
    if (!operations.contains(operation) ||
        receipt['authorizationRetained'] != false ||
        receipt['authorization'] is! Map) {
      return false;
    }
    final card = receipt['authorization'] as Map;
    if (card.length != _fields.length ||
        !card.keys.every(_fields.contains) ||
        card['format'] != 'moderationReceiptDigest2' ||
        card['operation'] != operation ||
        card['commandHash'] != requestHash ||
        card['signatureBase64'] != signed['signatureBase64']) {
      return false;
    }
    try {
      final bytes = base64Decode(signed['commandBase64'] as String);
      if (await cryptoSha256(bytes) != requestHash) return false;
      final command = CryptoJson.decode(bytes) as Map;
      if (command['version'] != 2 ||
          command['operation'] != operation ||
          receipt['requestId'] != command['requestId'] ||
          receipt['requestHash'] != requestHash) {
        return false;
      }
      final payload = command['payload'] as Map;
      final Map<String, dynamic> expected;
      if (operation == 'crypto2.moderation.report' ||
          operation == 'crypto2.moderation.disclosure.begin') {
        final source = payload['sourceContext'] as Map;
        expected = {
          'sourceContext': {
            'scopeId': source['scopeId'],
            'domain': source['domain'],
          },
        };
      } else {
        expected = {'stageId': payload['stageId']};
      }
      return base64Encode(CryptoJson.encode(card['replayPayload'])) ==
          base64Encode(CryptoJson.encode(expected));
    } on FormatException {
      return false;
    } on TypeError {
      return false;
    }
  }
}
