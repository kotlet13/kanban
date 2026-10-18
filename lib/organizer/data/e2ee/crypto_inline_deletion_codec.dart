import 'dart:convert';
import 'account_directory_v2.dart' show cryptoSha256;
import 'crypto_json.dart';
import 'crypto_record_address.dart';
import 'crypto_scope_deletion_codec.dart';

/// Inline deletion commits one complete signed graph while retaining the
/// original canonical IDs, source revisions and immutable request bytes.
class CryptoInlineDeletionCodec {
  static const domain = 'JivieInlineDeletion/v2\n';
  static const maxRecords = 10000;
  static void graphDescriptor(Map value) {
    CryptoScopeDeletionCodec.fields(value, {
      'scopeId',
      'id',
      'type',
      'domain',
      'revision',
      'recordProofHash',
    });
    CryptoScopeDeletionCodec.uuid(value['scopeId']);
    if (!isCryptoWireRecordId(value['id']) ||
        cryptoRecordDomain(value['type']) != value['domain']) {
      throw const FormatException('crypto_inline_delete_domain');
    }
    CryptoScopeDeletionCodec.safeInt(value['revision'], minimum: 1);
    CryptoScopeDeletionCodec.digest(value['recordProofHash']);
  }

  static void tombstoneDescriptor(Map value) {
    CryptoScopeDeletionCodec.fields(value, {
      'id',
      'domain',
      'type',
      'expectedRevision',
      'previousRecordHash',
      'recordProofHash',
      'batchCommitmentHash',
    });
    if (!isCryptoWireRecordId(value['id']) ||
        cryptoRecordDomain(value['type']) != value['domain']) {
      throw const FormatException('crypto_inline_delete_domain');
    }
    CryptoScopeDeletionCodec.safeInt(value['expectedRevision'], minimum: 1);
    for (final field in [
      'previousRecordHash',
      'recordProofHash',
      'batchCommitmentHash',
    ]) {
      CryptoScopeDeletionCodec.digest(value[field]);
    }
  }

  static Future<String> graphRoot(List<Map<String, dynamic>> values) =>
      _root('JivieInlineDeletionGraph/v2\n', values, graphDescriptor);
  static Future<String> tombstoneLeaf(Map<String, dynamic> descriptor) async {
    tombstoneDescriptor(descriptor);
    return cryptoSha256(
      utf8.encode('JivieInlineDeletionLeaf/v2\n') +
          CryptoJson.encode(descriptor),
    );
  }

  static Future<String> tombstoneRoot(List<Map<String, dynamic>> values) async {
    final seen = <String>{};
    final hashes = <String>[];
    for (final value in values) {
      if (!seen.add(value['id'] as String)) {
        throw const FormatException('crypto_inline_delete_order');
      }
      hashes.add(await tombstoneLeaf(value));
    }
    hashes.sort();
    return tombstoneDigestRoot(hashes);
  }

  static Future<String> tombstoneDigestRoot(List<String> hashes) async {
    if (hashes.length > maxRecords) {
      throw const FormatException('crypto_inline_delete_limit');
    }
    String? previous;
    for (final hash in hashes) {
      CryptoScopeDeletionCodec.digest(hash);
      if (previous != null && previous.compareTo(hash) >= 0) {
        throw const FormatException('crypto_inline_delete_order');
      }
      previous = hash;
    }
    return cryptoSha256(
      utf8.encode(
        'JivieInlineDeletionTombstones/v2\n${hashes.map((v) => '$v\n').join()}',
      ),
    );
  }

  static Future<String> _root(
    String prefix,
    List<Map<String, dynamic>> values,
    void Function(Map value) validate,
  ) async {
    if (values.length > maxRecords)
      throw const FormatException('crypto_inline_delete_limit');
    final bytes = <int>[...utf8.encode(prefix)];
    String? previous;
    for (final value in values) {
      validate(value);
      final id = value['id'] as String;
      if (previous != null && previous.compareTo(id) >= 0)
        throw const FormatException('crypto_inline_delete_order');
      previous = id;
      bytes.addAll(CryptoJson.encode(value));
      bytes.add(10);
    }
    return cryptoSha256(bytes);
  }

  static Future<String> batchRoot(List<String> digests) async {
    if (digests.length > maxRecords)
      throw const FormatException('crypto_inline_delete_limit');
    String? previous;
    for (final digest in digests) {
      CryptoScopeDeletionCodec.digest(digest);
      if (previous != null && previous.compareTo(digest) >= 0)
        throw const FormatException('crypto_inline_delete_order');
      previous = digest;
    }
    return cryptoSha256(
      utf8.encode(
        'JivieInlineDeletionBatches/v2\n${digests.map((v) => '$v\n').join()}',
      ),
    );
  }

  static void certificate(Map value) {
    CryptoScopeDeletionCodec.fields(value, {
      'version',
      'serverId',
      'scopeId',
      'projectId',
      'projectWireId',
      'actionId',
      'planHash',
      'requestId',
      'membershipHeadHash',
      'accessRevision',
      'lifecycleHash',
      'graphRoot',
      'graphCount',
      'tombstoneRoot',
      'tombstoneCount',
      'batchRoot',
      'batchCount',
      'accountId',
      'deviceId',
      'authorDirectoryHeadHash',
    });
    if (value['version'] != 2)
      throw const FormatException('crypto_inline_delete_version');
    for (final field in [
      'serverId',
      'scopeId',
      'projectId',
      'actionId',
      'requestId',
      'accountId',
      'deviceId',
    ]) {
      CryptoScopeDeletionCodec.uuid(value[field]);
    }
    if (!isCryptoWireRecordId(value['projectWireId']))
      throw const FormatException('crypto_inline_delete_context');
    for (final field in [
      'planHash',
      'membershipHeadHash',
      'lifecycleHash',
      'graphRoot',
      'tombstoneRoot',
      'batchRoot',
      'authorDirectoryHeadHash',
    ]) {
      CryptoScopeDeletionCodec.digest(value[field]);
    }
    CryptoScopeDeletionCodec.safeInt(value['accessRevision']);
    for (final field in ['graphCount', 'tombstoneCount', 'batchCount']) {
      CryptoScopeDeletionCodec.safeInt(
        value[field],
        minimum: 1,
        maximum: maxRecords,
      );
    }
    if (value['graphCount'] != value['tombstoneCount'] ||
        value['batchCount'] > value['tombstoneCount']) {
      throw const FormatException('crypto_inline_delete_count');
    }
  }

  static Future<String> token(Map value) => cryptoSha256(
    utf8.encode('JivieInlineDeletionToken/v2\n') +
        CryptoJson.encode({
          'version': 2,
          'serverId': value['serverId'],
          'scopeId': value['scopeId'],
          'projectWireId': value['projectWireId'],
          'actionId': value['actionId'],
        }),
  );
}
