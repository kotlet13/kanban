import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/local_spaces_repository.dart';
import 'package:kanban/organizer/data/organizer_repository.dart';
import 'package:kanban/organizer/data/organizer_storage.dart';
import 'package:kanban/organizer/data/sqlite_organizer_storage.dart';
import 'package:kanban/organizer/data/idea_repository.dart';
import 'package:kanban/organizer/data/idea_storage.dart';
import 'package:kanban/organizer/domain/local_space_models.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'package:kanban/organizer/domain/idea_models.dart';

import 'idea_repository_test.dart' show board, id, e1;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late CollaborationDatabase db;
  late SqliteOrganizerStorage storage;
  late LocalSpacesRepository spaces;
  late OrganizerRepository organizer;
  late IdeaRepository ideas;
  setUp(() async {
    db = CollaborationDatabase(NativeDatabase.memory());
    storage = SqliteOrganizerStorage(db);
    await storage.initialize();
    spaces = LocalSpacesRepository(db);
    organizer = OrganizerRepository(storage);
    await organizer.initialize();
    ideas = IdeaRepository(IdeaStorage(db));
    await ideas.initialize();
  });
  tearDown(() async {
    await ideas.close();
    await organizer.close();
    await db.close();
  });
  Future<void> archiveProject(String id, {required bool archived}) =>
      organizer.updateProject(
        organizer.snapshot.projects
            .singleWhere((p) => p.id == id)
            .copyWith(archived: archived),
      );
  Future<LocalSpace> home() async {
    final s = await spaces.createSpace(
      kind: LocalSpaceKind.household,
      name: 'Target household',
    );
    await spaces.selectSpace(s.id);
    await organizer.reload();
    await ideas.reload();
    return s;
  }

  test(
    'local space counted deletion removes its records ideas drafts and photos, preserves personal and siblings',
    () async {
      await organizer.createTask(title: 'Default personal');
      final target = await home();
      await organizer.createProject(title: 'Target project');
      await organizer.createTask(
        title: 'Target task',
        projectId: organizer.snapshot.projects.single.id,
      );
      final asset = await ideas.importImage(
        Uint8List.fromList(img.encodePng(img.Image(width: 3, height: 2))),
      );
      final b = board().copyWith(
        projectId: organizer.snapshot.projects.single.id,
        elements: [
          IdeaElement(
            id: e1,
            kind: IdeaElementKind.image,
            x: 0,
            y: 0,
            width: 30,
            height: 20,
            asset: asset,
          ),
        ],
      );
      await ideas.saveBoard(b, isNew: true);
      await ideas.saveDraft(b, base: b);
      final sibling = await spaces.createSpace(
        kind: LocalSpaceKind.organization,
        name: 'Sibling',
      );
      final preview = await spaces.previewSpaceDeletion(target.id);
      expect((preview['counts'] as Map)['projects'], 1);
      expect((preview['counts'] as Map)['tasks'], 1);
      expect((preview['counts'] as Map)['ideas'], 1);
      expect((preview['counts'] as Map)['photos'], 1);
      expect((preview['counts'] as Map)['drafts'], 1);
      await spaces.deleteSpace(preview);
      expect(db.selectedLocalWorkspaceId, 'local');
      expect(
        (await spaces.read()).spaces.map((s) => s.id),
        contains(sibling.id),
      );
      expect(
        await db.rows('SELECT * FROM idea_assets WHERE workspace=?', [
          target.id,
        ]),
        isEmpty,
      );
      expect(
        await db.rows('SELECT * FROM idea_drafts WHERE workspace=?', [
          target.id,
        ]),
        isEmpty,
      );
      expect(
        await db.rows('SELECT * FROM device_ideas WHERE id=?', [id]),
        isEmpty,
      );
      expect(
        await db.rows('SELECT * FROM personal_records WHERE workspace=?', [
          target.id,
        ]),
        isEmpty,
      );
      await organizer.reload();
      expect(organizer.snapshot.tasks.single.title, 'Default personal');
      expect(
        await db.rows('SELECT value FROM local_meta WHERE name=?', [
          'idea_record_revision:$id',
        ]),
        isNotEmpty,
      );
      expect(
        await db.rows('SELECT value FROM local_meta WHERE name=?', [
          'idea_deleted_revision:$id',
        ]),
        isNotEmpty,
      );
    },
  );

  test(
    'default personal and linked local catalog cannot be destructively deleted',
    () async {
      await expectLater(
        spaces.previewSpaceDeletion('local'),
        throwsA(isA<OrganizerConflictException>()),
      );
      final target = await home();
      await db.execute('UPDATE local_spaces SET data=? WHERE id=?', [
        jsonEncode({
          ...target.toJson(),
          'binding': {'partition': 'synthetic-account', 'scopeId': target.id},
        }),
        target.id,
      ]);
      await expectLater(
        spaces.previewSpaceDeletion(target.id),
        throwsA(isA<OrganizerConflictException>()),
      );
      expect((await spaces.read()).spaces.any((s) => s.id == target.id), true);
    },
  );

  test(
    'local linked payment graph outside selected space blocks entire deletion',
    () async {
      final target = await home();
      await organizer.createTask(title: 'Keep');
      await db.execute(
        'INSERT INTO linked_payment_projections(space_key,event_id,data) VALUES(?,?,?)',
        [
          'local:local',
          'synthetic-event',
          jsonEncode({'sourceScopeId': target.id, 'sourcePartition': null}),
        ],
      );
      final preview = await spaces.previewSpaceDeletion(target.id);
      expect(preview['canDelete'], false);
      await expectLater(
        spaces.deleteSpace(preview),
        throwsA(isA<CollaborationException>()),
      );
      expect((await storage.read()).tasks.single.title, 'Keep');
      expect(
        await db.rows('SELECT * FROM linked_payment_projections'),
        hasLength(1),
      );
    },
  );

  test(
    'local deletion stale preview and actual SQL failure preserve complete graph atomically',
    () async {
      final target = await home();
      await organizer.createTask(title: 'Before');
      final stale = await spaces.previewSpaceDeletion(target.id);
      await organizer.createTask(title: 'After');
      await expectLater(
        spaces.deleteSpace(stale),
        throwsA(isA<CollaborationException>()),
      );
      final fresh = await spaces.previewSpaceDeletion(target.id),
          before = await db.rows(
            'SELECT * FROM personal_records WHERE workspace=?',
            [target.id],
          );
      await db.execute(
        "CREATE TRIGGER fail_scope_delete BEFORE DELETE ON local_spaces BEGIN SELECT RAISE(ABORT,'synthetic rollback'); END",
      );
      await expectLater(spaces.deleteSpace(fresh), throwsA(anything));
      expect(
        await db.rows('SELECT * FROM personal_records WHERE workspace=?', [
          target.id,
        ]),
        before,
      );
      expect(
        await db.rows('SELECT * FROM personal_workspaces WHERE id=?', [
          target.id,
        ]),
        isNotEmpty,
      );
      expect(db.selectedLocalWorkspaceId, target.id);
    },
  );

  test(
    'archiving preserves read data and closes stale organizer writers until restore',
    () async {
      final target = await home();
      await organizer.createTask(title: 'Read history');
      await spaces.archiveSpace(target.id, archived: true);
      expect(
        (await spaces.read()).spaces
            .singleWhere((s) => s.id == target.id)
            .archived,
        true,
      );
      expect((await storage.read()).tasks.single.title, 'Read history');
      await expectLater(
        organizer.createTask(title: 'Must not save'),
        throwsA(isA<OrganizerConflictException>()),
      );
      await spaces.archiveSpace(target.id, archived: false);
      await organizer.reload();
      await organizer.createTask(title: 'Restored');
      expect(organizer.snapshot.tasks, hasLength(2));
    },
  );

  test(
    'counted local project deletion removes own graph and keeps sibling image reference',
    () async {
      await home();
      await organizer.createProject(title: 'Target');
      final pid = organizer.snapshot.projects.single.id;
      await organizer.createTask(title: 'Closed task', projectId: pid);
      await organizer.createTask(title: 'Sibling task');
      final asset = await ideas.importImage(
        Uint8List.fromList(img.encodePng(img.Image(width: 3, height: 2))),
      );
      final picture = IdeaElement(
        id: e1,
        kind: IdeaElementKind.image,
        x: 0,
        y: 0,
        width: 30,
        height: 20,
        asset: asset,
      );
      final original = board().copyWith(projectId: pid, elements: [picture]);
      await ideas.saveBoard(original, isNew: true);
      await ideas.saveDraft(original, base: original);
      final sibling = board().copyWith(
        id: '44444444-4444-4444-8444-444444444444',
        title: 'Sibling board',
        elements: [picture],
      );
      await ideas.saveBoard(sibling, isNew: true);
      await organizer.reload();
      final preview = await organizer.previewProjectDeletion(pid);
      expect((preview['counts'] as Map)['ideas'], 1);
      expect((preview['counts'] as Map)['photos'], 1);
      await organizer.deleteProject(
        pid,
        previewHash: preview['previewHash'] as String,
      );
      await ideas.reload();
      expect(organizer.snapshot.tasks.single.title, 'Sibling task');
      expect(ideas.snapshot.boards.single.id, sibling.id);
      expect(await ideas.readDraft(id), isNull);
      expect(await ideas.readAsset(asset), isNotNull);
    },
  );

  test(
    'archived project closes captured task event finance idea editors but restore and whole delete work',
    () async {
      await home();
      await organizer.createProject(title: 'Archive parent');
      final pid = organizer.snapshot.projects.single.id;
      await organizer.createTask(title: 'Before', projectId: pid);
      final staleTask = organizer.snapshot.tasks.single;
      await organizer.createEvent(
        title: 'Meeting',
        startsAt: DateTime.utc(2026, 10, 15),
        projectId: pid,
      );
      final staleEvent = organizer.snapshot.events.single;
      await organizer.createFinanceEntry(
        title: 'Cost',
        amountMinor: 100,
        currency: 'EUR',
        kind: FinanceEntryKind.expense,
        occurredAt: DateTime.utc(2026),
        projectId: pid,
      );
      final staleFinance = organizer.snapshot.financeEntries.single;
      final b = board().copyWith(projectId: pid);
      await ideas.saveBoard(b, isNew: true);
      final staleBoard = ideas.snapshot.boards.single;
      await organizer.reload();
      await archiveProject(pid, archived: true);
      await expectLater(
        organizer.updateTask(staleTask.copyWith(title: 'Forbidden')),
        throwsA(isA<OrganizerConflictException>()),
      );
      await expectLater(
        organizer.updateEvent(staleEvent.copyWith(title: 'Forbidden')),
        throwsA(isA<OrganizerConflictException>()),
      );
      await expectLater(
        organizer.updateFinanceEntry(staleFinance.copyWith(title: 'Forbidden')),
        throwsA(isA<OrganizerConflictException>()),
      );
      await expectLater(
        organizer.createTask(title: 'Forbidden new', projectId: pid),
        throwsA(isA<OrganizerConflictException>()),
      );
      await expectLater(
        ideas.saveBoard(
          staleBoard.copyWith(title: 'Forbidden'),
          base: staleBoard,
        ),
        throwsA(isA<OrganizerConflictException>()),
      );
      final current = await storage.read();
      await expectLater(
        storage.write(
          current.copyWith(
            revision: current.revision + 1,
            tasks: [staleTask.copyWith(title: 'Direct forbidden')],
          ),
        ),
        throwsA(isA<OrganizerConflictException>()),
      );
      await archiveProject(pid, archived: false);
      await organizer.updateTask(staleTask.copyWith(title: 'Restored'));
      await archiveProject(pid, archived: true);
      final preview = await organizer.previewProjectDeletion(pid);
      await organizer.deleteProject(
        pid,
        previewHash: preview['previewHash'] as String,
      );
      expect(organizer.snapshot.projects, isEmpty);
      expect(organizer.snapshot.tasks, isEmpty);
      await ideas.reload();
      expect(ideas.snapshot.boards, isEmpty);
    },
  );

  test(
    'standalone archived project backup fences old clients with schema5 while active stays4',
    () async {
      await organizer.createProject(title: 'Archived backup');
      final pid = organizer.snapshot.projects.single.id;
      final active = OrganizerBackupCodec.encode(organizer.snapshot);
      expect((jsonDecode(active) as Map)['schemaVersion'], 4);
      await archiveProject(pid, archived: true);
      final encoded = OrganizerBackupCodec.encode(organizer.snapshot);
      expect((jsonDecode(encoded) as Map)['schemaVersion'], 5);
      expect(
        OrganizerBackupCodec.decode(encoded).projects.single.archived,
        true,
      );
      final downgraded = jsonDecode(encoded) as Map<String, dynamic>;
      downgraded['schemaVersion'] = 4;
      expect(
        () => OrganizerBackupCodec.decode(jsonEncode(downgraded)),
        throwsFormatException,
      );
      final restored = OrganizerBackupCodec.decode(encoded);
      final another = CollaborationDatabase(NativeDatabase.memory());
      final store = SqliteOrganizerStorage(another);
      await store.initialize();
      await store.importPersonalJsonBackup(encoded);
      expect((await store.read()).projects.single.archived, true);
      expect(restored.projects.single.id, pid);
      await another.close();
    },
  );

  test(
    'project preview sees separate draft edits and rollback includes private photos',
    () async {
      await home();
      await organizer.createProject(title: 'Target');
      final pid = organizer.snapshot.projects.single.id;
      final b = board().copyWith(projectId: pid);
      await ideas.saveBoard(b, isNew: true);
      await organizer.reload();
      final stale = await organizer.previewProjectDeletion(pid);
      await ideas.saveDraft(b, base: b);
      await expectLater(
        organizer.deleteProject(
          pid,
          previewHash: stale['previewHash'] as String,
        ),
        throwsA(isA<CollaborationException>()),
      );
      expect(
        await db.rows('SELECT * FROM device_ideas WHERE id=?', [id]),
        isNotEmpty,
      );
      await organizer.reload();
      final fresh = await organizer.previewProjectDeletion(pid);
      await db.execute(
        "CREATE TRIGGER fail_project_delete BEFORE DELETE ON personal_records WHEN OLD.type='project' BEGIN SELECT RAISE(ABORT,'synthetic project rollback'); END",
      );
      await expectLater(
        organizer.deleteProject(
          pid,
          previewHash: fresh['previewHash'] as String,
        ),
        throwsA(anything),
      );
      expect(
        await db.rows('SELECT * FROM device_ideas WHERE id=?', [id]),
        isNotEmpty,
      );
      expect(await ideas.readDraft(id), isNotNull);
      expect(organizer.snapshot.projects, hasLength(1));
    },
  );
}
