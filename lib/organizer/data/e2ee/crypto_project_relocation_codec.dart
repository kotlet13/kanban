import 'dart:convert';

import 'account_directory_v2.dart';
import 'crypto_json.dart';
import 'crypto_record_address.dart';

abstract final class CryptoProjectRelocationCodec {
  static const publicationDomain = 'JivieProjectRelocationPublication/v2\n';
  static const maximumRecords = 10000;
  static final _digest = RegExp(r'^[a-f0-9]{64}$');
  static void exact(Map value, Set<String> fields) {
    if (value.length != fields.length ||
        value.keys.any((key) => !fields.contains(key))) {
      throw const FormatException('crypto_relocation_fields');
    }
  }

  static void hashValue(Object? value) {
    if (value is! String || !_digest.hasMatch(value)) {
      throw const FormatException('crypto_relocation_digest');
    }
  }

  static void safe(Object? value, [int min = 0, int max = 9007199254740991]) {
    if (value is! int || value < min || value > max) {
      throw const FormatException('crypto_relocation_count');
    }
  }

  static Map<String, dynamic> body(Map proof) {
    exact(proof, {'commandBase64', 'signatureBase64'});
    cryptoBase64(proof['signatureBase64'], length: 64);
    final raw = cryptoBase64(proof['commandBase64']);
    if (raw.length > 16 * 1024) {
      throw const FormatException('crypto_relocation_proof_limit');
    }
    final decoded = CryptoJson.decode(raw);
    if (decoded is! Map ||
        base64Encode(CryptoJson.encode(decoded)) != proof['commandBase64']) {
      throw const FormatException('crypto_relocation_canonical');
    }
    return Map<String, dynamic>.from(decoded);
  }

  static void publication(Map value) {
    exact(value, {
      'version',
      'serverId',
      'scopeId',
      'side',
      'actionId',
      'planHash',
      'requestId',
      'accountId',
      'deviceId',
      'authorDirectoryHeadHash',
      'membershipHeadHash',
      'proposalProofHash',
      'activationProofHash',
      'accessRevision',
      'lifecycleHash',
      'counterpartToken',
      'recordRoot',
      'recordCount',
      'batchRoot',
      'batchCount',
      'auditRoot',
      'auditCount',
      'notificationRoot',
      'notificationCount',
    });
    if (value['version'] != 2 ||
        !const {'source', 'target'}.contains(value['side'])) {
      throw const FormatException('crypto_relocation_publication');
    }
    for (final field in const [
      'serverId',
      'scopeId',
      'actionId',
      'requestId',
      'accountId',
      'deviceId',
    ]) {
      if (!isCryptoCanonicalUuid(value[field])) {
        throw const FormatException('crypto_relocation_identity');
      }
    }
    for (final field in const [
      'planHash',
      'authorDirectoryHeadHash',
      'membershipHeadHash',
      'proposalProofHash',
      'activationProofHash',
      'lifecycleHash',
      'counterpartToken',
      'recordRoot',
      'batchRoot',
      'auditRoot',
      'notificationRoot',
    ]) {
      hashValue(value[field]);
    }
    safe(value['accessRevision']);
    safe(value['recordCount'], 1, maximumRecords + 1);
    safe(value['batchCount'], 1, value['recordCount'] as int);
    safe(value['auditCount'], 0, maximumRecords * 100);
    safe(value['notificationCount'], 0, maximumRecords * 100);
    if (value['side'] == 'source' && value['auditCount'] != 0) {
      throw const FormatException('crypto_relocation_count');
    }
  }

  static Future<String> proofHash(Map proof) =>
      cryptoSha256(CryptoJson.encode(proof));
  static Future<String> publicationRoot(String source, String target) {
    hashValue(source);
    hashValue(target);
    return cryptoSha256([
      ...utf8.encode('JivieProjectRelocationPair/v2\n'),
      ...CryptoJson.encode({
        'version': 2,
        'sourcePublicationHash': source,
        'targetPublicationHash': target,
      }),
    ]);
  }

  static Future<String> digestRoot(String kind, List<String> digests) {
    final history = const {'audit', 'notifications'}.contains(kind);
    if (!const {
          'records',
          'batches',
          'audit',
          'notifications',
        }.contains(kind) ||
        digests.isEmpty && !history ||
        digests.length >
            maximumRecords * (history ? 100 : 1) + (history ? 0 : 1)) {
      throw const FormatException('crypto_relocation_count');
    }
    String? previous;
    for (final digest in digests) {
      hashValue(digest);
      if (previous != null && previous.compareTo(digest) >= 0) {
        throw const FormatException('crypto_relocation_order');
      }
      previous = digest;
    }
    return cryptoSha256(
      utf8.encode(
        'JivieProjectRelocation/$kind/v2\n${digests.map((v) => '$v\n').join()}',
      ),
    );
  }

  static Future<String> recordLeaf(Map value) {
    exact(value, {
      'id',
      'type',
      'domain',
      'recordProofHash',
      'logicalRevision',
    });
    if (!isCryptoWireRecordId(value['id']) ||
        cryptoRecordDomain(value['type']) != value['domain']) {
      throw const FormatException('crypto_relocation_record_identity');
    }
    hashValue(value['recordProofHash']);
    safe(value['logicalRevision']);
    return cryptoSha256([
      ...utf8.encode('JivieProjectRelocationRecord/v2\n'),
      ...CryptoJson.encode(value),
    ]);
  }
}
