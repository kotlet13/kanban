import 'dart:convert';
import 'package:cryptography/cryptography.dart' show Sha256;

import 'account_directory_v2.dart' show cryptoSha256;
import 'crypto_json.dart';
import 'crypto_record_address.dart';

/// Opaque certificate commitments only. A caller must independently verify each
/// signed transformation and the complete own frozen source inventory first.
class CryptoMigrationNotificationCodec {
  static const kinds = {'reminder', 'inbox', 'preference', 'inboxState'};
  static const contextFields = {
    'version',
    'serverId',
    'migrationId',
    'captureId',
    'accountId',
    'sourceInventoryRoot',
  };

  static void context(Map value) {
    fields(value, contextFields);
    if (value['version'] != 3) {
      throw const FormatException('crypto_notification_migration_version');
    }
    for (final key in const [
      'serverId',
      'migrationId',
      'captureId',
      'accountId',
    ]) {
      if (!isCryptoCanonicalUuid(value[key])) {
        throw const FormatException('crypto_notification_migration_context');
      }
    }
    digest(value['sourceInventoryRoot']);
  }

  /// Pre-certificate framing: no archive/cold-parity/certificate cycle.
  static Future<String> selectionRoot(
    Map value,
    int expectedCount,
    Stream<String> digests,
  ) async {
    context(value);
    count(expectedCount);
    final sink = Sha256().newHashSink()
      ..add(utf8.encode('JivieNotificationSelection/v3\n'))
      ..add(CryptoJson.encode(value))
      ..add([10]);
    String? previous;
    var total = 0;
    await for (final hash in digests) {
      digest(hash);
      if (previous != null && previous.compareTo(hash) >= 0) {
        throw const FormatException('crypto_notification_migration_order');
      }
      if (++total > expectedCount) {
        throw const FormatException('crypto_notification_migration_count');
      }
      sink.add(utf8.encode('$hash\n'));
      previous = hash;
    }
    if (total != expectedCount) {
      throw const FormatException('crypto_notification_migration_incomplete');
    }
    sink.close();
    return (await sink.hash()).bytes
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  static const headerFields = {
    'version',
    'serverId',
    'migrationId',
    'captureId',
    'accountId',
    'sourceInventoryRoot',
    'archiveManifestHash',
    'coldParityProofHash',
    'authorDirectoryHeadHash',
    'transformCount',
    'sourceCounts',
    'transformRoot',
  };
  static void fields(Map value, Set<String> fields) {
    if (value.length != fields.length || !value.keys.every(fields.contains)) {
      throw const FormatException('crypto_notification_migration_shape');
    }
  }

  static void digest(Object? value) {
    if (value is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(value)) {
      throw const FormatException('crypto_notification_migration_context');
    }
  }

  static void count(Object? value) {
    if (value is! int || value < 0 || value > 9007199254740991) {
      throw const FormatException('crypto_notification_migration_count');
    }
  }

  static void header(Map value) {
    fields(value, headerFields);
    if (value['version'] != 3) {
      throw const FormatException('crypto_notification_migration_version');
    }
    for (final key in const [
      'serverId',
      'migrationId',
      'captureId',
      'accountId',
    ]) {
      if (!isCryptoCanonicalUuid(value[key])) {
        throw const FormatException('crypto_notification_migration_context');
      }
    }
    for (final key in const [
      'sourceInventoryRoot',
      'archiveManifestHash',
      'coldParityProofHash',
      'authorDirectoryHeadHash',
      'transformRoot',
    ]) {
      digest(value[key]);
    }
    final counts = value['sourceCounts'];
    if (counts is! Map) {
      throw const FormatException('crypto_notification_migration_count');
    }
    fields(counts, kinds);
    var total = 0;
    for (final kind in kinds) {
      count(counts[kind]);
      total += counts[kind] as int;
      count(total);
    }
    count(value['transformCount']);
    if (value['transformCount'] != total) {
      throw const FormatException('crypto_notification_migration_count');
    }
  }

  static Future<String> scopeToken(Map value) async {
    header(value);
    return cryptoSha256([
      ...utf8.encode('JivieNotificationMigrationToken/v3\n'),
      ...CryptoJson.encode({
        'version': 3,
        for (final key in const [
          'serverId',
          'accountId',
          'migrationId',
          'captureId',
          'sourceInventoryRoot',
        ])
          key: value[key],
      }),
    ]);
  }

  static Future<String> leafDigest(Map leaf) async {
    fields(leaf, {'bindingId', 'kind', 'transformHash', 'useProofHash'});
    if (!isCryptoCanonicalUuid(leaf['bindingId']) ||
        !kinds.contains(leaf['kind'])) {
      throw const FormatException('crypto_notification_migration_kind');
    }
    digest(leaf['transformHash']);
    if (leaf['useProofHash'] != null) {
      digest(leaf['useProofHash']);
      if (leaf['kind'] != 'reminder') {
        throw const FormatException('crypto_notification_migration_kind');
      }
    }
    return cryptoSha256([
      ...utf8.encode('JivieNotificationTransformLeaf/v3\n'),
      ...CryptoJson.encode(leaf),
    ]);
  }

  static Future<String> transformRoot(Map value, Stream<String> digests) async {
    header(value);
    final context = Map<String, dynamic>.from(value)..remove('transformRoot');
    final bytes = Sha256().newHashSink()
      ..add(utf8.encode('JivieNotificationTransforms/v3\n'))
      ..add(CryptoJson.encode(context))
      ..add([10]);
    String? previous;
    var total = 0;
    await for (final hash in digests) {
      digest(hash);
      if (previous != null && previous.compareTo(hash) >= 0) {
        throw const FormatException('crypto_notification_migration_order');
      }
      if (++total > (value['transformCount'] as int)) {
        throw const FormatException('crypto_notification_migration_count');
      }
      bytes.add(utf8.encode('$hash\n'));
      previous = hash;
    }
    if (total != value['transformCount']) {
      throw const FormatException('crypto_notification_migration_incomplete');
    }
    bytes.close();
    return (await bytes.hash()).bytes
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
  }
}
