import 'crypto_record_address.dart';
import 'crypto_record_policy.dart';

/// Public target authority for an existing-record blob upload. It grants no
/// creation, checkbox-only write, finance access or permission on another ID.
abstract final class CryptoRecordBlobTarget {
  static String? typeForKind(String kind) {
    final type = switch (kind) {
      'table' => 'table',
      'attachment' => 'attachment',
      'ideaAsset' => 'idea',
      _ => kind.startsWith('payload:') ? kind.substring(8) : null,
    };
    return type != null &&
            CryptoRecordPolicy.businessTypes.contains(type) &&
            cryptoRecordDomain(type) == 'content'
        ? type
        : null;
  }

  static void validate(Map<String, dynamic> target) {
    const fields = {'type', 'wireId', 'currentRecordProofHash'};
    if (target.length != fields.length ||
        !target.keys.every(fields.contains) ||
        !CryptoRecordPolicy.businessTypes.contains(target['type']) ||
        cryptoRecordDomain(target['type']) != 'content' ||
        !isCryptoWireRecordId(target['wireId']) ||
        target['currentRecordProofHash'] is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(target['currentRecordProofHash'])) {
      throw const FormatException('crypto_record_policy_blob_target');
    }
  }

  static void requireRecordBinding(
    Map<String, dynamic> target,
    Map<String, dynamic> record,
  ) {
    validate(target);
    if (record['domain'] != 'content' ||
        target['wireId'] != record['id'] ||
        target['type'] != record['type']) {
      throw const FormatException('crypto_record_policy_blob_binding');
    }
  }
}
