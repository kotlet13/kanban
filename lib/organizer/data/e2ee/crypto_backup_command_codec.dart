import 'dart:convert';
import 'dart:typed_data';

import 'account_directory_v2.dart' show cryptoSha256;
import 'crypto_json.dart';

/// Lossless BACKUP-ONLY representation of immutable ciphertext chunk commands.
/// Tagged strings are never installed as an active request. Reconstruction and
/// original hashes are checked before signature/authority reconciliation.
class CryptoBackupCommandCodec {
  CryptoBackupCommandCodec(Map<String, dynamic> drafts, String? partition)
    : _partition = partition {
    try {
      final tables = drafts['tables'] as Map;
      final jobs = <String, Map>{};
      for (final raw in tables['crypto_document_jobs'] as List) {
        final row = raw as Map;
        jobs[row['id'] as String] = row;
      }
      for (final raw in tables['crypto_document_chunks'] as List) {
        final row = raw as Map, job = jobs[row['id']];
        if (job == null) throw const FormatException('crypto_backup_chunk_job');
        final bytes = base64Decode(
          (row['cipher'] as Map)['blobBase64'] as String,
        );
        final key =
            '${row['partition']}:${job['scope_id']}:${row['id']}:${row['offset']}';
        final previous = _chunks[key];
        if (previous != null && base64Encode(previous) != base64Encode(bytes)) {
          throw const FormatException('crypto_backup_chunk_conflict');
        }
        _chunks[key] = bytes;
      }
      for (final candidate
          in drafts['restoredCandidates'] as List? ?? const []) {
        final row = candidate as Map;
        final id = row['backupId'] as String;
        if (_restored.containsKey(id)) {
          throw const FormatException('crypto_backup_candidate_duplicate');
        }
        _restored[id] = CryptoBackupCommandCodec({
          'version': 1,
          'partition': row['partition'],
          'tables': row['tables'],
        }, row['partition'] as String?);
      }
      for (final codec in _restored.values) {
        codec._restored.addAll(_restored);
      }
    } on TypeError {
      throw const FormatException('crypto_backup_chunk_shape');
    } on RangeError {
      throw const FormatException('crypto_backup_chunk_shape');
    }
  }
  final String? _partition;
  final _chunks = <String, Uint8List>{};
  final _restored = <String, CryptoBackupCommandCodec>{};
  CryptoBackupCommandCodec forRestoredBackup(String backupId) {
    final child = _restored[backupId];
    if (child == null)
      throw const FormatException('crypto_backup_candidate_missing');
    return child;
  }

  static const _commandTag = 'JIVIE_BACKUP_CIPHER_COMMAND/v1\n';
  static const _receiptTag = 'JIVIE_BACKUP_CIPHER_RECEIPT/v1\n';

  String _text(Object? value) {
    Object? sorted(Object? x) {
      if (x is Map) {
        final keys = x.keys.cast<String>().toList()..sort();
        return {for (final k in keys) k: sorted(x[k])};
      }
      if (x is List) return x.map(sorted).toList();
      return x;
    }

    return jsonEncode(sorted(value));
  }

  Future<String> compactSigned(
    String original, {
    required String requestHash,
  }) async {
    if (original.startsWith(_commandTag)) {
      await expandSigned(original, requestHash: requestHash);
      return original;
    }
    final signed = jsonDecode(original);
    if (signed is! Map ||
        signed.length != 2 ||
        signed['commandBase64'] is! String ||
        signed['signatureBase64'] is! String ||
        _text(signed) != original) {
      return original;
    }
    final commandBytes = cryptoBase64(signed['commandBase64']);
    final decoded = CryptoJson.decode(commandBytes);
    if (decoded is! Map ||
        decoded['operation'] != 'crypto2.blob.chunk' ||
        decoded['payload'] is! Map) {
      return original;
    }
    final command = Map<String, dynamic>.from(decoded),
        payload = Map<String, dynamic>.from(decoded['payload'] as Map);
    final bytes =
        _chunks['$_partition:${payload['scopeId']}:${payload['id']}:${payload['offset']}'];
    // A superseded completed object may intentionally have no current snapshot
    // bytes. Its transport row is separately omitted only after exact ACK proof.
    if (bytes == null) return original;
    if (base64Encode(bytes) != payload['dataBase64']) {
      throw const FormatException('crypto_backup_chunk_conflict');
    }
    if (await cryptoSha256(commandBytes) != requestHash ||
        base64Encode(CryptoJson.encode(command)) != signed['commandBase64']) {
      throw const FormatException('crypto_backup_command_hash');
    }
    payload.remove('dataBase64');
    command['payload'] = payload;
    final compact =
        _commandTag +
        _text({
          'version': 1,
          'partition': _partition,
          'scopeId': payload['scopeId'],
          'blobId': payload['id'],
          'offset': payload['offset'],
          'length': bytes.length,
          'sha256': await cryptoSha256(bytes),
          'command': command,
          'signatureBase64': signed['signatureBase64'],
          'requestHash': requestHash,
          'signedBodyHash': await cryptoSha256(utf8.encode(original)),
        });
    if (await expandSigned(compact, requestHash: requestHash) != original) {
      throw const FormatException('crypto_backup_command_roundtrip');
    }
    return compact;
  }

  Future<String> expandSigned(
    String value, {
    required String requestHash,
  }) async {
    try {
      return await _expandSigned(value, requestHash: requestHash);
    } on TypeError {
      throw const FormatException('crypto_backup_command_shape');
    } on RangeError {
      throw const FormatException('crypto_backup_command_shape');
    }
  }

  Future<String> _expandSigned(
    String value, {
    required String requestHash,
  }) async {
    if (!value.startsWith(_commandTag)) return value;
    final raw = jsonDecode(value.substring(_commandTag.length));
    if (raw is! Map ||
        raw.length != 11 ||
        raw['version'] != 1 ||
        raw['partition'] != _partition ||
        raw['requestHash'] != requestHash ||
        raw['command'] is! Map ||
        raw['signatureBase64'] is! String ||
        raw['length'] is! int ||
        raw['length'] < 1 ||
        raw['length'] > 196608) {
      throw const FormatException('crypto_backup_command_reference');
    }
    final command = Map<String, dynamic>.from(raw['command'] as Map),
        payload = Map<String, dynamic>.from(command['payload'] as Map);
    if (command['operation'] != 'crypto2.blob.chunk' ||
        payload.containsKey('dataBase64') ||
        payload['scopeId'] != raw['scopeId'] ||
        payload['id'] != raw['blobId'] ||
        payload['offset'] != raw['offset']) {
      throw const FormatException('crypto_backup_command_binding');
    }
    final bytes =
        _chunks['$_partition:${raw['scopeId']}:${raw['blobId']}:${raw['offset']}'];
    if (bytes == null ||
        bytes.length != raw['length'] ||
        await cryptoSha256(bytes) != raw['sha256']) {
      throw const FormatException('crypto_backup_chunk_missing');
    }
    payload['dataBase64'] = base64Encode(bytes);
    command['payload'] = payload;
    final canonical = CryptoJson.encode(command);
    if (await cryptoSha256(canonical) != requestHash) {
      throw const FormatException('crypto_backup_command_hash');
    }
    final expanded = _text({
      'commandBase64': base64Encode(canonical),
      'signatureBase64': raw['signatureBase64'],
    });
    if (await cryptoSha256(utf8.encode(expanded)) != raw['signedBodyHash']) {
      throw const FormatException('crypto_backup_signed_body_hash');
    }
    return expanded;
  }

  Future<String?> compactReceipt(
    String? original, {
    required String requestHash,
  }) async {
    if (original == null || original.startsWith(_receiptTag)) return original;
    final receipt = jsonDecode(original);
    if (receipt is! Map ||
        receipt['authorization'] is! Map ||
        _text(receipt) != original) {
      return original;
    }
    final auth = _text(receipt['authorization']);
    final compact = await compactSigned(auth, requestHash: requestHash);
    if (compact == auth) return original;
    final remaining = Map<String, dynamic>.from(receipt)
      ..remove('authorization');
    final tagged =
        _receiptTag +
        _text({
          'version': 1,
          'receipt': remaining,
          'authorization': compact,
          'hash': await cryptoSha256(utf8.encode(original)),
        });
    if (await expandReceipt(tagged, requestHash: requestHash) != original) {
      throw const FormatException('crypto_backup_receipt_roundtrip');
    }
    return tagged;
  }

  Future<String?> expandReceipt(
    String? value, {
    required String requestHash,
  }) async {
    if (value == null || !value.startsWith(_receiptTag)) return value;
    final raw = jsonDecode(value.substring(_receiptTag.length));
    if (raw is! Map ||
        raw.length != 4 ||
        raw['version'] != 1 ||
        raw['receipt'] is! Map ||
        raw['authorization'] is! String) {
      throw const FormatException('crypto_backup_receipt_reference');
    }
    final receipt = Map<String, dynamic>.from(raw['receipt'] as Map);
    receipt['authorization'] = jsonDecode(
      await expandSigned(
        raw['authorization'] as String,
        requestHash: requestHash,
      ),
    );
    final text = _text(receipt);
    if (await cryptoSha256(utf8.encode(text)) != raw['hash']) {
      throw const FormatException('crypto_backup_receipt_hash');
    }
    return text;
  }

  Future<Map<String, dynamic>> compactEvidence(
    Map<String, dynamic> evidence,
  ) async {
    final tables = Map<String, dynamic>.from(evidence['tables'] as Map);
    tables['crypto_outbox'] = [
      for (final raw in tables['crypto_outbox'] as List)
        await _compactRow(Map<String, dynamic>.from(raw as Map)),
    ];
    final result = {...evidence, 'tables': tables};
    await validateEvidence(result);
    return result;
  }

  Future<Map<String, dynamic>> _compactRow(Map<String, dynamic> row) async => {
    ...row,
    'signed_body': await compactSigned(
      row['signed_body'] as String,
      requestHash: row['request_hash'] as String,
    ),
    'response': await compactReceipt(
      row['response'] as String?,
      requestHash: row['request_hash'] as String,
    ),
  };
  Future<void> validateEvidence(Map<String, dynamic> evidence) async =>
      _validateEvidence(evidence, 0);

  Future<void> _validateEvidence(
    Map<String, dynamic> evidence,
    int depth,
  ) async {
    if (depth > 16) throw const FormatException('crypto_backup_evidence_depth');
    for (final raw in (evidence['tables'] as Map)['crypto_outbox'] as List) {
      final row = raw as Map;
      await expandSigned(
        row['signed_body'] as String,
        requestHash: row['request_hash'] as String,
      );
      await expandReceipt(
        row['response'] as String?,
        requestHash: row['request_hash'] as String,
      );
    }
    for (final raw
        in (evidence['tables'] as Map)['crypto_restore_evidence'] as List? ??
            const []) {
      final row = raw as Map;
      final child = _restored[row['backup_id']] ?? this;
      await child._validateEvidence(
        Map<String, dynamic>.from(jsonDecode(row['evidence'] as String) as Map),
        depth + 1,
      );
    }
  }
}
