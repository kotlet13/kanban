import 'dart:convert';
import 'account_directory_v2.dart' show cryptoSha256;
import 'crypto_json.dart';
import 'crypto_record_address.dart';

/// Closed signed deletion evidence. No record tombstones or key-erasure claim
/// are inferred from transport flags or an unsigned preview.
class CryptoScopeDeletionCodec {
  static const certificateDomain = 'JivieScopeDeletion/v2\n';
  static const headerDomain = 'JivieScopeDeletionHeader/v2\n';
  static const leafDomain = 'JivieScopeDeletionLeaf/v2\n';
  static const maxScopes = 100;
  static const retention = <String, dynamic>{
    'version': 1,
    'retainsSignedEvidence': true,
    'mayRetainEncryptedHistoricalBackups': true,
    'mayRetainLegacyMigrationSources': true,
    'erasesOtherKeyCopies': false,
  };
  static void fields(Map value, Set<String> keys) {
    if (value.length != keys.length || !value.keys.every(keys.contains)) {
      throw const FormatException('crypto_scope_deletion_shape');
    }
  }

  static void uuid(Object? value) {
    if (!isCryptoCanonicalUuid(value)) {
      throw const FormatException('crypto_scope_deletion_context');
    }
  }

  static void digest(Object? value) {
    if (value is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(value)) {
      throw const FormatException('crypto_scope_deletion_context');
    }
  }

  static void safeInt(
    Object? value, {
    int minimum = 0,
    int maximum = 9007199254740991,
  }) {
    if (value is! int || value < minimum || value > maximum) {
      throw const FormatException('crypto_scope_deletion_count');
    }
  }

  static void scope(Map value) {
    fields(value, {'scopeId', 'headHash', 'accessRevision', 'lifecycleHash'});
    uuid(value['scopeId']);
    digest(value['headHash']);
    digest(value['lifecycleHash']);
    safeInt(value['accessRevision']);
  }

  static void retained(Map value) {
    fields(value, retention.keys.toSet());
    if (retention.entries.any((entry) => value[entry.key] != entry.value)) {
      throw const FormatException('crypto_scope_deletion_retention');
    }
  }

  static void certificate(Map value) {
    fields(value, {
      'version',
      'serverId',
      'rootScopeId',
      'requestId',
      'actorAccountId',
      'actorDeviceId',
      'scopes',
      'graphRoot',
      'graphCount',
      'retention',
      if (value.containsKey('parentTopologyHash')) 'parentTopologyHash',
    });
    if (value.containsKey('parentTopologyHash'))
      digest(value['parentTopologyHash']);
    if (value['version'] != 2) {
      throw const FormatException('crypto_scope_deletion_version');
    }
    for (final k in [
      'serverId',
      'rootScopeId',
      'requestId',
      'actorAccountId',
      'actorDeviceId',
    ]) {
      uuid(value[k]);
    }
    digest(value['graphRoot']);
    safeInt(value['graphCount'], minimum: 1, maximum: maxScopes);
    if (value['retention'] is! Map ||
        value['scopes'] is! List ||
        value['scopes'].length != value['graphCount']) {
      throw const FormatException('crypto_scope_deletion_shape');
    }
    retained(value['retention'] as Map);
    String? previous;
    var root = false;
    for (final item in value['scopes'] as List) {
      if (item is! Map) {
        throw const FormatException('crypto_scope_deletion_shape');
      }
      scope(item);
      final id = item['scopeId'] as String;
      if (previous != null && previous.compareTo(id) >= 0) {
        throw const FormatException('crypto_scope_deletion_order');
      }
      root |= id == value['rootScopeId'];
      previous = id;
    }
    if (!root) throw const FormatException('crypto_scope_deletion_context');
  }

  static const headerFields = {
    'version',
    'serverId',
    'requestId',
    'actorAccountId',
    'actorDeviceId',
    'authorDirectoryHeadHash',
    'privateCertificateHash',
    'rootToken',
    'graphRoot',
    'graphCount',
    'retention',
    'scopeLeafRoot',
    'scopeLeafCount',
  };
  static void header(Map value) {
    fields(value, {
      ...headerFields,
      if (value.containsKey('parentTopologyHash')) 'parentTopologyHash',
    });
    if (value.containsKey('parentTopologyHash'))
      digest(value['parentTopologyHash']);
    if (value['version'] != 2) {
      throw const FormatException('crypto_scope_deletion_version');
    }
    for (final k in [
      'serverId',
      'requestId',
      'actorAccountId',
      'actorDeviceId',
    ]) {
      uuid(value[k]);
    }
    for (final k in [
      'authorDirectoryHeadHash',
      'privateCertificateHash',
      'rootToken',
      'graphRoot',
      'scopeLeafRoot',
    ]) {
      digest(value[k]);
    }
    safeInt(value['graphCount'], minimum: 1, maximum: maxScopes);
    if (value['scopeLeafCount'] != value['graphCount'] ||
        value['retention'] is! Map) {
      throw const FormatException('crypto_scope_deletion_count');
    }
    retained(value['retention'] as Map);
  }

  static void leaf(Map value) {
    fields(value, {
      'version',
      'serverId',
      'requestId',
      'headerContextHash',
      'scopeId',
      'headHash',
      'accessRevision',
      'lifecycleHash',
    });
    if (value['version'] != 2) {
      throw const FormatException('crypto_scope_deletion_version');
    }
    uuid(value['serverId']);
    uuid(value['requestId']);
    digest(value['headerContextHash']);
    scope({
      for (final k in [
        'scopeId',
        'headHash',
        'accessRevision',
        'lifecycleHash',
      ])
        k: value[k],
    });
  }

  static Future<String> rootToken(Map certificateBody) {
    certificate(certificateBody);
    return cryptoSha256([
      ...utf8.encode('JivieScopeDeletionRootToken/v2\n'),
      ...CryptoJson.encode({
        'version': 2,
        for (final k in ['serverId', 'requestId', 'rootScopeId'])
          k: certificateBody[k],
      }),
    ]);
  }

  static Future<String> headerContext(Map headerBody) {
    header(headerBody);
    final context = Map<String, dynamic>.from(headerBody)
      ..remove('scopeLeafRoot')
      ..remove('scopeLeafCount');
    return cryptoSha256([
      ...utf8.encode('JivieScopeDeletionHeaderContext/v2\n'),
      ...CryptoJson.encode(context),
    ]);
  }

  static Future<String> leafRoot(Map headerBody, List<String> hashes) {
    header(headerBody);
    if (hashes.length != headerBody['scopeLeafCount']) {
      throw const FormatException('crypto_scope_deletion_count');
    }
    String? previous;
    for (final hash in hashes) {
      digest(hash);
      if (previous != null && previous.compareTo(hash) >= 0) {
        throw const FormatException('crypto_scope_deletion_order');
      }
      previous = hash;
    }
    return cryptoSha256([
      ...utf8.encode('JivieScopeDeletionLeaves/v2\n'),
      ...utf8.encode('${hashes.join('\n')}\n'),
    ]);
  }
}
