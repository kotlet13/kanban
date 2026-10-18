import 'dart:convert';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/e2ee/crypto_capture_v3.dart';
import 'package:kanban/organizer/data/e2ee/crypto_codec.dart';
import 'package:kanban/organizer/data/e2ee/crypto_migration_audit.dart';
import 'package:kanban/organizer/data/e2ee/crypto_migration_witness.dart';
import 'package:sodium/sodium.dart';

void main() {
  test(
    'audit witness preserves original raw history without author or revision conversion',
    () async {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      final crypto = CryptoCodec(await SodiumInit.init());
      final db = CollaborationDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final domainKey = crypto.sodium.crypto.secretStream.keygen();
      final captureKey = crypto.sodium.crypto.secretStream.keygen();
      addTearDown(domainKey.dispose);
      addTearDown(captureKey.dispose);
      final scope = crypto.randomId(), record = crypto.randomId();
      final source = CryptoCaptureSourceContext(
        serverId: crypto.randomId(),
        captureId: crypto.randomId(),
        migrationId: crypto.randomId(),
        accountId: crypto.randomId(),
        scopeId: scope,
        domain: 'finance',
        sourceTable: 'familyhub_finance_audit',
        sourceId: 'row:0',
      );
      Map<String, dynamic> cell(String type, String? value) => {
        'type': type,
        'valueBase64': value == null ? null : base64Encode(utf8.encode(value)),
      };
      final before =
          '{"unknown":{"negativeZero":-0.0,"fraction":0.1,"text":"${'z' * 110000}"}}';
      final row = <String, dynamic>{
        'scope_id': cell('text', scope),
        'record_id': cell('text', record),
        'revision': cell('integer', '50'),
        'actor_account_id': cell('text', crypto.randomId()),
        'changed_at': cell('text', '2020-01-02T03:04:05.123+01:00'),
        'before_json': cell('text', before),
        'after_json': cell('null', null),
        'op_id': cell('text', crypto.randomId()),
        'future_column': cell('blob', 'future-bytes'),
      };
      final original = CryptoMigrationAuditSource.decode(source, row);
      expect(original.facts['revision'], 50);
      expect(original.facts['revisionNamespace'], 'legacy');
      expect(original.facts['beforeJson'], before);
      expect(original.facts['changedAt'], '2020-01-02T03:04:05.123+01:00');
      expect(original.typedRow['future_column'], row['future_column']);
      final salt = await CryptoCaptureV3.salt(captureKey, source);
      final context = CryptoMigrationWitnessContext({
        'version': 3,
        'purpose': 'migrationAudit',
        'serverId': source.serverId,
        'accountId': source.accountId,
        'captureId': source.captureId,
        'migrationId': source.migrationId,
        'bindingId': await CryptoCaptureV3.bindingId(captureKey, source),
        'sourceInventoryRoot': 'a' * 64,
        'sourceCommitment': await CryptoCaptureV3.sourceCommitment(
          context: source,
          salt: salt,
          typedRow: row,
        ),
        'scopeId': scope,
        'domain': 'finance',
        'epoch': 1,
        'accessRevision': 0,
        'membershipHeadHash': 'b' * 64,
        'recordId': record,
        'legacyRevision': 50,
      });
      final witness = <String, dynamic>{
        'version': 3,
        'context': source.toJson(),
        'typedRow': row,
        'saltBase64': base64Encode(salt),
      };
      salt.fillRange(0, salt.length, 0);
      final producer = CryptoMigrationWitness(
        database: db,
        partition: 'audit',
        crypto: crypto,
      );
      final descriptor = await producer.stage(
        context: context,
        witness: witness,
        domainKey: domainKey,
      );
      expect(descriptor['purpose'], 'migrationAudit');
      expect(jsonEncode(descriptor), isNot(contains('future-bytes')));
      expect(jsonEncode(descriptor), isNot(contains('2020-01-02')));
      expect(
        await producer.open(
          context: context,
          descriptor: descriptor,
          domainKey: domainKey,
        ),
        witness,
      );
      final changed = CryptoMigrationWitnessContext({
        ...context.value,
        'legacyRevision': 51,
      });
      await expectLater(
        producer.open(
          context: changed,
          descriptor: descriptor,
          domainKey: domainKey,
        ),
        throwsFormatException,
      );
      expect(
        () => CryptoMigrationWitnessContext({
          ...context.value,
          'domain': 'content',
        }),
        throwsFormatException,
      );
      expect(
        () => CryptoMigrationWitnessContext({
          ...context.value,
          'purpose': 'migrationWitness',
        }),
        throwsFormatException,
      );
      expect(
        () => context.requireSource(
          CryptoCaptureSourceContext(
            serverId: source.serverId,
            captureId: source.captureId,
            migrationId: source.migrationId,
            accountId: source.accountId,
            scopeId: scope,
            domain: 'finance',
            sourceTable: 'familyhub_finance_records',
            sourceId: 'row:0',
          ),
        ),
        throwsFormatException,
      );
      expect(
        () => CryptoMigrationAuditSource.decode(source, {
          ...row,
          'revision': cell('integer', '0'),
        }),
        throwsFormatException,
      );
    },
  );
}
