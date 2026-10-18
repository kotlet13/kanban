import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/e2ee/crypto_migration_payments.dart';
import 'package:kanban/organizer/data/e2ee/crypto_migration_record_source.dart';
import 'package:kanban/organizer/data/e2ee/crypto_business_json.dart';
import 'package:kanban/organizer/data/e2ee/crypto_record_address.dart';

void main() {
  const scope = '11111111-1111-4111-8111-111111111111',
      event = '22222222-2222-4222-8222-222222222222',
      entry = '33333333-3333-4333-8333-333333333333',
      payer = '44444444-4444-4444-8444-444444444444',
      account = '55555555-5555-4555-8555-555555555555';
  Map<String, dynamic> cell(Object value, {String type = 'text'}) => {
    'type': type,
    'valueBase64': base64Encode(utf8.encode(value.toString())),
  };
  Map<String, dynamic> payload() => {
    'eventId': event,
    'sourceScopeId': scope,
    'sourceEntryId': entry,
    'sourceRevision': 77,
    'payerAccountId': payer,
    'amountMinor': 1000,
    'currency': 'EUR',
    'paidAt': '2026-10-17T00:00:00.000Z',
    'expectReimbursement': true,
    'revision': 12,
    'reimbursements': <Object>[],
    'sourceState': 'deleted',
    'future': {'fraction': 0.125, 'negativeZero': -0.0, 'unicode': 'Čebelica'},
  };
  Map<String, dynamic> eventRow(Map<String, dynamic> raw) => {
    'scope_id': cell(scope),
    'event_id': cell(event),
    'entry_id': cell(entry),
    'payer_account_id': cell(payer),
    'revision': cell(12, type: 'bigint(20)'),
    'data': cell(jsonEncode(raw), type: 'longtext'),
    'future_sql_column': cell('retained by the typed source archive'),
  };
  test(
    'captured deleted-source event preserves old money and all raw extensions',
    () {
      final raw = payload(), row = eventRow(payload());
      final decoded = decodeCryptoMigrationPaymentSource(
        table: 'familyhub_payment_events',
        row: row,
      );
      expect(decoded.legacyRevision, 12);
      expect(decoded.deleted, false);
      expect(decoded.canonicalId, event);
      expect(
        CryptoBusinessJson.canonical(decoded.rawPayload),
        CryptoBusinessJson.canonical(raw),
      );
      expect(decoded.rawPayload.containsKey('paymentFormat'), false);
      expect(decoded.rawPayload.containsKey('paymentSourceWitness'), false);
      expect(row.containsKey('future_sql_column'), true);
    },
  );
  test(
    'central source pipeline uses typed payment PK rather than absent id column',
    () async {
      final row = eventRow(payload());
      final decoded = await CryptoMigrationRecordSource.decode(
        table: 'familyhub_payment_events',
        domain: 'finance',
        row: row,
        reservedId: (_, _) async =>
            throw StateError('No reserved payment identity'),
      );
      expect(decoded.sourceId, event);
      expect(decoded.canonicalId, event);
      expect(decoded.legacyRevision, 12);
      expect(decoded.rawPayload, payload());
      expect(decoded.typedRow, row);
      await expectLater(
        CryptoMigrationRecordSource.decode(
          table: 'familyhub_payment_events',
          domain: 'content',
          row: row,
          reservedId: (_, _) async => event,
        ),
        throwsFormatException,
      );
    },
  );
  test('SQL event tuple cannot substitute a different captured event', () {
    final row = eventRow(payload())..['entry_id'] = cell(event);
    expect(
      () => decodeCryptoMigrationPaymentSource(
        table: 'familyhub_payment_events',
        row: row,
      ),
      throwsFormatException,
    );
    final revision = eventRow(payload())
      ..['revision'] = cell(13, type: 'integer');
    expect(
      () => decodeCryptoMigrationPaymentSource(
        table: 'familyhub_payment_events',
        row: revision,
      ),
      throwsFormatException,
    );
  });
  test('source-removed private projection remains a historical fact', () {
    final raw = {
      ...payload(),
      'paymentRevision': 12,
      'state': 'sourceRemoved',
      'privateAccountId': account,
    };
    final row = <String, dynamic>{
      'scope_id': cell(payer),
      'event_id': cell(event),
      'source_scope_id': cell(scope),
      'owner_account_id': cell(payer),
      'data': cell(jsonEncode(raw)),
    };
    final decoded = decodeCryptoMigrationPaymentSource(
      table: 'familyhub_payment_projections',
      row: row,
    );
    expect(decoded.scopeId, payer);
    expect(decoded.type, 'paymentProjection');
    expect(decoded.rawPayload, raw);
    expect(decoded.rawPayload['amountMinor'], 1000);
  });
  test(
    'old cash retains exact ID and amount without inventing an event link',
    () {
      final raw = {
        'id': event,
        'accountId': account,
        'amountMinor': -1000,
        'currency': 'EUR',
        'paidAt': '2026-10-17T00:00:00.000Z',
        'future': {'ratio': 0.5},
      };
      final row = <String, dynamic>{
        'scope_id': cell(payer),
        'movement_id': cell(event),
        'data': cell(jsonEncode(raw)),
      };
      final decoded = decodeCryptoMigrationPaymentSource(
        table: 'familyhub_payment_cash',
        row: row,
      );
      expect(decoded.legacyRevision, 1);
      expect(decoded.rawPayload, raw);
      expect(decoded.rawPayload.containsKey('paymentLink'), false);
      final substituted = {...row, 'movement_id': cell(entry)};
      expect(
        () => decodeCryptoMigrationPaymentSource(
          table: 'familyhub_payment_cash',
          row: substituted,
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'baseline validator binds supplied verified origin to exact proof coordinate',
    () {
      final address = CryptoRecordAddress.forType(
        serverId: '66666666-6666-4666-8666-666666666666',
        scopeId: scope,
        type: 'paymentEvent',
        canonicalId: event,
        domain: 'finance',
      );
      final hash = 'a' * 64;
      final origin = <String, dynamic>{
        'captureVersion': 3,
        'sourceTable': 'familyhub_payment_events',
        'type': 'paymentEvent',
        'scopeId': scope,
        'domain': 'finance',
        'sourceId': event,
        'canonicalId': event,
        'sourceKind': address.identity['sourceKind'],
        'wireId': address.wireId,
        'recordProofHash': hash,
        'materializationRole': 'primary',
        'legacyRevision': 12,
      };
      final record = <String, dynamic>{
        'type': 'paymentEvent',
        'scopeId': scope,
        'domain': 'finance',
        'id': address.wireId,
        'expectedRevision': 0,
        'deleted': false,
        'metadata': {'identity': address.identity},
      };
      final raw = payload();
      expect(
        validateCryptoMigrationPaymentBaseline(
          origin: origin,
          record: record,
          recordProofHash: hash,
          raw: raw,
        ),
        same(raw),
      );
      expect(
        () => validateCryptoMigrationPaymentBaseline(
          origin: origin,
          record: {...record, 'expectedRevision': 1},
          recordProofHash: hash,
          raw: raw,
        ),
        throwsFormatException,
      );
      expect(
        () => validateCryptoMigrationPaymentBaseline(
          origin: origin,
          record: record,
          recordProofHash: 'b' * 64,
          raw: raw,
        ),
        throwsFormatException,
      );
      expect(
        () => validateCryptoMigrationPaymentBaseline(
          origin: {...origin, 'scopeId': payer},
          record: record,
          recordProofHash: hash,
          raw: raw,
        ),
        throwsFormatException,
      );
    },
  );
}
