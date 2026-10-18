import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart' show Hmac, SecretKey, Sha256;
import 'package:sodium/sodium.dart' show SecureKey;

import 'crypto_inventory_json.dart';
import 'crypto_json.dart';
import 'crypto_record_address.dart';

/// Private capture context. In particular sourceId may be an idea board/SHA
/// tuple: this context belongs in the encrypted witness, never a public proof.
class CryptoCaptureSourceContext {
  CryptoCaptureSourceContext({
    required this.serverId,
    required this.captureId,
    required this.migrationId,
    required this.accountId,
    required this.scopeId,
    required this.domain,
    required this.sourceTable,
    required this.sourceId,
  }) {
    if (![
          serverId,
          captureId,
          migrationId,
          accountId,
        ].every(isCryptoCanonicalUuid) ||
        (scopeId != null && !isCryptoCanonicalUuid(scopeId)) ||
        !const ['content', 'finance', 'private'].contains(domain) ||
        (scopeId == null && domain != 'private') ||
        !RegExp(r'^familyhub_[a-z_]{1,69}$').hasMatch(sourceTable) ||
        sourceId.isEmpty ||
        utf8.encode(sourceId).length > 256 ||
        sourceId.codeUnits.any((c) => c < 32 || c == 127)) {
      throw const FormatException('crypto_capture_context');
    }
  }

  factory CryptoCaptureSourceContext.fromJson(Map<String, dynamic> value) {
    if (value.length != 9 || value['version'] != 3) {
      throw const FormatException('crypto_capture_version');
    }
    try {
      return CryptoCaptureSourceContext(
        serverId: value['serverId'] as String,
        captureId: value['captureId'] as String,
        migrationId: value['migrationId'] as String,
        accountId: value['accountId'] as String,
        scopeId: value['scopeId'] as String?,
        domain: value['domain'] as String,
        sourceTable: value['sourceTable'] as String,
        sourceId: value['sourceId'] as String,
      );
    } on TypeError {
      throw const FormatException('crypto_capture_context');
    }
  }

  final String serverId, captureId, migrationId, accountId;
  final String? scopeId;
  final String domain, sourceTable, sourceId;

  Map<String, dynamic> toJson() => {
    'version': 3,
    'serverId': serverId,
    'captureId': captureId,
    'migrationId': migrationId,
    'accountId': accountId,
    'scopeId': scopeId,
    'domain': domain,
    'sourceTable': sourceTable,
    'sourceId': sourceId,
  };
}

/// The only public source identifier is a random binding ID. Raw source IDs,
/// row hashes, file hashes and comparison salts are deliberately absent.
class CryptoCaptureBinding {
  CryptoCaptureBinding({
    required this.bindingId,
    required this.scopeId,
    required this.domain,
    required this.sourceCommitment,
  }) {
    if (!isCryptoCanonicalUuid(bindingId) ||
        (scopeId != null && !isCryptoCanonicalUuid(scopeId)) ||
        !const ['content', 'finance', 'private'].contains(domain) ||
        (scopeId == null && domain != 'private') ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(sourceCommitment)) {
      throw const FormatException('crypto_capture_binding');
    }
  }

  factory CryptoCaptureBinding.fromJson(Map<String, dynamic> value) {
    if (value.length != 4) {
      throw const FormatException('crypto_capture_binding');
    }
    try {
      return CryptoCaptureBinding(
        bindingId: value['bindingId'] as String,
        scopeId: value['scopeId'] as String?,
        domain: value['domain'] as String,
        sourceCommitment: value['sourceCommitment'] as String,
      );
    } on TypeError {
      throw const FormatException('crypto_capture_binding');
    }
  }

  final String bindingId, domain, sourceCommitment;
  final String? scopeId;
  Map<String, dynamic> toJson() => {
    'bindingId': bindingId,
    'scopeId': scopeId,
    'domain': domain,
    'sourceCommitment': sourceCommitment,
  };
}

/// Capture3 is intentionally a different format from the raw-hash preview2.
/// A sidecar salt is transient at the server boundary; the recovery-reachable
/// capture key and the encrypted witness are its only durable secret copies.
class CryptoCaptureV3 {
  static Future<String> bindingId(
    SecureKey captureKey,
    CryptoCaptureSourceContext context,
  ) async {
    final raw = captureKey.extractBytes();
    try {
      if (raw.length != 32) {
        throw const FormatException('crypto_capture_key');
      }
      final bytes = (await Hmac.sha256().calculateMac([
        ...utf8.encode('JivieCaptureBindingId/v3\n'),
        ...CryptoInventoryJson.encode(context.toJson()),
      ], secretKey: SecretKey(raw))).bytes.take(16).toList();
      bytes[6] = (bytes[6] & 0x0f) | 0x40;
      bytes[8] = (bytes[8] & 0x3f) | 0x80;
      final hex = bytes.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
      return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-'
          '${hex.substring(16, 20)}-${hex.substring(20)}';
    } finally {
      raw.fillRange(0, raw.length, 0);
    }
  }

  static Future<Uint8List> salt(
    SecureKey captureKey,
    CryptoCaptureSourceContext context,
  ) async {
    final raw = captureKey.extractBytes();
    try {
      if (raw.length != 32) {
        throw const FormatException('crypto_capture_key');
      }
      return Uint8List.fromList(
        (await Hmac.sha256().calculateMac([
          ...utf8.encode('JivieCaptureSalt/v3\n'),
          ...CryptoInventoryJson.encode(context.toJson()),
        ], secretKey: SecretKey(raw))).bytes,
      );
    } finally {
      raw.fillRange(0, raw.length, 0);
    }
  }

  static Future<String> sourceCommitment({
    required CryptoCaptureSourceContext context,
    required Uint8List salt,
    required Object typedRow,
  }) async {
    if (salt.length != 32 ||
        typedRow is! Map ||
        typedRow.keys.any((key) => key is! String)) {
      throw const FormatException('crypto_capture_salt');
    }
    return _hash([
      ...utf8.encode('JivieCaptureSource/v3\n'),
      ...CryptoInventoryJson.encode(context.toJson()),
      10,
      ...salt,
      ...CryptoInventoryJson.encode(typedRow),
    ]);
  }

  /// Secret material must be persisted only inside an encrypted witness/private
  /// journal. This map is never an inner signed command payload.
  static Map<String, dynamic> sidecar({
    required String bindingId,
    required CryptoCaptureSourceContext context,
    required Uint8List salt,
  }) {
    if (!isCryptoCanonicalUuid(bindingId) || salt.length != 32) {
      throw const FormatException('crypto_capture_sidecar');
    }
    return {
      'bindingId': bindingId,
      'sourceTable': context.sourceTable,
      'sourceId': context.sourceId,
      'saltBase64': base64Encode(salt),
    };
  }

  /// Complete sorted stream, including the empty inventory. The caller supplies
  /// authenticated header fields; this function never authenticates a server
  /// inventory or concludes absence merely because pagination ended.
  static Future<String> inventoryRoot({
    required String serverId,
    required String captureId,
    required String migrationId,
    required String accountId,
    required int sourceCount,
    required Stream<CryptoCaptureBinding> bindings,
  }) async {
    if (![
          serverId,
          captureId,
          migrationId,
          accountId,
        ].every(isCryptoCanonicalUuid) ||
        sourceCount < 0) {
      throw const FormatException('crypto_capture_inventory');
    }
    final sink = Sha256().newHashSink();
    sink.add(utf8.encode('JivieCaptureInventory/v3\n'));
    sink.add(
      CryptoInventoryJson.encode({
        'version': 3,
        'serverId': serverId,
        'captureId': captureId,
        'migrationId': migrationId,
        'accountId': accountId,
        'sourceCount': sourceCount,
      }),
    );
    sink.add([10]);
    String? previous;
    var count = 0;
    await for (final binding in bindings) {
      if (previous != null && previous.compareTo(binding.bindingId) >= 0 ||
          ++count > sourceCount) {
        throw const FormatException('crypto_capture_inventory_order');
      }
      previous = binding.bindingId;
      sink.add(CryptoInventoryJson.encode(binding.toJson()));
      sink.add([10]);
    }
    if (count != sourceCount) {
      throw const FormatException('crypto_capture_inventory_incomplete');
    }
    sink.close();
    return (await sink.hash()).bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  static Future<void> verifyWitness({
    required CryptoCaptureBinding binding,
    required CryptoCaptureSourceContext context,
    required Map<String, dynamic> witness,
  }) async {
    if (witness.length != 4 ||
        witness['version'] != 3 ||
        CryptoInventoryJson.canonical(witness['context']) !=
            CryptoInventoryJson.canonical(context.toJson()) ||
        binding.scopeId != context.scopeId ||
        binding.domain != context.domain ||
        witness['typedRow'] is! Map) {
      throw const FormatException('crypto_capture_witness');
    }
    final saltBytes = cryptoBase64(witness['saltBase64'], length: 32);
    try {
      if (await sourceCommitment(
            context: context,
            salt: saltBytes,
            typedRow: witness['typedRow'] as Object,
          ) !=
          binding.sourceCommitment) {
        throw const FormatException('crypto_capture_source_mismatch');
      }
    } finally {
      saltBytes.fillRange(0, saltBytes.length, 0);
    }
  }

  static Future<String> _hash(List<int> bytes) async => (await Sha256().hash(
    bytes,
  )).bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}
