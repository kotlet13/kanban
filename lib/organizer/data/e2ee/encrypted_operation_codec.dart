import 'dart:convert';
import 'dart:typed_data';

import 'package:sodium/sodium.dart';

import 'crypto_codec.dart';
import 'crypto_json.dart';

/// A single immutable record representation for the opaque batch transport.
/// Callers persist the returned envelope once and retry those exact bytes.
class EncryptedOperationCodec {
  EncryptedOperationCodec(this.crypto);
  final CryptoCodec crypto;

  Map<String, dynamic> seal({
    required String serverId,
    required String scopeId,
    required String id,
    required String type,
    required int expectedRevision,
    required int epoch,
    required SecureKey key,
    required Map<String, dynamic> payload,
    required Map<String, dynamic> metadata,
  }) {
    if (expectedRevision < 0 || epoch < 1) {
      throw const FormatException('crypto_record_revision');
    }
    final context = _context(
      serverId,
      scopeId,
      id,
      type,
      expectedRevision + 1,
      epoch,
      metadata,
    );
    final plaintext = Uint8List.fromList(utf8.encode(jsonEncode(payload)));
    try {
      return {
        'scopeId': scopeId,
        'id': id,
        'type': type,
        'expectedRevision': expectedRevision,
        'deleted': false,
        'epoch': epoch,
        'metadata': metadata,
        'envelopeBase64': base64Encode(
          CryptoJson.encode(
            crypto.encrypt(plaintext: plaintext, key: key, context: context),
          ),
        ),
      };
    } finally {
      plaintext.fillRange(0, plaintext.length, 0);
    }
  }

  Map<String, dynamic> open({
    required String serverId,
    required Map<String, dynamic> wire,
    required SecureKey key,
    required Uint8List independentlyTrustedSigningKey,
  }) {
    final command = crypto.verify(
      wire['authorization'] as Map<String, dynamic>,
      independentlyTrustedSigningKey,
    );
    if (command['version'] != 1 ||
        command['operation'] != 'crypto.records.batch' ||
        command['serverId'] != serverId ||
        command['signer'] != 'device') {
      throw const FormatException('crypto_record_authorization');
    }
    final expected = {
      'scopeId': wire['scopeId'],
      'id': wire['id'],
      'type': wire['type'],
      'expectedRevision': (wire['revision'] as int) - 1,
      'deleted': wire['deleted'],
      'epoch': wire['epoch'],
      'metadata': wire['metadata'],
      'envelopeBase64': wire['envelopeBase64'],
    };
    final records = (command['payload'] as Map)['records'] as List;
    if (!records.any(
      (r) =>
          utf8.decode(CryptoJson.encode(r)) ==
          utf8.decode(CryptoJson.encode(expected)),
    )) {
      throw const FormatException('crypto_record_substitution');
    }
    if (wire['deleted'] != false || wire['envelopeBase64'] is! String) {
      throw const FormatException('crypto_record_deleted');
    }
    final plaintext = crypto.decrypt(
      envelope:
          CryptoJson.decode(cryptoBase64(wire['envelopeBase64']))
              as Map<String, dynamic>,
      key: key,
      context: _context(
        serverId,
        wire['scopeId'] as String,
        wire['id'] as String,
        wire['type'] as String,
        wire['revision'] as int,
        wire['epoch'] as int,
        wire['metadata'] as Map<String, dynamic>,
      ),
    );
    try {
      final payload = jsonDecode(utf8.decode(plaintext, allowMalformed: false));
      if (payload is! Map<String, dynamic>) {
        throw const FormatException('crypto_record_payload');
      }
      return payload;
    } finally {
      plaintext.fillRange(0, plaintext.length, 0);
    }
  }

  Map<String, dynamic> _context(
    String serverId,
    String scopeId,
    String id,
    String type,
    int revision,
    int epoch,
    Map<String, dynamic> metadata,
  ) => {
    'version': 1,
    'purpose': 'contentRecord',
    'serverId': serverId,
    'scopeId': scopeId,
    'recordId': id,
    'type': type,
    'revision': revision,
    'epoch': epoch,
    'metadata': metadata,
  };
}
