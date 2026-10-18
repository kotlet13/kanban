import 'dart:convert';

import 'account_directory_v2.dart' show cryptoSha256;
import 'crypto_json.dart';
import 'crypto_record_address.dart';

/// One structural, signer-observed child set. It contains no account names,
/// balances or child UUIDs; unreadable tokens remain explicitly incomplete.
abstract final class CryptoFinanceTopology {
  static const maximum = 1000;
  static Future<String> childToken(
    String server,
    String parent,
    String child,
  ) => cryptoSha256([
    ...utf8.encode('JivieFinanceTopologyChild/v3\n'),
    ...CryptoJson.encode({
      'version': 3,
      'serverId': server,
      'parentScopeId': parent,
      'childScopeId': child,
    }),
  ]);
  static Future<Map<String, dynamic>> create({
    required String serverId,
    required String scopeId,
    required List<String> childTokens,
    Map<String, dynamic>? previous,
  }) async {
    if (!isCryptoCanonicalUuid(serverId) || !isCryptoCanonicalUuid(scopeId)) {
      throw const FormatException('crypto_finance_topology_context');
    }
    final sorted = childTokens.toList()..sort();
    if (sorted.length > maximum ||
        sorted.toSet().length != sorted.length ||
        sorted.any((t) => !RegExp(r'^[a-f0-9]{64}$').hasMatch(t))) {
      throw const FormatException('crypto_finance_topology_set');
    }
    if (previous != null) {
      await validate(previous, serverId: serverId, scopeId: scopeId);
    }
    final removed = previous == null
        ? <String>[]
        : (previous['childTokens'] as List)
              .cast<String>()
              .where((t) => !sorted.contains(t))
              .toList();
    final body = <String, dynamic>{
      'version': 3,
      'serverId': serverId,
      'scopeId': scopeId,
      'generation': previous == null ? 0 : (previous['generation'] as int) + 1,
      'previousRoot': previous?['root'] ?? '0' * 64,
      'childTokens': sorted,
      'removedTokens': removed,
      'count': sorted.length,
    };
    return {
      ...body,
      'root': await cryptoSha256([
        ...utf8.encode('JivieFinanceTopology/v3\n'),
        ...CryptoJson.encode(body),
      ]),
    };
  }

  static Future<void> validate(
    Map<String, dynamic> value, {
    required String serverId,
    required String scopeId,
  }) async {
    const keys = {
      'version',
      'serverId',
      'scopeId',
      'generation',
      'previousRoot',
      'childTokens',
      'removedTokens',
      'count',
      'root',
    };
    if (value.length != keys.length ||
        !value.keys.every(keys.contains) ||
        value['version'] != 3 ||
        value['serverId'] != serverId ||
        value['scopeId'] != scopeId ||
        value['generation'] is! int ||
        value['generation'] < 0 ||
        value['generation'] > 9007199254740991 ||
        value['childTokens'] is! List ||
        value['removedTokens'] is! List ||
        value['count'] != (value['childTokens'] as List).length ||
        value['count'] > maximum) {
      throw const FormatException('crypto_finance_topology_context');
    }
    for (final list in [
      value['childTokens'] as List,
      value['removedTokens'] as List,
    ]) {
      String? previous;
      if (list.length > maximum) {
        throw const FormatException('crypto_finance_topology_set');
      }
      for (final token in list) {
        if (token is! String ||
            !RegExp(r'^[a-f0-9]{64}$').hasMatch(token) ||
            previous != null && previous.compareTo(token) >= 0) {
          throw const FormatException('crypto_finance_topology_set');
        }
        previous = token;
      }
    }
    if ((value['removedTokens'] as List).any(
          (t) => (value['childTokens'] as List).contains(t),
        ) ||
        value['previousRoot'] is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(value['previousRoot']) ||
        value['generation'] == 0 &&
            (value['previousRoot'] != '0' * 64 ||
                (value['removedTokens'] as List).isNotEmpty)) {
      throw const FormatException('crypto_finance_topology_link');
    }
    final body = {
      for (final e in value.entries)
        if (e.key != 'root') e.key: e.value,
    };
    if (value['root'] !=
        await cryptoSha256([
          ...utf8.encode('JivieFinanceTopology/v3\n'),
          ...CryptoJson.encode(body),
        ])) {
      throw const FormatException('crypto_finance_topology_root');
    }
  }

  static Future<void> successor(
    Map<String, dynamic> before,
    Map<String, dynamic> after,
  ) async {
    await validate(
      before,
      serverId: before['serverId'],
      scopeId: before['scopeId'],
    );
    await validate(
      after,
      serverId: before['serverId'],
      scopeId: before['scopeId'],
    );
    final removed = (before['childTokens'] as List)
        .where((t) => !(after['childTokens'] as List).contains(t))
        .toList();
    if (after['generation'] != before['generation'] + 1 ||
        after['previousRoot'] != before['root'] ||
        jsonEncode(removed) != jsonEncode(after['removedTokens'])) {
      throw const FormatException('crypto_finance_topology_link');
    }
  }
}
