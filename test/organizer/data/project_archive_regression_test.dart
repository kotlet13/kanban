import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/organizer_repository.dart';
import 'package:kanban/organizer/data/organizer_storage.dart';
import 'package:kanban/organizer/data/sqlite_organizer_storage.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  test(
    'legacy project omits archive field; true survives JSON and malformed flags fail',
    () {
      final day = DateTime.utc(2026, 10, 14);
      final project = LocalProject(
        id: 'p',
        title: 'Legacy project',
        description: 'Notes',
        createdAt: day,
        updatedAt: day,
      );
      expect(project.toJson().containsKey('archived'), isFalse);
      expect(LocalProject.fromJson(project.toJson()).archived, isFalse);
      final archived = project.copyWith(archived: true);
      final decoded = OrganizerBackupCodec.decode(
        OrganizerBackupCodec.encode(OrganizerSnapshot(projects: [archived])),
      );
      expect(decoded.projects.single.toJson(), archived.toJson());
      expect(
        decoded.projects.single.copyWith(archived: false).toJson(),
        project.toJson(),
      );
      expect(
        () => LocalProject.fromJson({...project.toJson(), 'archived': 'true'}),
        throwsFormatException,
      );
    },
  );

  test(
    'archived project JSON uses a newer envelope and cannot masquerade as historical version4',
    () {
      final day = DateTime.utc(2026, 10, 14);
      final archived = LocalProject(
        id: 'p',
        title: 'Closed project',
        description: '',
        archived: true,
        createdAt: day,
        updatedAt: day,
      );
      final json =
          jsonDecode(
                OrganizerBackupCodec.encode(
                  OrganizerSnapshot(projects: [archived]),
                ),
              )
              as Map<String, dynamic>;
      expect(
        json['schemaVersion'] as int,
        greaterThan(4),
        reason:
            'Old version4 readers ignore unknown archived flags and would reactivate the project',
      );
      final relabeled = {...json, 'schemaVersion': 4};
      expect(
        () => OrganizerBackupCodec.decode(jsonEncode(relabeled)),
        throwsFormatException,
      );
      final historical = {
        ...json,
        'schemaVersion': 4,
        'data': OrganizerSnapshot(
          projects: [archived.copyWith(archived: false)],
        ).toJson(),
      };
      expect(
        OrganizerBackupCodec.decode(
          jsonEncode(historical),
        ).projects.single.archived,
        isFalse,
      );
    },
  );
  test(
    'SQLite project archive and restore preserve graph after real close/reopen, reject stale project',
    () async {
      final dir = await Directory.systemTemp.createTemp('project-archive-');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/organizer.db');
      var db = CollaborationDatabase(NativeDatabase(file));
      var storage = SqliteOrganizerStorage(db);
      await storage.initialize();
      var repo = OrganizerRepository(storage);
      await repo.initialize();
      await repo.createProject(
        title: 'Archive target',
        description: 'Stable details',
        area: ProjectArea.home,
      );
      final original = repo.snapshot.projects.single;
      await repo.createTask(title: 'Preserve task', projectId: original.id);
      await repo.createEvent(
        title: 'Preserve event',
        startsAt: DateTime.utc(2026, 10, 20),
        endsAt: DateTime.utc(2026, 10, 20, 1),
        projectId: original.id,
      );
      final tasks = jsonEncode(
        repo.snapshot.tasks.map((v) => v.toJson()).toList(),
      );
      final events = jsonEncode(
        repo.snapshot.events.map((v) => v.toJson()).toList(),
      );
      await repo.updateProject(original.copyWith(archived: true));
      await expectLater(
        repo.updateProject(original.copyWith(title: 'Stale overwrite')),
        throwsA(isA<OrganizerConflictException>()),
      );
      final archived = repo.snapshot.projects.single.toJson();
      await repo.close();
      await db.close();
      db = CollaborationDatabase(NativeDatabase(file));
      storage = SqliteOrganizerStorage(db);
      await storage.initialize();
      repo = OrganizerRepository(storage);
      await repo.initialize();
      expect(repo.snapshot.projects.single.toJson(), archived);
      expect(
        jsonEncode(repo.snapshot.tasks.map((v) => v.toJson()).toList()),
        tasks,
      );
      expect(
        jsonEncode(repo.snapshot.events.map((v) => v.toJson()).toList()),
        events,
      );
      await repo.updateProject(
        repo.snapshot.projects.single.copyWith(archived: false),
      );
      expect(repo.snapshot.projects.single.id, original.id);
      expect(repo.snapshot.projects.single.archived, isFalse);
      expect(repo.snapshot.projects.single.area, ProjectArea.home);
      expect(repo.snapshot.projects.single.description, original.description);
      expect(
        jsonEncode(repo.snapshot.tasks.map((v) => v.toJson()).toList()),
        tasks,
      );
      expect(
        jsonEncode(repo.snapshot.events.map((v) => v.toJson()).toList()),
        events,
      );
      await repo.close();
      await db.close();
    },
  );

  test(
    'task editor opened before local project archive cannot save into archived parent',
    () async {
      final db = CollaborationDatabase(NativeDatabase.memory());
      final storage = SqliteOrganizerStorage(db);
      await storage.initialize();
      final repo = OrganizerRepository(storage);
      await repo.initialize();
      addTearDown(() async {
        await repo.close();
        await db.close();
      });
      await repo.createProject(title: 'Parent');
      final project = repo.snapshot.projects.single;
      await repo.createTask(
        title: 'Task before archive',
        projectId: project.id,
      );
      final staleTask = repo.snapshot.tasks.single;
      await repo.updateProject(project.copyWith(archived: true));
      await expectLater(
        repo.updateTask(staleTask.copyWith(title: 'Late editor save')),
        throwsA(isA<OrganizerConflictException>()),
      );
      expect(repo.snapshot.tasks.single.title, 'Task before archive');
      await expectLater(
        repo.createTask(title: 'New task in archive', projectId: project.id),
        throwsA(isA<OrganizerConflictException>()),
      );
      expect(repo.snapshot.tasks, hasLength(1));
    },
  );
  test(
    'archived task-linked cost remains protected when its optional project field is empty',
    () async {
      final db = CollaborationDatabase(NativeDatabase.memory());
      final storage = SqliteOrganizerStorage(db);
      await storage.initialize();
      final repo = OrganizerRepository(storage);
      await repo.initialize();
      addTearDown(() async {
        await repo.close();
        await db.close();
      });
      await repo.createProject(title: 'Archived parent');
      final project = repo.snapshot.projects.single;
      await repo.createTask(title: 'Cost owner', projectId: project.id);
      await repo.saveTaskWithCost(
        task: repo.snapshot.tasks.single,
        cost: const TaskCostDraft(amountMinor: 1234),
        expectedWorkspaceKey: 'local',
      );
      await repo.updateFinanceEntry(
        repo.snapshot.financeEntries.single.copyWith(projectId: null),
      );
      final cost = repo.snapshot.financeEntries.single;
      expect(cost.taskId, repo.snapshot.tasks.single.id);
      expect(cost.projectId, isNull);
      await repo.updateProject(project.copyWith(archived: true));
      await expectLater(
        repo.deleteFinanceEntry(cost.id),
        throwsA(isA<OrganizerConflictException>()),
      );
      expect(repo.snapshot.financeEntries.single.toJson(), cost.toJson());
    },
  );
}
