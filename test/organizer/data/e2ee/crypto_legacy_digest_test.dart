import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/e2ee/crypto_legacy_digest.dart';

void main() {
  test(
    '44 actual NativeDatabase hashRequest golden vectors match historical wire namespaces',
    () async {
      final fixture =
          jsonDecode(
                await File(
                  'server/tests/fixtures/e2ee-legacy-request-hashes.json',
                ).readAsString(),
              )
              as Map;
      for (final value in fixture['vectors'] as List) {
        final row = value as Map;
        final params =
            jsonDecode(row['inputJson'] as String) as Map<String, dynamic>;
        expect(
          await CryptoLegacyDigest.hash(row['operation'] as String, params),
          row['sha256'],
          reason: row['name'] as String,
        );
      }
    },
  );
  test(
    'exact historical PHP canonical vectors preserve doubles, separators, empty arrays and unknown fields',
    () async {
      final vectors =
          jsonDecode(
                await File(
                  'test/organizer/data/e2ee/legacy_digest_php_vectors.json',
                ).readAsString(),
              )
              as List;
      for (final row in vectors) {
        expect(
          CryptoLegacyDigest.canonical(jsonDecode(row['source'] as String)),
          row['canonical'],
          reason: jsonEncode(row),
        );
      }
    },
  );
  test(
    'unsupported numeric map keys fail unresolved rather than guess or modify original',
    () {
      for (final key in [
        '00',
        '1e2',
        '20.5',
        '10e1',
        '2e1',
        ' 3 ',
        '+4',
        '.5',
      ]) {
        final original = {
          key: 'unknown historical field',
          'title': 'preserved',
        };
        expect(
          () => CryptoLegacyDigest.canonical(original),
          throwsFormatException,
        );
        expect(original, {
          key: 'unknown historical field',
          'title': 'preserved',
        });
      }
    },
  );
}
