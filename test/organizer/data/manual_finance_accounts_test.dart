import 'dart:convert';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/organizer_repository.dart';
import 'package:kanban/organizer/data/sqlite_organizer_storage.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:kanban/organizer/domain/finance_forecast.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final now = DateTime.utc(2026, 10, 8);
  LocalFinanceAccount account(String id, {String currency = 'EUR'}) =>
      LocalFinanceAccount(
        id: id,
        name: id,
        currency: currency,
        openingBalanceMinor: 10000,
        openingBalanceAt: now,
        createdAt: now,
        updatedAt: now,
      );
  test(
    'manual account entries survive SQLite restart and forecast/account filters are exact',
    () async {
      final db = CollaborationDatabase(NativeDatabase.memory());
      final storage = SqliteOrganizerStorage(db);
      await storage.initialize();
      var repo = OrganizerRepository(storage, clock: () => now);
      await repo.initialize();
      await repo.saveFinancePlan(
        accounts: [
          account('bank'),
          account('usd', currency: 'USD'),
        ],
        rules: [],
        expectedRevision: repo.snapshot.revision,
        expectedWorkspaceKey: 'local',
      );
      await repo.createFinanceEntry(
        title: 'Material',
        amountMinor: 2500,
        kind: FinanceEntryKind.expense,
        occurredAt: now,
        ledgerAccountId: 'bank',
        expectedWorkspaceKey: 'local',
      );
      await repo.createFinanceEntry(
        title: 'Cash',
        amountMinor: 700,
        kind: FinanceEntryKind.expense,
        occurredAt: now,
        expectedWorkspaceKey: 'local',
      );
      await expectLater(
        repo.createFinanceEntry(
          title: 'Wrong',
          amountMinor: 10,
          kind: FinanceEntryKind.expense,
          occurredAt: now,
          ledgerAccountId: 'usd',
        ),
        throwsFormatException,
      );
      await expectLater(
        repo.createFinanceEntry(
          title: 'Late',
          amountMinor: 10,
          kind: FinanceEntryKind.expense,
          occurredAt: now,
          expectedWorkspaceKey: 'private:other',
        ),
        throwsA(isA<OrganizerConflictException>()),
      );
      expect(repo.snapshot.financeEntries.length, 2);
      await repo.close();
      repo = OrganizerRepository(storage, clock: () => now);
      await repo.initialize();
      expect(
        repo.snapshot.financeEntries
            .firstWhere((e) => e.title == 'Material')
            .ledgerAccountId,
        'bank',
      );
      expect(
        forecastFinance(
          repo.snapshot,
          currency: 'EUR',
          through: now,
          account: repo.snapshot.financeAccounts.firstWhere(
            (a) => a.id == 'bank',
          ),
        ).endMinor,
        BigInt.from(7500),
      );
      expect(
        forecastFinance(
          repo.snapshot,
          currency: 'EUR',
          through: now,
          unassignedOnly: true,
        ).endMinor,
        BigInt.from(-700),
      );
      await repo.close();
      await db.close();
    },
  );
  test(
    'new hybrid entry inherits local ledger; denial and account switch cannot upload or rebind it',
    () async {
      final db = CollaborationDatabase(NativeDatabase.memory());
      final storage = SqliteOrganizerStorage(db);
      await storage.initialize();
      await storage.write(
        OrganizerSnapshot(
          revision: 1,
          financeAccounts: [account('local-bank')],
        ),
      );
      final profile = AccountSession(
        serverUrl: 'https://test.invalid',
        serverId: '00000000-0000-4000-8000-000000000001',
        accountId: '00000000-0000-4000-8000-000000000002',
        userId: 1,
        username: 'test',
        displayName: 'test',
        deviceId: '00000000-0000-4000-8000-000000000003',
        expiresAt: DateTime.utc(2099),
      );
      const scope = '00000000-0000-4000-8000-000000000010';
      await db.execute('INSERT INTO accounts(partition,profile) VALUES(?,?)', [
        profile.partition,
        jsonEncode(profile.toJson()),
      ]);
      await db.execute(
        'INSERT INTO scopes(partition,id,data,cursor,finance_policy,finance_complete) VALUES(?,?,?,1,?,1)',
        [
          profile.partition,
          scope,
          jsonEncode(
            const SharedScope(
              id: scope,
              name: 'Private',
              kind: SharedScopeKind.personal,
              role: SharedRole.owner,
            ).toJson(),
          ),
          jsonEncode({'enabled': true, 'grant': 'write', 'revision': 1}),
        ],
      );
      final binding = <String, dynamic>{
        'id': 'private:${profile.partition}',
        'partition': profile.partition,
        'scope_id': scope,
      };
      await db.execute(
        'INSERT INTO personal_workspaces(id,partition,scope_id,enabled) VALUES(?,?,?,1)',
        [binding['id'], profile.partition, scope],
      );
      db.activatePersonal(profile);
      await db.transaction(() async {
        await queuePrivateRecord(
          db,
          binding,
          'private-bank',
          'financeAccount',
          account('private-bank').toJson(),
        );
      });
      final repo = OrganizerRepository(storage, clock: () => now);
      await repo.initialize();
      final before = await db.rows('SELECT op_id FROM finance_outbox');
      await repo.createFinanceEntry(
        title: 'Local',
        amountMinor: 2500,
        kind: FinanceEntryKind.expense,
        occurredAt: now,
        ledgerAccountId: 'local-bank',
        expectedWorkspaceKey: repo.snapshot.workspaceKey,
      );
      expect(
        (await storage.localSnapshot()).financeEntries.single.title,
        'Local',
      );
      expect(await db.rows('SELECT op_id FROM finance_outbox'), before);
      final local = repo.snapshot.financeEntries.single;
      await expectLater(
        repo.updateFinanceEntry(
          local.copyWith(ledgerAccountId: 'private-bank'),
        ),
        throwsFormatException,
      );
      await repo.createFinanceEntry(
        title: 'Private',
        amountMinor: 500,
        kind: FinanceEntryKind.expense,
        occurredAt: now,
        ledgerAccountId: 'private-bank',
        expectedWorkspaceKey: repo.snapshot.workspaceKey,
      );
      expect(
        (await db.rows('SELECT op_id FROM finance_outbox')).length,
        before.length + 1,
      );
      final private = repo.snapshot.financeEntries.firstWhere(
        (e) => e.title == 'Private',
      );
      await expectLater(
        repo.updateFinanceEntry(
          private.copyWith(ledgerAccountId: 'local-bank'),
        ),
        throwsFormatException,
      );
      await db.execute(
        'UPDATE scopes SET finance_policy=?,finance_complete=0 WHERE partition=? AND id=?',
        [
          jsonEncode({'enabled': true, 'grant': 'none', 'revision': 2}),
          profile.partition,
          scope,
        ],
      );
      await repo.reload();
      await repo.createFinanceEntry(
        title: 'Local while denied',
        amountMinor: 100,
        kind: FinanceEntryKind.expense,
        occurredAt: now,
        ledgerAccountId: 'local-bank',
        expectedWorkspaceKey: repo.snapshot.workspaceKey,
      );
      expect((await storage.localSnapshot()).financeEntries.length, 2);
      final origin = repo.snapshot.workspaceKey;
      db.activatePersonal(null);
      await expectLater(
        repo.createFinanceEntry(
          title: 'Late response',
          amountMinor: 200,
          kind: FinanceEntryKind.expense,
          occurredAt: now,
          ledgerAccountId: 'local-bank',
          expectedWorkspaceKey: origin,
        ),
        throwsA(isA<OrganizerConflictException>()),
      );
      expect((await storage.localSnapshot()).financeEntries.length, 2);
      await repo.close();
      await db.close();
    },
  );
}
