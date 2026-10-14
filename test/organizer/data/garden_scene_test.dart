import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/garden_repository.dart';
import 'package:kanban/organizer/data/garden_storage.dart';
import 'package:kanban/organizer/data/local_spaces_repository.dart';
import 'package:kanban/organizer/domain/local_space_models.dart';
import 'package:kanban/organizer/data/organizer_repository.dart';
import 'package:kanban/organizer/data/portable_backup_document.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart'
    show BackupRestoreMode;
import 'package:kanban/organizer/domain/garden_models.dart';
import 'package:kanban/organizer/domain/garden_rotation.dart';
import 'package:kanban/organizer/domain/garden_scene.dart';
import 'package:kanban/organizer/domain/shared_payload_validation.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart'
    show SharedRecordType, CollaborationException;
import 'garden_repository_test.dart' as old;
import 'garden_seasons_test.dart' as seasonal;

Garden sceneGarden() => seasonal.richGarden().copyWith(
  widthMeters: 12,
  heightMeters: 8,
  seasons: [
    ...seasonal.richGarden().seasons,
    GardenSeason(
      year: 2028,
      plantings: [
        seasonal
            .planting(id: 41)
            .copyWith(
              illustration: GardenCropIllustration.tomato,
              spacingCm: 35.5,
              visualGrowthDays: 80,
              sowAt: DateTime.utc(2028, 3, 20),
              plantAt: DateTime.utc(2028, 5, 15),
              clearHarvestAt: true,
            ),
      ],
    ),
  ],
);
Map<String, dynamic> clone(Object value) =>
    jsonDecode(jsonEncode(value)) as Map<String, dynamic>;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  test(
    'v1/v2 remain exact; v3 roundtrip preserves physical and all planting fields',
    () {
      final legacy = Garden.fromJson(seasonal.legacyGarden());
      expect(legacy.hasPhysicalSize, isFalse);
      expect(legacy.toJson()['version'], 2);
      final v2 = seasonal.richGarden();
      expect(Garden.fromJson(clone(v2.toJson())).toJson(), v2.toJson());
      expect(
        v2.seasons.first.plantings.first.harvested,
        isFalse,
        reason: 'Old harvest dates never auto-empty beds',
      );
      final rich = sceneGarden();
      final restored = Garden.fromJson(clone(rich.toJson()));
      expect(restored.toJson(), rich.toJson());
      expect(restored.documentVersion, 3);
      expect(restored.widthMeters, 12);
      expect(restored.seasonForYear(2028)!.plantings.single.spacingCm, 35.5);
      final mixed = GardenSnapshot(
        gardens: [
          rich,
          old.garden().copyWith(name: 'Another'),
        ],
      );
      // Roundtrip the single rich document; mixed legacy/new identity collisions remain invalid.
      expect(() => mixed.validate(), throwsFormatException);
      expect(() {
        if (rich.toJson()['version'] != 2) throw const FormatException();
      }, throwsFormatException);
      final minimal3 = clone(old.garden().toJson())
        ..['version'] = 3
        ..['widthMeters'] = null
        ..['heightMeters'] = null;
      expect(
        Garden.fromJson(minimal3).toJson()['version'],
        3,
        reason: 'Cleared defaults cannot downgrade a recognized v3 document',
      );
    },
  );
  test(
    'v3 rejects unknown/missing/NaN measurements, invalid harvested state and nested truncation',
    () {
      final valid = sceneGarden().toJson();
      for (final mutate in <void Function(Map<String, dynamic>)>[
        (j) => j['version'] = 4,
        (j) => j.remove('heightMeters'),
        (j) => j['heightMeters'] = null,
        (j) => j['widthMeters'] = 0,
        (j) => j['widthMeters'] = 10001,
        (j) => j['widthMeters'] = '12',
        (j) => j['seasons'][2]['plantings'][0].remove('harvested'),
        (j) => j['seasons'][2]['plantings'][0]['spacingCm'] = 0,
        (j) => j['seasons'][2]['plantings'][0]['visualGrowthDays'] = 0,
        (j) => j['seasons'][2]['plantings'][0]['illustration'] = 'invented',
        (j) => j['seasons'][2]['plantings'][0]['harvested'] = true,
        (j) => j['seasons'][2]['plantings'][0]['other'] = 1,
        (j) {
          j['version'] = 2;
          j.remove('widthMeters');
          j.remove('heightMeters');
        },
      ]) {
        final changed = clone(valid);
        mutate(changed);
        expect(
          () => Garden.fromJson(changed),
          throwsA(
            anyOf(
              isA<FormatException>(),
              isA<TypeError>(),
              isA<ArgumentError>(),
            ),
          ),
        );
      }
      expect(
        () => sceneGarden().copyWith(widthMeters: double.nan).validate(),
        throwsFormatException,
      );
    },
  );
  test(
    'calendar growth advances with days independent of DST, saturates and respects missing dates and plans',
    () {
      final planting = seasonal.planting().copyWith(
        plantAt: DateTime.utc(2026, 5, 10),
        visualGrowthDays: 60,
      );
      expect(gardenVisualGrowth(planting, DateTime(2026, 5, 10, 23)), .12);
      expect(
        gardenVisualGrowth(planting, DateTime(2026, 6, 9)),
        closeTo(.56, .0001),
      );
      expect(gardenVisualGrowth(planting, DateTime(2026, 8, 10)), 1);
      expect(gardenVisualGrowth(planting, DateTime(2026, 3, 1)), .12);
      expect(
        gardenVisualGrowth(
          planting.copyWith(status: GardenPlantingStatus.planned),
          DateTime(2028),
        ),
        .12,
      );
      expect(
        gardenVisualGrowth(
          planting.copyWith(clearSowAt: true, clearPlantAt: true),
          DateTime(2028),
        ),
        .12,
      );
    },
  );
  test(
    'harvest clears only its planting from scene and preserves crop, identity, spacing and history',
    () {
      final garden = sceneGarden();
      final planting = garden.seasonForYear(2028)!.plantings.single;
      final harvested = harvestGardenPlanting(
        planting,
        DateTime(2028, 9, 4, 13),
      );
      expect(harvested.id, planting.id);
      expect(harvested.harvestAt, DateTime.utc(2028, 9, 4));
      expect(harvested.spacingCm, planting.spacingCm);
      final updated = garden.copyWith(
        seasons: [
          for (final s in garden.seasons)
            s.year == 2028 ? s.copyWith(plantings: [harvested]) : s,
        ],
      );
      expect(gardenVisiblePlantings(updated, 2028, planting.areaId), isEmpty);
      expect(
        gardenAreaHistory(updated, planting.areaId).first.plantings.single.id,
        planting.id,
      );
      expect(gardenVisualGrowth(harvested, DateTime(2028, 9, 5)), 0);
      expect(
        harvested.copyWith(harvested: false).harvestAt,
        harvested.harvestAt,
      );
      expect(
        () => harvestGardenPlanting(planting, DateTime(2028, 2, 1)),
        throwsFormatException,
      );
    },
  );
  test(
    'metric gaps use edges and physical axes with diagonal overlap and legacy cases',
    () {
      final garden = old.garden().copyWith(widthMeters: 10, heightMeters: 8);
      final a = old.area(x: .1, width: .2).copyWith(y: .1, height: .2);
      final b = a.copyWith(x: .5);
      expect(gardenBedGapMeters(garden, a, b), closeTo(2, .00001));
      expect(
        gardenBedGapMeters(garden, a, b.copyWith(y: .6)),
        closeTo(3.12409987, .00001),
      );
      expect(gardenBedGapMeters(garden, a, a), 0);
      expect(gardenBedGapMeters(old.garden(), a, b), isNull);
    },
  );
  test('shared scene requires record6 before creating an outbox operation', () {
    final payload = clone(sceneGarden().toJson());
    expect(sharedPayloadContractVersion('garden', payload), 6);
    expect(
      () => validateSharedPayload(
        SharedRecordType.garden,
        payload,
        contractVersion: 5,
      ),
      throwsA(
        isA<CollaborationException>().having(
          (e) => e.code,
          'code',
          'client_upgrade_required',
        ),
      ),
    );
    validateSharedPayload(SharedRecordType.garden, payload, contractVersion: 6);
    expect(
      sharedPayloadContractVersion('garden', clone(old.garden().toJson())),
      4,
    );
  });
  test(
    'real SQLite reopen persists metrics and harvested history with stale-write protection',
    () async {
      final directory = await Directory.systemTemp.createTemp('garden-scene-');
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/garden.db');
      var db = CollaborationDatabase(NativeDatabase(file));
      var repo = GardenRepository(GardenStorage(db));
      await repo.initialize();
      final source = sceneGarden();
      await repo.createGarden(
        name: source.name,
        widthMeters: source.widthMeters,
        heightMeters: source.heightMeters,
        areas: source.areas,
        seasons: source.seasons,
      );
      final stale = repo.snapshot.gardens.single;
      final planting = stale.seasonForYear(2028)!.plantings.single;
      await repo.savePlanting(
        stale,
        2028,
        harvestGardenPlanting(planting, DateTime(2028, 9, 4)),
      );
      final expected = repo.snapshot.gardens.single.toJson();
      await expectLater(
        repo.updateGarden(stale),
        throwsA(isA<OrganizerConflictException>()),
      );
      await repo.close();
      await db.close();
      db = CollaborationDatabase(NativeDatabase(file));
      repo = GardenRepository(GardenStorage(db));
      await repo.initialize();
      expect(repo.snapshot.gardens.single.toJson(), expected);
      expect(await db.rows('SELECT * FROM outbox'), isEmpty);
      await repo.close();
      await db.close();
    },
  );
  for (final kind in ['archived', 'bound', 'deleted']) {
    test(
      '$kind local household rejects stale garden writes atomically',
      () async {
        final client = await old.client();
        final spaces = LocalSpacesRepository(client.db);
        final household = await spaces.createSpace(
          kind: LocalSpaceKind.household,
          name: 'Local garden owner',
        );
        await spaces.selectSpace(household.id);
        await client.garden.reload();
        await client.garden.createGarden(
          name: 'Preserved garden',
          widthMeters: 8,
          heightMeters: 10,
        );
        final snapshot = client.garden.snapshot;
        final stale = snapshot.gardens.single;
        final storage = GardenStorage(client.db);
        if (kind == 'archived') {
          await spaces.archiveSpace(household.id, archived: true);
          expect(
            (await storage.read()).gardens.single.toJson(),
            stale.toJson(),
          );
        } else if (kind == 'deleted') {
          await spaces.deleteSpace(
            await spaces.previewSpaceDeletion(household.id),
          );
          expect(client.db.selectedLocalWorkspaceId, 'local');
          expect(await client.db.rows('SELECT * FROM device_gardens'), isEmpty);
        } else {
          await client.db.execute('UPDATE local_spaces SET data=? WHERE id=?', [
            jsonEncode({
              ...household.toJson(),
              'binding': {'partition': 'account:test', 'scopeId': 'scope:test'},
            }),
            household.id,
          ]);
        }
        final after = await client.db.rows(
          'SELECT payload FROM device_gardens',
        );
        await expectLater(
          client.garden.updateGarden(stale.copyWith(name: 'Stale change')),
          throwsA(isA<OrganizerConflictException>()),
        );
        // Even a writer with a fresh collection revision must respect the catalog.
        // Deleted scope selection is deliberately stale to exercise that guard.
        if (kind == 'deleted') client.db.activateLocalWorkspace(household.id);
        final revision = (await storage.readAll()).revision;
        await expectLater(
          storage.write(snapshot, expectedRevision: revision),
          throwsA(isA<OrganizerConflictException>()),
        );
        expect(
          await client.db.rows('SELECT payload FROM device_gardens'),
          after,
        );
        expect(await client.db.rows('SELECT * FROM outbox'), isEmpty);
      },
    );
  }
  test(
    'JSON and encrypted standalone restore preserve v3 including harvest without server',
    () async {
      final source = await old.client(),
          target = await old.client(),
          targetJson = await old.client();
      final rich = sceneGarden();
      await source.garden.createGarden(
        name: rich.name,
        widthMeters: 12,
        heightMeters: 8,
        areas: rich.areas,
        seasons: rich.seasons,
      );
      final before = source.garden.snapshot.gardens.single;
      await source.garden.savePlanting(
        before,
        2028,
        harvestGardenPlanting(
          before.seasonForYear(2028)!.plantings.single,
          DateTime(2028, 9, 10),
        ),
      );
      final saved = source.garden.snapshot.gardens.single;
      final json = await source.personal.exportBackup();
      await targetJson.personal.importBackup(json);
      expect(
        (await GardenStorage(targetJson.db).read()).gardens.single.toJson(),
        saved.toJson(),
      );
      const password = 'Garden scene portable backup passphrase';
      final bytes = await source.backup.exportEncryptedBackup(password);
      final document = await source.backup.crypto.decrypt(bytes, password);
      validateBackupDocument(document);
      expect(document['gardens']['version'], 3);
      await target.backup.restoreEncryptedBackup(
        bytes,
        password,
        mode: BackupRestoreMode.replace,
        expectedPersonalRevision: (await target.storage.read()).revision,
      );
      final restored = (await GardenStorage(target.db).read()).gardens.single;
      expect(restored.toJson(), saved.toJson());
      expect(gardenVisiblePlantings(restored, 2028, old.areaId), isEmpty);
      expect(gardenAreaHistory(restored, old.areaId).length, 3);
    },
  );
}
