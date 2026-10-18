import 'dart:convert';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/e2ee/crypto_business_settlement.dart';
import 'package:kanban/organizer/data/e2ee/crypto_json.dart';
import 'package:kanban/organizer/data/e2ee/crypto_migration_local_intents.dart';

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  test(
    'applied ACK alone is unresolved; semantic completion binds exact immutable request',
    () async {
      final db = CollaborationDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.execute(
        'INSERT INTO crypto_outbox(partition,request_id,operation,signed_body,request_hash,state) VALUES(?,?,?,?,?,?)',
        [
          'own',
          'request',
          'crypto2.records.batch',
          ' exact original bytes ',
          'a' * 64,
          'applied',
        ],
      );
      Future<bool> settled([String partition = 'own']) =>
          CryptoBusinessSettlement.contains(
            database: db,
            partition: partition,
            requestId: 'request',
          );
      expect(await settled(), isFalse);
      await CryptoBusinessSettlement.record(
        database: db,
        partition: 'own',
        requestId: 'request',
      );
      // No current scope/READ is needed for already completed historical work.
      expect(await settled(), isTrue);
      expect(await settled('foreign'), isFalse);
      await db.execute(
        'UPDATE crypto_outbox SET signed_body=? WHERE request_id=?',
        ['replacement bytes', 'request'],
      );
      expect(await settled(), isFalse);
      await db.execute(
        'UPDATE crypto_outbox SET signed_body=?,request_hash=? WHERE request_id=?',
        [' exact original bytes ', 'b' * 64, 'request'],
      );
      expect(await settled(), isFalse);
    },
  );
  test(
    'private crypto receipt frame rejects foreign actor, workflow and extra secret column',
    () {
      Map<String, dynamic> frame({
        String actor = 'account',
        String operation = 'crypto2.records.batch',
      }) {
        final command = {
          'operation': operation,
          'accountId': actor,
          'serverId': 'server',
          'requestId': 'request',
        };
        return {
          'kind': 'cryptoReceiptRow',
          'table': 'crypto_outbox',
          'row': {
            'sequence': 1,
            'partition': 'own',
            'request_id': 'request',
            'operation': operation,
            'signed_body': jsonEncode({
              'commandBase64': base64Encode(CryptoJson.encode(command)),
            }),
            'request_hash': 'a' * 64,
            'state': 'applied',
            'response': ' exact old response ',
          },
        };
      }

      void verify(Map<String, dynamic> f) =>
          CryptoMigrationLocalIntentSnapshot.validateReceiptFrame(
            f,
            partition: 'own',
            serverId: 'server',
            accountId: 'account',
          );
      verify(frame());
      expect(() => verify(frame(actor: 'foreign')), throwsFormatException);
      expect(
        () => verify(frame(operation: 'crypto2.migration.verify3')),
        throwsFormatException,
      );
      final secret = frame();
      (secret['row'] as Map)['key_bytes'] = 'must never be exported';
      expect(() => verify(secret), throwsFormatException);
    },
  );
}
