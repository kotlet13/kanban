import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/e2ee/crypto_migration_record_source.dart';
import 'package:kanban/organizer/data/e2ee/crypto_record_address.dart';
import 'package:kanban/organizer/data/e2ee/crypto_record_authorship.dart';

const _server = '11111111-1111-4111-8111-111111111111';
const _scope = '22222222-2222-4222-8222-222222222222';
const _id = '33333333-3333-4333-8333-333333333333';
const _creator = '44444444-4444-4444-8444-444444444444';
const _importer = '55555555-5555-4555-8555-555555555555';
const _updater = '66666666-6666-4666-8666-666666666666';
Map<String, dynamic> _cell(String? value, {String type = 'text'}) => {
  'type': type,
  'valueBase64': value == null ? null : base64Encode(utf8.encode(value)),
};
Map<String, dynamic> _row(String type) => {
  'id': _cell(_id),
  'scope_id': _cell(_scope),
  'type': _cell(type),
  'revision': _cell('7', type: 'integer'),
  'deleted': _cell('0', type: 'integer'),
  'payload': _cell(jsonEncode({'title': 'Exact payload'})),
  'created_by': _cell(_creator),
  'updated_by': _cell(_updater),
};
Future<CryptoMigrationRecordSource> _decode(
  String table,
  Map<String, dynamic> row, {
  String domain = 'content',
}) => CryptoMigrationRecordSource.decode(
  table: table,
  domain: domain,
  row: row,
  serverId: _server,
  reservedId: (_, _) async => _id,
);

void main() {
  test(
    'verified legacy witness retains exact creator/updater separately without assigning importer or rewriting payload',
    () async {
      for (final (table, domain, type) in [
        ('familyhub_records', 'content', 'task'),
        ('familyhub_finance_records', 'finance', 'financeEntry'),
      ]) {
        final row = _row(type);
        final source = await _decode(table, row, domain: domain);
        final address = CryptoRecordAddress.forType(
          serverId: _server,
          scopeId: _scope,
          type: type,
          canonicalId: _id,
        );
        final binding = source.binding(address, 'a' * 64);
        final envelope = <String, dynamic>{
          'format': 2,
          'identity': address.identity,
          'payload': source.rawPayload,
          'migrationSource': {
            'version': 2,
            'sourceTable': table,
            'typedRow': row,
          },
        };
        final record = <String, dynamic>{
          'serverId': _server,
          'accountId': _importer,
          'scopeId': _scope,
          'domain': domain,
          'id': address.wireId,
          'type': type,
          'deleted': false,
          'expectedRevision': 0,
          'metadata': {'identity': address.identity, 'migrationOrigin': {}},
        };
        var callbacks = 0;
        final raw = await verifyCryptoMigrationWitness(
          record: record,
          origin: binding,
          recordProofHash: 'a' * 64,
          envelope: envelope,
          reservedId: (_, _) async => _id,
          onVerifiedSource: (verified) {
            callbacks++;
            expect(verified.createdByAccountId, _creator);
            expect(verified.updatedByAccountId, _updater);
            expect(
              CryptoRecordAuthorship.resolve(
                verifiedRecord: record,
                verifiedOriginCreator: verified.createdByAccountId,
              ),
              _creator,
            );
          },
        );
        expect(raw, {'title': 'Exact payload'});
        expect(callbacks, 1);
        await expectLater(
          verifyCryptoMigrationWitness(
            record: record,
            origin: binding,
            recordProofHash: 'a' * 64,
            envelope: {
              ...envelope,
              'migrationSource': {
                'version': 2,
                'sourceTable': table,
                'typedRow': {...row, 'created_by': _cell(_importer)},
              },
            },
            reservedId: (_, _) async => _id,
            onVerifiedSource: (_) => callbacks++,
          ),
          throwsFormatException,
        );
        expect(
          callbacks,
          1,
          reason: 'Unverified author never reaches projection',
        );
      }
    },
  );

  test(
    'verified table/attachment typed rows retain established transport authors',
    () async {
      final table = await _decode('familyhub_tables', {
        ..._row('table'),
        'title': _cell('Table'),
        'cells': _cell('{}'),
        'updated_at': _cell('1', type: 'integer'),
      });
      expect(table.createdByAccountId, _creator);
      expect(table.updatedByAccountId, isNull);
      final attachment = await _decode('familyhub_attachments', {
        ..._row('attachment'),
        'owner_account_id': _cell(_updater),
        'complete': _cell('1', type: 'integer'),
        'received': _cell('1', type: 'integer'),
        'target_type': _cell('scope'),
        'target_id': _cell(_scope),
        'name': _cell('example.txt'),
        'mime': _cell('text/plain'),
        'size': _cell('1', type: 'integer'),
        'sha256': _cell('a' * 64),
        'created_at': _cell('1', type: 'integer'),
      });
      expect(
        attachment.createdByAccountId,
        _updater,
        reason: 'Attachment uses owner_account_id, not unrelated created_by',
      );
    },
  );

  test(
    'ordinary update preserves verified creator; relocation publisher never becomes author',
    () {
      final original = <String, dynamic>{
        'expectedRevision': 0,
        'accountId': _creator,
        'metadata': <String, dynamic>{},
      };
      expect(
        CryptoRecordAuthorship.resolve(verifiedRecord: original),
        _creator,
      );
      final edited = {
        ...original,
        'expectedRevision': 4,
        'accountId': _updater,
      };
      expect(
        CryptoRecordAuthorship.resolve(
          verifiedRecord: edited,
          previousCanonical: {'createdByAccountId': _creator},
        ),
        _creator,
      );
      final relocation = {
        ...original,
        'accountId': _importer,
        'metadata': {'projectRelocation': {}},
      };
      expect(
        CryptoRecordAuthorship.resolve(verifiedRecord: relocation),
        isNull,
        reason: 'Unproven source creator must remain unknown, not importer',
      );
      expect(
        CryptoRecordAuthorship.resolve(
          verifiedRecord: relocation,
          verifiedOriginCreator: _creator,
        ),
        _creator,
      );
      expect(
        () => CryptoRecordAuthorship.resolve(
          verifiedRecord: edited,
          previousCanonical: {'createdByAccountId': _creator},
          verifiedOriginCreator: _importer,
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'missing captured author remains missing and malformed author fails without guessed reconstruction',
    () async {
      final row = _row('task')..remove('created_by');
      final missing = await _decode('familyhub_records', row);
      expect(missing.createdByAccountId, isNull);
      final malformed = await _decode('familyhub_records', {
        ...row,
        'created_by': _cell('not-an-account'),
      });
      expect(() => malformed.createdByAccountId, throwsFormatException);
    },
  );
  test(
    'explicit anonymized legacy creator remains readable without invented replacement',
    () async {
      final source = await _decode('familyhub_records', {
        ..._row('task'),
        'created_by': _cell(''),
        'updated_by': _cell(''),
      });
      expect(source.createdByAccountId, isNull);
      expect(source.updatedByAccountId, isNull);
      expect(CryptoRecordAuthorship.account(''), isNull);
      expect(
        CryptoRecordAuthorship.resolve(
          verifiedRecord: {
            'expectedRevision': 0,
            'accountId': _importer,
            'metadata': {'migrationOrigin': {}},
          },
          verifiedOriginCreator: source.createdByAccountId,
        ),
        isNull,
      );
    },
  );
  test(
    'missing creator column is unavailable provenance while captured anonymous sentinel is explicit evidence',
    () async {
      final missing = await _decode(
        'familyhub_records',
        _row('task')..remove('created_by'),
      );
      expect(missing.hasCapturedCreator, false);
      expect(missing.createdByAccountId, isNull);
      final anonymous = await _decode('familyhub_records', {
        ..._row('task'),
        'created_by': _cell(''),
      });
      expect(anonymous.hasCapturedCreator, true);
      expect(anonymous.createdByAccountId, isNull);
      final explicitNull = await _decode('familyhub_records', {
        ..._row('task'),
        'created_by': _cell(null),
      });
      expect(explicitNull.hasCapturedCreator, true);
      expect(explicitNull.createdByAccountId, isNull);
    },
  );
}
