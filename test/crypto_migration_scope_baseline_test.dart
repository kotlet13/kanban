import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/e2ee/crypto_migration_scope_baseline.dart';

const scope = '11111111-1111-4111-8111-111111111111';
const owner = '22222222-2222-4222-8222-222222222222';
const reader = '33333333-3333-4333-8333-333333333333';

Future<Map<String, dynamic>> baseline({
  String policy = '2',
  String enabled = '1',
  String revision = '7',
  bool absent = false,
  bool inactive = false,
  String actualOwner = owner,
  String kind = 'organization',
  List<Map<String, String?>> rawGrants = const [],
}) => CryptoMigrationScopeBaseline.fromRows(
  scopeId: scope,
  accountId: owner,
  scopes: [
    {'id': scope, 'kind': kind, 'access_policy_version': policy},
  ],
  policies: absent
      ? []
      : [
          {
            'scope_id': scope,
            'enabled': enabled,
            'revision': revision,
            'required_contract_version': '3',
          },
        ],
  members: [
    {
      'scope_id': scope,
      'account_id': actualOwner,
      'role': 'owner',
      'active': '1',
    },
    {
      'scope_id': scope,
      'account_id': reader,
      'role': 'member',
      'active': inactive ? '0' : '1',
    },
  ],
  grants: rawGrants,
  leaders: [
    {'scope_id': scope, 'account_id': owner},
    {'scope_id': scope, 'account_id': reader},
  ],
);

void main() {
  test(
    'complete owner baseline preserves exact minimal finance revision and leaders',
    () async {
      expect(await baseline(), {
        'financePolicy': {
          'enabled': true,
          'revision': 7,
          'requiredContractVersion': 3,
          'grantCount': 0,
          'policyHash':
              '6c64c06741f0ba9d31d29bd20025a21d0270f2bdd62f451c2ad20687bb6ffa82',
        },
        'leaderAccountIds': [reader],
      });
    },
  );
  test(
    'owner implicit, inactive leaders excluded, policy3 dormant leaders excluded',
    () async {
      expect((await baseline(inactive: true))['leaderAccountIds'], isEmpty);
      expect((await baseline(policy: '3'))['leaderAccountIds'], isEmpty);
      expect(
        (await baseline(kind: 'household')).containsKey('leaderAccountIds'),
        isFalse,
      );
    },
  );
  test(
    'dormant raw grants remain in the exact hash without becoming leaders',
    () async {
      final result = await baseline(
        inactive: true,
        rawGrants: const [
          {'scope_id': scope, 'account_id': reader, 'access_level': 'none'},
        ],
      );
      expect(result['leaderAccountIds'], isEmpty);
      expect((result['financePolicy'] as Map)['grantCount'], 1);
      expect(
        (result['financePolicy'] as Map)['policyHash'],
        isNot((await baseline())['financePolicy']['policyHash']),
      );
    },
  );
  test(
    'absent policy has closed legacy default without invented grants',
    () async {
      expect((await baseline(absent: true))['financePolicy'], {
        'enabled': false,
        'revision': 0,
        'requiredContractVersion': 1,
        'grantCount': 0,
        'policyHash':
            '2253baa64505e1d23a9f609022f16ad6e543d3d06b25ad7a33d1717b3499936b',
      });
    },
  );
  test(
    'malformed values, unsafe revision and wrong owner fail closed',
    () async {
      await expectLater(baseline(enabled: 'true'), throwsFormatException);
      await expectLater(baseline(revision: '-1'), throwsFormatException);
      await expectLater(
        baseline(revision: '9007199254740992'),
        throwsFormatException,
      );
      expect(
        () => baseline(actualOwner: '44444444-4444-4444-8444-444444444444'),
        throwsFormatException,
      );
      await expectLater(baseline(policy: '0'), throwsFormatException);
    },
  );
}
