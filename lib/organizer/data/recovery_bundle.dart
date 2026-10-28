import 'dart:convert';
import 'dart:typed_data';

import 'e2ee/crypto_json.dart';

/// One bearer file for installation unlock and the independently generated
/// account recovery material. The nested formats retain their own validation.
abstract final class RecoveryBundleCodec {
  static const maxBytes = 64 * 1024;
  static const _format = 'jivie-recovery';

  static Map<String, dynamic> _decode(Uint8List bytes) {
    if (bytes.isEmpty || bytes.length > maxBytes) {
      throw const FormatException('recovery_bundle_size');
    }
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('recovery_bundle_format');
    }
    return decoded;
  }

  static bool _installation(Object? value) =>
      value is Map<String, dynamic> &&
      value.length == 4 &&
      value['format'] == 'jivie-installation-recovery' &&
      value['version'] == 1 &&
      value['vaultId'] is String &&
      value['key'] is String;

  static bool _account(Object? value) =>
      value is Map<String, dynamic> &&
      value.length == 10 &&
      value['scope'] == 'account' &&
      const [1, 2].contains(value['version']) &&
      const {
        'accountId',
        'encryptionPublicKeyBase64',
        'fingerprint',
        'recoveryId',
        'scope',
        'secretBase64',
        'serverId',
        'signingPublicKeyBase64',
        'suite',
        'version',
      }.every(value.containsKey);

  static Uint8List wrap(Uint8List installation, Uint8List account) {
    final local = _decode(installation);
    final remote = CryptoJson.decode(account, limit: maxBytes);
    if (!_installation(local) || !_account(remote)) {
      throw const FormatException('recovery_bundle_format');
    }
    final bytes = Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'format': _format,
          'version': 1,
          'installation': local,
          'account': remote,
        }),
      ),
    );
    if (bytes.length > maxBytes) {
      bytes.fillRange(0, bytes.length, 0);
      throw const FormatException('recovery_bundle_size');
    }
    return bytes;
  }

  static Uint8List _extract(Uint8List bytes, String field) {
    final decoded = _decode(bytes);
    if (decoded['format'] != _format) return Uint8List.fromList(bytes);
    // The account protocol rejects parser differentials. Validate the original
    // envelope before extracting, so duplicate or escaped aliases cannot be
    // normalized into an apparently valid account section.
    if (jsonEncode(decoded) != utf8.decode(bytes)) {
      throw const FormatException('recovery_bundle_noncanonical');
    }
    if (decoded.length != 4 ||
        decoded['version'] != 1 ||
        !_installation(decoded['installation']) ||
        !_account(decoded['account'])) {
      throw const FormatException('recovery_bundle_format');
    }
    final account = Uint8List.fromList(
      utf8.encode(jsonEncode(decoded['account'])),
    );
    try {
      // Preserve the original account key order when checking the canonical
      // protocol. Reordering must fail rather than be repaired by extraction.
      CryptoJson.decode(account, limit: maxBytes);
      return field == 'account'
          ? Uint8List.fromList(account)
          : Uint8List.fromList(utf8.encode(jsonEncode(decoded[field])));
    } finally {
      account.fillRange(0, account.length, 0);
    }
  }

  static Uint8List installationBytes(Uint8List bytes) =>
      _extract(bytes, 'installation');
  static Uint8List accountBytes(Uint8List bytes) => _extract(bytes, 'account');
}
