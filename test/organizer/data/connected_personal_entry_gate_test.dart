import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/idea_repository.dart';
import 'package:kanban/organizer/data/connected_personal_entry.dart';
import 'package:kanban/organizer/data/sqlite_organizer_storage.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'dart:async';
import 'package:kanban/organizer/data/idea_storage.dart';
import 'package:kanban/organizer/data/organizer_repository.dart';
import 'package:kanban/organizer/data/organizer_storage.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';

class _Storage implements OrganizerStorage {
  OrganizerSnapshot value = OrganizerSnapshot();
  int writes = 0;
  @override
  Future<OrganizerSnapshot> read() async => value;
  @override
  Future<void> write(OrganizerSnapshot next) async {
    value = next;
    writes++;
  }

  @override
  Future<void> close() async {}
}

void main() {
  test('storage binding requires authorization even while UI state is absent or loading',( )async {
    final db=CollaborationDatabase(NativeDatabase.memory());
    final profile=AccountSession(serverUrl:'https://example.test',serverId:'11111111-1111-4111-8111-111111111111',accountId:'22222222-2222-4222-8222-222222222222',userId:1,username:'test',displayName:'Test',deviceId:'33333333-3333-4333-8333-333333333333',expiresAt:DateTime.utc(2099));
    db.activatePersonal(profile);
    await db.execute('INSERT INTO personal_workspaces(id,partition,scope_id) VALUES(?,?,?)',['private:${profile.partition}',profile.partition,'44444444-4444-4444-8444-444444444444']);
    final storage=SqliteOrganizerStorage(db);
    final authorization=Completer<void>();
    var called=0;
    final attempt=authorizeConnectedPersonalEntry(db,(bound)async {called++;expect(bound.partition,profile.partition);await authorization.future;});
    await Future<void>.delayed(Duration.zero);
    expect(called,1);expect(await storage.activeBinding(),isNotNull);
    db.activatePersonal(null);
    authorization.complete();
    await expectLater(attempt,throwsA(isA<OrganizerConflictException>()));
    var accountlessCalls=0;
    await authorizeConnectedPersonalEntry(db,(_)async {accountlessCalls++;});
    expect(accountlessCalls,0);
    await db.close();
  });

  test(
    'connected personal entry email failure precedes local commit; accountless editing remains available',
    () async {
      final storage = _Storage();
      final blocked = OrganizerRepository(
        storage,
        beforeConnectedEntry: () async =>
            throw StateError('email_verification_required'),
      );
      await blocked.initialize();
      await expectLater(
        blocked.createTask(title: 'Keep private'),
        throwsStateError,
      );
      expect(storage.writes, 0);
      expect(storage.value.tasks, isEmpty);
      await blocked.close();
      final local = OrganizerRepository(storage);
      await local.initialize();
      await local.createTask(title: 'No account required');
      expect(storage.value.tasks.single.title, 'No account required');
      await local.close();
    },
  );
  test(
    'idea entry gate leaves boards unchanged and preserves a separate local draft',
    () async {
      final db = CollaborationDatabase(NativeDatabase.memory());
      final storage = IdeaStorage(db);
      final blocked = IdeaRepository(
        storage,
        beforeConnectedEntry: () async =>
            throw StateError('email_verification_required'),
      );
      try {
        await blocked.initialize();
        await expectLater(
          blocked.createBoard(title: 'Private idea'),
          throwsStateError,
        );
        expect((await storage.read()).boards, isEmpty);
      } finally {
        await blocked.close();
        await db.close();
      }
    },
  );
}
