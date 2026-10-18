import 'dart:convert';

import 'package:cryptography/cryptography.dart' show Sha256;

/// Compatibility with NativeDatabase::hashRequest's historical PHP canonical
/// JSON. This is deliberately separate from the restricted crypto2 codec.
/// It never rewrites the immutable original body or sends its plaintext.
class CryptoLegacyDigest {
  static Future<String> hash(
    String operation,
    Map<String, dynamic> params,
  ) async => (await Sha256().hash(
    utf8.encode(canonical({'op': operation, 'params': params})),
  )).bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  static String canonical(Object? value) => _canonical(value, nested: false);

  static String _canonical(Object? value, {required bool nested}) {
    if (value == null || value is bool || value is int) {
      return jsonEncode(value);
    }
    if (value is double) {
      if (!value.isFinite) {
        throw const FormatException('legacy_nonfinite_number');
      }
      if (value == 0) return value.isNegative && !nested ? '-0' : '0';
      final scientific = value.abs() < 0.0001 || value.abs() >= 1e17;
      var text = scientific ? value.toStringAsExponential() : value.toString();
      if (scientific) {
        final parts = text.split('e');
        var mantissa = parts[0];
        if (!mantissa.contains('.')) mantissa += '.0';
        final exponent = int.parse(parts[1]);
        text =
            '$mantissa'
            'e${exponent >= 0 ? '+' : ''}$exponent';
      } else if (text.endsWith('.0')) {
        text = text.substring(0, text.length - 2);
      }
      return text;
    }
    if (value is String) {
      // PHP's UNESCAPED_UNICODE still escapes these JavaScript separators.
      return jsonEncode(
        value,
      ).replaceAll('\u2028', r'\u2028').replaceAll('\u2029', r'\u2029');
    }
    if (value is List) {
      return '[${value.map((item) => _canonical(item, nested: true)).join(',')}]';
    }
    if (value is Map) {
      if (value.isEmpty) return '[]'; // PHP json_decode(..., associative:true)
      if (value.keys.any(
        (k) =>
            k is! String ||
            RegExp(
              r'^\s*[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?\s*$',
            ).hasMatch(k),
      )) {
        // PHP mixed numeric-key array casting/sorting has additional rules.
        // Do not guess an idempotence hash for unsupported historical shapes.
        throw const FormatException(
          'legacy_numeric_map_requires_reconciliation',
        );
      }
      final keys = value.keys.cast<String>().toList()
        ..sort((a, b) {
          final left = utf8.encode(a), right = utf8.encode(b);
          for (var i = 0; i < left.length && i < right.length; i++) {
            final order = left[i].compareTo(right[i]);
            if (order != 0) return order;
          }
          return left.length.compareTo(right.length);
        });
      return '{${keys.map((key) => '${canonical(key)}:${_canonical(value[key], nested: true)}').join(',')}}';
    }
    throw const FormatException('legacy_unknown_value');
  }
}
