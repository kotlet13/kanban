import 'crypto_inventory_json.dart';
import 'crypto_json.dart';

/// Recognizes the actual typed local journals only. A matching journal is not
/// success: its exact publication must still occur in verified head ancestry.
class CryptoMigrationReviewBinding {
  static Map review(Map data) => data['review'] is Map
      ? data['review'] as Map
      : data['history'] is Map
      ? data['history'] as Map
      : data;

  static String? reviewId(String state, String intentId, Map data) {
    final id = review(data)['reviewId'];
    if (id is String) return id;
    if (state == 'scopeRotationReview') return intentId;
    if (state == 'scopeSuccessorDraft' && intentId.endsWith(':successor')) {
      return intentId.substring(0, intentId.length - ':successor'.length);
    }
    return null;
  }

  static bool matches({
    required String state,
    required String scopeId,
    required String intentId,
    required Map draft,
    required Map publication,
  }) {
    final id = reviewId(state, intentId, draft), h = publication['body'];
    if (id == null ||
        publication['reviewId'] != id ||
        h is! Map ||
        h['scopeId'] != scopeId) {
      return false;
    }
    final source = review(draft)['sourceHeadHash'] ?? draft['previousHeadHash'];
    if (source is! String || h['previousHeadHash'] != source) return false;
    if (state == 'scopeSuccessorDraft') {
      for (final key in [
        'scopeId',
        'epoch',
        'previousHeadHash',
        'expectedAccessRevision',
        'accessBasis',
        'authorDirectoryHeadHash',
        'members',
        'membershipIntents',
        'financePolicyIntentProof',
        'accessIntentProof',
        'initialLifecycleHash',
        'previousLifecycleHash',
      ]) {
        if (!_same(draft[key], h[key])) return false;
      }
    }
    if (state == 'scopeAccessReview') {
      final proposal = draft['proposal'], proof = h['accessIntentProof'];
      if (proposal is! Map || proof is! Map) return false;
      final consent = CryptoJson.decode(cryptoBase64(proof['commandBase64']));
      if (consent is! Map ||
          consent['operation'] != 'crypto2.access.scopeConsent' ||
          consent['scopeId'] != scopeId ||
          consent['previousHeadHash'] != source ||
          consent['intentHash'] != proposal['intentHash'] ||
          consent['affectedHash'] != proposal['affectedHash'] ||
          consent['affectedCount'] != proposal['affectedCount']) {
        return false;
      }
    }
    if (state == 'financePolicyWorkflow') {
      final proof = h['financePolicyIntentProof'];
      if (proof is! Map || draft['payload'] is! Map) return false;
      final command = CryptoJson.decode(cryptoBase64(proof['commandBase64']));
      if (command is! Map ||
          command['operation'] != 'crypto2.scope.financePolicy.propose' ||
          !_same(command['payload'], draft['payload'])) {
        return false;
      }
    }
    return true;
  }

  static bool _same(Object? a, Object? b) =>
      CryptoInventoryJson.canonical(a) == CryptoInventoryJson.canonical(b);
}
