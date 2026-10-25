import 'crypto_record_address.dart';

/// Resolves only already verified provenance. A migration/relocation publisher
/// must never become the creator merely by signing its materialization.
abstract final class CryptoRecordAuthorship {
  static String? account(Object? value) {
    // Account deletion deliberately anonymizes historical transport authors.
    // Preserve that concrete absence instead of rejecting readable history.
    if (value == null || value == '') return null;
    if (!isCryptoCanonicalUuid(value)) {
      throw const FormatException('crypto_record_author');
    }
    return value as String;
  }

  static String? nativeCreation(Map<String, dynamic> verifiedRecord) {
    final metadata = verifiedRecord['metadata'];
    if (verifiedRecord['expectedRevision'] != 0 ||
        metadata is! Map ||
        const {
          'migrationOrigin',
          'projectRelocation',
          'inlineDeletion',
        }.any(metadata.containsKey)) {
      return null;
    }
    return account(verifiedRecord['accountId']);
  }

  static String? resolve({
    required Map<String, dynamic> verifiedRecord,
    Map<String, dynamic>? previousCanonical,
    String? verifiedOriginCreator,
  }) {
    final previous = account(previousCanonical?['createdByAccountId']);
    final origin = account(verifiedOriginCreator);
    if (previous != null && origin != null && previous != origin) {
      throw const FormatException('crypto_record_author_substitution');
    }
    return previous ?? origin ?? nativeCreation(verifiedRecord);
  }
}
