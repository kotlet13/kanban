import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/e2ee/crypto_sync_store.dart';

class _MeasuredDatabase extends CollaborationDatabase {
  _MeasuredDatabase() : super(NativeDatabase.memory());
  final pages = <({int rows, int bytes})>[];
  @override
  Future<List<Map<String, Object?>>> rows(
    String sql, [
    List<Object?> params = const [],
  ]) async {
    final values = await super.rows(sql, params);
    if (sql.startsWith('SELECT * FROM crypto_outbox') &&
        sql.contains('state=')) {
      pages.add((
        rows: values.length,
        bytes: values.fold(
          0,
          (sum, row) => sum + utf8.encode(row['signed_body'] as String).length,
        ),
      ));
    }
    return values;
  }
}

void main() {
  test(
    '1050 immutable pending bodies use bounded pages and a fixed initial watermark',
    () async {
      final db = _MeasuredDatabase(), partition = 'synthetic-partition';
      addTearDown(db.close);
      final store = CryptoSyncStore(db, partition);
      final expected = <String, String>{};
      await db.transaction(() async {
        for (var i = 0; i < 1050; i++) {
          final body = 'immutable:$i:${'x' * (i < 6 ? 250 * 1024 : 64)}';
          expected['request-$i'] = body;
          await db.execute(
            "INSERT INTO crypto_outbox(partition,request_id,operation,signed_body,request_hash,state) VALUES(?,?,?,?,?,'pending')",
            [partition, 'request-$i', 'synthetic.metadata', body, 'hash-$i'],
          );
        }
      });
      final seen = <String>[];
      await for (final row in store.pendingDelivery()) {
        final id = row['request_id'] as String;
        expect(row['signed_body'], expected[id]);
        seen.add(id);
        if (seen.length == 1) {
          await db.execute(
            "INSERT INTO crypto_outbox(partition,request_id,operation,signed_body,request_hash,state) VALUES(?,?,?,?,?,'pending')",
            [
              partition,
              'enqueued-during-pass',
              'synthetic.metadata',
              'later exact bytes',
              'later-hash',
            ],
          );
        }
        await db.execute(
          "UPDATE crypto_outbox SET state='applied' WHERE partition=? AND request_id=?",
          [partition, id],
        );
      }
      expect(seen, expected.keys.toList());
      expect(db.pages.length, greaterThan(60));
      expect(
        db.pages.every((p) => p.rows <= 16 && p.bytes <= 1024 * 1024),
        true,
      );
      expect(
        (await store.pendingDelivery().toList()).single['request_id'],
        'enqueued-during-pass',
      );
      expect(
        (await store.pending()).single['signed_body'],
        'later exact bytes',
      );
    },
  );
}
