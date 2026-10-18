import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/e2ee/crypto_migration_business_parity_v3.dart';

void main() {
  late Map<String, dynamic> fixture, header;
  late List<Map<String, dynamic>> frames;
  setUp(() {
    fixture =
        jsonDecode(
              File(
                'server/tests/fixtures/e2ee-business-parity-v3.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    header = Map<String, dynamic>.from(fixture['header'] as Map);
    frames = (fixture['frames'] as List).cast<Map<String, dynamic>>();
  });
  test(
    'canonical artifact binds exact signed source/proof coordinates',
    () async {
      final vector = fixture['canonicalArtifact'] as Map;
      final binding = Map<String, dynamic>.from(vector['sourceBinding'] as Map);
      expect(
        await CryptoMigrationBusinessParityV3.canonicalArtifact(binding),
        vector['hash'],
      );
      for (final entry in {
        'bindingId': '99999999-1111-4111-8111-111111111111',
        'recordProofHash': '9' * 64,
        'scopeId': '99999998-1111-4111-8111-111111111111',
      }.entries) {
        expect(
          await CryptoMigrationBusinessParityV3.canonicalArtifact({
            ...binding,
            entry.key: entry.value,
          }),
          isNot(vector['hash']),
        );
      }
      await expectLater(
        CryptoMigrationBusinessParityV3.canonicalArtifact({
          ...binding,
          'sourceRowHash': '0' * 64,
        }),
        throwsFormatException,
      );
    },
  );
  test(
    'complete blinded source fold and distinct file/proof counts match independent Python fixture',
    () async {
      expect(
        await CryptoMigrationBusinessParityV3.compute(
          header: header,
          frames: Stream.fromIterable(frames),
        ),
        fixture['result'],
      );
    },
  );
  test(
    'omitted/reordered/duplicate source binding cannot preserve complete source root',
    () async {
      for (final bad in [
        frames.skip(1).toList(),
        [frames[1], frames[0], ...frames.skip(2)],
        [frames.first, ...frames],
      ]) {
        await expectLater(
          CryptoMigrationBusinessParityV3.compute(
            header: header,
            frames: Stream.fromIterable(bad),
          ),
          throwsFormatException,
        );
      }
    },
  );
  test(
    'raw hashes and unknown active adapters cannot become public parity frames',
    () async {
      final value = Map<String, dynamic>.from(frames.first['value'] as Map);
      for (final bad in [
        {...value, 'sourceRowHash': '1' * 64},
        {...value, 'adapter': 'unsupportedCurrentSource'},
      ]) {
        await expectLater(
          CryptoMigrationBusinessParityV3.compute(
            header: header,
            frames: Stream.fromIterable([
              {'tag': 'binding', 'value': bad},
              ...frames.skip(1),
            ]),
          ),
          throwsFormatException,
        );
      }
    },
  );
  test(
    'missing required control coverage and foreign account root fail closed',
    () async {
      await expectLater(
        CryptoMigrationBusinessParityV3.compute(
          header: header,
          frames: Stream.fromIterable(frames.take(frames.length - 1)),
        ),
        throwsFormatException,
      );
      await expectLater(
        CryptoMigrationBusinessParityV3.compute(
          header: {
            ...header,
            'accountId': '99999999-1111-4111-8111-111111111111',
          },
          frames: Stream.fromIterable(frames),
        ),
        throwsFormatException,
      );
    },
  );
}
