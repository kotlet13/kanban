import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/idea_repository.dart';
import 'package:kanban/organizer/data/idea_storage.dart';
import 'package:kanban/organizer/data/local_spaces_repository.dart';
import 'package:kanban/organizer/data/organizer_repository.dart';
import 'package:kanban/organizer/data/sqlite_organizer_storage.dart';
import 'package:kanban/organizer/data/reminder_snooze_store.dart';
import 'package:kanban/organizer/data/portable_backup_repository.dart';
import 'package:kanban/organizer/data/portable_backup_crypto.dart';
import 'package:kanban/organizer/domain/idea_models.dart';
import 'package:kanban/organizer/domain/organizer_projections.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:kanban/organizer/domain/shared_payload_validation.dart';
import 'package:kanban/organizer/domain/local_space_models.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;

const bid = '11111111-1111-4111-8111-111111111111';
const eid = '22222222-2222-4222-8222-222222222222';
final now = DateTime.utc(2026, 10, 14, 12);
IdeaBoard board() => IdeaBoard(
  id: bid,
  title: 'Idea',
  createdAt: now,
  updatedAt: now,
  elements: [
    IdeaElement(
      id: eid,
      kind: IdeaElementKind.text,
      x: 100,
      y: 100,
      width: 400,
      height: 200,
      text: 'Text',
    ),
  ],
);
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  test(
    'all-spaces lifecycle acts on explicit local source and rejects stale/archived access',
    () async {
      final db = CollaborationDatabase(NativeDatabase.memory());
      final storage = SqliteOrganizerStorage(db);
      await storage.initialize();
      final catalog = LocalSpacesRepository(db);
      await catalog.read();
      final space = await catalog.createSpace(
        kind: LocalSpaceKind.household,
        name: 'Household',
      );
      db.activateLocalWorkspace(space.id);
      final repo = IdeaRepository(IdeaStorage(db), clock: () => now);
      await repo.initialize();
      await repo.saveBoard(board(), isNew: true);
      final before = repo.snapshot.boards.single;
      db.activateLocalWorkspace('local');
      await changeLocalIdeaLifecycle(db, space.id, before, delete: false);
      expect(db.selectedLocalWorkspaceId, 'local');
      final archived = (await IdeaStorage(db).readAll()).boards.single;
      expect(archived.archived, true);
      await expectLater(
        () => changeLocalIdeaLifecycle(db, space.id, before, delete: true),
        throwsA(isA<OrganizerConflictException>()),
      );
      await db.execute('UPDATE local_spaces SET data=? WHERE id=?', [
        jsonEncode({...space.toJson(), 'archived': true}),
        space.id,
      ]);
      await expectLater(
        () => changeLocalIdeaLifecycle(db, space.id, archived, delete: true),
        throwsA(isA<OrganizerConflictException>()),
      );
      await repo.close();
      await db.close();
    },
  );

  test(
    'legacy exact JSON retained, persisted font and archive negotiate6, strict fields fenced',
    () {
      final legacy = board();
      expect(legacy.toJson()['version'], 1);
      expect(legacy.toJson().containsKey('archived'), false);
      expect(legacy.elements.single.toJson().containsKey('fontSize'), false);
      final rich = legacy.copyWith(
        archived: true,
        elements: [legacy.elements.single.copyWith(fontSize: 44)],
      );
      final parsed = IdeaBoard.fromJson(
        Map<String, dynamic>.from(jsonDecode(jsonEncode(rich.toJson()))),
      );
      expect(parsed.archived, true);
      expect(parsed.elements.single.fontSize, 44);
      expect(
        parsed
            .copyWith(
              archived: false,
              elements: [parsed.elements.single.copyWith(fontSize: 22)],
            )
            .toJson()['version'],
        2,
      );
      expect(sharedPayloadContractVersion('idea', parsed.toJson()), 6);
      expect(
        () => validateSharedPayload(
          SharedRecordType.idea,
          Map.from(parsed.toJson()),
          contractVersion: 5,
        ),
        throwsA(isA<CollaborationException>()),
      );
      validateSharedPayload(
        SharedRecordType.idea,
        Map.from(parsed.toJson()),
        contractVersion: 6,
      );
      expect(
        () => IdeaBoard.fromJson({...parsed.toJson(), 'version': 1}),
        throwsFormatException,
      );
      expect(
        () => parsed
            .copyWith(
              elements: [parsed.elements.single.copyWith(fontSize: double.nan)],
            )
            .validate(),
        throwsFormatException,
      );
    },
  );
  test(
    'three-way archive and text size merge independent edits and retain competing sizes',
    () {
      final base = board();
      final local = base.copyWith(archived: true);
      final remote = base.copyWith(
        elements: [base.elements.single.copyWith(fontSize: 44)],
      );
      final merged = mergeIdeaBoards(base, local, remote);
      expect(merged.archived, true);
      expect(merged.elements.single.fontSize, 44);
      expect(
        () => mergeIdeaBoards(
          base,
          base.copyWith(
            elements: [base.elements.single.copyWith(fontSize: 33)],
          ),
          remote,
        ),
        throwsA(isA<IdeaMergeConflict>()),
      );
    },
  );
  test(
    'photo annotation font uses normalized units and survives exact roundtrip',
    () {
      final asset = IdeaAsset(
        sha256: 'a' * 64,
        mime: 'image/png',
        size: 12,
        width: 200,
        height: 100,
      );
      final image = IdeaElement(
        id: eid,
        kind: IdeaElementKind.image,
        x: 10,
        y: 10,
        width: 400,
        height: 200,
        asset: asset,
      );
      final note = IdeaElement(
        id: '33333333-3333-4333-8333-333333333333',
        kind: IdeaElementKind.sticky,
        x: .1,
        y: .1,
        width: .6,
        height: .5,
        parentImageId: eid,
        text: 'Photo note',
        fontSize: .13,
      );
      final parsed = IdeaBoard.fromJson(
        Map.from(board().copyWith(elements: [image, note]).toJson()),
      );
      expect(parsed.elements.last.fontSize, .13);
      parsed.validate();
    },
  );
  test(
    'local relative persists, moves before delivery, appears early in center, cancels completion and never resurrects',
    () async {
      var clock = now;
      final db = CollaborationDatabase(NativeDatabase.memory());
      final storage = SqliteOrganizerStorage(db);
      final repo = OrganizerRepository(storage, clock: () => clock);
      await repo.initialize();
      await LocalSpacesRepository(db).read();
      await repo.createTask(
        title: 'Task',
        dueAt: now.add(const Duration(days: 2)),
      );
      final id = repo.snapshot.tasks.single.id;
      final store = ReminderSnoozeStore(db, clock: () => clock);
      List<ReminderPlan> plans() => desiredReminderPlans(
        personal: repo.snapshot,
        shared: CollaborationState(),
      );
      await store.setDeadlineOffset(
        plans().single,
        60,
        stillCurrent: () => true,
      );
      expect(
        (await store.resolveDeadlineOffsets(plans())).single.scheduledAt,
        now.add(const Duration(days: 2, hours: -1)),
      );
      await repo.reload();
      await repo.updateTask(
        repo.snapshot.tasks.single.copyWith(
          dueAt: now.add(const Duration(days: 3)),
        ),
      );
      expect(
        (await store.resolveDeadlineOffsets(plans())).single.scheduledAt,
        now.add(const Duration(days: 3, hours: -1)),
      );
      clock = now.add(const Duration(days: 3, hours: -1));
      await store.resolveDeadlineOffsets(plans());
      await repo.reload();
      await repo.refreshReminders();
      expect(repo.snapshot.reminders, hasLength(1));
      expect(repo.snapshot.tasks.single.dueAt!.isAfter(clock), true);
      await repo.reload();
      await repo.updateTask(
        repo.snapshot.tasks.single.copyWith(
          dueAt: now.add(const Duration(days: 4)),
        ),
      );
      expect(await store.resolveDeadlineOffsets(plans()), isEmpty);
      await store.setDeadlineOffset(
        plans().single,
        1440,
        stillCurrent: () => true,
      );
      await repo.reload();
      await repo.setTaskCompleted(id, true);
      await store.resolveDeadlineOffsets(plans());
      await repo.setTaskCompleted(id, false);
      expect(await store.resolveDeadlineOffsets(plans()), isEmpty);
      await store.setDeadlineOffset(
        plans().single,
        0,
        stillCurrent: () => true,
      );
      await repo.reload();
      await repo.updateTask(repo.snapshot.tasks.single.copyWith(dueAt: null));
      await store.resolveDeadlineOffsets(plans());
      await repo.reload();
      await repo.updateTask(
        repo.snapshot.tasks.single.copyWith(
          dueAt: now.add(const Duration(days: 5)),
        ),
      );
      expect(await store.resolveDeadlineOffsets(plans()), isEmpty);
      await repo.close();
      await db.close();
    },
  );
  test(
    'encrypted content6 restores archive, font-size, draft and task-relative preferences independently',
    () async {
      final db = CollaborationDatabase(NativeDatabase.memory());
      final storage = SqliteOrganizerStorage(db);
      final repo = OrganizerRepository(storage, clock: () => now);
      await repo.initialize();
      await LocalSpacesRepository(db).read();
      final ideas = IdeaRepository(IdeaStorage(db), clock: () => now);
      await ideas.initialize();
      final rich = board().copyWith(
        archived: true,
        elements: [board().elements.single.copyWith(fontSize: 44)],
      );
      await ideas.saveBoard(rich, isNew: true);
      await ideas.saveDraft(rich);
      await repo.reload();
      await repo.createTask(
        title: 'Task',
        dueAt: now.add(const Duration(days: 2)),
      );
      final plans = desiredReminderPlans(
        personal: repo.snapshot,
        shared: CollaborationState(),
      );
      await ReminderSnoozeStore(
        db,
        clock: () => now,
      ).setDeadlineOffset(plans.single, 60, stillCurrent: () => true);
      final crypto = PortableBackupCrypto();
      final backup = PortableBackupRepository(
        db,
        storage,
        MemoryBackupUiPreferencesStore(),
        crypto: crypto,
      );
      final bytes = await backup.exportEncryptedBackup('synthetic-password');
      final doc = await crypto.decrypt(bytes, 'synthetic-password');
      expect(doc['version'], 7);
      expect(doc['databaseVersion'], 10);
      expect(doc['localTaskReminderPreferences'], hasLength(1));
      final restored = CollaborationDatabase(NativeDatabase.memory());
      final restStorage = SqliteOrganizerStorage(restored);
      await restStorage.initialize();
      final restBackup = PortableBackupRepository(
        restored,
        restStorage,
        MemoryBackupUiPreferencesStore(),
        crypto: crypto,
      );
      await restBackup.restoreEncryptedBackup(
        bytes,
        'synthetic-password',
        mode: BackupRestoreMode.replace,
        expectedPersonalRevision: (await restStorage.read()).revision,
      );
      final recovered = await IdeaStorage(restored).readAll();
      expect(recovered.boards.single.archived, true);
      expect(recovered.boards.single.elements.single.fontSize, 44);
      final snapshot = await restStorage.read();
      final effective = await ReminderSnoozeStore(restored, clock: () => now)
          .resolveDeadlineOffsets(
            desiredReminderPlans(
              personal: snapshot,
              shared: CollaborationState(),
            ),
          );
      expect(
        effective.single.scheduledAt,
        snapshot.tasks.single.dueAt!.subtract(const Duration(hours: 1)),
      );
      await ideas.close();
      await repo.close();
      await db.close();
      await restored.close();
    },
  );
}
