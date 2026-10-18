import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/e2ee/crypto_payment_semantics.dart';

const scope = '11111111-1111-4111-8111-111111111111';
const eventId = '22222222-2222-4222-8222-222222222222';
const entryId = '33333333-3333-4333-8333-333333333333';
const payer = '44444444-4444-4444-8444-444444444444';
const author = '55555555-5555-4555-8555-555555555555';
const account = '66666666-6666-4666-8666-666666666666';
const legId = '77777777-7777-4777-8777-777777777777';
const date = '2026-10-17T10:00:00.000Z';
Map<String, dynamic> initial() => {
  'paymentFormat': 2,
  'sourceState': 'active',
  'eventId': eventId,
  'sourceScopeId': scope,
  'sourceEntryId': entryId,
  'sourceRevision': 51,
  'payerAccountId': payer,
  'amountMinor': 100,
  'currency': 'EUR',
  'paidAt': date,
  'expectReimbursement': true,
  'revision': 1,
  'reimbursements': <Map<String, dynamic>>[],
  'future': {'fraction': 1.25},
};
Map<String, dynamic> source() => {
  'kind': 'expense',
  'status': 'posted',
  'accountScopeId': null,
  'payerAccountId': payer,
  'amountMinor': 100,
  'currency': 'EUR',
  'paidAt': date,
};
Map<String, dynamic> refunded() => {
  ...initial(),
  'revision': 2,
  'reimbursements': [
    {
      'legId': legId,
      'amountMinor': 40,
      'paidAt': date,
      'approvedByAccountId': author,
      'organizationAccountId': account,
      'organizationAccountScopeId': scope,
      'futureLeg': {'fraction': 0.5},
    },
  ],
};
void validate(
  Map<String, dynamic> raw, {
  Map<String, dynamic>? before,
  String actor = payer,
  Map<String, dynamic>? paidSource,
}) {
  CryptoPaymentSemantics.event(
    raw: raw,
    before: before,
    scopeId: scope,
    eventId: eventId,
    authorAccountId: actor,
    paidSource: paidSource ?? source(),
    paidSourceRevision: 51,
  );
}

void main() {
  test('paid source facts and exact non-payer reimbursement transition', () {
    validate(initial());
    validate(refunded(), before: initial(), actor: author);
    for (final change in [
      {'amountMinor': 99},
      {'currency': 'USD'},
      {'paidAt': '2026-10-18T10:00:00.000Z'},
      {'payerAccountId': author},
      {'status': 'canceled'},
    ]) {
      expect(
        () => validate(initial(), paidSource: {...source(), ...change}),
        throwsFormatException,
      );
    }
    expect(
      () => validate(refunded(), before: initial()),
      throwsFormatException,
    );
    expect(
      () => validate(
        {...refunded(), 'sourceState': 'deleted'},
        before: initial(),
        actor: author,
      ),
      throwsFormatException,
    );
    expect(
      () => validate(
        {
          ...refunded(),
          'future': {'fraction': 2.5},
        },
        before: initial(),
        actor: author,
      ),
      throwsFormatException,
    );
    expect(
      () => validate(
        {...refunded(), 'revision': 3},
        before: initial(),
        actor: author,
      ),
      throwsFormatException,
    );
  });
  test(
    'existing reimbursement bytes and unknown fields cannot be rewritten',
    () {
      final before = refunded();
      final next = {
        ...before,
        'revision': 3,
        'reimbursements': [
          ...(before['reimbursements'] as List),
          {
            'legId': '88888888-8888-4888-8888-888888888888',
            'amountMinor': 10,
            'paidAt': date,
            'approvedByAccountId': author,
            'organizationAccountId': account,
            'organizationAccountScopeId': scope,
          },
        ],
      };
      validate(next, before: before, actor: author);
      final altered = List<Map<String, dynamic>>.from(
        next['reimbursements'] as List,
      );
      altered[0] = {
        ...altered[0],
        'futureLeg': {'fraction': 0.75},
      };
      expect(
        () => validate(
          {...next, 'reimbursements': altered},
          before: before,
          actor: author,
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'refund cash authenticates exact event leg without double-moving money',
    () {
      final event = CryptoPaymentSemantics.event(
        raw: refunded(),
        before: initial(),
        scopeId: scope,
        eventId: eventId,
        authorAccountId: author,
        paidSource: source(),
        paidSourceRevision: 51,
      );
      final cash = <String, dynamic>{
        'id': legId,
        'accountId': account,
        'amountMinor': -40,
        'currency': 'EUR',
        'paidAt': date,
        'paymentFormat': 2,
        'future': 1.25,
        'paymentLink': {
          'version': 1,
          'sourceScopeId': scope,
          'eventId': eventId,
          'eventRevision': 2,
          'kind': 'refundDebit',
          'legId': legId,
          'accountScopeId': scope,
        },
      };
      void check(Map<String, dynamic> raw, {Map<String, dynamic>? before}) =>
          CryptoPaymentSemantics.cash(
            raw: raw,
            before: before,
            event: event,
            scopeId: scope,
            movementId: legId,
            kind: 'refundDebit',
            legId: legId,
            accountId: account,
          );
      check(cash);
      check(cash, before: cash);
      for (final changed in [
        {'amountMinor': 40},
        {'currency': 'USD'},
        {'accountId': payer},
        {'id': eventId},
        {'paidAt': '2026-10-18T10:00:00.000Z'},
      ]) {
        expect(() => check({...cash, ...changed}), throwsFormatException);
      }
      expect(
        () => check({...cash, 'future': 2.5}, before: cash),
        throwsFormatException,
      );
    },
  );
}
