import 'dart:convert';

import 'package:cryptography/cryptography.dart' show Sha256;

import 'account_directory_v2.dart' show cryptoSha256;
import 'crypto_inventory_json.dart';
import 'crypto_record_address.dart';

/// Capture3 public commitments contain randomized source commitments and
/// ciphertext digests exclusively. Preview2 raw-hash certificates are separate
/// immutable history and cannot be converted merely by changing a version.
abstract final class CryptoMigrationCommitmentsV3 {
  static bool _hash(Object? v) =>
      v is String && RegExp(r'^[a-f0-9]{64}$').hasMatch(v);
  static void _exact(Map value, Set<String> keys) {
    if (value.length != keys.length ||
        value.keys.any((key) => !keys.contains(key))) {
      throw const FormatException('crypto_capture_commitment_shape');
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
      throw const FormatException('crypto_capture_commitment_context');
    }
    return cryptoSha256([
      ...utf8.encode('JivieMigrationScope/v3\n'),
      ...CryptoInventoryJson.encode({
        'version': 3,
        'serverId': serverId,
        'migrationId': migrationId,
        'scopeId': scopeId,
        'domain': domain,
      }),
    ]);
  }

  static Future<String> componentCommitment({
    required String serverId,
    required String migrationId,
    required String componentId,
    required String inventoryCommitment,
  }) {
    if (![serverId, migrationId, componentId].every(isCryptoCanonicalUuid) ||
        !_hash(inventoryCommitment)) {
      throw const FormatException('crypto_capture_commitment_context');
    }
    return cryptoSha256([
      ...utf8.encode('JivieMigrationComponent/v3\n'),
      ...CryptoInventoryJson.encode({
        'version': 3,
        'serverId': serverId,
        'migrationId': migrationId,
        'componentId': componentId,
        'inventoryCommitment': inventoryCommitment,
      }),
    ]);
  }

  /// Exact opaque portion-token to capture/root mapping. The token is already
  /// bound to server/migration/account; it grants no content or finance access.
  static Future<String> inventoryCommitment({
    required String serverId,
    required String migrationId,
    required String componentId,
    required int portionCount,
    required Stream<Map<String, dynamic>> portions,
  }) async {
    if (![serverId, migrationId, componentId].every(isCryptoCanonicalUuid) ||
        portionCount < 1 ||
        portionCount > 1000) {
      throw const FormatException('crypto_capture_commitment_context');
    }
    final sink = Sha256().newHashSink();
    sink.add(utf8.encode('JivieMigrationInventory/v3\n'));
    sink.add(
      CryptoInventoryJson.encode({
        'version': 3,
        'serverId': serverId,
        'migrationId': migrationId,
        'componentId': componentId,
        'portionCount': portionCount,
      }),
    );
    sink.add([10]);
    String? previous;
    var count = 0;
    await for (final p in portions) {
      _exact(p, {'portionToken', 'captureId', 'sourceInventoryRoot'});
      if (!_hash(p['portionToken']) ||
          !isCryptoCanonicalUuid(p['captureId']) ||
          !_hash(p['sourceInventoryRoot']) ||
          previous != null && previous.compareTo(p['portionToken']) >= 0 ||
          ++count > portionCount) {
        throw const FormatException('crypto_capture_commitment_portions');
      }
      previous = p['portionToken'];
      sink.add(CryptoInventoryJson.encode(p));
      sink.add([10]);
    }
    if (count != portionCount) {
      throw const FormatException('crypto_capture_commitment_incomplete');
    }
    sink.close();
    return _hex((await sink.hash()).bytes);
  }

  static const headerFields = {
    'version',
    'serverId',
    'migrationId',
    'componentId',
    'componentCommitment',
    'inventoryCommitment',
    'scopeId',
    'scopeToken',
    'domain',
    'membershipHeadHash',
    'managerAccountId',
    'managerDirectoryHeadHash',
    'sourceRowCount',
    'materializedRecordProofCount',
  };
  static Future<void> validateHeader(Map<String, dynamic> header) async {
    _exact(header, headerFields);
    if (header['version'] != 3 ||
        ![
          'serverId',
          'migrationId',
          'componentId',
          'scopeId',
          'managerAccountId',
        ].every((k) => isCryptoCanonicalUuid(header[k])) ||
        ![
          'componentCommitment',
          'inventoryCommitment',
          'scopeToken',
          'membershipHeadHash',
          'managerDirectoryHeadHash',
        ].every((k) => _hash(header[k])) ||
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
            ) ||
        header['componentCommitment'] !=
            await componentCommitment(
              serverId: header['serverId'],
              migrationId: header['migrationId'],
              componentId: header['componentId'],
              inventoryCommitment: header['inventoryCommitment'],
            )) {
      throw const FormatException('crypto_capture_commitment_context');
    }
  }

  static const leafFields = {
    'version',
    'migrationId',
    'scopeId',
    'domain',
    'membershipHeadHash',
    'captureId',
    'sourceInventoryRoot',
    'bindingId',
    'sourceCommitment',
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
    'witnessCipherManifestHash',
  };

  /// Callers reconstruct each leaf from the exact signed source binding and
  /// verified witness, including every companion. Server-generated candidates
  /// alone cannot establish this provenance or claim plaintext verification.
  static Future<String> leafHash(
    Map<String, dynamic> header,
    Map<String, dynamic> leaf,
  ) async {
    await validateHeader(header);
    _exact(leaf, leafFields);
    if (leaf['version'] != 3 ||
        ![
          'migrationId',
          'scopeId',
          'domain',
          'membershipHeadHash',
        ].every((k) => leaf[k] == header[k]) ||
        ![
          'captureId',
          'bindingId',
          'canonicalId',
          'contributorAccountId',
          'contributorDeviceId',
        ].every((k) => isCryptoCanonicalUuid(leaf[k])) ||
        !isCryptoWireRecordId(leaf['wireId']) ||
        ![
          'sourceInventoryRoot',
          'sourceCommitment',
          'recordProofHash',
          'contributorDeviceSnapshotHash',
          'archiveManifestHash',
          'coldParityHash',
        ].every((k) => _hash(leaf[k])) ||
        leaf['type'] is! String ||
        leaf['sourceKind'] is! String ||
        ![
          'primary',
          'taskDerivationIntent',
          'taskDerivationResolution',
          'financeAccountChoice',
        ].contains(leaf['materializationRole']) ||
        leaf['legacyRevision'] is! int ||
        leaf['legacyRevision'] < 0) {
      throw const FormatException('crypto_capture_commitment_leaf');
    }
    final address = CryptoRecordAddress(
      serverId: header['serverId'],
      scopeId: leaf['scopeId'],
      domain: leaf['domain'],
      sourceKind: leaf['sourceKind'],
      canonicalId: leaf['canonicalId'],
      type: leaf['type'],
    );
    if (address.wireId != leaf['wireId'] ||
        leaf['legacyRevision'] == 0 && leaf['type'] != 'scopeMetadata' ||
        (leaf['materializationRole'] == 'taskDerivationIntent' &&
            leaf['type'] != 'taskDerivationIntent') ||
        (leaf['materializationRole'] == 'financeAccountChoice' &&
            leaf['type'] != 'financeAccountChoice') ||
        (leaf['materializationRole'] == 'taskDerivationResolution' &&
            leaf['type'] != 'taskDerivationResolution') ||
        (leaf['type'] == 'scopeMetadata'
            ? leaf['witnessCipherManifestHash'] != null ||
                  leaf['contributorAccountId'] != header['managerAccountId']
            : !_hash(leaf['witnessCipherManifestHash']))) {
      throw const FormatException('crypto_capture_commitment_leaf');
    }
    return cryptoSha256([
      ...utf8.encode('JivieMigrationLeaf/v3\n'),
      ...CryptoInventoryJson.encode(leaf),
    ]);
  }

  /// Sorted complete opaque digest stream, including the explicitly defined
  /// empty root. Only its context/count-authenticated result may enter a cert.
  static Future<String> domainRoot(
    Map<String, dynamic> header,
    Stream<String> hashes,
  ) async {
    await validateHeader(header);
    final sink = Sha256().newHashSink();
    sink.add(utf8.encode('JivieMigrationDomain/v3\n'));
    sink.add(CryptoInventoryJson.encode(header));
    sink.add([10]);
    String? previous;
    var count = 0;
    await for (final hash in hashes) {
      if (!_hash(hash) ||
          previous != null && previous.compareTo(hash) >= 0 ||
          ++count > header['materializedRecordProofCount']) {
        throw const FormatException('crypto_capture_commitment_order');
      }
      previous = hash;
      sink.add(utf8.encode('$hash\n'));
    }
    if (count != header['materializedRecordProofCount']) {
      throw const FormatException('crypto_capture_commitment_incomplete');
    }
    sink.close();
    return _hex((await sink.hash()).bytes);
  }

  static const contributionFields = {
    'version',
    'serverId',
    'migrationId',
    'scopeToken',
    'domain',
    'headerHash',
    'portionToken',
    'captureId',
    'sourceInventoryRoot',
    'coldParityProofHash',
    'leafCount',
    'sourceRowCount',
    'authorDirectoryHeadHash',
  };

  static Future<String> headerHash(Map<String, dynamic> header) async {
    await validateHeader(header);
    return cryptoSha256([
      ...utf8.encode('JivieMigrationDomainHeader/v3\n'),
      ...CryptoInventoryJson.encode(header),
    ]);
  }

  static void validateContribution(Map<String, dynamic> header) {
    _exact(header, contributionFields);
    if (header['version'] != 3 ||
        ![
          'serverId',
          'migrationId',
          'captureId',
        ].every((k) => isCryptoCanonicalUuid(header[k])) ||
        ![
          'scopeToken',
          'headerHash',
          'portionToken',
          'sourceInventoryRoot',
          'coldParityProofHash',
          'authorDirectoryHeadHash',
        ].every((k) => _hash(header[k])) ||
        !['content', 'finance'].contains(header['domain']) ||
        header['leafCount'] is! int ||
        header['sourceRowCount'] is! int ||
        header['sourceRowCount'] < 0 ||
        header['leafCount'] < header['sourceRowCount'] ||
        header['leafCount'] > 10000000) {
      throw const FormatException('crypto_capture_commitment_contribution');
    }
  }

  /// Opaque digests from ONE independently verified selected portion. Selection,
  /// signature, complete source coverage and exact own-log inclusion must also
  /// be verified by the producer/reader; a root alone grants no authority.
  static Future<String> contributionRoot(
    Map<String, dynamic> header,
    Stream<String> hashes,
  ) async {
    validateContribution(header);
    final sink = Sha256().newHashSink();
    sink.add(utf8.encode('JivieMigrationContribution/v3\n'));
    sink.add(CryptoInventoryJson.encode(header));
    sink.add([10]);
    String? previous;
    var count = 0;
    await for (final hash in hashes) {
      if (!_hash(hash) ||
          previous != null && previous.compareTo(hash) >= 0 ||
          ++count > header['leafCount']) {
        throw const FormatException('crypto_capture_commitment_contribution');
      }
      previous = hash;
      sink.add(utf8.encode('$hash\n'));
    }
    if (count != header['leafCount']) {
      throw const FormatException('crypto_capture_commitment_incomplete');
    }
    sink.close();
    return _hex((await sink.hash()).bytes);
  }

  static String _hex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}
