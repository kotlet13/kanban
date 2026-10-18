import '../../domain/linked_payment_models.dart';
import 'crypto_business_json.dart';
import 'crypto_record_address.dart';

/// Checks a transition only after its records/dependencies have authenticated.
/// Model parsing alone cannot establish a payment's causal financial effects.
class CryptoPaymentSemantics {
  static bool _same(Object? a, Object? b) =>
      CryptoBusinessJson.canonical(a) == CryptoBusinessJson.canonical(b);

  static PaymentEvent event({
    required Map<String, dynamic> raw,
    required Map<String, dynamic>? before,
    required String scopeId,
    required String eventId,
    required String authorAccountId,
    required Map<String, dynamic> paidSource,
    required int paidSourceRevision,
  }) {
    final next = PaymentEvent.fromJson(raw);
    if (next.sourceScopeId != scopeId ||
        next.eventId != eventId ||
        next.sourcePartition != null ||
        raw['paymentFormat'] != 2 ||
        raw['sourceState'] != 'active' ||
        paidSource['kind'] != 'expense' ||
        paidSource['status'] != 'posted' ||
        paidSource['deleted'] == true ||
        paidSource['accountScopeId'] != null ||
        paidSource['payerAccountId'] != next.payerAccountId ||
        paidSource['amountMinor'] != next.amountMinor ||
        paidSource['currency'] != next.currency ||
        paidSource['paidAt'] is! String ||
        DateTime.parse(paidSource['paidAt']) != next.paidAt ||
        next.sourceRevision != paidSourceRevision) {
      throw const FormatException('crypto_payment_source_facts');
    }
    for (final value in [
      next.eventId,
      next.sourceScopeId,
      next.sourceEntryId,
      next.payerAccountId,
      authorAccountId,
    ]) {
      if (!isCryptoCanonicalUuid(value)) {
        throw const FormatException('crypto_payment_identity');
      }
    }
    if (before == null) {
      if (next.revision != 1 ||
          next.reimbursements.isNotEmpty ||
          next.payerAccountId != authorAccountId) {
        throw const FormatException('crypto_payment_initial_transition');
      }
      return next;
    }
    final old = PaymentEvent.fromJson(before);
    final previousCore = old.toJson()
      ..remove('revision')
      ..remove('reimbursements');
    final nextCore = next.toJson()
      ..remove('revision')
      ..remove('reimbursements');
    if (!_same(previousCore, nextCore) ||
        before['sourceState'] != 'active' ||
        next.revision != old.revision + 1 ||
        !next.expectReimbursement ||
        next.reimbursements.length != old.reimbursements.length + 1) {
      throw const FormatException('crypto_payment_transition');
    }
    // Existing legs and extensions are immutable, including unknown fields.
    final previousLegs = before['reimbursements'] as List;
    final nextLegs = raw['reimbursements'] as List;
    for (var i = 0; i < previousLegs.length; i++) {
      if (!_same(previousLegs[i], nextLegs[i])) {
        throw const FormatException('crypto_payment_reimbursement_rewrite');
      }
    }
    for (final entry in before.entries) {
      if (!const {'revision', 'reimbursements'}.contains(entry.key) &&
          !_same(entry.value, raw[entry.key])) {
        throw const FormatException('crypto_payment_extension_rewrite');
      }
    }
    final leg = next.reimbursements.last;
    if (leg.approvedByAccountId != authorAccountId ||
        !isCryptoCanonicalUuid(leg.organizationAccountId) ||
        !isCryptoCanonicalUuid(leg.organizationAccountScopeId ?? scopeId)) {
      throw const FormatException('crypto_payment_reimbursement_author');
    }
    return next;
  }

  static void cash({
    required Map<String, dynamic> raw,
    required Map<String, dynamic>? before,
    required PaymentEvent event,
    required String scopeId,
    required String movementId,
    required String kind,
    required String? legId,
    required String accountId,
  }) {
    final cash = PaymentCashMovement.fromJson(raw);
    final link = raw['paymentLink'];
    if (raw['paymentFormat'] != 2 ||
        link is! Map ||
        link['version'] != 1 ||
        link['sourceScopeId'] != event.sourceScopeId ||
        link['eventId'] != event.eventId ||
        link['eventRevision'] != event.revision ||
        link['kind'] != kind ||
        link['legId'] != legId ||
        link['accountScopeId'] != scopeId ||
        cash.id != movementId ||
        cash.accountId != accountId ||
        cash.currency != event.currency) {
      throw const FormatException('crypto_payment_cash_binding');
    }
    final legs = event.reimbursements
        .where((leg) => leg.legId == legId)
        .toList();
    final amount = kind == 'advance'
        ? -event.amountMinor
        : legs.length == 1
        ? (kind == 'refundDebit'
              ? -legs.single.amountMinor
              : legs.single.amountMinor)
        : null;
    final date = kind == 'advance'
        ? event.paidAt
        : legs.length == 1
        ? legs.single.paidAt
        : null;
    if (!const {'advance', 'refundDebit', 'refundCredit'}.contains(kind) ||
        cash.amountMinor != amount ||
        cash.paidAt != date ||
        movementId != (kind == 'advance' ? event.eventId : legId)) {
      throw const FormatException('crypto_payment_cash_facts');
    }
    if (before != null) {
      // Catch-up can authenticate the same leg at a later source revision; it
      // cannot move money twice or change an established account or amount.
      final old = PaymentCashMovement.fromJson(before);
      if (!_same(old.toJson(), cash.toJson())) {
        throw const FormatException('crypto_payment_cash_rewrite');
      }
      for (final entry in before.entries) {
        if (entry.key != 'paymentLink' && !_same(entry.value, raw[entry.key])) {
          throw const FormatException('crypto_payment_extension_rewrite');
        }
      }
      final previousLink = before['paymentLink'] as Map;
      for (final entry in previousLink.entries) {
        if (entry.key != 'eventRevision' &&
            !_same(entry.value, link[entry.key])) {
          throw const FormatException('crypto_payment_cash_rewrite');
        }
      }
      if (link['eventRevision'] < previousLink['eventRevision']) {
        throw const FormatException('crypto_payment_cash_rollback');
      }
    }
  }
}
