import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart' show Sha256;

/// Stable JSON for encrypted business values and local immutable intent hashes.
/// Unlike signed protocol/inventory codecs, valid payloads contain fractional
/// coordinates, dimensions and numeric cells. No value is rounded or coerced.
abstract final class CryptoBusinessJson {
  static String canonical(Object? value) {
    if (value == null || value is bool || value is int) {
      return jsonEncode(value);
    }
    if (value is String) {
      return jsonEncode(
        value,
      ).replaceAll('\u2028', r'\u2028').replaceAll('\u2029', r'\u2029');
    }
    if (value is double) {
      if (!value.isFinite) {
        throw const FormatException('crypto_business_number');
      }
      return jsonEncode(value);
    }
    if (value is List) return '[${value.map(canonical).join(',')}]';
    if (value is Map) {
      if (value.keys.any((key) => key is! String)) {
        throw const FormatException('crypto_business_key');
      }
      final keys = value.keys.cast<String>().toList()
        ..sort((a, b) {
          final left = utf8.encode(a), right = utf8.encode(b);
          for (var i = 0; i < left.length && i < right.length; i++) {
            final comparison = left[i].compareTo(right[i]);
            if (comparison != 0) return comparison;
          }
          return left.length.compareTo(right.length);
        });
      return '{${keys.map((key) => '${canonical(key)}:${canonical(value[key])}').join(',')}}';
    }
    throw const FormatException('crypto_business_type');
  }

  static Uint8List encode(Object? value) =>
      Uint8List.fromList(utf8.encode(canonical(value)));
  static Future<String> hash(Object? value) async => (await Sha256().hash(
    encode(value),
  )).bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}
