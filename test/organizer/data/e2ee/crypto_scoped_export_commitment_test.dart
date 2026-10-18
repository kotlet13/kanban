import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_v2.dart';
import 'package:kanban/organizer/data/e2ee/crypto_business_json.dart';
import 'package:kanban/organizer/data/e2ee/crypto_json.dart';
import 'package:kanban/organizer/data/e2ee/crypto_scoped_exports.dart';

void main() {
  test(
    'randomized disclosure commitment binds secret salt, exact context and finite business values',
    () async {
      final body = <String, dynamic>{
        'version': 2,
        'serverId': 'server',
        'scopeId': 'target',
        'purpose': 'paymentSource',
        'membershipHeadHash': '1' * 64,
        'sourceScopeToken': '2' * 64,
        'subjectToken': '3' * 64,
        'sourceMembershipHeadHash': '4' * 64,
        'sourceRecordProofHash': '5' * 64,
        'sourceRevision': 7,
        'accountId': 'issuer',
        'deviceId': 'device',
        'deviceSnapshotHash': '6' * 64,
      };
      final disclosure = <String, dynamic>{
        'amountMinor': 123,
        'name': 'PRIVATE_NAME',
        'nested': {'fraction': 1.25},
      };
      final salt = Uint8List.fromList(List.generate(32, (i) => i));
      Future<String> commitment(Map c, Map<String, dynamic> value, String s) =>
          CryptoScopedExports.disclosureHash(
            disclosure: value,
            proofBody: c,
            disclosureSaltBase64: s,
          );
      final actual = await commitment(body, disclosure, base64Encode(salt));
      final expected = await cryptoSha256([
        ...utf8.encode('JivieScopedDisclosureCommitment/v2\n'),
        ...CryptoJson.encode(body),
        10,
        ...salt,
        ...CryptoBusinessJson.encode(disclosure),
      ]);
      expect(actual, expected);
      expect(actual, isNot(await CryptoBusinessJson.hash(disclosure)));
      expect(
        await commitment(body, disclosure, base64Encode(Uint8List(32))),
        isNot(actual),
      );
      for (final field in body.keys) {
        final changed = {
          ...body,
          field: field == 'version' || field == 'sourceRevision'
              ? 99
              : 'changed',
        };
        expect(
          await commitment(changed, disclosure, base64Encode(salt)),
          isNot(actual),
          reason: field,
        );
      }
      expect(
        await commitment(body, {
          ...disclosure,
          'amountMinor': 124,
        }, base64Encode(salt)),
        isNot(actual),
      );
      await expectLater(
        commitment(body, disclosure, base64Encode(Uint8List(31))),
        throwsFormatException,
      );
    },
  );
}
