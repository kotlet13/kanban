import 'dart:convert';

import 'package:cryptography/cryptography.dart' show Sha256;

import 'account_directory_v2.dart';
import 'crypto_inventory_json.dart';
import 'crypto_migration_business_parity_v3.dart';
import 'crypto_record_address.dart';

/// Scoped final activation, distinct from the private whole-component command.
/// Its signature and exact own-log inclusion are verified by the reader; this
/// codec checks only closed framing, commitment contexts and complete counts.
abstract final class CryptoMigrationActivationV3 {
  static const fields = {
    'version',
    'serverId',
    'migrationId',
    'componentId',
    'componentCommitment',
    'inventoryCommitment',
    'scopeId',
    'membershipHeadHash',
    'lifecycleHash',
    'managerAccountId',
    'managerDirectoryHeadHash',
    'contentCertificateHash',
    'financeCertificateHash',
    'controlCount',
    'controlRoot',
  };
  static const controlFields = {
    'version',
    'scopeId',
    'kind',
    'portionToken',
    'captureId',
    'sourceInventoryRoot',
    'verify3ProofHash',
    'selectionCount',
    'selectionRoot',
    'certificateHash',
    'eventCommandHash',
  };
  static void validate(Map<String, dynamic> value) {
    CryptoMigrationBusinessParityV3.exact(value, fields);
    if (value['version'] != 3 ||
        ![
          'serverId',
          'migrationId',
          'componentId',
          'scopeId',
          'managerAccountId',
        ].every((k) => isCryptoCanonicalUuid(value[k])) ||
        ![
          'componentCommitment',
          'inventoryCommitment',
          'membershipHeadHash',
          'lifecycleHash',
          'managerDirectoryHeadHash',
          'contentCertificateHash',
          'financeCertificateHash',
          'controlRoot',
        ].every((k) => CryptoMigrationBusinessParityV3.hash(value[k])) ||
        !CryptoMigrationBusinessParityV3.count(value['controlCount']) ||
        value['controlCount'] < 5 ||
        value['controlCount'] > 5000) {
      throw const FormatException('crypto_migration_activation_context');
    }
  }

  static Future<String> controlHash(Map<String, dynamic> value) async {
    CryptoMigrationBusinessParityV3.exact(value, controlFields);
    final kind = value['kind'];
    if (value['version'] != 3 ||
        !isCryptoCanonicalUuid(value['scopeId']) ||
        !isCryptoCanonicalUuid(value['captureId']) ||
        !CryptoMigrationBusinessParityV3.requiredSections.contains(kind) ||
        ![
          'portionToken',
          'sourceInventoryRoot',
          'verify3ProofHash',
          'selectionRoot',
        ].every((k) => CryptoMigrationBusinessParityV3.hash(value[k])) ||
        !CryptoMigrationBusinessParityV3.count(value['selectionCount']) ||
        (kind == 'notifications' || kind == 'invitations'
            ? !CryptoMigrationBusinessParityV3.hash(value['certificateHash']) ||
                  !CryptoMigrationBusinessParityV3.hash(
                    value['eventCommandHash'],
                  )
            : value['certificateHash'] != null ||
                  value['eventCommandHash'] != null)) {
      throw const FormatException('crypto_migration_activation_control');
    }
    return cryptoSha256([
      ...utf8.encode('JivieMigrationControl/v3\n'),
      ...CryptoInventoryJson.encode(value),
    ]);
  }

  static Future<String> controlRoot(
    Map<String, dynamic> header,
    Stream<String> hashes,
  ) async {
    validate(header);
    final context = Map<String, dynamic>.from(header)..remove('controlRoot');
    final sink = Sha256().newHashSink();
    sink.add([
      ...utf8.encode('JivieMigrationControls/v3\n'),
      ...CryptoInventoryJson.encode(context),
      10,
    ]);
    String? previous;
    var count = 0;
    await for (final hash in hashes) {
      if (!CryptoMigrationBusinessParityV3.hash(hash) ||
          previous != null && previous.compareTo(hash) >= 0 ||
          ++count > header['controlCount']) {
        throw const FormatException('crypto_migration_activation_coverage');
      }
      previous = hash;
      sink.add(utf8.encode('$hash\n'));
    }
    if (count != header['controlCount'])
      throw const FormatException('crypto_migration_activation_coverage');
    sink.close();
    return CryptoMigrationBusinessParityV3.hex((await sink.hash()).bytes);
  }

  static Future<String> token(Map<String, dynamic> header) async {
    validate(header);
    return cryptoSha256([
      ...utf8.encode('JivieMigrationActivationToken/v3\n'),
      ...CryptoInventoryJson.encode({
        'version': 3,
        for (final k in [
          'serverId',
          'migrationId',
          'scopeId',
          'componentCommitment',
        ])
          k: header[k],
      }),
    ]);
  }
}
