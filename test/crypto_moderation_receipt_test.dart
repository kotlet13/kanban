import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_v2.dart';
import 'package:kanban/organizer/data/e2ee/crypto_json.dart';
import 'package:kanban/organizer/data/e2ee/crypto_moderation_receipt.dart';

void main() {
  test(
    'moderation retention card matches only exact own five-op intent',
    () async {
      for (final operation in CryptoModerationReceipt.operations) {
        final initial =
            operation.endsWith('report') || operation.endsWith('begin');
        final payload = initial
            ? {
                'sourceContext': {'scopeId': 'scope', 'domain': 'finance'},
              }
            : {'stageId': 'stage'};
        final body = {
          'version': 2,
          'operation': operation,
          'requestId': 'request',
          'payload': payload,
        };
        final raw = CryptoJson.encode(body);
        final hash = await cryptoSha256(raw);
        final signed = {
          'commandBase64': base64Encode(raw),
          'signatureBase64': base64Encode(List.filled(64, 7)),
        };
        final card = {
          'format': 'moderationReceiptDigest2',
          'operation': operation,
          'commandHash': hash,
          'signatureBase64': signed['signatureBase64'],
          'replayPayload': payload,
        };
        final receipt = {
          'requestId': 'request',
          'requestHash': hash,
          'authorizationRetained': false,
          'authorization': card,
        };
        Future<bool> verify(Map<String, dynamic> value, {String? op}) =>
            CryptoModerationReceipt.matches(
              signed: signed,
              operation: op ?? operation,
              requestHash: hash,
              receipt: value,
            );
        expect(await verify(receipt), isTrue);
        for (final replacement in [
          {...card, 'operation': 'crypto2.records.batch'},
          {...card, 'commandHash': '0' * 64},
          {...card, 'signatureBase64': base64Encode(List.filled(64, 8))},
          {
            ...card,
            'replayPayload': {'stageId': 'other'},
          },
          {...card, 'extra': true},
        ]) {
          expect(
            await verify({...receipt, 'authorization': replacement}),
            isFalse,
          );
        }
        expect(await verify(receipt, op: 'crypto2.records.batch'), isFalse);
        expect(await verify({...receipt, 'requestId': 'other'}), isFalse);
        expect(
          await verify({...receipt, 'authorizationRetained': true}),
          isFalse,
        );
      }
    },
  );
}
