import 'dart:convert';
import 'dart:typed_data';

/// Restricted canonical JSON used by the signed PHP/Dart protocol. No doubles,
/// non-ASCII object keys, invalid Unicode, or JavaScript-unsafe integers.
class CryptoJson {
  static const maxBytes = 512 * 1024;

  static Uint8List encode(Object? value, {int limit = maxBytes}) {
    final encoded = Uint8List.fromList(utf8.encode(_encode(value, 0)));
    if (encoded.length > limit) throw const FormatException('crypto_size');
    return encoded;
  }

  /// Canonicalizes already validated, locally derived state, whose complete
  /// history may exceed one wire command. Never use this for incoming commands.
  static Uint8List encodeDerivedState(Object? value) =>
      Uint8List.fromList(utf8.encode(_encode(value, 0)));

  static Object? decode(Uint8List bytes, {int limit = maxBytes}) {
    if (bytes.isEmpty || bytes.length > limit) {
      throw const FormatException('crypto_size');
    }
    final text = utf8.decode(bytes, allowMalformed: false);
    final value = jsonDecode(text);
    final canonical = _encode(value, 0);
    // This also rejects duplicate keys, alternative numeric spellings, escaped
    // aliases, trailing whitespace and parser differentials before verification.
    if (canonical != text) throw const FormatException('crypto_noncanonical');
    return value;
  }

  static String _encode(Object? value, int depth) {
    if (depth > 32) throw const FormatException('crypto_depth');
    if (value == null || value is bool) return jsonEncode(value);
    if (value is int && value.abs() <= 9007199254740991) return '$value';
    if (value is String) {
      for (var i = 0; i < value.length; i++) {
        final c = value.codeUnitAt(i);
        if (c >= 0xd800 && c <= 0xdbff) {
          if (++i >= value.length) {
            throw const FormatException('crypto_unicode');
          }
          final next = value.codeUnitAt(i);
          if (next < 0xdc00 || next > 0xdfff) {
            throw const FormatException('crypto_unicode');
          }
        } else if (c >= 0xdc00 && c <= 0xdfff) {
          throw const FormatException('crypto_unicode');
        }
      }
      return jsonEncode(value);
    }
    if (value is List) {
      return '[${value.map((e) => _encode(e, depth + 1)).join(',')}]';
    }
    if (value is Map) {
      if (value.keys.any((key) => key is! String)) {
        throw const FormatException('crypto_key');
      }
      final keys = value.keys.cast<String>().toList()..sort();
      if (keys.any(
        (key) =>
            key.length > 80 ||
            !RegExp(r'^[A-Za-z][A-Za-z0-9_]*$').hasMatch(key),
      )) {
        throw const FormatException('crypto_key');
      }
      return '{${keys.map((k) => '${jsonEncode(k)}:${_encode(value[k], depth + 1)}').join(',')}}';
    }
    throw const FormatException('crypto_type');
  }
}

Uint8List cryptoBase64(Object? value, {int? length, int max = 512 * 1024}) {
  if (value is! String || value.length > ((max + 2) ~/ 3) * 4) {
    throw const FormatException('crypto_base64');
  }
  final bytes = base64Decode(value);
  if (base64Encode(bytes) != value ||
      bytes.length > max ||
      (length != null && bytes.length != length)) {
    throw const FormatException('crypto_base64');
  }
  return bytes;
}
