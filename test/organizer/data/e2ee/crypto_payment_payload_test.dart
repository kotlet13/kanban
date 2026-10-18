import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/e2ee/crypto_payment_payload.dart';

void main() {
  test(
    'unknown payment and nested leg fields survive updates and exact removals',
    () {
      final previous = {
        'future': {'a': 1},
        'reimbursements': [
          {
            'legId': 'one',
            'amountMinor': 12,
            'futureLeg': {'x': 7},
          },
          {'legId': 'removed', 'amountMinor': 1},
        ],
        'paymentLink': {'kind': 'advance', 'futureLink': true},
      };
      final next =
          mergeCryptoPaymentPayload(previous, {
                'revision': 2,
                'reimbursements': [
                  {'legId': 'one', 'amountMinor': 13},
                  {'legId': 'two', 'amountMinor': 2},
                ],
                'paymentLink': {'kind': 'advance', 'eventRevision': 2},
              })
              as Map;
      expect(next['future'], {'a': 1});
      expect(next['paymentLink'], {
        'kind': 'advance',
        'futureLink': true,
        'eventRevision': 2,
      });
      expect(next['reimbursements'], [
        {
          'legId': 'one',
          'amountMinor': 13,
          'futureLeg': {'x': 7},
        },
        {'legId': 'two', 'amountMinor': 2},
      ]);
      expect(
        mergeCryptoPaymentPayload(next, {'reimbursements': []}) is Map,
        true,
      );
      expect(
        (mergeCryptoPaymentPayload(next, {'reimbursements': []})
            as Map)['reimbursements'],
        isEmpty,
      );
    },
  );
  test(
    '500 reimbursement legs fit bounded catchup without truncation or duplicate IDs',
    () {
      final legs = List.generate(500, (i) => 'leg-$i'),
          groups = cryptoPaymentCatchupGroups(legs);
      expect(groups, hasLength(17));
      expect(groups.every((g) => g.length <= 31), true);
      expect(groups.expand((g) => g).toList(), legs);
      expect(
        cryptoPaymentCatchupGroups(legs.sublist(31)).expand((g) => g).toSet(),
        legs.sublist(31).toSet(),
      );
      expect(
        () => cryptoPaymentCatchupGroups(legs, capacity: 32),
        throwsArgumentError,
      );
    },
  );
}
