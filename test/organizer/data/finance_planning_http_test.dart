// Explicit isolated loopback fixture; credentials and bodies never go in logs.
import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/data/organizer_repository.dart';
import 'package:kanban/organizer/data/sqlite_organizer_storage.dart';
import 'package:kanban/organizer/data/portable_backup_repository.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart'
    show BackupRestoreMode;
import 'collaboration_repository_test.dart' show MemorySessionStore;
import 'family_upgrade_http_test.dart' show ControlledHttp;

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final fixturePath = Platform.environment['JIVIE_FINANCE_HTTP_FIXTURE'];
  test(
    'real HTTP many monthly rules preserve finance2 fields, exact one occurrence, actual confirmation retry and backup',
    () async {
      final fixture =
          jsonDecode(await File(fixturePath!).readAsString())
              as Map<String, dynamic>;
      final server = fixture['server'] as String;
      if (fixture['synthetic'] != true ||
          Uri.parse(server).host != '127.0.0.1') {
        throw StateError('Synthetic loopback fixture required');
      }
      final directory = await Directory.systemTemp.createTemp(
        'jivie-finance-http-',
      );
      addTearDown(() => directory.delete(recursive: true));
      Future<
        ({
          CollaborationDatabase db,
          CollaborationRepository shared,
          OrganizerRepository personal,
          SqliteOrganizerStorage storage,
          ControlledHttp http,
        })
      >
      client(String name) async {
        final db = CollaborationDatabase(
          NativeDatabase(File('${directory.path}/$name.sqlite')),
        );
        final storage = SqliteOrganizerStorage(db);
        await storage.initialize();
        final personal = OrganizerRepository(storage);
        await personal.initialize();
        final http = ControlledHttp();
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
          serverUrl: server,
          username: fixture['username'],
          password: fixture['password'],
          allowLocalHttp: true,
          deviceName: name,
        );
        expect(shared.state.privateSync.enabled, false);
        await shared.enablePrivateSync(
          expectedRevision: (await storage.read()).revision,
        );
        await personal.reload();
        return (
          db: db,
          shared: shared,
          personal: personal,
          storage: storage,
          http: http,
        );
      }

      final a = await client('a');
      final now = DateTime.now().toUtc();
      final account = LocalFinanceAccount(
        id: newLocalId(),
        name: 'Synthetic named ledger',
        currency: 'EUR',
        openingBalanceMinor: 200000,
        openingBalanceAt: DateTime(now.year, now.month, 1).toUtc(),
        createdAt: now,
        updatedAt: now,
      );
      final rules = [
        for (var i = 0; i < 48; i++)
          FinanceRecurrenceRule(
            id: newLocalId(),
            title: 'Synthetic monthly item $i',
            kind: FinanceRecurrenceKind
                .values[i % FinanceRecurrenceKind.values.length],
            ledgerAccountId: account.id,
            currency: 'EUR',
            estimatedAmountMinor: 10000 + i,
            loanPrincipalMinor: i % 5 == 2 ? 1000000 : null,
            startYear: now.toLocal().year,
            startMonth: now.toLocal().month,
            monthDay: i % 31 + 1,
            createdAt: now,
            updatedAt: now,
          ),
      ];
      await a.personal.saveFinancePlan(
        accounts: [account],
        rules: rules,
        expectedRevision: a.personal.snapshot.revision,
        expectedWorkspaceKey: a.personal.snapshot.workspaceKey,
      );
      expect(a.personal.snapshot.financeEntries, hasLength(576));
      await a.shared.syncNow();
      expect(a.shared.state.lastError, null);
      expect(a.shared.state.financeConflicts, isEmpty);
      expect(a.shared.state.financePendingCount, 0);
      await a.personal.reload();
      expect(a.personal.snapshot.financeRecurrenceRules, hasLength(48));
      expect(
        a.personal.snapshot.financeAccounts.single.openingBalanceMinor,
        200000,
      );
      final b = await client('b');
      expect(b.personal.snapshot.financeEntries, hasLength(576));
      expect(b.personal.snapshot.financeRecurrenceRules, hasLength(48));
      final pairs = b.personal.snapshot.financeEntries
          .map((e) => '${e.recurrenceRuleId}:${e.occurrenceKey}')
          .toSet();
      expect(pairs, hasLength(576));
      await b.personal.materializeFinanceOccurrences(
        expectedWorkspaceKey: b.personal.snapshot.workspaceKey,
      );
      expect(b.personal.snapshot.financeEntries, hasLength(576));
      await b.shared.syncNow();
      expect(b.shared.state.financePendingCount, 0);
      final selected = a.personal.snapshot.financeEntries.first;
      await a.personal.confirmFinanceOccurrence(
        entry: selected,
        amountMinor: selected.amountMinor + 321,
        paidAt: now,
        expectedWorkspaceKey: a.personal.snapshot.workspaceKey,
      );
      a.http.loseReply = 'finance2.push';
      await a.shared.syncNow();
      expect(a.shared.state.financePendingCount, greaterThan(0));
      await a.shared.syncNow();
      expect(a.shared.state.lastError, null);
      expect(a.shared.state.financePendingCount, 0);
      await b.shared.syncNow();
      await b.personal.reload();
      final posted = b.personal.snapshot.financeEntries.singleWhere(
        (e) => e.id == selected.id,
      );
      expect(posted.status, FinanceEntryStatus.posted);
      expect(posted.paidAt, now);
      expect(posted.amountMinor, selected.amountMinor + 321);
      expect(b.personal.snapshot.financeEntries, hasLength(576));
      final backup = PortableBackupRepository(
        a.db,
        a.storage,
        MemoryBackupUiPreferencesStore(),
        collaboration: () => a.shared,
      );
      final bytes = await backup.exportEncryptedBackup(
        'synthetic long backup password',
      );
      final fresh = CollaborationDatabase(
        NativeDatabase(File('${directory.path}/restore.sqlite')),
      );
      final restoredStorage = SqliteOrganizerStorage(fresh);
      await restoredStorage.initialize();
      addTearDown(() async {
        await restoredStorage.close();
        await fresh.close();
      });
      final restore = PortableBackupRepository(
        fresh,
        restoredStorage,
        MemoryBackupUiPreferencesStore(),
      );
      final result = await restore.restoreEncryptedBackup(
        bytes,
        'synthetic long backup password',
        mode: BackupRestoreMode.merge,
        expectedPersonalRevision: (await restoredStorage.read()).revision,
      );
      expect(result.hasRemoteRecovery, true);
      expect((await restoredStorage.read()).financeEntries, isEmpty);
      expect(await restore.listRestoredBackups(), hasLength(1));
    },
    skip: fixturePath == null,
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
