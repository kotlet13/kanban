import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/e2ee/crypto_migration_record_source.dart';
import 'package:kanban/organizer/data/e2ee/crypto_record_address.dart';
import 'package:kanban/organizer/data/e2ee/crypto_business_json.dart';

void main() {
  test(
    'typed source preserves revision50, nested future fields and tombstones across independent same-ID namespaces',
    () async {
      const server = '11111111-1111-4111-8111-111111111111',
          scope = '22222222-2222-4222-8222-222222222222',
          id = '33333333-3333-4333-8333-333333333333';
      Map<String, Object?> cell(String? value, {String type = 'text'}) => {
        'type': type,
        'valueBase64': value == null ? null : base64Encode(utf8.encode(value)),
      };
      final payload = {
        'title': 'Captured',
        'phases': [
          {
            'id': id,
            'title': 'Phase',
            'unknownNested': {
              'exact': ['Čebelica', true, null, 1, -0.0, 0.1, 1e20],
            },
          },
        ],
      };
      final row = <String, dynamic>{
        'id': cell(id),
        'scope_id': cell(scope),
        'type': cell('task'),
        'revision': cell('50', type: 'integer'),
        'deleted': cell('0', type: 'integer'),
        'payload': cell(jsonEncode(payload)),
        'futureSqlColumn': cell('preserve exactly'),
      };
      Future<CryptoMigrationRecordSource> read(
        Map<String, dynamic> row, {
        String table = 'familyhub_records',
        String domain = 'content',
      }) => CryptoMigrationRecordSource.decode(
        table: table,
        domain: domain,
        row: row,
        reservedId: (_, _) async => id,
      );
      final source = await read(row);
      expect(source.legacyRevision, 50);
      expect(source.canonicalId, id);
      expect(source.rawPayload, payload);
      expect(source.typedRow, row);
      final changed = await read({...row, 'futureSqlColumn': cell('changed')});
      expect(changed.rowHash, isNot(source.rowHash));
      final tombstone = await read({
        ...row,
        'deleted': cell('1', type: 'integer'),
      });
      expect(tombstone.deleted, isTrue);
      expect(tombstone.rawPayload, isNull);
      expect(tombstone.typedRow['payload'], row['payload']);
      final finance = await read(
        {...row, 'type': cell('financeEntry')},
        table: 'familyhub_finance_records',
        domain: 'finance',
      );
      final taskAddress = CryptoRecordAddress.forType(
        serverId: server,
        scopeId: scope,
        type: 'task',
        canonicalId: id,
      );
      final moneyAddress = CryptoRecordAddress.forType(
        serverId: server,
        scopeId: scope,
        type: 'financeEntry',
        canonicalId: id,
      );
      expect(source.binding(taskAddress, 'a' * 64)['legacyRevision'], 50);
      expect(finance.binding(moneyAddress, 'b' * 64)['canonicalId'], id);
      expect(taskAddress.wireId, isNot(moneyAddress.wireId));
      final binding = source.binding(taskAddress, 'a' * 64);
      final envelope = <String, dynamic>{
        'format': 2,
        'identity': taskAddress.identity,
        'payload': payload,
        'migrationSource': {
          'version': 2,
          'sourceTable': source.table,
          'typedRow': row,
        },
      };
      final record = <String, dynamic>{
        'serverId': server,
        'scopeId': scope,
        'domain': 'content',
        'id': taskAddress.wireId,
        'type': 'task',
        'deleted': false,
        'metadata': {'identity': taskAddress.identity},
      };
      Future<void> verify(Map<String, dynamic> value) =>
          verifyCryptoMigrationWitness(
            record: record,
            origin: binding,
            recordProofHash: 'a' * 64,
            envelope: value,
            reservedId: (_, _) async => id,
          );
      await verify(
        Map<String, dynamic>.from(
          jsonDecode(utf8.decode(CryptoBusinessJson.encode(envelope))) as Map,
        ),
      );
      await expectLater(
        verify({
          ...envelope,
          'payload': {'title': 'Altered'},
        }),
        throwsFormatException,
      );
      await expectLater(
        verify({...envelope}..remove('migrationSource')),
        throwsFormatException,
      );
      await expectLater(
        verify({
          ...envelope,
          'migrationSource': {
            'version': 2,
            'sourceTable': source.table,
            'typedRow': {...row, 'futureSqlColumn': cell('different capture')},
          },
        }),
        throwsFormatException,
      );
      await expectLater(
        read({...row, 'revision': cell('50.0', type: 'real')}),
        throwsFormatException,
      );
      await expectLater(
        read({...row, 'type': cell('financeEntry')}),
        throwsFormatException,
      );
    },
  );
}
