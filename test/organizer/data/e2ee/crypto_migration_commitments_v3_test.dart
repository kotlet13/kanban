import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/e2ee/crypto_migration_commitments_v3.dart';

void main() {
  late Map<String, dynamic> fixture, header;
  setUp(() {
    fixture = jsonDecode(
      File(
        'server/tests/fixtures/e2ee-migration-commitments-v3.json',
      ).readAsStringSync(),
    );
    header = Map<String, dynamic>.from(fixture['header']);
  });
  test(
    'independent Python/PHP complete opaque streams and empty root match',
    () async {
      final inventory = fixture['inventoryHeader'] as Map;
      expect(
        await CryptoMigrationCommitmentsV3.inventoryCommitment(
          serverId: inventory['serverId'],
          migrationId: inventory['migrationId'],
          componentId: inventory['componentId'],
          portionCount: 2,
          portions: Stream.fromIterable(
            (fixture['portions'] as List).cast<Map<String, dynamic>>(),
          ),
        ),
        fixture['inventoryCommitment'],
      );
      final hashes = <String>[];
      for (final leaf
          in (fixture['leaves'] as List).cast<Map<String, dynamic>>()) {
        hashes.add(await CryptoMigrationCommitmentsV3.leafHash(header, leaf));
      }
      hashes.sort();
      expect(hashes, fixture['leafHashes']);
      expect(
        await CryptoMigrationCommitmentsV3.domainRoot(
          header,
          Stream.fromIterable(hashes),
        ),
        fixture['root'],
      );
      expect(
        await CryptoMigrationCommitmentsV3.domainRoot({
          ...header,
          'sourceRowCount': 0,
          'materializedRecordProofCount': 0,
        }, const Stream.empty()),
        fixture['emptyRoot'],
      );
    },
  );
  test(
    'independent opaque contribution context, required empty and full coverage',
    () async {
      final ch = Map<String, dynamic>.from(
        fixture['contributionHeader'] as Map,
      );
      final hashes = (fixture['leafHashes'] as List).cast<String>();
      expect(
        await CryptoMigrationCommitmentsV3.headerHash(header),
        fixture['headerHash'],
      );
      expect(
        await CryptoMigrationCommitmentsV3.contributionRoot(
          ch,
          Stream.fromIterable(hashes),
        ),
        fixture['contributionRoot'],
      );
      expect(
        await CryptoMigrationCommitmentsV3.contributionRoot({
          ...ch,
          'sourceRowCount': 0,
          'leafCount': 0,
        }, const Stream.empty()),
        fixture['emptyContributionRoot'],
      );
      for (final list in [
        hashes.reversed.toList(),
        [hashes.first, hashes.first],
        [hashes.first],
      ]) {
        await expectLater(
          CryptoMigrationCommitmentsV3.contributionRoot(
            ch,
            Stream.fromIterable(list),
          ),
          throwsFormatException,
        );
      }
      for (final field in [
        'serverId',
        'migrationId',
        'captureId',
        'scopeToken',
        'headerHash',
        'sourceInventoryRoot',
        'coldParityProofHash',
        'portionToken',
      ]) {
        final changed = {
          ...ch,
          field: field.endsWith('Id')
              ? '99999999-1111-4111-8111-111111111111'
              : '9' * 64,
        };
        expect(
          await CryptoMigrationCommitmentsV3.contributionRoot(
            changed,
            Stream.fromIterable(hashes),
          ),
          isNot(fixture['contributionRoot']),
        );
      }
    },
  );
  test(
    'component commitment derives exact server/migration/component/inventory context',
    () async {
      expect(
        await CryptoMigrationCommitmentsV3.componentCommitment(
          serverId: header['serverId'],
          migrationId: header['migrationId'],
          componentId: header['componentId'],
          inventoryCommitment: header['inventoryCommitment'],
        ),
        header['componentCommitment'],
      );
      for (final field in [
        'serverId',
        'migrationId',
        'componentId',
        'inventoryCommitment',
        'componentCommitment',
      ]) {
        await expectLater(
          CryptoMigrationCommitmentsV3.validateHeader({
            ...header,
            field: field.endsWith('Commitment')
                ? '0' * 64
                : '99999999-1111-4111-8111-111111111111',
          }),
          throwsFormatException,
        );
      }
    },
  );
  test(
    'duplicate/reordered/omitted/foreign leaves and raw-hash ancestry reject',
    () async {
      final hashes = (fixture['leafHashes'] as List).cast<String>();
      for (final bad in [
        hashes.reversed.toList(),
        [hashes.first, hashes.first],
        [hashes.first],
      ]) {
        await expectLater(
          CryptoMigrationCommitmentsV3.domainRoot(
            header,
            Stream.fromIterable(bad),
          ),
          throwsFormatException,
        );
      }
      final leaf = Map<String, dynamic>.from((fixture['leaves'] as List).first);
      await expectLater(
        CryptoMigrationCommitmentsV3.leafHash(header, {
          ...leaf,
          'domain': 'finance',
        }),
        throwsFormatException,
      );
      await expectLater(
        CryptoMigrationCommitmentsV3.leafHash(header, {
          ...leaf,
          'sourceRowHash': 'a' * 64,
        }),
        throwsFormatException,
      );
      await expectLater(
        CryptoMigrationCommitmentsV3.validateHeader({...header, 'version': 2}),
        throwsFormatException,
      );
      final portions = (fixture['portions'] as List)
          .cast<Map<String, dynamic>>();
      final inventory = fixture['inventoryHeader'] as Map;
      await expectLater(
        CryptoMigrationCommitmentsV3.inventoryCommitment(
          serverId: inventory['serverId'],
          migrationId: inventory['migrationId'],
          componentId: inventory['componentId'],
          portionCount: 2,
          portions: Stream.fromIterable([portions.first, portions.first]),
        ),
        throwsFormatException,
      );
      final swapped = [
        {
          ...portions[0],
          'sourceInventoryRoot': portions[1]['sourceInventoryRoot'],
        },
        {
          ...portions[1],
          'sourceInventoryRoot': portions[0]['sourceInventoryRoot'],
        },
      ];
      expect(
        await CryptoMigrationCommitmentsV3.inventoryCommitment(
          serverId: inventory['serverId'],
          migrationId: inventory['migrationId'],
          componentId: inventory['componentId'],
          portionCount: 2,
          portions: Stream.fromIterable(swapped),
        ),
        isNot(fixture['inventoryCommitment']),
      );
    },
  );
}
