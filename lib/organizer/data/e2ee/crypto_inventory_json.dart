import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart' show Sha256;

/// General sorted JSON for typed legacy inventories. This is not the signed
/// command codec: UUID/table:domain keys and empty objects retain their shape.
class CryptoInventoryJson {
  static String canonical(Object? value) {
    if (value == null || value is bool || value is int)
      return jsonEncode(value);
    if (value is String)
      return jsonEncode(
        value,
      ).replaceAll('\u2028', r'\u2028').replaceAll('\u2029', r'\u2029');
    if (value is List) return '[${value.map(canonical).join(',')}]';
    if (value is Map) {
      if (value.keys.any((k) => k is! String))
        throw const FormatException('crypto_inventory_key');
      final keys = value.keys.cast<String>().toList()
        ..sort((a, b) {
          final left = utf8.encode(a), right = utf8.encode(b);
          for (var i = 0; i < left.length && i < right.length; i++) {
            final order = left[i].compareTo(right[i]);
            if (order != 0) return order;
          }
          return left.length.compareTo(right.length);
        });
      return '{${keys.map((k) => '${canonical(k)}:${canonical(value[k])}').join(',')}}';
    }
    throw const FormatException('crypto_inventory_type');
  }

  static Uint8List encode(Object? value) =>
      Uint8List.fromList(utf8.encode(canonical(value)));
  static Future<String> hash(Object? value) async => (await Sha256().hash(
    encode(value),
  )).bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}
