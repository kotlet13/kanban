import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/e2ee/crypto_business_json.dart';
import 'package:kanban/organizer/data/e2ee/crypto_inventory_json.dart';

void main() {
  test(
    'business JSON retains fractional garden, idea and table values',
    () async {
      final raw = {
        'garden': {
          'bounds': {'x': -0.0, 'y': 0.1},
          'widthMeters': 2.75,
          'future': {'growth': 1e20},
        },
        'idea': {
          'nodes': [
            {'id': 'stable', 'x': 0.1, 'rotation': -0.125, 'zoom': 1.25},
          ],
        },
        'table': {
          'cells': {'A1': 0.1, 'B1': 1e20, 'C1': -0.0},
        },
      };
      final encoded = CryptoBusinessJson.encode(raw);
      final decoded = jsonDecode(utf8.decode(encoded)) as Map;
      expect(decoded, raw);
      expect(
        (ByteData(8)..setFloat64(0, decoded['garden']['bounds']['x'] as double))
            .getUint64(0),
        0x8000000000000000,
      );
      expect(CryptoBusinessJson.encode(decoded), encoded);
      expect(
        await CryptoBusinessJson.hash(decoded),
        await CryptoBusinessJson.hash(raw),
      );
      expect(() => CryptoInventoryJson.encode(raw), throwsFormatException);
    },
  );

  test(
    'nonfractional immutable hashes remain compatible; invalid numbers fail',
    () {
      final raw = {
        '\u{10000}': [1, true, null, 'Č\u2028'],
        '\uE000': {'z': 2},
      };
      expect(
        CryptoBusinessJson.canonical(raw),
        CryptoInventoryJson.canonical(raw),
      );
      for (final number in [
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ]) {
        expect(
          () => CryptoBusinessJson.encode({
            'nested': [number],
          }),
          throwsFormatException,
        );
      }
    },
  );
}
