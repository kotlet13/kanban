import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/domain/linked_payment_models.dart';
import 'package:kanban/organizer/domain/shared_finance_models.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'package:kanban/organizer/domain/finance_forecast.dart';

const source = '11111111-1111-4111-a111-111111111111';
const entryId = '22222222-2222-4222-a222-222222222222';
const eventId = '33333333-3333-4333-a333-333333333333';
const actor = '44444444-4444-4444-a444-444444444444';
const ledger = '55555555-5555-4555-a555-555555555555';
const card = '66666666-6666-4666-a666-666666666666';
PaymentEvent event({
  int revision = 1,
  String? partition,
  bool expected = true,
  List<PaymentReimbursement> legs = const [],
}) => PaymentEvent(
  eventId: eventId,
  sourceScopeId: source,
  sourceEntryId: entryId,
  sourceRevision: 2,
  payerAccountId: actor,
  amountMinor: 3000,
  currency: 'EUR',
  paidAt: DateTime.utc(2026, 10, 9),
  expectReimbursement: expected,
  revision: revision,
  reimbursements: legs,
  sourcePartition: partition,
);
PaymentReimbursement refund(int amount, String id, int day) =>
    PaymentReimbursement(
      legId: id,
      amountMinor: amount,
      paidAt: DateTime.utc(2026, 10, day),
      approvedByAccountId: actor,
      organizationAccountId: ledger,
      organizationAccountScopeId: source,
    );
PaymentCashMovement cash(String id, String account, int amount, int day) =>
    PaymentCashMovement(
      id: id,
      accountId: account,
      amountMinor: amount,
      currency: 'EUR',
      paidAt: DateTime.utc(2026, 10, day),
    );

void main() {
  final now = DateTime.utc(2026, 10, 9);
  final account = SharedFinanceAccount(
    id: ledger,
    name: 'Organization',
    currency: 'EUR',
    createdAt: now,
    updatedAt: now,
  );
  final expense = SharedFinanceEntry(
    id: entryId,
    accountId: ledger,
    kind: FinanceEntryKind.expense,
    amountMinor: 3000,
    currency: 'EUR',
    title: 'Expense',
    occurredAt: now,
    createdAt: now,
    updatedAt: now,
  );
  final first = refund(1000, '77777777-7777-4777-a777-777777777777', 10);
  final second = refund(2000, '88888888-8888-4888-a888-888888888888', 11);
  test('refund decoder rejects normalized impossible calendar dates', () {
    expect(
      () => PaymentReimbursement.fromJson({
        ...first.toJson(),
        'paidAt': '2027-02-30T00:00:00Z',
      }),
      throwsFormatException,
    );
  });
  test(
    'source removed receipts preserve complete cash history without active receivable',
    () {
      final history = PaymentSnapshot(
        projections: [
          PaymentProjection(
            event: event(),
            state: PaymentProjectionState.sourceRemoved,
          ),
        ],
        cashMovements: [cash(eventId, card, -3000, 9)],
        fresh: true,
      );
      expect(history.complete, isTrue);
      expect(history.receivableByCurrency['EUR'], BigInt.zero);
      expect(history.cashBurdenByCurrency['EUR'], BigInt.from(3000));
    },
  );
  test(
    'quarantined backup validates refund payload and exact source identity',
    () {
      final params = {
        'scopeId': source,
        'eventId': eventId,
        'expectedRevision': 1,
        'legId': first.legId,
        'amountMinor': 1000,
        'paidAt': first.paidAt.toIso8601String(),
        'organizationAccountId': ledger,
        'requestId': eventId,
      };
      Map<String, dynamic> document(Map<String, Object?> body) => {
        'events': [],
        'projections': [],
        'cashMovements': [],
        'intents': [
          {
            'id': eventId,
            'state': 'quarantine',
            'data': jsonEncode({
              'source': PaymentSourceRef(
                space: const PaymentSpaceRef(source),
                entryId: entryId,
                expectedRevision: 1,
              ).toJson(),
              'sourceSpaceKey': 'local:$source',
              'operation': 'finance3.paymentReimburse',
              'params': body,
            }),
          },
        ],
      };
      validateLinkedPaymentsBackup(document(params));
      expect(
        () => validateLinkedPaymentsBackup(
          document({...params, 'amountMinor': -1}),
        ),
        throwsFormatException,
      );
      expect(
        () => validateLinkedPaymentsBackup(
          document({...params, 'scopeId': card}),
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'one expense remains 30 EUR while organization cash changes only for refund legs',
    () {
      final paid = PaymentSnapshot(events: [event()], fresh: true);
      var totals = summarizeSharedFinance(
        accounts: [account],
        entries: [expense],
        transfers: [],
        payments: paid,
      )['EUR']!;
      expect(totals.expenseMinor, BigInt.from(3000));
      expect(totals.balanceMinor, BigInt.zero);
      final settled = PaymentSnapshot(
        events: [
          event(revision: 3, legs: [first, second]),
        ],
        cashMovements: [
          cash(first.legId, ledger, -1000, 10),
          cash(second.legId, ledger, -2000, 11),
        ],
        fresh: true,
      );
      totals = summarizeSharedFinance(
        accounts: [account],
        entries: [expense],
        transfers: [],
        payments: settled,
      )['EUR']!;
      expect(totals.expenseMinor, BigInt.from(3000));
      expect(totals.incomeMinor, BigInt.zero);
      expect(totals.balanceMinor, BigInt.from(-3000));
    },
  );
  test(
    'personal cash and receivable settle 30 then 10 then 20 without expense copies',
    () {
      expect(event().receivableMinor, 3000);
      expect(event(revision: 2, legs: [first]).receivableMinor, 2000);
      final settled = event(revision: 3, legs: [first, second]);
      expect(settled.receivableMinor, 0);
      expect(settled.cashBurdenMinor, 0);
      final snapshot = OrganizerSnapshot(
        financeAccounts: [
          LocalFinanceAccount(
            id: card,
            name: 'Private',
            currency: 'EUR',
            openingBalanceMinor: 0,
            createdAt: now,
            updatedAt: now,
          ),
        ],
      );
      final payments = PaymentSnapshot(
        projections: [
          PaymentProjection(
            event: settled,
            state: PaymentProjectionState.complete,
            privateAccountId: card,
          ),
        ],
        cashMovements: [
          cash(eventId, card, -3000, 9),
          cash(first.legId, card, 1000, 10),
          cash(second.legId, card, 2000, 11),
        ],
        fresh: true,
      );
      final forecast = forecastFinance(
        snapshot,
        currency: 'EUR',
        through: DateTime.utc(2026, 10, 12),
        account: snapshot.financeAccounts.single,
        payments: payments,
      );
      expect(forecast.points.map((p) => p.runningMinor), [
        BigInt.from(-3000),
        BigInt.from(-2000),
        BigInt.zero,
      ]);
      expect(
        forecast.points.every(
          (p) => p.entry == null && p.paymentMovement != null,
        ),
        isTrue,
      );
      expect(snapshot.financeEntries, isEmpty);
    },
  );
  test(
    'projection omits organization ledger and private card from household wire',
    () {
      final projection = PaymentProjection(
        event: event(revision: 2, legs: [first]),
        state: PaymentProjectionState.complete,
      );
      expect(jsonEncode(projection.toJson()), isNot(contains(ledger)));
      expect(projection.toJson().containsKey('privateAccountId'), isFalse);
      expect(
        PaymentProjection.fromJson(projection.toJson()).receivableMinor,
        2000,
      );
    },
  );
  test(
    'all spaces dedupe includes partition so different servers never collapse',
    () {
      final same = PaymentProjection(
        event: event(partition: 'server-a'),
        state: PaymentProjectionState.complete,
      );
      final other = PaymentProjection(
        event: event(partition: 'server-b'),
        state: PaymentProjectionState.complete,
      );
      expect(
        PaymentSnapshot(
          projections: [same, same, other],
        ).cashBurdenByCurrency['EUR'],
        BigInt.from(6000),
      );
    },
  );
  test(
    'no reimbursement explicitly suppresses receivable and refund history',
    () {
      expect(event(expected: false).cashBurdenMinor, 3000);
      expect(event(expected: false).receivableMinor, 0);
      expect(
        () => PaymentEvent.fromJson(
          event(expected: false, legs: [first]).toJson(),
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'immutable lost ACK cannot regress refund history or conflict at equal revision',
    () {
      expect(
        shouldReplacePaymentEvent(event(revision: 2, legs: [first]), event()),
        isFalse,
      );
      expect(
        () => shouldReplacePaymentEvent(event(), event(legs: [first])),
        throwsFormatException,
      );
      expect(
        shouldReplacePaymentEvent(event(), event(partition: 'server-a')),
        isTrue,
      );
    },
  );
  test(
    'portable cash movement validation rejects malformed amounts and calendar dates',
    () {
      final good = {
        'events': [],
        'projections': [],
        'intents': [],
        'cashMovements': [
          {
            'space_key': 'local:$source',
            'movement_id': eventId,
            'data': jsonEncode(cash(eventId, card, -3000, 9).toJson()),
          },
        ],
      };
      validateLinkedPaymentsBackup(good);
      final bad = Map<String, Object?>.from(
        cash(eventId, card, -3000, 9).toJson(),
      )..['paidAt'] = '2026-02-30T00:00:00Z';
      expect(
        () => validateLinkedPaymentsBackup({
          ...good,
          'cashMovements': [
            {
              'space_key': 'local:$source',
              'movement_id': eventId,
              'data': jsonEncode(bad),
            },
          ],
        }),
        throwsFormatException,
      );
    },
  );
}
