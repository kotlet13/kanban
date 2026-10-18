import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart' show Sha256;

import 'crypto_capture_v3.dart';
import 'crypto_inventory_json.dart';
import 'crypto_json.dart';
import 'crypto_record_address.dart';

/// Random legacy routing identity, not a request/response plaintext hash.
/// Compound pushTaskWithCost remains ONE records receipt with its original
/// combined response; it is never split into independent financial effects.
class CryptoLegacyReceiptTuple {
  CryptoLegacyReceiptTuple({
    required this.scopeId,
    required this.kind,
    required this.legacyId,
    this.documentDeviceId,
  }) {
    if (!isCryptoCanonicalUuid(scopeId) ||
        !isCryptoCanonicalUuid(legacyId) ||
        !const ['records', 'finance', 'documents'].contains(kind) ||
        (kind == 'documents'
            ? !isCryptoCanonicalUuid(documentDeviceId)
            : documentDeviceId != null)) {
      throw const FormatException('crypto_legacy_receipt_identity');
    }
  }
  final String scopeId, kind, legacyId;
  final String? documentDeviceId;
  String get domain => kind == 'finance' ? 'finance' : 'content';
  String get orderKey =>
      '$scopeId\u0000$kind\u0000$legacyId\u0000${documentDeviceId ?? ''}';
  Map<String, dynamic> toJson() => {
    'scopeId': scopeId,
    'receiptKind': kind,
    'legacyId': legacyId,
    'legacyDeviceId': documentDeviceId,
  };

  factory CryptoLegacyReceiptTuple.fromJson(Map value) {
    try {
      return CryptoLegacyReceiptTuple(
        scopeId: value['scopeId'] as String,
        kind: value['receiptKind'] as String,
        legacyId: value['legacyId'] as String,
        documentDeviceId: value['legacyDeviceId'] as String?,
      );
    } on TypeError {
      throw const FormatException('crypto_legacy_receipt_identity');
    }
  }
}

class CryptoLegacyReceiptDescriptor {
  CryptoLegacyReceiptDescriptor({
    required this.tuple,
    required this.bindingId,
    required this.sourceCommitment,
  }) {
    if (!isCryptoCanonicalUuid(bindingId) ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(sourceCommitment)) {
      throw const FormatException('crypto_legacy_receipt_binding');
    }
  }
  final CryptoLegacyReceiptTuple tuple;
  final String bindingId, sourceCommitment;
  Map<String, dynamic> toJson() => {
    ...tuple.toJson(),
    'bindingId': bindingId,
    'sourceCommitment': sourceCommitment,
  };
  factory CryptoLegacyReceiptDescriptor.fromJson(Map<String, dynamic> value) {
    if (value.length != 6) {
      throw const FormatException('crypto_legacy_receipt_binding');
    }
    try {
      return CryptoLegacyReceiptDescriptor(
        tuple: CryptoLegacyReceiptTuple.fromJson(value),
        bindingId: value['bindingId'] as String,
        sourceCommitment: value['sourceCommitment'] as String,
      );
    } on TypeError {
      throw const FormatException('crypto_legacy_receipt_binding');
    }
  }
}

/// Original byte-level evidence is PRIVATE. It is returned only after the
/// account archive has been decrypted and its typed witness commitment checked.
/// A missing frame, wrong kind, bad tag or malformed response cannot mean absent.
class CryptoCapturedLegacyReceipt {
  CryptoCapturedLegacyReceipt._(
    this.tuple,
    this.requestHash,
    this.responseBytes,
    this.status,
  );
  final CryptoLegacyReceiptTuple tuple;
  final String requestHash;
  final Uint8List responseBytes;
  final int status;
  String get outcome => status == 200 ? 'applied' : 'rejected';
  void requireOriginalRequestHash(String locallyComputedHash) {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(locallyComputedHash) ||
        locallyComputedHash != requestHash) {
      throw const FormatException('crypto_legacy_original_request_mismatch');
    }
  }

  static Future<CryptoCapturedLegacyReceipt> fromWitness({
    required CryptoLegacyReceiptDescriptor descriptor,
    required CryptoCaptureSourceContext context,
    required Map<String, dynamic> witness,
  }) async {
    if (context.domain != 'private' || context.scopeId != null) {
      throw const FormatException('crypto_legacy_receipt_private_context');
    }
    final expectedTable = switch (descriptor.tuple.kind) {
      'records' => 'familyhub_operations',
      'finance' => 'familyhub_finance_operations',
      'documents' => 'familyhub_document_requests',
      _ => throw const FormatException('crypto_legacy_receipt_identity'),
    };
    if (context.sourceTable != expectedTable) {
      throw const FormatException('crypto_legacy_receipt_kind_mismatch');
    }
    await CryptoCaptureV3.verifyWitness(
      binding: CryptoCaptureBinding(
        bindingId: descriptor.bindingId,
        scopeId: null,
        domain: 'private',
        sourceCommitment: descriptor.sourceCommitment,
      ),
      context: context,
      witness: witness,
    );
    final row = witness['typedRow'] as Map;
    Uint8List bytes(String name) {
      final cell = row[name];
      if (cell is! Map ||
          cell.length != 2 ||
          cell['type'] is! String ||
          cell['valueBase64'] == null) {
        throw const FormatException('crypto_legacy_receipt_source');
      }
      return cryptoBase64(cell['valueBase64'], max: 32 * 1024 * 1024);
    }

    String text(String name) => utf8.decode(bytes(name));
    final captured = CryptoLegacyReceiptTuple(
      scopeId: text('scope_id'),
      kind: descriptor.tuple.kind,
      legacyId: text(
        descriptor.tuple.kind == 'documents' ? 'request_id' : 'id',
      ),
      documentDeviceId: descriptor.tuple.kind == 'documents'
          ? text('device_id')
          : null,
    );
    if (captured.orderKey != descriptor.tuple.orderKey ||
        (descriptor.tuple.kind != 'records' &&
            text('account_id') != context.accountId)) {
      throw const FormatException('crypto_legacy_receipt_identity');
    }
    final hash = text('request_hash');
    final statusText = descriptor.tuple.kind == 'documents'
        ? '200'
        : text('status');
    final status = int.tryParse(statusText);
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(hash) ||
        status == null ||
        status < 100 ||
        status > 599 ||
        status.toString() != statusText) {
      throw const FormatException('crypto_legacy_receipt_source');
    }
    return CryptoCapturedLegacyReceipt._(
      captured,
      hash,
      bytes('response'),
      status,
    );
  }
}

/// One streamed public format, with an explicit empty-list root. A caller must
/// separately verify the exact own-account migrationAttest inclusion before
/// using this complete manifest to conclude notApplied. Pagination alone is
/// never an absence proof; ciphertext/archive lookup failures stay unresolved.
class CryptoLegacyReceiptInventory {
  static Map<String, dynamic> header({
    required String serverId,
    required String accountId,
    required String captureId,
    required String migrationId,
    required String domain,
    required String sourceInventoryRoot,
    required String archiveManifestHash,
    required String receiptSelectionHash,
    required int receiptCount,
  }) {
    if (![
          serverId,
          accountId,
          captureId,
          migrationId,
        ].every(isCryptoCanonicalUuid) ||
        !const ['content', 'finance'].contains(domain) ||
        receiptCount < 0 ||
        ![
          sourceInventoryRoot,
          archiveManifestHash,
          receiptSelectionHash,
        ].every((v) => RegExp(r'^[a-f0-9]{64}$').hasMatch(v))) {
      throw const FormatException('crypto_legacy_inventory_context');
    }
    return {
      'captureVersion': 3,
      'serverId': serverId,
      'accountId': accountId,
      'captureId': captureId,
      'migrationId': migrationId,
      'domain': domain,
      'sourceInventoryRoot': sourceInventoryRoot,
      'archiveManifestHash': archiveManifestHash,
      'receiptCount': receiptCount,
      'receiptSelectionHash': receiptSelectionHash,
    };
  }

  static Future<String> root(
    Map<String, dynamic> value,
    Stream<CryptoLegacyReceiptDescriptor> descriptors, {
    Future<bool> Function(String bindingId)? claimBinding,
  }) async {
    if (value.length != 10 || value['captureVersion'] != 3) {
      throw const FormatException('crypto_legacy_inventory_version');
    }
    late Map<String, dynamic> checked;
    try {
      checked = header(
        serverId: value['serverId'],
        accountId: value['accountId'],
        captureId: value['captureId'],
        migrationId: value['migrationId'],
        domain: value['domain'],
        sourceInventoryRoot: value['sourceInventoryRoot'],
        archiveManifestHash: value['archiveManifestHash'],
        receiptCount: value['receiptCount'],
        receiptSelectionHash: value['receiptSelectionHash'],
      );
    } on TypeError {
      throw const FormatException('crypto_legacy_inventory_context');
    }
    final hash = Sha256().newHashSink();
    hash.add(utf8.encode('JivieCaptureLegacyInventory/v3\n'));
    hash.add(CryptoInventoryJson.encode(checked));
    hash.add([10]);
    var count = 0;
    String? previous;
    // Production supplies a UNIQUE-backed SQL claim so memory stays bounded.
    // The pure codec fallback is useful for small standalone golden fixtures.
    final ids = claimBinding == null ? <String>{} : null;
    await for (final descriptor in descriptors) {
      if (descriptor.tuple.domain != value['domain'] ||
          ++count > value['receiptCount'] ||
          previous != null &&
              previous.compareTo(descriptor.tuple.orderKey) >= 0 ||
          !(claimBinding == null
              ? ids!.add(descriptor.bindingId)
              : await claimBinding(descriptor.bindingId))) {
        throw const FormatException('crypto_legacy_inventory_order');
      }
      previous = descriptor.tuple.orderKey;
      hash.add(CryptoInventoryJson.encode(descriptor.toJson()));
      hash.add([10]);
    }
    if (count != value['receiptCount']) {
      throw const FormatException('crypto_legacy_inventory_incomplete');
    }
    hash.close();
    return (await hash.hash()).bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  static Future<String> scopeToken(Map<String, dynamic> header) async =>
      (await Sha256().hash([
        ...utf8.encode('JivieCaptureLegacyScope/v3\n'),
        ...CryptoInventoryJson.encode({
          for (final key in const [
            'captureVersion',
            'serverId',
            'accountId',
            'captureId',
            'migrationId',
            'domain',
          ])
            key: header[key],
        }),
      ])).bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  static Future<String> selectionHash({
    required String serverId,
    required String accountId,
    required String captureId,
    required String migrationId,
    required List<Map<String, dynamic>> receiptSelections,
  }) async {
    if (![
          serverId,
          accountId,
          captureId,
          migrationId,
        ].every(isCryptoCanonicalUuid) ||
        receiptSelections.length > 2000) {
      throw const FormatException('crypto_capture_receipt_selection');
    }
    String? previous;
    for (final selection in receiptSelections) {
      if (selection.length != 2 ||
          !isCryptoCanonicalUuid(selection['scopeId']) ||
          !const ['content', 'finance'].contains(selection['domain'])) {
        throw const FormatException('crypto_capture_receipt_selection');
      }
      final order = '${selection['scopeId']}/${selection['domain']}';
      if (previous != null && previous.compareTo(order) >= 0) {
        throw const FormatException('crypto_capture_receipt_selection');
      }
      previous = order;
    }
    return (await Sha256().hash([
      ...utf8.encode('JivieCaptureReceiptSelection/v3\n'),
      ...CryptoInventoryJson.encode({
        'captureVersion': 3,
        'serverId': serverId,
        'accountId': accountId,
        'captureId': captureId,
        'migrationId': migrationId,
        'receiptSelections': receiptSelections,
      }),
    ])).bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
