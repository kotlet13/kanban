import 'dart:convert';

import 'account_directory_v2.dart' show cryptoSha256;
import 'crypto_inventory_json.dart';
import 'crypto_migration_business_parity_v3.dart';

/// Public receipt provenance contains random routing tuples, randomized source
/// commitments and cipher/signed-proof hashes only. Exact legacy bytes stay in
/// the account-private authenticated archives.
abstract final class CryptoMigrationReceiptCodec {
  static void common(Map<String, dynamic> value) {
    CryptoMigrationBusinessParityV3.exact(value, {
      'version',
      'serverId',
      'migrationId',
      'captureId',
      'accountId',
      'sourceInventoryRoot',
    });
    if (value['version'] != 3) {
      throw const FormatException('crypto_receipts_context');
    }
    for (final key in ['serverId', 'migrationId', 'captureId', 'accountId']) {
      final v = value[key];
      if (v is! String ||
          !RegExp(
            r'^[a-f0-9]{8}-[a-f0-9]{4}-[1-5][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$',
          ).hasMatch(v)) {
        throw const FormatException('crypto_receipts_context');
      }
    }
    _hash(value['sourceInventoryRoot']);
  }

  static void _hash(Object? value) {
    if (!CryptoMigrationBusinessParityV3.hash(value)) {
      throw const FormatException('crypto_receipts_hash');
    }
  }

  static void _count(Object? value) {
    if (!CryptoMigrationBusinessParityV3.count(value)) {
      throw const FormatException('crypto_receipts_count');
    }
  }

  static void certificate(Map<String, dynamic> value) {
    CryptoMigrationBusinessParityV3.exact(value, {
      'certificateHash',
      'manifestRoot',
      'receiptCount',
    });
    _hash(value['certificateHash']);
    _hash(value['manifestRoot']);
    _count(value['receiptCount']);
  }

  static void local(Map<String, dynamic> value) {
    CryptoMigrationBusinessParityV3.exact(value, {
      'artifactId',
      'cipherManifestHash',
      'intentCount',
      'ownEventCommandHash',
    });
    final id = value['artifactId'];
    if (id is! String ||
        !RegExp(
          r'^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$',
        ).hasMatch(id)) {
      throw const FormatException('crypto_receipts_context');
    }
    _hash(value['cipherManifestHash']);
    _hash(value['ownEventCommandHash']);
    _count(value['intentCount']);
  }

  static Future<String> artifact({
    required String bindingId,
    required String sourceCommitment,
    required String domain,
    required Map<String, dynamic> cert,
  }) {
    certificate(cert);
    _hash(sourceCommitment);
    if (!const {'content', 'finance'}.contains(domain)) {
      throw const FormatException('crypto_receipts_context');
    }
    final id = bindingId;
    if (!RegExp(
      r'^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$',
    ).hasMatch(id)) {
      throw const FormatException('crypto_receipts_context');
    }
    return cryptoSha256([
      ...utf8.encode('JivieMigrationReceiptArtifact/v3\n'),
      ...CryptoInventoryJson.encode({
        'bindingId': id,
        'sourceCommitment': sourceCommitment,
        'domain': domain,
        'certificateHash': cert['certificateHash'],
        'manifestRoot': cert['manifestRoot'],
      }),
    ]);
  }

  static Future<Map<String, dynamic>> section({
    required Map<String, dynamic> context,
    required Map<String, dynamic> content,
    required Map<String, dynamic> finance,
    required Map<String, dynamic> localIntents,
  }) async {
    common(context);
    certificate(content);
    certificate(finance);
    local(localIntents);
    final count =
        (content['receiptCount'] as int) +
        (finance['receiptCount'] as int) +
        (localIntents['intentCount'] as int);
    _count(count);
    return {
      'kind': 'receipts',
      'count': count,
      'root': await cryptoSha256([
        ...utf8.encode('JivieMigrationReceipts/v3\n'),
        ...CryptoInventoryJson.encode(context),
        10,
        ...CryptoInventoryJson.encode({
          'content': content,
          'finance': finance,
          'localIntents': localIntents,
        }),
        10,
      ]),
    };
  }
}
