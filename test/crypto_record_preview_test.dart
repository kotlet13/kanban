import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/presentation/recovery/crypto_record_preview.dart';

String preview(Object value) => cryptoRecoveryPreviewSummary(
  Uint8List.fromList(utf8.encode(jsonEncode(value))),
  deletedLabel: 'Deleted',
  unknownLabel: 'Protected record',
);

void main() {
  test(
    'review renders meaningful encrypted payload without protocol fields',
    () {
      final text = preview({
        'format': 2,
        'identity': {'canonicalId': 'secret-wire'},
        'payload': {
          'title': 'Rent',
          'amountMinor': 4321,
          'currency': 'EUR',
          'date': '2026-10-17',
          'migrationPayload': {'bindingId': 'private-binding'},
        },
      });
      expect(text, 'Rent\n43.21 EUR\n2026-10-17');
      for (final forbidden in [
        'format',
        'identity',
        'secret-wire',
        'bindingId',
        '{',
      ]) {
        expect(text.contains(forbidden), isFalse);
      }
    },
  );
  test(
    'unknown technical payloads, tombstones and invalid bytes use generic label',
    () {
      expect(
        preview({
          'format': 2,
          'identity': {},
          'payload': {'recordProof': {}, 'ciphertextBase64': 'abc'},
        }),
        'Protected record',
      );
      expect(
        cryptoRecoveryPreviewSummary(
          null,
          deletedLabel: 'Deleted',
          unknownLabel: 'Protected record',
        ),
        'Deleted',
      );
      expect(
        cryptoRecoveryPreviewSummary(
          Uint8List.fromList([255]),
          deletedLabel: 'Deleted',
          unknownLabel: 'Protected record',
        ),
        'Protected record',
      );
    },
  );
  test(
    'known text is bounded and invalid financial values are not guessed',
    () {
      expect(preview({'name': 'a' * 1200}).length, 1001);
      expect(
        preview({'amountMinor': '1234', 'currency': 'EUR'}),
        'Protected record',
      );
      expect(
        preview({'amountMinor': 1234, 'currency': 'not-a-currency'}),
        'Protected record',
      );
    },
  );
}
