import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/e2ee/crypto_migration_provenance.dart';

void main() {
  test(
    'streamed migration commitment matches independent Python/PHP vectors and rejects omissions or context substitution',
    () async {
      final fixture =
          jsonDecode(
                await File(
                  'server/tests/fixtures/e2ee-migration-provenance-v2.json',
                ).readAsString(),
              )
              as Map;
      final header = Map<String, dynamic>.from(fixture['header'] as Map);
      final leaf = Map<String, dynamic>.from(fixture['leaf'] as Map);
      final hash = await CryptoMigrationProvenance.leafHash(header, leaf);
      expect(
        await CryptoMigrationProvenance.portionToken(
          serverId: header['serverId'],
          migrationId: header['migrationId'],
          accountId: leaf['contributorAccountId'],
        ),
        fixture['portionToken'],
      );
      expect(
        await CryptoMigrationProvenance.inventoryHash(
          serverId: header['serverId'],
          migrationId: header['migrationId'],
          componentHash: header['componentHash'],
          portions: Stream.fromIterable(
            (fixture['portions'] as List).cast<Map<String, dynamic>>(),
          ),
        ),
        fixture['inventoryHash'],
      );
      expect(
        await CryptoMigrationProvenance.inventoryHash(
          serverId: header['serverId'],
          migrationId: header['migrationId'],
          componentHash: header['componentHash'],
          portions: Stream.value({
            'portionToken': '0' * 64,
            'inventoryHash': '2' * 64,
          }),
        ),
        isNot(fixture['inventoryHash']),
      );
      expect(hash, fixture['leafHash']);
      expect(
        await CryptoMigrationProvenance.root(header, Stream.value(hash)),
        fixture['root'],
      );
      expect(
        await CryptoMigrationProvenance.root(
          Map<String, dynamic>.from(fixture['emptyHeader'] as Map),
          const Stream.empty(),
        ),
        fixture['emptyRoot'],
      );
      await expectLater(
        CryptoMigrationProvenance.root(header, const Stream.empty()),
        throwsFormatException,
      );
      final two = {...header, 'materializedRecordProofCount': 2};
      await expectLater(
        CryptoMigrationProvenance.root(two, Stream.fromIterable([hash, hash])),
        throwsFormatException,
      );
      final sorted = [hash, 'f' * 64]..sort();
      await expectLater(
        CryptoMigrationProvenance.root(
          two,
          Stream.fromIterable(sorted.reversed),
        ),
        throwsFormatException,
      );
      await expectLater(
        CryptoMigrationProvenance.leafHash(header, {
          ...leaf,
          'migrationId': '88888888-8888-4888-8888-888888888888',
        }),
        throwsFormatException,
      );
      await expectLater(
        CryptoMigrationProvenance.root({
          ...header,
          'domain': 'finance',
        }, Stream.value(hash)),
        throwsFormatException,
      );
    },
  );
}
