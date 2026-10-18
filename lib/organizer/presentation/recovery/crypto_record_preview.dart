import 'dart:convert';
import 'dart:typed_data';

/// Human review of decrypted content. Protocol envelopes, identities, cipher
/// descriptors and unknown technical fields are never rendered as a JSON dump.
String cryptoRecoveryPreviewSummary(
  Uint8List? plaintext, {
  required String deletedLabel,
  required String unknownLabel,
}) {
  if (plaintext == null) return deletedLabel;
  try {
    final decoded = jsonDecode(utf8.decode(plaintext));
    final value = decoded is Map && decoded['payload'] is Map
        ? decoded['payload'] as Map
        : decoded;
    if (value is! Map) return unknownLabel;
    final parts = <String>[];
    for (final field in const ['title', 'name', 'description', 'notes']) {
      final text = value[field];
      if (text is String && text.trim().isNotEmpty) {
        final bounded = String.fromCharCodes(text.runes.take(1000));
        parts.add(text.runes.length > 1000 ? '$bounded…' : bounded);
      }
    }
    final amount = value['amountMinor'], currency = value['currency'];
    if (amount is int &&
        amount.abs() <= 9007199254740991 &&
        currency is String &&
        RegExp(r'^[A-Z]{3}$').hasMatch(currency)) {
      final absolute = amount.abs();
      parts.add(
        '${amount < 0 ? '-' : ''}${absolute ~/ 100}.${(absolute % 100).toString().padLeft(2, '0')} $currency',
      );
    }
    final dates = <String>{};
    for (final field in const [
      'date',
      'dueOn',
      'dueAt',
      'startsAt',
      'paidAt',
    ]) {
      final date = value[field];
      if (date is String &&
          date.length <= 35 &&
          RegExp(r'^\d{4}-\d{2}-\d{2}(T.*)?$').hasMatch(date) &&
          DateTime.tryParse(date) != null) {
        dates.add(date);
      }
    }
    parts.addAll(dates);
    return parts.isEmpty ? unknownLabel : parts.join('\n');
  } catch (_) {
    return unknownLabel;
  }
}
