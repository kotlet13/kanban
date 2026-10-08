// Opt-in loopback tests create only new scopes under a synthetic fixture account.
import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'collaboration_repository_test.dart' show MemorySessionStore;
import 'collaboration_http_integration_test.dart' show OfflineHttpTransport;

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final path = Platform.environment['KANBAN_PLANNING_HTTP_FIXTURE'];
  test(
    'actual shared client offline ledger+task cost, rename/root quickadd, archive/restore',
    () async {
      final fixture =
              jsonDecode(await File(path!).readAsString())
                  as Map<String, dynamic>,
          url = fixture['server'] as String;
      if (fixture['synthetic'] != true || Uri.parse(url).host != '127.0.0.1') {
        throw StateError('Synthetic loopback required');
      }
      final owner = fixture['owner'] as Map<String, dynamic>,
          db = CollaborationDatabase(NativeDatabase.memory()),
          http = OfflineHttpTransport();
      final repo = CollaborationRepository(db, http, MemorySessionStore());
      await repo.initialize();
      addTearDown(repo.close);
      await repo.login(
        serverUrl: url,
        username: owner['username'] as String,
        password: owner['password'] as String,
        allowLocalHttp: true,
      );
      final org = await repo.createScope(
        'Synthetic client organization',
        kind: SharedScopeKind.organization,
      );
      final scope = await repo.createScope(
        'Synthetic client project',
        kind: SharedScopeKind.project,
        organizationId: org,
      );
      await repo.syncNow();
      await repo.enableFinance(scope, true);
      expect(repo.state.dataForScope(scope).projects.single.id, scope);
      final now = DateTime.now().toUtc(),
          ledgerId = newSharedId(),
          taskId = newSharedId();
      http.offline = true;
      await repo.saveFinancePlanForScope(
        scopeId: scope,
        accounts: [
          LocalFinanceAccount(
            id: ledgerId,
            name: 'Synthetic ledger',
            currency: 'EUR',
            createdAt: now,
            updatedAt: now,
          ),
        ],
        rules: [],
      );
      final task = LocalTask(
        id: taskId,
        title: 'Offline cost task',
        notes: '',
        projectId: scope,
        dueAt: now.add(const Duration(days: 7)),
        isCompleted: false,
        createdAt: now,
        updatedAt: now,
      );
      await repo.saveTaskWithCost(
        scope,
        task,
        isNew: true,
        cost: TaskCostDraft(amountMinor: 1234, ledgerAccountId: ledgerId),
      );
      expect(repo.state.pendingCount, 3);
      http.offline = false;
      await repo.syncNow();
      expect(repo.state.lastError, isNull);
      expect(repo.state.pendingCount, 0);
      expect(repo.state.blockedCount, 0);
      expect(repo.state.financeBlockedCount, 0);
      expect(
        repo.state.dataForScope(scope).financeEntries.single.amountMinor,
        1234,
      );
      expect(
        repo.state.dataForScope(scope).financeEntries.single.taskId,
        taskId,
      );
      final quick = await repo.createTask(scopeId: scope, title: 'Quick task');
      final event = await repo.createEvent(
        scopeId: scope,
        title: 'Quick event',
        startAt: now.add(const Duration(days: 1)),
      );
      expect(
        repo.state
            .dataForScope(scope)
            .tasks
            .firstWhere((task) => task.id == quick)
            .projectId,
        scope,
      );
      expect(
        repo.state
            .dataForScope(scope)
            .events
            .firstWhere((row) => row.id == event)
            .projectId,
        scope,
      );
      await repo.updateProject(
        scope,
        repo.state
            .dataForScope(scope)
            .projects
            .single
            .copyWith(title: 'Renamed actual project'),
      );
      await repo.syncNow();
      expect(
        repo.state.scopes.firstWhere((s) => s.id == scope).name,
        'Renamed actual project',
      );
      await repo.selectSpace(scope);
      await repo.archiveProjectScope(scope, archived: true);
      expect(
        repo.state.scopes.firstWhere((s) => s.id == scope).archived,
        isTrue,
      );
      expect(repo.state.financePolicyForScope(scope).canRead, isTrue);
      expect(repo.state.financePolicyForScope(scope).canWrite, isFalse);
      expect(
        repo.state.dataForScope(scope).financeEntries.single.amountMinor,
        1234,
      );
      await repo.archiveProjectScope(scope, archived: false);
      expect(
        repo.state.scopes.firstWhere((s) => s.id == scope).archived,
        isFalse,
      );
      expect(repo.state.financePolicyForScope(scope).canWrite, isTrue);
      expect(repo.state.dataForScope(scope).tasks.length, 2);

      // A second actual account exercises cold inbox hydration and financial
      // conflict review through the public financial operation ID.
      final recipient = fixture['recipient'] as Map<String, dynamic>,
          otherHttp = OfflineHttpTransport(),
          other = CollaborationRepository(
            CollaborationDatabase(NativeDatabase.memory()),
            otherHttp,
            MemorySessionStore(),
          );
      await other.initialize();
      addTearDown(other.close);
      await other.login(
        serverUrl: url,
        username: recipient['username'] as String,
        password: recipient['password'] as String,
        allowLocalHttp: true,
      );
      final invite = await repo.createInvitation(
        scopeId: scope,
        recipientUsername: recipient['username'] as String,
      );
      await other.acceptInvitation(invite.token!);
      await repo.grantFinance(
        scopeId: scope,
        accountId: other.state.session!.accountId,
        grant: SharedFinanceGrant.write,
      );
      await other.syncNow();
      final existing = other.state
          .dataForScope(scope)
          .tasks
          .firstWhere((t) => t.id == taskId);
      await other.saveTaskWithCost(
        scope,
        existing.copyWith(title: 'Remote notification task'),
        expectedFinanceRevision: other.state
            .dataForScope(scope)
            .financeEntries
            .single
            .revision,
        cost: TaskCostDraft(amountMinor: 2345, ledgerAccountId: ledgerId),
      );
      await other.syncNow();
      await repo.syncNow();
      final profile = repo.state.session!;
      Future<void> openTarget(
        String type,
        String id, {
        bool fromInbox = true,
      }) async {
        final entry = repo.state.inbox.lastWhere(
          (i) => i.scopeId == scope && i.targetType == type && i.targetId == id,
        );
        final target = NotificationTarget(
          serverUrl: profile.serverUrl,
          serverId: profile.serverId,
          accountId: profile.accountId,
          scopeId: scope,
          records: [NotificationRecordTarget(type: type, recordId: id)],
          inboxIds: fromInbox ? [entry.id] : [],
        );
        expect(
          (await repo.openNotificationTarget(target)).status,
          NotificationOpenStatus.available,
        );
      }

      await openTarget('task', taskId);
      final costId = repo.state.dataForScope(scope).financeEntries.single.id;
      await db.execute(
        'DELETE FROM finance_records WHERE partition=? AND id=?',
        [profile.partition, costId],
      );
      await repo.refreshLocal();
      await openTarget('financeEntry', costId);
      expect(
        repo.state.dataForScope(scope).financeEntries.single.amountMinor,
        2345,
      );
      await openTarget('task', taskId, fromInbox: false);
      await repo.archiveProjectScope(scope, archived: true);
      await openTarget('financeEntry', costId, fromInbox: false);
      await repo.archiveProjectScope(scope, archived: false);
      for (final keepLocal in [true, false]) {
        await repo.syncNow();
        await other.syncNow();
        final localTask = repo.state
            .dataForScope(scope)
            .tasks
            .firstWhere((t) => t.id == taskId);
        http.offline = true;
        await repo.saveTaskWithCost(
          scope,
          localTask.copyWith(title: 'Local conflict'),
          expectedFinanceRevision: repo.state
              .dataForScope(scope)
              .financeEntries
              .single
              .revision,
          cost: TaskCostDraft(amountMinor: 3456, ledgerAccountId: ledgerId),
        );
        final remoteTask = other.state
            .dataForScope(scope)
            .tasks
            .firstWhere((t) => t.id == taskId);
        await other.saveTaskWithCost(
          scope,
          remoteTask.copyWith(title: 'Canonical conflict'),
          expectedFinanceRevision: other.state
              .dataForScope(scope)
              .financeEntries
              .single
              .revision,
          cost: TaskCostDraft(amountMinor: 4567, ledgerAccountId: ledgerId),
        );
        await other.syncNow();
        http.offline = false;
        await repo.syncNow();
        expect(
          repo.state.financeConflicts.where((c) => c.scopeId == scope),
          hasLength(1),
        );
        final conflict = repo.state.financeConflicts.singleWhere(
          (c) => c.scopeId == scope,
        );
        await repo.resolveFinanceConflict(
          conflictId: conflict.id,
          keepLocal: keepLocal,
        );
        await repo.syncNow();
        expect(repo.state.lastError, isNull);
        expect(repo.state.pendingCount, 0);
        expect(repo.state.blockedCount, 0);
        expect(repo.state.financeBlockedCount, 0);
        expect(
          await db.rows('SELECT name FROM local_meta WHERE name LIKE ?', [
            'task_cost_pair:${profile.partition}:%',
          ]),
          isEmpty,
        );
        expect(
          repo.state.dataForScope(scope).financeEntries.single.amountMinor,
          keepLocal ? 3456 : 4567,
        );
        expect(
          repo.state
              .dataForScope(scope)
              .tasks
              .firstWhere((t) => t.id == taskId)
              .title,
          keepLocal ? 'Local conflict' : 'Canonical conflict',
        );
      }
    },
    skip: path == null,
  );
}
