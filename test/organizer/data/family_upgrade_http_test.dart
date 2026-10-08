// Explicit synthetic loopback fixture only. Never logs credentials or bodies.
import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/data/collaboration_transport.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'package:kanban/organizer/domain/organizer_projections.dart';
import 'collaboration_repository_test.dart' show MemorySessionStore;

class ControlledHttp implements CollaborationTransport {
  final inner = HttpCollaborationTransport();
  bool offline = false;
  String? loseReply;
  Future<void> Function(String, Map<String, Object?>)? before;
  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) async {
    if (offline) throw const CollaborationException('network');
    await before?.call(operation, params);
    final reply = await inner.call(
      serverUrl: serverUrl,
      operation: operation,
      params: params,
      token: token,
      allowLocalHttp: allowLocalHttp,
    );
    if (loseReply == operation) {
      loseReply = null;
      throw const CollaborationException('network');
    }
    return reply;
  }

  @override
  void close() => inner.close();
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final fixturePath =
      Platform.environment['KANBAN_FAMILY_HTTP_FIXTURE'] ??
      Platform.environment['KANBAN_SHARED_HTTP_FIXTURE'];
  test(
    'real collaboration: assignment, inbox races/pagination, finance ACL/restart/conflicts',
    () async {
      final fixture =
          jsonDecode(await File(fixturePath!).readAsString())
              as Map<String, dynamic>;
      final url = fixture['server'] as String;
      if (fixture['synthetic'] != true || Uri.parse(url).host != '127.0.0.1') {
        throw StateError('Synthetic loopback fixture required');
      }
      final directory = await Directory.systemTemp.createTemp('family-http-');
      final repositories = <CollaborationRepository>[];
      Future<CollaborationRepository> open(
        String name,
        MemorySessionStore store,
        ControlledHttp transport,
      ) async {
        final repo = CollaborationRepository(
          CollaborationDatabase(
            NativeDatabase(File('${directory.path}/$name.sqlite')),
          ),
          transport,
          store,
        );
        repositories.add(repo);
        await repo.initialize();
        return repo;
      }

      Future<void> syncSuccess(CollaborationRepository repository) async {
        await repository.syncNow();
        expect(
          repository.state.lastError,
          isNull,
          reason: 'HTTP sync must succeed before reading its projection',
        );
      }

      try {
        final bootstrap = await open(
          'bootstrap',
          MemorySessionStore(),
          ControlledHttp(),
        );
        final fixtureOwner = fixture['owner'] as Map<String, dynamic>;
        await bootstrap.login(
          serverUrl: url,
          username: fixtureOwner['username'] as String,
          password: fixtureOwner['password'] as String,
          allowLocalHttp: true,
        );
        final seed = await bootstrap.createScope(
          'Synthetic bootstrap ${newSharedId()}',
        );
        final usernameA =
                'fa_${newSharedId().replaceAll('-', '').substring(0, 16)}',
            passwordA = 'Synthetic-${newSharedId()}';
        final inviteA = await bootstrap.createInvitation(
          scopeId: seed,
          recipientUsername: usernameA,
        );
        final storeA = MemorySessionStore(), transportA = ControlledHttp();
        final a = await open('a', storeA, transportA);
        await a.registerWithInvitation(
          serverUrl: url,
          invitationToken: inviteA.token!,
          username: usernameA,
          name: 'Synthetic owner',
          password: passwordA,
          allowLocalHttp: true,
        );
        await bootstrap.signOut();
        final scope = await a.createScope('Synthetic family ${newSharedId()}');
        await syncSuccess(a);
        expect(a.state.lastError, isNull);
        final usernameB =
                'fb_${newSharedId().replaceAll('-', '').substring(0, 16)}',
            passwordB = 'Synthetic-${newSharedId()}';
        final invitation = await a.createInvitation(
          scopeId: scope,
          recipientUsername: usernameB,
        );
        final storeB = MemorySessionStore();
        var transportB = ControlledHttp();
        var b = await open('b', storeB, transportB);
        await b.registerWithInvitation(
          serverUrl: url,
          invitationToken: invitation.token!,
          username: usernameB,
          name: 'Synthetic member',
          password: passwordB,
          allowLocalHttp: true,
        );
        final b2 = await open('b2', MemorySessionStore(), ControlledHttp());
        await b2.login(
          serverUrl: url,
          username: usernameB,
          password: passwordB,
          allowLocalHttp: true,
        );
        await syncSuccess(a);
        final membership = a.state.inbox.firstWhere(
          (i) => i.targetType == 'membership',
        );
        final membershipTarget = SharedInboxGroup([
          membership,
        ]).targetFor(a.state.session!);
        expect(
          (await a.openNotificationTarget(membershipTarget)).status,
          NotificationOpenStatus.available,
        );
        final ownerId = a.state.session!.accountId,
            memberId = b.state.session!.accountId;
        final date = DateTime.now().toUtc().add(const Duration(days: 1));
        final unassigned = await a.createTask(
          scopeId: scope,
          title: 'Scope awareness',
          dueAt: date,
          assigneeAccountIds: [ownerId],
        );
        final assigned = await a.createTask(
          scopeId: scope,
          title: 'Personal assignment',
          dueAt: date,
          assigneeAccountIds: [memberId],
        );
        await a.createTask(
          scopeId: scope,
          title: 'Second assignment',
          dueAt: date,
          assigneeAccountIds: [memberId],
        );
        final event = await a.createEvent(
          scopeId: scope,
          title: 'Shared calendar',
          startAt: date,
          endAt: date.add(const Duration(hours: 1)),
          assigneeAccountIds: [memberId],
        );
        await syncSuccess(a);
        expect(a.state.lastError, isNull);
        await b.syncNow();
        expect(b.state.lastError, isNull);
        expect(
          b.state.inbox.where((i) => i.targetId == unassigned).single.audience,
          InboxAudience.scope,
        );
        expect(
          b.state.inbox.where((i) => i.targetId == assigned).single.audience,
          InboxAudience.personal,
        );
        expect(b.state.inbox.where((i) => i.targetId == assigned).length, 1);
        expect(
          b.state
              .dataForScope(scope)
              .tasks
              .firstWhere((t) => t.id == assigned)
              .createdByAccountId,
          ownerId,
        );
        expect(
          b.state.membersForScope(scope).map((m) => m.accountId),
          contains(memberId),
        );
        expect(b.state.dataForScope(scope).events.single.id, event);
        final group = groupSharedInbox(
          b.state.inbox,
        ).firstWhere((g) => g.entries.any((i) => i.targetId == assigned));
        expect(
          group.targetFor(b.state.session!).records.map((r) => r.recordId),
          contains(assigned),
        );
        // Provider data supplies only identity and an inbox reference. Resolve the
        // complete canonical group even with Firebase/provider delivery disabled.
        final anchor = group.ids.reduce((a, b) => a > b ? a : b);
        final pushed = await b.openRemotePushReference(
          RemotePushReference(
            serverId: b.state.session!.serverId,
            accountId: b.state.session!.accountId,
            notificationId: anchor,
          ),
        );
        expect(pushed.status, RemotePushOpenStatus.available);
        expect(pushed.target!.inboxIds.toSet(), group.ids.toSet());
        expect(
          pushed.target!.records.map((r) => r.recordId),
          contains(assigned),
        );
        final task = b.state
            .dataForScope(scope)
            .tasks
            .firstWhere((t) => t.id == assigned);
        final remindAt = DateTime.now().toUtc().add(const Duration(days: 1));
        await b.putReminder(
          scopeId: scope,
          targetType: 'task',
          targetId: task.id,
          remindAt: remindAt,
        );
        await b.syncNow();
        transportB.offline = true;
        await b.updateTask(
          scope,
          b.state
              .dataForScope(scope)
              .tasks
              .firstWhere((t) => t.id == assigned)
              .copyWith(title: 'Only title changed'),
        );
        expect(
          desiredReminderPlans(
            personal: OrganizerSnapshot(),
            shared: b.state,
          ).any((p) => p.scheduledAt == remindAt),
          false,
        );
        expect(b.state.scheduledReminders.single.state, 'pending');
        expect(b.state.scheduledReminders.single.remindAt, remindAt);
        await b.updateTask(
          scope,
          b.state
              .dataForScope(scope)
              .tasks
              .firstWhere((t) => t.id == assigned)
              .copyWith(dueAt: date.add(const Duration(days: 2))),
        );
        expect(
          desiredReminderPlans(
            personal: OrganizerSnapshot(),
            shared: b.state,
          ).any((p) => p.scheduledAt == remindAt),
          false,
        );
        final captured = group.ids;
        await b.markInboxRead(captured);
        final addedLater = await a.createTask(
          scopeId: scope,
          title: 'Later unread addition',
          dueAt: date,
          assigneeAccountIds: [memberId],
        );
        await syncSuccess(a);
        transportB.offline = false;
        await syncSuccess(b);
        expect(
          b.state.inbox.firstWhere((i) => i.targetId == addedLater).isRead,
          false,
        );
        expect(
          b.state.inbox
              .where((i) => captured.contains(i.id))
              .every((i) => i.isRead),
          true,
        );
        final readId = b.state.inbox
            .firstWhere((i) => i.targetId == unassigned)
            .id;
        transportB.loseReply = 'inbox.read';
        await b.markInboxRead([readId]);
        await b.syncNow();
        expect(b.state.lastError?.code, 'network');
        await syncSuccess(b2);
        expect(b2.state.inbox.firstWhere((i) => i.id == readId).isRead, true);
        await b2.markInboxRead([readId], read: false);
        await syncSuccess(b2);
        await b.syncNow();
        expect(b.state.inbox.firstWhere((i) => i.id == readId).isRead, false);
        expect(b.state.inbox.firstWhere((i) => i.id == readId).revision, 3);
        // More than one inbox page; a failed second page resumes at durable cursor.
        for (var i = 0; i < 102; i++) {
          await a.createTask(
            scopeId: scope,
            title: 'Page $i',
            assigneeAccountIds: [memberId],
          );
        }
        await syncSuccess(a);
        expect(a.state.lastError, isNull);
        await b.database.execute('DELETE FROM inbox WHERE partition=?', [
          b.state.session!.partition,
        ]);
        await b.database.execute('DELETE FROM inbox_state WHERE partition=?', [
          b.state.session!.partition,
        ]);
        var calls = 0;
        transportB.before = (op, params) async {
          if (op == 'inbox.sync' && ++calls == 2) {
            throw const CollaborationException('network');
          }
        };
        await b.syncNow();
        expect(b.state.inbox.length, 100);
        expect(b.state.lastError?.code, 'network');
        transportB.before = null;
        await b.syncNow();
        expect(b.state.inbox.length, greaterThan(100));
        expect(
          b.state.inbox.map((i) => i.id).toSet().length,
          b.state.inbox.length,
        );
        // Explicitly enabled finance; membership alone never grants access.
        await a.enableFinance(scope, true);
        await b.syncNow();
        expect(b.state.financePolicyForScope(scope).canRead, false);
        await expectLater(
          b.createFinanceAccount(
            scopeId: scope,
            name: 'Denied',
            currency: 'EUR',
          ),
          throwsA(isA<CollaborationException>()),
        );
        await a.grantFinance(
          scopeId: scope,
          accountId: memberId,
          grant: SharedFinanceGrant.write,
        );
        await b.syncNow();
        expect(b.state.financePolicyForScope(scope).canWrite, true);
        final account1 = await a.createFinanceAccount(
          scopeId: scope,
          name: 'Shared account',
          currency: 'EUR',
          openingBalanceMinor: 10000,
        );
        final account2 = await a.createFinanceAccount(
          scopeId: scope,
          name: 'Member account',
          currency: 'EUR',
          openingBalanceMinor: 2000,
          ownerAccountId: memberId,
        );
        await a.createFinanceEntry(
          scopeId: scope,
          accountId: account1,
          kind: FinanceEntryKind.income,
          amountMinor: 1500,
          currency: 'EUR',
          title: 'Income',
          occurredAt: date,
          recipientAccountId: memberId,
        );
        await a.createFinanceEntry(
          scopeId: scope,
          accountId: account1,
          kind: FinanceEntryKind.expense,
          amountMinor: 300,
          currency: 'EUR',
          title: 'Expense',
          occurredAt: date,
          payerAccountId: memberId,
        );
        await a.createFinanceEntry(
          scopeId: scope,
          accountId: account1,
          kind: FinanceEntryKind.expense,
          status: SharedFinanceStatus.planned,
          amountMinor: 999,
          currency: 'EUR',
          title: 'Planned',
          occurredAt: date,
        );
        await a.createFinanceTransfer(
          scopeId: scope,
          fromAccountId: account2,
          toAccountId: account1,
          amountMinor: 500,
          currency: 'EUR',
          title: 'Internal transfer',
          occurredAt: date,
        );
        await syncSuccess(a);
        expect(a.state.lastError, isNull);
        await b.syncNow();
        expect(b.state.lastError, isNull);
        var ledger = b.state.dataForScope(scope);
        final totals = summarizeSharedFinance(
          accounts: ledger.financeAccounts,
          entries: ledger.financeEntries,
          transfers: ledger.financeTransfers,
        )['EUR']!;
        expect(totals.incomeMinor, BigInt.from(1500));
        expect(totals.expenseMinor, BigInt.from(300));
        expect(totals.balanceMinor, BigInt.from(13200));
        expect(totals.accountBalances[account1], BigInt.from(11700));
        expect(totals.accountBalances[account2], BigInt.from(1500));
        final expense = ledger.financeEntries.firstWhere(
          (e) =>
              e.kind == FinanceEntryKind.expense &&
              e.status == SharedFinanceStatus.posted,
        );
        expect(expense.createdByAccountId, ownerId);
        expect(expense.payerAccountId, memberId);
        transportB.offline = true;
        await b.updateFinanceEntry(
          scope,
          expense.copyWith(title: 'Offline financial draft', amountMinor: 350),
        );
        final before = await b.exportUnsentWork();
        await b.close();
        repositories.remove(b);
        transportB = ControlledHttp()..offline = true;
        b = await open('b', storeB, transportB);
        expect(b.state.financeSupported, true);
        expect(b.state.inboxSupported, true);
        expect(await b.exportUnsentWork(), before);
        await a.updateFinanceEntry(
          scope,
          a.state
              .dataForScope(scope)
              .financeEntries
              .firstWhere((e) => e.id == expense.id)
              .copyWith(amountMinor: 400),
        );
        await syncSuccess(a);
        transportB.offline = false;
        await b.syncNow();
        expect(b.state.financeConflicts.length, 1);
        await b.resolveFinanceConflict(
          conflictId: b.state.financeConflicts.single.id,
          keepLocal: false,
        );
        expect(
          b.state
              .dataForScope(scope)
              .financeEntries
              .firstWhere((e) => e.id == expense.id)
              .amountMinor,
          400,
        );
        final audit = await b.financeAudit(
          scopeId: scope,
          recordId: expense.id,
        );
        expect(audit.length, 2);
        expect(audit.every((e) => e.actorAccountId == ownerId), true);
        final financialInbox = b.state.inbox.lastWhere(
          (i) => i.category == 'finance' && i.targetId == expense.id,
        );
        final hydrateTarget = NotificationTarget(
          serverUrl: b.state.session!.serverUrl,
          serverId: b.state.session!.serverId,
          accountId: b.state.session!.accountId,
          scopeId: scope,
          records: [
            NotificationRecordTarget(
              type: 'financeEntry',
              recordId: expense.id,
            ),
          ],
          inboxIds: [financialInbox.id],
        );
        await b.database.execute(
          'DELETE FROM finance_records WHERE partition=? AND id=?',
          [b.state.session!.partition, expense.id],
        );
        await b.refreshLocal();
        expect(
          (await b.openNotificationTarget(hydrateTarget)).status,
          NotificationOpenStatus.available,
        );
        expect(
          b.state
              .dataForScope(scope)
              .financeEntries
              .any((e) => e.id == expense.id),
          true,
        );
        // Loss of write preserves the readable canonical ledger and blocked draft.
        transportB.offline = true;
        await b.createFinanceEntry(
          scopeId: scope,
          accountId: account1,
          kind: FinanceEntryKind.expense,
          amountMinor: 10,
          currency: 'EUR',
          title: 'Write revoked draft',
          occurredAt: date,
        );
        await a.grantFinance(
          scopeId: scope,
          accountId: memberId,
          grant: SharedFinanceGrant.read,
        );
        transportB.offline = false;
        await b.syncNow();
        expect(b.state.financeBlockedCount, 1);
        expect(b.state.dataForScope(scope).financeAccounts.length, 2);
        expect(
          summarizeSharedFinance(
            accounts: b.state.dataForScope(scope).financeAccounts,
            entries: b.state.dataForScope(scope).financeEntries,
            transfers: b.state.dataForScope(scope).financeTransfers,
          )['EUR']!.balanceMinor,
          BigInt.from(13100),
        );
        final financeTarget = NotificationTarget(
          serverUrl: b.state.session!.serverUrl,
          serverId: b.state.session!.serverId,
          accountId: b.state.session!.accountId,
          scopeId: scope,
          records: [
            NotificationRecordTarget(
              type: 'financeEntry',
              recordId: expense.id,
            ),
          ],
          inboxIds: [
            b.state.inbox
                .lastWhere(
                  (i) => i.category == 'finance' && i.targetId == expense.id,
                )
                .id,
          ],
        );
        await a.grantFinance(
          scopeId: scope,
          accountId: memberId,
          grant: SharedFinanceGrant.none,
        );
        // A tap must learn revocation before normal synchronization and hide all
        // financial projections immediately while retaining the unsent candidate.
        expect(
          (await b.openNotificationTarget(financeTarget)).status,
          NotificationOpenStatus.permissionDenied,
        );
        expect(b.state.financePolicyForScope(scope).canRead, false);
        expect(b.state.dataForScope(scope).financeAccounts, isEmpty);
        expect(b.state.financeConflicts, isEmpty);
        expect(b.state.inbox.where((i) => i.category == 'finance'), isEmpty);
        expect(
          await b.exportUnsentWork(),
          isNot(contains('Write revoked draft')),
        );
        expect(
          (await b.database.rows(
            'SELECT id FROM finance_records WHERE partition=?',
            [b.state.session!.partition],
          )).length,
          1,
        );
        await expectLater(
          b.financeAudit(scopeId: scope, recordId: expense.id),
          throwsA(isA<CollaborationException>()),
        );
        await a.grantFinance(
          scopeId: scope,
          accountId: memberId,
          grant: SharedFinanceGrant.write,
        );
        await b.syncNow();
        expect(b.state.financeBlockedCount, 1);
        await b.resumeBlockedFinanceChanges(scope);
        expect(b.state.financePendingCount, 0);
        final openTarget = group.targetFor(b.state.session!);
        transportB.offline = true;
        expect(
          (await b.openNotificationTarget(openTarget)).status,
          NotificationOpenStatus.offline,
        );
        transportB.offline = false;
        await a.revokeMember(scopeId: scope, userId: b.state.session!.userId);
        await b.syncNow();
        expect(
          (await b.openNotificationTarget(openTarget)).status,
          NotificationOpenStatus.permissionDenied,
        );
        await b.signOut();
        expect(
          (await b.openNotificationTarget(openTarget)).status,
          NotificationOpenStatus.wrongAccount,
        );
        await a.signOut();
        await b2.signOut();
      } finally {
        for (final repository in repositories) {
          await repository.close();
        }
        await directory.delete(recursive: true);
      }
    },
    skip: fixturePath == null
        ? 'Explicit synthetic HTTP fixture required'
        : false,
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
