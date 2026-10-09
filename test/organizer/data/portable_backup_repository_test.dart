import 'dart:convert';
import 'dart:async';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/data/organizer_repository.dart';
import 'package:kanban/organizer/data/portable_backup_repository.dart';
import 'package:kanban/organizer/data/portable_backup_crypto.dart';
import 'package:kanban/organizer/data/sqlite_organizer_storage.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'collaboration_repository_test.dart' show FakeServer, MemorySessionStore;
import 'private_sync_test_support.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  const password = 'a long backup password';
  Future<
    ({
      CollaborationDatabase db,
      SqliteOrganizerStorage storage,
      OrganizerRepository personal,
      CollaborationRepository shared,
      PortableBackupRepository backup,
    })
  >
  client(PersonalTransport transport) async {
    final db = CollaborationDatabase(NativeDatabase.memory());
    final local = SqliteOrganizerStorage(db);
    await local.initialize();
    final personal = OrganizerRepository(local);
    await personal.initialize();
    final shared = CollaborationRepository(
      db,
      transport,
      MemorySessionStore(),
      ownsDatabase: false,
    );
    await shared.initialize();
    final backup = PortableBackupRepository(
      db,
      local,
      MemoryBackupUiPreferencesStore(),
      collaboration: () => shared,
    );
    addTearDown(() async {
      await personal.close();
      await shared.close();
      await db.close();
    });
    return (
      db: db,
      storage: local,
      personal: personal,
      shared: shared,
      backup: backup,
    );
  }

  test(
    'authenticated crypto wrong password/tamper, bounded KDF header and asynchronous event-loop progress',
    () async {
      final crypto = PortableBackupCrypto();
      var ticks = 0;
      final timer = Timer.periodic(
        const Duration(milliseconds: 2),
        (_) => ticks++,
      );
      final bytes = await crypto.encrypt({'test': 'no credentials'}, password);
      timer.cancel();
      expect(ticks, greaterThan(0));
      expect((await crypto.decrypt(bytes, password))['test'], 'no credentials');
      await expectLater(
        crypto.decrypt(bytes, 'wrong long password'),
        throwsA(
          isA<CollaborationException>().having(
            (e) => e.code,
            'code',
            'backup_auth_failed',
          ),
        ),
      );
      final tampered = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      final ciphertext = base64Decode(tampered['ciphertext'] as String);
      ciphertext[0] ^= 1;
      tampered['ciphertext'] = base64Encode(ciphertext);
      await expectLater(
        crypto.decrypt(utf8.encode(jsonEncode(tampered)), password),
        throwsA(
          isA<CollaborationException>().having(
            (e) => e.code,
            'code',
            'backup_auth_failed',
          ),
        ),
      );
      tampered['iterations'] = 2147483647;
      await expectLater(
        crypto.decrypt(utf8.encode(jsonEncode(tampered)), password),
        throwsA(
          isA<CollaborationException>().having(
            (e) => e.code,
            'code',
            'backup_unsupported',
          ),
        ),
      );
    },
  );
  test(
    'restore rollback on SQL failure, stale review, merge collision and restart-safe encrypted recovery; no upload into B',
    () async {
      final transport = PersonalTransport(FakeServer()),
          a = await client(transport),
          b = await client(transport);
      await a.personal.createTask(title: 'Local backup task');
      await a.personal.createFinanceEntry(
        title: 'Private expense',
        amountMinor: 100,
        currency: 'EUR',
        kind: FinanceEntryKind.expense,
        occurredAt: DateTime.utc(2026),
      );
      final bytes = await a.backup.exportEncryptedBackup(password),
          preview = await a.backup.inspectEncryptedBackup(bytes, password);
      await a.backup.validatePreparedExport(preview.backupId);
      await b.shared.login(
        serverUrl: 'https://test.invalid',
        username: 'bob',
        password: 'test',
      );
      await b.personal.reload();
      await b.shared.enablePrivateSync(
        expectedRevision: (await b.shared.previewPrivateSync()).revision,
      );
      await b.personal.reload();
      final revision = (await b.storage.read()).revision;
      await b.db.execute(
        "CREATE TRIGGER fail_restore BEFORE INSERT ON personal_records BEGIN SELECT RAISE(ABORT,'test failure'); END",
      );
      await expectLater(
        b.backup.restoreEncryptedBackup(
          bytes,
          password,
          mode: BackupRestoreMode.replace,
          expectedPersonalRevision: revision,
        ),
        throwsA(anything),
      );
      expect((await b.storage.localSnapshot()).tasks, isEmpty);
      expect(await b.db.rows('SELECT * FROM restored_backups'), isEmpty);
      await b.db.execute('DROP TRIGGER fail_restore');
      await b.backup.restoreEncryptedBackup(
        bytes,
        password,
        mode: BackupRestoreMode.replace,
        expectedPersonalRevision: revision,
      );
      await b.personal.reload();
      expect(
        (await b.storage.localSnapshot()).financeEntries.single.amountMinor,
        100,
      );
      expect(await b.db.rows('SELECT * FROM finance_outbox'), isEmpty);
      expect(await b.db.rows('SELECT * FROM outbox'), isEmpty);
      final reopened = PortableBackupRepository(
        b.db,
        b.storage,
        MemoryBackupUiPreferencesStore(),
        collaboration: () => b.shared,
      );
      expect(
        (await reopened.listRestoredBackups()).single.backupId,
        preview.backupId,
      );
      await expectLater(
        reopened.restoreEncryptedBackup(
          bytes,
          password,
          mode: BackupRestoreMode.merge,
          expectedPersonalRevision: revision,
        ),
        throwsA(
          isA<CollaborationException>().having(
            (e) => e.code,
            'code',
            'backup_stale',
          ),
        ),
      );
      await expectLater(
        reopened.restoreEncryptedBackup(
          bytes,
          password,
          mode: BackupRestoreMode.merge,
          expectedPersonalRevision: (await b.storage.read()).revision,
        ),
        throwsA(
          isA<CollaborationException>().having(
            (e) => e.code,
            'code',
            'backup_conflict',
          ),
        ),
      );
    },
  );
  test(
    'private backup original ID maps/reminder history + lost-ACK finance replay restore without double expense or local publish',
    () async {
      final transport = PersonalTransport(FakeServer()),
          a = await client(transport);
      await a.personal.createTask(title: 'Due', dueAt: DateTime.utc(2020));
      await a.personal.createFinanceEntry(
        title: 'Exact expense',
        amountMinor: 125,
        currency: 'EUR',
        kind: FinanceEntryKind.expense,
        occurredAt: DateTime.utc(2026),
      );
      await a.shared.login(
        serverUrl: 'https://test.invalid',
        username: 'alice',
        password: 'test',
      );
      await a.personal.reload();
      await a.shared.enablePrivateSync(
        expectedRevision: (await a.shared.previewPrivateSync()).revision,
      );
      await a.personal.reload();
      transport.offline = true;
      await a.personal.updateFinanceEntry(
        a.personal.snapshot.financeEntries.single.copyWith(amountMinor: 275),
      );
      final bytes = await a.backup.exportEncryptedBackup(password),
          preview = await a.backup.inspectEncryptedBackup(bytes, password);
      transport.offline = false;
      await a.shared.syncNow();
      expect(transport.finances.records.values.single.length, 1);
      final b = await client(transport);
      await b.personal.createProject(title: 'Remain anonymous');
      await b.shared.login(
        serverUrl: 'https://test.invalid',
        username: 'alice',
        password: 'test',
      );
      await b.personal.reload();
      await b.backup.restoreEncryptedBackup(
        bytes,
        password,
        mode: BackupRestoreMode.merge,
        expectedPersonalRevision: (await b.storage.read()).revision,
      );
      await b.backup.resumeRestoredWork(preview.backupId, password: password);
      await b.personal.reload();
      expect(transport.finances.records.values.single.length, 1);
      expect(b.personal.snapshot.financeEntries.single.amountMinor, 275);
      expect(b.personal.snapshot.reminders.length, 1);
      expect(
        (await b.storage.localSnapshot()).projects.single.title,
        'Remain anonymous',
      );
      expect(
        transport.server.records.values.single.values.any(
          (r) => (r['payload'] as Map?)?['title'] == 'Remain anonymous',
        ),
        false,
      );
      expect(await b.db.rows('SELECT * FROM finance_outbox'), isEmpty);
      final generic = await b.backup.reviewRestoredWork(
        preview.backupId,
        password,
      );
      expect(generic.canResume, true);
      expect(generic.items.any((i) => i.isFinancial), true);
      await b.db.execute(
        'UPDATE scopes SET finance_policy=?,finance_blocked=1 WHERE partition=?',
        [
          jsonEncode(const SharedFinancePolicy().toJson()),
          b.shared.state.session!.partition,
        ],
      );
      final denied = await b.backup.reviewRestoredWork(
        preview.backupId,
        password,
      );
      expect(denied.items.any((i) => i.isFinancial), false);
      await expectLater(
        b.backup.validatePreparedExport(preview.backupId),
        throwsA(isA<CollaborationException>()),
      );
    },
  );
  test(
    'prepared export survives routine sync and sequence changes; known rights revoke invalidates release',
    () async {
      final transport = PersonalTransport(FakeServer()),
          a = await client(transport);
      await a.shared.login(
        serverUrl: 'https://test.invalid',
        username: 'alice',
        password: 'test',
      );
      await a.shared.createScope('Shared');
      await a.shared.syncNow();
      final bytes = await a.backup.exportEncryptedBackup(password),
          preview = await a.backup.inspectEncryptedBackup(bytes, password);
      await a.shared.syncNow();
      await a.backup.validatePreparedExport(preview.backupId);
      final scope = a.shared.state.scopes.single.id;
      transport.server.scopes[scope]!['sequence'] = 123;
      await a.shared.syncNow();
      await a.backup.validatePreparedExport(preview.backupId);
      transport.server.confirmRevocation(scope, 'alice');
      await a.shared.syncNow();
      await expectLater(
        a.backup.validatePreparedExport(preview.backupId),
        throwsA(
          isA<CollaborationException>().having(
            (e) => e.code,
            'code',
            'backup_stale',
          ),
        ),
      );
    },
  );
}
