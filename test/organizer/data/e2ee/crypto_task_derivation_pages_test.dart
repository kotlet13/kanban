import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/e2ee/crypto_task_resolution.dart';

void main() {
  test(
    'task-cost scan reaches beyond sixteen resolved entries in bounded pages',
    () async {
      final db = CollaborationDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      for (var i = 0; i < 33; i++) {
        await db.execute(
          "INSERT INTO crypto_business_records(partition,scope_id,domain,id,type,crypto_revision,record_proof_hash,deleted,raw_payload,projection,history_basis) VALUES('p','scope','finance',?,'financeEntry',1,?,0,?,?,'currentEpoch')",
          [
            i.toString().padLeft(3, '0'),
            'a' * 64,
            jsonEncode({'taskId': 'task$i', 'alreadyResolved': i < 16}),
            jsonEncode({'id': 'entry$i'}),
          ],
        );
      }
      final lengths = <int>[], unresolved = <String>[];
      await for (final page in cryptoTaskDerivationPages(db, 'p', 'scope')) {
        lengths.add(page.length);
        for (final row in page) {
          final raw = jsonDecode(row['raw_payload'] as String) as Map;
          if (raw['alreadyResolved'] != true)
            unresolved.add(raw['taskId'] as String);
        }
      }
      expect(lengths, [16, 16, 1]);
      expect(unresolved, [for (var i = 16; i < 33; i++) 'task$i']);
    },
  );
}
