import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  Future<void> flush() => Future<void>.delayed(Duration.zero);

  test(
    'document notifications publish once after the durable outer commit',
    () async {
      final db = CollaborationDatabase(NativeDatabase.memory());
      await db.rows('SELECT 1');
      var events = 0;
      final subscription = db
          .documentChanges('account-a', 'scope-a')
          .listen((_) => events++);
      await db.transaction(() async {
        db.documentsChanged('account-a', 'scope-a');
        await db.transaction(
          () async => db.documentsChanged('account-a', 'scope-a'),
        );
        await flush();
        expect(events, 0);
      });
      await flush();
      expect(events, 1);
      await subscription.cancel();
      await db.close();
    },
  );

  test('failed document projection publishes no notification', () async {
    final db = CollaborationDatabase(NativeDatabase.memory());
    await db.rows('SELECT 1');
    var events = 0;
    final subscription = db
        .documentChanges('account-a', 'scope-a')
        .listen((_) => events++);
    await expectLater(
      db.transaction(() async {
        db.documentsChanged('account-a', 'scope-a');
        throw StateError('synthetic projection failure');
      }),
      throwsStateError,
    );
    await flush();
    expect(events, 0);
    await subscription.cancel();
    await db.close();
  });

  test(
    'document scopes ignore account status and unrelated task content',
    () async {
      final db = CollaborationDatabase(NativeDatabase.memory());
      await db.rows('SELECT 1');
      var events = 0;
      final subscription = db
          .documentChanges('account-a', 'scope-a')
          .listen((_) => events++);
      db.personalChanged(domains: {'organizer'});
      await db.execute(
        "INSERT INTO local_meta(name,value) VALUES('cloud-status','busy')",
      );
      db.documentsChanged('account-b', 'scope-a');
      db.documentsChanged('account-a', 'scope-b');
      await flush();
      expect(events, 0);
      db.documentsChanged('account-a', 'scope-a');
      await flush();
      expect(events, 1);
      await subscription.cancel();
      await db.close();
    },
  );
}
