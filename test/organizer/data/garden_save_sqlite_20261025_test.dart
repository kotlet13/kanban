import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/garden_repository.dart';
import 'package:kanban/organizer/data/garden_storage.dart';
import 'package:kanban/organizer/data/organizer_repository.dart';
import 'package:kanban/organizer/domain/garden_models.dart';
import 'package:kanban/organizer/domain/local_space_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'household garden creates then saves two beds and season with revision guards',
    () async {
      final db = CollaborationDatabase(NativeDatabase.memory());
      final storage = GardenStorage(db);
      final repository = GardenRepository(storage);
      addTearDown(() async {
        await repository.close();
        await db.close();
      });
      const household = LocalSpace(
        id: 'synthetic-household',
        kind: LocalSpaceKind.household,
        name: 'Synthetic household',
      );
      await db.execute('INSERT INTO local_spaces(id,data) VALUES(?,?)', [
        household.id,
        jsonEncode(household.toJson()),
      ]);
      db.activateLocalWorkspace(household.id);
      await repository.initialize();
      await repository.createGarden(
        name: 'Synthetic two beds',
        widthMeters: 8,
        heightMeters: 10,
        expectedWorkspaceKey: household.id,
      );
      final created = repository.snapshot.gardens.single;
      const bed1 = GardenArea(
        id: '10000000-0000-4000-8000-000000000002',
        label: 'Bed one',
        x: .1,
        y: .1,
        width: .3,
        height: .3,
      );
      const bed2 = GardenArea(
        id: '10000000-0000-4000-8000-000000000003',
        label: 'Bed two',
        x: .5,
        y: .5,
        width: .3,
        height: .3,
      );
      await repository.updateGarden(
        created.copyWith(
          areas: [bed1, bed2],
          seasons: [GardenSeason(year: 2026)],
        ),
        expectedWorkspaceKey: household.id,
      );
      final saved = (await storage.read()).gardens.single;
      expect(saved.areas.map((a) => a.label), ['Bed one', 'Bed two']);
      expect(saved.seasons.single.year, 2026);
      expect(saved.revision, greaterThan(created.revision));
      expect(saved.createdAt, created.createdAt);
      expect(await db.rows('SELECT * FROM outbox'), isEmpty);
      await expectLater(
        repository.updateGarden(
          created.copyWith(notes: 'Old editor'),
          expectedWorkspaceKey: household.id,
        ),
        throwsA(isA<OrganizerConflictException>()),
      );
      expect((await storage.read()).gardens.single.toJson(), saved.toJson());
    },
  );
}
