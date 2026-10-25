import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'crypto_business_json.dart';
import 'crypto_record_address.dart';

/// Versioned, signed authorization metadata. The server compares the opaque
/// commitments; recipients also recompute them from authenticated plaintext.
/// The random per-record MAC key never occurs in public record metadata.
abstract final class CryptoRecordPolicy {
  static const businessTypes = {
    'project',
    'task',
    'event',
    'shoppingList',
    'shoppingItem',
    'householdPerson',
    'garden',
    'idea',
    'financeAccount',
    'financeEntry',
    'financeTransfer',
    'personalFinanceEntry',
    'personalFinanceAccount',
    'financeRecurrenceRule',
    'table',
    'attachment',
  };
  static const secretField = '_recordPolicy';
  static const operations = {
    'create',
    'edit',
    'delete',
    'shoppingCheck',
    'restore',
  };
  static const groups = {'content', 'assignment', 'checked'};

  static void validate(Map<String, dynamic> value) {
    const fields = {
      'version',
      'createdByAccountId',
      'operation',
      'fieldCommitments',
    };
    final commitments = value['fieldCommitments'];
    if (value.length != fields.length ||
        !value.keys.every(fields.contains) ||
        value['version'] != 1 ||
        (value['createdByAccountId'] != null &&
            !isCryptoCanonicalUuid(value['createdByAccountId'])) ||
        !operations.contains(value['operation']) ||
        commitments is! Map ||
        commitments.length != groups.length ||
        !commitments.keys.every(groups.contains) ||
        !commitments.values.every(
          (v) => v is String && RegExp(r'^[a-f0-9]{64}$').hasMatch(v),
        )) {
      throw const FormatException('crypto_record_policy_shape');
    }
  }

  static void validateRestore(Map<String, dynamic> record) {
    final metadata = record['metadata'] as Map;
    final tag = metadata['recordRestore'];
    final restoring =
        (metadata['recordPolicy'] as Map?)?['operation'] == 'restore';
    if (restoring != (tag != null)) {
      throw const FormatException('crypto_record_restore_invalid');
    }
    if (!restoring) return;
    const fields = {'version', 'tombstoneProofHash', 'previousLiveProofHash'};
    if (tag is! Map ||
        tag.length != fields.length ||
        !tag.keys.every(fields.contains) ||
        tag['version'] != 1 ||
        ![
          tag['tombstoneProofHash'],
          tag['previousLiveProofHash'],
        ].every((v) => v is String && RegExp(r'^[a-f0-9]{64}$').hasMatch(v)) ||
        tag['tombstoneProofHash'] != record['previousRecordHash'] ||
        record['expectedRevision'] is! int ||
        record['expectedRevision'] < 1 ||
        record['deleted'] != false) {
      throw const FormatException('crypto_record_restore_invalid');
    }
  }

  static Uint8List secret(Map<String, dynamic> payload) {
    final value = payload[secretField];
    if (value is! Map ||
        value.length != 2 ||
        value['version'] != 1 ||
        value['keyBase64'] is! String) {
      throw const FormatException('crypto_record_policy_secret');
    }
    final bytes = base64Decode(value['keyBase64']);
    if (bytes.length != 32 || base64Encode(bytes) != value['keyBase64']) {
      bytes.fillRange(0, bytes.length, 0);
      throw const FormatException('crypto_record_policy_secret');
    }
    return bytes;
  }

  static Map<String, dynamic> attachSecret(
    Map<String, dynamic> payload,
    Uint8List key,
  ) {
    if (key.length != 32)
      throw const FormatException('crypto_record_policy_secret');
    return {
      ...payload,
      secretField: {'version': 1, 'keyBase64': base64Encode(key)},
    };
  }

  static Map<String, dynamic> businessPayload(Map<String, dynamic> payload) =>
      Map<String, dynamic>.from(payload)..remove(secretField);

  static Map<String, dynamic> _values(
    String type,
    Map<String, dynamic> payload,
  ) {
    final content = businessPayload(payload)
      ..remove('updatedAt')
      ..remove('cryptoPayloadBlob')
      ..remove('cryptoBlob');
    // These exact protocol fields describe transport, not editable values.
    // Never recursively remove similarly named business fields (e.g. cells).
    if (type == 'idea' && content['assets'] is List) {
      content['assets'] = [
        for (final asset in content['assets'] as List)
          if (asset is Map)
            Map<String, dynamic>.from(asset)..remove('cryptoBlob')
          else
            asset,
      ];
    }
    Object? assignment;
    Object? checked;
    if (type == 'task') {
      final ids = content.remove('assigneeAccountIds') ?? const <String>[];
      if (ids is! List ||
          !ids.every(isCryptoCanonicalUuid) ||
          ids.toSet().length != ids.length) {
        throw const FormatException('crypto_record_policy_assignment');
      }
      assignment = ids.cast<String>().toList()..sort();
    }
    if (type == 'shoppingItem') {
      checked = content.remove('isChecked');
      if (checked is! bool)
        throw const FormatException('crypto_record_policy_checked');
    }
    return {'content': content, 'assignment': assignment, 'checked': checked};
  }

  static Future<Map<String, String>> commitments({
    required String serverId,
    required String scopeId,
    required String domain,
    required String wireId,
    required String type,
    required Map<String, dynamic> payload,
    bool deleted = false,
  }) async {
    if (![serverId, scopeId].every(isCryptoCanonicalUuid) ||
        !isCryptoWireRecordId(wireId) ||
        !const {'content', 'finance'}.contains(domain) ||
        cryptoRecordDomain(type) != domain) {
      throw const FormatException('crypto_record_policy_context');
    }
    final key = secret(payload);
    try {
      final values = deleted
          ? <String, dynamic>{for (final group in groups) group: null}
          : _values(type, payload);
      final result = <String, String>{};
      for (final group in groups) {
        final bytes = CryptoBusinessJson.encode({
          'domain': 'JivieRecordFieldCommitment/v1',
          'serverId': serverId,
          'scopeId': scopeId,
          'recordDomain': domain,
          'id': wireId,
          'type': type,
          'group': group,
          if (deleted) 'deleted': true,
          'value': values[group],
        });
        try {
          final mac = await Hmac.sha256().calculateMac(
            bytes,
            secretKey: SecretKey(key),
          );
          result[group] = mac.bytes
              .map((b) => b.toRadixString(16).padLeft(2, '0'))
              .join();
        } finally {
          bytes.fillRange(0, bytes.length, 0);
        }
      }
      return result;
    } finally {
      key.fillRange(0, key.length, 0);
    }
  }

  static Future<Map<String, dynamic>> prepare({
    required String serverId,
    required String scopeId,
    required String domain,
    required String wireId,
    required String type,
    required String? creator,
    required String operation,
    required Map<String, dynamic> payload,
    bool deleted = false,
  }) async {
    final policy = <String, dynamic>{
      'version': 1,
      'createdByAccountId': creator,
      'operation': operation,
      'fieldCommitments': await commitments(
        serverId: serverId,
        scopeId: scopeId,
        domain: domain,
        wireId: wireId,
        type: type,
        payload: payload,
        deleted: deleted,
      ),
    };
    validate(policy);
    return policy;
  }

  /// Call only after verifying the signed membership head and predecessor (or
  /// its signed baseline). Current submitted assignments never grant authority.
  static void requireAuthority({
    required Map<String, dynamic> record,
    required String role,
    required String financeRole,
    Map<String, dynamic>? previousPolicy,
    Iterable<String> previousAssignees = const [],
  }) {
    final policy = Map<String, dynamic>.from(
      record['metadata']['recordPolicy'] as Map,
    );
    validate(policy);
    final actor = record['accountId'];
    if (record['domain'] == 'finance' && financeRole != 'write') {
      throw const FormatException('crypto_record_policy_finance_forbidden');
    }
    if (record['expectedRevision'] == 0) {
      if (role == 'viewer' ||
          policy['createdByAccountId'] != actor ||
          policy['operation'] != 'create' ||
          record['deleted'] == true) {
        throw const FormatException('crypto_record_policy_creation');
      }
      return;
    }
    if (policy['operation'] == 'create') {
      throw const FormatException('crypto_record_policy_operation');
    }
    if (previousPolicy == null ||
        policy['createdByAccountId'] != previousPolicy['createdByAccountId']) {
      throw const FormatException('crypto_record_policy_predecessor');
    }
    if (role == 'owner' || policy['createdByAccountId'] == actor) return;
    if (record['domain'] == 'content' &&
        record['deleted'] == false &&
        record['type'] == 'shoppingItem' &&
        policy['operation'] == 'shoppingCheck' &&
        const ['content', 'assignment'].every(
          (group) =>
              policy['fieldCommitments'][group] ==
              previousPolicy['fieldCommitments'][group],
        ))
      return;
    if (record['domain'] == 'content' &&
        record['deleted'] == false &&
        record['type'] == 'task' &&
        policy['operation'] == 'edit' &&
        previousAssignees.contains(actor) &&
        policy['fieldCommitments']['assignment'] ==
            previousPolicy['fieldCommitments']['assignment'])
      return;
    throw const FormatException('crypto_record_policy_author_forbidden');
  }

  static Future<void> verifyPayload({
    required Map<String, dynamic> record,
    required Map<String, dynamic>? payload,
    Map<String, dynamic>? previousPayload,
    Map<String, dynamic>? previousPolicy,
  }) async {
    final metadata = record['metadata'];
    final supplied = metadata is Map ? metadata['recordPolicy'] : null;
    if (supplied is! Map)
      throw const FormatException('crypto_record_policy_required');
    final policy = Map<String, dynamic>.from(supplied);
    validate(policy);
    validateRestore(record);
    final revision = record['expectedRevision'];
    if (policy['operation'] == 'create' &&
        (previousPolicy != null || revision is int && revision > 0)) {
      throw const FormatException('crypto_record_policy_operation');
    }
    if (previousPolicy != null) {
      validate(previousPolicy);
      if (policy['createdByAccountId'] !=
          previousPolicy['createdByAccountId']) {
        throw const FormatException('crypto_record_author_substitution');
      }
    }
    if (payload == null) {
      if (record['deleted'] != true ||
          policy['operation'] != 'delete' ||
          previousPolicy == null ||
          CryptoBusinessJson.canonical(policy['fieldCommitments']) !=
              CryptoBusinessJson.canonical(
                previousPolicy['fieldCommitments'],
              )) {
        throw const FormatException('crypto_record_policy_tombstone');
      }
      return;
    }
    if (record['deleted'] == true || policy['operation'] == 'delete') {
      throw const FormatException('crypto_record_policy_payload');
    }
    if (previousPayload != null) {
      final previousKey = secret(previousPayload), key = secret(payload);
      try {
        var difference = 0;
        for (var i = 0; i < 32; i++) {
          difference |= previousKey[i] ^ key[i];
        }
        if (difference != 0)
          throw const FormatException('crypto_record_policy_secret_changed');
      } finally {
        previousKey.fillRange(0, previousKey.length, 0);
        key.fillRange(0, key.length, 0);
      }
    }
    final actual = await commitments(
      serverId: record['serverId'],
      scopeId: record['scopeId'],
      domain: record['domain'],
      wireId: record['id'],
      type: record['type'],
      payload: payload,
    );
    if (CryptoBusinessJson.canonical(actual) !=
        CryptoBusinessJson.canonical(policy['fieldCommitments'])) {
      throw const FormatException('crypto_record_policy_payload_mismatch');
    }
    if (policy['operation'] == 'shoppingCheck' &&
        (record['type'] != 'shoppingItem' ||
            previousPolicy == null ||
            const ['content', 'assignment'].any(
              (group) =>
                  actual[group] != previousPolicy['fieldCommitments'][group],
            ))) {
      throw const FormatException('crypto_record_policy_checkbox');
    }
  }
}
