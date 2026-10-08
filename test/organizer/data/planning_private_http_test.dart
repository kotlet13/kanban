// Explicit isolated synthetic loopback fixture. Never logs credentials/bodies.
import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/data/organizer_repository.dart';
import 'package:kanban/organizer/data/sqlite_organizer_storage.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'collaboration_repository_test.dart' show MemorySessionStore;
import 'family_upgrade_http_test.dart' show ControlledHttp;

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final path = Platform.environment['KANBAN_PLANNING_HTTP_FIXTURE'];
  test(
    'real private client phase removal detaches tasks before project; 72 monthly entries follow their parent rules',
    () async {
      final fixture =
          jsonDecode(await File(path!).readAsString()) as Map<String, dynamic>;
      final url = fixture['server'] as String;
      if (fixture['synthetic'] != true || Uri.parse(url).host != '127.0.0.1') {
        throw StateError('Isolated loopback fixture required');
      }
      final owner = fixture['owner'] as Map<String, dynamic>,
          db = CollaborationDatabase(NativeDatabase.memory()),
          http = ControlledHttp();
      final storage = SqliteOrganizerStorage(db);
      await storage.initialize();
      final personal = OrganizerRepository(storage);
      await personal.initialize();
      final shared = CollaborationRepository(
        db,
        http,
        MemorySessionStore(),
        ownsDatabase: false,
      );
      await shared.initialize();
      addTearDown(() async {
        await personal.close();
        await shared.close();
        await db.close();
      });
      await shared.login(
        serverUrl: url,
        username: owner['username'] as String,
        password: owner['password'] as String,
        allowLocalHttp: true,
      );
      expect(shared.state.recordContractVersion, 3);
      expect(shared.state.financeContractVersion, 2);
      await personal.reload();
      await shared.enablePrivateSync(
        expectedRevision: (await storage.read()).revision,
      );
      await personal.reload();
      final key = personal.snapshot.workspaceKey,
          now = DateTime.now().toUtc(),
          id = newLocalId();
      await personal.createProject(
        title: 'Planning HTTP $id',
        phases: const [ProjectPhase(id: 'phase-a', title: 'A')],
      );
      final project = personal.snapshot.projects.firstWhere(
        (p) => p.title == 'Planning HTTP $id',
      );
      final taskId = newLocalId();
      await personal.saveTaskWithCost(
        task: LocalTask(
          id: taskId,
          title: 'Phase HTTP $id',
          notes: '',
          projectId: project.id,
          phaseId: 'phase-a',
          estimateMinutes: 30,
          dueAt: now.add(const Duration(days: 2)),
          isCompleted: false,
          createdAt: now,
          updatedAt: now,
        ),
        isNew: true,
        cost: const TaskCostDraft(amountMinor: 1250),
        expectedWorkspaceKey: key,
      );
      await shared.syncNow();
      expect(shared.state.lastError, isNull);
      await personal.reload();
      final current = personal.snapshot.projects.firstWhere(
        (p) => p.id == project.id,
      );
      await personal.updateProject(
        current.copyWith(
          phases: const [ProjectPhase(id: 'phase-b', title: 'B')],
        ),
      );
      final outgoing = await db.rows(
        'SELECT type,sequence FROM records r JOIN outbox o ON o.partition=r.partition AND o.scope_id=r.scope_id AND o.record_id=r.id ORDER BY o.sequence',
      );
      expect(outgoing.map((r) => r['type']), ['task', 'project']);
      await shared.syncNow();
      expect(shared.state.lastError, isNull);
      expect(shared.state.blockedCount, 0);
      await personal.reload();
      expect(
        personal.snapshot.tasks.firstWhere((t) => t.id == taskId).phaseId,
        isNull,
      );
      expect(
        personal.snapshot.projects
            .firstWhere((p) => p.id == project.id)
            .phases
            .single
            .id,
        'phase-b',
      );
      final accountId = newLocalId();
      final rules = [
        for (var i = 0; i < 6; i++)
          FinanceRecurrenceRule(
            id: 'z-rule-$id-$i',
            title: 'Rule $i',
            kind: FinanceRecurrenceKind.expense,
            ledgerAccountId: accountId,
            currency: 'EUR',
            estimatedAmountMinor: 1000 + i,
            startYear: now.toLocal().year,
            startMonth: now.toLocal().month,
            monthDay: 15,
            createdAt: now,
            updatedAt: now,
          ),
      ];
      await personal.saveFinancePlan(
        accounts: [
          LocalFinanceAccount(
            id: accountId,
            name: 'HTTP account',
            currency: 'EUR',
            createdAt: now,
            updatedAt: now,
          ),
        ],
        rules: rules,
        expectedRevision: personal.snapshot.revision,
        expectedWorkspaceKey: key,
      );
      final financeOps = (await db.rows(
        'SELECT request FROM finance_outbox ORDER BY sequence',
      )).map((r) => jsonDecode(r['request'] as String) as Map).toList();
      final firstEntry = financeOps.indexWhere(
        (op) => op['type'] == 'personalFinanceEntry',
      );
      final lastRule = financeOps.lastIndexWhere(
        (op) => op['type'] == 'financeRecurrenceRule',
      );
      expect(lastRule, greaterThanOrEqualTo(5));
      expect(firstEntry, greaterThan(lastRule));
      expect(
        personal.snapshot.financeEntries.where(
          (e) => rules.any((r) => r.id == e.recurrenceRuleId),
        ),
        hasLength(72),
      );
      await shared.syncNow();
      expect(shared.state.lastError, isNull);
      expect(shared.state.blockedCount, 0);
      expect(await db.rows('SELECT op_id FROM outbox'), isEmpty);
      expect(await db.rows('SELECT op_id FROM finance_outbox'), isEmpty);
    },
    skip: path == null
        ? 'Set KANBAN_PLANNING_HTTP_FIXTURE to isolated fixture'
        : false,
  );
}
