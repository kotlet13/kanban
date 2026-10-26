import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';

void main() {
  test(
    'scoped commit deduplicates targets and retains broad fallback and rollback',
    () async {
      final db = CollaborationDatabase(NativeDatabase.memory());
      await db.rows('SELECT 1');
      var broad = 0, table = 0, attachments = 0;
      final subscriptions = [
        db.documentChanges('a', 's').listen((_) => broad++),
        db
            .documentChanges('a', 's', type: 'table', id: 't')
            .listen((_) => table++),
        db
            .documentChanges('a', 's', targetType: 'table', targetId: 't')
            .listen((_) => attachments++),
      ];
      Future<void> flush() => Future<void>.delayed(Duration.zero);
      await db.transaction(() async {
        db.documentsChanged('a', 's', type: 'table', id: 't');
        await db.transaction(() async {
          db.documentsChanged(
            'a',
            's',
            type: 'attachment',
            id: 'f',
            targetType: 'table',
            targetId: 't',
          );
          db.documentsChanged('a', 's', type: 'table', id: 'other');
        });
        await flush();
        expect([broad, table, attachments], [0, 0, 0]);
      });
      await flush();
      expect([broad, table, attachments], [1, 1, 1]);
      await expectLater(
        db.transaction(() async {
          db.documentsChanged('a', 's', type: 'table', id: 't');
          throw StateError('rollback');
        }),
        throwsStateError,
      );
      db.documentsChanged('other-account', 's');
      db.documentsChanged('a', 'other-scope');
      await flush();
      expect([broad, table, attachments], [1, 1, 1]);
      // Unknown target on an old tombstone conservatively refreshes attachments.
      db.documentsChanged('a', 's', type: 'attachment', id: 'f');
      await flush();
      expect([broad, table, attachments], [2, 1, 2]);
      db.documentsChanged('a', 's');
      await flush();
      expect([broad, table, attachments], [3, 2, 3]);
      for (final sub in subscriptions) {
        await sub.cancel();
      }
      await db.close();
    },
  );
}
