import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/e2ee/crypto_finance_policy_actions.dart';

void main() {
  const owner = '11111111-1111-4111-8111-111111111111';
  const member = '22222222-2222-4222-8222-222222222222';
  CryptoFinancePolicySnapshot initial() => CryptoFinancePolicySnapshot(
    enabled: true,
    revision: 1,
    requiredContractVersion: 3,
    grants: [
      {'accountId': owner, 'grant': 'write'},
    ],
  );
  test(
    'finance policy canonical stream matches independent SHA256 vector',
    () async {
      expect(
        await initial().hash(),
        'ca7a386c20a792d13f1d50b8155bb84a72c3c7c726de2cd8851886e32d485264',
      );
      final granted = initial().apply({
        'kind': 'grant',
        'accountId': member,
        'grant': 'none',
      }, owner);
      expect(granted.revision, 2);
      expect(granted.grants, [
        {'accountId': owner, 'grant': 'write'},
        {'accountId': member, 'grant': 'none'},
      ]);
      expect(await granted.hash(), isNot(await initial().hash()));
      expect(
        granted.apply({'kind': 'enable', 'enabled': false}, owner).grants,
        granted.grants,
      );
    },
  );
  test(
    'complete policy rejects omitted/extra fields, invalid identity and duplicate grants',
    () {
      for (final grants in <List<Map<String, dynamic>>>[
        [
          {'accountId': owner, 'grant': 'write', 'other': true},
        ],
        [
          {'accountId': owner, 'grant': 'write'},
          {'accountId': owner, 'grant': 'none'},
        ],
        [
          {'accountId': member, 'grant': 'write'},
          {'accountId': owner, 'grant': 'none'},
        ],
        [
          {
            'accountId': '11111111-1111-8111-8111-111111111111',
            'grant': 'write',
          },
        ],
        [
          {'accountId': owner, 'grant': 'admin'},
        ],
      ]) {
        expect(
          () => CryptoFinancePolicySnapshot(
            enabled: true,
            revision: 1,
            requiredContractVersion: 3,
            grants: grants,
          ),
          throwsFormatException,
        );
      }
      expect(
        () => initial().apply({
          'kind': 'grant',
          'accountId': member,
          'grant': 'read',
          'unknown': 1,
        }, owner),
        throwsFormatException,
      );
      expect(
        () => CryptoFinancePolicySnapshot(
          enabled: true,
          revision: 9007199254740991,
          requiredContractVersion: 3,
          grants: [],
        ).apply({'kind': 'enable', 'enabled': true}, owner),
        throwsFormatException,
      );
    },
  );
}
