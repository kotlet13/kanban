import 'dart:convert';

import 'account_directory_v2.dart';
import 'crypto_business_json.dart';
import 'crypto_json.dart';
import 'crypto_record_address.dart';

/// Explicit complete-selection variant of financeAccountChoice. Existing
/// per-account exports retain their original closed shapes and signatures.
class CryptoFinanceChoiceSelectionCodec {
  static const variant = 'accountChoiceSelection';
  static const fields = [
    'accountId',
    'accountScopeId',
    'archived',
    'currency',
    'name',
    'sourceRevision',
  ];
  static const selectionDomain = 'JivieFinanceAccountChoiceSelection/v2\n';
  static const rootDomain = 'JivieFinanceAccountChoiceSelectionRoot/v2\n';
  static void closed(Map value, Set<String> keys) {
    if (value.length != keys.length ||
        value.keys.any((k) => !keys.contains(k))) {
      throw const FormatException('crypto_account_choices_fields');
    }
  }

  static void hash(Object? value) {
    if (value is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(value)) {
      throw const FormatException('crypto_account_choices_hash');
    }
  }

  static void uuid(Object? value) {
    if (!isCryptoCanonicalUuid(value)) {
      throw const FormatException('crypto_account_choices_id');
    }
  }

  static void count(Object? value, {int max = 5000}) {
    if (value is! int || value < 0 || value > max) {
      throw const FormatException('crypto_account_choices_count');
    }
  }

  static Map<String, dynamic> context(Map value) {
    final result = <String, dynamic>{
      for (final key in const [
        'version',
        'serverId',
        'sourceScopeId',
        'sourceHeadHash',
        'sourceCheckpoint',
        'targetScopeId',
        'targetHeadHash',
        'selectionCount',
      ])
        key: value[key],
    };
    for (final key in ['serverId', 'sourceScopeId', 'targetScopeId']) {
      uuid(result[key]);
    }
    for (final key in ['sourceHeadHash', 'targetHeadHash']) {
      hash(result[key]);
    }
    if (result['version'] != 2 || result['sourceCheckpoint'] is! Map) {
      throw const FormatException('crypto_account_choices_context');
    }
    final checkpoint = result['sourceCheckpoint'] as Map;
    closed(checkpoint, {'proofHash', 'sequence', 'manifestHash'});
    hash(checkpoint['proofHash']);
    hash(checkpoint['manifestHash']);
    count(checkpoint['sequence'], max: 9007199254740991);
    count(result['selectionCount']);
    return result;
  }

  static List<Map<String, dynamic>> choices(Object? raw, String parent) {
    if (raw is! List || raw.length > 5000) {
      throw const FormatException('crypto_account_choices_count');
    }
    String? previous;
    return List.unmodifiable(
      raw.map((v) {
        if (v is! Map)
          throw const FormatException('crypto_account_choices_shape');
        final c = Map<String, dynamic>.from(v);
        closed(c, fields.toSet());
        uuid(c['accountId']);
        if (c['accountScopeId'] != parent ||
            c['archived'] is! bool ||
            c['name'] is! String ||
            (c['name'] as String).length > 200 ||
            c['currency'] is! String ||
            !RegExp(r'^[A-Z]{3}$').hasMatch(c['currency']) ||
            c['sourceRevision'] is! int ||
            c['sourceRevision'] < 1 ||
            c['sourceRevision'] > 9007199254740991 ||
            previous != null &&
                (c['accountId'] as String).compareTo(previous!) <= 0) {
          throw const FormatException('crypto_account_choices_order');
        }
        previous = c['accountId'];
        return Map<String, dynamic>.unmodifiable(c);
      }),
    );
  }

  static Future<String> selectionHash(
    Map contextValue,
    List<Map<String, dynamic>> choicesValue,
    String saltBase64,
  ) async {
    final salt = cryptoBase64(saltBase64, length: 32);
    try {
      return await cryptoSha256([
        ...utf8.encode(rootDomain),
        ...CryptoJson.encode(context(contextValue)),
        10,
        ...salt,
        ...CryptoBusinessJson.encode(choicesValue),
      ]);
    } finally {
      salt.fillRange(0, salt.length, 0);
    }
  }

  static Map<String, dynamic> body(Map proof) => Map<String, dynamic>.from(
    CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map,
  );
}
