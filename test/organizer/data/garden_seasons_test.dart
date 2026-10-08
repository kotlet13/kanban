import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/garden_repository.dart';
import 'package:kanban/organizer/data/garden_storage.dart';
import 'package:kanban/organizer/data/organizer_repository.dart';
import 'package:kanban/organizer/data/organizer_storage.dart';
import 'package:kanban/organizer/data/portable_backup_document.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart'
    show BackupRestoreMode;
import 'package:kanban/organizer/domain/garden_models.dart';
import 'package:kanban/organizer/domain/garden_rotation.dart';

import 'garden_repository_test.dart' as original;

String plantingId(int value) =>
    '33333333-3333-4333-8333-${value.toRadixString(16).padLeft(12, '0')}';
const otherAreaId = '44444444-4444-4444-8444-444444444444';
GardenPlanting planting({
  int id = 1,
  String areaId = original.areaId,
  String family = 'Solanaceae',
  GardenPlantingStatus status = GardenPlantingStatus.actual,
}) => GardenPlanting(
  id: plantingId(id),
  areaId: areaId,
  crop: 'Paradižnik',
  variety: 'Volovsko srce',
  family: family,
  status: status,
  sowAt: DateTime(2026, 3, 2),
  plantAt: DateTime(2026, 5, 10),
  harvestAt: DateTime(2026, 8, 20),
  notes: 'Lastne opombe 🌱',
);
Garden richGarden() => original.garden().copyWith(
  seasons: [
    GardenSeason(year: 2026, notes: 'Prvo leto', plantings: [planting()]),
    GardenSeason(
      year: 2027,
      notes: 'Naslednji načrt',
      plantings: [
        planting(id: 2, status: GardenPlantingStatus.planned).copyWith(
          crop: 'Paprika',
          variety: '',
          clearSowAt: true,
          clearPlantAt: true,
          clearHarvestAt: true,
        ),
        planting(
          id: 3,
          family: 'Fabaceae',
          status: GardenPlantingStatus.planned,
        ).copyWith(
          crop: 'Fižol',
          variety: 'Nizek',
          clearSowAt: true,
          clearPlantAt: true,
          clearHarvestAt: true,
        ),
      ],
    ),
  ],
);

/// Genuine old payload: no seasons, version marker, kind or archive fields.
Map<String, dynamic> legacyGarden() => {
  'id': original.gardenId,
  'name': 'Ohranjen vrt',
  'notes': 'Izvirna opomba',
  'areas': [
    {
      'id': original.areaId,
      'label': 'Moja prvotna greda',
      'x': 0.1,
      'y': 0.2,
      'width': 0.4,
      'height': 0.3,
    },
  ],
  'revision': 7,
  'createdAt': original.now.toIso8601String(),
  'updatedAt': original.now.toIso8601String(),
};
Map<String, dynamic> legacySnapshot() => {
  'version': 1,
  'revision': 2,
  'gardens': [legacyGarden()],
};

/// These exact guards are the original v1 reader's contract. A current garden
/// section is rejected before fields could be dropped by an older application.
void originalVersionOneGuard(Map<String, dynamic> json) {
  if (json['version'] != 1 ||
      json.length != 3 ||
      json.keys.toSet().difference({
        'version',
        'revision',
        'gardens',
      }).isNotEmpty) {
    throw const FormatException('Unsupported garden data');
  }
  for (final raw in json['gardens'] as List) {
    final garden = raw as Map<String, dynamic>;
    const fields = {
      'id',
      'name',
      'notes',
      'areas',
      'revision',
      'createdAt',
      'updatedAt',
    };
    if (garden.length != fields.length ||
        garden.keys.toSet().difference(fields).isNotEmpty) {
      throw const FormatException('Unsupported garden field');
    }
  }
}

Map<String, dynamic> jsonMap(Object? value) =>
    jsonDecode(jsonEncode(value)) as Map<String, dynamic>;
List<Map<String, Object?>> seasonJson(Garden garden) =>
    garden.seasons.map((s) => s.toJson()).toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test(
    'old payloads and snapshots retain IDs, coordinates and text; old reader rejects new section',
    () {
      originalVersionOneGuard(legacySnapshot());
      final migrated = GardenSnapshot.fromJson(legacySnapshot());
      final garden = migrated.gardens.single;
      expect(garden.id, original.gardenId);
      expect(garden.revision, 7);
      expect(garden.name, 'Ohranjen vrt');
      expect(garden.notes, 'Izvirna opomba');
      expect(garden.seasons, isEmpty);
      final area = garden.areas.single;
      expect(
        (area.id, area.x, area.y, area.width, area.height),
        (original.areaId, 0.1, 0.2, 0.4, 0.3),
      );
      expect(area.kind, GardenAreaKind.bed);
      expect(area.archived, isFalse);
      final upgraded = jsonMap(migrated.toJson());
      expect(upgraded['version'], 2);
      expect(() => originalVersionOneGuard(upgraded), throwsFormatException);
      expect(GardenSnapshot.fromJson(upgraded).toJson(), migrated.toJson());
      final payload = jsonMap(richGarden().toJson());
      expect(
        () => originalVersionOneGuard({
          'version': 1,
          'revision': 0,
          'gardens': [payload],
        }),
        throwsFormatException,
      );
    },
  );

  test(
    'every seasonal field and date-only value roundtrips; copy preserves and clears explicitly',
    () {
      final expected = richGarden();
      final actual = Garden.fromJson(jsonMap(expected.toJson()));
      expect(actual.toJson(), expected.toJson());
      final first = actual.seasons.first.plantings.single;
      expect(first.toJson()['sowAt'], '2026-03-02');
      expect(first.toJson()['plantAt'], '2026-05-10');
      expect(first.toJson()['harvestAt'], '2026-08-20');
      expect(first.notes, 'Lastne opombe 🌱');
      expect(first.variety, 'Volovsko srce');
      expect(first.family, 'Solanaceae');
      expect(first.status, GardenPlantingStatus.actual);
      expect(first.sowAt, DateTime.utc(2026, 3, 2));
      expect(first.copyWith(crop: 'Druga kultura').sowAt, first.sowAt);
      expect(first.copyWith(clearSowAt: true).sowAt, isNull);
      expect(
        seasonJson(actual.copyWith(name: 'Drugo ime')),
        seasonJson(expected),
      );
      expect(
        () => actual.seasons.add(GardenSeason(year: 2028)),
        throwsUnsupportedError,
      );
      expect(
        () => actual.seasons.first.plantings.add(planting(id: 99)),
        throwsUnsupportedError,
      );
    },
  );

  test(
    'calendar dates remain UTC date-only at a local midnight DST transition',
    () {
      final original = planting().copyWith(
        sowAt: DateTime.utc(2018, 11, 4),
        plantAt: DateTime.utc(2018, 11, 5),
        harvestAt: DateTime.utc(2019, 2, 15),
      );
      final restored = GardenPlanting.fromJson(jsonMap(original.toJson()));
      for (final value in [
        restored.sowAt!,
        restored.plantAt!,
        restored.harvestAt!,
      ]) {
        expect(value.isUtc, isTrue);
        expect(value.hour, 0);
      }
      expect(restored.sowAt, DateTime.utc(2018, 11, 4));
      expect(restored.toJson(), original.toJson());
      restored.validate();
    },
  );

  test(
    'strict v2 parsing rejects missing, unknown, newer, duplicate and orphan seasonal content',
    () {
      final valid = GardenSnapshot(gardens: [richGarden()]).toJson();
      for (final mutate in <void Function(Map<String, dynamic>)>[
        (j) => j['version'] = 3,
        (j) => j['version'] = 2.0,
        (j) => j['version'] = 1,
        (j) => j['gardens'][0]['version'] = 3,
        (j) => j['gardens'][0].remove('seasons'),
        (j) => j['gardens'][0]['areas'][0].remove('archived'),
        (j) => j['gardens'][0]['areas'][0]['kind'] = 'unknown',
        (j) => j['gardens'][0]['seasons'][0]['year'] = 1899,
        (j) => j['gardens'][0]['seasons'][0]['year'] = 10000,
        (j) => j['gardens'][0]['seasons'][1]['year'] = 2026,
        (j) => j['gardens'][0]['seasons'][0]['plantings'][0]['areaId'] =
            otherAreaId,
        (j) => j['gardens'][0]['seasons'][0]['plantings'][0]['sowAt'] =
            '2026-02-30',
        (j) => j['gardens'][0]['seasons'][0]['plantings'][0]['sowAt'] =
            '2026-03-02T00:00:00Z',
        (j) => j['gardens'][0]['seasons'][0]['plantings'][0]['plantAt'] =
            '2026-02-01',
        (j) => j['gardens'][0]['seasons'][0]['plantings'][0]['harvestAt'] =
            '2026-03-01',
        (j) =>
            j['gardens'][0]['seasons'][0]['plantings'][0]['status'] = 'unknown',
        (j) => j['gardens'][0]['seasons'][0]['plantings'][0]['crop'] = ' ',
        (j) => j['gardens'][0]['seasons'][0]['plantings'][0]['variety'] =
            'a' * 201,
        (j) =>
            j['gardens'][0]['seasons'][0]['plantings'][0]['family'] = 'a' * 201,
        (j) => j['gardens'][0]['seasons'][0]['plantings'][0]['notes'] =
            'a' * 20001,
        (j) =>
            j['gardens'][0]['seasons'][0]['plantings'][0]['futureField'] = true,
        (j) =>
            j['gardens'][0]['seasons'][1]['plantings'][0]['id'] = plantingId(1),
        (j) => j['gardens'][0]['seasons'][0]['plantings'].add(
          j['gardens'][0]['seasons'][0]['plantings'][0],
        ),
      ]) {
        final changed = jsonMap(valid);
        mutate(changed);
        expect(() => GardenSnapshot.fromJson(changed), throwsFormatException);
      }
      expect(
        () => planting().copyWith(sowAt: DateTime(2026, 3, 2, 12)).validate(),
        throwsFormatException,
      );
      // A winter crop can be sown in the previous year and harvested next year.
      planting()
          .copyWith(
            sowAt: DateTime(2025, 11, 2),
            harvestAt: DateTime(2027, 1, 2),
          )
          .validate();
    },
  );

  test(
    'season, planting and aggregate byte limits are enforced before persistence',
    () {
      expect(
        () => original
            .garden()
            .copyWith(
              seasons: [
                for (var i = 0; i < 501; i++) GardenSeason(year: 1900 + i),
              ],
            )
            .validate(),
        throwsFormatException,
      );
      expect(
        () => GardenSeason(
          year: 2026,
          plantings: [for (var i = 0; i < 2001; i++) planting(id: i)],
        ).validate(),
        throwsFormatException,
      );
      expect(
        () => original
            .garden()
            .copyWith(
              seasons: [
                for (var year = 2020; year < 2026; year++)
                  GardenSeason(
                    year: year,
                    plantings: [
                      for (var i = 0; i < 1800; i++)
                        planting(id: (year - 2020) * 1800 + i),
                    ],
                  ),
              ],
            )
            .validate(),
        throwsFormatException,
      );
      expect(
        () => GardenSnapshot(
          gardens: [
            original.garden().copyWith(
              seasons: [
                GardenSeason(
                  year: 2026,
                  plantings: [
                    for (var i = 0; i < 400; i++)
                      planting(id: i).copyWith(notes: 'ž' * 20000),
                  ],
                ),
              ],
            ),
          ],
        ).validate(),
        throwsFormatException,
      );
    },
  );

  test(
    'SQLite opens genuine old rows then persists seasons, archived geometry and reopens offline',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'jivie-garden-seasons-',
      );
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/garden.sqlite');
      var db = CollaborationDatabase(NativeDatabase(file));
      await db.execute('INSERT INTO device_gardens(id,payload) VALUES(?,?)', [
        original.gardenId,
        jsonEncode(legacyGarden()),
      ]);
      var repo = GardenRepository(GardenStorage(db), clock: () => original.now);
      await repo.initialize();
      final legacy = repo.snapshot.gardens.single;
      expect(legacy.seasons, isEmpty);
      await repo.updateGarden(
        legacy.copyWith(
          areas: [legacy.areas.single.copyWith(archived: true)],
          seasons: richGarden().seasons,
        ),
      );
      final expected = repo.snapshot.toJson();
      expect(await db.rows('SELECT * FROM outbox'), isEmpty);
      expect(await db.rows('SELECT * FROM personal_record_map'), isEmpty);
      await repo.close();
      await db.close();
      db = CollaborationDatabase(NativeDatabase(file));
      repo = GardenRepository(GardenStorage(db), clock: () => original.now);
      try {
        await repo.initialize();
        expect(repo.snapshot.toJson(), expected);
        final restored = repo.snapshot.gardens.single;
        expect(restored.areas.single.archived, isTrue);
        expect(restored.areas.single.x, 0.1);
        expect(
          gardenAreaHistory(restored, original.areaId).map((h) => h.year),
          [2027, 2026],
        );
        expect(gardenRotationWarnings(restored, 2027).single.previousYears, [
          2026,
        ]);
        expect((await db.rows('PRAGMA user_version')).single.values.single, 6);
      } finally {
        await repo.close();
        await db.close();
      }
    },
  );

  test(
    'removing referenced area is rejected; archiving retains its complete history',
    () async {
      final c = await original.client();
      await c.garden.createGarden(
        name: 'Vrt',
        areas: richGarden().areas,
        seasons: richGarden().seasons,
      );
      final before = c.garden.snapshot.gardens.single;
      await expectLater(
        c.garden.updateGarden(before.copyWith(areas: [])),
        throwsFormatException,
      );
      expect(
        (await GardenStorage(c.db).read()).gardens.single.toJson(),
        before.toJson(),
      );
      await c.garden.updateGarden(
        before.copyWith(areas: [before.areas.single.copyWith(archived: true)]),
      );
      final archived = c.garden.snapshot.gardens.single;
      expect(seasonJson(archived), seasonJson(before));
      expect(archived.areas.single.id, before.areas.single.id);
      expect(gardenAreaHistory(archived, original.areaId).length, 2);
    },
  );

  test(
    'concurrent season edits reject stale snapshots and preserve unrelated garden writes',
    () async {
      final c = await original.client();
      await c.garden.createGarden(
        name: 'Prvi vrt',
        areas: richGarden().areas,
        seasons: richGarden().seasons,
      );
      final stale = c.garden.snapshot.gardens.single;
      final other = GardenRepository(GardenStorage(c.db));
      await other.initialize();
      addTearDown(other.close);
      await other.createGarden(name: 'Drugi vrt');
      await other.saveSeason(
        stale,
        stale.seasons.first.copyWith(notes: 'Novejša sezona'),
      );
      await expectLater(
        c.garden.savePlanting(stale, 2026, planting(id: 91)),
        throwsA(isA<OrganizerConflictException>()),
      );
      await expectLater(
        c.garden.deleteSeason(stale, 2026),
        throwsA(isA<OrganizerConflictException>()),
      );
      await c.garden.reload();
      final saved = c.garden.snapshot.gardens.firstWhere(
        (g) => g.id == stale.id,
      );
      expect(saved.seasonForYear(2026)!.notes, 'Novejša sezona');
      expect(c.garden.snapshot.gardens.length, 2);
      await c.garden.savePlanting(saved, 2026, planting(id: 91));
      final withExtra = c.garden.snapshot.gardens.firstWhere(
        (g) => g.id == stale.id,
      );
      expect(withExtra.seasonForYear(2026)!.plantings.length, 2);
      await c.garden.deletePlanting(withExtra, 2026, plantingId(91));
      expect(
        c.garden.snapshot.gardens
            .firstWhere((g) => g.id == stale.id)
            .seasonForYear(2026)!
            .plantings
            .length,
        1,
      );
    },
  );

  test(
    'rotation warning uses same bed, recognized aliases, actual previous planting, and precise year window',
    () {
      final garden = original.garden();
      final otherArea = GardenArea(
        id: otherAreaId,
        label: 'Druga',
        x: 0.6,
        y: 0.2,
        width: 0.3,
        height: 0.3,
      );
      final seasons = <GardenSeason>[];
      for (final year in [2020, 2023, 2024, 2025, 2026, 2027, 2028]) {
        seasons.add(
          GardenSeason(
            year: year,
            plantings: [
              planting(
                id: year,
                family: year == 2023 ? 'raZhudnikovke' : ' Solanaceae ',
              ).copyWith(
                clearSowAt: true,
                clearPlantAt: true,
                clearHarvestAt: true,
              ),
              planting(
                id: year + 100,
                family: 'Fabaceae',
                areaId: otherAreaId,
              ).copyWith(
                clearSowAt: true,
                clearPlantAt: true,
                clearHarvestAt: true,
              ),
              planting(
                id: year + 200,
                family: 'Fabaceae',
                status: GardenPlantingStatus.planned,
              ).copyWith(
                clearSowAt: true,
                clearPlantAt: true,
                clearHarvestAt: true,
              ),
            ],
          ),
        );
      }
      final candidate = garden.copyWith(
        areas: [original.area(), otherArea],
        seasons: seasons,
      );
      candidate.validate();
      final warnings = gardenRotationWarnings(candidate, 2026);
      expect(
        warnings.where((w) => w.areaId == original.areaId).map((w) => w.family),
        ['Solanaceae'],
      );
      expect(warnings.first.previousYears, [2025, 2024, 2023]);
      expect(
        gardenRotationWarnings(
          candidate,
          2026,
          lookbackYears: 1,
        ).first.previousYears,
        [2025],
      );
      expect(
        () => gardenRotationWarnings(candidate, 2026, lookbackYears: 0),
        throwsArgumentError,
      );
      expect(gardenAreaHistory(candidate, otherAreaId).map((h) => h.year), [
        2028,
        2027,
        2026,
        2025,
        2024,
        2023,
        2020,
      ]);
      expect(knownGardenFamily('  razhudnikovke  '), 'Solanaceae');
      expect(knownGardenFamily('Nedoločena družina'), isNull);
      expect(knownGardenFamily(''), isNull);
      expect(knownGardenFamily('Bučevke'), 'Cucurbitaceae');
      expect(knownGardenFamily('bučovke'), 'Cucurbitaceae');
      expect(knownGardenFamily('Narcisovke'), 'Amaryllidaceae');
      final unknown = original.garden().copyWith(
        seasons: [
          GardenSeason(
            year: 2025,
            plantings: [planting(family: 'Moja družina')],
          ),
          GardenSeason(
            year: 2026,
            plantings: [planting(id: 2, family: 'Moja družina')],
          ),
        ],
      );
      expect(gardenRotationWarnings(unknown, 2026), isEmpty);
      expect(gardenRotationWarnings(candidate, 2030), isEmpty);
    },
  );

  test(
    'JSON and encrypted copies preserve all seasons, multi-crop rows, archive flags and stale editor protection',
    () async {
      final source = await original.client(),
          jsonTarget = await original.client(),
          encryptedTarget = await original.client();
      final rich = richGarden().copyWith(
        areas: [
          original.area().copyWith(archived: true, kind: GardenAreaKind.zone),
        ],
      );
      await source.garden.createGarden(
        name: rich.name,
        notes: rich.notes,
        areas: rich.areas,
        seasons: rich.seasons,
      );
      final json = await source.personal.exportBackup();
      final document = OrganizerBackupCodec.decodeDocument(json);
      expect(jsonDecode(json)['schemaVersion'], 4);
      expect(document.gardens!.toJson()['version'], 2);
      await jsonTarget.personal.importBackup(json);
      final restoredJson = (await GardenStorage(
        jsonTarget.db,
      ).read()).gardens.single;
      expect(seasonJson(restoredJson), seasonJson(rich));
      expect(restoredJson.areas.single.toJson(), rich.areas.single.toJson());
      const password = 'Seasonal garden backup password';
      final bytes = await source.backup.exportEncryptedBackup(password);
      final decrypted = await source.backup.crypto.decrypt(bytes, password);
      expect(decrypted['version'], 3);
      expect(decrypted['gardens']['version'], 2);
      validateBackupDocument(decrypted);
      await encryptedTarget.backup.restoreEncryptedBackup(
        bytes,
        password,
        mode: BackupRestoreMode.replace,
        expectedPersonalRevision:
            (await encryptedTarget.storage.read()).revision,
      );
      await encryptedTarget.garden.reload();
      final open = encryptedTarget.garden.snapshot.gardens.single;
      expect(seasonJson(open), seasonJson(rich));
      expect(open.areas.single.toJson(), rich.areas.single.toJson());
      await encryptedTarget.garden.deleteGarden(open);
      await encryptedTarget.backup.restoreEncryptedBackup(
        bytes,
        password,
        mode: BackupRestoreMode.replace,
        expectedPersonalRevision:
            (await encryptedTarget.storage.read()).revision,
      );
      await expectLater(
        encryptedTarget.garden.saveSeason(open, GardenSeason(year: 2028)),
        throwsA(isA<OrganizerConflictException>()),
      );
      expect(
        seasonJson(
          (await GardenStorage(encryptedTarget.db).read()).gardens.single,
        ),
        seasonJson(rich),
      );
    },
  );

  test(
    'genuine v1 garden sections restore through existing personal and encrypted formats',
    () async {
      final source = await original.client(), target = await original.client();
      final personalJson =
          jsonDecode(await source.personal.exportBackup())
              as Map<String, dynamic>;
      personalJson['gardens'] = legacySnapshot();
      await target.personal.importBackup(jsonEncode(personalJson));
      final first = (await GardenStorage(target.db).read()).gardens.single;
      expect(first.id, original.gardenId);
      expect(first.seasons, isEmpty);
      expect(first.areas.single.label, 'Moja prvotna greda');
      const password = 'Legacy garden encrypted backup';
      final bytes = await source.backup.exportEncryptedBackup(password);
      final doc = await source.backup.crypto.decrypt(bytes, password);
      doc['gardens'] = legacySnapshot();
      validateBackupDocument(doc);
      final older = await source.backup.crypto.encrypt(doc, password);
      await target.backup.restoreEncryptedBackup(
        older,
        password,
        mode: BackupRestoreMode.replace,
        expectedPersonalRevision: (await target.storage.read()).revision,
      );
      final restored = (await GardenStorage(target.db).read()).gardens.single;
      expect(restored.id, original.gardenId);
      expect(restored.areas.single.id, original.areaId);
      expect(restored.areas.single.archived, isFalse);
      expect(restored.seasons, isEmpty);
    },
  );
}
