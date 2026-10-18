import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/e2ee/crypto_business_addresses.dart';
import 'package:kanban/organizer/data/e2ee/crypto_record_address.dart';
import 'package:kanban/organizer/data/e2ee/crypto_sync_repository.dart';

void main() {
  test(
    'wire golden preserves independent same-ID legacy namespaces and typed lookup',
    () async {
      const server = '11111111-1111-4111-8111-111111111111';
      const scope = '22222222-2222-4222-8222-222222222222';
      const canonical = '33333333-3333-4333-8333-333333333333';
      final addresses = [
        for (final type in [
          'task',
          'table',
          'attachment',
          'financeAccount',
          'paymentEvent',
          'paymentProjection',
          'cashMovement',
          'scopeMetadata',
          'taskDerivationIntent',
          'taskDerivationResolution',
        ])
          CryptoRecordAddress.forType(
            serverId: server,
            scopeId: scope,
            type: type,
            canonicalId: canonical,
          ),
      ];
      expect(addresses.first.wireId, '48e295e5-89b4-8825-beb2-20ef53b9face');
      expect(
        addresses.map((a) => a.wireId).toSet(),
        hasLength(addresses.length),
      );
      expect(addresses.every((a) => isCryptoWireRecordId(a.wireId)), isTrue);
      expect(isCryptoWireRecordId(canonical), isFalse);
      for (final bad in [
        addresses.first.wireId,
        '33333333-3333-0333-8333-333333333333',
        '33333333-3333-4333-0333-333333333333',
      ]) {
        expect(isCryptoCanonicalUuid(bad), isFalse);
        expect(
          () => CryptoRecordAddress.forType(
            serverId: server,
            scopeId: scope,
            type: 'task',
            canonicalId: bad,
          ),
          throwsFormatException,
        );
      }
      final db = CollaborationDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final store = CryptoBusinessAddresses(db, 'synthetic', server);
      for (final address in addresses) {
        await store.install(address);
        await store.install(address);
        expect(
          await store.existingWireId(
            scope,
            address.domain,
            canonical,
            type: address.type,
          ),
          address.wireId,
        );
        expect(
          cryptoRecordAddressFromMetadata({
            'serverId': server,
            'scopeId': scope,
            'domain': address.domain,
            'type': address.type,
            'id': address.wireId,
            'metadata': {'identity': address.identity},
          }).canonicalId,
          canonical,
        );
      }
      await expectLater(
        store.existingWireId(scope, 'content', canonical),
        throwsA(isA<CryptoAuthorityPending>()),
      );
      expect(
        await db.rows('SELECT * FROM crypto_business_addresses'),
        hasLength(addresses.length),
      );
      final otherScope = '44444444-4444-4444-8444-444444444444';
      final forced = CryptoRecordAddress.forType(
        serverId: server,
        scopeId: otherScope,
        type: 'table',
        canonicalId: canonical,
      );
      await db.execute(
        'INSERT INTO crypto_business_addresses VALUES(?,?,?,?,?,?,?)',
        [
          'synthetic',
          otherScope,
          'content',
          'records',
          scope,
          forced.wireId,
          'task',
        ],
      );
      await expectLater(store.install(forced), throwsFormatException);
      expect(
        (await db.rows(
          'SELECT type FROM crypto_business_addresses WHERE partition=? AND scope_id=? AND wire_id=?',
          ['synthetic', otherScope, forced.wireId],
        )).single['type'],
        'task',
      );
      expect(
        () => cryptoRecordAddressFromMetadata({
          'serverId': server,
          'scopeId': scope,
          'domain': 'content',
          'type': 'table',
          'id': addresses.first.wireId,
          'metadata': {
            'identity': {'sourceKind': 'tables', 'canonicalId': canonical},
          },
        }),
        throwsFormatException,
      );
    },
  );
}
