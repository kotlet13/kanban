// ignore_for_file: avoid_print
// Bounded synthetic performance evidence; never logs record contents.
import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/data/garden_repository.dart';
import 'package:kanban/organizer/data/garden_storage.dart';
import 'package:kanban/organizer/data/idea_repository.dart';
import 'package:kanban/organizer/data/idea_storage.dart';
import '../support/synthetic_content_route_guard.dart';
import 'collaboration_repository_test.dart'
    show FakeServer, FakeTransport, MemorySessionStore;

class MeasuredDb extends CollaborationDatabase {
  MeasuredDb() : super(NativeDatabase.memory());
  final reads = <String>[];
  @override
  Future<List<Map<String, dynamic>>> rows(
    String sql, [
    List<Object?> args = const [],
  ]) {
    reads.add(sql);
    return super.rows(sql, args);
  }
}

Future<Map<String, Object>> measure(
  MeasuredDb db,
  Future<void> Function() body,
) async {
  db.reads.clear();
  final watch = Stopwatch()..start();
  await body();
  watch.stop();
  return {
    'elapsedMicroseconds': watch.elapsedMicroseconds,
    'sqlReads': db.reads.length,
    'recordScans': db.reads
        .where((s) => s.contains('FROM records') && s.contains('ORDER BY'))
        .length,
  };
}

void main() {
  test(
    'P8 scoped save rebuilds only changed scope and preserves others',
    () async {
      final db = MeasuredDb(), server = FakeServer();
      final repo = CollaborationRepository(
        db,
        FakeTransport(server),
        MemorySessionStore(),
        contentRouteGuard: const SyntheticContentRouteGuard(),
      );
      addTearDown(repo.close);
      await repo.initialize();
      await repo.login(
        serverUrl: 'https://synthetic.invalid',
        username: 'alice',
        password: 'synthetic',
      );
      final ids = <String>[];
      for (var i = 0; i < 8; i++) {
        ids.add(await repo.createScope('Scoped $i'));
      }
      final unchanged = repo.state.data[ids.last];
      final beforeCalls = server.calls.length;
      final saved = await measure(db, () async {
        await repo.createTask(scopeId: ids.first, title: 'Scoped measurement');
      });
      expect(
        saved['recordScans'],
        2,
      ); // One pre-read, one postcommit changed scope.
      expect(identical(repo.state.data[ids.last], unchanged), true);
      expect(
        repo.state.data[ids.first]!.tasks.single.title,
        'Scoped measurement',
      );
      expect(repo.state.pendingCount, 1);
      expect(server.calls.length, beforeCalls);
      print('P8_SCOPED_SAVE ${jsonEncode(saved)}');
      // Two distinct local transactions racing their coalesced postcommit refresh.
      await Future.wait([
        repo.createTask(scopeId: ids[1], title: 'Concurrent one'),
        repo.createTask(scopeId: ids[2], title: 'Concurrent two'),
      ]);
      expect(repo.state.data[ids[1]]!.tasks.single.title, 'Concurrent one');
      expect(repo.state.data[ids[2]]!.tasks.single.title, 'Concurrent two');
      expect(
        repo.state.data[ids.first]!.tasks.single.title,
        'Scoped measurement',
      );
      expect(repo.state.pendingCount, 3);
      final rows = await db.rows('SELECT DISTINCT scope_id FROM outbox');
      expect(rows.map((r) => r['scope_id']).toSet(), ids.take(3).toSet());
      expect(server.calls.length, beforeCalls);
    },
  );

  test(
    'P8 bounded local measurement: shared refresh and garden idea signals',
    () async {
      final db = MeasuredDb();
      final server = FakeServer();
      final repo = CollaborationRepository(
        db,
        FakeTransport(server),
        MemorySessionStore(),
        contentRouteGuard: const SyntheticContentRouteGuard(),
      );
      addTearDown(repo.close);
      await repo.initialize();
      await repo.login(
        serverUrl: 'https://synthetic.invalid',
        username: 'alice',
        password: 'synthetic',
      );
      final ids = <String>[];
      for (var i = 0; i < 8; i++) {
        ids.add(await repo.createScope('Measured $i'));
      }
      final beforeCalls = server.calls.length;
      final full = await measure(db, () => repo.refreshLocal());
      final scoped = await measure(
        db,
        () => repo.refreshLocal(scopeIds: {ids.first}),
      );
      final saved = await measure(db, () async {
        await repo.createTask(scopeId: ids.first, title: 'Measurement only');
      });
      expect(
        repo.state.data[ids.first]!.tasks.single.title,
        'Measurement only',
      );
      expect(repo.state.data[ids.last]!.tasks, isEmpty);
      expect(
        server.calls.length,
        beforeCalls,
      ); // These are local SQL measurements.
      print(
        'P8_SHARED ${jsonEncode({'scopes': ids.length, 'full': full, 'scoped': scoped, 'save': saved})}',
      );
      final garden = GardenRepository(GardenStorage(db));
      final ideas = IdeaRepository(IdeaStorage(db));
      await garden.initialize();
      await ideas.initialize();
      var gardenEvents = 0, ideaEvents = 0;
      final gs = garden.changes.listen((_) {
        gardenEvents++;
      });
      final isub = ideas.changes.listen((_) {
        ideaEvents++;
      });
      final local = await measure(db, () async {
        await garden.createGarden(name: 'Measured garden');
        await ideas.createBoard(title: 'Measured idea');
        // Drain their queued signal reloads by the public serialized reads.
        await garden.reload();
        await ideas.reload();
        await Future<void>.delayed(Duration.zero);
      });
      expect(garden.snapshot.gardens.single.name, 'Measured garden');
      expect(ideas.snapshot.boards.single.title, 'Measured idea');
      print(
        'P8_LOCAL ${jsonEncode({...local, 'gardenEventsIncludingDrain': gardenEvents, 'ideaEventsIncludingDrain': ideaEvents})}',
      );
      await gs.cancel();
      await isub.cancel();
      await garden.close();
      await ideas.close();
    },
  );
}
