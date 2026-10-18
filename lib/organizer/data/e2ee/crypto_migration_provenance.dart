import 'dart:convert';

import 'package:cryptography/cryptography.dart' show Sha256;

import 'account_directory_v2.dart' show cryptoSha256;
import 'crypto_json.dart';
import 'crypto_record_address.dart';

/// One streaming commitment format shared with the migration server. This
/// authenticates captured-source parity; it cannot authenticate plaintext edits
/// made before E2EE existed. A root alone never grants contributor authority.
class CryptoMigrationProvenance {
  static const headerFields = {
    'version',
    'serverId',
    'migrationId',
    'componentHash',
    'scopeToken',
    'scopeId',
    'domain',
    'inventoryHash',
    'membershipHeadHash',
    'managerAccountId',
    'managerDirectoryHeadHash',
    'sourceRowCount',
    'materializedRecordProofCount',
  };
  static const leafFields = {
    'version',
    'migrationId',
    'inventoryHash',
    'sourceInventoryHash',
    'scopeId',
    'domain',
    'membershipHeadHash',
    'sourceTable',
    'sourceId',
    'sourceRowHash',
    'legacyRevision',
    'sourceKind',
    'canonicalId',
    'wireId',
    'type',
    'recordProofHash',
    'materializationRole',
    'contributorAccountId',
    'contributorDeviceId',
    'contributorDeviceSnapshotHash',
    'archiveManifestHash',
    'coldParityHash',
  };

  static bool _digest(Object? value) =>
      value is String && RegExp(r'^[a-f0-9]{64}$').hasMatch(value);
  static void _exact(Map<String, dynamic> value, Set<String> fields) {
    if (value.length != fields.length ||
        value.keys.any((k) => !fields.contains(k))) {
      throw const FormatException('crypto_migration_provenance_shape');
    }
  }

  static Future<String> scopeToken({
    required String serverId,
    required String migrationId,
    required String scopeId,
    required String domain,
  }) {
    if (![serverId, migrationId, scopeId].every(isCryptoCanonicalUuid) ||
        !['content', 'finance'].contains(domain)) {
      throw const FormatException('crypto_migration_provenance_context');
    }
    return cryptoSha256([
      ...utf8.encode('JivieMigrationScope/v2\n'),
      ...CryptoJson.encode({
        'version': 2,
        'serverId': serverId,
        'migrationId': migrationId,
        'scopeId': scopeId,
        'domain': domain,
      }),
    ]);
  }

  static Future<void> validateHeader(Map<String, dynamic> header) async {
    _exact(header, headerFields);
    if (header['version'] != 2 ||
        ![
          'serverId',
          'migrationId',
          'scopeId',
          'managerAccountId',
        ].every((k) => isCryptoCanonicalUuid(header[k])) ||
        ![
          'componentHash',
          'scopeToken',
          'inventoryHash',
          'membershipHeadHash',
          'managerDirectoryHeadHash',
        ].every((k) => _digest(header[k])) ||
        !['content', 'finance'].contains(header['domain']) ||
        header['sourceRowCount'] is! int ||
        header['sourceRowCount'] < 0 ||
        header['materializedRecordProofCount'] is! int ||
        header['materializedRecordProofCount'] < header['sourceRowCount'] ||
        header['materializedRecordProofCount'] > 10000000 ||
        header['scopeToken'] !=
            await scopeToken(
              serverId: header['serverId'],
              migrationId: header['migrationId'],
              scopeId: header['scopeId'],
              domain: header['domain'],
            )) {
      throw const FormatException('crypto_migration_provenance_context');
    }
  }

  static Future<String> portionToken({
    required String serverId,
    required String migrationId,
    required String accountId,
  }) {
    if (![serverId, migrationId, accountId].every(isCryptoCanonicalUuid)) {
      throw const FormatException('crypto_migration_provenance_context');
    }
    return cryptoSha256([
      ...utf8.encode('JivieMigrationPortion/v2\n'),
      ...CryptoJson.encode({
        'version': 2,
        'serverId': serverId,
        'migrationId': migrationId,
        'accountId': accountId,
      }),
    ]);
  }

  static Future<String> inventoryHash({
    required String serverId,
    required String migrationId,
    required String componentHash,
    required Stream<Map<String, dynamic>> portions,
  }) async {
    if (![serverId, migrationId].every(isCryptoCanonicalUuid) ||
        !_digest(componentHash)) {
      throw const FormatException('crypto_migration_provenance_context');
    }
    final sink = Sha256().newHashSink();
    sink.add([
      ...utf8.encode('JivieMigrationInventory/v2\n'),
      ...CryptoJson.encode({
        'version': 2,
        'serverId': serverId,
        'migrationId': migrationId,
        'componentHash': componentHash,
      }),
      10,
    ]);
    String? previous;
    var count = 0;
    await for (final portion in portions) {
      _exact(portion, {'portionToken', 'inventoryHash'});
      if (!_digest(portion['portionToken']) ||
          !_digest(portion['inventoryHash']) ||
          previous != null &&
              previous.compareTo(portion['portionToken']) >= 0 ||
          ++count > 10000) {
        throw const FormatException('crypto_migration_inventory_portions');
      }
      sink.add([...CryptoJson.encode(portion), 10]);
      previous = portion['portionToken'];
    }
    if (count == 0)
      throw const FormatException('crypto_migration_inventory_portions');
    sink.close();
    return (await sink.hash()).bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  static Future<String> leafHash(
    Map<String, dynamic> header,
    Map<String, dynamic> leaf,
  ) async {
    await validateHeader(header);
    _exact(leaf, leafFields);
    if (leaf['version'] != 2 ||
        ![
          'migrationId',
          'inventoryHash',
          'scopeId',
          'domain',
          'membershipHeadHash',
        ].every((k) => leaf[k] == header[k]) ||
        ![
          'sourceId',
          'canonicalId',
          'contributorAccountId',
          'contributorDeviceId',
        ].every((k) => isCryptoCanonicalUuid(leaf[k])) ||
        ![
          'sourceRowHash',
          'sourceInventoryHash',
          'recordProofHash',
          'contributorDeviceSnapshotHash',
          'archiveManifestHash',
          'coldParityHash',
        ].every((k) => _digest(leaf[k])) ||
        leaf['legacyRevision'] is! int ||
        leaf['legacyRevision'] < 0 ||
        leaf['sourceTable'] is! String ||
        ![
          'primary',
          'taskDerivationIntent',
          'taskDerivationResolution',
        ].contains(leaf['materializationRole'])) {
      throw const FormatException('crypto_migration_provenance_leaf');
    }
    final address = CryptoRecordAddress(
      serverId: header['serverId'],
      scopeId: leaf['scopeId'],
      domain: leaf['domain'],
      type: leaf['type'],
      sourceKind: leaf['sourceKind'],
      canonicalId: leaf['canonicalId'],
    );
    if (address.wireId != leaf['wireId']) {
      throw const FormatException('crypto_migration_provenance_address');
    }
    return cryptoSha256([
      ...utf8.encode('JivieMigrationLeaf/v2\n'),
      ...CryptoJson.encode(leaf),
    ]);
  }

  /// The retained complete sorted digest stream is required for verification.
  /// Other records' IDs are never exposed through this list. Each digest occurs
  /// exactly once; pagination may not omit, duplicate or reorder a leaf.
  static Future<String> root(
    Map<String, dynamic> header,
    Stream<String> leaves,
  ) async {
    await validateHeader(header);
    final sink = Sha256().newHashSink();
    sink.add([
      ...utf8.encode('JivieMigrationDomain/v2\n'),
      ...CryptoJson.encode(header),
      10,
    ]);
    String? previous;
    var count = 0;
    await for (final hash in leaves) {
      if (!_digest(hash) ||
          previous != null && previous.compareTo(hash) >= 0 ||
          ++count > (header['materializedRecordProofCount'] as int)) {
        throw const FormatException('crypto_migration_provenance_stream');
      }
      sink.add([...utf8.encode(hash), 10]);
      previous = hash;
    }
    if (count != header['materializedRecordProofCount']) {
      throw const FormatException('crypto_migration_provenance_count');
    }
    sink.close();
    return (await sink.hash()).bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }
}
